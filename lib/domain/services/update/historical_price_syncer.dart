import 'dart:convert';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/price_repository.dart';

/// 歷史價格資料同步器
///
/// 負責確保分析所需的歷史價格資料完整。兩段式：
/// - **Phase 0 市場日快照回補**：偵測 lookback 窗內「整個市場缺資料」的
///   交易日，逐日以 1 次 API 呼叫回補該市場全部股票（TWSE MI_INDEX /
///   TPEx afterTrading 歷史端點）。非自選股不再受 per-symbol 早退門檻
///   （180 天）餓死——52 週規則需要 250 天。
/// - **Phase 1 per-symbol 回補**：FinMind 逐檔逐月，處理個股殘缺
///   （新上市、恢復交易等 phase 0 覆蓋不到的情境）。
class HistoricalPriceSyncer {
  const HistoricalPriceSyncer({
    required AppDatabase database,
    required PriceRepository priceRepository,
    this.marketDayCallDelay = const Duration(
      milliseconds: ApiConfig.priceRequestDelayMs,
    ),
  }) : _db = database,
       _priceRepo = priceRepository;

  final AppDatabase _db;
  final PriceRepository _priceRepo;

  /// 市場日快照回補的呼叫間隔（測試注入 [Duration.zero]）
  final Duration marketDayCallDelay;

  /// 同步歷史價格資料
  ///
  /// 確保分析所需的股票有足夠的歷史資料（52 週）
  /// 整合：自選清單 + 熱門股 + 市場候選股 + 既有資料股票
  Future<HistoricalPriceSyncResult> syncHistoricalPrices({
    required DateTime date,
    required List<String> watchlistSymbols,
    required List<String> popularStocks,
    required List<String> marketCandidates,
    void Function(String message)? onProgress,
  }) async {
    // 分段計時（debug log）：各段耗時歸因。2026-07-15 in-app 實測曾為
    // phase0=1407ms（~540 次逐日 COUNT 的 isolate roundtrip，離線 harness
    // 直連僅 56ms——低估了 isolate 開銷）、覆蓋載入前身整包載入=3010ms；
    // 兩者已分別以 getPriceCountsByDayAndMarket / getPriceCoverageBatch
    // 聚合化。留計時供回歸監控。
    final phaseTimer = Stopwatch()..start();

    // Phase 0：市場日快照回補（整市場缺漏日，1 呼叫補全市場一天）
    final marketDayRows = await _syncMissingMarketDays(
      date: date,
      onProgress: onProgress,
    );
    final phase0Ms = phaseTimer.elapsedMilliseconds;

    // Phase 1：整合所有歷史資料來源
    phaseTimer.reset();
    final historyLookbackStart = date.subtract(
      const Duration(days: RuleParams.swingWindow + 20),
    );
    final existingDataSymbols = await _db.getSymbolsWithSufficientData(
      minDays: RuleParams.swingWindow,
      startDate: historyLookbackStart,
      endDate: date,
    );
    final existingScanMs = phaseTimer.elapsedMilliseconds;

    final symbolsForHistory = <String>{
      ...watchlistSymbols,
      ...popularStocks,
      ...marketCandidates,
      ...existingDataSymbols,
    }.toList();

    final historyStartDate = date.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    );

    // 檢查哪些股票需要歷史資料（聚合摘要，不物件化完整價格列——
    // 舊整包載入 in-app 實測 3.0 秒 / ~59 萬列跨 isolate）
    phaseTimer.reset();
    final coverageBatch = await _db.getPriceCoverageBatch(
      symbolsForHistory,
      startDate: historyStartDate,
      endDate: date,
    );
    final bulkLoadMs = phaseTimer.elapsedMilliseconds;
    phaseTimer.reset();

    // 自選 + 熱門 = priority locked。它們不適用 lenient nearThreshold
    // 早退門檻（180 天）— 因 52w high/low rule 嚴格要求 250 天，priority
    // 股需要追到 250 才算「夠」。否則 popular 大型權值股（2330/2317/2454）
    // 會卡在 220-240 天區間永遠不被同步，52w rule 永久無法觸發。
    final priorityLocked = <String>{...watchlistSymbols, ...popularStocks};

    final backoff = await _loadBackoff();
    final symbolsNeedingData = _findSymbolsNeedingData(
      symbolsForHistory,
      coverageBatch,
      date,
      priorityLocked: priorityLocked,
      backoff: backoff,
    );
    final scanMs = phaseTimer.elapsedMilliseconds;
    AppLogger.debug(
      'HistoricalPriceSyncer',
      '分段計時: phase0=${phase0Ms}ms 既有資料掃描=${existingScanMs}ms '
          '覆蓋載入=${bulkLoadMs}ms 需求掃描=${scanMs}ms',
    );

    if (symbolsNeedingData.isEmpty) {
      onProgress?.call('歷史資料已完整');
      return HistoricalPriceSyncResult(
        syncedCount: 0,
        symbolsProcessed: 0,
        marketDayRows: marketDayRows,
      );
    }

    _logSyncDiagnostics(symbolsNeedingData, coverageBatch);

    // 估算每檔平均需要的 API 呼叫數（上櫃整段 1 次，見方法註解）。
    // 查不到市場的 symbol 不進這個集合 → 按上市（逐月）保守計價。
    final marketsBatch = await _db.getMarketsForSymbolsBatch(
      symbolsNeedingData,
    );
    final otcSymbols = <String>{
      for (final e in marketsBatch.entries)
        if (e.value == MarketCode.tpex) e.key,
    };
    final avgMonthsPerSymbol = _estimateAvgMonthsNeeded(
      symbolsNeedingData,
      coverageBatch,
      historyStartDate: historyStartDate,
      endDate: date,
      otcSymbols: otcSymbols,
    );

    final limitedSymbols = await _prioritizeSymbols(
      symbolsNeedingData,
      watchlistSymbols: watchlistSymbols,
      popularStocks: popularStocks,
      avgMonthsPerSymbol: avgMonthsPerSymbol,
    );

    final batchResult = await _performBatchSync(
      limitedSymbols,
      historyStartDate: historyStartDate,
      endDate: date,
      totalNeeded: symbolsNeedingData.length,
      onProgress: onProgress,
    );
    await _updateBackoff(
      backoff,
      succeeded: batchResult.succeededSymbols,
      preCoverage: coverageBatch,
      historyStartDate: historyStartDate,
      date: date,
    );
    return HistoricalPriceSyncResult(
      syncedCount: batchResult.syncedCount,
      symbolsProcessed: batchResult.symbolsProcessed,
      totalSymbolsNeeded: batchResult.totalSymbolsNeeded,
      failedSymbols: batchResult.failedSymbols,
      succeededSymbols: batchResult.succeededSymbols,
      marketDayRows: marketDayRows,
      rateLimitError: batchResult.rateLimitError,
    );
  }

  /// Phase 0：市場日快照回補
  ///
  /// 掃描 `[date - historyRequiredDays, date - 1]` 窗內每個交易日
  /// （[TaiwanCalendar]，新→舊），該日該市場筆數 < 市場股數 ×
  /// [ApiConfig.historicalMarketDayMinCoverageRatio] 即視為缺漏，
  /// 以 [PriceRepository.backfillTwsePricesByDate] /
  /// [PriceRepository.backfillTpexPricesByDate] 一次補齊該市場一天。
  ///
  /// 防護：
  /// - 單次上限 [ApiConfig.historicalMarketDayMaxCallsPerRun]
  /// - 連續零筆 [ApiConfig.historicalMarketDayMaxConsecutiveZeroDays]
  ///   中止（端點失效 / 日曆未知休市）
  /// - RateLimit / Network 中止 phase 0 但不外拋——phase 1 走 FinMind，
  ///   不同 API 來源不受牽連
  /// - 股票主檔為空（fresh DB 首次更新，尚未同步股票清單）→ 跳過
  ///
  /// 回傳實際寫入的價格列數。
  Future<int> _syncMissingMarketDays({
    required DateTime date,
    void Function(String message)? onProgress,
  }) async {
    // 各市場目標股票集合與缺漏門檻
    final targets = <String, Set<String>>{};
    final thresholds = <String, int>{};
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      final stocks = await _db.getStocksByMarket(market);
      if (stocks.isEmpty) continue;
      targets[market] = stocks.map((s) => s.symbol).toSet();
      thresholds[market] =
          (stocks.length * ApiConfig.historicalMarketDayMinCoverageRatio)
              .ceil();
    }
    if (targets.isEmpty) return 0;

    // 掃描缺漏（日, 市場），今日不含（由每日同步負責），新→舊。
    // 覆蓋筆數以一次 GROUP BY 預先取回（原逐 (日,市場) COUNT ~540 次
    // 在 app 的 isolate 連線累積 ~1.4 秒）；掃描讀的是回補前的快照，
    // 與原逐日查詢語意一致（tasks 本就先建完才執行）。
    final endDay = DateTime(date.year, date.month, date.day);
    final windowStart = endDay.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    );
    final dayCounts = await _db.getPriceCountsByDayAndMarket(
      startDate: windowStart,
      endDate: endDay,
    );
    final tasks = <(DateTime, String)>[];
    for (
      var day = endDay.subtract(const Duration(days: 1));
      !day.isBefore(windowStart) &&
          tasks.length < ApiConfig.historicalMarketDayMaxCallsPerRun;
      day = day.subtract(const Duration(days: 1))
    ) {
      if (!TaiwanCalendar.isTradingDay(day)) continue;
      final dayKey = DateContext.formatYmd(day);
      for (final market in targets.keys) {
        if (tasks.length >= ApiConfig.historicalMarketDayMaxCallsPerRun) {
          break;
        }
        final count = dayCounts[market]?[dayKey] ?? 0;
        if (count < thresholds[market]!) tasks.add((day, market));
      }
    }
    if (tasks.isEmpty) return 0;

    AppLogger.info(
      'HistoricalPriceSyncer',
      '市場日快照回補: ${tasks.length} 個(日,市場)缺漏，開始逐日回補',
    );

    var totalRows = 0;
    var consecutiveZero = 0;
    var processed = 0;
    for (final (day, market) in tasks) {
      if (processed > 0) await Future.delayed(marketDayCallDelay);
      processed++;
      onProgress?.call('市場日回補 ($processed/${tasks.length})');
      try {
        final added = market == MarketCode.twse
            ? await _priceRepo.backfillTwsePricesByDate(
                date: day,
                targetSymbols: targets[market]!,
              )
            : await _priceRepo.backfillTpexPricesByDate(
                date: day,
                targetSymbols: targets[market]!,
              );
        if (added > 0) {
          totalRows += added;
          consecutiveZero = 0;
        } else {
          consecutiveZero++;
        }
      } on RateLimitException {
        AppLogger.warning(
          'HistoricalPriceSyncer',
          '市場日回補 API 限流，中止 phase 0（phase 1 照常）',
        );
        break;
      } on NetworkException {
        AppLogger.warning(
          'HistoricalPriceSyncer',
          '市場日回補網路異常，中止 phase 0（phase 1 照常）',
        );
        break;
      } on Exception catch (e) {
        // 單日失敗（如 DatabaseException）：計入零筆 streak 後續行，
        // 連續失敗同樣觸發中止
        consecutiveZero++;
        AppLogger.warning(
          'HistoricalPriceSyncer',
          '市場日回補失敗 $market ${day.year}-${day.month}-${day.day}: $e',
        );
      }
      if (consecutiveZero >=
          ApiConfig.historicalMarketDayMaxConsecutiveZeroDays) {
        AppLogger.warning(
          'HistoricalPriceSyncer',
          '市場日回補連續 $consecutiveZero 日零筆，推測端點異常，中止 phase 0',
        );
        break;
      }
    }

    AppLogger.info(
      'HistoricalPriceSyncer',
      '市場日快照回補完成: +$totalRows 列（$processed/${tasks.length} 日）',
    );
    return totalRows;
  }

  /// 判斷哪些 symbol 需要補歷史資料
  ///
  /// [priorityLocked] 為自選 + 熱門股 union — 它們不適用 [nearThreshold]
  /// lenient 早退（180 天），必須追到 [minRequiredDays]（250 天）才算夠。
  /// 與下游 52w high/low rule 的硬性需求對齊；non-priority 股維持 180
  /// 早退避免無效追打。
  /// 讀退避表(壞 JSON 一律當空表,fail-open——退避只是省配額,不是正確性)
  Future<Map<String, DateTime>> _loadBackoff() async {
    final raw = await _db.getSetting(
      DataFreshness.historicalBackfillBackoffKey,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (DateTime.tryParse(e.value as String) != null)
            e.key: DateTime.parse(e.value as String),
      };
    } catch (_) {
      return {};
    }
  }

  /// 成功同步後的收斂記帳(回補收斂設計「陷阱 1 假進度」的對策):
  /// **進度=覆蓋筆數成長**,不是「有寫入列」——重寫既有列也會讓寫入數
  /// >0(8291 實錄:139 列重寫 124 列,連日「成功」但永不收斂)。
  /// 無成長 → 記退避日;有成長 → 清標記(自癒,不會永久封鎖)。
  Future<void> _updateBackoff(
    Map<String, DateTime> backoff, {
    required List<String> succeeded,
    required Map<String, PriceCoverage> preCoverage,
    required DateTime historyStartDate,
    required DateTime date,
  }) async {
    if (succeeded.isEmpty) return;
    final post = await _db.getPriceCoverageBatch(
      succeeded,
      startDate: historyStartDate,
      endDate: date,
    );
    var changed = false;
    for (final symbol in succeeded) {
      final pre = preCoverage[symbol]?.count ?? 0;
      final now = post[symbol]?.count ?? 0;
      if (now > pre) {
        if (backoff.remove(symbol) != null) changed = true;
      } else {
        backoff[symbol] = date;
        changed = true;
        AppLogger.debug(
          'HistoricalPriceSyncer',
          '$symbol: 抓取成功但覆蓋無成長($pre→$now),退避 '
              '${DataFreshness.historicalBackfillBackoffDays} 天',
        );
      }
    }
    if (changed) {
      await _db.setSetting(
        DataFreshness.historicalBackfillBackoffKey,
        jsonEncode({
          for (final e in backoff.entries)
            e.key: e.value.toIso8601String().substring(0, 10),
        }),
      );
    }
  }

  List<String> _findSymbolsNeedingData(
    List<String> symbols,
    Map<String, PriceCoverage> coverageBatch,
    DateTime date, {
    Set<String> priorityLocked = const {},
    Map<String, DateTime> backoff = const {},
  }) {
    final result = <String>[];
    var backoffSkipped = 0;
    // 退避期內跳過(期滿重試):見 _updateBackoff 與
    // DataFreshness.historicalBackfillBackoffDays 的設計說明
    bool inBackoff(String symbol) {
      final marked = backoff[symbol];
      if (marked == null) return false;
      return date.difference(marked).inDays <
          DataFreshness.historicalBackfillBackoffDays;
    }

    const minRequiredDays = IndicatorParams.week52Days;
    const nearThreshold = IndicatorParams.historyNearCompleteThreshold;

    for (final symbol in symbols) {
      final coverage = coverageBatch[symbol];
      final priceCount = coverage?.count ?? 0;

      if (priceCount >= minRequiredDays) continue;

      // Priority 股（watchlist + popular）的早退條件**只認嚴格 250 天**。
      // 對它們 skip nearThreshold + _hasEnoughDataForAge — 因下游 52w
      // high/low rule 嚴格要求 250 交易日，priority 股若卡在 200-240
      // 區間會永遠補不到，相關規則永久無法觸發（2026-06 production：
      // 2330/2317/2454 等 popular 全卡 221/250）。
      // Non-priority 股維持原本 lenient 早退避免無效追打。
      final isPriority = priorityLocked.contains(symbol);

      if (!isPriority && priceCount >= nearThreshold) continue;

      if (coverage == null || priceCount == 0) {
        if (inBackoff(symbol)) {
          backoffSkipped++;
        } else {
          result.add(symbol);
        }
        continue;
      }

      // 對已有資料的股票，檢查是否為近期上市且資料已足夠
      // 避免反覆向 TWSE 查詢不存在的歷史資料
      final daysSinceFirstTrade = date.difference(coverage.firstDate).inDays;

      // Fresh DB 場景：首筆資料是最近 3 天內（可能只從今日同步取得），
      // 且資料量極少 → 仍需補歷史
      // 例外：若首筆資料日期 > 今天 - 3 天，且最後一筆已是最新，
      // 且已有 > 1 天的歷史（代表曾同步過），視為新上市而非 fresh DB
      if (daysSinceFirstTrade <= 3 && priceCount < RuleParams.swingWindow) {
        final isUpToDate = date.difference(coverage.lastDate).inDays <= 1;
        final hasMultipleDays = priceCount > 1;
        if (isUpToDate && hasMultipleDays && daysSinceFirstTrade > 0) {
          // 新上市股票：有多天資料且已是最新，走 _hasEnoughDataForAge 判斷
        } else {
          if (inBackoff(symbol)) {
            backoffSkipped++;
          } else {
            result.add(symbol);
          }
          continue;
        }
      }

      // 其他情況：檢查資料量是否與上市時間相符
      // Priority 股 skip 此 ratio check — 它們追的是「is 250 enough」
      // 而非「is data-density acceptable for current age」。
      if (!isPriority && _hasEnoughDataForAge(coverage, date)) {
        continue;
      }

      if (inBackoff(symbol)) {
        backoffSkipped++;
      } else {
        result.add(symbol);
      }
    }

    if (backoffSkipped > 0) {
      AppLogger.info(
        'HistoricalPriceSyncer',
        '回補退避跳過 $backoffSkipped 檔(覆蓋無成長,'
            '${DataFreshness.historicalBackfillBackoffDays} 天後重試)',
      );
    }
    return result;
  }

  /// 檢查股票的資料量是否與其上市時間相符
  ///
  /// 避免反覆同步數據源無法提供更多資料的股票
  bool _hasEnoughDataForAge(PriceCoverage coverage, DateTime date) {
    final priceCount = coverage.count;
    final daysSinceFirstTrade = date.difference(coverage.firstDate).inDays;

    // 今天才上市（daysSinceFirstTrade == 0），有任何資料就算足夠
    if (daysSinceFirstTrade <= 0) return priceCount > 0;

    // 約 71% 的日曆天是交易日
    final expectedTradingDays =
        (daysSinceFirstTrade * DataFreshness.tradingDayRatio).round().clamp(
          1,
          daysSinceFirstTrade,
        );

    // 只要資料達到預期的 50% 就視為足夠
    final minAcceptableDays =
        (expectedTradingDays * DataFreshness.minAcceptableDataRatio).round();
    return priceCount >= minAcceptableDays;
  }

  /// 記錄需要同步的股票診斷資訊
  void _logSyncDiagnostics(
    List<String> symbolsNeedingData,
    Map<String, PriceCoverage> priceHistoryBatch,
  ) {
    if (symbolsNeedingData.length <= 10) {
      final details = symbolsNeedingData
          .map((symbol) {
            final coverage = priceHistoryBatch[symbol];
            final priceCount = coverage?.count ?? 0;
            final firstDate = coverage != null
                ? '${coverage.firstDate.month}/${coverage.firstDate.day}'
                : 'N/A';
            return '$symbol($priceCount 天,起:$firstDate)';
          })
          .join(', ');
      AppLogger.info('HistoricalPriceSyncer', '需要歷史資料: $details');
    } else {
      AppLogger.info(
        'HistoricalPriceSyncer',
        '需要歷史資料的股票: ${symbolsNeedingData.length} 檔',
      );
    }
  }

  /// 估算每檔股票平均需要的月度 API 呼叫數
  ///
  /// 鏡像 [PriceRepository.syncStockPrices] 第 134–161 行的月份迭代邏輯：
  ///   1. 對 `[historyStartDate, endDate]` 視窗內每個月份，
  ///   2. 跳過上市前的月份（cached ≥ 60 天時才信 firstKnownDate 作上市日代理），
  ///   3. 凡 cached days < [DataFreshness.minTradingDaysPerMonth] 的月份就計入。
  ///
  /// 早期版本對所有非零 symbol 一律假設 4 個月（[historicalPartialSyncMonths]，
  /// 已移除）。但實際 API 呼叫數取決於 cached 資料如何分佈於月份桶 — 若 222
  /// 天散落在 9 個月，缺口可能是 6 個月而非 4。低估會讓 maxSyncCount 估高，
  /// 超出真實 API budget 觸發限流（2026-06 production 案例：估 75 檔 × 4 月
  /// = 300 calls 預算，實打 75 × ~15 月 = 1125，跑到 16 檔就被擋）。
  /// 估算每檔平均需要的 API 呼叫數（單位沿用「月」，上市 1 月 = 1 次呼叫）
  ///
  /// **上櫃整段只要 1 次呼叫**：`PriceRepository.syncStockPrices` 依市場分流，
  /// 上櫃走 `_tpexSource.fetchSingleStockPrices(startDate, endDate)` 一次取回
  /// 整個區間，上市才是 `_twseSource.fetchMonthlyPrices(months: ...)` 逐月。
  /// 不分市場一律按月計價會把上櫃高估 monthsNeeded 倍——2026-07-27 正式日誌
  /// 實測 8291 尚茂（TPEx）估 8.0 個月、實際 `TaiwanStockPrice(8291): 138 筆`
  /// 只有 1 次呼叫；fresh DB（avgMonths≈14）時高估可達 14 倍。
  ///
  /// [otcSymbols] 未包含的 symbol **一律按上市（逐月）計價**。估錯方向不對稱：
  /// 高估只是回補變慢，低估會讓 `maxSyncCount` 放大到打爆 FinMind 的 600/hr。
  double _estimateAvgMonthsNeeded(
    List<String> symbols,
    Map<String, PriceCoverage> coverageBatch, {
    required DateTime historyStartDate,
    required DateTime endDate,
    required Set<String> otcSymbols,
  }) {
    if (symbols.isEmpty) return 1;

    // 預先計算視窗內月份清單（與 PriceRepository 的 while 迴圈邊界一致）
    final windowMonths = <(int, int)>[];
    var cur = DateTime(historyStartDate.year, historyStartDate.month, 1);
    final windowEnd = DateTime(endDate.year, endDate.month, 1);
    while (!cur.isAfter(windowEnd)) {
      windowMonths.add((cur.year, cur.month));
      cur = DateTime(cur.year, cur.month + 1, 1);
    }
    final totalWindowMonths = windowMonths.length;

    var totalMonthsNeeded = 0;
    for (final symbol in symbols) {
      // 上櫃：整段 1 次呼叫，與缺多少個月無關
      if (otcSymbols.contains(symbol)) {
        totalMonthsNeeded += 1;
        continue;
      }

      final coverage = coverageBatch[symbol];
      if (coverage == null || coverage.count == 0) {
        // 無資料：整個視窗都需抓取
        totalMonthsNeeded += totalWindowMonths;
        continue;
      }

      // (year, month) → 天數分佈由 aggregate 直接提供
      // （與 PriceRepository 第 128–132 行的 group-by 對齊）
      final daysByMonth = coverage.daysByMonth;

      // 鏡像 firstKnownDate 上市日邏輯（≥ 60 天才信任）
      // PriceRepository.syncStockPrices line 121–125
      final firstKnownDate = coverage.count >= 60 ? coverage.firstDate : null;
      final firstKnownMonth = firstKnownDate != null
          ? (firstKnownDate.year, firstKnownDate.month)
          : null;

      var monthsNeeded = 0;
      for (final month in windowMonths) {
        // 跳過上市前月份
        if (firstKnownMonth != null) {
          final (fy, fm) = firstKnownMonth;
          final (my, mm) = month;
          if (my < fy || (my == fy && mm < fm)) continue;
        }
        final days = daysByMonth[month] ?? 0;
        if (days < DataFreshness.minTradingDaysPerMonth) {
          monthsNeeded++;
        }
      }
      totalMonthsNeeded += monthsNeeded;
    }

    return totalMonthsNeeded / symbols.length;
  }

  /// 依重要性排序並限制同步數量
  ///
  /// 優先順序：自選 > 熱門 > 其他
  /// 確保 TWSE 和 TPEX 都按比例分配到名額
  ///
  /// [avgMonthsPerSymbol] 越大代表每檔需要越多 API 呼叫，
  /// 動態降低同步數量避免觸發限流。
  Future<List<String>> _prioritizeSymbols(
    List<String> symbolsNeedingData, {
    required List<String> watchlistSymbols,
    required List<String> popularStocks,
    required double avgMonthsPerSymbol,
  }) async {
    // 以月度 API 呼叫預算計算動態上限
    // 正常日（avgMonths ≈ 1）→ 200 檔
    // Fresh DB（avgMonths ≈ 14）→ ~21 檔
    final maxSyncCount =
        (ApiConfig.historicalPriceMaxMonthlyApiCalls / avgMonthsPerSymbol)
            .ceil()
            .clamp(
              ApiConfig.historicalPriceMinSyncCount,
              ApiConfig.historicalPriceMaxSyncCount,
            );

    if (avgMonthsPerSymbol > 3) {
      AppLogger.info(
        'HistoricalPriceSyncer',
        '每檔平均需 ${avgMonthsPerSymbol.toStringAsFixed(1)} 個月 API 呼叫，'
            '動態限制為 $maxSyncCount 檔（API 預算 ${ApiConfig.historicalPriceMaxMonthlyApiCalls}）',
      );
    }

    if (symbolsNeedingData.length <= maxSyncCount) {
      return symbolsNeedingData;
    }

    final watchlistSet = watchlistSymbols.toSet();
    final popularSet = popularStocks.toSet();

    // 分成優先股（自選+熱門）和一般股
    final prioritySymbols = <String>[];
    final otherSymbols = <String>[];

    for (final symbol in symbolsNeedingData) {
      if (watchlistSet.contains(symbol) || popularSet.contains(symbol)) {
        prioritySymbols.add(symbol);
      } else {
        otherSymbols.add(symbol);
      }
    }

    // 排序優先股（自選 > 熱門）
    prioritySymbols.sort((a, b) {
      final aScore =
          (watchlistSet.contains(a) ? 2 : 0) + (popularSet.contains(a) ? 1 : 0);
      final bScore =
          (watchlistSet.contains(b) ? 2 : 0) + (popularSet.contains(b) ? 1 : 0);
      return bScore.compareTo(aScore);
    });

    final priorityCount = prioritySymbols.length.clamp(0, maxSyncCount);
    final remainingSlots = maxSyncCount - priorityCount;

    if (remainingSlots <= 0) {
      AppLogger.info('HistoricalPriceSyncer', '限制同步 $maxSyncCount 檔（全為自選/熱門）');
      return prioritySymbols.take(maxSyncCount).toList();
    }

    // 查詢市場資訊，按比例分配名額給 TWSE 和 TPEX
    final stockMap = await _db.getStocksBatch(otherSymbols);
    final twseOther = <String>[];
    final tpexOther = <String>[];

    for (final symbol in otherSymbols) {
      if (stockMap[symbol]?.market == MarketCode.tpex) {
        tpexOther.add(symbol);
      } else {
        twseOther.add(symbol);
      }
    }

    // 按市場比例分配（確保少數市場至少分到 1 個名額）
    final totalOther = twseOther.length + tpexOther.length;
    int tpexSlots;
    int twseSlots;

    if (totalOther == 0 || tpexOther.isEmpty) {
      tpexSlots = 0;
      twseSlots = remainingSlots;
    } else if (twseOther.isEmpty) {
      tpexSlots = remainingSlots;
      twseSlots = 0;
    } else {
      tpexSlots = (remainingSlots * tpexOther.length / totalOther)
          .round()
          .clamp(1, remainingSlots - 1);
      twseSlots = remainingSlots - tpexSlots;
    }

    final result = <String>[
      ...prioritySymbols.take(priorityCount),
      ...twseOther.take(twseSlots),
      ...tpexOther.take(tpexSlots),
    ];

    AppLogger.info(
      'HistoricalPriceSyncer',
      '限制同步 ${result.length} 檔'
          '（優先 $priorityCount, '
          'TWSE ${twseOther.take(twseSlots).length}, '
          'TPEx ${tpexOther.take(tpexSlots).length}）',
    );
    return result;
  }

  /// 執行批次同步
  Future<HistoricalPriceSyncResult> _performBatchSync(
    List<String> symbols, {
    required DateTime historyStartDate,
    required DateTime endDate,
    required int totalNeeded,
    void Function(String message)? onProgress,
  }) async {
    final total = symbols.length;
    var historySynced = 0;
    const batchSize = ApiConfig.historicalPriceBatchSize;
    final failedSymbols = <String>[];

    var rateLimited = false;
    // 只在收到「確證的」RateLimitException 時填入 —— NetworkException 與
    // 防禦性 circuit breaker 同樣會中止迴圈，但那是推測不是確證。
    Object? rateLimitError;
    var consecutiveFailedBatches = 0;
    var symbolsSucceeded = 0;
    final succeededSymbols = <String>[];

    for (var i = 0; i < total; i += batchSize) {
      if (rateLimited) break;
      if (i > 0) {
        await Future.delayed(
          const Duration(milliseconds: ApiConfig.priceRequestDelayMs),
        );
      }

      final batchEnd = (i + batchSize).clamp(0, total);
      final batch = symbols.sublist(i, batchEnd);

      onProgress?.call('歷史資料 (${i + 1}~$batchEnd / $total)');

      final futures = batch.map((symbol) async {
        try {
          final count = await _priceRepo.syncStockPrices(
            symbol,
            startDate: historyStartDate,
            endDate: endDate,
          );
          return (symbol, count, null as Object?);
        } catch (e) {
          return (symbol, 0, e);
        }
      });

      final results = await Future.wait(futures);

      var batchHasSuccess = false;
      for (final (symbol, count, error) in results) {
        if (error is RateLimitException) {
          rateLimited = true;
          rateLimitError ??= error;
          failedSymbols.add(symbol);
          AppLogger.warning(
            'HistoricalPriceSyncer',
            '$symbol: API 限流，中止剩餘歷史資料同步',
          );
        } else if (error is NetworkException) {
          rateLimited = true;
          failedSymbols.add(symbol);
          AppLogger.warning(
            'HistoricalPriceSyncer',
            '$symbol: 網路異常，中止剩餘歷史資料同步',
          );
        } else if (error != null) {
          failedSymbols.add(symbol);
        } else {
          historySynced += count;
          batchHasSuccess = true;
          symbolsSucceeded++;
          succeededSymbols.add(symbol);
        }
      }

      // 防禦性 circuit breaker：連續多批全部失敗時視為 API 限流
      // 即使錯誤類型不是 RateLimitException（如 NetworkException），
      // 連續失敗也代表 API 不可用，應停止發送無效請求
      if (!rateLimited) {
        if (batchHasSuccess) {
          consecutiveFailedBatches = 0;
        } else {
          consecutiveFailedBatches++;
          if (consecutiveFailedBatches >=
              ApiConfig.historicalPriceMaxConsecutiveFailedBatches) {
            rateLimited = true;
            AppLogger.warning(
              'HistoricalPriceSyncer',
              '連續 $consecutiveFailedBatches 批全部失敗，推測 API 限流，中止同步',
            );
          }
        }
      }
    }

    AppLogger.info(
      'HistoricalPriceSyncer',
      '歷史資料同步完成 $symbolsSucceeded/${symbols.length} 檔'
          '${totalNeeded > symbols.length ? " (共需 $totalNeeded 檔)" : ""}',
    );

    return HistoricalPriceSyncResult(
      syncedCount: historySynced,
      symbolsProcessed: symbolsSucceeded,
      totalSymbolsNeeded: totalNeeded,
      failedSymbols: failedSymbols,
      succeededSymbols: succeededSymbols,
      rateLimitError: rateLimitError,
    );
  }
}

/// 歷史價格同步結果
class HistoricalPriceSyncResult {
  const HistoricalPriceSyncResult({
    required this.syncedCount,
    required this.symbolsProcessed,
    this.totalSymbolsNeeded = 0,
    this.failedSymbols = const [],
    this.succeededSymbols = const [],
    this.marketDayRows = 0,
    this.rateLimitError,
  });

  final int syncedCount;
  final int symbolsProcessed;
  final int totalSymbolsNeeded;
  final List<String> failedSymbols;

  /// 本輪成功呼叫 API 的 symbol(退避記帳用——與 [failedSymbols] 互斥,
  /// 但限流中止後未嘗試的不在任一邊)
  final List<String> succeededSymbols;

  /// Phase 0（市場日快照回補）寫入的價格列數
  final int marketDayRows;

  /// 因 API 限流而提前中止時保留的原始例外，否則為 null。
  ///
  /// **不 rethrow 是刻意的**：整段歷史回補不該因為配額用完就算全失敗，
  /// 已抓到的資料要保留。但 caller 必須分辨得出「限流中止」與「個股資料
  /// 異常」——前者要設 `rateLimitedAbort` 止血並走
  /// `UpdateResult.recordError`（才會設 `hasRateLimitError`），後者不用。
  ///
  /// 只在真的收到 [RateLimitException] 時填入。`NetworkException` 與
  /// 「連續整批失敗」的防禦性 circuit breaker 同樣會中止迴圈，但那是推測
  /// 不是確證，不足以讓整條更新進入止血模式。
  final Object? rateLimitError;

  bool get hasErrors => failedSymbols.isNotEmpty;

  bool get rateLimited => rateLimitError != null;
}

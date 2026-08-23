import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/request_deduplicator.dart';
import 'package:daredevil/core/utils/safe_execution.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/price_candidate_filter.dart';
import 'package:daredevil/data/repositories/twse_price_source.dart';
import 'package:daredevil/data/repositories/tpex_price_source.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';

/// 每日價格資料 Repository
///
/// 主要資料來源：TWSE/TPEX Open Data（免費、無限制、全市場）
/// 備援資料來源：FinMind（歷史資料）
///
/// 將市場特定的 API 呼叫與資料轉換委託給 [TwsePriceSource] 和 [TpexPriceSource]，
/// 歷史資料不足時透過 [FinMindClient] 補齊。
class PriceRepository implements IPriceRepository {
  PriceRepository({
    required AppDatabase database,
    required FinMindClient finMindClient,
    required TwseClient twseClient,
    required TpexClient tpexClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _twseSource = TwsePriceSource(client: twseClient),
       _tpexSource = TpexPriceSource(
         client: tpexClient,
         finMind: finMindClient,
       ),
       _clock = clock;

  final AppDatabase _db;
  final TwsePriceSource _twseSource;
  final TpexPriceSource _tpexSource;
  final AppClock _clock;

  /// Request deduplicator for price history queries
  final _priceHistoryDedup = RequestDeduplicator<List<DailyPriceEntry>>();

  /// 取得價格歷史資料供分析使用
  ///
  /// 若可用，至少回傳 [RuleParams.lookbackPrice] 天的資料
  ///
  /// 使用 Request Deduplication 防止同時多次查詢相同股票的歷史資料
  @override
  Future<List<DailyPriceEntry>> getPriceHistory(
    String symbol, {
    int? days,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final effectiveStartDate =
        startDate ??
        _clock.now().subtract(
          Duration(
            days:
                (days ?? RuleParams.lookbackPrice) +
                RuleParams.historyBufferDays,
          ),
        );

    // 建立唯一的快取鍵
    final cacheKey =
        'price_history_${symbol}_'
        '${effectiveStartDate.toIso8601String()}_'
        '${endDate?.toIso8601String() ?? 'now'}';

    return _priceHistoryDedup.call(
      cacheKey,
      () => _db.getPriceHistory(
        symbol,
        startDate: effectiveStartDate,
        endDate: endDate,
      ),
    );
  }

  /// 取得股票最新價格
  @override
  Future<DailyPriceEntry?> getLatestPrice(String symbol) {
    return _db.getLatestPrice(symbol);
  }

  /// 取得特定日期的收盤價
  @override
  Future<DailyPriceEntry?> getPriceOnDate(String symbol, DateTime date) {
    return _db.getPriceOnDate(symbol, date);
  }

  /// 同步單檔股票價格歷史資料
  ///
  /// 上市股票使用 TWSE API，上櫃股票使用 FinMind API。
  /// 最佳化：僅抓取 Database 中缺少的月份。
  @override
  Future<int> syncStockPrices(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    try {
      final effectiveEndDate = endDate ?? _clock.now();

      // 最佳化：檢查既有資料
      final existingHistory = await _db.getPriceHistory(
        symbol,
        startDate: startDate,
        endDate: effectiveEndDate,
      );

      // 取得該股票在 DB 中的最早交易日期，用於跳過上市前的月份
      // 避免反覆向 TWSE 查詢不存在的歷史資料（永遠回傳空 → 永遠重抓）
      // 需要足夠資料量（>= 60 天）才信任 firstKnownDate 作為上市日代理，
      // 避免 partial sync 場景誤跳過有效月份
      final firstKnownDate = existingHistory.length >= 60
          ? existingHistory.first.date
          : null;

      // 預先 group by (year, month)，避免 while 迴圈內每次都掃描全部歷史資料
      final existingDaysByMonth = <(int, int), int>{};
      for (final p in existingHistory) {
        final key = (p.date.year, p.date.month);
        existingDaysByMonth[key] = (existingDaysByMonth[key] ?? 0) + 1;
      }

      // 計算需要抓取的月份（僅抓取資料不足的月份）
      final monthsToFetch = <DateTime>[];
      var current = DateTime(startDate.year, startDate.month, 1);
      final end = DateTime(effectiveEndDate.year, effectiveEndDate.month, 1);

      while (!current.isAfter(end)) {
        // 跳過股票上市前的月份：若 DB 已有資料且該月早於最早紀錄的月份，
        // 代表該月確實無交易資料，不需要再抓取
        if (firstKnownDate != null) {
          final firstKnownMonth = DateTime(
            firstKnownDate.year,
            firstKnownDate.month,
            1,
          );
          if (current.isBefore(firstKnownMonth)) {
            current = DateTime(current.year, current.month + 1, 1);
            continue;
          }
        }

        // 僅當該月資料不足時才抓取（少於 10 個交易日）
        final existingDaysInMonth =
            existingDaysByMonth[(current.year, current.month)] ?? 0;
        if (existingDaysInMonth < DataFreshness.minTradingDaysPerMonth) {
          monthsToFetch.add(current);
        }
        current = DateTime(current.year, current.month + 1, 1);
      }

      // 若無需抓取，直接回傳
      if (monthsToFetch.isEmpty) {
        return 0;
      }

      // 檢查股票市場（上市或上櫃）
      final stock = await _db.getStock(symbol);
      final isOtc = stock?.market == MarketCode.tpex;

      // 委託給對應的市場資料來源
      final entries = isOtc
          ? await _tpexSource.fetchSingleStockPrices(
              symbol: symbol,
              startDate: startDate,
              endDate: effectiveEndDate,
            )
          : await _twseSource.fetchMonthlyPrices(
              symbol: symbol,
              months: monthsToFetch,
              startDate: startDate,
              endDate: effectiveEndDate,
            );

      if (entries.isNotEmpty) {
        await _db.insertPrices(entries);
      }

      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync prices for $symbol', e);
    }
  }

  /// 用 TWSE MI_INDEX 歷史端點回補單一交易日**所有**上市股票價格
  ///
  /// 詳細語意見 [IPriceRepository.backfillTwsePricesByDate]。
  ///
  /// 實作走 [TwsePriceSource.fetchAllDailyPricesHistorical]（MI_INDEX；
  /// STOCK_DAY_ALL 自 2026-06 起忽略 date 參數、無法回補歷史），接著
  /// [TwsePriceSource.processDailyPrices] 轉成
  /// DB Companion 並依 [targetSymbols] 過濾，最後一次 batch insert。
  /// Pattern 與 [backfillTpexPricesByDate] 對稱。
  @override
  Future<int> backfillTwsePricesByDate({
    required DateTime date,
    required Set<String> targetSymbols,
  }) async {
    try {
      // 歷史回補走 MI_INDEX（STOCK_DAY_ALL 自 2026-06 起忽略 date 參數）
      final prices = await _twseSource.fetchAllDailyPricesHistorical(date);
      if (prices.isEmpty) return 0;

      final processed = _twseSource.processDailyPrices(prices);

      // 端點失效防護：TWSE 2026-06 起 STOCK_DAY_ALL 忽略 date 參數、永遠回
      // 最新交易日。只保留「請求日期」的 rows —— 寫入別的日子會讓 per-day
      // backfill 誤以為有進展（實際是同一天反覆重寫、歷史永遠補不滿）。
      final requestedDay = DateContext.normalize(date);
      final filtered = processed.priceEntries
          .where(
            (entry) =>
                targetSymbols.contains(entry.symbol.value) &&
                DateContext.normalize(entry.date.value) == requestedDay,
          )
          .toList();

      if (filtered.isEmpty) return 0;

      await _db.insertPrices(filtered);
      return filtered.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to backfill TWSE prices for ${DateContext.formatYmd(date)}',
        e,
      );
    }
  }

  /// 用 TPEx afterTrading 歷史端點回補單一交易日**所有**上櫃股票價格
  ///
  /// 詳細語意見 [IPriceRepository.backfillTpexPricesByDate]。
  ///
  /// 實作走 TPEx `getAllDailyPricesHistorical`（afterTrading/otc；舊
  /// daily_close_quotes 端點同樣自 2026-06 起忽略歷史 date），
  /// 接著 [TpexPriceSource.processDailyPrices] 轉成 DB Companion 並依
  /// [targetSymbols] 過濾，最後一次 batch insert。
  @override
  Future<int> backfillTpexPricesByDate({
    required DateTime date,
    required Set<String> targetSymbols,
  }) async {
    try {
      // 歷史回補走新版 afterTrading/otc（舊端點同樣忽略 date 參數）
      final prices = await _tpexSource.fetchAllDailyPricesHistorical(date);
      if (prices.isEmpty) return 0;

      // processDailyPrices 已處理 StockPatterns.isValidCode 過濾。
      final processed = _tpexSource.processDailyPrices(prices);

      // 同 backfillTwsePricesByDate：只保留請求日期的 rows（端點失效防護）。
      final requestedDay = DateContext.normalize(date);
      final filtered = processed.priceEntries.where((entry) {
        // DailyPriceCompanion 的 symbol 為 Value<String>；present 後比對
        final symbol = entry.symbol.value;
        return targetSymbols.contains(symbol) &&
            DateContext.normalize(entry.date.value) == requestedDay;
      }).toList();

      if (filtered.isEmpty) return 0;

      await _db.insertPrices(filtered);
      return filtered.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to backfill TPEx prices for ${DateContext.formatYmd(date)}',
        e,
      );
    }
  }

  /// 同步最新交易日的所有價格，並回傳快篩候選股
  ///
  /// 主要來源：TWSE/TPEX Open Data（免費、無限制、全市場）
  ///
  /// 同時以 TWSE/TPEX 資料更新 stock_master 中的股票名稱。
  ///
  /// 回傳 [MarketSyncResult]，包含同步筆數和快篩候選股。
  @override
  Future<MarketSyncResult> syncAllPricesForDate(
    DateTime date, {
    bool force = false,
  }) async {
    try {
      // 正規化日期至 UTC 午夜時間，確保跨時區一致性
      final normalizedDate = DateContext.normalize(date);

      // 最佳化：先檢查 Database，避免不必要的 API 呼叫
      if (!force) {
        final existingCount = await _db.getPriceCountForDate(normalizedDate);
        if (existingCount > DataFreshness.fullMarketThreshold) {
          final candidates = await quickFilterCandidatesFromDb(
            _db,
            normalizedDate,
          );

          AppLogger.info(
            'PriceRepo',
            '價格同步: $existingCount 筆 (${DateContext.formatYmd(normalizedDate)}, 快取)',
          );

          return MarketSyncResult(
            count: existingCount,
            candidates: candidates,
            dataDate: normalizedDate,
            skipped: true,
          );
        }
      }

      // 平行取得上市與上櫃價格資料（錯誤隔離，允許部分成功）
      // TWSE 端點自動回傳最新交易日資料（不接受日期參數）
      // TPEX 端點需要明確傳入日期，否則 fallback 到 DateTime.now()
      // 在非交易日（週末/假日）會導致 TPEX 回傳空資料
      // safeAwaitPair(2026-07-30):雙來源同時 rethrow 型失敗(斷網/同時
      // 限流)在舊「先啟動再逐一 await」寫法下,第二個 future 的 rejection
      // 無人監聽 → zone unhandled;pair 版啟動當下就掛好兩邊 listener
      final (twsePrices, tpexPrices) = await safeAwaitPair(
        _twseSource.fetchAllDailyPrices(),
        _tpexSource.fetchAllDailyPrices(date: normalizedDate),
        firstDefault: <TwseDailyPrice>[],
        secondDefault: <TpexDailyPrice>[],
        tag: 'PriceRepo',
        firstDescription: '上市價格取得失敗，繼續處理上櫃',
        secondDescription: '上櫃價格取得失敗，繼續處理上市',
      );

      if (twsePrices.isEmpty && tpexPrices.isEmpty) {
        AppLogger.warning('PriceRepo', '價格同步: 無資料');
        return const MarketSyncResult(
          count: 0,
          candidates: [],
          emptyMarkets: [MarketCode.twse, MarketCode.tpex],
        );
      }

      // 委託給市場資料來源處理轉換和篩選
      final twseResult = _twseSource.processDailyPrices(twsePrices);
      final tpexResult = _tpexSource.processDailyPrices(tpexPrices);

      final allPriceEntries = [
        ...twseResult.priceEntries,
        ...tpexResult.priceEntries,
      ];
      final allStockEntries = [
        ...twseResult.stockEntries,
        ...tpexResult.stockEntries,
      ];
      final allCandidates = [
        ...twseResult.candidates,
        ...tpexResult.candidates,
      ];

      // 寫入資料庫
      if (allStockEntries.isNotEmpty) {
        await _db.upsertStocks(allStockEntries);
      }
      await _db.insertPrices(allPriceEntries);

      // 決定資料日期
      final dataDate = twseResult.dataDate ?? tpexResult.dataDate;

      AppLogger.info(
        'PriceRepo',
        '價格同步: ${allPriceEntries.length} 筆 '
            '(上市 ${twseResult.priceEntries.length}, '
            '上櫃 ${tpexResult.priceEntries.length}, '
            '${dataDate != null ? DateContext.formatYmd(dataDate) : 'N/A'}, '
            '候選 ${allCandidates.length})',
      );

      // 回報零筆的市場：safeAwait 把來源失敗吞成空清單，只有兩市場皆空才會
      // 被上方分支攔下；僅單一市場掛掉時流程照常走完，必須讓呼叫端看得見。
      //
      // **半市場日刻意不擋整天出榜**（2026-07-26 稽核否決過「全市場列數
      // < 1500 就整天不出榜」，三條理由）：
      //  1. 半市場產出的是「清單不完整」而非「排名被扭曲」——
      //     `getModeStockScores` 無 LIMIT 無 top-N，每檔的 mode 分數是它自己
      //     規則分數的 SUM，與其他股票無關；配合 staleBar 檢查，每一列都由
      //     該股當日 bar 算出，個別訊號皆正確。
      //  2. 已有通報管道：本 `emptyMarkets` 會在半市場日觸發警告。再加整天
      //     不出榜是替使用者做決定。
      //  3. 門檻須綁定當下市場規模（當時 2,129 檔）。規模漂移後會開始靜默
      //     丟棄健康日的資料，是難以察覺的迴歸。
      final emptyMarkets = <String>[
        if (twseResult.priceEntries.isEmpty) MarketCode.twse,
        if (tpexResult.priceEntries.isEmpty) MarketCode.tpex,
      ];

      return MarketSyncResult(
        count: allPriceEntries.length,
        candidates: allCandidates,
        dataDate: dataDate,
        emptyMarkets: emptyMarkets,
      );
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, stack) {
      AppLogger.error('PriceRepo', '價格同步失敗', e, stack);
      throw DatabaseException('Failed to sync prices from TWSE/TPEX', e);
    }
  }
}

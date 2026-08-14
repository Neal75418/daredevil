import 'package:daredevil/core/constants/api_config.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';

/// 市場籌碼資料更新器
///
/// 負責同步當沖、融資融券、外資持股、警示、董監持股等資料
/// 選出本輪要同步外資持股的上櫃候選 —— **最舊優先**。
///
/// 兩個規則：
/// 1. 已新鮮者（持股日期 ≥ [freshnessDate]）一律排除，不佔配額
/// 2. 其餘依持股日期由舊到新排序，**無資料者視為最舊**；同日期以代號排序
///    保證決定性
///
/// ## 為什麼不能只做過濾
///
/// 新鮮度定義是「持股日期 ≥ 最新交易日」，每到新的一天全部股票同時變舊。
/// 若仍按候選順序取前 N，跨天永遠是同一批（價格走快取路徑時候選順序退化
/// 為代號升冪）。實測 2026-07-26 正式 DB：上櫃股「最新持股日 = 07-24」的
/// **恰好 20 檔**，正是 `maxSyncCount`；263 檔候選中 177 檔完全無資料。
///
/// 舊實作把 `take(N)` 放在新鮮度檢查**之前**，配額先分配給前 N 名才發現
/// 他們已新鮮 —— 同日重複跑時整個步驟空轉（日誌「跳過 20 檔」+「持股=0」）。
///
/// 最舊優先後模擬顯示 9 個交易日達 100% 涵蓋，現行邏輯恆為 88 檔。
@visibleForTesting
List<String> selectOtcShareholdingTargets({
  required List<String> candidates,
  required Map<String, DateTime?> latestDates,
  required DateTime freshnessDate,
  required int limit,
}) {
  // 無資料者用 epoch 當排序鍵 → 自然排在最前
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final stale =
      <String>[
        for (final s in candidates)
          if (!(latestDates[s]?.isBefore(freshnessDate) == false)) s,
      ]..sort((a, b) {
        final cmp = (latestDates[a] ?? epoch).compareTo(
          latestDates[b] ?? epoch,
        );
        return cmp != 0 ? cmp : a.compareTo(b);
      });
  return stale.length > limit ? stale.sublist(0, limit) : stale;
}

class MarketDataUpdater {
  MarketDataUpdater({
    required AppDatabase database,
    required TradingRepository tradingRepository,
    required ShareholdingRepository shareholdingRepository,
    required WarningRepository warningRepository,
    required InsiderRepository insiderRepository,
    this.backfillCallDelay = const Duration(
      milliseconds: ApiConfig.priceRequestDelayMs,
    ),
  }) : _db = database,
       _tradingRepo = tradingRepository,
       _shareholdingRepo = shareholdingRepository,
       _warningRepo = warningRepository,
       _insiderRepo = insiderRepository;

  final AppDatabase _db;
  final TradingRepository _tradingRepo;
  final ShareholdingRepository _shareholdingRepo;
  final WarningRepository _warningRepo;
  final InsiderRepository _insiderRepo;

  /// 缺漏日回補的呼叫間隔（測試注入 [Duration.zero]）
  final Duration backfillCallDelay;

  /// 同步全市場籌碼資料（TWSE + TPEX 批次 API）
  ///
  /// 包含當沖和融資融券資料。
  /// 使用官方免費 API，無需 FinMind 配額。
  Future<MarketDataSyncResult> syncMarketWideData({
    required DateTime date,
    bool force = false,
  }) async {
    var twseDayTradingCount = 0;
    int? marginCount = 0;

    // 從 TWSE 批次同步上市當沖資料（無 TPEX 對等：上櫃端點被 Cloudflare 擋）
    try {
      twseDayTradingCount = await _tradingRepo.syncAllDayTradingFromTwse(
        date: date,
        force: force,
      );
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('MarketDataUpdater', '上市當沖資料同步失敗', e);
    }

    // 從 TWSE/TPEX 批次同步融資融券資料
    try {
      marginCount = await _tradingRepo.syncAllMarginTrading(date: date);
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('MarketDataUpdater', '融資融券資料同步失敗', e);
    }

    // 回補缺漏日（今日同步完才跑，確保當日資料不被回補預算排擠）
    final backfilledDays = await _backfillMissingTradingDays(date);

    return MarketDataSyncResult(
      dayTradingCount: twseDayTradingCount,
      marginCount: marginCount,
      backfilledDays: backfilledDays,
    );
  }

  /// 回補當沖 / 融資融券的缺漏交易日
  ///
  /// 這兩類資料台交所約 21:00 後才發布，使用者在那之前更新就抓不到；
  /// 而每日路徑只抓「更新當下那一天」，錯過即永久缺漏（2026-07-14 實測：
  /// 近 30 交易日當沖缺 12 天、融資缺 10 天；法人因有回補迴圈而 0 缺漏）。
  ///
  /// 掃 `[date - lookback, date - 1]` 內的交易日（[TaiwanCalendar]，新→舊），
  /// 以**三個獨立來源**（當沖、上市融資、上櫃融資）分別判斷缺漏與進度：
  /// - **當沖**（僅上市，上櫃無全市場快照端點）走
  ///   [TradingRepository.syncAllDayTradingFromTwse]（force 略過新鮮度檢查）。
  ///   前提：該日價格覆蓋須達門檻——當沖比例以價格表的成交量為分母，半覆蓋日
  ///   會把沒價格的股票全寫成 ratio 0（假資料），且之後筆數已足、永不重抓。
  /// - **融資融券**走 [TradingRepository.backfillMarginTradingByDate]，**逐市場**
  ///   判斷（合併門檻是上市+上櫃合計校準的，上市單邊約 1,280 筆低於門檻，
  ///   上櫃失敗時會讓該日永遠被判缺漏）。
  ///
  /// **收斂性**（三道設計，缺一就會卡死）：
  /// 1. **價格表當 ground truth**：行事曆是靜態表，未預期停市（颱風）會謊報為
  ///    交易日。零價格日直接跳過，不浪費呼叫、也不吃斷路器額度。
  /// 2. **進度 = 跨過缺漏偵測的門檻**（不是「有寫入列」）。某來源若持續回
  ///    「非零但不足額」，用 rows > 0 判進度會無限重試。
  /// 3. **斷路器 per-source**：某來源連續 N 天沒進度即在本次 run 標記 dead、
  ///    不再嘗試，**也不再阻擋其他來源**。合併成 day-level 會讓單一來源永久
  ///    失效時餓死整個掃描（頭部日子的唯一缺口就是它 → 連續零筆 → 中止 →
  ///    更舊、原本補得到的日子永遠掃不到）。
  ///
  /// 其餘防護：單次上限 [ApiConfig.tradingBackfillMaxDaysPerRun]、單日一般
  /// 錯誤不中斷後續日子。RateLimit / Network 往上拋——與本層每日路徑一致，
  /// 讓 UpdateService 設 `rateLimitedAbort` 停掉後續 TWSE 呼叫。
  ///
  /// 回傳實際有進度的天數。
  Future<int> _backfillMissingTradingDays(DateTime date) async {
    final endDay = DateContext.normalize(date);
    final windowStart = endDay.subtract(
      const Duration(days: ApiConfig.tradingBackfillLookbackDays),
    );

    final twseStocks = await _db.countStocksByMarket(MarketCode.twse);
    final tpexStocks = await _db.countStocksByMarket(MarketCode.tpex);
    if (twseStocks == 0 && tpexStocks == 0) return 0; // fresh DB：主檔未同步

    const ratio = ApiConfig.tradingBackfillMinCoverageRatio;
    final twseThreshold = (twseStocks * ratio).ceil();
    final tpexThreshold = (tpexStocks * ratio).ceil();

    // 三個獨立來源的連續失敗計數；達門檻即在本次 run 標記 dead
    const srcDayTrading = 'dayTrading';
    final failures = <String, int>{};
    final dead = <String>{};
    void recordAttempt(String source, {required bool progressed}) {
      if (progressed) {
        failures[source] = 0;
        return;
      }
      final n = (failures[source] ?? 0) + 1;
      failures[source] = n;
      if (n >= ApiConfig.tradingBackfillMaxConsecutiveZeroDays) {
        dead.add(source);
        AppLogger.warning(
          'MarketDataUpdater',
          '$source 連續 $n 天無進度，本次更新不再嘗試（其他來源照常回補）',
        );
      }
    }

    var backfilledDays = 0;
    var apiDays = 0;

    for (
      var day = endDay.subtract(const Duration(days: 1));
      !day.isBefore(windowStart) &&
          backfilledDays < ApiConfig.tradingBackfillMaxDaysPerRun;
      day = day.subtract(const Duration(days: 1))
    ) {
      if (!TaiwanCalendar.isTradingDay(day)) continue;

      // 收斂設計 1：價格表 = 「那天到底有沒有開市」的 ground truth
      final twsePrices = twseStocks > 0
          ? await _db.countPricesByDateAndMarket(day, MarketCode.twse)
          : 0;
      var hasPrices = twsePrices > 0;
      if (!hasPrices && tpexStocks > 0) {
        hasPrices =
            await _db.countPricesByDateAndMarket(day, MarketCode.tpex) > 0;
      }
      if (!hasPrices) {
        AppLogger.debug(
          'MarketDataUpdater',
          '${DateContext.formatYmd(day)} 無任何價格資料，視為非交易日，跳過',
        );
        continue;
      }

      // 當沖（上市）
      var canBackfillDayTrading = false;
      if (!dead.contains(srcDayTrading) &&
          twseStocks > 0 &&
          await _db.getDayTradingCountForDate(day) <=
              DataFreshness.twseBatchThreshold) {
        canBackfillDayTrading = twsePrices >= twseThreshold;
        if (!canBackfillDayTrading) {
          AppLogger.debug(
            'MarketDataUpdater',
            '${DateContext.formatYmd(day)} 價格覆蓋不足 '
                '($twsePrices < $twseThreshold)，跳過當沖回補（比例會失真）',
          );
        }
      }

      // 融資融券（per-market）
      final missingMarkets = <String>{
        if (!dead.contains(MarketCode.twse) &&
            twseStocks > 0 &&
            await _db.countMarginTradingByDateAndMarket(day, MarketCode.twse) <
                twseThreshold)
          MarketCode.twse,
        if (!dead.contains(MarketCode.tpex) &&
            tpexStocks > 0 &&
            await _db.countMarginTradingByDateAndMarket(day, MarketCode.tpex) <
                tpexThreshold)
          MarketCode.tpex,
      };

      if (!canBackfillDayTrading && missingMarkets.isEmpty) continue;

      if (apiDays > 0) await Future.delayed(backfillCallDelay);
      apiDays++;

      var dayProgressed = false;

      if (canBackfillDayTrading) {
        var rows = 0;
        try {
          rows = await _tradingRepo.syncAllDayTradingFromTwse(
            date: day,
            force: true,
          );
        } on RateLimitException {
          rethrow;
        } on NetworkException {
          rethrow;
        } on Exception catch (e) {
          AppLogger.warning(
            'MarketDataUpdater',
            '當沖回補失敗 ${DateContext.formatYmd(day)}',
            e,
          );
        }
        // 收斂設計 2：進度 = 跨過缺漏偵測的門檻（與上方偵測條件互為補集）
        final progressed = rows > DataFreshness.twseBatchThreshold;
        recordAttempt(srcDayTrading, progressed: progressed);
        dayProgressed |= progressed;
      }

      if (missingMarkets.isNotEmpty) {
        var result = (twseRows: 0, tpexRows: 0);
        try {
          result = await _tradingRepo.backfillMarginTradingByDate(
            date: day,
            markets: missingMarkets,
          );
        } on RateLimitException {
          rethrow;
        } on NetworkException {
          rethrow;
        } on Exception catch (e) {
          AppLogger.warning(
            'MarketDataUpdater',
            '融資融券回補失敗 ${DateContext.formatYmd(day)}',
            e,
          );
        }
        if (missingMarkets.contains(MarketCode.twse)) {
          final progressed = result.twseRows >= twseThreshold;
          recordAttempt(MarketCode.twse, progressed: progressed);
          dayProgressed |= progressed;
        }
        if (missingMarkets.contains(MarketCode.tpex)) {
          final progressed = result.tpexRows >= tpexThreshold;
          recordAttempt(MarketCode.tpex, progressed: progressed);
          dayProgressed |= progressed;
        }
      }

      if (dayProgressed) backfilledDays++;
    }

    if (apiDays > 0) {
      AppLogger.info(
        'MarketDataUpdater',
        '籌碼缺漏日回補: $backfilledDays/$apiDays 天'
            '${dead.isEmpty ? "" : "（失效來源: ${dead.join(", ")}）"}',
      );
    }
    return backfilledDays;
  }

  /// 同步特定股票清單的外資持股資料
  ///
  /// 用於自選清單和熱門股的詳細籌碼追蹤。
  ///
  /// 當沖資料已由 syncMarketWideData 透過批次 TWSE/TPEX API 同步，
  /// 不再需要逐檔呼叫 FinMind，節省 API 配額。
  Future<int> syncSymbolsMarketData({
    required List<String> symbols,
    required DateTime date,
  }) async {
    if (symbols.isEmpty) return 0;

    final marketDataStartDate = date.subtract(
      const Duration(
        days:
            InstitutionalParams.foreignShareholdingLookbackDays +
            ApiConfig.foreignShareholdingBufferDays,
      ),
    );

    const chunkSize = ApiConfig.marketDataBatchSize;
    var syncedCount = 0;

    for (var i = 0; i < symbols.length; i += chunkSize) {
      final chunk = symbols.skip(i).take(chunkSize).toList();

      final futures = chunk.map((symbol) async {
        try {
          // 只同步外資持股，當沖資料已由批次 API 處理
          await _shareholdingRepo.syncShareholding(
            symbol,
            startDate: marketDataStartDate,
            endDate: date,
          );
          return true;
        } on RateLimitException {
          rethrow;
        } on NetworkException {
          rethrow;
        } catch (e) {
          AppLogger.debug('MarketDataUpdater', '$symbol 市場資料同步失敗: $e');
          return false;
        }
      });

      final results = await Future.wait(futures);
      syncedCount += results.where((r) => r).length;
    }

    return syncedCount;
  }

  /// 補充上櫃候選股票的外資持股資料
  ///
  /// 當沖資料由 `syncMarketWideData` 透過批次 TPEX API 同步（非此方法）。
  /// 此方法只同步外資持股資料（仍需 FinMind 逐檔呼叫）。
  ///
  /// maxSyncCount 預設 20：外資持股規則（ForeignExodus, ForeignConcentration）
  /// 為輔助訊號，20 檔足夠涵蓋主要候選股，避免 API 額度耗盡。
  Future<OtcMarketDataResult> syncOtcCandidatesMarketData({
    required List<String> candidates,
    required DateTime date,
    int maxSyncCount = 20,
  }) async {
    if (candidates.isEmpty) {
      return const OtcMarketDataResult(
        dayTradingCount: 0,
        shareholdingCount: 0,
      );
    }

    // 取得上櫃股票清單
    final otcStocks = await _db.getStocksByMarket(MarketCode.tpex);
    final otcSymbols = otcStocks.map((s) => s.symbol).toSet();

    // 篩選出候選清單中的上櫃股票
    final otcCandidates = candidates
        .where((symbol) => otcSymbols.contains(symbol))
        .toList();

    if (otcCandidates.isEmpty) {
      return const OtcMarketDataResult(
        dayTradingCount: 0,
        shareholdingCount: 0,
      );
    }

    // 取得新鮮度檢查基準日期
    final latestDayTradingDate = await _db.getLatestDayTradingDate();
    final normalizedFreshnessDate = latestDayTradingDate != null
        ? DateContext.normalize(latestDayTradingDate)
        : DateContext.normalize(date);

    // 批次預載**全部**候選的最新持股（單次查詢），供最舊優先排序用。
    // 必須先於配額分配 —— 舊實作把 take(N) 放在新鮮度檢查之前，配額先給
    // 前 N 名才發現他們已新鮮（見 selectOtcShareholdingTargets 的說明）。
    final latestShareholdingMap = await _shareholdingRepo
        .getLatestShareholdingsBatch(otcCandidates);

    final limitedOtcCandidates = selectOtcShareholdingTargets(
      candidates: otcCandidates,
      latestDates: {
        for (final e in latestShareholdingMap.entries) e.key: e.value.date,
      },
      freshnessDate: normalizedFreshnessDate,
      limit: maxSyncCount,
    );

    if (otcCandidates.length > maxSyncCount) {
      AppLogger.info(
        'MarketDataUpdater',
        '上櫃候選 ${otcCandidates.length} 檔超過配額 $maxSyncCount，'
            '本輪取最舊 ${limitedOtcCandidates.length} 檔',
      );
    }

    final marketDataStartDate = date.subtract(
      const Duration(
        days:
            InstitutionalParams.foreignShareholdingLookbackDays +
            ApiConfig.foreignShareholdingBufferDays,
      ),
    );

    var shareholdingCount = 0;
    var skippedCount = 0;
    var quotaExhausted = false;
    var totalErrorCount = 0;
    const maxTotalErrors = ApiConfig.marketDataMaxTotalErrors;

    const chunkSize = ApiConfig.marketDataBatchSize;
    outerLoop:
    for (var i = 0; i < limitedOtcCandidates.length; i += chunkSize) {
      final chunk = limitedOtcCandidates.skip(i).take(chunkSize).toList();

      final futures = chunk.map((symbol) async {
        try {
          // 新鮮度檢查：若已有參考日期的外資持股資料，跳過
          final latestShareholding = latestShareholdingMap[symbol];
          // 冗餘防線：selectOtcShareholdingTargets 已排除新鮮者，正常路徑
          // 不會走到這裡。保留是為了「選擇邏輯若有誤仍不會重打 API」；
          // 下方 skippedCount 的日誌因此**應恆為靜默** —— 它一旦出現，
          // 代表選擇階段與此處的新鮮度判斷不一致，是需要查的訊號。
          final hasFreshShareholding =
              latestShareholding != null &&
              !latestShareholding.date.isBefore(normalizedFreshnessDate);

          if (hasFreshShareholding) {
            return (
              true,
              false,
              false,
              false,
            ); // skipped, synced, error, quotaError
          }

          // 同步外資持股資料
          try {
            final shResult = await _shareholdingRepo.syncShareholding(
              symbol,
              startDate: marketDataStartDate,
              endDate: date,
            );
            return (false, shResult > 0, false, false);
          } on RateLimitException {
            return (false, false, true, true); // quota error
          }
        } catch (e) {
          AppLogger.debug('MarketDataUpdater', '$symbol 外資持股同步失敗: $e');
          return (false, false, true, false);
        }
      });

      final results = await Future.wait(futures);

      for (final (skipped, synced, isError, isQuotaError) in results) {
        if (skipped) skippedCount++;
        if (synced) shareholdingCount++;
        if (isError) {
          totalErrorCount++;
          if (isQuotaError) quotaExhausted = true;
        }
      }

      // 若偵測到額度耗盡，提前終止
      if (quotaExhausted &&
          totalErrorCount >= ApiConfig.marketDataQuotaExhaustMinErrors) {
        AppLogger.warning(
          'MarketDataUpdater',
          'FinMind API 額度耗盡，停止上櫃同步 (已處理 ${i + chunkSize}/${limitedOtcCandidates.length} 檔)',
        );
        break outerLoop;
      }

      // 偵測累積錯誤
      if (totalErrorCount >= maxTotalErrors) {
        AppLogger.warning(
          'MarketDataUpdater',
          'FinMind API 累積 $totalErrorCount 個錯誤，停止上櫃同步 (已處理 ${i + chunkSize}/${limitedOtcCandidates.length} 檔)',
        );
        break outerLoop;
      }
    }

    if (skippedCount > 0) {
      AppLogger.warning(
        'MarketDataUpdater',
        '上櫃外資持股：選擇階段與迴圈新鮮度判斷不一致，跳過 $skippedCount 檔'
            '（正常路徑不應出現）',
      );
    }

    // 上櫃當沖恆為 0：**沒有任何 TPEx 當沖資料來源**。
    // `dayTrading` 在 lib/data/remote/ 底下只出現於 twse_client.dart，
    // TPEx 側從未實作過對應端點，day_trading 表全期 0 筆 TPEx 列。
    // （此處原本註明「已由批次 TPEX API 同步」，與程式碼不符，2026-07-26 更正。）
    //
    // 後果見 RuleScores.dayTradingExtreme 的註解：上櫃股結構性吃不到該扣分。
    return OtcMarketDataResult(
      dayTradingCount: 0,
      shareholdingCount: shareholdingCount,
      totalCandidates: otcCandidates.length,
      syncedCandidates: limitedOtcCandidates.length,
    );
  }

  // ==================================================
  // Killer Features 同步方法
  // ==================================================

  /// 同步 Killer Features 資料（警示、董監持股）
  ///
  /// 警示資料每日更新，董監持股資料每月更新。
  /// 兩者為獨立操作，即使一項同步失敗另一項仍繼續執行（部分成功模式）。
  ///
  /// 序列化執行（非平行），避免同時對 TPEX 伺服器發起過多連線，
  /// 減少 "Connection closed" / "Connection reset" 錯誤。
  Future<KillerFeaturesSyncResult> syncKillerFeaturesData({
    bool force = false,
  }) async {
    int warningCount = 0;
    int insiderCount = 0;
    Object? warningError;
    Object? insiderError;

    // 先同步警示資料（內部包含 TWSE + TPEX 請求）
    try {
      warningCount = await _warningRepo.syncAllMarketWarnings(force: force);
      AppLogger.info('MarketDataUpdater', '警示資料同步完成: $warningCount 筆');
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('MarketDataUpdater', '警示資料同步失敗', e);
      warningError = e;
    }

    // 再同步董監持股資料（內部包含 TWSE + TPEX 請求）
    try {
      insiderCount = await _insiderRepo.syncAllInsiderHoldings(force: force);
      AppLogger.info('MarketDataUpdater', '董監持股資料同步完成: $insiderCount 筆');
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('MarketDataUpdater', '董監持股資料同步失敗', e);
      insiderError = e;
    }

    return KillerFeaturesSyncResult(
      warningCount: warningCount,
      insiderCount: insiderCount,
      warningError: warningError,
      insiderError: insiderError,
    );
  }
}

/// 市場籌碼同步結果
class MarketDataSyncResult {
  const MarketDataSyncResult({
    required this.dayTradingCount,
    required this.marginCount,
    this.backfilledDays = 0,
  });

  final int dayTradingCount;

  /// 融資融券同步筆數。null 表示已快取（跳過同步）。
  final int? marginCount;

  /// 回補成功的缺漏交易日天數（當沖或融資任一**跨過缺漏偵測門檻**才計
  /// 1 天——與收斂設計第 2 條一致，非「有寫入列」即計）
  final int backfilledDays;

  int get total => dayTradingCount + (marginCount ?? 0);
}

/// 上櫃籌碼同步結果
class OtcMarketDataResult {
  const OtcMarketDataResult({
    required this.dayTradingCount,
    required this.shareholdingCount,
    this.totalCandidates = 0,
    this.syncedCandidates = 0,
  });

  final int dayTradingCount;
  final int shareholdingCount;
  final int totalCandidates;
  final int syncedCandidates;

  int get total => dayTradingCount + shareholdingCount;
}

/// Killer Features 同步結果
class KillerFeaturesSyncResult {
  const KillerFeaturesSyncResult({
    required this.warningCount,
    required this.insiderCount,
    this.warningError,
    this.insiderError,
  });

  final int warningCount;
  final int insiderCount;

  /// 警示同步錯誤（若有）
  final Object? warningError;

  /// 董監持股同步錯誤（若有）
  final Object? insiderError;

  int get total => warningCount + insiderCount;

  /// 是否有任何同步錯誤
  bool get hasErrors => warningError != null || insiderError != null;
}

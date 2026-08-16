import 'dart:async';
// meta 而非 flutter/foundation:本檔在 tool/daily_update.dart 的 launchd
// 純 Dart 鏈上,flutter/foundation 經 binding.dart 依賴 dart:ui,dart run
// 之下編譯直接炸(守門:test/tool/daily_update_pure_dart_test.dart)。
import 'package:meta/meta.dart' show visibleForTesting;

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/default_stocks.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';
import 'package:daredevil/domain/services/alert/trailing_ma_alert_service.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_accuracy_service.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/scoring_service.dart';
import 'package:daredevil/domain/services/update/news_mention_snapshot_service.dart';
import 'package:daredevil/domain/services/update/update.dart';
import 'package:daredevil/domain/services/update/zeroing_impact_reporter.dart';
import 'package:daredevil/domain/services/update_service_deps.dart';

/// 每日市場資料更新協調服務
///
/// 協調各專責 updater 執行 10 步驟每日更新流程：
/// 1. 檢查交易日
/// 2. 更新股票清單
/// 3. 取得每日價格
/// 4. 取得法人資料（可選）
/// 5. 取得 RSS 新聞
/// 6. 篩選候選股票（候選優先策略）
/// 7. 執行分析
/// 8. 套用規則引擎（寫 daily_reason）
/// 9-10. 標記完成（daily_recommendation 已退役、3-mode 從 daily_reason 即時聚合）
class UpdateService {
  UpdateService({
    required AppDatabase database,
    required UpdateRepositories repositories,
    UpdateClients clients = const UpdateClients(),
    UpdateServices services = const UpdateServices(),
    List<String>? popularStocks,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _clock = clock,
       _ruleAccuracyService = services.ruleAccuracy,
       _thesisMonitorService = services.thesisMonitor,
       _newsMentionSnapshotService = services.newsMentionSnapshot,
       _trailingMaAlertService = TrailingMaAlertService(
         database: database,
         clock: clock,
       ),
       _priceRepo = repositories.price,
       _analysisRepo = repositories.analysis,
       _analysisService = services.analysis ?? AnalysisService(),
       _ruleEngine = services.ruleEngine ?? RuleEngine(),
       _scoringService = services.scoring,
       _popularStocks = popularStocks ?? DefaultStocks.popularStocks,
       // 初始化專責 updater
       _stockListSyncer = StockListSyncer(stockRepository: repositories.stock),
       _newsSyncer = NewsSyncer(newsRepository: repositories.news),
       _institutionalSyncer = repositories.institutional != null
           ? InstitutionalSyncer(
               institutionalRepository: repositories.institutional!,
             )
           : null,
       _batchDataLoader = BatchDataLoader(
         database: database,
         newsRepository: repositories.news,
         institutionalRepository: repositories.institutional,
         shareholdingRepository: repositories.shareholding,
         insiderRepository: repositories.insider,
       ),
       _candidateSelector = CandidateSelector(
         database: database,
         popularStocks: popularStocks ?? DefaultStocks.popularStocks,
       ),
       _historicalPriceSyncer = HistoricalPriceSyncer(
         database: database,
         priceRepository: repositories.price,
       ),
       _marketDataUpdater =
           (repositories.trading != null &&
               repositories.shareholding != null &&
               repositories.warning != null &&
               repositories.insider != null)
           ? MarketDataUpdater(
               database: database,
               tradingRepository: repositories.trading!,
               shareholdingRepository: repositories.shareholding!,
               warningRepository: repositories.warning!,
               insiderRepository: repositories.insider!,
             )
           : null,
       _fundamentalSyncer = repositories.fundamental != null
           ? FundamentalSyncer(
               database: database,
               fundamentalRepository: repositories.fundamental!,
               marketDataRepository: repositories.marketData,
             )
           : null,
       _finMindClient = clients.finMind,
       _marketIndexSyncer = clients.twse != null
           ? MarketIndexSyncer(
               database: database,
               twseClient: clients.twse!,
               tpexClient: clients.tpex,
               finMindClient: clients.finMind,
             )
           : null,
       _tdccHoldingSyncer = clients.tdcc != null
           ? TdccHoldingSyncer(database: database, tdccClient: clients.tdcc!)
           : null,
       _dividendSyncer = (clients.twse != null || clients.tpex != null)
           ? DividendSyncer(
               database: database,
               twseClient: clients.twse,
               tpexClient: clients.tpex,
             )
           : null,
       _insiderTransferSyncer = (clients.tpex != null || clients.twse != null)
           ? InsiderTransferSyncer(
               database: database,
               tpexClient: clients.tpex,
               twseClient: clients.twse,
             )
           : null,
       _quarterlyReportSyncer = (clients.tpex != null || clients.twse != null)
           ? QuarterlyReportSyncer(
               database: database,
               twseClient: clients.twse,
               tpexClient: clients.tpex,
             )
           : null;

  final AppDatabase _db;
  final AppClock _clock;

  /// 只為了在完成日誌印真實 FinMind 用量（hourlyUsage）；null 時該段省略。
  final FinMindClient? _finMindClient;
  final IPriceRepository _priceRepo;
  final IAnalysisRepository _analysisRepo;
  final AnalysisService _analysisService;
  final RuleEngine _ruleEngine;
  final ScoringService? _scoringService;
  final RuleAccuracyService? _ruleAccuracyService;
  final ThesisMonitorService? _thesisMonitorService;
  final NewsMentionSnapshotService? _newsMentionSnapshotService;

  /// 均線階梯提醒。**刻意不做成可選注入**：其餘 fail-safe service 為 null
  /// 時整段靜默跳過，而本專案有「自動更新靜默斷 13 天」的前科——只依賴
  /// AppDatabase 的東西沒有理由讓呼叫端有機會漏接。
  final TrailingMaAlertService _trailingMaAlertService;
  final List<String> _popularStocks;

  // 專責 updater / loader
  final BatchDataLoader _batchDataLoader;
  final CandidateSelector _candidateSelector;
  final StockListSyncer _stockListSyncer;
  final NewsSyncer _newsSyncer;
  final InstitutionalSyncer? _institutionalSyncer;
  final HistoricalPriceSyncer _historicalPriceSyncer;
  final MarketDataUpdater? _marketDataUpdater;
  final FundamentalSyncer? _fundamentalSyncer;
  final MarketIndexSyncer? _marketIndexSyncer;
  final TdccHoldingSyncer? _tdccHoldingSyncer;
  final DividendSyncer? _dividendSyncer;
  final InsiderTransferSyncer? _insiderTransferSyncer;
  final QuarterlyReportSyncer? _quarterlyReportSyncer;

  /// 取得或建立 ScoringService（延遲初始化）
  ScoringService get _scoring =>
      _scoringService ??
      ScoringService(
        analysisService: _analysisService,
        ruleEngine: _ruleEngine,
        analysisRepository: _analysisRepo,
      );

  /// 同一個 [UpdateService] 實例內的並發更新鎖
  ///
  /// 更新執行中時，後續呼叫共享同一個 Future 結果，避免重複 API 呼叫與
  /// DB 寫入競爭。
  ///
  /// ## ⚠️ 這是 instance 級、不是跨 isolate 級
  ///
  /// 背景 WorkManager 路徑（`headless_update_runner`）在**另一個 isolate**
  /// 用 `UpdateServiceFactory` 另建一整套服務圖，含自己的 [AppDatabase] 與
  /// 自己的 `ApiBudgetTracker`（後者的 docstring 自承 process-local、
  /// 「新 isolate 等於 reset」）。此欄位對那條路徑**完全無效**。
  ///
  /// 目前不修，判定依據：
  /// - 背景任務只在 Android / iOS 註冊（`background_update_service.dart`
  ///   的 `Platform.isAndroid || Platform.isIOS`），**macOS 不存在此路徑**
  /// - iOS 上要碰撞需背景任務（15:00）與前景冷啟動同時發生，且冷啟動
  ///   gate 的兩個條件（距上次成功 ≥6h、距上次嘗試 ≥60min）皆通過
  /// - 跨 isolate 互斥需引入檔案鎖或 DB lock 表，兩者都帶新的失效模式
  ///   （isolate 被 OS 殺掉後鎖殘留），代價與風險不成比例
  ///
  /// 若日後背景路徑擴及 macOS，或觀察到 API 配額異常消耗 / 當日分析被
  /// 重複 clear-then-write，須重新評估。
  Completer<UpdateResult>? _activeUpdate;

  /// 執行完整每日更新流程
  ///
  /// 若已有更新正在執行，會等待並回傳該更新的結果，不重複執行。
  Future<UpdateResult> runDailyUpdate({
    DateTime? forDate,
    bool force = false,
    UpdateProgressCallback? onProgress,
  }) async {
    // 已有更新在執行中 → 共享結果，避免重複 API 呼叫
    if (_activeUpdate != null) {
      AppLogger.info('UpdateService', '更新已在執行中，等待現有結果');
      return _activeUpdate!.future;
    }

    final completer = Completer<UpdateResult>();
    _activeUpdate = completer;
    // ignore(2026-07-30 審查):無併發等待者時 completer.future 沒有
    // listener;_executeUpdate 在 try 之前就可能拋(createUpdateRun DB
    // I/O),completeError 會讓同一個錯誤除了 rethrow 給 caller 外,再以
    // unhandled async error 打進 zone handler(重複且無 context)。
    completer.future.ignore();

    try {
      final result = await _executeUpdate(
        forDate: forDate,
        force: force,
        onProgress: onProgress,
      );
      completer.complete(result);
      return result;
    } catch (e, s) {
      completer.completeError(e, s);
      rethrow;
    } finally {
      _activeUpdate = null;
    }
  }

  /// 實際執行更新邏輯（由 [runDailyUpdate] 的鎖保護）
  Future<UpdateResult> _executeUpdate({
    DateTime? forDate,
    bool force = false,
    UpdateProgressCallback? onProgress,
  }) async {
    var targetDate = forDate ?? _clock.now();

    // 智慧回溯：若為預設「現在」但非交易日，自動回溯至最近交易日
    if (forDate == null && !TaiwanCalendar.isTradingDay(targetDate)) {
      final lastTradingDay = TaiwanCalendar.getPreviousTradingDay(targetDate);
      AppLogger.info(
        'UpdateService',
        '非交易日 ($targetDate)，自動調整至上個交易日: $lastTradingDay',
      );
      targetDate = lastTradingDay;
    }

    final normalizedDate = DateContext.normalize(targetDate);
    // 起手 RUNNING(2026-07-30):app 中途被殺時遺留的 row 由 DB beforeOpen
    // 的 failOrphanRunningRuns 收斂成 FAILED,與「完成但部分失敗」的
    // PARTIAL 得以區分。
    final runId = await _db.createUpdateRun(
      normalizedDate,
      UpdateStatus.running.code,
    );

    final result = UpdateResult(date: normalizedDate);
    final ctx = _UpdateContext(
      targetDate: normalizedDate,
      runId: runId,
      result: result,
      force: force,
      onProgress: onProgress,
    );

    try {
      // 步驟 1：檢查是否為交易日
      onProgress?.call(1, 10, '檢查交易日');
      if (!force && !TaiwanCalendar.isTradingDay(targetDate)) {
        result.skipped = true;
        result.message = '非交易日，跳過更新';
        await _db.finishUpdateRun(
          runId,
          UpdateStatus.success.code,
          message: result.message,
        );
        return result;
      }

      // 步驟 1.5：強制更新時清理無效資料
      if (force) {
        await _cleanupInvalidData(onProgress);
      }

      // 步驟 2：更新股票清單
      await _syncStockList(ctx, targetDate);

      // 步驟 3-3.5：同步價格（含日期校正）+ 歷史資料
      await _syncPricesAndHistory(ctx);

      // 步驟 3.8-5：大盤指數、TDCC、法人、籌碼、基本面、新聞（互相獨立，並行執行）
      ctx.reportProgress(4, 10, '取得法人與基本面資料');
      await (
        _syncAuxiliaryData(ctx),
        _syncInstitutionalData(ctx),
        _syncMarketAndFundamentalData(ctx, ctx.normalizedDate),
        _syncNews(ctx),
      ).wait;

      // 步驟 6：篩選候選股票 + 補充上櫃資料
      ctx.reportProgress(6, 10, '篩選候選股票');
      final candidates = await _candidateSelector.filterCandidates(
        date: ctx.normalizedDate,
        marketCandidates: ctx.marketCandidates,
      );
      result.candidatesFound = candidates.length;
      await _syncOtcCandidatesData(ctx, candidates, ctx.normalizedDate);

      // 步驟 7-8：執行分析
      ctx.reportProgress(7, 10, '執行分析');
      final scoredStocks = await _analyzeStocks(
        ctx: ctx,
        candidates: candidates,
      );
      result.stocksAnalyzed = scoredStocks.length;

      // 步驟 9-10：完成
      //
      // **2026-06-21 退役舊推薦系統 Step 4**：daily_recommendation 已停寫。
      // 3-mode tab（起漲/強勢/回檔）從 daily_reason 即時聚合（scoring 已寫入
      // daily_reason）、不再產生 / 儲存 Top-20 推薦清單。
      ctx.onProgress?.call(9, 10, '完成分析');
      ctx.onProgress?.call(10, 10, '完成');
      // 步驟 10+: 三個後處理。**必須在 _finishUpdate 之前**——後者依
      // `result.errors` 決定 update_run 狀態並設 `result.success = true`，
      // 跑在它之後等於這三步的失敗永遠反映不到狀態上（finding #23）。
      //
      // 維持 await：docstring 曾自承「非阻塞」，但 background WorkManager
      // 路徑若不 await，isolate 可能在跑完前被 OS 殺掉；foreground 從 user
      // 角度本來就是等整個 update 跑完才看到結果。
      //
      // fail-safe 的語意是「不中斷流程」，不是「不留下痕跡」——三者皆
      // 捕捉例外後 recordError，不 rethrow。
      await _updateRuleAccuracyStatsFailSafe(ctx);
      await _snapshotNewsMentionsFailSafe(ctx);
      await _checkPinnedThesesFailSafe(ctx);
      await _reportZeroingImpactFailSafe(ctx);
      // 在 _finishUpdate 之前：那裡的 _fetchAlertPrices 會為「有啟用中提醒」
      // 的股票補價格資料，順序顛倒的話今天新設的那批會少一天的資料。
      await _refreshTrailingAlertsFailSafe(ctx);

      await _finishUpdate(ctx, result);

      return result;
    } catch (e, st) {
      // 頂層 catch 必記 stack trace(2026-07-29 審查):這是最嚴重的失敗
      // 類別(整輪中止),卻曾是唯一不落 log 的路徑——事後只剩 e.toString()
      AppLogger.error('UpdateService', '更新失敗(未捕捉例外)', e, st);
      result.success = false;
      result.message = '更新失敗: $e';
      result.recordError(e.toString(), e);
      await _db.finishUpdateRun(
        runId,
        UpdateStatus.failed.code,
        message: result.message,
      );
      return result;
    }
  }

  /// 負證據歸零的每日觀測(2026-07-29 三態 lookup 配套,fail-safe)。
  ///
  /// 「如果它沒生效,我怎麼知道?」——每日更新 log 歸零列數/檔數/因歸零
  /// 跌出訊號層的檔數,對照離線重放的預期量級(日均 ~29 檔)。registry
  /// 未載入或歸零集為空時靜默跳過(機制未啟用,無可觀測)。
  Future<void> _reportZeroingImpactFailSafe(_UpdateContext ctx) async {
    try {
      final zeroed = CalibratedScoresRegistry.instance.zeroedShortSnapshot();
      if (zeroed.isEmpty) return;
      final rows = await _db.getAllReasonsForDate(ctx.normalizedDate);
      final impact = computeZeroingImpact(
        rows: rows,
        zeroedRules: zeroed,
        hardcodedScores: {for (final r in ReasonType.values) r.code: r.score},
      );
      AppLogger.info(
        'UpdateService',
        '負證據歸零: ${impact.zeroedRows} 列/${impact.zeroedStocks} 檔歸零 '
            '→ ${impact.droppedStocks} 檔跌出訊號層',
      );
      if (impact.addedStocks > 0) {
        // 方向 gate 下結構上不可能——非零代表歸零集混入負分規則
        AppLogger.warning(
          'UpdateService',
          '歸零 invariant 破壞: ${impact.addedStocks} 檔因歸零「新進」訊號層',
        );
      }
    } catch (e) {
      AppLogger.warning('UpdateService', '歸零影響統計失敗(fail-safe)', e);
    }
  }

  /// PARTIAL run 的持久化訊息:含失敗步驟細節,截斷至 500 字。
  ///
  /// 2026-07-29 審查:僅寫死「部分更新成功」時,update_run 表事後無法
  /// 重建故障現場(7/28「誤判更新掛死」事件中 message 空白即為此病)。
  static String _partialRunMessage(List<String> errors) {
    final joined = '部分更新成功(${errors.length} 項失敗): ${errors.join('; ')}';
    return joined.length <= 500 ? joined : '${joined.substring(0, 497)}…';
  }

  // ==================================================
  // 私有輔助方法
  // ==================================================

  Future<void> _cleanupInvalidData(UpdateProgressCallback? onProgress) async {
    onProgress?.call(1, 10, '清理無效資料');
    try {
      final cleanupResult = await _db.cleanupInvalidStockCodes();
      final totalCleaned = cleanupResult.values.fold(0, (a, b) => a + b);
      if (totalCleaned > 0) {
        AppLogger.info(
          'UpdateService',
          '已清理 $totalCleaned 筆無效資料: $cleanupResult',
        );
      }
    } catch (e) {
      AppLogger.warning('UpdateService', '清理無效資料失敗', e);
    }
  }

  Future<void> _syncStockList(_UpdateContext ctx, DateTime targetDate) async {
    ctx.onProgress?.call(2, 10, '更新股票清單');
    // 2026-08-01 實機(force+額度耗盡):此前是唯一沒有 try/catch 的
    // pipeline 步驟——syncer 按慣例 rethrow 的 RateLimitException 直接
    // 「未捕捉例外」炸整輪。週一首輪額度總是新鮮,潛伏至 force 連跑
    // 才引爆。與 sibling 步驟同骨架:限流標 rateLimitedAbort 續走。
    try {
      final stockResult = await _stockListSyncer.smartSync(
        date: targetDate,
        force: ctx.force,
      );
      ctx.result.stocksUpdated = stockResult.stockCount;
      if (!stockResult.success && stockResult.error != null) {
        ctx.result.errors.add('股票清單更新失敗: ${stockResult.error}');
      }
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '股票清單同步失敗 (rate limit)', e);
      ctx.result.recordError('股票清單同步失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '股票清單同步失敗', e);
      ctx.result.recordError('股票清單同步失敗: $e', e);
    }
  }

  Future<void> _syncPricesAndHistory(_UpdateContext ctx) async {
    ctx.onProgress?.call(3, 10, '取得今日價格');
    final originalDate = ctx.normalizedDate;
    final correctedDate = await _syncDailyPrices(ctx, ctx.normalizedDate);
    ctx.normalizedDate = correctedDate;

    // 若日期被校正，更新 UpdateRun 的 runDate
    if (correctedDate != originalDate) {
      await _db.updateRunDate(ctx.runId, correctedDate);
      ctx.result.date = correctedDate;
      AppLogger.info(
        'UpdateService',
        '日期校正: $originalDate -> $correctedDate，已更新 UpdateRun',
      );
    }

    ctx.reportProgress(4, 10, '取得歷史資料');
    await _syncHistoricalData(ctx);
  }

  Future<void> _syncAuxiliaryData(_UpdateContext ctx) async {
    if (ctx.rateLimitedAbort) return;
    if (_marketIndexSyncer != null) {
      try {
        await _marketIndexSyncer.sync();
      } on RateLimitException catch (e) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning('UpdateService', '大盤指數同步失敗 (rate limit)', e);
        ctx.result.recordError('大盤指數同步失敗 (rate limit): $e', e);
      } catch (e) {
        AppLogger.warning('UpdateService', '大盤指數同步失敗', e);
        ctx.result.recordError('大盤指數同步失敗: $e', e);
      }
    }

    if (ctx.rateLimitedAbort) return;
    if (_tdccHoldingSyncer != null) {
      try {
        await _tdccHoldingSyncer.sync();
      } on RateLimitException catch (e) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning('UpdateService', 'TDCC 股權分散表同步失敗 (rate limit)', e);
        ctx.result.recordError('TDCC 股權分散表同步失敗 (rate limit): $e', e);
      } catch (e) {
        AppLogger.warning('UpdateService', 'TDCC 股權分散表同步失敗', e);
        ctx.result.recordError('TDCC 股權分散表同步失敗: $e', e);
      }
    }

    if (ctx.rateLimitedAbort) return;
    if (_dividendSyncer != null) {
      try {
        final divResult = await _dividendSyncer.sync();
        if (divResult.dividendsUpserted > 0 ||
            divResult.meetingEventsCreated > 0) {
          AppLogger.info(
            'UpdateService',
            '股利同步: ${divResult.dividendsUpserted} 筆股利, '
                '${divResult.meetingEventsCreated} 筆股東會',
          );
        }
        // DividendSyncer 內部以 per-source catch 收集 generic 失敗，
        // 不 throw — 必須讀取 errors 轉發，否則對使用者靜默
        for (final err in divResult.errors) {
          ctx.result.errors.add('股利/股東會同步失敗: $err');
        }
      } on RateLimitException catch (e) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning('UpdateService', '股利/股東會同步失敗 (rate limit)', e);
        ctx.result.recordError('股利/股東會同步失敗 (rate limit): $e', e);
      } catch (e) {
        AppLogger.warning('UpdateService', '股利/股東會同步失敗', e);
        ctx.result.recordError('股利/股東會同步失敗: $e', e);
      }
    }

    if (ctx.rateLimitedAbort) return;
    if (_insiderTransferSyncer != null) {
      try {
        final transferCount = await _insiderTransferSyncer.sync();
        if (transferCount > 0) {
          AppLogger.info('UpdateService', '內部人轉讓同步: $transferCount 筆');
        }
      } on RateLimitException catch (e) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning('UpdateService', '內部人轉讓同步失敗 (rate limit)', e);
        ctx.result.recordError('內部人轉讓同步失敗 (rate limit): $e', e);
      } catch (e) {
        AppLogger.warning('UpdateService', '內部人轉讓同步失敗', e);
        ctx.result.recordError('內部人轉讓同步失敗: $e', e);
      }
    }
    // 季報快照(t187ap06 兩市場,12 個免額度 openapi 端點):每次更新都
    // 同步——公布期端點逐日長、平時回最後完整季,總覽頁因此恆有資料
    if (ctx.rateLimitedAbort) return;
    if (_quarterlyReportSyncer != null) {
      try {
        final reportCount = await _quarterlyReportSyncer.sync();
        if (reportCount > 0) {
          AppLogger.info('UpdateService', '季報同步: $reportCount 筆');
        }
      } on RateLimitException catch (e) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning('UpdateService', '季報同步失敗 (rate limit)', e);
        ctx.result.recordError('季報同步失敗 (rate limit): $e', e);
      } catch (e) {
        AppLogger.warning('UpdateService', '季報同步失敗', e);
        ctx.result.recordError('季報同步失敗: $e', e);
      }
    }
  }

  Future<void> _syncNews(_UpdateContext ctx) async {
    // 修前是唯一沒有 rateLimitedAbort guard 的步驟,且 errors.addAll 繞過
    // recordError 的限流偵測——與 NewsSyncer 的裸 catch 疊加成熔斷盲區
    if (ctx.rateLimitedAbort) return;
    try {
      final newsResult = await _newsSyncer.syncAndCleanup();
      ctx.result.newsUpdated = newsResult.itemsAdded;
      ctx.result.errors.addAll(newsResult.errors);
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '新聞同步失敗 (rate limit)', e);
      ctx.result.recordError('新聞同步失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '新聞同步失敗', e);
      ctx.result.recordError('新聞同步失敗: $e', e);
    }
  }

  Future<DateTime> _syncDailyPrices(
    _UpdateContext ctx,
    DateTime normalizedDate,
  ) async {
    try {
      final syncResult = await _priceRepo.syncAllPricesForDate(
        normalizedDate,
        force: ctx.force,
      );

      // 日期校正
      var dateRolledBack = false;
      if (syncResult.dataDate != null) {
        final dataDate = DateContext.normalize(syncResult.dataDate!);
        if (dataDate.year != normalizedDate.year ||
            dataDate.month != normalizedDate.month ||
            dataDate.day != normalizedDate.day) {
          normalizedDate = dataDate;
          dateRolledBack = true;
        }
      }

      ctx.result.pricesUpdated = syncResult.count;
      ctx.marketCandidates = syncResult.candidates;

      // 缺整個市場的當日價格必須可見：來源失敗被 safeAwait 吞成空清單，
      // 只有兩市場皆空才會拋錯；僅單一市場掛掉時流程照常走完，規則層仍以
      // `prices.last` 當「今日」，等於拿昨日 K 棒算今日訊號、UI 綠燈零警告。
      //
      // 兩個不回報的情況：
      // - 快取路徑（skipped）：不是抓取行為。
      // - **日期已回滾**：交易日盤前/盤中 TPEx 當日檔未發布（空），而 TWSE
      //   端點自動回上一交易日 → dataDate 早於目標日。此時「今日零筆」是預期，
      //   且回滾後那天的資料 DB 早已完整；不排除會讓每個交易日早盤都假 partial，
      //   造成警告疲勞、真正的缺市場反而被淹沒。
      if (!syncResult.skipped &&
          !dateRolledBack &&
          syncResult.emptyMarkets.isNotEmpty) {
        final markets = syncResult.emptyMarkets.join('/');
        AppLogger.warning('UpdateService', '價格同步缺市場: $markets');
        ctx.result.recordError('$markets 當日價格為零筆，評分資料不完整');
      }
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '價格同步失敗 (rate limit)', e);
      ctx.result.recordError('價格資料更新失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '價格同步失敗', e);
      ctx.result.recordError('價格資料更新失敗: $e', e);
    }
    return normalizedDate;
  }

  Future<void> _syncHistoricalData(_UpdateContext ctx) async {
    if (ctx.rateLimitedAbort) return;
    try {
      final watchlist = await _db.getWatchlist();
      final historyResult = await _historicalPriceSyncer.syncHistoricalPrices(
        date: ctx.normalizedDate,
        watchlistSymbols: watchlist.map((w) => w.symbol).toList(),
        popularStocks: _popularStocks,
        marketCandidates: ctx.marketCandidates,
        onProgress: (msg) => ctx.reportProgress(4, 10, msg),
      );
      if (historyResult.syncedCount > 0) {
        ctx.result.pricesUpdated += historyResult.syncedCount;
      }
      if (historyResult.marketDayRows > 0) {
        ctx.result.pricesUpdated += historyResult.marketDayRows;
      }
      // syncer 撞限流時**不 rethrow**（已抓到的歷史資料要保留），所以下面
      // 的 `on RateLimitException` 接不到——必須改從 result 判讀。否則
      // rateLimitedAbort 與 hasRateLimitError 雙雙翻不起來，限流被降級成
      // 一般失敗，UI 的限流專屬提示永遠不亮。
      if (historyResult.rateLimited) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning(
          'UpdateService',
          '歷史資料更新失敗 (rate limit)',
          historyResult.rateLimitError,
        );
        ctx.result.recordError(
          '歷史資料更新失敗 (rate limit): '
          '${historyResult.failedSymbols.length} 檔未同步',
          historyResult.rateLimitError,
        );
      } else if (historyResult.hasErrors) {
        ctx.result.errors.add(
          '歷史資料同步失敗 (${historyResult.failedSymbols.length} 檔)',
        );
      }
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '歷史資料更新失敗 (rate limit)', e);
      ctx.result.recordError('歷史資料更新失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '歷史資料更新失敗', e);
      ctx.result.recordError('歷史資料更新失敗: $e', e);
    }
  }

  Future<void> _syncInstitutionalData(_UpdateContext ctx) async {
    if (ctx.rateLimitedAbort) return;
    final syncer = _institutionalSyncer;
    if (syncer == null) return;

    try {
      final instResult = await syncer.syncInstitutionalData(
        date: ctx.normalizedDate,
        force: ctx.force,
        // 強制同步把回補窗拉深（~62 交易日）補足 surge/streak/Z-score 所需
        // 歷史深度；已完整的天會被 per-day 檢查跳過（非破壞式、可續傳）。
        // 日常更新維持淺回補保持快速。
        backfillDays: ctx.force
            ? ApiConfig.institutionalForceBackfillDays
            : ApiConfig.institutionalDailyBackfillDays,
        onProgress: (msg) => ctx.reportProgress(4, 10, msg),
      );
      ctx.result.institutionalUpdated = instResult.estimatedCount;
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '法人資料更新失敗 (rate limit)', e);
      ctx.result.recordError('法人資料更新失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '法人資料更新失敗', e);
      ctx.result.recordError('法人資料更新失敗: $e', e);
    }
  }

  Future<void> _syncMarketAndFundamentalData(
    _UpdateContext ctx,
    DateTime normalizedDate,
  ) async {
    if (ctx.rateLimitedAbort) return;
    // 方法內共享自選清單，避免重複查詢。
    // 包 try(2026-07-30 審查):此行在步驟 4 的 record .wait 分支內,
    // 若裸拋 DatabaseException 會被包成 ParallelWaitError 直穿頂層 catch,
    // message 不可讀且 RateLimitException 型別判定失效。讀不到自選就退化
    // 為空優先集,其餘同步照跑。
    List<WatchlistEntry> watchlist;
    try {
      watchlist = await _db.getWatchlist();
    } catch (e) {
      AppLogger.warning('UpdateService', '自選清單讀取失敗,以空集合續跑', e);
      ctx.result.recordError('自選清單讀取失敗: $e', e);
      watchlist = const [];
    }
    final watchlistSymbols = watchlist.map((w) => w.symbol).toSet();

    await _syncDayTradingAndMarginData(ctx, normalizedDate, watchlistSymbols);
    if (ctx.rateLimitedAbort) return;
    await _syncFundamentalValuationAndRevenue(ctx, normalizedDate);
    if (ctx.rateLimitedAbort) return;
    await _syncBalanceSheetAndEps(ctx, normalizedDate, watchlistSymbols);
    if (ctx.rateLimitedAbort) return;
    await _syncKillerFeatures(ctx);
  }

  /// 步驟 4.5：籌碼資料（當沖、融資、持股）
  Future<void> _syncDayTradingAndMarginData(
    _UpdateContext ctx,
    DateTime normalizedDate,
    Set<String> watchlistSymbols,
  ) async {
    if (ctx.rateLimitedAbort) return;
    final marketUpdater = _marketDataUpdater;
    if (marketUpdater == null) return;

    try {
      // 硬寫 force: true 是刻意：當沖/融資/融券 batch API 每次都重抓全市場
      // (free TWSE/TPEx Open Data，配額不是 bottleneck)，新鮮度檢查反而
      // 浪費一次 DB count query。比 `ctx.force` 更積極、與本層 daily
      // pipeline 設計一致。若未來想跑 dry-run / replay 不刷新，應把這個
      // 決策移進 `MarketDataUpdater` 內部常數而非從 ctx 傳。
      final marketResult = await marketUpdater.syncMarketWideData(
        date: normalizedDate,
        force: true,
      );

      // 同步自選清單和熱門股的詳細籌碼
      final symbolsForMarketData = <String>{
        ...watchlistSymbols,
        ..._popularStocks,
      }.toList();

      final syncedCount = await marketUpdater.syncSymbolsMarketData(
        symbols: symbolsForMarketData,
        date: normalizedDate,
      );

      final marginLabel = marketResult.marginCount == null
          ? '已快取'
          : '${marketResult.marginCount}';
      final backfillLabel = marketResult.backfilledDays > 0
          ? ', 回補缺漏日=${marketResult.backfilledDays}'
          : '';
      AppLogger.info(
        'UpdateService',
        '步驟 4.5: 當沖=${marketResult.dayTradingCount}, '
            '融資=$marginLabel, '
            '外資持股(全市場)=${marketResult.foreignShareholdingCount}, '
            '持股(自選+熱門)=$syncedCount$backfillLabel',
      );
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '籌碼資料更新失敗 (rate limit)', e);
      ctx.result.recordError('籌碼資料更新失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '籌碼資料更新失敗', e);
      ctx.result.recordError('籌碼資料更新失敗: $e', e);
    }
  }

  /// 步驟 4.6：基本面資料（估值 + 營收 + 上櫃自選補充）
  Future<void> _syncFundamentalValuationAndRevenue(
    _UpdateContext ctx,
    DateTime normalizedDate,
  ) async {
    if (ctx.rateLimitedAbort) return;
    final fundamentalSyncer = _fundamentalSyncer;
    if (fundamentalSyncer == null) return;

    try {
      final fundResult = await fundamentalSyncer.syncMarketWideFundamentals(
        date: normalizedDate,
        force: ctx.force,
      );
      // FundamentalSyncer 內部以 per-call catch 收集 generic 失敗（不
      // throw）— 必須讀取 errors 轉發，否則對使用者靜默
      for (final err in fundResult.errors) {
        ctx.result.errors.add('基本面同步失敗: $err');
      }

      // 補充上櫃自選股
      if (!ctx.rateLimitedAbort) {
        try {
          final otcResult = await fundamentalSyncer
              .syncOtcWatchlistFundamentals(
                date: normalizedDate,
                force: ctx.force,
              );
          for (final err in otcResult.errors) {
            ctx.result.errors.add('基本面同步失敗: $err');
          }
        } on RateLimitException catch (e) {
          ctx.rateLimitedAbort = true;
          AppLogger.warning('UpdateService', '上櫃自選基本面補充失敗 (rate limit)', e);
          ctx.result.recordError('上櫃自選基本面補充失敗 (rate limit): $e', e);
        } catch (e) {
          AppLogger.warning('UpdateService', '上櫃自選基本面補充失敗', e);
          ctx.result.recordError('上櫃自選基本面補充失敗: $e', e);
        }
      }

      // 自選股營收歷史回補（「近 3 月均年增」所需；冪等，穩態零 API 呼叫）
      if (!ctx.rateLimitedAbort) {
        try {
          await fundamentalSyncer.syncWatchlistRevenueHistory();
        } on RateLimitException catch (e) {
          ctx.rateLimitedAbort = true;
          AppLogger.warning('UpdateService', '自選營收歷史回補失敗 (rate limit)', e);
          ctx.result.recordError('自選營收歷史回補失敗 (rate limit): $e', e);
        } catch (e) {
          AppLogger.warning('UpdateService', '自選營收歷史回補失敗', e);
          ctx.result.recordError('自選營收歷史回補失敗: $e', e);
        }
      }

      final revenueLabel = fundResult.revenueCached
          ? '已快取'
          : '${fundResult.revenueCount}';
      AppLogger.info(
        'UpdateService',
        '步驟 4.6: 估值=${fundResult.valuationCount}, 營收=$revenueLabel',
      );
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '基本面資料更新失敗 (rate limit)', e);
      ctx.result.recordError('基本面資料更新失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '基本面資料更新失敗', e);
      ctx.result.recordError('基本面資料更新失敗: $e', e);
    }
  }

  /// 步驟 4.7：財報資料（EPS + 資產負債表）
  Future<void> _syncBalanceSheetAndEps(
    _UpdateContext ctx,
    DateTime normalizedDate,
    Set<String> watchlistSymbols,
  ) async {
    if (ctx.rateLimitedAbort) return;
    final fundamentalSyncer = _fundamentalSyncer;
    if (fundamentalSyncer == null) return;

    try {
      // 全市場資產負債表先跑(2026-08-16):免費官方端點一次拿上市 968 +
      // 上櫃 859 檔,寫入後下面 syncBalanceSheets 的 per-statementType 新鮮度
      // 檢查會提早 return、不打 FinMind。財報是額度的唯一瓶頸(129 檔 × 2
      // = 258 次/輪,實測當天因額度保留只跑了 10 檔),這一步砍掉其中一半。
      var marketWideBs = 0;
      try {
        marketWideBs = await fundamentalSyncer.syncMarketWideBalanceSheets();
      } on RateLimitException {
        rethrow;
      } catch (e) {
        AppLogger.warning('UpdateService', '全市場資產負債表同步失敗,退回逐檔', e);
      }

      // 兩市場統一額度配額(2026-08-05 季報季修復):上市佇列原無額度
      // 守衛——「重跑 needy 為空」在季報季破產(全市場同時變 needy),
      // 單輪 488 次呼叫吃掉 82% 小時額度。額度感知從上櫃推廣到全財報:
      // 上市先拿、上櫃吃剩,總支出保證留 reserve 給其餘步驟與下一輪。
      final usage = _finMindClient?.hourlyUsage;
      final quota = financialQuotaForBudget(usage: usage);
      if (usage != null &&
          (quota.twse < ApiConfig.financialSyncMaxCandidates ||
              quota.otc < ApiConfig.otcFinancialSyncMaxCount)) {
        AppLogger.info(
          'UpdateService',
          '財報回填縮量: 上市 ${quota.twse} 檔、上櫃 ${quota.otc} 檔 '
              '(FinMind 已用 ${usage.used}/${usage.budget},保留 '
              '${ApiConfig.financialBackfillReserve})',
        );
      }
      final targetSymbols = quota.twse == 0
          ? const <String>[]
          : selectFinancialSyncTargets(
              prioritySymbols: {...watchlistSymbols, ..._popularStocks},
              marketCandidates: ctx.marketCandidates,
              maxCandidates: quota.twse,
            );
      // 上櫃專屬回填佇列(獨立於上市名額,理由見 selectOtcFinancialBacklog)
      final otcBacklog = quota.otc == 0
          ? const <String>[]
          : await fundamentalSyncer.selectOtcFinancialBacklog(
              candidates: ctx.marketCandidates,
              limit: quota.otc,
            );
      final allTargets = {...targetSymbols, ...otcBacklog}.toList();
      if (allTargets.isNotEmpty) {
        // 損益表與資產負債表無相依性，平行執行以縮短等待時間。
        //
        // **必須用 `Future.wait` 而非 record 的 `.wait`**：後者在任一支失敗時
        // 拋 `ParallelWaitError` 包住底層例外，下面的 `on RateLimitException`
        // 就永遠接不到 —— 而這是全流程 FinMind 用量最大的一步（2026-07-27
        // 實測 338/384 = 88%），止血旗標死在這裡最不能接受。
        // 實跑驗證：record `.wait` → ParallelWaitError<(int?, int?), ...>；
        // `Future.wait` → 原型 RateLimitException，且同樣等所有 future 結束。
        final counts = await Future.wait<int?>([
          fundamentalSyncer.syncFinancialStatements(symbols: allTargets),
          fundamentalSyncer.syncBalanceSheets(symbols: allTargets),
        ]);
        final epsCount = counts[0];
        final bsCount = counts[1];
        final bsLabel = bsCount == null ? '已快取' : '$bsCount';
        AppLogger.info(
          'UpdateService',
          '步驟 4.7: 損益=$epsCount, 資負=$bsLabel, '
              '全市場資負(免費)=$marketWideBs '
              '(${allTargets.length} 檔，其中上櫃回填 ${otcBacklog.length})',
        );
      }
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '財報資料同步失敗 (rate limit)', e);
      ctx.result.recordError('財報資料同步失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '財報資料同步失敗', e);
      ctx.result.recordError('財報資料同步失敗: $e', e);
    }
  }

  /// 挑選財報同步的目標股票（自選＋熱門優先，其餘依候選順序補到上限）。
  ///
  /// 抽成純函式以便單獨驗證配額分配——這段的正確性不在於「有沒有呼叫到
  /// syncer」，而在於**名額有沒有被用滿**，那需要對回傳清單本身斷言。
  /// 依剩餘 FinMind 額度決定本輪上櫃財報回填量（上限
  /// [ApiConfig.otcFinancialSyncMaxCount]）。
  ///
  /// 為什麼固定 100 不夠安全：回填佇列是最舊優先，**設計上保證每輪都選得出
  /// 100 檔完全無資料的上櫃股**（補完 1~100 名，下輪就換 101~200 名），
  /// 所以重跑不會變便宜 —— 這與上市那條（`_filterNeedingStatementSync` 讓
  /// 重跑時 needy 為空、零呼叫）性質相反。而 [ApiBudgetTracker] 是 app
  /// session 級單一實例 + sliding 1 小時，跨輪會累加。
  ///
  /// 2026-07-27 實測同一小時內兩輪：113 + 384 = 497/600，第三輪要再約 200
  /// → 約 700，破表。同檔 api_budget_tracker.dart:17 記著這事發生過
  /// （「加總打了 1125 calls，撞 hourly cap 整套 abort」）。
  ///
  /// [usage] 為 null（未掛 tracker）時回上限：**「量不到」不等於「沒額度」**，
  /// 當成 0 會讓沒有 tracker 的環境完全停掉回填。這與
  /// `FinMindClient.hourlyUsage` 刻意回 null 而非 0 是同一條原則。
  ///
  /// 只約束上櫃這條自己的用量。上市那條的
  /// [ApiConfig.financialSyncMaxCandidates] 維持不動——它先於本功能存在，
  /// 且重跑時 needy 為空，不是壓力來源。
  /// 財報回填的兩市場統一額度配額(2026-08-05 季報季修復)。
  ///
  /// affordable =(budget − used − [ApiConfig.financialBackfillReserve])÷2
  /// (每檔打損益+資負兩次);上市先拿(候選恆超上限,是覆蓋主力)、
  /// 上櫃吃剩餘。整點滿額度時上市拿滿 150、上櫃約 50——單輪財報支出
  /// 封頂 400,加其餘步驟 ~50 仍留 >150 給同小時的下一次手動更新;
  /// 額度耗至 reserve 內時兩市場歸零,更新數十秒完成且不再 402。
  ///
  /// [usage] null(未掛 tracker)回雙上限:「量不到」≠「沒額度」。
  @visibleForTesting
  static ({int twse, int otc}) financialQuotaForBudget({
    required ({int used, int budget})? usage,
  }) {
    if (usage == null) {
      return (
        twse: ApiConfig.financialSyncMaxCandidates,
        otc: ApiConfig.otcFinancialSyncMaxCount,
      );
    }
    final affordable =
        (usage.budget - usage.used - ApiConfig.financialBackfillReserve) ~/ 2;
    final twse = affordable.clamp(0, ApiConfig.financialSyncMaxCandidates);
    final otc = (affordable - twse).clamp(
      0,
      ApiConfig.otcFinancialSyncMaxCount,
    );
    return (twse: twse, otc: otc);
  }

  @visibleForTesting
  static int otcFinancialLimitForBudget({
    required ({int used, int budget})? usage,
    int maxLimit = ApiConfig.otcFinancialSyncMaxCount,
    int reserve = ApiConfig.otcFinancialBackfillReserve,
  }) {
    if (usage == null) return maxLimit;
    // 每檔要打損益表 + 資產負債表兩次
    final affordable = (usage.budget - usage.used - reserve) ~/ 2;
    return affordable.clamp(0, maxLimit);
  }

  @visibleForTesting
  static List<String> selectFinancialSyncTargets({
    required Set<String> prioritySymbols,
    required List<String> marketCandidates,
    int maxCandidates = ApiConfig.financialSyncMaxCandidates,
  }) {
    final remainingSlots = maxCandidates - prioritySymbols.length;
    return {
      ...prioritySymbols,
      if (remainingSlots > 0)
        // **ETF 過濾必須早於 take**：ETF 無財報，下游 fundamental_syncer
        // （:306 INCOME／:409 BALANCE）會濾掉它們，但被丟掉的名額不會由
        // 第 N+1 名遞補 → 名額空轉。與 3faea63 在 chip_anomaly_service
        // 立的同一條規則。
        //
        // 實測 2026-07-24：價格走快取路徑時候選順序退化為 symbol 升冪
        // （quickFilterCandidatesFromDb 不排序、DAO 無 ORDER BY），扣掉
        // 39 檔 priority 後**前 111 檔 100% 是 00 開頭 ETF**，那一輪等於
        // 沒有任何非自選股拿到新財報；而 update_run 72 次中約 89% 走快取路徑。
        //
        // priority（自選＋熱門）不套此過濾：使用者主動追蹤的 ETF 應留在
        // 清單裡，由下游自然跳過即可。
        ...marketCandidates
            .where(
              (s) =>
                  !prioritySymbols.contains(s) && !StockPatterns.isEtfCode(s),
            )
            .take(remainingSlots),
    }.toList();
  }

  /// 步驟 4.8：Killer Features 資料（警示、董監持股）
  Future<void> _syncKillerFeatures(_UpdateContext ctx) async {
    if (ctx.rateLimitedAbort) return;
    final marketUpdater = _marketDataUpdater;
    if (marketUpdater == null) return;

    try {
      final killerResult = await marketUpdater.syncKillerFeaturesData(
        force: ctx.force,
      );

      AppLogger.info(
        'UpdateService',
        '步驟 4.8: 警示=${killerResult.warningCount}, 董監=${killerResult.insiderCount}',
      );

      // `KillerFeaturesSyncResult` 的兩個 error 欄位過去零消費點——欄位是死的。
      // 警示不是「額外功能」：處置股是三模式榜的**硬性宇宙排除**（-50 分 +
      // droppedDisposal），缺名單是 fail-open——危險股照常上榜、風險徽章不亮，
      // 而使用者看到的是綠燈。必須讓 run 降級為 partial。
      if (killerResult.warningError != null) {
        ctx.result.recordError(
          '警示（注意/處置）資料同步失敗: ${killerResult.warningError}',
          killerResult.warningError,
        );
      }
      if (killerResult.insiderError != null) {
        ctx.result.recordError(
          '董監持股資料同步失敗: ${killerResult.insiderError}',
          killerResult.insiderError,
        );
      }
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning(
        'UpdateService',
        'Killer Features 資料更新失敗 (rate limit)',
        e,
      );
      ctx.result.recordError('Killer Features (rate limit): $e', e);
    } catch (e) {
      // 過去這裡註記「額外功能不影響主流程」故不記 errors，但該假設不成立：
      // 警示線失敗會讓處置股漏掉硬排除。且 warning_repository 對每個來源
      // `on NetworkException { rethrow; }`，而 market_client_mixin 把所有
      // DioException（4xx/5xx/timeout/連線錯誤）都轉成 NetworkException——
      // 也就是**最常見的失敗會直接穿透到這裡**，過去一個字都不會留下。
      AppLogger.warning('UpdateService', 'Killer Features 資料更新失敗', e);
      ctx.result.recordError('Killer Features（警示/董監）資料更新失敗: $e', e);
    }
  }

  Future<void> _syncOtcCandidatesData(
    _UpdateContext ctx,
    List<String> candidates,
    DateTime normalizedDate,
  ) async {
    if (ctx.rateLimitedAbort) return;
    if (candidates.isEmpty) return;

    try {
      ctx.reportProgress(6, 10, '補充上櫃資料');

      var fundResult = const FundamentalSyncResult(
        valuationCount: 0,
        revenueCount: 0,
      );
      var marketResult = const OtcMarketDataResult(
        dayTradingCount: 0,
        shareholdingCount: 0,
      );

      final fundamentalSyncer = _fundamentalSyncer;
      if (fundamentalSyncer != null) {
        fundResult = await fundamentalSyncer.syncOtcCandidatesFundamentals(
          candidates: candidates,
          date: normalizedDate,
        );
        for (final err in fundResult.errors) {
          ctx.result.errors.add('上櫃候選基本面同步失敗: $err');
        }
      }

      final marketUpdater = _marketDataUpdater;
      if (marketUpdater != null) {
        marketResult = await marketUpdater.syncOtcCandidatesMarketData(
          candidates: candidates,
          date: normalizedDate,
        );
      }

      // 這裡加總的是**寫入筆數**，不是 API 呼叫數。上櫃估值與營收都走 TPEx
      // OpenAPI 的單次批次端點（見 FundamentalRepository 的「API calls: 1」），
      // 只有外資持股是 per-symbol。
      //
      // 曾標為「API ~N calls」：2026-07-26 實測一次更新報 94 calls，真實
      // API 呼叫約 2 次，**高報 47 倍**。高報的方向特別有害——會讓人誤以為
      // 配額已緊而不敢調高 `maxSyncCount`，而 FinMind 配額正是上櫃資料
      // 涵蓋率上不去的瓶頸（估值 249/904、外資持股全市場僅 147 檔）。
      //
      // 真實用量在 `ApiBudgetTracker`（per-vendor、sliding 1hr、只掛
      // FinMindClient）。**已於 2026-07-27 接出來**：FinMindClient.hourlyUsage
      // → `_finishUpdate` 的「完成」行會印 `FinMind=used/budget (近 1hr)`。
      // 下方這些 count 仍是寫入筆數（非 API 呼叫數），兩者不可混看。
      final syncedRows = fundResult.total + marketResult.total;
      if (syncedRows > 0) {
        AppLogger.info(
          'UpdateService',
          '步驟 6.5: 上櫃 (${marketResult.syncedCandidates}/${marketResult.totalCandidates} 檔): '
              '估值=${fundResult.valuationCount}, 營收=${fundResult.revenueCount}, '
              '當沖=${marketResult.dayTradingCount}, 持股=${marketResult.shareholdingCount} '
              '(寫入 $syncedRows 筆)',
        );
      }
    } on RateLimitException catch (e) {
      ctx.rateLimitedAbort = true;
      AppLogger.warning('UpdateService', '上櫃資料補充失敗 (rate limit)', e);
      ctx.result.recordError('上櫃資料補充失敗 (rate limit): $e', e);
    } catch (e) {
      AppLogger.warning('UpdateService', '上櫃資料補充失敗', e);
      ctx.result.recordError('上櫃資料補充失敗: $e', e);
    }
  }

  Future<List<ScoredStock>> _analyzeStocks({
    required _UpdateContext ctx,
    required List<String> candidates,
  }) async {
    final batchData = await _batchDataLoader.loadBatchData(
      ctx.normalizedDate,
      candidates,
    );

    // 自選股即使當日零訊號也要留下分析列——畫面上一定看得到那張卡，沒有列
    // 就整張空白（無評分、無標籤、無趨勢），使用者分不出「今日沒訊號」與
    // 「壞掉」。實機 2059 川湖連續四天全空。理由與範圍見
    // [ScoringIsolateInput.watchlistSymbols]。
    final watchlistSymbols = (await _db.getWatchlist())
        .map((w) => w.symbol)
        .toList();

    // 當日舊資料的清除已移入 ScoringService 的寫入 transaction
    // （clear-then-write 原子化，避免中斷留下當日分析真空）
    ctx.reportProgress(7, 10, '分析中 (${candidates.length} 檔)');
    final scoredStocks = await _scoring.scoreStocksInIsolate(
      candidates: candidates,
      date: ctx.normalizedDate,
      batchData: batchData,
      watchlistSymbols: watchlistSymbols,
    );

    AppLogger.info('UpdateService', '步驟 7-8: 評分 ${scoredStocks.length} 檔');
    return scoredStocks;
  }

  Future<void> _finishUpdate(_UpdateContext ctx, UpdateResult result) async {
    final dateStr = '${ctx.normalizedDate.month}/${ctx.normalizedDate.day}';
    // FinMind 是唯一有硬額度的 vendor（free tier 600/hr），也是唯一被
    // per-symbol 消耗的來源（getFinancialStatements）。印**真實**用量而非
    // 估算：2026-07-26 日誌曾報 94 calls、真實約 2 次（高報 47 倍），
    // 2026-07-27 靜態讀 code 追查上櫃財報覆蓋率時又連續三次估錯誰在吃額度。
    // 高報會讓人以為配額已緊而不敢調高上櫃相關上限，方向特別有害。
    final usage = _finMindClient?.hourlyUsage;
    final usageStr = usage == null
        ? ''
        : ', FinMind=${usage.used}/${usage.budget} (近 1hr)';
    AppLogger.info(
      'UpdateService',
      '完成 ($dateStr): 價格=${result.pricesUpdated}, '
          '分析=${result.stocksAnalyzed}$usageStr',
    );

    final status = result.errors.isEmpty
        ? UpdateStatus.success.code
        : UpdateStatus.partial.code;
    await _db.finishUpdateRun(
      ctx.runId,
      status,
      message: result.errors.isEmpty
          ? '更新完成'
          : _partialRunMessage(result.errors),
    );

    result.success = true;
    // message 與 update_run 用同一份(2026-08-15 稽核):CLI 只印 message 與
    // exit code,若這裡無條件寫「更新完成」,20 個 recordError 的內容對維運
    // 完全不可見——本專案有「自動更新靜默斷 13 天」的前科。
    // success 語意維持「主流程完成」不變(輔助資料失敗不算主流程失敗)。
    result.message = result.errors.isEmpty
        ? '更新完成'
        : _partialRunMessage(result.errors);

    // 擷取警示價格資料
    await _fetchAlertPrices(ctx, result);
  }

  /// 重算規則準確度統計（`rule_accuracy`）。**失敗不會拋例外**（fail-safe），
  /// 失敗只 log，不影響 update result.success。
  ///
  /// 命名重點：「fail-safe」≠「非阻塞」。caller 仍會 await 等統計更新跑完才
  /// return（避免 background isolate 被 WorkManager kill）。
  Future<void> _updateRuleAccuracyStatsFailSafe(_UpdateContext ctx) async {
    final service = _ruleAccuracyService;
    if (service == null) return;

    try {
      await service.updateRuleAccuracyStats();
      AppLogger.info('UpdateService', '步驟 10+: 規則準確度統計更新完成');
    } catch (e, stack) {
      AppLogger.error('UpdateService', '規則準確度統計更新失敗（fail-safe）', e, stack);
      ctx.result.recordError('規則準確度統計更新失敗: $e', e);
    }
  }

  /// 新聞提及數快照（新聞熱度發現層）。**fail-safe**：失敗只 log、
  /// 不影響 update result（與 [_updateRuleAccuracyStatsFailSafe] 同模式）。
  Future<void> _snapshotNewsMentionsFailSafe(_UpdateContext ctx) async {
    final service = _newsMentionSnapshotService;
    if (service == null) return;

    try {
      await service.snapshotRecentDays();
      AppLogger.info('UpdateService', '步驟 10+: 新聞提及快照完成');
    } catch (e) {
      // 非關鍵路徑（顯示層不依賴此表）：降級 warning，只留 Sentry
      // breadcrumb，不觸發 Sentry 錯誤事件（`.error` 才會 capture exception）
      AppLogger.warning('UpdateService', '新聞提及快照失敗（不影響更新）', e);
      ctx.result.recordError('新聞提及快照失敗: $e', e);
    }
  }

  /// 釘選論點失效檢查（出場層 Phase 2）。**fail-safe**：失敗只 log、
  /// 不影響 update result（與 [_updateRuleAccuracyStatsFailSafe] 同模式）。
  Future<void> _checkPinnedThesesFailSafe(_UpdateContext ctx) async {
    final service = _thesisMonitorService;
    if (service == null) return;

    try {
      final n = await service.checkActiveTheses(asOf: ctx.normalizedDate);
      AppLogger.info('UpdateService', '步驟 10+: 釘選論點檢查完成（失效 $n 筆）');
    } catch (e, stack) {
      AppLogger.error('UpdateService', '釘選論點檢查失敗（fail-safe）', e, stack);
      ctx.result.recordError('釘選論點檢查失敗: $e', e);
    }
  }

  /// 均線階梯提醒重算。**fail-safe**：失敗只 log、不影響 update result
  /// （與 [_updateRuleAccuracyStatsFailSafe] 同模式）。
  ///
  /// 為什麼掛在每日更新而不是做成按鈕：提醒價位是死的、均線是活的，靠人
  /// 記得按只會讓失效間隔變短而非消失（2026-08-16 重整 36 檔提醒時，手動
  /// 設的價位全數落後於當時的 5MA）。
  Future<void> _refreshTrailingAlertsFailSafe(_UpdateContext ctx) async {
    try {
      final n = await _trailingMaAlertService.refresh(asOf: ctx.normalizedDate);
      AppLogger.info('UpdateService', '步驟 10+: 均線階梯提醒重算完成（$n 檔）');
    } catch (e, stack) {
      AppLogger.error('UpdateService', '均線階梯提醒重算失敗（fail-safe）', e, stack);
      ctx.result.recordError('均線階梯提醒重算失敗: $e', e);
    }
  }

  Future<void> _fetchAlertPrices(
    _UpdateContext ctx,
    UpdateResult result,
  ) async {
    try {
      final alertSymbols = (await _db.getActiveAlerts())
          .map((a) => a.symbol)
          .toSet()
          .toList();

      if (alertSymbols.isNotEmpty) {
        final latestPrices = await _db.getLatestPricesBatch(alertSymbols);
        final priceHistories = await _db.getPriceHistoryBatch(
          alertSymbols,
          startDate: ctx.normalizedDate.subtract(
            const Duration(days: DataFreshness.alertPriceHistoryDays),
          ),
          endDate: ctx.normalizedDate,
        );

        for (final symbol in alertSymbols) {
          final price = latestPrices[symbol]?.close;
          if (price != null) {
            result.currentPrices[symbol] = price;

            final history = priceHistories[symbol];
            if (history != null && history.length >= 2) {
              final previousClose = history[history.length - 2].close;
              if (previousClose != null && previousClose > 0) {
                result.priceChanges[symbol] =
                    ((price - previousClose) / previousClose) * 100;
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.warning('UpdateService', '警示價格擷取失敗', e);
    }
  }
}

/// 更新進度回呼
typedef UpdateProgressCallback =
    void Function(int currentStep, int totalSteps, String message);

/// 更新流程內部上下文
class _UpdateContext {
  _UpdateContext({
    required this.targetDate,
    required this.runId,
    required this.result,
    this.force = false,
    this.onProgress,
  }) : normalizedDate = targetDate;

  final DateTime targetDate;
  DateTime normalizedDate;
  final int runId;
  final UpdateResult result;
  final bool force;
  final UpdateProgressCallback? onProgress;
  List<String> marketCandidates = [];

  /// 任一 syncer 撞到 [RateLimitException] 時翻起，後續 API-heavy 步驟自我
  /// 跳過。Syncer 本身已守 `on RateLimitException rethrow` 契約，但 coordinator
  /// 過去用裸 `catch (e)` 把 rethrow 吞成 warning，導致下游 syncer 繼續打同
  /// 一個被限流的 API（最壞情形 _syncOtcCandidatesData 222 檔×3 vendor）。
  bool rateLimitedAbort = false;

  void reportProgress(int step, int total, String message) {
    onProgress?.call(step, total, message);
  }
}

/// 每日更新結果
class UpdateResult {
  UpdateResult({required this.date});

  /// 資料實際日期（可能在同步過程中被校正）
  DateTime date;
  bool success = false;
  bool skipped = false;
  String? message;
  int stocksUpdated = 0;
  int pricesUpdated = 0;
  int institutionalUpdated = 0;
  int newsUpdated = 0;
  int candidatesFound = 0;
  int stocksAnalyzed = 0;
  List<String> errors = [];
  bool hasRateLimitError = false;

  /// 是否有任何失敗項。與 [success] 語意不同:[success] 表「主流程完成」,
  /// 本旗標表「過程中有東西壞掉」——CLI 的 exit code 應該看這個。
  bool get hasErrors => errors.isNotEmpty;
  Map<String, double> currentPrices = {};
  Map<String, double> priceChanges = {};

  /// 記錄錯誤，同時自動偵測 RateLimitException
  /// [exception] 可為 null——並非所有失敗都來自例外，缺整個市場的當日價格
  /// 是資料條件而非拋錯，但同樣必須讓 run 降級為 partial。
  void recordError(String message, [Object? exception]) {
    errors.add(message);
    if (exception is RateLimitException) hasRateLimitError = true;
  }

  /// 是否為部分成功（成功但有步驟失敗）
  bool get hasWarnings => errors.isNotEmpty && success;

  /// 警告數量
  int get warningCount => errors.length;

  String get summary {
    if (skipped) return message ?? '跳過更新';
    if (!success) return '更新失敗: ${errors.join(', ')}';
    if (errors.isNotEmpty) {
      return '分析 $stocksAnalyzed 檔（${errors.length} 項警告）';
    }
    return '分析 $stocksAnalyzed 檔';
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/services/price_calculator.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:daredevil/presentation/mappers/summary_localizer.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_state.dart';
import 'package:daredevil/data/loaders/stock_fundamentals_loader.dart';
import 'package:daredevil/data/loaders/stock_chip_loader.dart';

// Re-export 狀態類別供外部使用
export 'package:daredevil/presentation/providers/stock_detail_state.dart';

// ==================================================
// 股票詳情 Notifier
// ==================================================

class StockDetailNotifier extends Notifier<StockDetailState> {
  StockDetailNotifier(this._symbol);

  final String _symbol;
  // late(非 final):build() 會因 finMindClientProvider 重建而重跑,
  // late final 會在第二次 build 拋 LateInitializationError(測試實證)
  late StockFundamentalsLoader _fundamentalsLoader;
  late StockChipLoader _chipLoader;
  var _active = true;

  /// 曾成功載入過內容(2026-08-01 複審):build() 因 finMindClientProvider
  /// 重建而重跑時 state 被清空,而 epoch listener 的空 state guard
  /// 恰好在清空後擋住自己——無此旗標則「換 token」讓存活的個股頁靜默
  /// 空白且永久卡死。同 instance 重跑 field 保留,據此排自動 reload。
  var _hasLoadedOnce = false;

  /// [loadData] 的世代號：每輪載入遞增，await 之後比對，過期（已有較新的
  /// 一輪）就放棄寫入——最新的請求勝出。build() 重跑時也遞增，讓重建前
  /// 發起的載入作廢：`_active` 會在 build() 被設回 true 擋不住它們，而
  /// build() 排的自動重載是 microtask，舊一輪已排入佇列的續行會先跑。
  var _loadGeneration = 0;

  /// 最新一輪載入的 Future（[_load]，或 build() 排定的自動重載），被取代
  /// 的 [loadData] 呼叫改等它
  Future<void>? _latestLoad;

  @override
  StockDetailState build() {
    _active = true;
    _loadGeneration++;
    ref.onDispose(() => _active = false);
    // finMindClientProvider 用 watch 而非 read(2026-07-29 審查修正):
    // 使用者更新 token 會讓該 provider 重建(watch finMindTokenProvider),舊 client 的 Dio 隨即被
    // close;read 快照會讓存活頁面(含 3 分鐘 keepAlive 窗)的 API fallback
    // 全打在死連線上、被 loader 的 catch 吞掉,症狀恰為「設了 token 還是
    // 沒資料」。watch 讓 notifier 隨 client 重建,與 repository providers
    // 的訂閱語意一致。databaseProvider/appClockProvider 從不 invalidate,
    // 維持 read。
    final finMind = ref.watch(finMindClientProvider);
    _fundamentalsLoader = StockFundamentalsLoader(
      db: ref.read(databaseProvider),
      finMind: finMind,
      clock: ref.read(appClockProvider),
    );
    _chipLoader = StockChipLoader(
      db: ref.read(databaseProvider),
      finMind: finMind,
      insiderRepo: ref.read(insiderRepositoryProvider),
      clock: ref.read(appClockProvider),
    );

    // 保活機制：3 分鐘內返回同一頁面時使用快取
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: ApiConfig.keepAliveMin), () {
      try {
        link.close();
      } catch (_) {
        // link 可能已在 dispose 時關閉，忽略此例外
      }
    });
    ref.onDispose(() => timer.cancel());

    // M6 follow-up：runUpdate 完成後 bump dataUpdateEpoch；同股票頁面
    // 停留時若背景觸發更新，自動 reload 拿到最新分析。與進行中的載入
    // 重疊時由 [_loadGeneration] 保證較新的一輪勝出。
    ref.listen(dataUpdateEpochProvider, (_, _) {
      if (!_active) return;
      if (state.price.analysis == null && state.reasons.isEmpty) return;
      loadData();
    });

    // 非首次 build(token 更換觸發的重建):state 即將被下方回傳值清空,
    // 排 microtask 自動重載——這是清空後唯一的恢復管道(見 _hasLoadedOnce)。
    // 登記為最新一輪，重建前發起的 loadData() 呼叫端改等這次重載完成
    if (_hasLoadedOnce) {
      _latestLoad = Future.microtask(() async {
        if (_active) await loadData();
      });
    }

    return const StockDetailState();
  }

  AppDatabase get _db => ref.read(databaseProvider);
  DataSyncService get _dataSyncService => ref.read(dataSyncServiceProvider);
  MarketDataRepository get _marketRepo =>
      ref.read(marketDataRepositoryProvider);

  /// 大盤位階（多頭/空頭/盤整）— 供 AI 摘要的 regime context 行使用。
  /// 讀 marketOverview 已載入的加權指數長窗口 closes；未載入或資料不足回 null
  /// （摘要 graceful 不顯示位階行）。
  MarketStage? _currentMarketStage() {
    final closes = ref
        .read(marketOverviewProvider)
        .indexStageHistory[MarketIndexNames.taiex];
    if (closes == null || closes.isEmpty) return null;
    final result = TechnicalIndicatorService().calculateMarketStage(closes);
    return result.stage == MarketStage.insufficient ? null : result.stage;
  }

  /// 載入股票詳情資料。
  ///
  /// 回傳的 Future 在最新一輪完成時才完成：被較新一輪取代時改等較新那輪，
  /// 呼叫端（巡檢換股 `_swapTo`）據此判斷資料已到位再切換畫面。
  Future<void> loadData() async {
    var run = _latestLoad = _load(++_loadGeneration);
    while (true) {
      await run;
      final latest = _latestLoad;
      // 沒有更新的一輪就結束
      if (latest == null || identical(latest, run)) return;
      run = latest;
    }
  }

  Future<void> _load(int generation) async {
    _hasLoadedOnce = true;
    bool isCurrent() => _active && generation == _loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final dateCtx = DateContext.withLookback(RuleParams.lookbackPrice);
      final normalizedToday = dateCtx.today;
      final startDate = dateCtx.historyStart;

      // 決定分析資料的查詢日期
      // 使用資料庫最新價格日期，確保盤前/非交易日也能顯示上次分析結果
      final latestDataDate = await _marketRepo.getLatestDataDate();
      if (!isCurrent()) return;
      final analysisDate = latestDataDate != null
          ? DateContext.normalize(latestDataDate)
          : normalizedToday;

      // 使用 Dart 3 Records 進行型別安全的平行載入
      final (
        stock,
        priceHistory,
        recentPrices,
        analysis,
        reasons,
        dbInstHistory,
        isInWatchlist,
      ) = await (
        _db.getStock(_symbol),
        _db.getPriceHistory(
          _symbol,
          startDate: startDate,
          endDate: normalizedToday,
        ),
        _db.getRecentPrices(_symbol, count: 2),
        _db.getAnalysis(_symbol, analysisDate),
        _db.getReasons(_symbol, analysisDate),
        _db.getInstitutionalHistory(
          _symbol,
          startDate: normalizedToday.subtract(
            const Duration(days: InstitutionalParams.institutionalLookbackDays),
          ),
          endDate: normalizedToday,
        ),
        _db.isInWatchlist(_symbol),
      ).wait;
      if (!isCurrent()) return;
      var instHistory = dbInstHistory;

      // 從最近價格提取最新與前一日（recentPrices 依日期降序排列）
      final latestPrice = recentPrices.isNotEmpty ? recentPrices.first : null;

      AppLogger.debug(
        'StockDetailNotifier',
        'recentPrices count=${recentPrices.length}, '
            'latest=${latestPrice?.close} (${latestPrice?.date})',
      );

      // DB 無法人資料時從 API 取得
      if (instHistory.isEmpty) {
        final apiResult = await _chipLoader.fetchInstitutionalFromApi(_symbol);
        if (!isCurrent()) return;
        instHistory = apiResult.data;
      }

      // 同步資料日期 — 找到共同最新日期
      final syncResult = _dataSyncService.synchronizeDataDates(
        priceHistory,
        instHistory,
      );
      final syncedInstHistory = syncResult.institutionalHistory;
      final dataDate = syncResult.dataDate;
      final hasDataMismatch = syncResult.hasDataMismatch;

      // 使用同步後的價格確保與 dataDate 一致
      final displayPrice = syncResult.latestPrice ?? latestPrice;

      if (hasDataMismatch) {
        AppLogger.debug(
          'StockDetailNotifier',
          'Data mismatch: using synced price '
              '${displayPrice?.close} (${displayPrice?.date}) '
              'instead of ${latestPrice?.close} (${latestPrice?.date})',
        );
      }

      // 生成 AI 智慧分析摘要（horizon 固定 short — 選擇器已於 2026-06 移除）。
      const loadHorizon = Horizon.short;
      final summaryData = const AnalysisSummaryService().generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: displayPrice,
        priceChange: PriceCalculator.calculatePriceChange(
          priceHistory,
          displayPrice,
        ),
        institutionalHistory: syncedInstHistory,
        revenueHistory: state.fundamentals.revenueHistory,
        latestPER: state.fundamentals.latestPER,
        horizon: loadHorizon,
        marketStage: _currentMarketStage(),
      );
      final summary = const SummaryLocalizer().localize(summaryData);
      if (!isCurrent()) return;

      state = state.copyWith(
        stock: stock,
        latestPrice: displayPrice,
        priceHistory: priceHistory,
        analysis: analysis,
        reasons: reasons,
        institutionalHistory: syncedInstHistory,
        aiSummary: summary,
        isInWatchlist: isInWatchlist,
        isLoading: false,
        dataDate: dataDate,
        hasDataMismatch: hasDataMismatch,
      );
    } catch (e) {
      AppLogger.warning('StockDetailNotifier', '載入股票詳情失敗: $_symbol', e);
      if (!isCurrent()) return;
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }

  /// 關閉已有內容時的重載錯誤 banner
  void clearError() => state = state.copyWith(error: null);

  /// 切換自選股 — 同步更新全域 watchlistProvider
  ///
  /// 失敗時拋出例外（而非寫入 [state.error]，因為該欄位會觸發整頁錯誤狀態）。
  /// 呼叫端應 catch 並以 SnackBar 等輕量方式顯示錯誤。
  Future<void> toggleWatchlist() async {
    final watchlistNotifier = ref.read(watchlistProvider.notifier);
    final wasInWatchlist = state.isInWatchlist;

    if (wasInWatchlist) {
      final success = await watchlistNotifier.removeStock(_symbol);
      if (!success) {
        final msg =
            ref.read(watchlistProvider).error ?? S.watchlistRemoveFailed;
        throw StateError(msg);
      }
    } else {
      final success = await watchlistNotifier.addStock(_symbol);
      if (!success) {
        final msg = ref.read(watchlistProvider).error ?? S.watchlistAddFailed;
        throw StateError(msg);
      }
    }

    // 操作成功才更新本地狀態
    state = state.copyWith(isInWatchlist: !wasInWatchlist);
  }

  /// 載入基本面資料（營收/股利/本益比/EPS）
  Future<void> loadFundamentals() async {
    if (state.loading.isLoadingFundamentals) return;

    // 只有在完全沒有錯誤且已有資料時才跳過
    // 若有 fundamentalsError 表示上次部分失敗，允許重試
    final hasSomeData =
        state.fundamentals.revenueHistory.isNotEmpty ||
        state.fundamentals.dividendSummary != null;
    if (hasSomeData && state.fundamentalsError == null) return;

    state = state.copyWith(
      isLoadingFundamentals: true,
      fundamentalsError: null,
    );

    try {
      final result = await _fundamentalsLoader.loadAll(_symbol);
      if (!_active) return;

      // 檢查是否所有資料源都有拿到資料
      // loadAll() 內部 catch 不會 rethrow，會回傳空資料
      // 若有缺漏項目則標記 fundamentalsError 讓下次允許重試
      // 股利資料不完整是摘要裡的「建置中」，不是缺漏：只有讀取失敗（null）
      // 才列入，避免頁首紅字與無效的重試
      final missingParts = <String>[
        if (result.revenueData.isEmpty) '營收',
        if (result.epsData.isEmpty) '每股盈餘',
        if (result.dividendSummary == null) '股利',
        if (result.latestPER == null) '估值',
      ];
      final partialError = missingParts.isNotEmpty
          ? '部分基本面資料暫無法取得（${missingParts.join("、")}）'
          : null;

      state = state.copyWith(
        revenueHistory: result.revenueData,
        dividendSummary: result.dividendSummary,
        latestPER: result.latestPER,
        epsHistory: result.epsData,
        latestQuarterMetrics: result.quarterMetrics,
        isLoadingFundamentals: false,
        fundamentalsError: partialError,
      );

      // 基本面載入後重新生成 AI 摘要（含營收/估值資料）
      _regenerateAiSummary(
        revenueData: result.revenueData,
        latestPER: result.latestPER,
      );
    } catch (e) {
      AppLogger.warning('StockDetailNotifier', '載入基本面資料失敗: $_symbol', e);
      state = state.copyWith(
        isLoadingFundamentals: false,
        fundamentalsError: ErrorDisplay.message(e),
      );
    }
  }

  /// 載入董監持股資料與內部人轉讓記錄
  Future<void> loadInsiderData() async {
    if (state.loading.isLoadingInsider ||
        state.chip.insiderHistory.isNotEmpty) {
      return;
    }

    state = state.copyWith(isLoadingInsider: true, insiderError: null);
    try {
      final (insiderHistory, transfers) = await (
        _chipLoader.loadInsiderFromDb(_symbol),
        _db.getRecentTransfers(_symbol),
      ).wait;
      if (!_active) return;
      state = state.copyWith(
        insiderHistory: insiderHistory,
        insiderTransfers: transfers,
        isLoadingInsider: false,
      );
    } catch (e) {
      AppLogger.warning('StockDetailNotifier', '載入內部人資料失敗: $_symbol', e);
      state = state.copyWith(
        isLoadingInsider: false,
        insiderError: ErrorDisplay.message(e),
      );
    }
  }

  /// 載入完整籌碼分析資料
  Future<void> loadChipData() async {
    if (state.loading.isLoadingChip || state.chip.chipStrength != null) return;

    state = state.copyWith(isLoadingChip: true);

    try {
      final result = await _chipLoader.loadAllChipData(
        _symbol,
        existingInstitutional: state.chip.institutionalHistory,
        existingInsider: state.chip.insiderHistory,
      );
      if (!_active) return;

      state = state.copyWith(
        dayTradingHistory: result.dayTrading,
        shareholdingHistory: result.shareholding,
        marginTradingHistory: result.marginTrading,
        holdingDistribution: result.holdingDist,
        insiderHistory: result.insider.isNotEmpty ? result.insider : null,
        chipStrength: result.strength,
        isLoadingChip: false,
      );
    } catch (e) {
      AppLogger.warning('StockDetailNotifier', '載入籌碼分析資料失敗: $_symbol', e);
      state = state.copyWith(
        isLoadingChip: false,
        chipError: ErrorDisplay.message(e),
      );
    }
  }

  /// 重新生成 AI 智慧分析摘要（含營收/估值資料）
  void _regenerateAiSummary({
    required List<FinMindRevenue> revenueData,
    required FinMindPER? latestPER,
  }) {
    final summaryData = const AnalysisSummaryService().generate(
      analysis: state.price.analysis,
      reasons: state.reasons,
      latestPrice: state.price.latestPrice,
      priceChange: state.priceChange,
      institutionalHistory: state.chip.institutionalHistory,
      revenueHistory: revenueData,
      latestPER: latestPER,
      horizon: Horizon.short,
      marketStage: _currentMarketStage(),
    );
    state = state.copyWith(
      aiSummary: const SummaryLocalizer().localize(summaryData),
    );
  }
}

/// 股票詳情 Provider family
/// 使用 autoDispose + keepAlive 組合：
/// - autoDispose: 無訂閱者時觸發清理
/// - keepAlive: 保留 ApiConfig.keepAliveMin（3 分鐘）快取，改善列表↔詳情
///   切換體驗
final stockDetailProvider = NotifierProvider.autoDispose
    .family<StockDetailNotifier, StockDetailState, String>(
      StockDetailNotifier.new,
    );

/// 主要規則準確度摘要文字 Provider
///
/// 取得股票的主要觸發規則，並返回其準確度摘要文字。
/// 例如：「命中率 65%，平均 5 日報酬 +2.3%」
final primaryRuleAccuracySummaryProvider = FutureProvider.family
    .autoDispose<String?, String>((ref, symbol) async {
      final state = ref.watch(stockDetailProvider(symbol));
      if (state.reasons.isEmpty) return null;

      // 取得主要規則（rank = 1）
      final primaryReason = state.reasons.firstWhere(
        (r) => r.rank == 1,
        orElse: () => state.reasons.first,
      );

      final service = ref.watch(ruleAccuracyServiceProvider);
      return service.getRuleSummaryText(primaryReason.reasonType);
    });

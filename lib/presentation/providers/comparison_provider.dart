import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';
import 'package:daredevil/data/mappers/finmind_model_mapper.dart';
import 'package:daredevil/presentation/mappers/summary_localizer.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==================================================
// 比較狀態
// ==================================================

class ComparisonState {
  const ComparisonState({
    this.symbols = const [],
    this.stocksMap = const {},
    this.latestPricesMap = const {},
    this.priceHistoriesMap = const {},
    this.analysesMap = const {},
    this.valuationsMap = const {},
    this.institutionalMap = const {},
    this.epsMap = const {},
    this.revenueMap = const {},
    this.summariesMap = const {},
    this.isLoading = false,
    this.error,
  });

  final List<String> symbols;
  final Map<String, StockMasterEntry> stocksMap;
  final Map<String, DailyPriceEntry> latestPricesMap;
  final Map<String, List<DailyPriceEntry>> priceHistoriesMap;
  final Map<String, DailyAnalysisEntry> analysesMap;
  final Map<String, StockValuationEntry> valuationsMap;
  final Map<String, List<DailyInstitutionalEntry>> institutionalMap;
  final Map<String, List<FinancialDataEntry>> epsMap;
  final Map<String, List<MonthlyRevenueEntry>> revenueMap;
  final Map<String, StockSummary> summariesMap;
  final bool isLoading;
  final String? error;

  bool get canAddMore => symbols.length < 4;
  bool get hasEnoughToCompare => symbols.length >= 2;

  ComparisonState copyWith({
    List<String>? symbols,
    Map<String, StockMasterEntry>? stocksMap,
    Map<String, DailyPriceEntry>? latestPricesMap,
    Map<String, List<DailyPriceEntry>>? priceHistoriesMap,
    Map<String, DailyAnalysisEntry>? analysesMap,
    Map<String, StockValuationEntry>? valuationsMap,
    Map<String, List<DailyInstitutionalEntry>>? institutionalMap,
    Map<String, List<FinancialDataEntry>>? epsMap,
    Map<String, List<MonthlyRevenueEntry>>? revenueMap,
    Map<String, StockSummary>? summariesMap,
    bool? isLoading,
    Object? error = sentinel,
  }) {
    return ComparisonState(
      symbols: symbols ?? this.symbols,
      stocksMap: stocksMap ?? this.stocksMap,
      latestPricesMap: latestPricesMap ?? this.latestPricesMap,
      priceHistoriesMap: priceHistoriesMap ?? this.priceHistoriesMap,
      analysesMap: analysesMap ?? this.analysesMap,
      valuationsMap: valuationsMap ?? this.valuationsMap,
      institutionalMap: institutionalMap ?? this.institutionalMap,
      epsMap: epsMap ?? this.epsMap,
      revenueMap: revenueMap ?? this.revenueMap,
      summariesMap: summariesMap ?? this.summariesMap,
      isLoading: isLoading ?? this.isLoading,
      error: error == sentinel ? this.error : error as String?,
    );
  }
}

// ==================================================
// 比較 Notifier
// ==================================================

class ComparisonNotifier extends Notifier<ComparisonState> {
  var _active = true;

  /// Generation token：每次啟動 _loadAllData 遞增，
  /// 載入完成時若 generation 已過期（有更新的載入），放棄寫入。
  int _loadGeneration = 0;

  @override
  ComparisonState build() {
    _active = true;
    _loadGeneration = 0;
    ref.onDispose(() => _active = false);

    return const ComparisonState();
  }

  AppDatabase get _db => ref.read(databaseProvider);
  CachedDatabaseAccessor get _cachedDb => ref.read(cachedDbProvider);

  /// 新增股票並重新載入所有比較資料。
  ///
  /// 失敗時回滾新增的 symbol，避免佔用名額且無資料。
  Future<void> addStock(String symbol) async {
    if (state.symbols.contains(symbol) || !state.canAddMore) return;

    final oldSymbols = state.symbols;
    final newSymbols = [...oldSymbols, symbol];
    state = state.copyWith(symbols: newSymbols, isLoading: true, error: null);
    await _loadAllData(newSymbols);

    // autoDispose：user 加股票後立刻離頁，notifier 在 await 期間 dispose，
    // 此時讀寫 state 會 throw StateError。`_active` 由 `ref.onDispose` 設為
    // false，必須先 guard 才能讀 state.error / 寫 state。
    if (!_active) return;

    // _loadAllData 失敗時會設定 error，回滾新增的 symbol
    if (state.error != null) {
      state = state.copyWith(symbols: oldSymbols);
    }
  }

  /// 一次新增多檔股票（用於初始載入，避免 race condition）。
  Future<void> addStocks(List<String> symbols) async {
    final unique = <String>[];
    for (final s in symbols) {
      if (!unique.contains(s) && unique.length < 4) {
        unique.add(s);
      }
    }
    if (unique.isEmpty) return;

    state = state.copyWith(symbols: unique, isLoading: true);
    await _loadAllData(unique);
  }

  /// 移除股票並重新載入資料。
  void removeStock(String symbol) {
    final newSymbols = state.symbols.where((s) => s != symbol).toList();

    // 移除該股票的比較資料
    final newStocks = Map<String, StockMasterEntry>.from(state.stocksMap)
      ..remove(symbol);
    final newPrices = Map<String, DailyPriceEntry>.from(state.latestPricesMap)
      ..remove(symbol);
    final newHistories = Map<String, List<DailyPriceEntry>>.from(
      state.priceHistoriesMap,
    )..remove(symbol);
    final newAnalyses = Map<String, DailyAnalysisEntry>.from(state.analysesMap)
      ..remove(symbol);
    final newValuations = Map<String, StockValuationEntry>.from(
      state.valuationsMap,
    )..remove(symbol);
    final newInst = Map<String, List<DailyInstitutionalEntry>>.from(
      state.institutionalMap,
    )..remove(symbol);
    final newEps = Map<String, List<FinancialDataEntry>>.from(state.epsMap)
      ..remove(symbol);
    final newRevenue = Map<String, List<MonthlyRevenueEntry>>.from(
      state.revenueMap,
    )..remove(symbol);
    final newSummaries = Map<String, StockSummary>.from(state.summariesMap)
      ..remove(symbol);

    state = state.copyWith(
      symbols: newSymbols,
      stocksMap: newStocks,
      latestPricesMap: newPrices,
      priceHistoriesMap: newHistories,
      analysesMap: newAnalyses,
      valuationsMap: newValuations,
      institutionalMap: newInst,
      epsMap: newEps,
      revenueMap: newRevenue,
      summariesMap: newSummaries,
    );
  }

  /// 清除目前的錯誤狀態。
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 錯誤後重新載入目前所有股票的資料。
  Future<void> reload() async {
    if (state.symbols.isEmpty) return;
    state = state.copyWith(isLoading: true, error: null);
    await _loadAllData(state.symbols);
  }

  /// 載入指定股票的所有比較資料。
  ///
  /// 使用 generation token 防止舊載入覆蓋新狀態：
  /// 若載入期間有更新的 _loadAllData 被啟動，本次結果會被丟棄。
  Future<void> _loadAllData(List<String> symbols) async {
    final generation = ++_loadGeneration;

    try {
      // horizon 固定 short（選擇器已於 2026-06 移除）。
      const loadHorizon = Horizon.short;
      final dateCtx = DateContext.now(historyDays: 90);

      // 使用資料庫最新價格日期，確保盤前/非交易日也能顯示上次分析結果
      final latestDataDate = await _db.getLatestDataDate();
      final analysisDate = latestDataDate != null
          ? DateContext.normalize(latestDataDate)
          : dateCtx.today;

      // 1. Core data via cached batch query
      final coreData = await _cachedDb.loadStockListData(
        symbols: symbols,
        analysisDate: analysisDate,
        historyStart: dateCtx.historyStart,
      );

      // 2. Additional data in parallel
      final instStartDate = dateCtx.today.subtract(
        const Duration(days: InstitutionalParams.institutionalLookbackDays),
      );
      final (valuations, institutional, eps, revenue) = await (
        _db.getLatestValuationsBatch(symbols),
        _db.getInstitutionalHistoryBatch(symbols, startDate: instStartDate),
        _db.getEPSHistoryBatch(symbols),
        _db.getRecentMonthlyRevenueBatch(
          symbols,
          months: DataFreshness.revenueDisplayMonths,
        ),
      ).wait;

      if (!_active || _loadGeneration != generation) return;

      // 3. Generate AI summaries per stock
      const summaryService = AnalysisSummaryService();
      const localizer = SummaryLocalizer();
      final summaries = <String, StockSummary>{};
      for (final symbol in symbols) {
        final analysis = coreData.analyses[symbol];
        final reasons = coreData.reasons[symbol] ?? [];
        final latestPrice = coreData.latestPrices[symbol];
        final priceHistory = coreData.priceHistories[symbol] ?? [];

        // 將 DB Model 轉換為 API Model 供摘要服務使用
        final finMindRevenues = FinMindModelMapper.toFinMindRevenues(
          revenue[symbol] ?? [],
        );
        final finMindPER = FinMindModelMapper.toFinMindPER(valuations[symbol]);

        final summaryData = summaryService.generate(
          analysis: analysis,
          reasons: reasons,
          latestPrice: latestPrice,
          priceChange: PriceCalculator.calculatePriceChange(
            priceHistory,
            latestPrice,
          ),
          institutionalHistory: institutional[symbol] ?? [],
          revenueHistory: finMindRevenues,
          latestPER: finMindPER,
          horizon: loadHorizon,
        );
        summaries[symbol] = localizer.localize(summaryData);
      }

      // generation 過期：有更新的載入已啟動，丟棄本次結果
      if (!_active || _loadGeneration != generation) return;

      state = state.copyWith(
        stocksMap: coreData.stocks,
        latestPricesMap: coreData.latestPrices,
        priceHistoriesMap: coreData.priceHistories,
        analysesMap: coreData.analyses,
        valuationsMap: valuations,
        institutionalMap: institutional,
        epsMap: eps,
        revenueMap: revenue,
        summariesMap: summaries,
        isLoading: false,
      );
    } catch (e) {
      // generation 過期時不覆蓋新載入的錯誤狀態
      if (_loadGeneration != generation) return;
      // autoDispose race：notifier 在 await 期間被 dispose，跳過 state 寫入
      // 避免 StateError；錯誤已記 log。
      if (!_active) {
        AppLogger.warning(
          'ComparisonNotifier',
          '載入比較資料失敗（notifier 已 dispose）',
          e,
        );
        return;
      }
      AppLogger.warning('ComparisonNotifier', '載入比較資料失敗', e);
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }
}

// ==================================================
// Provider
// ==================================================

final comparisonProvider =
    NotifierProvider.autoDispose<ComparisonNotifier, ComparisonState>(
      ComparisonNotifier.new,
    );

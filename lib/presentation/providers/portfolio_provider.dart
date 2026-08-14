import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/portfolio_repository.dart';
import 'package:daredevil/domain/services/dividend_intelligence_service.dart';
import 'package:daredevil/domain/services/portfolio_analytics_service.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==================================================
// 交易類型
// ==================================================

enum TransactionType {
  buy('BUY'),
  sell('SELL'),
  dividendCash('DIVIDEND_CASH'),
  dividendStock('DIVIDEND_STOCK');

  const TransactionType(this.value);
  final String value;

  static TransactionType fromValue(String v) =>
      TransactionType.values.firstWhere((e) => e.value == v);

  String get i18nKey => switch (this) {
    TransactionType.buy => 'portfolio.txBuy',
    TransactionType.sell => 'portfolio.txSell',
    TransactionType.dividendCash => 'portfolio.txDividendCash',
    TransactionType.dividendStock => 'portfolio.txDividendStock',
  };
}

// ==================================================
// 單一持倉顯示資料
// ==================================================

class PortfolioPositionData {
  const PortfolioPositionData({
    required this.symbol,
    this.stockName,
    this.market,
    required this.quantity,
    required this.avgCost,
    required this.realizedPnl,
    required this.totalDividendReceived,
    this.currentPrice,
  });

  final String symbol;
  final String? stockName;
  final String? market;
  final double quantity;
  final double avgCost;
  final double realizedPnl;
  final double totalDividendReceived;
  final double? currentPrice;

  /// 市值
  double get marketValue => quantity * (currentPrice ?? avgCost);

  /// 未實現損益
  double get unrealizedPnl =>
      currentPrice != null ? (currentPrice! - avgCost) * quantity : 0;

  /// 未實現損益百分比
  double get unrealizedPnlPct => (avgCost > 0 && currentPrice != null)
      ? ((currentPrice! - avgCost) / avgCost) * 100
      : 0;

  /// 總損益（已實現 + 未實現 + 股利）
  double get totalPnl => realizedPnl + unrealizedPnl + totalDividendReceived;

  /// 總成本
  double get costBasis => quantity * avgCost;
}

// ==================================================
// 投資組合總覽
// ==================================================

class PortfolioSummary {
  const PortfolioSummary({
    required this.totalMarketValue,
    required this.totalCostBasis,
    required this.totalUnrealizedPnl,
    required this.totalRealizedPnl,
    required this.totalDividends,
    required this.positionCount,
  });

  final double totalMarketValue;
  final double totalCostBasis;
  final double totalUnrealizedPnl;
  final double totalRealizedPnl;
  final double totalDividends;
  final int positionCount;

  double get totalPnl => totalUnrealizedPnl + totalRealizedPnl + totalDividends;

  double get totalPnlPct =>
      totalCostBasis > 0 ? (totalPnl / totalCostBasis) * 100 : 0;

  static const empty = PortfolioSummary(
    totalMarketValue: 0,
    totalCostBasis: 0,
    totalUnrealizedPnl: 0,
    totalRealizedPnl: 0,
    totalDividends: 0,
    positionCount: 0,
  );
}

// ==================================================
// 投資組合狀態
// ==================================================

class PortfolioState {
  const PortfolioState({
    this.positions = const [],
    this.performance,
    this.dividendAnalysis,
    this.isLoading = false,
    this.error,
  });

  final List<PortfolioPositionData> positions;
  final PortfolioPerformance? performance;
  final DividendAnalysis? dividendAnalysis;
  final bool isLoading;
  final String? error;

  PortfolioSummary get summary {
    if (positions.isEmpty) return PortfolioSummary.empty;

    double totalMV = 0, totalCB = 0, totalUPnl = 0, totalRPnl = 0, totalDiv = 0;

    for (final p in positions) {
      totalMV += p.marketValue;
      totalCB += p.costBasis;
      totalUPnl += p.unrealizedPnl;
      totalRPnl += p.realizedPnl;
      totalDiv += p.totalDividendReceived;
    }

    return PortfolioSummary(
      totalMarketValue: totalMV,
      totalCostBasis: totalCB,
      totalUnrealizedPnl: totalUPnl,
      totalRealizedPnl: totalRPnl,
      totalDividends: totalDiv,
      positionCount: positions.where((p) => p.quantity > 0).length,
    );
  }

  /// 配置比例（symbol → 百分比）
  Map<String, double> get allocationMap {
    final total = summary.totalMarketValue;
    if (total <= 0) return {};
    return {
      for (final p in positions.where((p) => p.quantity > 0))
        p.symbol: (p.marketValue / total) * 100,
    };
  }

  PortfolioState copyWith({
    List<PortfolioPositionData>? positions,
    PortfolioPerformance? performance,
    DividendAnalysis? dividendAnalysis,
    bool? isLoading,
    Object? error = sentinel,
  }) {
    return PortfolioState(
      positions: positions ?? this.positions,
      performance: performance ?? this.performance,
      dividendAnalysis: dividendAnalysis ?? this.dividendAnalysis,
      isLoading: isLoading ?? this.isLoading,
      error: error == sentinel ? this.error : error as String?,
    );
  }
}

// ==================================================
// PortfolioNotifier
// ==================================================

class PortfolioNotifier extends Notifier<PortfolioState> {
  var _active = true;

  @override
  PortfolioState build() {
    _active = true;
    ref.onDispose(() => _active = false);
    return const PortfolioState();
  }

  AppDatabase get _db => ref.read(databaseProvider);
  PortfolioRepository get _repo => ref.read(portfolioRepositoryProvider);

  static const _analyticsService = PortfolioAnalyticsService();
  static const _dividendService = DividendIntelligenceService();

  /// 清除錯誤狀態
  void clearError() => state = state.copyWith(error: null);

  /// 載入所有持倉
  Future<void> loadPositions() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final positions = await _db.getPortfolioPositions();
      if (!_active) return;

      if (positions.isEmpty) {
        state = state.copyWith(
          positions: [],
          performance: PortfolioPerformance.empty,
          dividendAnalysis: DividendAnalysis.empty,
          isLoading: false,
        );
        return;
      }

      // 取得股票名稱和最新價格（批次查詢，避免 N+1）
      final symbols = positions.map((p) => p.symbol).toList();
      final (stocksResult, pricesResult) = await (
        _db.getStocksBatch(symbols),
        _db.getLatestPricesBatch(symbols),
      ).wait;
      if (!_active) return;

      // 建立 maps 供績效計算
      final stocksMap = <String, StockMasterEntry>{};
      final currentPrices = <String, double>{};

      final List<PortfolioPositionData> positionData = [];
      for (final pos in positions) {
        final stock = stocksResult[pos.symbol];
        final price = pricesResult[pos.symbol];

        if (stock != null) {
          stocksMap[pos.symbol] = stock;
        }
        if (price?.close != null) {
          currentPrices[pos.symbol] = price!.close!;
        }

        positionData.add(
          PortfolioPositionData(
            symbol: pos.symbol,
            stockName: stock?.name,
            market: stock?.market,
            quantity: pos.quantity,
            avgCost: pos.avgCost,
            realizedPnl: pos.realizedPnl,
            totalDividendReceived: pos.totalDividendReceived,
            currentPrice: price?.close,
          ),
        );
      }

      // 取得所有交易紀錄以計算績效
      final transactions = await _db.getAllPortfolioTransactions();

      // 計算績效
      final performance = _analyticsService.calculatePerformance(
        transactions: transactions,
        positions: positions,
        currentPrices: currentPrices,
        stocksMap: stocksMap,
      );

      // 取得股利歷史並計算股利分析
      final dividendHistories = await _db.getDividendHistoryBatch(symbols);
      final dividendAnalysis = _dividendService.analyzeDividends(
        positions: positions,
        dividendHistories: dividendHistories,
        currentPrices: currentPrices,
      );

      state = state.copyWith(
        positions: positionData,
        performance: performance,
        dividendAnalysis: dividendAnalysis,
        isLoading: false,
      );
    } catch (e) {
      AppLogger.warning('PortfolioNotifier', '載入持倉資料失敗', e);
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }

  /// 重載持倉並檢查是否成功
  ///
  /// 寫入操作成功後呼叫此方法重載資料；若重載失敗會拋出例外，
  /// 讓呼叫端知道資料可能未同步（寫入本身已完成）。
  Future<void> _reloadOrThrow() async {
    await loadPositions();
    if (state.error != null) {
      throw StateError(state.error!);
    }
  }

  /// 新增買進交易
  Future<void> addBuy({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    String? note,
  }) async {
    await _repo.addBuyTransaction(
      symbol: symbol,
      date: date,
      quantity: quantity,
      price: price,
      fee: fee,
      note: note,
    );
    await _reloadOrThrow();
  }

  /// 新增賣出交易
  Future<void> addSell({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {
    await _repo.addSellTransaction(
      symbol: symbol,
      date: date,
      quantity: quantity,
      price: price,
      fee: fee,
      tax: tax,
      note: note,
    );
    await _reloadOrThrow();
  }

  /// 新增股利紀錄
  Future<void> addDividend({
    required String symbol,
    required DateTime date,
    required double amount,
    required bool isCash,
    String? note,
  }) async {
    await _repo.addDividendTransaction(
      symbol: symbol,
      date: date,
      amount: amount,
      isCash: isCash,
      note: note,
    );
    await _reloadOrThrow();
  }

  /// 刪除交易
  Future<void> deleteTransaction(int txId, String symbol) async {
    await _repo.deleteTransaction(txId, symbol);
    await _reloadOrThrow();
  }

  /// 編輯交易
  Future<void> updateTransaction({
    required int txId,
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {
    await _repo.updateTransaction(
      txId: txId,
      symbol: symbol,
      date: date,
      quantity: quantity,
      price: price,
      fee: fee,
      tax: tax,
      note: note,
    );
    await _reloadOrThrow();
  }
}

// ==================================================
// Providers
// ==================================================

final portfolioProvider = NotifierProvider<PortfolioNotifier, PortfolioState>(
  PortfolioNotifier.new,
);

/// 單一 symbol 的交易紀錄
final positionTransactionsProvider =
    FutureProvider.family<List<PortfolioTransactionEntry>, String>((
      ref,
      symbol,
    ) {
      final db = ref.watch(databaseProvider);
      return db.getTransactionsForSymbol(symbol);
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/portfolio_repository.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
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
    this.priceDate,
    this.priceChangeAmount,
  });

  final String symbol;
  final String? stockName;
  final String? market;
  final double quantity;
  final double avgCost;
  final double realizedPnl;
  final double totalDividendReceived;
  final double? currentPrice;

  /// 現價那一筆的日期(合併規則據此判斷是不是今天的正式資料)
  final DateTime? priceDate;

  /// 交易所漲跌價差(金額);昨收 = 現價 − 價差(除權息日即為參考價)。
  /// 交易所沒給時以前一筆收盤推回;都沒有為 null
  final double? priceChangeAmount;

  /// 只換現價(盤中即時報價用);其他欄位不變。市值、未實現損益隨之以新
  /// 價格計算
  PortfolioPositionData copyWithPrice(double? price) => PortfolioPositionData(
    symbol: symbol,
    stockName: stockName,
    market: market,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    currentPrice: price,
    priceDate: priceDate,
    priceChangeAmount: priceChangeAmount,
  );

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
    this.unpricedCount = 0,
  });

  final double totalMarketValue;
  final double totalCostBasis;
  final double totalUnrealizedPnl;
  final double totalRealizedPnl;
  final double totalDividends;
  final int positionCount;

  /// 在倉但缺當日價的檔數(靜默稽核 #5)。這些持股以成本價計值、未實現
  /// 損益恰為 0——停牌/跌停鎖死的重倉股會讓總報酬看起來平穩。>0 時
  /// 頁首總覽掛警示,per-position 列本就保留 null 可下鑽。
  final int unpricedCount;

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

  /// 依代號找持股;沒有回 null
  PortfolioPositionData? positionOf(String symbol) {
    for (final p in positions) {
      if (p.symbol == symbol) return p;
    }
    return null;
  }

  /// 在倉持股價格日期的最大值(績效、配置、股利的資料日期);沒有為 null
  DateTime? get priceDate {
    DateTime? latest;
    for (final p in positions) {
      final d = p.priceDate;
      if (p.quantity <= 0 || d == null) continue;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    return latest;
  }

  PortfolioSummary get summary {
    if (positions.isEmpty) return PortfolioSummary.empty;

    double totalMV = 0, totalCB = 0, totalUPnl = 0, totalRPnl = 0, totalDiv = 0;

    var unpriced = 0;
    for (final p in positions) {
      totalMV += p.marketValue;
      totalCB += p.costBasis;
      totalUPnl += p.unrealizedPnl;
      totalRPnl += p.realizedPnl;
      totalDiv += p.totalDividendReceived;
      if (p.quantity > 0 && p.currentPrice == null) unpriced++;
    }

    return PortfolioSummary(
      totalMarketValue: totalMV,
      totalCostBasis: totalCB,
      totalUnrealizedPnl: totalUPnl,
      totalRealizedPnl: totalRPnl,
      totalDividends: totalDiv,
      positionCount: positions.where((p) => p.quantity > 0).length,
      unpricedCount: unpriced,
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

      // 交易所漲跌價差缺(例如上櫃單檔改走 FinMind 寫入)時,以前一筆收盤
      // 推回價差:今日損益要「收盤 − 價差」當昨收
      final previousCloses = await _previousCloses(pricesResult);
      if (!_active) return;

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
            priceDate: price?.date,
            priceChangeAmount:
                price?.priceChange ??
                switch ((price?.close, previousCloses[pos.symbol])) {
                  (final close?, final previous?) => close - previous,
                  _ => null,
                },
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

      final dividendAnalysis = await _analyzeDividends(
        positions,
        symbols,
        stocksMap,
        currentPrices,
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

  /// 價差缺的持股:取資料庫裡前一筆收盤(代號 → 收盤)。前一筆的日期要早於
  /// 最新那一筆,否則不算
  Future<Map<String, double>> _previousCloses(
    Map<String, DailyPriceEntry> latest,
  ) async {
    final missing = [
      for (final MapEntry(key: symbol, value: price) in latest.entries)
        if (price.close != null && price.priceChange == null) symbol,
    ];
    final recents = await Future.wait([
      for (final symbol in missing) _db.getRecentPrices(symbol, count: 2),
    ]);
    return {
      for (var i = 0; i < missing.length; i++)
        if (recents[i] case [final first, final second, ...]
            when second.close != null &&
                second.date.isBefore(first.date) &&
                DateContext.isSameDay(first.date, latest[missing[i]]!.date))
          missing[i]: second.close!,
    };
  }

  /// 股利分析：配發表與完整度事實建每檔的股利摘要，官方估值配上估值日的收盤。
  /// 先讀事實、再讀配發列（理由同個股頁的 `StockFundamentalsLoader`）
  Future<DividendAnalysis> _analyzeDividends(
    List<PortfolioPositionEntry> positions,
    List<String> symbols,
    Map<String, StockMasterEntry> stocksMap,
    Map<String, double> currentPrices,
  ) async {
    final now = ref.read(appClockProvider).now();
    final completeness = await loadDividendCompleteness(_db, now: now);
    final distributions = await _db.getDividendDistributionsBatch(symbols);
    final valuations = await _db.getLatestValuationsBatch(symbols);
    // 與個股頁同一個新鮮度下限：上櫃估值只同步自選與候選股，持股可能停在很久
    // 以前的一筆（中間若分割，舊的每股股利 × 現在的股數會放大好幾倍）。過時或
    // 殖利率空白的估值不用，改走近一年殖利率
    final valuationFrom = now.subtract(
      const Duration(days: DataFreshness.valuationDbLookbackDays),
    );
    final officialYields = <String, OfficialYield>{};
    for (final MapEntry(key: symbol, value: valuation) in valuations.entries) {
      final yieldPercent = valuation.dividendYield;
      if (yieldPercent == null || valuation.date.isBefore(valuationFrom)) {
        continue;
      }
      // 官方殖利率＝每股股利 ÷ 估值日收盤：乘回同一天的收盤才是交易所用的股利
      final close = (await _db.getPriceOnDate(symbol, valuation.date))?.close;
      if (close != null) {
        officialYields[symbol] = (yieldPercent: yieldPercent, close: close);
      }
    }
    return _dividendService.analyzeDividends(
      positions: positions,
      summaries: {
        for (final symbol in symbols)
          symbol: DividendSummary.compute(
            symbol: symbol,
            name: stocksMap[symbol]?.name,
            rows: distributions[symbol] ?? const [],
            completeness: completeness,
          ),
      },
      officialYields: officialYields,
      currentPrices: currentPrices,
    );
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

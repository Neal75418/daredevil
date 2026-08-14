import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/portfolio_repository.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockPortfolioRepository extends Mock implements PortfolioRepository {}

// ==========================================
// Test Helpers
// ==========================================

PortfolioPositionEntry createPosition({
  required int id,
  required String symbol,
  double quantity = 1000,
  double avgCost = 100,
  double realizedPnl = 0,
  double totalDividendReceived = 0,
  String? note,
}) {
  return PortfolioPositionEntry(
    id: id,
    symbol: symbol,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    note: note,
    createdAt: DateTime.utc(2026, 2, 13),
    updatedAt: DateTime.utc(2026, 2, 13),
  );
}

StockMasterEntry createStock({
  required String symbol,
  String? name,
  String? market,
  String? industry,
}) {
  return StockMasterEntry(
    symbol: symbol,
    name: name ?? '測試股票',
    market: market ?? 'TWSE',
    industry: industry ?? '半導體業',
    isActive: true,
    updatedAt: DateTime.utc(2026, 2, 13),
  );
}

DailyPriceEntry createPrice({required String symbol, double close = 100}) {
  return DailyPriceEntry(
    symbol: symbol,
    date: DateTime.utc(2026, 2, 13),
    open: close,
    high: close * 1.02,
    low: close * 0.98,
    close: close,
    volume: 10000,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockPortfolioRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockDb = MockAppDatabase();
    mockRepo = MockPortfolioRepository();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        portfolioRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('TransactionType', () {
    test('fromValue converts string to enum', () {
      expect(TransactionType.fromValue('BUY'), TransactionType.buy);
      expect(TransactionType.fromValue('SELL'), TransactionType.sell);
      expect(
        TransactionType.fromValue('DIVIDEND_CASH'),
        TransactionType.dividendCash,
      );
      expect(
        TransactionType.fromValue('DIVIDEND_STOCK'),
        TransactionType.dividendStock,
      );
    });

    test('value returns correct string', () {
      expect(TransactionType.buy.value, 'BUY');
      expect(TransactionType.sell.value, 'SELL');
    });
  });

  group('PortfolioPositionData', () {
    test('marketValue uses currentPrice when available', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 0,
        totalDividendReceived: 0,
        currentPrice: 600,
      );

      expect(pos.marketValue, 600000); // 1000 * 600
    });

    test('marketValue falls back to avgCost when no currentPrice', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 0,
        totalDividendReceived: 0,
      );

      expect(pos.marketValue, 500000); // 1000 * 500
    });

    test('unrealizedPnl calculates correctly', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 0,
        totalDividendReceived: 0,
        currentPrice: 600,
      );

      expect(pos.unrealizedPnl, 100000); // (600-500)*1000
    });

    test('unrealizedPnl is zero when no currentPrice', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 0,
        totalDividendReceived: 0,
      );

      expect(pos.unrealizedPnl, 0);
    });

    test('unrealizedPnlPct calculates correctly', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 0,
        totalDividendReceived: 0,
        currentPrice: 600,
      );

      expect(pos.unrealizedPnlPct, 20.0); // (600-500)/500 * 100
    });

    test('unrealizedPnlPct is zero when avgCost is zero', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 0, // e.g. from stock dividend
        realizedPnl: 0,
        totalDividendReceived: 0,
        currentPrice: 600,
      );

      expect(pos.unrealizedPnlPct, 0); // avoids division by zero
    });

    test('totalPnl includes realized + unrealized + dividends', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 50000,
        totalDividendReceived: 10000,
        currentPrice: 600,
      );

      // realized(50000) + unrealized(100000) + dividends(10000)
      expect(pos.totalPnl, 160000);
    });

    test('costBasis is quantity * avgCost', () {
      const pos = PortfolioPositionData(
        symbol: '2330',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 0,
        totalDividendReceived: 0,
      );

      expect(pos.costBasis, 500000);
    });
  });

  group('PortfolioSummary', () {
    test('empty summary has all zeros', () {
      expect(PortfolioSummary.empty.totalMarketValue, 0);
      expect(PortfolioSummary.empty.positionCount, 0);
      expect(PortfolioSummary.empty.totalPnl, 0);
      expect(PortfolioSummary.empty.totalPnlPct, 0);
    });

    test('totalPnlPct is 0 when totalCostBasis is 0', () {
      const summary = PortfolioSummary(
        totalMarketValue: 0,
        totalCostBasis: 0,
        totalUnrealizedPnl: 0,
        totalRealizedPnl: 0,
        totalDividends: 0,
        positionCount: 0,
      );

      expect(summary.totalPnlPct, 0);
    });
  });

  group('PortfolioState', () {
    test('has correct default values', () {
      const state = PortfolioState();

      expect(state.positions, isEmpty);
      expect(state.performance, isNull);
      expect(state.dividendAnalysis, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('summary returns empty when no positions', () {
      const state = PortfolioState();
      final summary = state.summary;

      expect(summary.positionCount, 0);
      expect(summary.totalMarketValue, 0);
    });

    test('summary calculates from positions', () {
      const state = PortfolioState(
        positions: [
          PortfolioPositionData(
            symbol: '2330',
            quantity: 1000,
            avgCost: 500,
            realizedPnl: 0,
            totalDividendReceived: 0,
            currentPrice: 600,
          ),
          PortfolioPositionData(
            symbol: '2317',
            quantity: 500,
            avgCost: 100,
            realizedPnl: 0,
            totalDividendReceived: 0,
            currentPrice: 120,
          ),
        ],
      );

      final summary = state.summary;
      expect(summary.positionCount, 2);
      expect(summary.totalMarketValue, 660000); // 600*1000 + 120*500
      expect(summary.totalCostBasis, 550000); // 500*1000 + 100*500
      expect(summary.totalUnrealizedPnl, 110000); // 100*1000 + 20*500
    });

    test('summary positionCount excludes zero-quantity positions', () {
      const state = PortfolioState(
        positions: [
          PortfolioPositionData(
            symbol: '2330',
            quantity: 1000,
            avgCost: 500,
            realizedPnl: 0,
            totalDividendReceived: 0,
          ),
          PortfolioPositionData(
            symbol: '2317',
            quantity: 0, // sold all
            avgCost: 100,
            realizedPnl: 5000,
            totalDividendReceived: 0,
          ),
        ],
      );

      expect(state.summary.positionCount, 1);
    });

    test('allocationMap calculates percentages', () {
      const state = PortfolioState(
        positions: [
          PortfolioPositionData(
            symbol: '2330',
            quantity: 1000,
            avgCost: 500,
            realizedPnl: 0,
            totalDividendReceived: 0,
            currentPrice: 600,
          ),
          PortfolioPositionData(
            symbol: '2317',
            quantity: 1000,
            avgCost: 100,
            realizedPnl: 0,
            totalDividendReceived: 0,
            currentPrice: 200,
          ),
        ],
      );

      final allocation = state.allocationMap;
      // 2330: 600000 / 800000 = 75%
      // 2317: 200000 / 800000 = 25%
      expect(allocation['2330'], 75.0);
      expect(allocation['2317'], 25.0);
    });

    test('allocationMap is empty when total value is zero', () {
      const state = PortfolioState(
        positions: [
          PortfolioPositionData(
            symbol: '2330',
            quantity: 0,
            avgCost: 500,
            realizedPnl: 0,
            totalDividendReceived: 0,
          ),
        ],
      );

      expect(state.allocationMap, isEmpty);
    });

    test('copyWith preserves error with sentinel', () {
      const original = PortfolioState(error: 'Some error');

      // Not passing error should preserve it
      final state1 = original.copyWith(isLoading: true);
      expect(state1.error, 'Some error');

      // Explicitly passing null should clear it
      final state2 = original.copyWith(error: null);
      expect(state2.error, isNull);
    });
  });

  group('PortfolioNotifier', () {
    test('initial state is empty', () {
      final state = container.read(portfolioProvider);

      expect(state.positions, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('loadPositions with empty portfolio', () async {
      when(() => mockDb.getPortfolioPositions()).thenAnswer((_) async => []);

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.loadPositions();

      final state = container.read(portfolioProvider);
      expect(state.isLoading, isFalse);
      expect(state.positions, isEmpty);
      expect(state.performance, isNotNull);
      expect(state.dividendAnalysis, isNotNull);
    });

    test('loadPositions loads positions with stock info and prices', () async {
      final positions = [
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ];

      when(
        () => mockDb.getPortfolioPositions(),
      ).thenAnswer((_) async => positions);

      when(() => mockDb.getStocksBatch(any())).thenAnswer(
        (_) async => {'2330': createStock(symbol: '2330', name: '台積電')},
      );

      when(() => mockDb.getLatestPricesBatch(any())).thenAnswer(
        (_) async => {'2330': createPrice(symbol: '2330', close: 600)},
      );

      when(
        () => mockDb.getAllPortfolioTransactions(),
      ).thenAnswer((_) async => []);

      when(
        () => mockDb.getDividendHistoryBatch(any()),
      ).thenAnswer((_) async => {});

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.loadPositions();

      final state = container.read(portfolioProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.positions.length, 1);
      expect(state.positions[0].symbol, '2330');
      expect(state.positions[0].stockName, '台積電');
      expect(state.positions[0].currentPrice, 600.0);
      expect(state.positions[0].quantity, 1000);
    });

    test('loadPositions handles error gracefully', () async {
      when(
        () => mockDb.getPortfolioPositions(),
      ).thenThrow(Exception('DB Error'));

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.loadPositions();

      final state = container.read(portfolioProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, isNotEmpty);
    });

    test('addBuy delegates to repository and reloads', () async {
      when(
        () => mockRepo.addBuyTransaction(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          quantity: any(named: 'quantity'),
          price: any(named: 'price'),
          fee: any(named: 'fee'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async {});

      // Setup for loadPositions (called after addBuy)
      when(() => mockDb.getPortfolioPositions()).thenAnswer((_) async => []);

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.addBuy(
        symbol: '2330',
        date: DateTime.utc(2026, 2, 13),
        quantity: 1000,
        price: 500,
      );

      verify(
        () => mockRepo.addBuyTransaction(
          symbol: '2330',
          date: DateTime.utc(2026, 2, 13),
          quantity: 1000,
          price: 500,
          fee: null,
          note: null,
        ),
      ).called(1);
    });

    test('addSell delegates to repository and reloads', () async {
      when(
        () => mockRepo.addSellTransaction(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          quantity: any(named: 'quantity'),
          price: any(named: 'price'),
          fee: any(named: 'fee'),
          tax: any(named: 'tax'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async {});

      when(() => mockDb.getPortfolioPositions()).thenAnswer((_) async => []);

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.addSell(
        symbol: '2330',
        date: DateTime.utc(2026, 2, 13),
        quantity: 500,
        price: 600,
      );

      verify(
        () => mockRepo.addSellTransaction(
          symbol: '2330',
          date: DateTime.utc(2026, 2, 13),
          quantity: 500,
          price: 600,
          fee: null,
          tax: null,
          note: null,
        ),
      ).called(1);
    });

    test('addDividend delegates to repository and reloads', () async {
      when(
        () => mockRepo.addDividendTransaction(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          amount: any(named: 'amount'),
          isCash: any(named: 'isCash'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async {});

      when(() => mockDb.getPortfolioPositions()).thenAnswer((_) async => []);

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.addDividend(
        symbol: '2330',
        date: DateTime.utc(2026, 2, 13),
        amount: 3.5,
        isCash: true,
      );

      verify(
        () => mockRepo.addDividendTransaction(
          symbol: '2330',
          date: DateTime.utc(2026, 2, 13),
          amount: 3.5,
          isCash: true,
          note: null,
        ),
      ).called(1);
    });

    test('deleteTransaction delegates to repository and reloads', () async {
      when(
        () => mockRepo.deleteTransaction(any(), any()),
      ).thenAnswer((_) async {});

      when(() => mockDb.getPortfolioPositions()).thenAnswer((_) async => []);

      final notifier = container.read(portfolioProvider.notifier);
      await notifier.deleteTransaction(42, '2330');

      verify(() => mockRepo.deleteTransaction(42, '2330')).called(1);
    });
  });
}

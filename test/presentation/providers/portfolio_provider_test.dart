import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/portfolio_repository.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockPortfolioRepository extends Mock implements PortfolioRepository {}

class _FixedClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 2, 21, 30);
}

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
  group('summary.unpricedCount(2026-08-29 靜默稽核 #5)', () {
    // 缺價持股以成本價計值、未實現損益恰為 0,混進總報酬——停牌/跌停
    // 鎖死的重倉股讓總報酬看起來平穩,aggregate 原本無任何「N 檔未計價」
    // 指標。
    PortfolioPositionData pos(String sym, {double? price, double qty = 1000}) =>
        PortfolioPositionData(
          symbol: sym,
          stockName: sym,
          market: 'TWSE',
          quantity: qty,
          avgCost: 100,
          realizedPnl: 0,
          totalDividendReceived: 0,
          currentPrice: price,
        );

    test('🚨 缺價的在倉持股要計數', () {
      final state = PortfolioState(
        positions: [pos('2330', price: 600), pos('9999'), pos('8888')],
      );
      expect(state.summary.unpricedCount, 2);
    });

    test('全部有價 → 0;已平倉(quantity 0)缺價不計', () {
      final state = PortfolioState(
        positions: [pos('2330', price: 600), pos('1111', qty: 0)],
      );
      expect(state.summary.unpricedCount, 0);
    });
  });

  setUpAll(() => registerFallbackValue(DateTime(2026)));

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
        appClockProvider.overrideWithValue(_FixedClock()),
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
    void stubPositions(
      List<PortfolioPositionEntry> positions, {
      required double close,
    }) {
      when(
        () => mockDb.getPortfolioPositions(),
      ).thenAnswer((_) async => positions);
      when(() => mockDb.getStocksBatch(any())).thenAnswer(
        (_) async => {
          for (final p in positions) p.symbol: createStock(symbol: p.symbol),
        },
      );
      when(() => mockDb.getLatestPricesBatch(any())).thenAnswer(
        (_) async => {
          for (final p in positions)
            p.symbol: createPrice(symbol: p.symbol, close: close),
        },
      );
      when(
        () => mockDb.getAllPortfolioTransactions(),
      ).thenAnswer((_) async => []);
    }

    /// 兩市場 2021-01～2026-09 完成、10 月列到 10/2（_FixedClock 的今天）
    List<DividendListingEntry> fullListings() => [
      for (final market in [MarketCode.twse, MarketCode.tpex])
        DividendListingEntry(
          market: market,
          year: 2026,
          month: 10,
          listedThrough: DateTime(2026, 10, 2),
        ),
    ];

    List<DividendMonthLedgerEntry> fullLedger() => [
      for (final market in [MarketCode.twse, MarketCode.tpex])
        for (final m in CalendarMonth.descending(
          from: const CalendarMonth(2021, 1),
          to: const CalendarMonth(2026, 9),
        ))
          DividendMonthLedgerEntry(
            market: market,
            year: m.year,
            month: m.month,
            completedAt: DateTime(2026, 10, 1),
            listedRows: 1,
            knownRows: 1,
            skippedSymbols: '',
            pricesRecorded: true,
          ),
    ];

    /// 2330 近一年只有 2026-09-16 一次除息：近一年殖利率＝7 ÷ 2385
    final distributions2330 = {
      '2330': [
        DividendDistributionEntry(
          symbol: '2330',
          exDate: DateTime(2026, 9, 16),
          cashDividend: 7,
          stockSharesPerThousand: 0,
          closeBefore: 2385,
          referencePrice: 2378,
        ),
      ],
    };

    StockValuationEntry valuation2330({
      required DateTime date,
      double? dividendYield = 2.0,
    }) => StockValuationEntry(
      symbol: '2330',
      date: date,
      per: 20,
      pbr: 5,
      dividendYield: dividendYield,
    );

    /// 股利分析的讀取：完整度事實、配發表、官方估值與估值日收盤
    void stubDividendReads({
      List<DividendListingEntry> listings = const [],
      List<DividendMonthLedgerEntry> ledger = const [],
      Map<String, List<DividendDistributionEntry>> distributions = const {},
      Map<String, StockValuationEntry> valuations = const {},
      Map<(String, DateTime), DailyPriceEntry> pricesOnDate = const {},
    }) {
      when(
        () => mockDb.getDividendListings(),
      ).thenAnswer((_) async => listings);
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => ledger);
      when(() => mockDb.getDividendUnresolved()).thenAnswer((_) async => []);
      when(
        () => mockDb.getDividendMissingPriceKeys(),
      ).thenAnswer((_) async => <(String, DateTime)>{});
      when(
        () => mockDb.getDividendDistributionsBatch(any()),
      ).thenAnswer((_) async => distributions);
      when(
        () => mockDb.getLatestValuationsBatch(any()),
      ).thenAnswer((_) async => valuations);
      when(() => mockDb.getPriceOnDate(any(), any())).thenAnswer(
        (inv) async =>
            pricesOnDate[(
              inv.positionalArguments[0] as String,
              inv.positionalArguments[1] as DateTime,
            )],
      );
    }

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

      stubDividendReads();

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

    test('股利分析：官方殖利率 × 估值日收盤（不是最新收盤）', () async {
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ], close: 1200);
      stubDividendReads(
        valuations: {
          '2330': StockValuationEntry(
            symbol: '2330',
            date: DateTime(2026, 9, 30),
            per: 20,
            pbr: 5,
            dividendYield: 2.0,
          ),
        },
        pricesOnDate: {
          ('2330', DateTime(2026, 9, 30)): createPrice(
            symbol: '2330',
            close: 1000,
          ),
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(info.estimatedDividendPerShare, closeTo(20, 1e-9));
    });

    test('股利分析：估值日沒有收盤→改走近一年殖利率 × 最新收盤', () async {
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ], close: 1200);
      stubDividendReads(
        listings: fullListings(),
        ledger: fullLedger(),
        distributions: distributions2330,
        valuations: {'2330': valuation2330(date: DateTime(2026, 9, 30))},
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(info.estimatedDividendPerShare, closeTo(7 / 2385 * 1200, 1e-9));
    });

    test('股利分析：官方估值的殖利率是空的→改走近一年殖利率', () async {
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ], close: 1200);
      stubDividendReads(
        listings: fullListings(),
        ledger: fullLedger(),
        distributions: distributions2330,
        valuations: {
          '2330': valuation2330(
            date: DateTime(2026, 9, 30),
            dividendYield: null,
          ),
        },
        pricesOnDate: {
          ('2330', DateTime(2026, 9, 30)): createPrice(
            symbol: '2330',
            close: 1000,
          ),
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(info.estimatedDividendPerShare, closeTo(7 / 2385 * 1200, 1e-9));
    });

    test('🚨 股利分析：過時的官方估值（早於 30 天）不用→改走近一年殖利率', () async {
      // 上櫃估值只同步自選與候選股，持股可能停在很久以前的一筆；中間若有
      // 分割，舊的每股股利 × 現在的股數會放大好幾倍
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ], close: 1200);
      stubDividendReads(
        listings: fullListings(),
        ledger: fullLedger(),
        distributions: distributions2330,
        valuations: {'2330': valuation2330(date: DateTime(2026, 8, 1))},
        pricesOnDate: {
          ('2330', DateTime(2026, 8, 1)): createPrice(
            symbol: '2330',
            close: 1000,
          ),
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(info.estimatedDividendPerShare, closeTo(7 / 2385 * 1200, 1e-9));
    });

    test('股利分析：官方估值的新鮮度下限是 30 天（與個股頁同一個）', () async {
      // _FixedClock＝10/2 21:30，下限＝9/2 21:30：9/3 的估值用、9/2 的不用
      // （常數是 29 天時 9/3 也不用、31 天時 9/2 也會用，兩邊都會紅）
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
        createPosition(id: 2, symbol: '2317', quantity: 1000, avgCost: 100),
      ], close: 1200);
      stubDividendReads(
        listings: fullListings(),
        ledger: fullLedger(),
        distributions: distributions2330,
        valuations: {
          '2330': valuation2330(date: DateTime(2026, 9, 3)),
          '2317': StockValuationEntry(
            symbol: '2317',
            date: DateTime(2026, 9, 2),
            per: 12,
            pbr: 1.5,
            dividendYield: 2.0,
          ),
        },
        pricesOnDate: {
          ('2330', DateTime(2026, 9, 3)): createPrice(
            symbol: '2330',
            close: 1000,
          ),
          ('2317', DateTime(2026, 9, 2)): createPrice(
            symbol: '2317',
            close: 200,
          ),
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final perShare = {
        for (final s
            in container
                .read(portfolioProvider)
                .dividendAnalysis!
                .stockDividends)
          s.symbol: s.estimatedDividendPerShare,
      };
      // 2330：官方 2% × 1000；2317：過時→近一年殖利率，近 400 天完整且沒有除息＝0
      expect(perShare['2330'], closeTo(20, 1e-9));
      expect(perShare['2317'], 0);
    });

    test('🚨 股利分析：完整度事實全空（新安裝）→走近一年殖利率的持股建置中、合計 null', () async {
      stubPositions([
        createPosition(id: 1, symbol: '0050', quantity: 1000, avgCost: 100),
      ], close: 112.8);
      stubDividendReads();

      await container.read(portfolioProvider.notifier).loadPositions();

      final state = container.read(portfolioProvider);
      expect(state.error, isNull);
      final analysis = state.dividendAnalysis!;
      expect(analysis.stockDividends.single.estimatedDividendPerShare, isNull);
      expect(analysis.totalExpectedDividend, isNull);
    });

    test('股利分析：先讀完整度事實、再讀配發列（與個股頁同一個順序）', () async {
      stubPositions([
        createPosition(id: 1, symbol: '0050', quantity: 1000, avgCost: 100),
      ], close: 112.8);
      stubDividendReads();

      await container.read(portfolioProvider.notifier).loadPositions();

      verifyInOrder([
        () => mockDb.getDividendListings(),
        () => mockDb.getDividendMonthLedgerEntries(),
        () => mockDb.getDividendUnresolved(),
        () => mockDb.getDividendMissingPriceKeys(),
        () => mockDb.getDividendDistributionsBatch(any()),
      ]);
    });

    test('股利分析：ETF 以配發表算近一年殖利率 × 最新收盤', () async {
      stubPositions([
        createPosition(id: 1, symbol: '0050', quantity: 1000, avgCost: 100),
      ], close: 112.8);
      stubDividendReads(
        listings: fullListings(),
        ledger: fullLedger(),
        distributions: {
          '0050': [
            DividendDistributionEntry(
              symbol: '0050',
              exDate: DateTime(2026, 7, 21),
              cashDividend: 0.6,
              stockSharesPerThousand: 0,
              closeBefore: 99.2,
              referencePrice: 98.6,
            ),
            DividendDistributionEntry(
              symbol: '0050',
              exDate: DateTime(2026, 1, 22),
              cashDividend: 1.0,
              stockSharesPerThousand: 0,
              closeBefore: 71.85,
              referencePrice: 70.85,
            ),
          ],
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(
        info.estimatedDividendPerShare,
        closeTo((0.6 / 99.2 + 1.0 / 71.85) * 112.8, 1e-9),
      );
    });
  });
}

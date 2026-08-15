import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/domain/services/rule_accuracy_service.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

class MockDataSyncService extends Mock implements DataSyncService {}

class MockRuleAccuracyService extends Mock implements RuleAccuracyService {}

class MockWatchlistNotifier extends Notifier<WatchlistState>
    with Mock
    implements WatchlistNotifier {
  @override
  WatchlistState build() => WatchlistState();

  @override
  Future<bool> addStock(String symbol) async => true;

  @override
  Future<bool> removeStock(String symbol) async => true;
}

class MockAppClock extends Mock implements AppClock {}

// ==========================================
// Test Helpers
// ==========================================

const _testSymbol = '2330';
final _defaultDate = DateTime(2026, 2, 13);

StockMasterEntry createStock({
  String symbol = _testSymbol,
  String name = '台積電',
  String market = 'TWSE',
}) {
  return StockMasterEntry(
    symbol: symbol,
    name: name,
    market: market,
    industry: '半導體',
    isActive: true,
    updatedAt: _defaultDate,
  );
}

DailyPriceEntry createPrice({
  String symbol = _testSymbol,
  DateTime? date,
  double close = 600.0,
}) {
  final d = date ?? _defaultDate;
  return DailyPriceEntry(
    symbol: symbol,
    date: d,
    open: close * 0.99,
    high: close * 1.02,
    low: close * 0.98,
    close: close,
    volume: 50000,
  );
}

DailyAnalysisEntry createAnalysis({
  String symbol = _testSymbol,
  DateTime? date,
  double score = 75.0,
}) {
  return DailyAnalysisEntry(
    symbol: symbol,
    date: date ?? _defaultDate,
    scoreShort: score,
    scoreLong: score,
    trendState: 'BULLISH',
    reversalState: '',
    computedAt: date ?? _defaultDate,
  );
}

DailyReasonEntry createReason({
  String symbol = _testSymbol,
  DateTime? date,
  int rank = 1,
  String reasonType = 'GOLDEN_CROSS',
}) {
  return DailyReasonEntry(
    symbol: symbol,
    date: date ?? _defaultDate,
    rank: rank,
    reasonType: reasonType,
    evidenceJson: '{}',
    ruleScoreShort: 10.0,
    ruleScoreLong: 10.0,
  );
}

DailyInstitutionalEntry createInstitutional({
  String symbol = _testSymbol,
  DateTime? date,
  double foreignNet = 1000.0,
}) {
  return DailyInstitutionalEntry(
    symbol: symbol,
    date: date ?? _defaultDate,
    foreignNet: foreignNet,
    investmentTrustNet: 500.0,
    dealerNet: -200.0,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockFinMind;
  late MockInsiderRepository mockInsiderRepo;
  late MockDataSyncService mockDataSyncService;
  late MockRuleAccuracyService mockRuleAccuracy;
  late MockAppClock mockClock;
  late ProviderContainer container;

  /// 設定 loadData 所需的所有 mock 行為
  void setupLoadDataMocks({
    StockMasterEntry? stock,
    List<DailyPriceEntry>? priceHistory,
    List<DailyPriceEntry>? recentPrices,
    DailyAnalysisEntry? analysis,
    List<DailyReasonEntry>? reasons,
    List<DailyInstitutionalEntry>? instHistory,
    bool isInWatchlist = false,
    DateTime? latestDataDate,
  }) {
    final defaultPriceHistory =
        priceHistory ??
        [
          createPrice(date: DateTime(2026, 2, 12), close: 595.0),
          createPrice(date: _defaultDate, close: 600.0),
        ];
    final defaultRecentPrices =
        recentPrices ??
        [
          createPrice(date: _defaultDate, close: 600.0),
          createPrice(date: DateTime(2026, 2, 12), close: 595.0),
        ];
    final defaultInstHistory =
        instHistory ?? [createInstitutional(date: _defaultDate)];

    when(
      () => mockDb.getLatestDataDate(),
    ).thenAnswer((_) async => latestDataDate ?? _defaultDate);
    when(
      () => mockDb.getStock(_testSymbol),
    ).thenAnswer((_) async => stock ?? createStock());
    when(
      () => mockDb.getPriceHistory(
        _testSymbol,
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => defaultPriceHistory);
    when(
      () => mockDb.getRecentPrices(_testSymbol, count: 2),
    ).thenAnswer((_) async => defaultRecentPrices);
    when(
      () => mockDb.getAnalysis(_testSymbol, any()),
    ).thenAnswer((_) async => analysis ?? createAnalysis());
    when(
      () => mockDb.getReasons(_testSymbol, any()),
    ).thenAnswer((_) async => reasons ?? [createReason()]);
    when(
      () => mockDb.getInstitutionalHistory(
        _testSymbol,
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => defaultInstHistory);
    when(
      () => mockDb.isInWatchlist(_testSymbol),
    ).thenAnswer((_) async => isInWatchlist);

    // DataSyncService
    when(
      () => mockDataSyncService.synchronizeDataDates(any(), any()),
    ).thenReturn((
      latestPrice: defaultPriceHistory.last,
      institutionalHistory: defaultInstHistory,
      dataDate: _defaultDate,
      hasDataMismatch: false,
    ));
  }

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(<DailyPriceEntry>[]);
    registerFallbackValue(<DailyInstitutionalEntry>[]);
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockFinMind = MockFinMindClient();
    mockInsiderRepo = MockInsiderRepository();
    mockDataSyncService = MockDataSyncService();
    mockRuleAccuracy = MockRuleAccuracyService();
    mockClock = MockAppClock();

    when(() => mockClock.now()).thenReturn(_defaultDate);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        finMindClientProvider.overrideWithValue(mockFinMind),
        insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
        dataSyncServiceProvider.overrideWithValue(mockDataSyncService),
        ruleAccuracyServiceProvider.overrideWithValue(mockRuleAccuracy),
        appClockProvider.overrideWithValue(mockClock),
        watchlistProvider.overrideWith(() => MockWatchlistNotifier()),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // ==========================================
  // StockDetailNotifier.loadData
  // ==========================================

  group('StockDetailNotifier.loadData', () {
    test('initial state has correct defaults', () {
      setupLoadDataMocks();

      final state = container.read(stockDetailProvider(_testSymbol));

      expect(state.loading.isLoading, isFalse);
      expect(state.price.stock, isNull);
      expect(state.error, isNull);
    });

    test('sets loading state and loads all data', () async {
      setupLoadDataMocks();

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      final loadFuture = notifier.loadData();

      // 驗證 loading 狀態
      expect(
        container.read(stockDetailProvider(_testSymbol)).loading.isLoading,
        isTrue,
      );

      await loadFuture;

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.price.stock, isNotNull);
      expect(state.price.stock!.name, equals('台積電'));
      expect(state.price.latestPrice, isNotNull);
      expect(state.price.priceHistory, hasLength(2));
      expect(state.reasons, hasLength(1));
      expect(state.chip.institutionalHistory, hasLength(1));
      expect(state.aiSummary, isNotNull);
      expect(state.dataDate, equals(_defaultDate));
    });

    test('handles missing stock gracefully', () async {
      setupLoadDataMocks();
      when(() => mockDb.getStock(_testSymbol)).thenAnswer((_) async => null);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.price.stock, isNull);
      expect(state.stockName, isNull);
    });

    test('falls back to API when DB has no institutional data', () async {
      setupLoadDataMocks(instHistory: []);
      when(
        () => mockDb.getInstitutionalHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => <DailyInstitutionalEntry>[]);

      // Mock FinMindClient.getInstitutionalData
      when(
        () => mockFinMind.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => <FinMindInstitutional>[]);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoading, isFalse);
      expect(state.error, isNull);

      // 驗證確實呼叫了 API fallback
      verify(
        () => mockFinMind.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });

    test('handles error gracefully', () async {
      when(
        () => mockDb.getLatestDataDate(),
      ).thenThrow(Exception('Database corrupted'));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoading, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, isNotEmpty);
    });

    test('clears previous error on successful load', () async {
      // 先觸發錯誤
      when(
        () => mockDb.getLatestDataDate(),
      ).thenThrow(Exception('First error'));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      expect(container.read(stockDetailProvider(_testSymbol)).error, isNotNull);

      // 重設 mock 為成功
      setupLoadDataMocks();
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.error, isNull);
      expect(state.price.stock, isNotNull);
    });

    test('handles null latestDataDate', () async {
      setupLoadDataMocks();
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => null);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('sets isInWatchlist from DB', () async {
      setupLoadDataMocks(isInWatchlist: true);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.isInWatchlist, isTrue);
    });

    test('handles data mismatch correctly', () async {
      final priceHistory = [
        createPrice(date: DateTime(2026, 2, 11), close: 590.0),
        createPrice(date: DateTime(2026, 2, 12), close: 595.0),
        createPrice(date: _defaultDate, close: 600.0),
      ];

      setupLoadDataMocks(priceHistory: priceHistory);

      when(
        () => mockDataSyncService.synchronizeDataDates(any(), any()),
      ).thenReturn((
        latestPrice: priceHistory[1],
        institutionalHistory: [
          createInstitutional(date: DateTime(2026, 2, 12)),
        ],
        dataDate: DateTime(2026, 2, 12),
        hasDataMismatch: true,
      ));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.hasDataMismatch, isTrue);
      expect(state.dataDate, equals(DateTime(2026, 2, 12)));
    });

    test('with empty reasons', () async {
      setupLoadDataMocks(reasons: []);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.reasons, isEmpty);
    });
  });

  // ==========================================
  // StockDetailNotifier.toggleWatchlist
  // ==========================================

  group('StockDetailNotifier.toggleWatchlist', () {
    test('adds to watchlist when not in watchlist', () async {
      setupLoadDataMocks(isInWatchlist: false);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.toggleWatchlist();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.isInWatchlist, isTrue);
    });

    test('removes from watchlist when in watchlist', () async {
      setupLoadDataMocks(isInWatchlist: true);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.toggleWatchlist();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.isInWatchlist, isFalse);
    });
  });

  // ==========================================
  // StockDetailNotifier.loadFundamentals
  // ==========================================

  group('StockDetailNotifier.loadFundamentals', () {
    test('handles error gracefully', () async {
      setupLoadDataMocks();

      when(
        () => mockDb.getValuationHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('Valuation API error'));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadFundamentals();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoadingFundamentals, isFalse);
      expect(state.error, isNull);
    });
  });

  // ==========================================
  // StockDetailNotifier.loadInsiderData
  // ==========================================

  group('StockDetailNotifier.loadInsiderData', () {
    test('loads insider data from DB', () async {
      setupLoadDataMocks();

      final insiderData = <InsiderHoldingEntry>[
        InsiderHoldingEntry(
          symbol: _testSymbol,
          date: _defaultDate,
          pledgeRatio: 5.0,
        ),
      ];

      when(
        () => mockInsiderRepo.getInsiderHoldingHistory(
          _testSymbol,
          months: any(named: 'months'),
        ),
      ).thenAnswer((_) async => insiderData);
      when(
        () =>
            mockDb.getRecentTransfers(_testSymbol, limit: any(named: 'limit')),
      ).thenAnswer((_) async => <InsiderTransferEntry>[]);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadInsiderData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.chip.insiderHistory, hasLength(1));
      expect(state.loading.isLoadingInsider, isFalse);
    });

    test('skips when already loaded', () async {
      setupLoadDataMocks();

      final insiderData = <InsiderHoldingEntry>[
        InsiderHoldingEntry(
          symbol: _testSymbol,
          date: _defaultDate,
          pledgeRatio: 5.0,
        ),
      ];

      when(
        () => mockInsiderRepo.getInsiderHoldingHistory(
          _testSymbol,
          months: any(named: 'months'),
        ),
      ).thenAnswer((_) async => insiderData);
      when(
        () =>
            mockDb.getRecentTransfers(_testSymbol, limit: any(named: 'limit')),
      ).thenAnswer((_) async => <InsiderTransferEntry>[]);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadInsiderData();
      await notifier.loadInsiderData(); // 第二次應跳過

      verify(
        () => mockInsiderRepo.getInsiderHoldingHistory(
          _testSymbol,
          months: any(named: 'months'),
        ),
      ).called(1);
    });
  });

  // ==========================================
  // StockDetailNotifier.loadChipData
  // ==========================================

  group('StockDetailNotifier.loadChipData', () {
    test('loads all chip data', () async {
      setupLoadDataMocks();

      when(
        () => mockDb.getDayTradingHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <DayTradingEntry>[]);
      when(
        () => mockDb.getShareholdingHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <ShareholdingEntry>[]);
      when(
        () => mockDb.getMarginTradingHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <MarginTradingEntry>[]);
      when(
        () => mockDb.getLatestHoldingDistribution(_testSymbol),
      ).thenAnswer((_) async => <HoldingDistributionEntry>[]);
      when(
        () => mockDb.getRecentInsiderHoldings(
          _testSymbol,
          months: any(named: 'months'),
        ),
      ).thenAnswer((_) async => <InsiderHoldingEntry>[]);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadChipData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoadingChip, isFalse);
      expect(state.chip.chipStrength, isNotNull);
    });

    test('handles error gracefully', () async {
      setupLoadDataMocks();

      when(
        () => mockDb.getDayTradingHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenThrow(Exception('DB error'));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadChipData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoadingChip, isFalse);
    });
  });

  // ==========================================
  // primaryRuleAccuracySummaryProvider
  // ==========================================

  group('primaryRuleAccuracySummaryProvider', () {
    test('returns null when no reasons', () async {
      setupLoadDataMocks(reasons: []);

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final result = await container.read(
        primaryRuleAccuracySummaryProvider(_testSymbol).future,
      );

      expect(result, isNull);
    });

    test('uses primary reason with rank=1', () async {
      final reasons = [
        createReason(rank: 2, reasonType: 'VOLUME_BREAKOUT'),
        createReason(rank: 1, reasonType: 'GOLDEN_CROSS'),
      ];

      setupLoadDataMocks(reasons: reasons);

      when(
        () => mockRuleAccuracy.getRuleSummaryText('GOLDEN_CROSS'),
      ).thenAnswer((_) async => '命中率 65%，平均 5 日報酬 +2.3%');

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final result = await container.read(
        primaryRuleAccuracySummaryProvider(_testSymbol).future,
      );

      expect(result, equals('命中率 65%，平均 5 日報酬 +2.3%'));
      verify(
        () => mockRuleAccuracy.getRuleSummaryText('GOLDEN_CROSS'),
      ).called(1);
    });

    test('falls back to first reason when rank=1 not found', () async {
      final reasons = [
        createReason(rank: 2, reasonType: 'VOLUME_BREAKOUT'),
        createReason(rank: 3, reasonType: 'RSI_OVERSOLD'),
      ];

      setupLoadDataMocks(reasons: reasons);

      when(
        () => mockRuleAccuracy.getRuleSummaryText('VOLUME_BREAKOUT'),
      ).thenAnswer((_) async => '量能突破摘要');

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();

      final result = await container.read(
        primaryRuleAccuracySummaryProvider(_testSymbol).future,
      );

      expect(result, equals('量能突破摘要'));
    });
  });

  group('finMindClientProvider 失效重建', () {
    test('invalidate 後 notifier 重建,不得沿用已 dispose 的舊 client', () async {
      // 2026-07-29 審查發現:build() 用 ref.read 快照 client,使用者更新
      // token → finMindClientProvider invalidate → 舊 client 的 Dio 已被
      // close,存活頁面的 API fallback 全打在死連線上被 catch-all 吞掉,
      // 症狀恰為「設了 token 還是沒資料」。watch 語意下 invalidate 應
      // 重建 notifier(state 歸零、重新持有新 client)。
      //
      // override 用 factory 而非 value:每次 invalidate 產生新 instance,
      // 才會通知 dependents(same-value 不通知,測不出 read/watch 差異)。
      setupLoadDataMocks();
      final localContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
          finMindClientProvider.overrideWith((ref) => MockFinMindClient()),
          insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
          dataSyncServiceProvider.overrideWithValue(mockDataSyncService),
          ruleAccuracyServiceProvider.overrideWithValue(mockRuleAccuracy),
          appClockProvider.overrideWithValue(mockClock),
          watchlistProvider.overrideWith(() => MockWatchlistNotifier()),
        ],
      );
      addTearDown(localContainer.dispose);

      final sub = localContainer.listen(
        stockDetailProvider(_testSymbol),
        (_, _) {},
      );
      addTearDown(sub.close);

      await localContainer
          .read(stockDetailProvider(_testSymbol).notifier)
          .loadData();
      expect(
        localContainer.read(stockDetailProvider(_testSymbol)).price.stock,
        isNotNull,
        reason: '前置:資料已載入',
      );

      localContainer.invalidate(finMindClientProvider);
      await localContainer.pump();
      // 重建會清空 state;自動恢復走 microtask reload,多推幾輪事件圈
      await Future<void>.delayed(Duration.zero);
      await localContainer.pump();
      await Future<void>.delayed(Duration.zero);

      expect(
        localContainer.read(stockDetailProvider(_testSymbol)).price.stock,
        isNotNull,
        reason:
            '2026-08-01 複審:重建清空後必須自動 reload——否則使用者換個'
            ' token,開著的個股頁靜默變空白且永久卡死(epoch listener 的'
            ' guard 恰在清空後擋住自己,無任何恢復管道)',
      );
    });
  });
}

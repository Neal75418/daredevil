import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/domain/models/market_overview_models.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/domain/services/rule_accuracy_service.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
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

/// 加權收盤：到 [_defaultDate] 連漲 80 天（多頭排列），隔天跌到 MA20 下方
/// （均線糾結），第三天又漲回多頭
final _stageDays = [
  for (var i = 79; i >= 0; i--) _defaultDate.subtract(Duration(days: i)),
];
final List<DatedValue> _stageCloses = [
  for (var i = 0; i < 80; i++) (date: _stageDays[i], value: 100.0 + i),
  (date: _defaultDate.add(const Duration(days: 1)), value: 150.0),
  (date: _defaultDate.add(const Duration(days: 2)), value: 200.0),
];

/// [closes] 轉成 DB 的加權指數列
List<MarketIndexEntry> _taiexRows(List<DatedValue> closes) => [
  for (final (i, p) in closes.indexed)
    MarketIndexEntry(
      id: i,
      date: p.date,
      name: MarketIndexNames.taiex,
      close: p.value,
      change: 0,
      changePercent: 0,
      createdAt: p.date,
    ),
];

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
    List<DatedValue> taiexCloses = const [],
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
    when(
      () => mockDb.getIndexHistoryBatch(
        any(),
        days: any(named: 'days'),
        now: any(named: 'now'),
      ),
    ).thenAnswer(
      (_) async => {MarketIndexNames.taiex: _taiexRows(taiexCloses)},
    );

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
    registerFallbackValue(<String>[]);
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

  /// 分析與理由是 [_defaultDate] 的隔天，股價（對齊法人）仍是 [_defaultDate]
  void setupAnalysisAfterPriceMocks() {
    final analysisDay = _defaultDate.add(const Duration(days: 1));
    setupLoadDataMocks(
      latestDataDate: analysisDay,
      analysis: createAnalysis(date: analysisDay),
      reasons: [createReason(date: analysisDay)],
      taiexCloses: _stageCloses,
    );
  }

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

    /// 營收（6 個月）、EPS、估值都有：頁首錯誤只會來自股利
    void stubFundamentalsReads({Exception? dividendError}) {
      when(
        () => mockDb.getValuationHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer(
        (_) async => [
          StockValuationEntry(
            symbol: _testSymbol,
            date: _defaultDate,
            per: 20,
            pbr: 5,
            dividendYield: 2,
          ),
        ],
      );
      when(
        () => mockDb.getMonthlyRevenueHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer(
        (_) async => [
          for (var m = 1; m <= 6; m++)
            MonthlyRevenueEntry(
              symbol: _testSymbol,
              date: DateTime(2025, m + 1, 10),
              revenueYear: 2025,
              revenueMonth: m,
              revenue: 1e9,
            ),
        ],
      );
      when(() => mockDb.getEPSHistory(_testSymbol)).thenAnswer(
        (_) async => [
          FinancialDataEntry(
            symbol: _testSymbol,
            date: DateTime(2025, 11, 14),
            statementType: 'INCOME',
            dataType: 'EPS',
            value: 5,
          ),
        ],
      );
      when(
        () => mockDb.getLatestQuarterMetrics(_testSymbol),
      ).thenAnswer((_) async => {'ROE': 20.0});
      when(
        () => mockDb.getDividendDistributions(_testSymbol),
      ).thenAnswer((_) async => []);
      if (dividendError != null) {
        when(() => mockDb.getDividendListings()).thenThrow(dividendError);
      } else {
        when(() => mockDb.getDividendListings()).thenAnswer((_) async => []);
      }
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => []);
      when(() => mockDb.getDividendUnresolved()).thenAnswer((_) async => []);
      when(
        () => mockDb.getDividendMissingPriceKeys(),
      ).thenAnswer((_) async => <(String, DateTime)>{});
    }

    test('🚨 營收、估值載入後重產摘要：大盤位階仍算到分析那天', () async {
      setupAnalysisAfterPriceMocks();
      stubFundamentalsReads();

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      final loaded = container.read(stockDetailProvider(_testSymbol)).aiSummary;
      await notifier.loadFundamentals();

      final summary = container
          .read(stockDetailProvider(_testSymbol))
          .aiSummary;
      expect(summary, isNot(same(loaded)), reason: '營收、估值到了要重產摘要');
      expect(summary!.overallAssessment, contains('summary.marketNeutral'));
    });

    test('🚨 股利資料建置中（新安裝、尚無完整度事實）：頁首不出現錯誤', () async {
      setupLoadDataMocks();
      stubFundamentalsReads();

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadFundamentals();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.fundamentals.dividendSummary!.allBuilding, isTrue);
      expect(state.fundamentalsError, isNull);
    });

    test('股利讀取失敗：頁首錯誤含「股利」（可重試）', () async {
      setupLoadDataMocks();
      stubFundamentalsReads(dividendError: Exception('db locked'));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadFundamentals();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.fundamentals.dividendSummary, isNull);
      expect(state.fundamentalsError, contains('股利'));

      // 有錯誤就不跳過：再呼叫一次會重讀
      await notifier.loadFundamentals();
      verify(() => mockDb.getDividendListings()).called(2);
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

  group('StockDetailNotifier.loadData 重入', () {
    test('較早發起、較晚完成的載入不得覆蓋較新的結果', () async {
      setupLoadDataMocks();
      final older = DateTime(2026, 2, 12);
      final newer = DateTime(2026, 2, 13);
      final firstDate = Completer<DateTime?>();
      var dateCalls = 0;
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) {
        dateCalls++;
        return dateCalls == 1 ? firstDate.future : Future.value(newer);
      });
      when(
        () => mockDb.getAnalysis(_testSymbol, older),
      ).thenAnswer((_) async => createAnalysis(score: 10));
      when(
        () => mockDb.getAnalysis(_testSymbol, newer),
      ).thenAnswer((_) async => createAnalysis(score: 90));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      final first = notifier.loadData();
      await notifier.loadData();
      expect(
        container
            .read(stockDetailProvider(_testSymbol))
            .price
            .analysis!
            .scoreShort,
        90,
      );

      firstDate.complete(older);
      await first;

      expect(
        container
            .read(stockDetailProvider(_testSymbol))
            .price
            .analysis!
            .scoreShort,
        90,
        reason: '第一次載入讀到的是更新前的資料，晚到時不得蓋掉第二次的結果',
      );
    });

    test('重建前發起的載入，續行排在自動重載之前（microtask 窗口）：不得寫入舊資料，呼叫端等到自動重載完成', () async {
      // 舊一輪停在 .wait（getStock 未完成）；同一段同步程式裡依序完成它、
      // 重建 notifier——舊一輪的續行 microtask 排在 build() 的自動重載之前
      setupLoadDataMocks();
      final older = DateTime(2026, 2, 12);
      final newer = DateTime(2026, 2, 13);
      var dateCalls = 0;
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) async {
        dateCalls++;
        return dateCalls == 1 ? older : newer;
      });
      when(
        () => mockDb.getAnalysis(_testSymbol, older),
      ).thenAnswer((_) async => createAnalysis(score: 10));
      when(
        () => mockDb.getAnalysis(_testSymbol, newer),
      ).thenAnswer((_) async => createAnalysis(score: 90));
      final blockedStock = Completer<StockMasterEntry?>();
      var stockCalls = 0;
      when(() => mockDb.getStock(_testSymbol)).thenAnswer((_) {
        stockCalls++;
        return stockCalls == 1
            ? blockedStock.future
            : Future.value(createStock());
      });

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
      final scores = <double?>[];
      final sub = localContainer.listen(
        stockDetailProvider(_testSymbol),
        (_, next) => scores.add(next.price.analysis?.scoreShort),
      );
      addTearDown(sub.close);

      final stale = localContainer
          .read(stockDetailProvider(_testSymbol).notifier)
          .loadData();
      await Future<void>.delayed(Duration.zero);

      blockedStock.complete(createStock());
      localContainer.invalidate(finMindClientProvider);
      localContainer.read(stockDetailProvider(_testSymbol));
      await stale;
      expect(
        localContainer.read(stockDetailProvider(_testSymbol)).hasContent,
        isTrue,
        reason: '呼叫端（_swapTo）在 await 回來時據此切換畫面，不得先於自動重載完成',
      );
      await Future<void>.delayed(Duration.zero);
      await localContainer.pump();
      await Future<void>.delayed(Duration.zero);

      expect(scores, isNot(contains(10)), reason: '重建前的舊資料不得出現在畫面上');
      expect(scores.last, 90);
    });

    test('被取代那一輪的 Future 等到最新一輪寫入後才完成（_swapTo 依此切換）', () async {
      setupLoadDataMocks();
      final older = DateTime(2026, 2, 12);
      final newer = DateTime(2026, 2, 13);
      final firstDate = Completer<DateTime?>();
      final secondDate = Completer<DateTime?>();
      var dateCalls = 0;
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) {
        dateCalls++;
        return dateCalls == 1 ? firstDate.future : secondDate.future;
      });
      when(
        () => mockDb.getAnalysis(_testSymbol, newer),
      ).thenAnswer((_) async => createAnalysis(score: 90));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      var firstDone = false;
      final first = notifier.loadData().then((_) => firstDone = true);
      final second = notifier.loadData();

      firstDate.complete(older);
      await Future<void>.delayed(Duration.zero);
      expect(firstDone, isFalse, reason: '最新一輪還沒寫入，呼叫端不該以為已載完');

      secondDate.complete(newer);
      await first;
      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.loading.isLoading, isFalse);
      expect(state.price.analysis!.scoreShort, 90);
      await second;
    });

    test('被取代的載入晚到失敗時，不得把錯誤寫進較新的結果', () async {
      setupLoadDataMocks();
      final firstDate = Completer<DateTime?>();
      var dateCalls = 0;
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) {
        dateCalls++;
        return dateCalls == 1 ? firstDate.future : Future.value(_defaultDate);
      });

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      final first = notifier.loadData();
      await notifier.loadData();

      firstDate.completeError(Exception('Database error'));
      await first;

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.error, isNull);
      expect(state.price.analysis, isNotNull);
    });

    test('重建（換 token）前發起的載入，晚到時不得寫入重建後的 state', () async {
      setupLoadDataMocks();
      final older = DateTime(2026, 2, 12);
      final newer = DateTime(2026, 2, 13);
      final firstDate = Completer<DateTime?>();
      var dateCalls = 0;
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) {
        dateCalls++;
        return dateCalls == 1 ? firstDate.future : Future.value(newer);
      });
      when(
        () => mockDb.getAnalysis(_testSymbol, older),
      ).thenAnswer((_) async => createAnalysis(score: 10));
      when(
        () => mockDb.getAnalysis(_testSymbol, newer),
      ).thenAnswer((_) async => createAnalysis(score: 90));

      // factory override：每次 invalidate 產生新 instance，才會重建 notifier
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

      final stale = localContainer
          .read(stockDetailProvider(_testSymbol).notifier)
          .loadData();

      // 重建 → build() 排 microtask 自動重載（讀到 newer）
      localContainer.invalidate(finMindClientProvider);
      await localContainer.pump();
      await Future<void>.delayed(Duration.zero);
      await localContainer.pump();
      await Future<void>.delayed(Duration.zero);
      expect(
        localContainer
            .read(stockDetailProvider(_testSymbol))
            .price
            .analysis
            ?.scoreShort,
        90,
        reason: '前置：重建後的自動重載已完成',
      );

      firstDate.complete(older);
      await stale;

      expect(
        localContainer
            .read(stockDetailProvider(_testSymbol))
            .price
            .analysis!
            .scoreShort,
        90,
        reason: '_active 在 build() 重跑時被設回 true，擋不住重建前的載入',
      );
    });
  });

  // 證交所約 14:00 公布收盤、每日更新後 DB 就有今天的加權；個股分析可能還是前一天
  group('大盤位階對齊分析日', () {
    test('marketStageAsOf：只用到 asOf 那天為止的收盤', () {
      expect(marketStageAsOf(_stageCloses, _defaultDate), MarketStage.bullish);
      expect(
        marketStageAsOf(
          _stageCloses,
          _defaultDate.add(const Duration(days: 1)),
        ),
        MarketStage.neutral,
      );
    });

    test('marketStageAsOf：序列還沒有 asOf 那天 → null（不拿前一天的頂替）', () {
      expect(
        marketStageAsOf(
          _stageCloses.sublist(0, 80),
          _defaultDate.add(const Duration(days: 1)),
        ),
        isNull,
      );
    });

    test('marketStageAsOf：沒有資料日、沒有序列或不足 60 天 → null', () {
      expect(marketStageAsOf(_stageCloses, null), isNull);
      expect(marketStageAsOf(_stageCloses, DateTime(2000)), isNull);
      expect(marketStageAsOf(null, _defaultDate), isNull);
      expect(
        marketStageAsOf(_stageCloses.sublist(0, 59), _stageDays[58]),
        isNull,
      );
    });

    test('🚨 載入時：DB 已有隔天的收盤，摘要仍用分析那天的位階', () async {
      setupLoadDataMocks(taiexCloses: _stageCloses.sublist(0, 81));

      await container
          .read(stockDetailProvider(_testSymbol).notifier)
          .loadData();

      final summary = container
          .read(stockDetailProvider(_testSymbol))
          .aiSummary;
      expect(summary!.overallAssessment, contains('summary.marketBullish'));
    });

    // 上市法人 15:30 那輪還沒出來：分析已是今天，股價對齊法人仍停在前一天
    test('🚨 分析日比股價日新：位階算到分析那天（摘要的訊號是那天的）', () async {
      setupAnalysisAfterPriceMocks();

      await container
          .read(stockDetailProvider(_testSymbol).notifier)
          .loadData();

      final summary = container
          .read(stockDetailProvider(_testSymbol))
          .aiSummary;
      expect(summary!.overallAssessment, contains('summary.marketNeutral'));
      // 讀取窗口以分析日為終點：DB 落後很久時 MA60 仍有足夠天數
      verify(
        () => mockDb.getIndexHistoryBatch(
          any(),
          days: any(named: 'days'),
          now: _defaultDate.add(const Duration(days: 1)),
        ),
      ).called(1);
    });

    test('讀加權指數失敗：頁面照常載入，摘要不顯示位階', () async {
      setupLoadDataMocks();
      when(
        () => mockDb.getIndexHistoryBatch(
          any(),
          days: any(named: 'days'),
          now: any(named: 'now'),
        ),
      ).thenAnswer((_) async => throw Exception('db'));

      await container
          .read(stockDetailProvider(_testSymbol).notifier)
          .loadData();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.error, isNull);
      expect(
        state.aiSummary!.overallAssessment,
        isNot(contains('summary.market')),
      );
    });
  });
}

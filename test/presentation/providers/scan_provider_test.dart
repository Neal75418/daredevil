import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/presentation/providers/scan_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

class MockDataSyncService extends Mock implements DataSyncService {}

class FakeWatchlistNotifier extends WatchlistNotifier {
  WatchlistState initialState = WatchlistState();
  bool addStockResult = true;
  bool removeStockResult = true;
  String? lastAddedSymbol;
  String? lastRemovedSymbol;

  @override
  WatchlistState build() => initialState;

  @override
  Future<void> loadData() async {}

  @override
  Future<void> loadMore() async {}

  @override
  void setSearchQuery(String query) {}

  @override
  void setSort(WatchlistSort sort) {}

  @override
  void setGroup(WatchlistGroup group) {}

  @override
  Future<bool> addStock(String symbol) async {
    lastAddedSymbol = symbol;
    return addStockResult;
  }

  @override
  Future<bool> removeStock(String symbol) async {
    lastRemovedSymbol = symbol;
    return removeStockResult;
  }

  @override
  Future<void> restoreStock(String symbol) async {}
}

// ==========================================
// Test Helpers
// ==========================================

DailyAnalysisEntry createAnalysis({
  required String symbol,
  double score = 80.0,
  DateTime? date,
}) {
  return DailyAnalysisEntry(
    symbol: symbol,
    date: date ?? DateTime.utc(2026, 2, 13),
    trendState: 'BULLISH',
    reversalState: 'NONE',
    scoreShort: score,
    scoreLong: score,
    computedAt: DateTime.utc(2026, 2, 13),
  );
}

DailyReasonEntry createReason({
  required String symbol,
  String reasonType = 'VOLUME_BREAKOUT',
  DateTime? date,
}) {
  return DailyReasonEntry(
    symbol: symbol,
    date: date ?? DateTime.utc(2026, 2, 13),
    rank: 1,
    reasonType: reasonType,
    evidenceJson: '{}',
    ruleScoreShort: 10.0,
    ruleScoreLong: 10.0,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late MockAnalysisRepository mockAnalysisRepo;
  late MockDataSyncService mockDataSyncService;
  late FakeWatchlistNotifier fakeWatchlistNotifier;
  late ProviderContainer container;

  final testDate = DateTime.utc(2026, 2, 13);

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();
    mockAnalysisRepo = MockAnalysisRepository();
    mockDataSyncService = MockDataSyncService();
    fakeWatchlistNotifier = FakeWatchlistNotifier();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
        analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
        dataSyncServiceProvider.overrideWithValue(mockDataSyncService),
        watchlistProvider.overrideWith(() => fakeWatchlistNotifier),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  /// 設定 loadData 成功所需的完整 mock 行為
  void setupLoadDataDefaults({
    List<DailyAnalysisEntry> analyses = const [],
    Map<String, List<DailyReasonEntry>>? reasons,
  }) {
    when(
      () => mockAnalysisRepo.findLatestAnalyses(horizon: Horizon.long),
    ).thenAnswer((_) async => (targetDate: testDate, analyses: analyses));
    when(
      () => mockDb.getReasonsBatch(any(), any()),
    ).thenAnswer((_) async => reasons ?? {});
    // rs60Desc / priceChange 排序 metrics（預設空 → 排序 fallback tiebreak）
    when(
      () => mockDb.getPriceHistoryBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => {});
    when(() => mockDb.getLatestPricesBatch(any())).thenAnswer((_) async => {});
    when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => testDate);
    when(
      () => mockDb.getLatestInstitutionalDate(),
    ).thenAnswer((_) async => testDate);
    when(
      () => mockDataSyncService.getDisplayDataDate(any(), any()),
    ).thenReturn(testDate);
    when(
      () => mockDb.getDistinctIndustries(),
    ).thenAnswer((_) async => ['半導體業', '金融業']);
    when(() => mockDb.getWatchlist()).thenAnswer((_) async => []);
    when(
      () => mockDb.getTradeableUniverseCount(any()),
    ).thenAnswer((_) async => 850);
    when(
      () => mockCachedDb.loadScanData(
        symbols: any(named: 'symbols'),
        analysisDate: any(named: 'analysisDate'),
        historyStart: any(named: 'historyStart'),
      ),
    ).thenAnswer(
      (_) async => (
        stocks: <String, StockMasterEntry>{},
        latestPrices: <String, DailyPriceEntry>{},
        reasons: <String, List<DailyReasonEntry>>{},
        priceHistories: <String, List<DailyPriceEntry>>{},
      ),
    );
  }

  group('ScanState', () {
    test('has correct default values', () {
      const state = ScanState();

      expect(state.stocks, isEmpty);
      expect(state.filter, ScanFilter.all);
      expect(state.sort, ScanSort.rs60Desc);
      expect(state.industryFilter, isNull);
      expect(state.industries, isEmpty);
      expect(state.dataDate, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isFiltering, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.totalCount, 0);
      expect(state.totalAnalyzedCount, 0);
      expect(state.error, isNull);
    });

    test('copyWith creates new instance with updated values', () {
      const original = ScanState(isLoading: true, totalCount: 100);

      final updated = original.copyWith(isLoading: false, error: 'test');

      expect(updated.isLoading, isFalse);
      expect(updated.error, 'test');
      expect(updated.totalCount, 100); // preserved
    });

    test('copyWith with clearIndustryFilter clears industry', () {
      const original = ScanState(industryFilter: '半導體業');

      final updated = original.copyWith(clearIndustryFilter: true);

      expect(updated.industryFilter, isNull);
    });

    test('copyWith preserves industryFilter when not clearing', () {
      const original = ScanState(industryFilter: '半導體業');

      final updated = original.copyWith(isLoading: true);

      expect(updated.industryFilter, '半導體業');
    });
  });

  group('ScanStockItem', () {
    test('copyWith toggles watchlist', () {
      final item = ScanStockItem(
        symbol: '2330',
        score: 85.0,
        isInWatchlist: false,
      );

      final toggled = item.copyWith(isInWatchlist: true);

      expect(toggled.isInWatchlist, isTrue);
      expect(toggled.symbol, '2330');
      expect(toggled.score, 85.0);
    });

    test('reasonTypes computed from reasons', () {
      final item = ScanStockItem(
        symbol: '2330',
        score: 85.0,
        reasons: [
          createReason(symbol: '2330', reasonType: 'VOLUME_BREAKOUT'),
          createReason(symbol: '2330', reasonType: 'GOLDEN_CROSS'),
        ],
      );

      expect(item.reasonTypes, equals(['VOLUME_BREAKOUT', 'GOLDEN_CROSS']));
    });

    test('reasonTypes is empty when no reasons', () {
      final item = ScanStockItem(symbol: '2330', score: 85.0);

      expect(item.reasonTypes, isEmpty);
    });
  });

  group('ScanFilter', () {
    test('all filter has null reasonCode', () {
      expect(ScanFilter.all.reasonCode, isNull);
    });

    test('specific filter has non-null reasonCode', () {
      expect(ScanFilter.volumeSpike.reasonCode, isNotNull);
    });

    test('group filters returns correct members', () {
      final reversalFilters = ScanFilterGroup.reversal.filters;

      expect(reversalFilters, contains(ScanFilter.reversalW2S));
      expect(reversalFilters, contains(ScanFilter.reversalS2W));
      expect(reversalFilters.length, 2);
    });
  });

  group('ScanNotifier', () {
    test('initial state has default values', () {
      final state = container.read(scanProvider);

      expect(state.isLoading, isFalse);
      expect(state.stocks, isEmpty);
      expect(state.error, isNull);
    });

    test('loadData with no analyses results in empty state', () async {
      setupLoadDataDefaults(analyses: []);

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      final state = container.read(scanProvider);
      expect(state.isLoading, isFalse);
      expect(state.stocks, isEmpty);
      expect(state.totalCount, 0);
      expect(state.totalAnalyzedCount, 0);
      expect(state.hasMore, isFalse);
      expect(state.error, isNull);
    });

    test('loadData 池准入:正分訊號股+純空方(雙 0 指紋)股,負分濾除', () async {
      // 2026-07-31 契約更新:落庫門檻改 |raw| 後,「雙 horizon 皆 0」是
      // 純空方股的落庫指紋——必須進主池,BREAK_* 篩選器才撈得到。
      // 負分列在新契約下不會存在(floor 為 0),此處驗防禦行為。
      final analyses = [
        createAnalysis(symbol: '2330', score: 85),
        createAnalysis(symbol: '2317', score: 0), // 純空方指紋 → 進池
        createAnalysis(symbol: '2454', score: -5), // 不應存在的髒資料 → 濾除
      ];

      setupLoadDataDefaults(analyses: analyses);

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      final state = container.read(scanProvider);
      expect(state.totalAnalyzedCount, 2); // 2330(訊號)+2317(空方)
    });

    test('loadData sets loading state', () async {
      setupLoadDataDefaults();

      final notifier = container.read(scanProvider.notifier);
      final loadFuture = notifier.loadData();

      expect(container.read(scanProvider).isLoading, isTrue);

      await loadFuture;

      expect(container.read(scanProvider).isLoading, isFalse);
    });

    test('loadData handles error gracefully', () async {
      when(
        () => mockAnalysisRepo.findLatestAnalyses(horizon: Horizon.long),
      ).thenThrow(Exception('Database error'));

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      final state = container.read(scanProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, isNotEmpty);
    });

    test('loadData loads industries list', () async {
      setupLoadDataDefaults();

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      final state = container.read(scanProvider);
      expect(state.industries, equals(['半導體業', '金融業']));
    });

    test('setFilter skips if same filter', () {
      setupLoadDataDefaults();

      final notifier = container.read(scanProvider.notifier);
      final stateBefore = container.read(scanProvider);

      notifier.setFilter(ScanFilter.all); // same as default

      final stateAfter = container.read(scanProvider);
      expect(identical(stateBefore, stateAfter), isTrue);
    });

    test('setSort skips if same sort', () {
      setupLoadDataDefaults();

      final notifier = container.read(scanProvider.notifier);
      final stateBefore = container.read(scanProvider);

      notifier.setSort(ScanSort.rs60Desc); // same as default

      final stateAfter = container.read(scanProvider);
      expect(identical(stateBefore, stateAfter), isTrue);
    });

    test('toggleWatchlist toggles stock watchlist status', () async {
      // Pre-populate state with a stock item
      setupLoadDataDefaults(
        analyses: [createAnalysis(symbol: '2330', score: 85)],
      );

      // Override getWatchlist AFTER setupLoadDataDefaults (which sets it to [])
      // so _watchlistSymbols contains '2330'
      when(() => mockDb.getWatchlist()).thenAnswer(
        (_) async => [
          WatchlistEntry(symbol: '2330', createdAt: DateTime(2026, 1, 1)),
        ],
      );

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      // Now toggle (remove from watchlist)
      await notifier.toggleWatchlist('2330');

      expect(fakeWatchlistNotifier.lastRemovedSymbol, '2330');
    });

    test('toggleWatchlist adds to watchlist when not present', () async {
      setupLoadDataDefaults(
        analyses: [createAnalysis(symbol: '2330', score: 85)],
      );

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      await notifier.toggleWatchlist('2330');

      expect(fakeWatchlistNotifier.lastAddedSymbol, '2330');
    });

    test('toggleWatchlist clears stale error on success', () async {
      setupLoadDataDefaults(
        analyses: [createAnalysis(symbol: '2330', score: 85)],
      );

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      // 先製造一次失敗 → state.error 被設定
      fakeWatchlistNotifier.addStockResult = false;
      await notifier.toggleWatchlist('2330');
      expect(container.read(scanProvider).error, isNotNull);

      // 恢復成功 → 舊 error 應被清除
      fakeWatchlistNotifier.addStockResult = true;
      await notifier.toggleWatchlist('2330');
      expect(container.read(scanProvider).error, isNull);
    });

    test('loadMore does nothing when no more data', () async {
      setupLoadDataDefaults(analyses: []);

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      // hasMore is false after empty load
      await notifier.loadMore();

      final state = container.read(scanProvider);
      expect(state.isLoadingMore, isFalse);
    });

    test('setIndustryFilter sets filter and triggers reload', () async {
      setupLoadDataDefaults(
        analyses: [createAnalysis(symbol: '2330', score: 85)],
      );

      when(
        () => mockDb.getSymbolsByIndustry('半導體業'),
      ).thenAnswer((_) async => {'2330'});

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      await notifier.setIndustryFilter('半導體業');

      // _reloadFirstPage is fire-and-forget, let it complete
      await Future<void>.delayed(Duration.zero);

      final state = container.read(scanProvider);
      expect(state.industryFilter, '半導體業');
      expect(state.isFiltering, isFalse);
    });

    test('setIndustryFilter clears when null', () async {
      setupLoadDataDefaults(
        analyses: [createAnalysis(symbol: '2330', score: 85)],
      );

      when(
        () => mockDb.getSymbolsByIndustry('半導體業'),
      ).thenAnswer((_) async => {'2330'});

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      // Set industry
      await notifier.setIndustryFilter('半導體業');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(scanProvider).industryFilter, '半導體業');

      // Clear industry
      await notifier.setIndustryFilter(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(scanProvider).industryFilter, isNull);
    });

    group('🚨 產業篩選必須保留排序(稽核 C1)', () {
      // applyFilter 回傳**新 list**、applySort 是**就地排序**——兩個相反的
      // mutation 契約。於是每次 applyFilter 都丟掉上一次的排序,而只有
      // setFilter 記得補呼叫 applySort,setIndustryFilter 漏了。
      //
      // 後果不是「順序有點不一樣」:實測 2026-08-28 的掃描主清單(422 檔,
      // 述詞見 loadData 的 `(scoreLong>0 && isScanSignal) || isScanRiskVisible`),
      // 點一下產業籤 → 第一頁 top-20 只剩 2 檔重疊、中位排名位移 103 名。
      // 而且排序籤仍寫著「60日相對強度」,清單其實落回 DAO 的
      // `ORDER BY score DESC`——ScanSort 自己的文件記載 score 排序
      // 「corr ≈ 0.17 近乎無鑑別力」、60D RS 才是「+6.3% 單調、有實證
      // edge 的排序鍵」。無聲從有 edge 的鍵掉到沒有的那個。

      /// 61 根 K 棒:首收 100、末收 [lastClose] → ret60d = lastClose - 100 (%)
      List<DailyPriceEntry> history(String symbol, double lastClose) => [
        for (var i = 0; i < 61; i++)
          DailyPriceEntry(
            symbol: symbol,
            date: testDate.subtract(Duration(days: 61 - i)),
            open: 100,
            high: 100,
            low: 100,
            close: i == 60 ? lastClose : 100,
            volume: 1000000,
            priceChange: null,
          ),
      ];

      /// 三種順序**兩兩互異**,才能分辨清單實際用的是哪一個鍵：
      ///   DAO 回傳序(= 排序遺失時的落點)  1111 → 3333 → 2222
      ///   rs60Desc（預設）                3333 → 2222 → 1111
      ///   scoreAsc                        2222 → 3333 → 1111
      void setupRankingDivergence() {
        setupLoadDataDefaults(
          analyses: [
            // DAO 回傳序 = score DESC（生產行為）
            createAnalysis(symbol: '1111', score: 90),
            createAnalysis(symbol: '3333', score: 80),
            createAnalysis(symbol: '2222', score: 70),
          ],
        );
        when(
          () => mockDb.getPriceHistoryBatch(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer(
          (_) async => {
            '1111': history('1111', 101), // ret60 = +1%
            '2222': history('2222', 105), // ret60 = +5%
            '3333': history('3333', 110), // ret60 = +10%
          },
        );
        when(
          () => mockDb.getSymbolsByIndustry('半導體業'),
        ).thenAnswer((_) async => {'1111', '2222', '3333'});
      }

      /// rs60Desc（預設排序）下的正確順序：報酬高的在前 = 分數序的相反
      const expectedByRs60 = ['3333', '2222', '1111'];

      List<String> currentOrder() =>
          container.read(scanProvider).stocks.map((s) => s.symbol).toList();

      test('baseline: loadData 後依 60D RS 排序(證明 fixture 有鑑別力)', () async {
        setupRankingDivergence();
        final notifier = container.read(scanProvider.notifier);
        await notifier.loadData();

        expect(currentOrder(), expectedByRs60);
      });

      test('🚨 套用產業篩選後,排序不得落回分數序', () async {
        setupRankingDivergence();
        final notifier = container.read(scanProvider.notifier);
        await notifier.loadData();

        await notifier.setIndustryFilter('半導體業');
        await Future<void>.delayed(Duration.zero);

        expect(
          currentOrder(),
          expectedByRs60,
          reason: '排序籤仍顯示 60日相對強度,清單卻回到 score DESC',
        );
      });

      test('🚨 清除產業篩選後,排序同樣不得落回分數序', () async {
        setupRankingDivergence();
        final notifier = container.read(scanProvider.notifier);
        await notifier.loadData();

        await notifier.setIndustryFilter('半導體業');
        await Future<void>.delayed(Duration.zero);
        await notifier.setIndustryFilter(null);
        await Future<void>.delayed(Duration.zero);

        expect(currentOrder(), expectedByRs60);
      });

      test('非預設排序也要被保留(不是只有 rs60Desc 這條路)', () async {
        setupRankingDivergence();
        final notifier = container.read(scanProvider.notifier);
        await notifier.loadData();

        notifier.setSort(ScanSort.scoreAsc);
        await Future<void>.delayed(Duration.zero);
        // scoreAsc 與 rs60Desc、與 DAO 序皆不同 → 能分辨用的是哪個鍵
        expect(currentOrder(), ['2222', '3333', '1111']);

        await notifier.setIndustryFilter('半導體業');
        await Future<void>.delayed(Duration.zero);

        expect(currentOrder(), [
          '2222',
          '3333',
          '1111',
        ], reason: '產業籤必須保留使用者當下選的排序鍵,不是只保留預設鍵');
      });
    });

    test('setIndustryFilter race condition: latest call wins', () async {
      setupLoadDataDefaults(
        analyses: [createAnalysis(symbol: '2330', score: 85)],
      );

      // 用 Completer 控制第一次呼叫完成時機，避免依賴 wall-clock timing
      final slowCompleter = Completer<Set<String>>();
      when(
        () => mockDb.getSymbolsByIndustry('半導體業'),
      ).thenAnswer((_) => slowCompleter.future);
      when(
        () => mockDb.getSymbolsByIndustry('金融業'),
      ).thenAnswer((_) async => {'2882'});

      final notifier = container.read(scanProvider.notifier);
      await notifier.loadData();

      // Fire first (slow) call without awaiting
      unawaited(notifier.setIndustryFilter('半導體業'));
      // Immediately override with second (fast) call
      await notifier.setIndustryFilter('金融業');
      // 讓第一次完成（generation token 應忽略此結果）
      slowCompleter.complete({'2330'});
      await Future<void>.delayed(Duration.zero);

      // The latest call should be the winner
      final state = container.read(scanProvider);
      expect(state.industryFilter, '金融業');
    });
  });

  group('scan tiering — isScanSignal / isScanObservation', () {
    DailyAnalysisEntry a(double s, double l) => DailyAnalysisEntry(
      symbol: 'X',
      date: DateTime.utc(2026, 2, 13),
      trendState: 'UP',
      reversalState: 'NONE',
      scoreShort: s,
      scoreLong: l,
      computedAt: DateTime.utc(2026, 2, 13),
    );

    test('signal：任一 horizon ≥ minScoreThreshold(12)', () {
      expect(isScanSignal(a(12, 3)), isTrue);
      expect(isScanSignal(a(3, 15)), isTrue);
      expect(isScanSignal(a(11, 8)), isFalse);
    });

    test('observation：未達訊號、但任一 horizon ≥ observationScoreThreshold(8)', () {
      expect(isScanObservation(a(11, 8)), isTrue); // 8–11 接近觸發
      expect(isScanObservation(a(7, 7)), isFalse); // < 8 雜訊
      expect(isScanObservation(a(12, 3)), isFalse); // 已是訊號、非觀察
    });
  });

  group('isScanRiskVisible(原 isScanBearish;2026-08-05 更名——雙 0=風控可見層兩族群)', () {
    DailyAnalysisEntry entry(int s, int l) => DailyAnalysisEntry(
      symbol: 'T',
      date: DateTime(2026, 7, 31),
      scoreShort: s.toDouble(),
      scoreLong: l.toDouble(),
      trendState: 'DOWN',
      reversalState: 'NONE',
      computedAt: DateTime(2026, 7, 31),
    );

    test('雙 0 = 純空方(負 raw 被 floor)→ true', () {
      expect(isScanRiskVisible(entry(0, 0)), isTrue);
    });

    test('任一 horizon 有正分 → false', () {
      expect(isScanRiskVisible(entry(8, 0)), isFalse);
      expect(isScanRiskVisible(entry(0, 12)), isFalse);
    });
  });
}

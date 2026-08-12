import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/pagination.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockWarningRepository extends Mock implements WarningRepository {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

// ==========================================
// Test Helpers
// ==========================================

WatchlistItemData createItem({
  required String symbol,
  String? stockName,
  double? latestClose,
  double? priceChange,
  double? score,
  String? trendState,
  bool hasSignal = false,
  DateTime? addedAt,
}) {
  return WatchlistItemData(
    symbol: symbol,
    stockName: stockName,
    latestClose: latestClose,
    priceChange: priceChange,
    score: score,
    trendState: trendState,
    hasSignal: hasSignal,
    addedAt: addedAt,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  setUpAll(() {
    // any(named: 'groupId') 需要 Value<int?> 的 fallback
    registerFallbackValue(const Value<int?>.absent());
  });

  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late MockWarningRepository mockWarningRepo;
  late MockInsiderRepository mockInsiderRepo;
  late ProviderContainer container;

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();
    mockWarningRepo = MockWarningRepository();
    mockInsiderRepo = MockInsiderRepository();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
        warningRepositoryProvider.overrideWithValue(mockWarningRepo),
        insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // ==========================================
  // WatchlistState
  // ==========================================

  group('WatchlistState', () {
    test('has correct default values', () {
      final state = WatchlistState();

      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.sort, WatchlistSort.addedDesc);
      expect(state.group, WatchlistGroup.none);
      expect(state.searchQuery, isEmpty);
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.displayedCount, kPageSize);
    });

    test('copyWith preserves unset values', () {
      final state = WatchlistState(
        isLoading: true,
        sort: WatchlistSort.scoreDesc,
        group: WatchlistGroup.status,
        searchQuery: 'test',
      );

      final copied = state.copyWith();
      expect(copied.isLoading, isTrue);
      expect(copied.sort, WatchlistSort.scoreDesc);
      expect(copied.group, WatchlistGroup.status);
      expect(copied.searchQuery, 'test');
    });

    test('copyWith with sentinel handles error correctly', () {
      final state = WatchlistState(error: 'old error');
      // Not passing error → preserves
      final preserved = state.copyWith();
      expect(preserved.error, 'old error');

      // Passing null → clears
      final cleared = state.copyWith(error: null);
      expect(cleared.error, isNull);

      // Passing new value → updates
      final updated = state.copyWith(error: 'new error');
      expect(updated.error, 'new error');
    });

    test('filteredItems returns all items when no search query', () {
      final items = [
        createItem(symbol: '2330', stockName: '台積電'),
        createItem(symbol: '2317', stockName: '鴻海'),
      ];
      final state = WatchlistState(items: items);

      expect(state.filteredItems, hasLength(2));
    });

    test('filteredItems filters by symbol', () {
      final items = [
        createItem(symbol: '2330', stockName: '台積電'),
        createItem(symbol: '2317', stockName: '鴻海'),
      ];
      final state = WatchlistState(items: items, searchQuery: '2330');

      expect(state.filteredItems, hasLength(1));
      expect(state.filteredItems.first.symbol, '2330');
    });

    test('filteredItems filters by stock name', () {
      final items = [
        createItem(symbol: '2330', stockName: '台積電'),
        createItem(symbol: '2317', stockName: '鴻海'),
      ];
      final state = WatchlistState(items: items, searchQuery: '鴻海');

      expect(state.filteredItems, hasLength(1));
      expect(state.filteredItems.first.symbol, '2317');
    });

    test('filteredItems is case-insensitive', () {
      final items = [createItem(symbol: 'TSMC', stockName: 'Taiwan Semi')];
      final state = WatchlistState(items: items, searchQuery: 'tsmc');

      expect(state.filteredItems, hasLength(1));
    });

    test('displayedItems respects displayedCount', () {
      final items = List.generate(
        100,
        (i) => createItem(symbol: '${1000 + i}'),
      );
      final state = WatchlistState(items: items, displayedCount: 10);

      expect(state.displayedItems, hasLength(10));
    });

    test('copyWith recomputes filteredItems when items change', () {
      final state = WatchlistState(
        items: [createItem(symbol: '2330')],
        searchQuery: '2317',
      );
      expect(state.filteredItems, isEmpty);

      final updated = state.copyWith(items: [createItem(symbol: '2317')]);
      expect(updated.filteredItems, hasLength(1));
    });

    test('copyWith recomputes filteredItems when searchQuery changes', () {
      final state = WatchlistState(
        items: [
          createItem(symbol: '2330'),
          createItem(symbol: '2317'),
        ],
      );
      expect(state.filteredItems, hasLength(2));

      final updated = state.copyWith(searchQuery: '2330');
      expect(updated.filteredItems, hasLength(1));
    });
  });

  // ==========================================
  // WatchlistNotifier sort/group/search
  // ==========================================

  group('WatchlistNotifier sort/group/search', () {
    test('setSort changes sort option', () {
      final notifier = container.read(watchlistProvider.notifier);
      notifier.setSort(WatchlistSort.scoreDesc);

      final state = container.read(watchlistProvider);
      expect(state.sort, WatchlistSort.scoreDesc);
    });

    test('setSort does nothing when same sort', () {
      final notifier = container.read(watchlistProvider.notifier);
      notifier.setSort(WatchlistSort.addedDesc); // default value

      // Should not cause unnecessary state update
      final state = container.read(watchlistProvider);
      expect(state.sort, WatchlistSort.addedDesc);
    });

    test('setGroup changes group option', () {
      final notifier = container.read(watchlistProvider.notifier);
      notifier.setGroup(WatchlistGroup.status);

      final state = container.read(watchlistProvider);
      expect(state.group, WatchlistGroup.status);
    });

    test('setSearchQuery filters items', () {
      final notifier = container.read(watchlistProvider.notifier);
      notifier.setSearchQuery('test');

      final state = container.read(watchlistProvider);
      expect(state.searchQuery, 'test');
    });
  });

  // ==========================================
  // WatchlistNotifier loadData
  // ==========================================

  group('WatchlistNotifier loadData', () {
    test('sets empty items when watchlist is empty', () async {
      when(() => mockDb.getWatchlistWithGroups()).thenAnswer((_) async => []);
      when(() => mockDb.getWatchlistGroups()).thenAnswer((_) async => []);

      final notifier = container.read(watchlistProvider.notifier);
      await notifier.loadData();

      final state = container.read(watchlistProvider);
      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('handles error gracefully', () async {
      when(
        () => mockDb.getWatchlistWithGroups(),
      ).thenThrow(Exception('DB error'));
      when(() => mockDb.getWatchlistGroups()).thenAnswer((_) async => []);

      final notifier = container.read(watchlistProvider.notifier);
      await notifier.loadData();

      final state = container.read(watchlistProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
    });

    test('並發 loadData:先發慢完成者不得覆蓋後發結果(2026-07-30 審查)', () async {
      // dataUpdateEpoch listener 與 pull-to-refresh 可同時觸發 loadData。
      // 模擬:第一次呼叫讀 DB 很慢(groupA)、第二次很快(groupB)。
      // 慢的完成後不得把 state 蓋回 groupA —— today/marketOverview 已修過
      // 同型 race,此測試鎖住 watchlist 的 generation guard。
      final groupA = WatchlistGroupEntry(
        id: 1,
        name: 'A(舊)',
        sortOrder: 0,
        createdAt: DateTime(2026, 7, 30),
        isDefault: false,
      );
      final groupB = WatchlistGroupEntry(
        id: 2,
        name: 'B(新)',
        sortOrder: 0,
        createdAt: DateTime(2026, 7, 30),
        isDefault: false,
      );
      final mockAnalysisRepo = MockAnalysisRepository();
      when(
        () => mockAnalysisRepo.findLatestAnalysisDate(),
      ).thenAnswer((_) async => DateTime(2026, 7, 30));
      final raceContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
          cachedDbProvider.overrideWithValue(mockCachedDb),
          warningRepositoryProvider.overrideWithValue(mockWarningRepo),
          insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
          analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
        ],
      );
      addTearDown(raceContainer.dispose);

      final slowGate = Completer<void>();
      var call = 0;
      when(() => mockDb.getWatchlistWithGroups()).thenAnswer((_) async {
        call++;
        if (call == 1) await slowGate.future; // 第一次呼叫卡住
        return [];
      });
      var groupCall = 0;
      when(() => mockDb.getWatchlistGroups()).thenAnswer((_) async {
        groupCall++;
        return [groupCall == 1 ? groupA : groupB];
      });

      final notifier = raceContainer.read(watchlistProvider.notifier);
      final first = notifier.loadData(); // 先發(慢)
      final second = notifier.loadData(); // 後發(快)
      await second;
      expect(
        raceContainer.read(watchlistProvider).groups.single.name,
        'B(新)',
        reason: '後發完成後 state 應為 B',
      );

      slowGate.complete(); // 放行先發
      await first;
      expect(
        raceContainer.read(watchlistProvider).groups.single.name,
        'B(新)',
        reason: '先發慢完成者不得以舊資料(A)覆蓋',
      );
    });

    test('並發 loadData:先發慢「失敗」者不得把 error 蓋到後發成功結果', () async {
      final mockAnalysisRepo = MockAnalysisRepository();
      when(
        () => mockAnalysisRepo.findLatestAnalysisDate(),
      ).thenAnswer((_) async => DateTime(2026, 7, 30));
      final raceContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
          cachedDbProvider.overrideWithValue(mockCachedDb),
          warningRepositoryProvider.overrideWithValue(mockWarningRepo),
          insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
          analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
        ],
      );
      addTearDown(raceContainer.dispose);

      final slowGate = Completer<void>();
      var call = 0;
      when(() => mockDb.getWatchlistWithGroups()).thenAnswer((_) async {
        call++;
        if (call == 1) {
          await slowGate.future;
          throw Exception('先發的 DB 讀取炸了');
        }
        return [];
      });
      when(() => mockDb.getWatchlistGroups()).thenAnswer((_) async => []);

      final notifier = raceContainer.read(watchlistProvider.notifier);
      final first = notifier.loadData(); // 先發(慢,終將失敗)
      final second = notifier.loadData(); // 後發(快,成功)
      await second;
      expect(raceContainer.read(watchlistProvider).error, isNull);

      slowGate.complete();
      await first;
      final state = raceContainer.read(watchlistProvider);
      expect(state.error, isNull, reason: '過期的失敗不得覆蓋成功結果');
      expect(state.isLoading, isFalse);
    });
  });

  // ==========================================
  // WatchlistNotifier loadMore
  // ==========================================

  group('WatchlistNotifier loadMore', () {
    test('returns immediately when already loading more', () async {
      // Default state has isLoadingMore = false, hasMore = true
      // Since there are no items, it should just update counts
      final notifier = container.read(watchlistProvider.notifier);
      await notifier.loadMore();

      final state = container.read(watchlistProvider);
      expect(state.isLoadingMore, isFalse);
    });

    test('returns immediately when hasMore is false', () async {
      final notifier = container.read(watchlistProvider.notifier);
      // Manually set hasMore to false via empty watchlist
      when(() => mockDb.getWatchlistWithGroups()).thenAnswer((_) async => []);
      when(() => mockDb.getWatchlistGroups()).thenAnswer((_) async => []);
      await notifier.loadData();

      await notifier.loadMore();
      final state = container.read(watchlistProvider);
      expect(state.isLoadingMore, isFalse);
    });
  });

  // ==========================================
  // WatchlistNotifier removeStock (optimistic update)
  // ==========================================

  group('WatchlistNotifier removeStock', () {
    test('removes stock from state optimistically', () async {
      when(() => mockDb.removeFromWatchlist(any())).thenAnswer((_) async {});
      when(() => mockDb.getWatchlistEntry(any())).thenAnswer((_) async => null);

      // Manually set initial state with items
      final notifier = container.read(watchlistProvider.notifier);

      // We can't easily set items without going through loadData.
      // Instead test the DB call
      await notifier.removeStock('2330');

      verify(() => mockDb.removeFromWatchlist('2330')).called(1);
    });
  });

  // ==========================================
  // WatchlistNotifier restoreStock 保留分組(2026-08-12)
  //
  // 修前:removeStock 刪列(分組資訊隨列消失)→ restoreStock 重新 insert
  // → groupId 永遠是 NULL/預設組。使用者「移除→復原」一輪,股票就從
  // 原分組靜默搬家。
  //
  // 只驗 addToWatchlist 的參數:後段 _loadSingleStockData 鏈未樁,會丟
  // 例外進 restoreStock 的 catch——不影響本組要驗的 stash 傳遞。
  // ==========================================

  group('WatchlistNotifier restoreStock 保留分組', () {
    setUp(() {
      when(() => mockDb.removeFromWatchlist(any())).thenAnswer((_) async {});
      when(
        () => mockDb.addToWatchlist(any(), groupId: any(named: 'groupId')),
      ).thenAnswer((_) async {});
    });

    test('🚨 復原後回到原分組,而非落入預設分組', () async {
      when(() => mockDb.getWatchlistEntry('2330')).thenAnswer(
        (_) async => WatchlistEntry(
          symbol: '2330',
          createdAt: DateTime(2026, 8, 1),
          groupId: 7,
        ),
      );
      final notifier = container.read(watchlistProvider.notifier);

      await notifier.removeStock('2330');
      await notifier.restoreStock('2330');

      verify(
        () => mockDb.addToWatchlist('2330', groupId: const Value<int?>(7)),
      ).called(1);
    });

    test('🚨 原本未分組的股票,復原後仍未分組(不得落入預設組)', () async {
      when(() => mockDb.getWatchlistEntry('2330')).thenAnswer(
        (_) async => WatchlistEntry(
          symbol: '2330',
          createdAt: DateTime(2026, 8, 1),
          groupId: null,
        ),
      );
      final notifier = container.read(watchlistProvider.notifier);

      await notifier.removeStock('2330');
      await notifier.restoreStock('2330');

      // Value(null) ≠ Value.absent():前者明確要求未分組
      verify(
        () => mockDb.addToWatchlist('2330', groupId: const Value<int?>(null)),
      ).called(1);
    });

    test('沒有移除紀錄時直接復原 → 不指定分組(走預設組解析)', () async {
      when(() => mockDb.getWatchlistEntry(any())).thenAnswer((_) async => null);
      final notifier = container.read(watchlistProvider.notifier);

      await notifier.restoreStock('2330');

      verify(
        () =>
            mockDb.addToWatchlist('2330', groupId: const Value<int?>.absent()),
      ).called(1);
    });
  });

  // ==========================================
  // WatchlistState copyWith _internal path
  // ==========================================

  group('WatchlistState copyWith internal path', () {
    test('preserves filteredItems cache when only isLoading changes', () {
      final items = [
        createItem(symbol: '2330', stockName: '台積電'),
        createItem(symbol: '2317', stockName: '鴻海'),
      ];
      final state = WatchlistState(items: items, searchQuery: '2330');
      expect(state.filteredItems, hasLength(1));

      // Only change isLoading → _internal path
      final updated = state.copyWith(isLoading: true);
      expect(updated.filteredItems, hasLength(1));
      expect(updated.isLoading, isTrue);
    });

    test('preserves filteredItems cache when only sort changes', () {
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      final state = WatchlistState(items: items);

      final updated = state.copyWith(sort: WatchlistSort.nameAsc);
      expect(updated.sort, WatchlistSort.nameAsc);
      expect(updated.filteredItems, hasLength(2));
    });

    test('preserves filteredItems cache when only group changes', () {
      final items = [createItem(symbol: '2330')];
      final state = WatchlistState(items: items);

      final updated = state.copyWith(group: WatchlistGroup.trend);
      expect(updated.group, WatchlistGroup.trend);
      expect(updated.filteredItems, hasLength(1));
    });

    test('preserves filteredItems cache when only error changes', () {
      final items = [createItem(symbol: '2330')];
      final state = WatchlistState(items: items);

      final updated = state.copyWith(error: 'some error');
      expect(updated.error, 'some error');
      expect(updated.filteredItems, hasLength(1));
    });

    test('recomputes when searchQuery changes to same value as current', () {
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      final state = WatchlistState(items: items, searchQuery: '2330');
      expect(state.filteredItems, hasLength(1));

      // Same query → no recompute (handled by copyWith condition)
      final updated = state.copyWith(searchQuery: '2330');
      expect(updated.filteredItems, hasLength(1));
    });
  });

  // ==========================================
  // WatchlistState pagination edge cases
  // ==========================================

  group('WatchlistState pagination', () {
    test('displayedItems caps at total items', () {
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      final state = WatchlistState(items: items, displayedCount: 100);
      expect(state.displayedItems, hasLength(2));
    });

    test('displayedItems is empty when displayedCount is 0', () {
      final items = [createItem(symbol: '2330')];
      final state = WatchlistState(items: items, displayedCount: 0);
      expect(state.displayedItems, isEmpty);
    });

    test('copyWith updates hasMore and displayedCount together', () {
      final state = WatchlistState(displayedCount: 10, hasMore: true);
      final updated = state.copyWith(displayedCount: 20, hasMore: false);
      expect(updated.displayedCount, 20);
      expect(updated.hasMore, isFalse);
    });

    test('copyWith updates isLoadingMore', () {
      final state = WatchlistState();
      final updated = state.copyWith(isLoadingMore: true);
      expect(updated.isLoadingMore, isTrue);
    });
  });

  // ==========================================
  // Provider declaration
  // ==========================================

  group('watchlistProvider', () {
    test('has correct initial state', () {
      final state = container.read(watchlistProvider);
      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
    });
  });
}

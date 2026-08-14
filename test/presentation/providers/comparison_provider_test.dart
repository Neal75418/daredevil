import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/comparison_provider.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late ProviderContainer container;

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // ==========================================
  // ComparisonState
  // ==========================================

  group('ComparisonState', () {
    test('has correct default values', () {
      const state = ComparisonState();

      expect(state.symbols, isEmpty);
      expect(state.stocksMap, isEmpty);
      expect(state.latestPricesMap, isEmpty);
      expect(state.priceHistoriesMap, isEmpty);
      expect(state.analysesMap, isEmpty);
      expect(state.valuationsMap, isEmpty);
      expect(state.institutionalMap, isEmpty);
      expect(state.epsMap, isEmpty);
      expect(state.revenueMap, isEmpty);
      expect(state.summariesMap, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('canAddMore is true when less than 4 stocks', () {
      const state = ComparisonState(symbols: ['2330', '2317', '2454']);
      expect(state.canAddMore, isTrue);
    });

    test('canAddMore is false when 4 stocks', () {
      const state = ComparisonState(symbols: ['2330', '2317', '2454', '3008']);
      expect(state.canAddMore, isFalse);
    });

    test('hasEnoughToCompare is true when >= 2 stocks', () {
      const state = ComparisonState(symbols: ['2330', '2317']);
      expect(state.hasEnoughToCompare, isTrue);
    });

    test('hasEnoughToCompare is false when < 2 stocks', () {
      const state = ComparisonState(symbols: ['2330']);
      expect(state.hasEnoughToCompare, isFalse);
    });

    test('hasEnoughToCompare is false when empty', () {
      const state = ComparisonState();
      expect(state.hasEnoughToCompare, isFalse);
    });

    test('copyWith preserves unset values', () {
      const state = ComparisonState(symbols: ['2330'], isLoading: true);

      final copied = state.copyWith();
      expect(copied.symbols, ['2330']);
      expect(copied.isLoading, isTrue);
    });

    test('copyWith with sentinel handles error correctly', () {
      const state = ComparisonState(error: 'old error');

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
  });

  // ==========================================
  // ComparisonNotifier
  // ==========================================

  group('ComparisonNotifier', () {
    test('initial state is empty', () {
      final state = container.read(comparisonProvider);
      expect(state.symbols, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('addStock skips duplicate symbol', () async {
      // 用 addStocks 設定初始狀態（不回滾）
      when(() => mockDb.getLatestDataDate()).thenThrow(Exception('DB error'));

      final notifier = container.read(comparisonProvider.notifier);
      await notifier.addStocks(['2330']);
      expect(container.read(comparisonProvider).symbols, ['2330']);

      // Second add: same symbol should be skipped (guard: symbols.contains)
      await notifier.addStock('2330');
      expect(container.read(comparisonProvider).symbols, hasLength(1));
    });

    test('addStock skips when at max capacity', () async {
      when(() => mockDb.getLatestDataDate()).thenThrow(Exception('DB error'));

      final notifier = container.read(comparisonProvider.notifier);
      await notifier.addStocks(['2330', '2317', '2454', '3008']);
      expect(container.read(comparisonProvider).symbols, hasLength(4));

      // 5th stock should be skipped (guard: !canAddMore)
      await notifier.addStock('6505');
      expect(container.read(comparisonProvider).symbols, hasLength(4));
      expect(
        container.read(comparisonProvider).symbols,
        isNot(contains('6505')),
      );
    });

    test('removeStock removes symbol from state', () async {
      // 用 addStocks 設定初始狀態（不回滾）
      when(() => mockDb.getLatestDataDate()).thenThrow(Exception('DB error'));

      final notifier = container.read(comparisonProvider.notifier);
      await notifier.addStocks(['2330']);
      expect(container.read(comparisonProvider).symbols, contains('2330'));

      // Remove it
      notifier.removeStock('2330');
      expect(container.read(comparisonProvider).symbols, isEmpty);
    });

    test('removeStock is no-op for nonexistent symbol', () {
      final notifier = container.read(comparisonProvider.notifier);
      notifier.removeStock('nonexistent');
      final state = container.read(comparisonProvider);
      expect(state.symbols, isEmpty);
    });

    test('addStock handles error when DB fails', () async {
      when(() => mockDb.getLatestDataDate()).thenThrow(Exception('DB error'));

      final notifier = container.read(comparisonProvider.notifier);
      await notifier.addStock('2330');

      final state = container.read(comparisonProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
      // addStock 失敗時應回滾，避免佔用名額
      expect(state.symbols, isNot(contains('2330')));
    });

    test(
      'addStock allows re-adding after previous failure (rollback unblocks)',
      () async {
        when(() => mockDb.getLatestDataDate()).thenThrow(Exception('DB error'));

        final notifier = container.read(comparisonProvider.notifier);

        // 第一次失敗 → 回滾
        await notifier.addStock('2330');
        expect(container.read(comparisonProvider).symbols, isEmpty);

        // 第二次嘗試不應被 symbols.contains 擋住
        await notifier.addStock('2330');
        // 仍然失敗（mock 未變），但重點是沒被跳過：error 被重新設定
        final state = container.read(comparisonProvider);
        expect(state.error, isNotNull);
        expect(state.symbols, isEmpty); // 再次回滾
      },
    );

    test('addStocks deduplicates and limits to 4', () async {
      when(() => mockDb.getLatestDataDate()).thenThrow(Exception('DB error'));

      final notifier = container.read(comparisonProvider.notifier);
      await notifier.addStocks([
        '2330',
        '2317',
        '2330', // duplicate
        '2454',
        '3008',
        '6505', // should be ignored (5th)
      ]);

      final state = container.read(comparisonProvider);
      expect(state.symbols, hasLength(4));
      expect(state.symbols, ['2330', '2317', '2454', '3008']);
    });

    test('addStocks does nothing for empty list', () async {
      final notifier = container.read(comparisonProvider.notifier);
      await notifier.addStocks([]);

      final state = container.read(comparisonProvider);
      expect(state.symbols, isEmpty);
      expect(state.isLoading, isFalse);
    });
  });

  // ==========================================
  // _loadAllData generation token
  // ==========================================

  group('_loadAllData generation token', () {
    test(
      'stale load result is discarded when newer load completes first',
      () async {
        // 用 Completer 控制第一次 getLatestDataDate 的完成時機
        final firstCompleter = Completer<DateTime?>();
        var callCount = 0;

        when(() => mockDb.getLatestDataDate()).thenAnswer((_) {
          callCount++;
          if (callCount == 1) return firstCompleter.future; // 第一次：延遲
          throw Exception('second-call-error'); // 第二次：立即失敗
        });

        final notifier = container.read(comparisonProvider.notifier);

        // 先啟動 addStocks（不 await），再立刻 reload
        final firstFuture = notifier.addStocks(['2330']);
        final secondFuture = notifier.reload();

        // 第二次載入先完成（帶 error）
        await secondFuture;
        final errorAfterSecond = container.read(comparisonProvider).error;
        expect(errorAfterSecond, isNotNull);

        // 第一次載入晚回來（也失敗，但 generation 已過期，應被丟棄）
        firstCompleter.completeError(Exception('first-call-error'));
        await firstFuture;

        // 最終 error 應仍是第二次的，不被第一次覆蓋
        // （若 generation token 未生效，error 會被重新設定為不同物件）
        final finalState = container.read(comparisonProvider);
        expect(identical(finalState.error, errorAfterSecond), isTrue);
      },
    );
  });

  // ==========================================
  // H1 regression: autoDispose state-after-await race
  // ==========================================
  //
  // `comparisonProvider` 是 autoDispose（無 keepAlive）；user 加股票後立刻
  // 離開頁面會觸發 dispose。in-flight 的 `_loadAllData` Future 仍會跑到
  // 結束、回到 addStock 的 `if (state.error != null)` 行 — 在 disposed
  // notifier 上讀/寫 state 在 Riverpod 2.x 會 throw StateError。
  //
  // Fix：addStock 在讀寫 state 前 guard `_active`，_loadAllData 的 catch
  // 也 guard `_active` 不寫 error state。
  group('H1 regression: autoDispose race when load completes after dispose', () {
    test(
      'addStock does not throw StateError when notifier is disposed mid-await',
      () async {
        final completer = Completer<DateTime?>();
        when(
          () => mockDb.getLatestDataDate(),
        ).thenAnswer((_) => completer.future);

        final notifier = container.read(comparisonProvider.notifier);
        // 不 await — 讓 _loadAllData 卡在 getLatestDataDate
        final pending = notifier.addStock('2330');

        // 模擬 user 離頁：container dispose → notifier dispose → _active = false
        container.dispose();

        // 解開 await：以 error 完成，触發 catch path
        completer.completeError(Exception('post-dispose error'));

        // 不應 throw — _loadAllData 的 catch 與 addStock 的尾段都該 guard
        // `_active` 跳過 state 寫入。
        await expectLater(pending, completes);
      },
    );

    test(
      'addStock does not throw when load succeeds after notifier disposed',
      () async {
        final completer = Completer<DateTime?>();
        when(
          () => mockDb.getLatestDataDate(),
        ).thenAnswer((_) => completer.future);

        final notifier = container.read(comparisonProvider.notifier);
        final pending = notifier.addStock('2330');

        container.dispose();

        // 成功 path：getLatestDataDate 回 null，後續 _cachedDb.loadStockListData
        // 等也會被 disposed 的 mock 設定影響，但只要 `_active` guard 起作用就不
        // 該 throw StateError。
        completer.complete(null);

        await expectLater(pending, completes);
      },
    );
  });
}

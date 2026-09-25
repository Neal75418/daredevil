import 'dart:async';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

class MockUpdateService extends Mock implements UpdateService {}

class MockDataSyncService extends Mock implements DataSyncService {}

class _CountingMarketOverviewNotifier extends MarketOverviewNotifier {
  int loads = 0;

  @override
  MarketOverviewState build() => const MarketOverviewState();

  @override
  Future<void> loadData() async => loads++;
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late MockAnalysisRepository mockAnalysisRepo;
  late MockUpdateService mockUpdateService;
  late MockDataSyncService mockDataSyncService;
  late ProviderContainer container;

  setUpAll(() {
    // Horizon enum 需要 fallback 才能用 any(named: 'horizon')
    registerFallbackValue(Horizon.short);
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();
    mockAnalysisRepo = MockAnalysisRepository();
    mockUpdateService = MockUpdateService();
    mockDataSyncService = MockDataSyncService();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
        analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
        updateServiceProvider.overrideWithValue(mockUpdateService),
        dataSyncServiceProvider.overrideWithValue(mockDataSyncService),
      ],
    );

    // 設置 loadData 編排路徑的預設 mock 行為。
    // loadData 透過 marketDataRepositoryProvider（內部委派給 databaseProvider）
    // 讀取 getLatestUpdateRun / getLatestDataDate / getLatestInstitutionalDate，
    // 再交給 dataSyncService.getDisplayDataDate 計算顯示日期。
    when(() => mockDb.getWatchlist()).thenAnswer((_) async => []);
    when(() => mockDb.getLatestUpdateRun()).thenAnswer((_) async => null);
    when(
      () => mockDb.getLatestSuccessfulUpdateRun(),
    ).thenAnswer((_) async => null);
    when(
      () => mockDb.getLatestDataDate(),
    ).thenAnswer((_) async => DateTime(2026, 2, 13));
    when(
      () => mockDb.getLatestInstitutionalDate(),
    ).thenAnswer((_) async => DateTime(2026, 2, 13));

    when(
      () => mockDataSyncService.getDisplayDataDate(any(), any()),
    ).thenReturn(DateTime(2026, 2, 13));
  });

  tearDown(() {
    container.dispose();
  });

  group('TodayState', () {
    test('has correct default values', () {
      const state = TodayState();

      expect(state.lastUpdate, isNull);
      expect(state.dataDate, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isUpdating, isFalse);
      expect(state.updateProgress, isNull);
      expect(state.error, isNull);
    });

    test('copyWith creates new instance with updated values', () {
      const originalState = TodayState(isLoading: true);

      final newState = originalState.copyWith(
        isLoading: false,
        error: 'Test error',
      );

      expect(newState.isLoading, isFalse);
      expect(newState.error, equals('Test error'));
      // 未修改的欄位應保持原值
      expect(newState.dataDate, equals(originalState.dataDate));
    });

    test('copyWith with sentinel preserves null values', () {
      const originalState = TodayState(error: 'Original error');

      // 不傳入 error 參數，應保留原值
      final state1 = originalState.copyWith(isLoading: true);
      expect(state1.error, equals('Original error'));

      // 明確傳入 null，應清除錯誤
      final state2 = originalState.copyWith(error: null);
      expect(state2.error, isNull);
    });
  });

  group('UpdateProgress', () {
    test('calculates progress correctly', () {
      const progress1 = UpdateProgress(
        currentStep: 5,
        totalSteps: 10,
        message: 'Step 5/10',
      );
      expect(progress1.progress, equals(0.5));

      const progress2 = UpdateProgress(
        currentStep: 10,
        totalSteps: 10,
        message: 'Complete',
      );
      expect(progress2.progress, equals(1.0));

      const progress3 = UpdateProgress(
        currentStep: 0,
        totalSteps: 10,
        message: 'Starting',
      );
      expect(progress3.progress, equals(0.0));
    });

    test('handles zero total steps gracefully', () {
      const progress = UpdateProgress(
        currentStep: 5,
        totalSteps: 0,
        message: 'Invalid state',
      );

      expect(progress.progress, equals(0.0));
    });
  });

  group('TodayNotifier', () {
    test('initial state is loading=false with no error', () {
      final state = container.read(todayProvider);

      expect(state.isLoading, isFalse);
      expect(state.isUpdating, isFalse);
      expect(state.error, isNull);
    });

    test('loadData sets loading state and loads orchestration state', () async {
      // Arrange — 提供完整編排路徑的回傳值
      final finishedAt = DateTime(2026, 2, 13, 16, 30);
      when(() => mockDb.getLatestUpdateRun()).thenAnswer(
        (_) async => UpdateRunEntry(
          id: 1,
          runDate: DateTime(2026, 2, 13),
          startedAt: DateTime(2026, 2, 13, 16, 0),
          finishedAt: finishedAt,
          status: 'success',
        ),
      );
      when(
        () => mockDb.getLatestDataDate(),
      ).thenAnswer((_) async => DateTime(2026, 2, 12));
      when(
        () => mockDb.getLatestInstitutionalDate(),
      ).thenAnswer((_) async => DateTime(2026, 2, 12));
      when(
        () => mockDataSyncService.getDisplayDataDate(any(), any()),
      ).thenReturn(DateTime(2026, 2, 12));

      // Act
      final notifier = container.read(todayProvider.notifier);
      final loadFuture = notifier.loadData();

      // 檢查 loading 狀態
      expect(container.read(todayProvider).isLoading, isTrue);

      await loadFuture;

      // Assert — 不再有 recommendations，只驗證編排 state
      final state = container.read(todayProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.lastUpdate, equals(finishedAt));
      expect(state.dataDate, equals(DateTime(2026, 2, 12)));
    });

    test('loadData handles error gracefully', () async {
      // Arrange — 讓編排路徑其中一個呼叫拋例外
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenThrow(Exception('Database error'));

      // Act
      final notifier = container.read(todayProvider.notifier);
      await notifier.loadData();

      // Assert
      final state = container.read(todayProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, isNotEmpty);
    });

    test('loadData clears previous error on successful load', () async {
      // Arrange — 先讓編排路徑失敗一次
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenThrow(Exception('First error'));

      final notifier = container.read(todayProvider.notifier);
      await notifier.loadData();

      expect(container.read(todayProvider).error, isNotNull);

      // Arrange — 還原成功的 mock
      when(() => mockDb.getLatestUpdateRun()).thenAnswer((_) async => null);

      // Act — 重新載入
      await notifier.loadData();

      // Assert — 錯誤應該被清除
      final state = container.read(todayProvider);
      expect(state.error, isNull);
    });
  });

  group('Edge Cases', () {
    test('handles null dataDate gracefully', () async {
      // Arrange
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => null);
      when(
        () => mockDb.getLatestInstitutionalDate(),
      ).thenAnswer((_) async => null);
      when(
        () => mockDataSyncService.getDisplayDataDate(null, null),
      ).thenReturn(null);

      // Act
      final notifier = container.read(todayProvider.notifier);
      await notifier.loadData();

      // Assert
      final state = container.read(todayProvider);
      expect(state.isLoading, isFalse);
      expect(state.dataDate, isNull); // 應優雅處理 null dataDate
    });
  });
  // ====================================================================
  // 冷啟動自動更新 gate（2026-07-26）
  //
  // data_freshness.dart 的 docstring 寫「距上次**成功** update_run」，
  // 但 getLatestUpdateRun() 完全不過濾 status，today_provider 也無條件
  // 拿最後一筆的時間 —— 一次 PARTIAL / FAILED 會把冷啟動自動更新擋滿
  // 6 小時。更新失敗反而讓 app 更不會重試，方向是反的。
  //
  // 修法把混在一起的兩件事拆開：
  //   資料夠不夠新 → 距上次**成功**更新 ≥ coldStartAutoUpdateGateHours
  //   是不是在狂打 → 距上次**嘗試** ≥ coldStartRetryThrottleMinutes
  // 兩者皆成立才觸發。這比「依 status 選單一門檻」更準確：後者在
  // 「上次成功才 3 小時前、但 2 小時前有一筆 PARTIAL」時會多餘重跑。
  // ====================================================================
  group('冷啟動自動更新 gate 依 status 分流', () {
    // 判斷抽成純函式後不需 mock harness，也不看真實時鐘 —— 舊寫法在
    // 週末跑會因為 isTradingDay(DateTime.now()) 直接早退而假綠/假紅。
    final tradingDay = DateTime(2026, 7, 22, 9); // 週三

    bool decide({DateTime? success, DateTime? attempt}) =>
        TodayNotifier.shouldTriggerColdStartUpdate(
          now: tradingDay,
          lastSuccessAt: success,
          lastAttemptAt: attempt,
        );

    test('🚨 上次成功已久、之後的失敗嘗試也夠久 → 必須重試', () {
      expect(
        decide(
          success: tradingDay.subtract(const Duration(hours: 9)),
          attempt: tradingDay.subtract(const Duration(hours: 3)),
        ),
        isTrue,
        reason:
            '舊實作拿不分 status 的最後一筆當新鮮度基準，'
            '一次 PARTIAL 就把重試擋滿 6 小時 —— 失敗反而更不重試',
      );
    });

    test('剛嘗試過就不要連打（attempt throttle）', () {
      expect(
        decide(
          success: tradingDay.subtract(const Duration(hours: 9)),
          attempt: tradingDay.subtract(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('資料還新就不重試，即使中間有失敗的嘗試', () {
      expect(
        decide(
          success: tradingDay.subtract(const Duration(hours: 3)),
          attempt: tradingDay.subtract(const Duration(hours: 2)),
        ),
        isFalse,
        reason: '「依 status 選單一門檻」的設計會在此情境多餘重跑',
      );
    });

    test('從未成功過 → 只受節流限制', () {
      expect(decide(success: null, attempt: null), isTrue);
      expect(
        decide(
          success: null,
          attempt: tradingDay.subtract(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('非交易日一律不觸發', () {
      expect(
        TodayNotifier.shouldTriggerColdStartUpdate(
          now: DateTime(2026, 7, 26), // 週日
          lastSuccessAt: null,
          lastAttemptAt: null,
        ),
        isFalse,
      );
    });
  });

  group('runUpdate 逾時後的背景收尾(2026-07-30 審查)', () {
    test('逾時後底層更新終於成功:補跑 invalidateCache + epoch bump', () {
      fakeAsync((async) {
        final pending = Completer<UpdateResult>();
        when(
          () => mockUpdateService.runDailyUpdate(
            force: any(named: 'force'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) => pending.future);

        final epochBefore = container.read(dataUpdateEpochProvider);
        final notifier = container.read(todayProvider.notifier);

        Object? thrown;
        notifier.runUpdate().then<void>(
          (_) {},
          onError: (Object e) {
            thrown = e;
          },
        );
        async.elapse(const Duration(minutes: 61));
        expect(thrown, isA<TimeoutException>(), reason: '逾時本身照舊拋出');

        // 底層更新其後成功——.timeout 不取消底層 future
        pending.complete(
          UpdateResult(date: DateTime(2026, 7, 6))..success = true,
        );
        async.flushMicrotasks();

        verify(() => mockCachedDb.invalidateCache()).called(1);
        expect(
          container.read(dataUpdateEpochProvider),
          greaterThan(epochBefore),
          reason:
              '逾時被放棄的更新成功後,若不補 bump epoch,'
              '所有 provider 永遠不知道 DB 已有新一輪資料',
        );
      });
    });

    test('逾時後底層更新失敗:靜默,零 unhandled async error', () {
      final unhandled = <Object>[];
      runZonedGuarded(() {
        fakeAsync((async) {
          final pending = Completer<UpdateResult>();
          when(
            () => mockUpdateService.runDailyUpdate(
              force: any(named: 'force'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) => pending.future);

          final notifier = container.read(todayProvider.notifier);
          notifier.runUpdate().then<void>((_) {}, onError: (Object e) {});
          async.elapse(const Duration(minutes: 61));

          pending.completeError(StateError('底層更新最終失敗'));
          async.flushMicrotasks();
        });
      }, (e, st) => unhandled.add(e));
      expect(unhandled, isEmpty);
    });
  });

  // ====================================================================
  // 節流錨點(2026-08-01 複審):lastAttemptAt 必須取 startedAt。
  // 孤兒 RUNNING 被 beforeOpen 的 failOrphanRunningRuns 收斂成 FAILED 時
  // finishedAt 會蓋成 sweep 當下——那是 DB bookkeeping、不是一次真實 API
  // 嘗試。舊寫法 finishedAt ?? startedAt 讓「app 被殺 3 小時後重開」被
  // 多節流最多一整個節流窗,資料早已過期卻不重試。
  // ====================================================================
  group('冷啟動節流錨點', () {
    test('🚨 sweep 蓋過 finishedAt 的孤兒 run:錨點仍是真實發起時刻', () {
      final started = DateTime(2026, 7, 22, 6); // 真實嘗試:3 小時前
      final swept = DateTime(2026, 7, 22, 9); // sweep 收斂當下
      final run = UpdateRunEntry(
        id: 1,
        runDate: DateTime(2026, 7, 22),
        startedAt: started,
        finishedAt: swept,
        status: 'failed',
      );
      expect(TodayNotifier.attemptAnchorOf(run), started);
    });

    test('無任何 run 回 null(從未嘗試)', () {
      expect(TodayNotifier.attemptAnchorOf(null), isNull);
    });
  });

  // App 內更新完成後才會 bump epoch；launchd CLI／背景任務在 App 外更新 DB
  // 時沒有任何東西通知 UI。回到前景若只 loadData，今日頁日期變新、訊號清單
  // 與其他頁卻仍是舊的——比「全部都舊」更誤導。
  group('回到前景重新載入(reloadAfterResume)', () {
    late ProviderContainer c;
    late _CountingMarketOverviewNotifier market;

    UpdateRunEntry run(DateTime finishedAt) => UpdateRunEntry(
      id: 1,
      runDate: DateTime(2026, 9, 24),
      startedAt: finishedAt.subtract(const Duration(minutes: 1)),
      finishedAt: finishedAt,
      status: 'SUCCESS',
    );

    setUp(() {
      market = _CountingMarketOverviewNotifier();
      c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
          cachedDbProvider.overrideWithValue(mockCachedDb),
          analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
          updateServiceProvider.overrideWithValue(mockUpdateService),
          dataSyncServiceProvider.overrideWithValue(mockDataSyncService),
          marketOverviewProvider.overrideWith(() => market),
        ],
      );
      addTearDown(c.dispose);
    });

    test('🚨 DB 已被 App 外更新 → 清快取、bump epoch、重載大盤', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      // launchd 21:30 那輪在 App 外跑完
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 21, 31)));
      await notifier.reloadAfterResume();

      verify(() => mockCachedDb.invalidateCache()).called(1);
      expect(c.read(dataUpdateEpochProvider), greaterThan(epochBefore));
      expect(market.loads, 1);
    });

    test('DB 沒變 → 只重讀今日狀態，不驚動其他頁', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      await notifier.reloadAfterResume();

      verifyNever(() => mockCachedDb.invalidateCache());
      expect(c.read(dataUpdateEpochProvider), epochBefore);
      expect(market.loads, 0);
    });

    test('🚨 先下拉重整讀到新資料、再回前景 → 仍要通知其他頁', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 21, 31)));
      await notifier.loadData(); // 下拉重整：只更新今日頁、不通知其他頁
      await notifier.reloadAfterResume();

      expect(
        c.read(dataUpdateEpochProvider),
        greaterThan(epochBefore),
        reason: '比對基準若是「當下 state」，下拉重整已把變化吃掉、永遠不通知',
      );
    });

    test('只有資料日變（同一筆 run 補寫了資料）→ 通知其他頁', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      when(
        () => mockDataSyncService.getDisplayDataDate(any(), any()),
      ).thenReturn(DateTime(2026, 9, 25));
      await notifier.reloadAfterResume();

      expect(c.read(dataUpdateEpochProvider), greaterThan(epochBefore));
    });

    test('App 外的更新還在跑（RUNNING）→ 先不通知，跑完後的下一次才通知', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      when(() => mockDb.getLatestUpdateRun()).thenAnswer(
        (_) async => UpdateRunEntry(
          id: 2,
          runDate: DateTime(2026, 9, 24),
          // 孤兒判斷以真實時間計算，進行中的 run 必須是剛開始的
          startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          status: 'RUNNING',
        ),
      );
      await notifier.reloadAfterResume();
      expect(c.read(dataUpdateEpochProvider), epochBefore, reason: '寫到一半');

      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 21, 31)));
      await notifier.reloadAfterResume();
      expect(c.read(dataUpdateEpochProvider), greaterThan(epochBefore));
    });

    test('載入途中觸發了 App 內更新（冷啟動）→ 不通知，交給那一輪收尾', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      final pending = Completer<UpdateResult>();
      when(
        () => mockUpdateService.runDailyUpdate(
          force: any(named: 'force'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => pending.future);
      // 模擬 loadData 內的冷啟動判斷啟動了一輪更新（會同步設 isUpdating）
      when(() => mockDb.getLatestUpdateRun()).thenAnswer((_) async {
        unawaited(notifier.runUpdate().then((_) {}, onError: (_) {}));
        return run(DateTime(2026, 9, 24, 21, 31));
      });
      await notifier.reloadAfterResume();

      expect(c.read(todayProvider).isUpdating, isTrue, reason: '前提');
      expect(c.read(dataUpdateEpochProvider), epochBefore);
      expect(market.loads, 0);
    });

    test('通知過一次後 DB 沒再變 → 下次回前景不重複通知', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();

      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 21, 31)));
      await notifier.reloadAfterResume();
      final epochAfterFirst = c.read(dataUpdateEpochProvider);

      await notifier.reloadAfterResume();

      expect(c.read(dataUpdateEpochProvider), epochAfterFirst);
      expect(market.loads, 1);
    });

    test('App 內更新完成（已通知）後回前景 → 不重複通知', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();

      when(
        () => mockUpdateService.runDailyUpdate(
          force: any(named: 'force'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer(
        (_) async => UpdateResult(date: DateTime(2026, 9, 24))..success = true,
      );
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 21, 31)));
      await notifier.runUpdate();
      final epochAfterUpdate = c.read(dataUpdateEpochProvider);
      final marketLoadsAfterUpdate = market.loads;

      await notifier.reloadAfterResume();

      expect(c.read(dataUpdateEpochProvider), epochAfterUpdate);
      expect(market.loads, marketLoadsAfterUpdate);
    });

    test('孤兒 RUNNING（CLI 中途崩潰、超過孤兒門檻）不擋通知', () async {
      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 15, 31)));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      final startedAt = DateTime.now().subtract(const Duration(hours: 3));
      when(() => mockDb.getLatestUpdateRun()).thenAnswer(
        (_) async => UpdateRunEntry(
          id: 3,
          runDate: DateTime(2026, 9, 24),
          startedAt: startedAt,
          status: 'RUNNING',
        ),
      );
      await notifier.reloadAfterResume();

      expect(
        c.read(dataUpdateEpochProvider),
        greaterThan(epochBefore),
        reason: '崩潰前寫進去的資料不該被一筆永遠 RUNNING 的紀錄擋到下一輪',
      );
    });

    test('首次載入失敗、之後 DB 被更新 → 回前景仍通知', () async {
      when(() => mockDb.getLatestUpdateRun()).thenThrow(Exception('db busy'));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      when(
        () => mockDb.getLatestUpdateRun(),
      ).thenAnswer((_) async => run(DateTime(2026, 9, 24, 21, 31)));
      await notifier.reloadAfterResume();

      expect(c.read(dataUpdateEpochProvider), greaterThan(epochBefore));
    });

    test('回前景時載入又失敗 → 不通知（不叫其他頁在 DB 出錯時重讀）', () async {
      when(() => mockDb.getLatestUpdateRun()).thenThrow(Exception('db busy'));
      final notifier = c.read(todayProvider.notifier);
      await notifier.loadData();
      final epochBefore = c.read(dataUpdateEpochProvider);

      await notifier.reloadAfterResume();

      expect(c.read(dataUpdateEpochProvider), epochBefore);
      expect(market.loads, 0);
    });

    test('App 內更新進行中 → 跳過（那一輪結束時本就會收尾）', () async {
      final pending = Completer<UpdateResult>();
      when(
        () => mockUpdateService.runDailyUpdate(
          force: any(named: 'force'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => pending.future);
      final notifier = c.read(todayProvider.notifier);
      unawaited(notifier.runUpdate().then((_) {}, onError: (_) {}));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(todayProvider).isUpdating, isTrue, reason: '前提');
      clearInteractions(mockDb);

      await notifier.reloadAfterResume();

      verifyNever(() => mockDb.getLatestUpdateRun());
    });
  });
}

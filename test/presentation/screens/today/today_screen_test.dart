import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/today/today_screen.dart';
import 'package:daredevil/presentation/screens/today/widgets/data_stale_banner.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/update_progress_banner.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeTodayNotifier extends TodayNotifier {
  TodayState initialState = const TodayState();
  int runUpdateCalls = 0;

  @override
  TodayState build() => initialState;

  @override
  Future<void> loadData() async {}

  int reloadCalls = 0;

  /// 模擬重讀 DB 後的狀態（例如 launchd 已在 App 外寫入新資料）
  TodayState? stateAfterReload;

  @override
  Future<void> reloadAfterResume() async {
    reloadCalls++;
    if (stateAfterReload case final s?) state = s;
  }

  @override
  Future<UpdateResult> runUpdate({bool force = false}) async {
    runUpdateCalls++;
    return UpdateResult(date: DateTime(2026, 9, 18))..success = true;
  }
}

class _FixedClock implements AppClock {
  const _FixedClock(this.fixed);
  final DateTime fixed;
  @override
  DateTime now() => fixed;
}

class FakeWatchlistNotifier extends WatchlistNotifier {
  WatchlistState initialState = WatchlistState();

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
  Future<bool> addStock(String symbol) async => true;

  @override
  Future<bool> removeStock(String symbol) async => true;

  @override
  Future<void> restoreStock(String symbol) async {}
}

class FakeMarketOverviewNotifier extends MarketOverviewNotifier {
  MarketOverviewState initialState = const MarketOverviewState();

  /// 設定後 loadData 會卡住直到完成（模擬網路慢）
  static Completer<void>? hold;

  @override
  MarketOverviewState build() => initialState;

  @override
  Future<void> loadData() async => hold?.future;
}

class FakeSettingsNotifier extends SettingsNotifier {
  SettingsState initialState = const SettingsState();

  @override
  SettingsState build() => initialState;

  @override
  void setThemeMode(ThemeMode mode) {}

  @override
  void setShowROCYear(bool value) {}

  @override
  void setShowWarningBadges(bool value) {}

  @override
  void setInsiderNotifications(bool value) {}

  @override
  void setDisposalUrgentAlerts(bool value) {}

  @override
  void setLimitAlerts(bool value) {}

  @override
  void setCacheDurationMinutes(int minutes) {}

  @override
  void setAutoUpdateEnabled(bool value) {}
}

// ==========================================
// Tests
// ==========================================

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestWidget({
    TodayState? todayState,
    WatchlistState? watchlistState,
    MarketOverviewState? marketState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
    Future<List<ModeRecommendation>> Function(Ref, ScoringMode)?
    modeRecommendations,
    AppClock? clock,
    FakeTodayNotifier? todayNotifier,
  }) {
    final today = todayState ?? const TodayState();
    final watchlist = watchlistState ?? WatchlistState();
    final market = marketState ?? const MarketOverviewState();
    final settings = settingsState ?? const SettingsState();
    return buildProviderTestApp(
      const TodayScreen(),
      overrides: [
        todayProvider.overrideWith(() {
          final n = todayNotifier ?? FakeTodayNotifier();
          n.initialState = today;
          return n;
        }),
        if (clock != null) appClockProvider.overrideWithValue(clock),
        watchlistProvider.overrideWith(() {
          final n = FakeWatchlistNotifier();
          n.initialState = watchlist;
          return n;
        }),
        marketOverviewProvider.overrideWith(() {
          final n = FakeMarketOverviewNotifier();
          n.initialState = market;
          return n;
        }),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = settings;
          return n;
        }),
        // 2026-06-19：3-tab Mode UI 加上。Today 篩選器改 FutureProvider.family，
        // 用 SynchronousFuture 同步 resolve、跳過 loading state、避開
        // CircularProgressIndicator 的 ticker 留下 pending timer 的 test infra bug。
        modeRecommendationsProvider.overrideWith(
          modeRecommendations ?? (ref, mode) => SynchronousFuture(const []),
        ),
      ],
      brightness: brightness,
    );
  }

  ModeRecommendation rec(String symbol, {String? trend}) => ModeRecommendation(
    symbol: symbol,
    rank: 1,
    modeScoreShort: 20,
    modeScoreLong: 20,
    reasons: const [],
    stockName: '測試$symbol',
    latestClose: 100,
    priceChange: 1.0,
    trendState: trend,
  );

  // 標籤依注入的時鐘判斷「今天」（原本用 DateTime.now()，與落後提示的
  // 時間來源不一致）。
  group('資料日期標籤', () {
    final now = DateTime(2026, 9, 17, 17);

    test('同一天 → 今日', () {
      expect(formatDataDateLabel(DateTime(2026, 9, 17), now), S.todayDataToday);
    });

    test('前一天 → 昨日', () {
      expect(
        formatDataDateLabel(DateTime(2026, 9, 16), now),
        S.todayDataYesterday,
      );
    });

    test('更早 → M/D', () {
      expect(formatDataDateLabel(DateTime(2026, 9, 14), now), '9/14');
    });
  });

  // 資料日期原本只是一行灰字「M/D」，落後好幾天也看不出來。以交易日判斷
  // 落後：週一早上的上週五資料、連假後的節前資料都不算。
  group('資料落後提示', () {
    Future<FakeTodayNotifier> pumpAt(
      WidgetTester tester, {
      required DateTime? dataDate,
      required DateTime now,
      bool isUpdating = false,
    }) async {
      widenViewport(tester);
      final notifier = FakeTodayNotifier();
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(
            dataDate: dataDate,
            lastUpdate: dataDate,
            isUpdating: isUpdating,
          ),
          clock: _FixedClock(now),
          todayNotifier: notifier,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return notifier;
    }

    testWidgets('🚨 落後交易日時顯示提示，並可直接更新', (tester) async {
      final notifier = await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 14),
        now: DateTime(2026, 9, 18, 17),
      );

      expect(find.text('today.dataStale'), findsOneWidget);
      // 元件內的文字另有真實翻譯測試；這裡驗今日頁傳進去的值
      final banner = tester.widget<DataStaleBanner>(
        find.byType(DataStaleBanner),
      );
      expect(banner.tradingDaysBehind, 4);
      expect(banner.dataDate, DateTime(2026, 9, 14));

      await tester.tap(find.text('today.updateNow'));
      await tester.pump();
      expect(notifier.runUpdateCalls, 1);
    });

    testWidgets('週一早上看上週五資料 → 不提示', (tester) async {
      await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 18),
        now: DateTime(2026, 9, 21, 9),
      );
      expect(find.text('today.dataStale'), findsNothing);
    });

    testWidgets('更新進行中 → 不提示（進度條已在顯示）', (tester) async {
      await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 14),
        now: DateTime(2026, 9, 18, 17),
        isUpdating: true,
      );
      expect(find.text('today.dataStale'), findsNothing);
    });

    testWidgets('還沒有任何資料 → 不提示（屬於首次安裝的空狀態）', (tester) async {
      await pumpAt(tester, dataDate: null, now: DateTime(2026, 9, 18, 17));
      expect(find.text('today.dataStale'), findsNothing);
    });
  });

  // 下拉原本只重讀 DB、不抓新資料（台股 App 的慣例是下拉＝抓最新），而且
  // loadData 會把整頁換成骨架、捲動位置跟著消失。
  group('下拉重新整理', () {
    Future<FakeTodayNotifier> pumpAt(
      WidgetTester tester, {
      required DateTime? dataDate,
      required DateTime now,
      bool isLoading = false,
      TodayState? afterReload,
    }) async {
      widenViewport(tester);
      final notifier = FakeTodayNotifier()..stateAfterReload = afterReload;
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(
            dataDate: dataDate,
            lastUpdate: dataDate,
            isLoading: isLoading,
          ),
          clock: _FixedClock(now),
          todayNotifier: notifier,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return notifier;
    }

    Future<void> pullToRefresh(WidgetTester tester) async {
      await tester
          .widget<ThemedRefreshIndicator>(find.byType(ThemedRefreshIndicator))
          .onRefresh();
      await tester.pump();
    }

    testWidgets('🚨 資料落後 → 下拉就跑更新', (tester) async {
      final notifier = await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 14),
        now: DateTime(2026, 9, 18, 17),
      );

      await pullToRefresh(tester);

      expect(notifier.runUpdateCalls, 1);
    });

    testWidgets('資料已是最新 → 不白跑更新，重讀並告知已是最新', (tester) async {
      final notifier = await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 18),
        now: DateTime(2026, 9, 18, 17),
      );

      await pullToRefresh(tester);

      expect(notifier.runUpdateCalls, 0);
      expect(notifier.reloadCalls, 1, reason: 'App 外的更新要能被帶進來');
      expect(find.text('today.alreadyLatest'), findsOneWidget);
    });

    testWidgets('🚨 先重讀 DB 再判斷：launchd 已寫入今天 → 不白跑更新', (tester) async {
      // App 開著、離開不到 30 分鐘，記憶體還是昨天；DB 其實已有今天
      final notifier = await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 17),
        now: DateTime(2026, 9, 18, 17),
        afterReload: TodayState(
          dataDate: DateTime(2026, 9, 18),
          lastUpdate: DateTime(2026, 9, 18, 15, 31),
        ),
      );

      await pullToRefresh(tester);

      expect(notifier.reloadCalls, 1);
      expect(notifier.runUpdateCalls, 0);
      expect(find.text('today.alreadyLatest'), findsOneWidget);
    });

    testWidgets('🚨 要跑更新時不必先等大盤的網路載入', (tester) async {
      FakeMarketOverviewNotifier.hold = Completer<void>();
      addTearDown(() => FakeMarketOverviewNotifier.hold = null);
      final notifier = await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 14),
        now: DateTime(2026, 9, 18, 17),
      );

      unawaited(
        tester
            .widget<ThemedRefreshIndicator>(find.byType(ThemedRefreshIndicator))
            .onRefresh(),
      );
      await tester.pump();

      expect(notifier.runUpdateCalls, 1, reason: '大盤載入卡住也不該擋住更新');
      FakeMarketOverviewNotifier.hold!.complete();
      await tester.pump();
    });

    testWidgets('已有推薦清單時重讀失敗 → 部分錯誤橫幅顯示、不說已是最新', (tester) async {
      widenViewport(tester);
      final notifier = FakeTodayNotifier()
        ..stateAfterReload = TodayState(
          dataDate: DateTime(2026, 9, 18),
          lastUpdate: DateTime(2026, 9, 18),
          error: 'db busy',
        );
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(
            dataDate: DateTime(2026, 9, 18),
            lastUpdate: DateTime(2026, 9, 18),
          ),
          clock: _FixedClock(DateTime(2026, 9, 18, 17)),
          todayNotifier: notifier,
          modeRecommendations: (ref, mode) =>
              SynchronousFuture([rec('2330', trend: 'UP')]),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester
          .widget<ThemedRefreshIndicator>(find.byType(ThemedRefreshIndicator))
          .onRefresh();
      await tester.pump();

      expect(find.textContaining('db busy'), findsOneWidget);
      expect(find.text('today.alreadyLatest'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('重讀失敗 → 不說「已是最新」', (tester) async {
      await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 18),
        now: DateTime(2026, 9, 18, 17),
        afterReload: TodayState(
          dataDate: DateTime(2026, 9, 18),
          lastUpdate: DateTime(2026, 9, 18),
          error: 'db busy',
        ),
      );

      await pullToRefresh(tester);

      expect(find.text('today.alreadyLatest'), findsNothing);
      // 重讀失敗會切到錯誤畫面，其進場動畫的 timer 要跑完
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('更新進行中 → 不說「已是最新」', (tester) async {
      await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 18),
        now: DateTime(2026, 9, 18, 17),
        afterReload: TodayState(
          dataDate: DateTime(2026, 9, 18),
          lastUpdate: DateTime(2026, 9, 18),
          isUpdating: true,
        ),
      );

      await pullToRefresh(tester);

      expect(find.text('today.alreadyLatest'), findsNothing);
    });

    testWidgets('還沒有任何資料 → 下拉就跑更新', (tester) async {
      final notifier = await pumpAt(
        tester,
        dataDate: null,
        now: DateTime(2026, 9, 18, 17),
      );

      await pullToRefresh(tester);

      expect(notifier.runUpdateCalls, 1);
    });

    testWidgets('🚨 推薦清單重算時保留舊清單，不換成轉圈', (tester) async {
      // DB 有變就 bump epoch → 推薦 provider 重算；AsyncValue.when 預設
      // reload 時回到 loading，清單被整塊換掉、捲動位置消失
      widenViewport(tester);
      var calls = 0;
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(
            dataDate: DateTime(2026, 9, 18),
            lastUpdate: DateTime(2026, 9, 18),
          ),
          clock: _FixedClock(DateTime(2026, 9, 18, 17)),
          // 與正式 provider 相同：watch epoch，bump 時以「依賴改變」reload
          modeRecommendations: (ref, mode) {
            final epoch = ref.watch(dataUpdateEpochProvider);
            calls++;
            return epoch == 0
                ? SynchronousFuture([rec('2330', trend: 'UP')])
                : Completer<List<ModeRecommendation>>().future;
          },
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2330'), findsOneWidget, reason: '前提');

      ProviderScope.containerOf(
        tester.element(find.byType(TodayScreen)),
      ).read(dataUpdateEpochProvider.notifier).bump();
      await tester.pump();
      expect(calls, greaterThan(1), reason: '前提：確實觸發了重算');

      expect(find.text('2330'), findsOneWidget);
    });

    testWidgets('🚨 已有內容時重新載入 → 不換成骨架（保留畫面與捲動位置）', (tester) async {
      await pumpAt(
        tester,
        dataDate: DateTime(2026, 9, 18),
        now: DateTime(2026, 9, 18, 17),
        isLoading: true,
      );

      expect(find.byType(StockListShimmer), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);
    });
  });

  // 訊號清單是最容易被當成「明牌」的地方；全文聲明只在首次同意頁與「關於」，
  // 清單底部要常駐短版。有訊號、沒訊號都要在。
  group('今日清單常駐短版免責聲明', () {
    testWidgets('有訊號時顯示在清單下方', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          modeRecommendations: (ref, mode) =>
              SynchronousFuture([rec('2330', trend: 'UP')]),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2330'), findsOneWidget, reason: '前提：清單有渲染');
      expect(find.text('disclaimer.short'), findsOneWidget);
    });

    testWidgets('沒有訊號時也顯示（空狀態撐滿視窗，聲明在其下方）', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await tester.scrollUntilVisible(
        find.text('disclaimer.short'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('disclaimer.short'), findsOneWidget);
    });
  });

  group('起漲候選趨勢分艙(2026-08-12)', () {
    Widget appWith(List<ModeRecommendation> momentum) => buildTestWidget(
      todayState: const TodayState(),
      modeRecommendations: (ref, mode) => SynchronousFuture(
        mode == ScoringMode.momentumEntry ? momentum : const [],
      ),
    );

    testWidgets('🚨 DOWN 卡預設收合:清單只見 UP/RANGE,收合列帶數量', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        appWith([
          rec('2376', trend: 'RANGE'),
          rec('1314', trend: 'DOWN'),
          rec('2201', trend: 'DOWN'),
        ]),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2376'), findsOneWidget);
      expect(find.text('1314'), findsNothing, reason: 'DOWN 卡預設不可見');
      expect(find.text('2201'), findsNothing);
      // 測試環境 .tr() 渲染原始 key(不做參數替換)
      expect(
        find.textContaining('today.trendGateCollapsed'),
        findsOneWidget,
        reason: '必須有收合列讓使用者知道有東西被收起來,不可無聲吞掉',
      );
    });

    testWidgets('🚨 點收合列展開:DOWN 卡出現且被淡化', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        appWith([rec('2376', trend: 'RANGE'), rec('1314', trend: 'DOWN')]),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.textContaining('today.trendGateCollapsed'));
      // Use multiple pumps to handle flutter_animate timers(檔內既有慣例)
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1314'), findsOneWidget, reason: '展開後資料要在——分艙不是過濾');
      final dimmed = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('1314'),
              matching: find.byType(Opacity),
            ),
          )
          .any((o) => o.opacity < 0.6);
      expect(dimmed, isTrue, reason: '後艙卡片必須淡化,與前艙有視覺區隔');
      // 鏡像斷言(2026-08-13 審查變異實測:全部淡化時整套照樣綠)——
      // 「視覺區隔」是雙邊性質,單邊斷言守不住它
      final qualifiedDimmed = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('2376'),
              matching: find.byType(Opacity),
            ),
          )
          .any((o) => o.opacity < 0.6);
      expect(qualifiedDimmed, isFalse, reason: '前艙卡片不可淡化——區隔就在這');
    });

    testWidgets('🚨 全 DOWN 日自動展開:不可只剩一條收合列的空畫面', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        appWith([rec('1314', trend: 'DOWN'), rec('2201', trend: 'DOWN')]),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1314'), findsOneWidget, reason: '前艙全空時強制展開');
      expect(find.text('2201'), findsOneWidget);
      expect(
        find.byIcon(Icons.expand_less),
        findsNothing,
        reason: '鎖定狀態不顯示收合箭頭——收起來就什麼都沒有',
      );
    });

    testWidgets('全部過門檻時不顯示收合列', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(appWith([rec('2376', trend: 'UP')]));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('today.trendGateCollapsed'), findsNothing);
    });

    testWidgets('🚨 強勢觀察 tab 不分艙(DOWN 卡直接可見)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          modeRecommendations: (ref, mode) => SynchronousFuture(
            mode == ScoringMode.strengthObserve
                ? [rec('1314', trend: 'DOWN')]
                : const [],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // 切到強勢觀察 tab
      await tester.tap(find.text('scoringMode.strengthObserve'));
      // Use multiple pumps to handle flutter_animate timers(檔內既有慣例)
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1314'), findsOneWidget, reason: 'B/C tab 的語意不同,不套趨勢門檻');
      expect(find.textContaining('today.trendGateCollapsed'), findsNothing);
    });
  });

  group('TodayScreen', () {
    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(todayState: const TodayState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockListShimmer), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(todayState: const TodayState(error: 'Network error')),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('mode 推薦載入失敗:可重試的錯誤狀態,tap 後重新載入(2026-07-30 審查)', (
      tester,
    ) async {
      widenViewport(tester);
      var calls = 0;
      await tester.pumpWidget(
        buildTestWidget(
          modeRecommendations: (ref, mode) {
            calls++;
            if (calls == 1) throw StateError('mode 資料炸了');
            return SynchronousFuture(const []);
          },
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // 裸 Text('Error: ...') 升級成 EmptyStates.error(帶重試)
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(S.retry), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing);

      // tap 重試 → provider invalidate → 第二次成功(空清單空狀態)
      await tester.tap(find.text(S.retry));
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2, reason: '重試必須真的 invalidate 重新載入');
      expect(find.text(S.emptyError), findsNothing);
    });

    testWidgets('自選跌破警示條:有跌破顯示紅條、無跌破不渲染(2026-07-31)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [
              const WatchlistItemData(symbol: '2330', stockName: '台積電'),
              const WatchlistItemData(
                symbol: '6414',
                stockName: '樺漢',
                reasons: ['BREAK_MA60', 'RSI_EXTREME_OVERSOLD'],
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // 測試 localization 是 key-passthrough(namedArgs 不代入),驗 key+icon
      expect(find.text('today.watchlistMaBreak'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('自選無跌破:警示條不渲染(零噪音)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [const WatchlistItemData(symbol: '2330', stockName: '台積電')],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('today.watchlistMaBreak'), findsNothing);
      expect(find.byIcon(Icons.trending_down), findsNothing);
    });

    // ── 站回均線警示條(2026-08-21)────────────────────────────────
    //
    // 跌破那半 2026-07-31 就做了,站回這半的訊號(RECLAIM_MA20/60)一直有算、
    // 有落庫、有分數,卻沒有任何地方顯示——實機 8/21 台積電站回季線,
    // 使用者的第一屏完全沒提示。風控看跌破、找機會看站回,兩邊對稱才完整。
    testWidgets('🚨 自選站回均線顯示綠條(對稱於跌破條)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [
              const WatchlistItemData(symbol: '2317', stockName: '鴻海'),
              const WatchlistItemData(
                symbol: '2330',
                stockName: '台積電',
                reasons: ['RECLAIM_MA60'],
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('today.watchlistMaReclaim'), findsOneWidget);
      // 用 _rounded 變體辨識:trending_up 在本頁 SectionHeader 已被佔用,
      // 拿它斷言會誤判(2026-08-21 寫測試時實際踩到)
      final icon = tester.widget<Icon>(find.byIcon(Icons.trending_up_rounded));
      // 🚨 站回條**不得是紅色**。第一版用了 AppTheme.upColor(= PriceColors.up
      // #FF4757,台股「漲=紅」),結果與跌破條的 error 紅在畫面上撞成一模一樣
      // ——使用者實機一眼就看出兩條都紅(2026-08-21)。這條 banner 表達的是
      // 「事件好壞」不是股價漲跌,紅綠是股價保留區(semantic_colors.dart),
      // 正向事件該走 successColor(品牌藍)。
      expect(
        icon.color,
        isNot(AppTheme.upColor),
        reason: '站回是正向事件,不得借用股價漲色——會與跌破紅條撞色',
      );
      expect(icon.color, AppTheme.successColor);
    });

    testWidgets('自選無站回:綠條不渲染(零噪音,與跌破條同標準)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [const WatchlistItemData(symbol: '2330', stockName: '台積電')],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('today.watchlistMaReclaim'), findsNothing);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    });

    testWidgets('🚨 跌破與站回同時發生時兩條並存(不得互相吃掉)', (tester) async {
      // 修復期的典型盤面:有人剛垮、有人剛回來。任一條被另一條蓋掉,
      // 使用者就會漏看其中一半。
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [
              const WatchlistItemData(
                symbol: '3711',
                stockName: '日月光投控',
                reasons: ['BREAK_MA20'],
              ),
              const WatchlistItemData(
                symbol: '2330',
                stockName: '台積電',
                reasons: ['RECLAIM_MA60'],
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('today.watchlistMaBreak'), findsOneWidget);
      expect(find.text('today.watchlistMaReclaim'), findsOneWidget);
    });

    testWidgets('shows refresh icon when not updating', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows progress indicator when updating', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(todayState: const TodayState(isUpdating: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('shows notifications icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });

    testWidgets('shows more menu with settings', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Settings is now in the overflow menu
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('shows empty recommendations state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // EmptyState for no recommendations
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows SliverAppBar with app name', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SliverAppBar), findsOneWidget);
    });

    testWidgets('shows last update and data date', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(
            lastUpdate: DateTime(2026, 2, 20, 18, 0),
            dataDate: DateTime(2026, 2, 20),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // 最後更新與資料日期兩個資訊區塊都應渲染
      // （測試環境未載入翻譯，.tr() 回傳 key）
      expect(find.text('today.lastUpdate'), findsOneWidget);
      expect(find.text('today.dataDate'), findsOneWidget);
    });

    testWidgets('shows update progress banner', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          todayState: const TodayState(
            isUpdating: true,
            updateProgress: UpdateProgress(
              currentStep: 3,
              totalSteps: 10,
              message: 'Updating...',
            ),
          ),
        ),
      );
      // Use multiple pumps to handle flutter_animate timers
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // banner 本體必須渲染（AppBar 在 isUpdating 時本來就有一顆 spinner，
      // 驗 CircularProgressIndicator 無法區分兩者）
      expect(find.byType(UpdateProgressBanner), findsOneWidget);
    });

    testWidgets('shows section header for recommendations', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // trending_up icon from SectionHeader
      expect(find.byIcon(Icons.trending_up), findsAtLeastNWidgets(1));
    });
  });
}

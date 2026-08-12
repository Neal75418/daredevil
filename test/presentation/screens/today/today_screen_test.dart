import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/core/l10n/app_strings.dart';

import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/today/today_screen.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/update_progress_banner.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeTodayNotifier extends TodayNotifier {
  TodayState initialState = const TodayState();

  @override
  TodayState build() => initialState;

  @override
  Future<void> loadData() async {}
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

  @override
  MarketOverviewState build() => initialState;

  @override
  Future<void> loadData() async {}
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
  }) {
    final today = todayState ?? const TodayState();
    final watchlist = watchlistState ?? WatchlistState();
    final market = marketState ?? const MarketOverviewState();
    final settings = settingsState ?? const SettingsState();
    return buildProviderTestApp(
      const TodayScreen(),
      overrides: [
        todayProvider.overrideWith(() {
          final n = FakeTodayNotifier();
          n.initialState = today;
          return n;
        }),
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

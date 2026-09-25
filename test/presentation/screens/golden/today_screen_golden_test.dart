/// Golden test: TodayScreen
///
/// 驗證首頁推薦股列表在 light/dark 模式下的視覺一致性。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/domain/services/update/history_coverage.dart';
import 'package:daredevil/presentation/providers/history_coverage_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:daredevil/presentation/screens/today/today_screen.dart';

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
  void setLocale(AppLocale locale) {}

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
// Test Data
// ==========================================

final _testDate = DateTime(2026, 3, 10);

/// 時鐘釘在資料日當天收盤資料就緒後：資料落後提示依時鐘計算，用真實時間
/// 會讓提示出現、golden 隨執行日期漂移。
class _FixedClock implements AppClock {
  const _FixedClock();
  @override
  DateTime now() => DateTime(2026, 3, 10, 17);
}

// 2026-06-19：Today screen 改 Mode-based、推薦來自 modeRecommendationsProvider
// （非 todayProvider.recommendations），fixtures 改成 ModeRecommendation。
final _testModeRecommendations = [
  ModeRecommendation(
    symbol: '2330',
    rank: 1,
    modeScoreShort: 45.0,
    modeScoreLong: 38.0,
    reasons: const [],
    stockName: '台積電',
    market: 'TWSE',
    latestClose: 950.0,
    priceChange: 2.5,
    trendState: 'UP',
    recentPrices: const [920, 925, 930, 940, 945, 950],
  ),
  ModeRecommendation(
    symbol: '2317',
    rank: 2,
    modeScoreShort: 32.0,
    modeScoreLong: 28.0,
    reasons: const [],
    stockName: '鴻海',
    market: 'TWSE',
    latestClose: 185.0,
    priceChange: -1.2,
    trendState: 'DOWN',
    recentPrices: const [190, 188, 186, 185],
  ),
  ModeRecommendation(
    symbol: '2454',
    rank: 3,
    modeScoreShort: 28.0,
    modeScoreLong: 22.0,
    reasons: const [],
    stockName: '聯發科',
    market: 'TWSE',
    latestClose: 1250.0,
    priceChange: 0.8,
    trendState: 'UP',
    recentPrices: const [1230, 1240, 1245, 1250],
  ),
];

/// 今日頁頂端的大盤摘要條要有內容才看得到版面（兩個主指數＋漲跌家數＋
/// 成交額歷史讓情緒算得出來）
final _testMarket = MarketOverviewState(
  indices: [
    TwseMarketIndex(
      date: _testDate,
      name: MarketIndexNames.taiex,
      close: 22150.3,
      change: -61.2,
      changePercent: -0.28,
    ),
    TwseMarketIndex(
      date: _testDate,
      name: MarketIndexNames.tpexIndex,
      close: 245.6,
      change: 0.25,
      changePercent: 0.1,
    ),
  ],
  advanceDeclineByMarket: const {
    MarketCode.twse: AdvanceDecline(advance: 408, decline: 667, unchanged: 149),
  },
  historyTrends: HistoryTrends(
    turnover: {
      MarketCode.twse: [
        (date: DateTime(2026, 3, 9), value: 3500.0),
        (date: DateTime(2026, 3, 10), value: 3200.0),
      ],
    },
  ),
);

// ==========================================
// Helpers
// ==========================================

void widenViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget buildTestWidget({
  TodayState? todayState,
  Brightness brightness = Brightness.light,
}) {
  final today =
      todayState ??
      TodayState(
        // recommendations 已搬到 modeRecommendationsProvider override（下方）；
        // 這裡只保留 lastUpdate / dataDate 給 header banner 用。
        lastUpdate: _testDate,
        dataDate: _testDate,
      );
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
        return n;
      }),
      marketOverviewProvider.overrideWith(() {
        final n = FakeMarketOverviewNotifier();
        n.initialState = _testMarket;
        return n;
      }),
      settingsProvider.overrideWith(() {
        final n = FakeSettingsNotifier();
        return n;
      }),
      modeRecommendationsProvider.overrideWith(
        (ref, mode) => SynchronousFuture(_testModeRecommendations),
      ),
      appClockProvider.overrideWithValue(const _FixedClock()),
      // 建置進度固定為已補齊：否則會讀到共用測試 DB（其他測試寫入的股票、
      // 沒有價格），golden 隨測試執行順序出現／消失建置橫幅
      historyCoverageProvider.overrideWith(
        (ref) => SynchronousFuture(const HistoryCoverage(covered: 1, total: 1)),
      ),
    ],
    brightness: brightness,
  );
}

// ==========================================
// Golden Tests
// ==========================================

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('TodayScreen Golden', () {
    testWidgets('light mode with recommendations', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/today_screen_light.png'),
      );
    });

    testWidgets('dark mode with recommendations', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget(brightness: Brightness.dark));
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/today_screen_dark.png'),
      );
    });
  });
}

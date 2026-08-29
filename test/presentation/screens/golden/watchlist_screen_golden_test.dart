/// Golden test: WatchlistScreen
///
/// 驗證自選股清單在 light/dark 模式下的視覺一致性。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_screen.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeWatchlistNotifier extends WatchlistNotifier {
  WatchlistState initialState = WatchlistState();

  @override
  WatchlistState build() => initialState;

  @override
  Future<void> loadData() async {}

  @override
  void loadMore() {}

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

class FakePortfolioNotifier extends PortfolioNotifier {
  PortfolioState initialState = const PortfolioState();

  @override
  PortfolioState build() => initialState;

  @override
  Future<void> loadPositions() async {}

  @override
  Future<void> deleteTransaction(int id, String symbol) async {}

  @override
  Future<void> addBuy({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    String? note,
  }) async {}

  @override
  Future<void> addSell({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {}

  @override
  Future<void> addDividend({
    required String symbol,
    required DateTime date,
    required double amount,
    required bool isCash,
    String? note,
  }) async {}
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

final _testItems = [
  WatchlistItemData(
    symbol: '2330',
    stockName: '台積電',
    market: 'TWSE',
    latestClose: 950.0,
    priceChange: 2.5,
    score: 85,
    trendState: 'UP',
    hasSignal: true,
    addedAt: DateTime(2026, 1, 15),
    recentPrices: [920, 925, 930, 940, 945, 950],
  ),
  WatchlistItemData(
    symbol: '2317',
    stockName: '鴻海',
    market: 'TWSE',
    latestClose: 185.0,
    priceChange: -1.2,
    score: 55,
    trendState: 'DOWN',
    addedAt: DateTime(2026, 2, 1),
    recentPrices: [190, 188, 186, 185],
  ),
  WatchlistItemData(
    symbol: '2454',
    stockName: '聯發科',
    market: 'TWSE',
    latestClose: 1250.0,
    priceChange: 0.8,
    score: 72,
    trendState: 'UP',
    hasSignal: true,
    addedAt: DateTime(2026, 2, 10),
    recentPrices: [1230, 1240, 1245, 1250],
  ),
];

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
  WatchlistState? watchlistState,
  Brightness brightness = Brightness.light,
}) {
  final watchlist =
      watchlistState ?? WatchlistState(items: _testItems, hasMore: false);
  return buildProviderTestApp(
    const WatchlistScreen(),
    overrides: [
      watchlistProvider.overrideWith(() {
        final n = FakeWatchlistNotifier();
        n.initialState = watchlist;
        return n;
      }),
      portfolioProvider.overrideWith(() {
        final n = FakePortfolioNotifier();
        return n;
      }),
      settingsProvider.overrideWith(() {
        final n = FakeSettingsNotifier();
        return n;
      }),
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

  group('WatchlistScreen Golden', () {
    testWidgets('light mode with items', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/watchlist_screen_light.png'),
      );
    });

    testWidgets('dark mode with items', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget(brightness: Brightness.dark));
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/watchlist_screen_dark.png'),
      );
    });
  });
}

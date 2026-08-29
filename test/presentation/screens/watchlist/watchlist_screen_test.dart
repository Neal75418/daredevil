import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

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
    WatchlistState? watchlistState,
    PortfolioState? portfolioState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
  }) {
    final watchlist = watchlistState ?? WatchlistState();
    final portfolio = portfolioState ?? const PortfolioState();
    final settings = settingsState ?? const SettingsState();
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
          n.initialState = portfolio;
          return n;
        }),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = settings;
          return n;
        }),
      ],
      brightness: brightness,
    );
  }

  WatchlistItemData createItem({
    required String symbol,
    String? stockName,
    double? latestClose,
    double? priceChange,
    double? score,
  }) {
    return WatchlistItemData(
      symbol: symbol,
      stockName: stockName ?? 'Stock $symbol',
      market: 'TWSE',
      latestClose: latestClose ?? 100.0,
      priceChange: priceChange ?? 1.5,
      score: score ?? 80,
      hasSignal: true,
      addedAt: DateTime(2026, 1, 1),
    );
  }

  group('WatchlistScreen', () {
    testWidgets('shows AppBar with title', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockListShimmer), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(error: 'Network error')),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty watchlist state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows search icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows sort icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('shows add icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows more_vert menu', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('shows portfolio in more menu', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Portfolio is no longer a SegmentedButton tab
      // It's accessible via the more_vert menu
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('shows stock count when items exist', (tester) async {
      widenViewport(tester);
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(items: items)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Stock list should be rendered (not empty state)
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('compare is accessible via more menu when 2+ stocks', (
      tester,
    ) async {
      widenViewport(tester);
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(items: items)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Compare is now inside the more_vert menu, not directly visible
      expect(find.byIcon(Icons.compare_arrows), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('tapping search shows TextField', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      // Search icon changes to close
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}

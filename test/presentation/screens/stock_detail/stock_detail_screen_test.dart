import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/stock_detail_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeStockDetailNotifier extends StockDetailNotifier {
  FakeStockDetailNotifier(super.symbol);

  StockDetailState initialState = const StockDetailState();
  int loadDataCalls = 0;

  @override
  StockDetailState build() => initialState;

  @override
  Future<void> loadData() async => loadDataCalls++;

  @override
  Future<void> loadFundamentals() async {}

  @override
  Future<void> loadInsiderData() async {}

  @override
  Future<void> loadChipData() async {}

  @override
  Future<void> toggleWatchlist() async {}
}

class FakePriceAlertNotifier extends PriceAlertNotifier {
  PriceAlertState initialState = const PriceAlertState();

  @override
  PriceAlertState build() => initialState;

  @override
  Future<void> loadAlerts() async {}

  @override
  Future<void> deleteAlert(int id) async {}

  @override
  Future<void> toggleAlert(int id, bool isActive) async {}

  @override
  Future<bool> createAlert({
    required String symbol,
    required AlertType alertType,
    required double targetValue,
    String? note,
  }) async {
    return true;
  }
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

  FakeStockDetailNotifier? lastStockNotifier;

  Widget buildTestWidget({
    StockDetailState? stockState,
    PriceAlertState? alertState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
  }) {
    final stock = stockState ?? const StockDetailState();
    final alert = alertState ?? const PriceAlertState();
    final settings = settingsState ?? const SettingsState();
    return buildProviderTestApp(
      const StockDetailScreen(symbol: '2330'),
      overrides: [
        stockDetailProvider.overrideWith2((symbol) {
          final n = FakeStockDetailNotifier(symbol);
          n.initialState = stock;
          return lastStockNotifier = n;
        }),
        priceAlertProvider.overrideWith(() {
          final n = FakePriceAlertNotifier();
          n.initialState = alert;
          return n;
        }),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = settings;
          return n;
        }),
        primaryRuleAccuracySummaryProvider.overrideWith(
          (ref, symbol) async => null,
        ),
      ],
      brightness: brightness,
    );
  }

  group('StockDetailScreen', () {
    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(
            loading: LoadingState(isLoading: true),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockDetailShimmer), findsOneWidget);
    });

    testWidgets('shows error state with retry', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(error: 'Network error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows SliverAppBar with symbol', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SliverAppBar), findsOneWidget);
      expect(find.text('2330'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows compare button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
    });

    testWidgets('shows watchlist star button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Not in watchlist → star_border
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });

    testWidgets('shows filled star when in watchlist', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(isInWatchlist: true),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('shows TabBar with 5 tabs', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(5));
    });

    testWidgets('shows NestedScrollView when loaded', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NestedScrollView), findsOneWidget);
    });
  });

  group('已有內容時的重載（背景 epoch）', () {
    final withContent = StockPriceState(
      latestPrice: DailyPriceEntry(
        symbol: '2330',
        date: DateTime(2026, 2, 13),
        close: 600,
      ),
    );

    testWidgets('載入中仍顯示內容，不切成整頁 shimmer', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: withContent,
            loading: const LoadingState(isLoading: true),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockDetailShimmer), findsNothing);
      expect(find.byType(NestedScrollView), findsOneWidget);
    });

    testWidgets('重載失敗：保留內容，以 banner 顯示錯誤與重試', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: withContent,
            error: 'Database error',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('Database error'), findsOneWidget);
    });

    testWidgets('只有股名（無價格）也算有內容', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: StockPriceState(
              stock: StockMasterEntry(
                symbol: '2330',
                name: '台積電',
                market: 'TWSE',
                isActive: true,
                updatedAt: DateTime(2026, 2, 13),
              ),
            ),
            error: 'Database error',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(MaterialBanner), findsOneWidget);
    });

    testWidgets('banner：重試呼叫 loadData、關閉清掉錯誤', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: withContent,
            error: 'Database error',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final callsBefore = lastStockNotifier!.loadDataCalls;

      await tester.tap(find.text('common.retry'));
      await tester.pump();
      expect(lastStockNotifier!.loadDataCalls, callsBefore + 1);

      await tester.tap(find.text('common.dismiss'));
      await tester.pump();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.byType(NestedScrollView), findsOneWidget);
    });

    testWidgets('沒有內容時照舊顯示整頁錯誤，不顯示 banner', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(error: 'Database error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
    });
  });
}

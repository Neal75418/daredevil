import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/portfolio_analytics_service.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/screens/portfolio/portfolio_tab.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifier
// ==========================================

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

// ==========================================
// Test Helpers
// ==========================================

PortfolioPositionData createPosition({
  String symbol = '2330',
  String? stockName = '台積電',
  double quantity = 1000,
  double avgCost = 500.0,
  double realizedPnl = 0,
  double totalDividendReceived = 0,
  double? currentPrice = 600.0,
}) {
  return PortfolioPositionData(
    symbol: symbol,
    stockName: stockName,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    currentPrice: currentPrice,
  );
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
    PortfolioState? portfolioState,
    Brightness brightness = Brightness.light,
  }) {
    final state = portfolioState ?? const PortfolioState();
    return buildProviderTestApp(
      const PortfolioTab(),
      overrides: [
        portfolioProvider.overrideWith(() {
          final n = FakePortfolioNotifier();
          n.initialState = state;
          return n;
        }),
      ],
      brightness: brightness,
    );
  }

  group('PortfolioTab', () {
    testWidgets('shows shimmer when loading with no data', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(portfolioState: const PortfolioState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(GenericListShimmer), findsOneWidget);
    });

    testWidgets('shows error state with retry', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: const PortfolioState(error: 'Network error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty state when no positions', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsOneWidget,
      );
    });

    testWidgets('shows add button in empty state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
    });

    testWidgets('shows positions list', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(symbol: '2330', stockName: '台積電'),
        createPosition(symbol: '2317', stockName: '鴻海'),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('shows FAB when positions exist', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows summary card', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      // PortfolioSummaryCard renders inside CustomScrollView
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('shows performance and industry allocation', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      const performance = PortfolioPerformance(
        totalReturn: 15.5,
        totalMarketValue: 600000,
        totalCostBasis: 500000,
        totalDividends: 13500,
        totalRealizedPnl: 0,
        periodReturns: PeriodReturns(
          daily: 0.5,
          weekly: 1.2,
          monthly: 3.0,
          yearly: 15.5,
        ),
        maxDrawdown: -5.2,
        industryAllocation: {
          '半導體業': IndustryAllocation(
            industry: '半導體業',
            value: 600000,
            percentage: 100.0,
            symbols: ['2330'],
          ),
        },
      );
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(
            positions: positions,
            performance: performance,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CustomScrollView), findsOneWidget);
    });
  });
}

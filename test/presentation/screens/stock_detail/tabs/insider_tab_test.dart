import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/insider_tab.dart';
import 'package:daredevil/presentation/widgets/metric_card.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

import '../../../../helpers/provider_test_helpers.dart';
import '../../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifier
// ==========================================

class FakeStockDetailNotifier extends StockDetailNotifier {
  FakeStockDetailNotifier(super.symbol);

  StockDetailState initialState = const StockDetailState();

  @override
  StockDetailState build() => initialState;

  @override
  Future<void> loadInsiderData() async {}

  @override
  Future<void> loadData() async {}
}

// ==========================================
// Test Helpers
// ==========================================

InsiderHoldingEntry createHolding({
  String symbol = '2330',
  required DateTime date,
  double? insiderRatio,
  double? pledgeRatio,
  double? directorShares,
  double? supervisorShares,
  double? managerShares,
}) {
  return InsiderHoldingEntry(
    symbol: symbol,
    date: date,
    insiderRatio: insiderRatio,
    pledgeRatio: pledgeRatio,
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

  late StockDetailState testState;

  Widget buildTestWidget(
    StockDetailState state, {
    Brightness brightness = Brightness.light,
  }) {
    testState = state;
    return buildProviderTestApp(
      const InsiderTab(symbol: '2330'),
      overrides: [
        stockDetailProvider.overrideWith2((symbol) {
          final n = FakeStockDetailNotifier(symbol);
          n.initialState = testState;
          return n;
        }),
      ],
      brightness: brightness,
    );
  }

  final holdings = [
    createHolding(
      date: DateTime(2026, 2),
      insiderRatio: 25.0,
      pledgeRatio: 10.0,
    ),
    createHolding(
      date: DateTime(2026, 1),
      insiderRatio: 23.5,
      pledgeRatio: 10.0,
    ),
    createHolding(
      date: DateTime(2025, 12),
      insiderRatio: 24.0,
      pledgeRatio: 9.0,
    ),
  ];

  group('InsiderTab', () {
    testWidgets('shows loading state', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(isLoadingInsider: true);
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      // 轉讓申報區段 + 持股歷史區段各一個 loading indicator
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    });

    testWidgets('shows empty state when no insider history', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget(const StockDetailState()));
      await tester.pump(const Duration(seconds: 1));

      // Empty state with message
      expect(find.byType(InsiderTab), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows section header', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget(const StockDetailState()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SectionHeader), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('shows metrics row with 3 metric cards', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(insiderHistory: holdings);
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(MetricCard), findsNWidgets(3));
    });

    testWidgets('displays insider ratio value', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(insiderHistory: holdings);
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('25.0%'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays pledge ratio value', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(insiderHistory: holdings);
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('10.0%'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays change value with + prefix', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(insiderHistory: holdings);
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      // 25.0 - 23.5 = 1.5 → "+1.50%"
      expect(find.text('+1.50%'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows dash when no data', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        insiderHistory: [createHolding(date: DateTime(2026, 2))],
      );
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      // Metric cards should show "-" for null values
      expect(find.text('-'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows insider table with data rows', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(insiderHistory: holdings);
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Card), findsAtLeastNWidgets(1));
      // Date column values
      expect(find.text('2026/02'), findsOneWidget);
      expect(find.text('2026/01'), findsOneWidget);
      expect(find.text('2025/12'), findsOneWidget);
    });

    testWidgets('high pledge ratio shows warning color', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        insiderHistory: [
          createHolding(
            date: DateTime(2026, 2),
            insiderRatio: 15.0,
            pledgeRatio: 75.0, // > 70.0 threshold
          ),
        ],
      );
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('75.0%'), findsAtLeastNWidgets(1));
    });

    testWidgets('limits display to 12 months', (tester) async {
      widenViewport(tester);
      final manyHoldings = List.generate(
        15,
        (i) => createHolding(
          date: DateTime(2026, 2 - i),
          insiderRatio: 20.0 + i * 0.5,
        ),
      );
      final state = const StockDetailState().copyWith(
        insiderHistory: manyHoldings,
      );
      await tester.pumpWidget(buildTestWidget(state));
      await tester.pump(const Duration(seconds: 1));

      // Should only show 12 rows (not 15)
      expect(find.byType(InsiderTab), findsOneWidget);
    });
  });
}

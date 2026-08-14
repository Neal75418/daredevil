import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/dividend_intelligence_service.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/dividend_analysis_card.dart';

import '../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  StockDividendInfo createStockInfo({
    String symbol = '2330',
    double personalYield = 4.5,
    DividendTrend trend = DividendTrend.stable,
  }) {
    return StockDividendInfo(
      symbol: symbol,
      estimatedDividendPerShare: 12.5,
      expectedYearlyAmount: 12500,
      personalYield: personalYield,
      trend: trend,
    );
  }

  group('DividendAnalysisCard', () {
    testWidgets('returns SizedBox.shrink when empty', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: 0,
              portfolioYieldOnCost: 0,
              portfolioYieldOnMarket: 0,
              stockDividends: [],
            ),
          ),
        ),
      );

      // Empty → SizedBox.shrink
      expect(find.byIcon(Icons.payments_outlined), findsNothing);
    });

    testWidgets('displays payments icon with data', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: 50000,
              portfolioYieldOnCost: 4.2,
              portfolioYieldOnMarket: 3.5,
              stockDividends: [createStockInfo()],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    });

    testWidgets('displays yield percentages', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: 50000,
              portfolioYieldOnCost: 4.20,
              portfolioYieldOnMarket: 3.50,
              stockDividends: [createStockInfo()],
            ),
          ),
        ),
      );

      expect(find.text('4.20%'), findsOneWidget);
      expect(find.text('3.50%'), findsOneWidget);
    });

    testWidgets('displays stock dividend rows', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: 50000,
              portfolioYieldOnCost: 4.2,
              portfolioYieldOnMarket: 3.5,
              stockDividends: [
                createStockInfo(symbol: '2330'),
                createStockInfo(symbol: '2317'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('2330'), findsOneWidget);
      expect(find.text('2317'), findsOneWidget);
    });

    testWidgets('shows trend icons', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: 50000,
              portfolioYieldOnCost: 4.2,
              portfolioYieldOnMarket: 3.5,
              stockDividends: [
                createStockInfo(trend: DividendTrend.increasing),
                createStockInfo(
                  symbol: '2317',
                  trend: DividendTrend.decreasing,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('limits to 5 stock rows', (tester) async {
      widenViewport(tester);
      final stocks = List.generate(8, (i) => createStockInfo(symbol: '230$i'));

      await tester.pumpWidget(
        buildTestApp(
          DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: 100000,
              portfolioYieldOnCost: 5.0,
              portfolioYieldOnMarket: 4.0,
              stockDividends: stocks,
            ),
          ),
        ),
      );

      // Only first 5 should appear
      expect(find.text('2300'), findsOneWidget);
      expect(find.text('2304'), findsOneWidget);
      expect(find.text('2305'), findsNothing);
    });
  });
}

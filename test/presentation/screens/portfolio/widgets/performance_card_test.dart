import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/domain/services/portfolio_analytics_service.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/performance_card.dart';

import '../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  PortfolioPerformance createPerformance({
    double totalReturn = 12.5,
    double maxDrawdown = 3.2,
    PeriodReturns? periodReturns,
  }) {
    return PortfolioPerformance(
      totalReturn: totalReturn,
      totalMarketValue: 1000000,
      totalCostBasis: 900000,
      totalDividends: 5000,
      totalRealizedPnl: 10000,
      periodReturns:
          periodReturns ??
          const PeriodReturns(
            daily: 0.5,
            weekly: 2.1,
            monthly: 8.3,
            yearly: 15.0,
          ),
      maxDrawdown: maxDrawdown,
      industryAllocation: const {},
    );
  }

  group('PerformanceCard', () {
    // Widen viewport: untranslated i18n keys are long strings that overflow
    // the default 800px test surface.
    void widenViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());
    }

    testWidgets('displays analytics icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PerformanceCard(performance: createPerformance())),
      );

      expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
    });

    testWidgets('displays period return values', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(
            performance: createPerformance(
              periodReturns: const PeriodReturns(
                daily: 0.5,
                weekly: 2.1,
                monthly: 8.3,
                yearly: 15.0,
              ),
            ),
          ),
        ),
      );

      // daily: +0.50%
      expect(find.text('+0.50%'), findsOneWidget);
      // weekly: +2.10%
      expect(find.text('+2.10%'), findsOneWidget);
      // monthly: +8.30%
      expect(find.text('+8.30%'), findsOneWidget);
      // yearly: +15.00%
      expect(find.text('+15.00%'), findsOneWidget);
    });

    testWidgets('displays negative returns without + prefix', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(
            performance: createPerformance(
              periodReturns: const PeriodReturns(
                daily: -0.8,
                weekly: -3.5,
                monthly: -10.2,
                yearly: -25.0,
              ),
            ),
          ),
        ),
      );

      expect(find.text('-0.80%'), findsOneWidget);
      expect(find.text('-3.50%'), findsOneWidget);
    });

    testWidgets('displays total return', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(performance: createPerformance(totalReturn: 12.5)),
        ),
      );

      expect(find.text('+12.50%'), findsOneWidget);
    });

    testWidgets('平盤期間報酬（0%）中性、無 + 號', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(
            performance: createPerformance(
              periodReturns: const PeriodReturns(
                daily: 0,
                weekly: 2.1,
                monthly: 8.3,
                yearly: 15.0,
              ),
            ),
          ),
        ),
      );

      expect(find.text('+0.00%'), findsNothing);
      final daily = tester.widget<Text>(find.text('0.00%'));
      expect(daily.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    });

    testWidgets('微負期間報酬（-0.004）捨入歸零、中性、無 -0.00%', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(
            performance: createPerformance(
              periodReturns: const PeriodReturns(
                daily: -0.004,
                weekly: 2.1,
                monthly: 8.3,
                yearly: 15.0,
              ),
            ),
          ),
        ),
      );

      expect(find.text('-0.00%'), findsNothing);
      expect(find.text('+0.00%'), findsNothing);
      final daily = tester.widget<Text>(find.text('0.00%'));
      expect(daily.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    });

    testWidgets('平盤總報酬（0%）中性、無 + 號', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(performance: createPerformance(totalReturn: 0)),
        ),
      );

      expect(find.text('+0.00%'), findsNothing);
      final total = tester.widget<Text>(find.text('0.00%'));
      expect(total.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    });

    testWidgets('shows info icon for annualized yearly return', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PerformanceCard(performance: createPerformance())),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('算不出來的期間報酬顯示「—」，不顯示 0.00%', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(
            performance: createPerformance(
              periodReturns: const PeriodReturns(),
            ),
          ),
        ),
      );

      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('0.00%'), findsNothing);
    });

    testWidgets('年化的說明圖示提示「持有滿一年才換算」', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PerformanceCard(performance: createPerformance())),
      );

      expect(find.byTooltip('portfolio.yearlyHint'.tr()), findsOneWidget);
    });

    testWidgets('🚨 當前回撤是虧損：用下跌色，與總報酬率同一套紅漲綠跌', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PerformanceCard(
            performance: createPerformance(totalReturn: 5, maxDrawdown: 3.2),
          ),
        ),
      );

      final drawdown = tester.widget<Text>(find.text('-3.20%'));
      expect(drawdown.style?.color, AppTheme.downColor);
    });

    testWidgets('renders with empty performance', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const PerformanceCard(performance: PortfolioPerformance.empty),
        ),
      );

      expect(find.byType(PerformanceCard), findsOneWidget);
    });
  });
}

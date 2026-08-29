import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/portfolio_summary_card.dart';

import '../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  PortfolioSummary createSummary({
    double totalMarketValue = 1000000,
    double totalCostBasis = 900000,
    double totalUnrealizedPnl = 80000,
    double totalRealizedPnl = 10000,
    double totalDividends = 5000,
    int positionCount = 5,
    int unpricedCount = 0,
  }) {
    return PortfolioSummary(
      totalMarketValue: totalMarketValue,
      totalCostBasis: totalCostBasis,
      totalUnrealizedPnl: totalUnrealizedPnl,
      totalRealizedPnl: totalRealizedPnl,
      totalDividends: totalDividends,
      positionCount: positionCount,
      unpricedCount: unpricedCount,
    );
  }

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(3000, 2400);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('PortfolioSummaryCard', () {
    testWidgets('🚨 有缺價持股 → 顯示「N 檔未計價」警示(靜默稽核 #5)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PortfolioSummaryCard(summary: createSummary(unpricedCount: 2)),
        ),
      );
      expect(find.text('portfolio.unpricedWarning'), findsOneWidget);
    });

    testWidgets('全部有價 → 不顯示警示(不誤報)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PortfolioSummaryCard(summary: createSummary())),
      );
      expect(find.text('portfolio.unpricedWarning'), findsNothing);
    });

    testWidgets('displays market value with NT\$ prefix', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PortfolioSummaryCard(summary: createSummary())),
      );

      expect(find.byType(PortfolioSummaryCard), findsOneWidget);
      // Should contain NT$ somewhere in the text
      expect(find.textContaining('NT\$'), findsWidgets);
    });

    testWidgets('renders with positive PnL', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PortfolioSummaryCard(
            summary: createSummary(
              totalUnrealizedPnl: 50000,
              totalRealizedPnl: 10000,
              totalDividends: 5000,
            ),
          ),
        ),
      );

      expect(find.byType(PortfolioSummaryCard), findsOneWidget);
      // totalPnl = 50000 + 10000 + 5000 = 65000 (positive → has +)
      expect(find.textContaining('+'), findsWidgets);
    });

    testWidgets('平盤 P/L（0）顯示中性、無 + 號', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PortfolioSummaryCard(
            summary: createSummary(
              totalUnrealizedPnl: 0,
              totalRealizedPnl: 0,
              totalDividends: 0,
            ),
          ),
        ),
      );

      // totalPnl == 0：任何損益列皆不得帶 + 號
      expect(find.textContaining('+'), findsNothing);
      // 百分比顯示 0.0%（非 +0.0%）
      expect(find.text('(0.0%)'), findsOneWidget);
      // 主損益列文字（NT$0）配色為中性、非漲色
      final pnlText = tester.widget<Text>(find.text('NT\$0'));
      expect(pnlText.style?.color, isNot(AppTheme.upColor));
      expect(pnlText.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    });

    testWidgets('明細微負損益（-0.004）0 位捨入為 0：中性色、不顯示 -0', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PortfolioSummaryCard(
            summary: createSummary(
              totalUnrealizedPnl: -0.004,
              totalRealizedPnl: 12345,
              totalDividends: 6789,
            ),
          ),
        ),
      );

      // -0.004 捨入為 0 的明細不得出現 -0，且著中性色
      expect(find.text('-0'), findsNothing);
      final pnl = tester.widget<Text>(find.text('0'));
      expect(pnl.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    });
  });
}

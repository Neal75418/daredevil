import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/margin_trading_section.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/mini_trend_chart.dart';

import '../../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  MarginTradingEntry createEntry({
    String symbol = '2330',
    DateTime? date,
    double? marginBalance = 50000,
    double? shortBalance = 3000,
  }) {
    return MarginTradingEntry(
      symbol: symbol,
      date: date ?? DateTime(2026, 2, 14),
      marginBalance: marginBalance,
      shortBalance: shortBalance,
    );
  }

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Future<void> pumpSection(
    WidgetTester tester,
    Widget widget, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(buildTestApp(widget, brightness: brightness));
    await tester.pump(const Duration(seconds: 1));
  }

  group('MarginTradingSection', () {
    testWidgets('displays swap_horiz icon', (tester) async {
      widenViewport(tester);
      await pumpSection(tester, MarginTradingSection(history: [createEntry()]));

      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('shows empty state when history is empty', (tester) async {
      widenViewport(tester);
      await pumpSection(tester, const MarginTradingSection(history: []));

      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('displays margin balance summary', (tester) async {
      widenViewport(tester);
      await pumpSection(
        tester,
        MarginTradingSection(
          history: [createEntry(marginBalance: 50000, shortBalance: 3000)],
        ),
      );

      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      expect(find.byIcon(Icons.percent), findsOneWidget);
    });

    testWidgets('displays the short/margin ratio', (tester) async {
      widenViewport(tester);
      await pumpSection(
        tester,
        MarginTradingSection(
          history: [createEntry(marginBalance: 10000, shortBalance: 2000)],
        ),
      );

      // ratio = 2000/10000*100 = 20%（低於 highShortMarginRatio 30，不觸發警示）
      expect(find.textContaining('20.0%'), findsWidgets);
    });

    // loader 為評分多讀的列（融資回溯窗）不應拉長走勢圖：圖與表格同一段期間
    testWidgets('走勢圖只畫最近 10 列、由舊到新', (tester) async {
      widenViewport(tester);
      await pumpSection(
        tester,
        MarginTradingSection(
          history: [
            for (var i = 14; i >= 1; i--)
              createEntry(
                date: DateTime(2026, 3, i),
                marginBalance: 1000.0 + i,
              ),
          ],
        ),
      );

      final chart = tester.widget<MiniTrendChart>(find.byType(MiniTrendChart));
      expect(chart.dataPoints, [for (var i = 5; i <= 14; i++) 1000.0 + i]);
    });
  });
}

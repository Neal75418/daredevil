import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/institutional_flow_chart.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('formatFlowAmount（依語系分級）', () {
    const zh = Locale('zh', 'TW');
    const en = Locale('en');

    test('中文：億依大小取 0/1/2 位小數，未滿 1 億降到千萬、百萬', () {
      expect(formatFlowAmount(43_400_000_000, zh), '+434 億');
      expect(formatFlowAmount(5_000_000_000, zh), '+50.0 億');
      expect(formatFlowAmount(150_000_000, zh), '+1.50 億');
      expect(formatFlowAmount(-50_000_000, zh), '-5.0 千萬');
      expect(formatFlowAmount(3_000_000, zh), '+3 百萬');
    });

    test('英文走 K/M/B：434 億 = 43.4 billion，不是 434 billion', () {
      expect(formatFlowAmount(43_400_000_000, en), '+43.4B');
      expect(formatFlowAmount(-50_000_000, en), '-50.0M');
      expect(formatFlowAmount(3_000_000, en), '+3.0M');
    });
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  const totals = InstitutionalTotals(
    foreignNet: 43400000000, // +434 億
    trustNet: 5000000000, // +50 億
    dealerNet: 2000000000, // +20 億
    totalNet: 50400000000,
  );

  group('InstitutionalFlowChart 金額依 context 語系格式化', () {
    // 外資列 434 億、合計列 504 億
    for (final (locale, foreign, total) in [
      (const Locale('zh', 'TW'), '+434 億', '+504 億'),
      (const Locale('en', 'US'), '+43.4B', '+50.4B'),
    ]) {
      testWidgets('$locale → 外資 $foreign、合計 $total', (tester) async {
        widenViewport(tester);
        await tester.pumpWidget(
          buildTestApp(
            const InstitutionalFlowChart(data: totals),
            locale: locale,
          ),
        );
        expect(find.textContaining(foreign), findsOneWidget);
        expect(find.textContaining(total), findsOneWidget);
      });
    }
  });

  group('InstitutionalFlowChart dealer hedge annotation', () {
    testWidgets('dealer row shows hedge tooltip; foreign/trust do not', (
      tester,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(const InstitutionalFlowChart(data: totals)),
      );

      // 自營含避險提示：恰好一個 Tooltip（僅自營列）
      final hedgeTooltip = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'marketOverview.dealerHedgeNote',
      );
      expect(hedgeTooltip, findsOneWidget);

      // ⓘ icon 只出現在自營列（外資/投信列無此標註）
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      // 三法人名稱都在（確認標註未影響其他列渲染）
      expect(find.text('marketOverview.foreign'), findsOneWidget);
      expect(find.text('marketOverview.trust'), findsOneWidget);
      expect(find.text('marketOverview.dealer'), findsOneWidget);
    });
  });
}

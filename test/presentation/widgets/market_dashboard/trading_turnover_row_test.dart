import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/trading_turnover_row.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('TradingTurnoverRow', () {
    testWidgets('returns empty when totalTurnover is 0', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const TradingTurnoverRow(data: TradingTurnover())),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byIcon(Icons.paid_rounded), findsNothing);
    });

    testWidgets('displays icon and formatted value', (tester) async {
      // Widen the test surface to avoid overflow from untranslated key strings
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = TradingTurnover(totalTurnover: 642195569620);
      await tester.pumpWidget(
        buildTestApp(const TradingTurnoverRow(data: data)),
      );

      expect(find.byIcon(Icons.paid_rounded), findsOneWidget);
      expect(find.byType(TradingTurnoverRow), findsOneWidget);
    });

    testWidgets('成交額以 context 語系格式化(測試 MaterialApp 預設 en_US)', (tester) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = TradingTurnover(totalTurnover: 642195569620);
      await tester.pumpWidget(
        buildTestApp(const TradingTurnoverRow(data: data)),
      );

      expect(find.textContaining('NT\$642.2B'), findsOneWidget);
    });

    testWidgets('5日均微幅正變動（+0.4%）0 位捨入為 0：不顯示 +0%、中性色', (tester) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = TradingTurnover(totalTurnover: 5e10);
      // changePercent = (1004 - 1000) / 1000 * 100 = 0.4% → 0 位捨入為 0
      const comparison = TurnoverComparison(
        todayTurnover: 1004,
        avg5dTurnover: 1000,
      );
      await tester.pumpWidget(
        buildTestApp(
          const TradingTurnoverRow(data: data, turnoverComparison: comparison),
        ),
      );

      expect(find.textContaining('+0%'), findsNothing);
      final badge = tester.widget<Text>(
        find.textContaining('marketOverview.avg5d'),
      );
      expect(badge.style?.color, AppTheme.getFlatColor(Brightness.light));
    });

    // Regression — 2026-06 screenshot 顯示左卡片 5日均 badge 右側溢出 1.1px。
    // 觸發條件：半寬 dashboard 卡片 + 萬億級成交額 + 5 位數百分比。
    // FittedBox(scaleDown) 修正在此寬度下不應再 throw RenderFlex overflow。
    // 判讀層（P2）— 量價判讀行
    testWidgets('renders volume-price interpretation line for valid input', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      // today 130 vs avg5d 100 → +30% 量增；指數漲 → healthyUp
      const data = TradingTurnover(totalTurnover: 5e10);
      const comparison = TurnoverComparison(
        todayTurnover: 130,
        avg5dTurnover: 100,
      );
      await tester.pumpWidget(
        buildTestApp(
          const TradingTurnoverRow(
            data: data,
            turnoverComparison: comparison,
            indexChangePercent: 1.0,
          ),
        ),
      );

      // .tr() 未載入翻譯時回傳 key
      expect(
        find.text('marketOverview.reading.volumePrice.healthyUp'),
        findsOneWidget,
      );
    });

    testWidgets('no interpretation line when indexChangePercent is absent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = TradingTurnover(totalTurnover: 5e10);
      const comparison = TurnoverComparison(
        todayTurnover: 130,
        avg5dTurnover: 100,
      );
      // 缺 indexChangePercent → 不顯示判讀行
      await tester.pumpWidget(
        buildTestApp(
          const TradingTurnoverRow(data: data, turnoverComparison: comparison),
        ),
      );

      expect(
        find.textContaining('marketOverview.reading.volumePrice'),
        findsNothing,
      );
    });

    testWidgets('no interpretation line when turnoverComparison is absent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = TradingTurnover(totalTurnover: 5e10);
      // 有指數但無均量比較 → 不顯示判讀行
      await tester.pumpWidget(
        buildTestApp(
          const TradingTurnoverRow(data: data, indexChangePercent: 1.0),
        ),
      );

      expect(
        find.textContaining('marketOverview.reading.volumePrice'),
        findsNothing,
      );
    });

    testWidgets(
      'narrow card with huge turnover + 5-digit percent does not overflow',
      (tester) async {
        const data = TradingTurnover(totalTurnover: 1.6494e12); // ~16,494 億
        // changePercent = (today - avg5d) / avg5d * 100 → ~28631%
        // 模擬 screenshot 的「+287..%」5 位數情境。
        const comparison = TurnoverComparison(
          todayTurnover: 1.6494e12,
          avg5dTurnover: 5.74e9,
        );

        await tester.pumpWidget(
          buildTestApp(
            const Center(
              child: SizedBox(
                width: 360, // 半寬 dashboard 卡片實測寬度 (~320-400)
                child: TradingTurnoverRow(
                  data: data,
                  turnoverComparison: comparison,
                ),
              ),
            ),
            // 中文字串（「16,494.00 億元」）比英文（「NT$1.6T」）長，驗較寬者
            locale: const Locale('zh', 'TW'),
          ),
        );

        // 等動畫穩定，allow FittedBox 完成 scaleDown 量測
        await tester.pumpAndSettle();

        expect(find.textContaining('16,494.00 億元'), findsOneWidget);
        // 沒 RenderFlex overflow assertion 才算通過
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('formatTurnover', () {
    const zh = Locale('zh', 'TW');
    const en = Locale('en');

    test('中文固定以億元:< 1000 億兩位、≥ 1000 億一位、≥ 10000 億兩位', () {
      expect(formatTurnover(5e10, zh), '500.00 億元');
      expect(formatTurnover(642195569620, zh), '6,422.0 億元');
      expect(formatTurnover(1.2e12, zh), '12,000.00 億元');
    });

    test('英文走 K/M/B/T:6,422 億 = 642.2 billion,不是 6,422 billion', () {
      expect(formatTurnover(5e10, en), 'NT\$50.0B');
      expect(formatTurnover(642195569620, en), 'NT\$642.2B');
      expect(formatTurnover(1.2e12, en), 'NT\$1.2T');
    });
  });
}

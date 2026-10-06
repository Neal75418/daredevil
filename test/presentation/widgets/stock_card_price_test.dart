import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/presentation/widgets/stock_card_price.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  group('StockCardPriceSection', () {
    testWidgets('displays closing price', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 150.50,
            priceColor: Colors.green,
          ),
        ),
      );

      expect(find.text('150.50'), findsOneWidget);
    });

    testWidgets('displays positive price change with sign', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 150.00,
            priceChange: 2.50,
            priceColor: Colors.green,
          ),
        ),
      );

      // Should show formatted change text
      expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    });

    testWidgets('displays negative price change', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 100.00,
            priceChange: -3.00,
            priceColor: Colors.red,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('does not show arrow icons for zero change', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 100.00,
            priceChange: 0,
            priceColor: Colors.grey,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('hides price text when latestClose is null', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const StockCardPriceSection(priceColor: Colors.grey)),
      );

      // Column should have no Text children with price format
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders in compact mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 50.00,
            priceChange: 1.50,
            priceColor: Colors.green,
            compact: true,
          ),
        ),
      );

      expect(find.text('50.00'), findsOneWidget);
    });

    testWidgets('limitStatus 為漲停 → 顯示漲停標記', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 110.00,
            priceChange: 10.0,
            priceColor: Colors.red,
            limitStatus: PriceLimitStatus.limitUp,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('limitStatus 為跌停鎖 → 顯示跌停標記', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 90.00,
            priceChange: -10.0,
            priceColor: Colors.green,
            limitStatus: PriceLimitStatus.limitDownLocked,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('🚨 價格區塊自己不推算:limitStatus 為 none 時漲 10% 也不標', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 110.00,
            priceChange: 10.0,
            priceColor: Colors.red,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });

    // 平盤/微負值迴歸 —— flat-value sign/color 缺陷類第三輪
    //
    // 原本 `isPositive = (priceChange ?? 0) >= 0` 讓平盤落入「正」分支，
    // 而 `isNeutral` 只認「恰為 0」：微負值 -0.004 會渲染成 `-0.00%` 並配
    // 向下箭頭，與顯示出來的 0.00% 自相矛盾。修正後方向與正負號一律以
    // 「捨入到顯示精度（2 位）後的值」判定。
    testWidgets('平盤（0）顯示 0.00%、不帶正負號、無方向箭頭', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 100.00,
            priceChange: 0,
            priceColor: AppTheme.neutralColor,
          ),
        ),
      );

      expect(find.textContaining('0.00%'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(find.textContaining('-'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('微負值 -0.004 捨入為 0：顯示 0.00%、不帶負號、無方向箭頭', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 100.00,
            priceChange: -0.004,
            priceColor: AppTheme.neutralColor,
          ),
        ),
      );

      expect(find.textContaining('0.00%'), findsOneWidget);
      // 不得出現 -0.00% / -0.00 這種負零
      expect(find.textContaining('-'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('compact 模式微負值同樣中性', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 100.00,
            priceChange: -0.004,
            priceColor: AppTheme.neutralColor,
            compact: true,
          ),
        ),
      );

      expect(find.textContaining('0.00%'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('真實上漲仍帶 + 號與上箭頭（未過度中性化）', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 150.00,
            priceChange: 1.67,
            priceColor: AppTheme.upColor,
          ),
        ),
      );

      expect(find.textContaining('+1.67%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    });

    testWidgets('真實下跌仍帶 - 號與下箭頭', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 97.00,
            priceChange: -3.00,
            priceColor: AppTheme.downColor,
          ),
        ),
      );

      expect(find.textContaining('-3.00%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 100.00,
            priceChange: 1.5,
            priceColor: Colors.green,
          ),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('100.00'), findsOneWidget);
    });
  });
}

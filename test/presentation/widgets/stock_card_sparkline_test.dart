import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/widgets/stock_card_sparkline.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  // 走勢圖顏色依「畫出來那段」的首尾漲跌（而非今日漲跌）；朗讀標籤同一個值
  group('MiniSparkline.trendChangePercent', () {
    test('上漲 → 正值', () {
      expect(
        MiniSparkline.trendChangePercent([100, 101, 103, 105, 108, 110]),
        closeTo(10, 1e-9),
      );
    });

    test('下跌 → 負值', () {
      expect(
        MiniSparkline.trendChangePercent([110, 108, 105, 103, 101, 100]),
        lessThan(0),
      );
    });

    test('變化不到 0.1% → 視為持平（0）', () {
      expect(
        MiniSparkline.trendChangePercent([1000, 1003, 998, 1001, 1000.5]),
        0,
      );
    });

    // 30 筆只畫最後 20 筆：前 10 筆很高、後 20 筆從低處上漲 → 看得到的是上漲
    test('只看畫出來的最後 20 筆', () {
      final prices = [
        ...List.filled(10, 200.0),
        for (var i = 0; i < 20; i++) 100.0 + i,
      ];
      expect(MiniSparkline.trendChangePercent(prices), greaterThan(0));
    });

    test('資料不足（< 5 筆）→ null', () {
      expect(MiniSparkline.trendChangePercent([100, 101, 102]), isNull);
    });
  });

  group('MiniSparkline', () {
    testWidgets('returns SizedBox.shrink when fewer than 5 data points', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          const MiniSparkline(prices: [100, 101, 102, 103], color: Colors.red),
        ),
      );

      // Should render SizedBox.shrink (no LineChart)
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('returns SizedBox.shrink for empty list', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const MiniSparkline(prices: [], color: Colors.red)),
      );

      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('renders LineChart when >= 5 data points with variation', (
      tester,
    ) async {
      // Prices with sufficient variation (> 0.3%)
      const prices = [100.0, 102.0, 98.0, 105.0, 103.0, 107.0, 110.0];
      await tester.pumpWidget(
        buildTestApp(const MiniSparkline(prices: prices, color: Colors.blue)),
      );

      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('returns SizedBox.shrink when variation < 0.3%', (
      tester,
    ) async {
      // All prices very close — variation < 0.3%
      const prices = [100.00, 100.01, 100.02, 100.01, 100.00];
      await tester.pumpWidget(
        buildTestApp(const MiniSparkline(prices: prices, color: Colors.green)),
      );

      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('samples last 20 points when data exceeds max', (tester) async {
      // 25 data points with variation — should sample last 20
      final prices = List.generate(25, (i) => 100.0 + i * 2);
      await tester.pumpWidget(
        buildTestApp(MiniSparkline(prices: prices, color: Colors.orange)),
      );

      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('has Semantics wrapper with image role', (tester) async {
      const prices = [100.0, 105.0, 98.0, 110.0, 103.0, 107.0];
      await tester.pumpWidget(
        buildTestApp(const MiniSparkline(prices: prices, color: Colors.red)),
      );

      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('renders with RepaintBoundary for performance', (tester) async {
      const prices = [100.0, 105.0, 98.0, 110.0, 103.0, 107.0];
      await tester.pumpWidget(
        buildTestApp(const MiniSparkline(prices: prices, color: Colors.red)),
      );

      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('uses custom width and height when provided', (tester) async {
      const prices = [100.0, 105.0, 98.0, 110.0, 103.0, 107.0];
      await tester.pumpWidget(
        buildTestApp(
          const MiniSparkline(
            prices: prices,
            color: Colors.blue,
            width: 120,
            height: 48,
          ),
        ),
      );

      expect(find.byType(LineChart), findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(LineChart),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.width, 120);
      expect(sizedBox.height, 48);
    });

    testWidgets('uses default size when width/height not provided', (
      tester,
    ) async {
      const prices = [100.0, 105.0, 98.0, 110.0, 103.0, 107.0];
      await tester.pumpWidget(
        buildTestApp(const MiniSparkline(prices: prices, color: Colors.blue)),
      );

      expect(find.byType(LineChart), findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(LineChart),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.width, 70);
      expect(sizedBox.height, 32);
    });
  });
}

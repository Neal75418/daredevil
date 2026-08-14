// 月營收年增分佈橫幅(2026-08-14「市場體溫」)
//
// 這頁 1,900+ 列只能逐列讀個股,回答不了「這個月市場整體好嗎」——
// 分佈直方圖+中位數補上全局視角。零新資料(已申報列的 yoy 就地聚合)。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/widgets/revenue_yoy_histogram.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async => setupTestLocalization()); // caption 走 .tr()

  group('binCounts(9 桶:<-30,每 10pp,>+40)', () {
    test('🚨 邊界歸屬:下緣含、上緣不含;兩端開放桶', () {
      // 桶: (<-30) [-30,-20) [-20,-10) [-10,0) [0,10) [10,20) [20,30) [30,40) (>=40)
      final counts = RevenueYoyHistogram.binCounts([
        -31.0, // 桶0
        -30.0, // 桶1(下緣含)
        -0.1, //  桶3
        0.0, //   桶4(下緣含)
        9.9, //   桶4
        10.0, //  桶5
        39.9, //  桶7
        40.0, //  桶8
        1096390.6, // 桶8(怪物也有位置)
      ]);
      expect(counts, [1, 1, 0, 1, 2, 1, 0, 1, 2]);
      expect(counts.length, RevenueYoyHistogram.binCount);
    });

    test('空清單 → 全零', () {
      expect(
        RevenueYoyHistogram.binCounts(const []),
        List.filled(RevenueYoyHistogram.binCount, 0),
      );
    });
  });

  group('median', () {
    test('奇偶與空', () {
      expect(RevenueYoyHistogram.median([3.0, 1.0, 2.0]), 2.0);
      expect(RevenueYoyHistogram.median([1.0, 2.0, 3.0, 4.0]), 2.5);
      expect(RevenueYoyHistogram.median(const []), isNull);
    });
  });

  testWidgets('🚨 渲染:9 根柱高與桶數成比例,標題帶中位數', (tester) async {
    // 10 個值:桶4(0~10)有 6 個、桶8 有 4 個 → 高度比 1.0 : 0.667
    final values = [
      for (var i = 0; i < 6; i++) 5.0,
      for (var i = 0; i < 4; i++) 50.0,
    ];
    await tester.pumpWidget(buildTestApp(RevenueYoyHistogram(values: values)));

    final factors = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((b) => b.heightFactor)
        .whereType<double>()
        .toList();
    expect(factors, hasLength(RevenueYoyHistogram.binCount));
    expect(factors.reduce((a, b) => a > b ? a : b), closeTo(1.0, 1e-9));
    expect(
      factors.where((f) => (f - 4 / 6).abs() < 1e-9),
      isNotEmpty,
      reason: '次高桶=最高桶的 2/3',
    );
    // 測試環境渲染原始 key,中位數經 namedArgs 不替換——驗 key 存在即可
    expect(find.text('revenueOverview.histogramCaption'), findsOneWidget);
  });

  testWidgets('無資料 → 整段不渲染(shrink)', (tester) async {
    await tester.pumpWidget(
      buildTestApp(const RevenueYoyHistogram(values: [])),
    );
    expect(find.byType(FractionallySizedBox), findsNothing);
  });
}

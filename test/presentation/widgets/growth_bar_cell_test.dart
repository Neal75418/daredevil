// GrowthBarCell(2026-08-13):數字牆變形狀的核心元件
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/widgets/growth_bar_cell.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  test('🚨 fractionOf:以可見最大值為滿條,超出夾住,null/無資料為 0', () {
    expect(GrowthBarCell.fractionOf(50, 100), 0.5);
    expect(GrowthBarCell.fractionOf(-50, 100), 0.5, reason: '負值取絕對值');
    expect(GrowthBarCell.fractionOf(150, 100), 1.0, reason: '夾住');
    expect(GrowthBarCell.fractionOf(null, 100), 0);
    expect(GrowthBarCell.fractionOf(50, 0), 0, reason: '全清單無資料不畫條');
  });

  testWidgets('比例反映在 FractionallySizedBox;null 無條', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        const Row(
          children: [
            GrowthBarCell(width: 80, text: '+50.0%', value: 50, maxAbs: 100),
            GrowthBarCell(width: 80, text: '--', value: null, maxAbs: 100),
          ],
        ),
      ),
    );
    final boxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    expect(boxes, hasLength(1), reason: 'null 欄不畫條');
    expect(boxes.single.widthFactor, closeTo(0.5, 1e-9));
  });

  testWidgets('🚨 極端字串(+1096390.6%)縮字不折行——單行高度', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        const Row(
          children: [
            GrowthBarCell(
              width: 62,
              text: '+1096390.6%',
              value: 1096390.6,
              maxAbs: 100,
            ),
            GrowthBarCell(width: 62, text: '+9.9%', value: 9.9, maxAbs: 100),
          ],
        ),
      ),
    );
    final sizes = tester
        .widgetList(find.byType(GrowthBarCell))
        .map((w) => tester.getSize(find.byWidget(w)))
        .toList();
    expect(
      sizes[0].height,
      closeTo(sizes[1].height, 0.5),
      reason: '折行會讓列高跳動;FittedBox 縮字維持單行(clip 會吃掉負號,禁用)',
    );
  });
}

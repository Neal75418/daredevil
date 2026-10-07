import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

/// 閃色層實際畫出的底色（沒閃時為 null）
Color? priceFlashTint(WidgetTester tester) {
  final decoration =
      tester.widget<DecoratedBox>(find.byKey(PriceFlash.tintKey)).decoration
          as BoxDecoration;
  return decoration.color;
}

/// 閃色層裡價格數字實際的顏色：閃色時被換成 [PriceColors.onFlash]
Color priceFlashTextColor(WidgetTester tester) {
  // 多個 PriceFlash 裡恰好一個在閃時，下面的 ColorFiltered 會算到別格頭上
  expect(find.byType(PriceFlash), findsOneWidget, reason: '前提：畫面上只有一個價格閃色');
  final filters = tester.widgetList<ColorFiltered>(
    find.descendant(
      of: find.byType(PriceFlash),
      matching: find.byType(ColorFiltered),
    ),
  );
  if (filters.isNotEmpty) {
    expect(
      filters.single.colorFilter,
      const ColorFilter.mode(PriceColors.onFlash, BlendMode.srcIn),
    );
    return PriceColors.onFlash;
  }
  return tester
      .widget<RichText>(
        find.descendant(
          of: find.byType(PriceFlash),
          matching: find.byType(RichText),
        ),
      )
      .text
      .style!
      .color!;
}

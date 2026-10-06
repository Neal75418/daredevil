import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

import '../../helpers/widget_test_helpers.dart';

/// 價格閃色(2026-10-06,spec §6)。
void main() {
  Widget host(
    LiveQuoteFlash? flash, {
    bool enabled = true,
    bool disableAnimations = false,
  }) => buildTestApp(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: PriceFlash(
          flash: flash,
          enabled: enabled,
          child: const Text('100.00'),
        ),
      ),
    ),
  );

  Color? tint(WidgetTester tester) =>
      (tester.widget<DecoratedBox>(find.byKey(PriceFlash.tintKey)).decoration
              as BoxDecoration)
          .color;

  testWidgets('🚨 新的閃色事件 → 底色閃一下,淡出後消失', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    expect(tint(tester), isNull, reason: '第一次建立不補閃');

    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    final peak = tint(tester)!;
    expect(peak.a, closeTo(LiveQuoteParams.flashTintAlpha, 0.02));
    expect(
      peak.withValues(alpha: 1),
      PriceColors.forChange(1, Brightness.light),
    );

    await tester.pump(LiveQuoteParams.flashFade);
    expect(tint(tester), isNull);
  });

  testWidgets('跌 → 跌色', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: false)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: false)));
    await tester.pump();
    expect(
      tint(tester)!.withValues(alpha: 1),
      PriceColors.forChange(-1, Brightness.light),
    );
  });

  testWidgets('🚨 第一次建立就帶著事件(清單捲回來重建卡片)→ 不補閃,之後同一事件再重建也不閃', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 5, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
    // 下一輪別檔有報價、整個清單重建,這一檔的事件沒變
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 5, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('🚨 同一個事件再重建 → 不再閃', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump(LiveQuoteParams.flashFade);
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('設定頁「價格閃色」關閉 → 不閃', (tester) async {
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 1, up: true), enabled: false),
    );
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 2, up: true), enabled: false),
    );
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('系統要求停用動畫(disableAnimations)→ 不閃', (tester) async {
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 1, up: true), disableAnimations: true),
    );
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 2, up: true), disableAnimations: true),
    );
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('🚨 iOS「減少動態效果」(reduceMotion)→ 不閃', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
  });
}

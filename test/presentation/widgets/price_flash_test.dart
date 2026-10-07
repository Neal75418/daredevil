import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

import '../../helpers/price_flash_helpers.dart';
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

  Color? tint(WidgetTester tester) => priceFlashTint(tester);

  testWidgets('🚨 新的閃色事件 → 價格那一格閃實心色,時間到消失', (tester) async {
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

    await tester.pump(LiveQuoteParams.flashDuration);
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
    await tester.pump(LiveQuoteParams.flashDuration);
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

  testWidgets('🚨 整段維持實心、時間到一次收掉（不留淡出）', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    await tester.pump(
      LiveQuoteParams.flashDuration - const Duration(milliseconds: 1),
    );
    expect(tint(tester)!.a, LiveQuoteParams.flashTintAlpha);

    await tester.pump(const Duration(milliseconds: 1));
    expect(tint(tester), isNull);
  });

  testWidgets('🚨 色塊左右比數字寬一圈、上下不超出數字那一行（不壓到上下相鄰的元件），數字不移動', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    final text = tester.getRect(find.text('100.00'));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();

    expect(
      tester.getRect(find.byKey(PriceFlash.tintKey)),
      Rect.fromLTRB(
        text.left - LiveQuoteParams.flashChipPadH,
        text.top,
        text.right + LiveQuoteParams.flashChipPadH,
        text.bottom,
      ),
    );
    expect(tester.getRect(find.text('100.00')), text);
  });

  testWidgets('🚨 外層給緊約束（固定寬、數字靠右）→ 數字照樣吃滿寬度，色塊仍是數字左右各寬一圈', (tester) async {
    Widget tight(int id) => buildTestApp(
      Center(
        child: SizedBox(
          width: 120,
          child: PriceFlash(
            flash: LiveQuoteFlash(id: id, up: true),
            enabled: true,
            child: const Text('100.00', textAlign: TextAlign.end),
          ),
        ),
      ),
    );
    await tester.pumpWidget(tight(1));
    await tester.pumpWidget(tight(2));
    await tester.pump();

    final text = tester.getRect(find.text('100.00'));
    expect(text.width, 120);
    expect(
      tester.getRect(find.byKey(PriceFlash.tintKey)),
      Rect.fromLTRB(
        text.left - LiveQuoteParams.flashChipPadH,
        text.top,
        text.right + LiveQuoteParams.flashChipPadH,
        text.bottom,
      ),
    );
  });

  testWidgets('🚨 閃色時數字改成深色（實心底上看得清楚），結束後恢復', (tester) async {
    Iterable<ColorFiltered> filters() =>
        tester.widgetList<ColorFiltered>(find.byType(ColorFiltered));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    expect(filters(), isEmpty);

    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    expect(
      filters().single.colorFilter,
      const ColorFilter.mode(PriceColors.onFlash, BlendMode.srcIn),
    );

    await tester.pump(LiveQuoteParams.flashDuration);
    expect(filters(), isEmpty);
  });

  for (final brightness in Brightness.values) {
    for (final up in [true, false]) {
      test('🚨 閃色數字對實心底色 ≥ 4.5：$brightness ${up ? '漲' : '跌'}', () {
        expect(
          ColorContrast.ratio(
            PriceColors.onFlash,
            PriceColors.forChange(up ? 1 : -1, brightness),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  }

  for (final brightness in Brightness.values) {
    for (final up in [true, false]) {
      testWidgets(
        '🚨 整段閃色每 10ms 取樣，數字對實際底色都 ≥ 4.5：$brightness ${up ? '漲' : '跌'}',
        (tester) async {
          Widget app(int id) => buildTestApp(
            Builder(
              builder: (context) => PriceFlash(
                flash: LiveQuoteFlash(id: id, up: up),
                enabled: true,
                child: Text(
                  '100.00',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            brightness: brightness,
          );
          await tester.pumpWidget(app(1));
          await tester.pumpWidget(app(2));
          await tester.pump();
          final surface = Theme.of(
            tester.element(find.text('100.00')),
          ).scaffoldBackgroundColor;
          expect(priceFlashTint(tester), isNotNull, reason: '前提：已在閃');

          var flashingSamples = 0;
          const step = Duration(milliseconds: 10);
          for (
            var t = Duration.zero;
            t <= LiveQuoteParams.flashDuration;
            t += step
          ) {
            final tint = priceFlashTint(tester);
            if (tint != null) flashingSamples++;
            final bg = tint == null
                ? surface
                : ColorContrast.compositeOver(
                    tint.withValues(alpha: 1),
                    surface,
                    tint.a,
                  );
            expect(
              ColorContrast.ratio(priceFlashTextColor(tester), bg),
              greaterThanOrEqualTo(4.5),
              reason: '閃色開始後 ${t.inMilliseconds}ms',
            );
            await tester.pump(step);
          }
          expect(
            flashingSamples,
            LiveQuoteParams.flashDuration.inMilliseconds ~/ step.inMilliseconds,
            reason: '0～590ms 在閃、600ms 已收掉',
          );
        },
      );
    }
  }
}

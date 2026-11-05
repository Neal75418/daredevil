import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';

/// 熱力圖色表（各色由 PriceColors 漲跌色以 alpha 0.40／0.54／0.66／0.78／0.89／
/// 1.0 疊在頁面底色上產生）。這裡逐值釘住，改色時下面的條件一定要重跑。
const _table = {
  Brightness.dark: (
    bg: 0xFF18181B,
    up: [
      0xFF742B33,
      0xFF95313B,
      0xFFB03743,
      0xFFCC3D4A,
      0xFFE64250,
      0xFFFF4757,
    ],
    down: [
      0xFF21643E,
      0xFF247E4B,
      0xFF279555,
      0xFF29AB60,
      0xFF2CC069,
      0xFF2ED573,
    ],
    flat: 0xFF303030,
    hollowBorder: 0xFF6B6B6B,
    hollowText: 0xFFA1A1A1,
    headerText: 0xFFF4F4F5,
  ),
  Brightness.light: (
    bg: 0xFFFFFFFF,
    up: [
      0xFFFFB5BC,
      0xFFFF9CA4,
      0xFFFF8690,
      0xFFFF6F7C,
      0xFFFF5B69,
      0xFFFF4757,
    ],
    down: [
      0xFFA4D8B9,
      0xFF84CBA0,
      0xFF69BF8B,
      0xFF4DB376,
      0xFF34A963,
      0xFF1B9E50,
    ],
    flat: 0xFFE4E4E4,
    hollowBorder: 0xFF8C8C8C,
    hollowText: 0xFF717171,
    headerText: 0xFF18181B,
  ),
};

List<Color> _steps(bool up, Brightness b) => [
  for (var step = 1; step <= 6; step++)
    HeatmapColors.fill(step: step, up: up, brightness: b),
];

void main() {
  for (final b in Brightness.values) {
    group('HeatmapColors（${b.name}）', () {
      final bg = HeatmapColors.pageBackground(b);

      test('色值與計畫色表一致', () {
        final t = _table[b]!;
        expect(bg, Color(t.bg));
        expect(_steps(true, b), [for (final v in t.up) Color(v)]);
        expect(_steps(false, b), [for (final v in t.down) Color(v)]);
        expect(HeatmapColors.flat(b), Color(t.flat));
        expect(HeatmapColors.hollowBorder(b), Color(t.hollowBorder));
        expect(HeatmapColors.hollowText(b), Color(t.hollowText));
        expect(HeatmapColors.headerText(b), Color(t.headerText));
        expect(HeatmapColors.mineOuter, const Color(0xFF000000));
        expect(HeatmapColors.mineInner, const Color(0xFFFFFFFF));
        // 文字對比與自選框兩道守門逐一檢查 allFills：內容錯了就會漏查
        expect(HeatmapColors.allFills(b), [
          for (final v in [...t.up, ...t.down, t.flat]) Color(v),
        ]);
      });

      test('頁面底色＝主題的 scaffold 底色（格子間隔露出的就是它）', () {
        final theme = b == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;
        expect(bg, theme.scaffoldBackgroundColor);
      });

      test('textOn 取純黑、純白中對比較高者（整條灰階）', () {
        for (var v = 0; v <= 255; v++) {
          final c = Color.fromARGB(255, v, v, v);
          final picked = HeatmapColors.textOn(c);
          final other = picked == const Color(0xFF000000)
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF000000);
          expect(
            ColorContrast.ratio(picked, c),
            greaterThanOrEqualTo(ColorContrast.ratio(other, c)),
            reason: '灰階 $v',
          );
        }
      });

      test('每一階文字（純黑或純白）對比 ≥ 4.5', () {
        for (final c in HeatmapColors.allFills(b)) {
          final text = HeatmapColors.textOn(c);
          expect(
            text == const Color(0xFF000000) || text == const Color(0xFFFFFFFF),
            isTrue,
          );
          expect(
            ColorContrast.ratio(text, c),
            greaterThanOrEqualTo(4.5),
            reason: '${c.toARGB32().toRadixString(16)} 上的文字',
          );
        }
      });

      test('每一階對頁面底色的對比不低於前一階', () {
        for (final up in [true, false]) {
          final ratios = [
            for (final c in _steps(up, b)) ColorContrast.ratio(c, bg),
          ];
          for (var i = 1; i < ratios.length; i++) {
            expect(
              ratios[i],
              greaterThanOrEqualTo(ratios[i - 1]),
              reason: '${up ? '漲' : '跌'}第 ${i + 1} 階對底色 $ratios',
            );
          }
        }
      });

      test('平盤、第 1 階對頁面底色 ≥ 1.25；平盤對兩方向第 1 階 ≥ 1.15', () {
        final flat = HeatmapColors.flat(b);
        final up1 = HeatmapColors.fill(step: 1, up: true, brightness: b);
        final down1 = HeatmapColors.fill(step: 1, up: false, brightness: b);
        for (final c in [flat, up1, down1]) {
          expect(ColorContrast.ratio(c, bg), greaterThanOrEqualTo(1.25));
        }
        expect(ColorContrast.ratio(flat, up1), greaterThanOrEqualTo(1.15));
        expect(ColorContrast.ratio(flat, down1), greaterThanOrEqualTo(1.15));
      });

      test('空心邊框對頁面底色 ≥ 3.0；空心文字、產業標題文字對頁面底色 ≥ 4.5', () {
        expect(
          ColorContrast.ratio(HeatmapColors.hollowBorder(b), bg),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          ColorContrast.ratio(HeatmapColors.hollowText(b), bg),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ColorContrast.ratio(HeatmapColors.headerText(b), bg),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('自選框：對每一階填色、平盤、頁面底色，外框或內框至少一條 ≥ 3.0', () {
        for (final c in [...HeatmapColors.allFills(b), bg]) {
          final best = [
            ColorContrast.ratio(HeatmapColors.mineOuter, c),
            ColorContrast.ratio(HeatmapColors.mineInner, c),
          ].reduce((a, x) => a > x ? a : x);
          expect(
            best,
            greaterThanOrEqualTo(3.0),
            reason: c.toARGB32().toRadixString(16),
          );
        }
      });

      test('漲各階色相在紅區、跌各階在綠區；平盤、空心、自選框為灰階', () {
        for (final c in _steps(true, b)) {
          final h = ColorContrast.hue(c);
          expect(h >= 345 || (h >= 0 && h <= 15), isTrue, reason: '漲色相 $h');
        }
        for (final c in _steps(false, b)) {
          final h = ColorContrast.hue(c);
          expect(h >= 88 && h <= 175, isTrue, reason: '跌色相 $h');
        }
        for (final c in [
          HeatmapColors.flat(b),
          HeatmapColors.hollowBorder(b),
          HeatmapColors.hollowText(b),
          HeatmapColors.mineOuter,
          HeatmapColors.mineInner,
        ]) {
          expect(ColorContrast.hue(c), lessThan(0), reason: '應為灰階');
        }
      });
    });
  }
}

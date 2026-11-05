import 'dart:ui';

import 'package:daredevil/core/theme/semantic_colors.dart';

/// 大盤熱力圖的顏色。
///
/// 漲跌各 6 階：[PriceColors] 的漲跌色（淺色主題的跌用
/// [PriceColors.downOnLight]）以 alpha 0.40／0.54／0.66／0.78／0.89／1.0 疊在
/// 頁面底色上，幅度越大對底色越顯眼。文字一律純黑或純白（[textOn]）。
/// 對比、色相與數值由 `test/core/theme/heatmap_colors_test.dart` 釘住；改色時
/// 那裡的條件都要成立。
abstract final class HeatmapColors {
  static const _upDark = [
    Color(0xFF742B33),
    Color(0xFF95313B),
    Color(0xFFB03743),
    Color(0xFFCC3D4A),
    Color(0xFFE64250),
    Color(0xFFFF4757),
  ];
  static const _downDark = [
    Color(0xFF21643E),
    Color(0xFF247E4B),
    Color(0xFF279555),
    Color(0xFF29AB60),
    Color(0xFF2CC069),
    Color(0xFF2ED573),
  ];
  static const _upLight = [
    Color(0xFFFFB5BC),
    Color(0xFFFF9CA4),
    Color(0xFFFF8690),
    Color(0xFFFF6F7C),
    Color(0xFFFF5B69),
    Color(0xFFFF4757),
  ];
  static const _downLight = [
    Color(0xFFA4D8B9),
    Color(0xFF84CBA0),
    Color(0xFF69BF8B),
    Color(0xFF4DB376),
    Color(0xFF34A963),
    Color(0xFF1B9E50),
  ];

  static bool _isDark(Brightness b) => b == Brightness.dark;

  /// 頁面底色（＝主題的 scaffold 底色；格子間隔露出的就是它）
  static Color pageBackground(Brightness b) => _isDark(b)
      ? SemanticColors.darkBackground
      : SemanticColors.lightBackground;

  /// 漲或跌第 [step] 階（1..6）的填色
  static Color fill({
    required int step,
    required bool up,
    required Brightness brightness,
  }) {
    assert(step >= 1 && step <= 6, 'step 應在 1..6，得到 $step');
    final dark = _isDark(brightness);
    final table = up
        ? (dark ? _upDark : _upLight)
        : (dark ? _downDark : _downLight);
    return table[step - 1];
  }

  /// 平盤（剛好 0%）：灰階，亮度落在頁面底色與第 1 階之間
  static Color flat(Brightness b) =>
      _isDark(b) ? const Color(0xFF303030) : const Color(0xFFE4E4E4);

  /// 填色上的文字：純黑或純白取對比較高者（相對亮度約 0.179 處兩者相等，
  /// 任何填色都至少 4.58）
  static Color textOn(Color fill) => fill.computeLuminance() > 0.179
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  /// 空心格子（沒有可用的今日漲跌）的細邊框
  static Color hollowBorder(Brightness b) =>
      _isDark(b) ? const Color(0xFF6B6B6B) : const Color(0xFF8C8C8C);

  /// 空心格子的變淡文字（畫在頁面底色上）
  static Color hollowText(Brightness b) =>
      _isDark(b) ? const Color(0xFFA1A1A1) : const Color(0xFF717171);

  /// 產業標題列的文字（標題列底色＝頁面底色）
  static Color headerText(Brightness b) =>
      _isDark(b) ? SemanticColors.darkTextPrimary : const Color(0xFF18181B);

  /// 自選或持股的雙線框：外深內淺各 1px，任何填色上至少一條看得見
  static const Color mineOuter = Color(0xFF000000);
  static const Color mineInner = Color(0xFFFFFFFF);

  /// 12 階填色加平盤（守門測試用）
  static List<Color> allFills(Brightness b) => [
    for (final up in [true, false])
      for (var step = 1; step <= 6; step++)
        fill(step: step, up: up, brightness: b),
    flat(b),
  ];
}

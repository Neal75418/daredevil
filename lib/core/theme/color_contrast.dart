import 'dart:math' as math;

import 'package:flutter/painting.dart'; // Color, HSLColor

/// WCAG 2.1 對比度與色相計算。
///
/// **消費者現況(2026-08-15 審計)**:執行期生產碼不 import 本檔——它是
/// 色彩守門測試的公式庫(semantic_colors_test 等 10+ 檔),留在 lib/ 是
/// 為了與色彩宣告同住、且未來生產碼要算對比度時直接可用。守門測試與
/// 未來的生產消費者共用同一份公式,避免「測試綠但實際不合格」的假安全。
abstract final class ColorContrast {
  /// sRGB 分量線性化（WCAG 2.1 定義）。
  static double _linearize(double channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  /// 相對亮度，範圍 0（純黑）至 1（純白）。
  ///
  /// Flutter 的 `Color.r/g/b` 已是 0.0-1.0 的 double，直接餵入線性化即可，
  /// 不需經過 0-255 整數轉換（多一次量化只會引入誤差）。
  static double relativeLuminance(Color color) {
    return 0.2126 * _linearize(color.r) +
        0.7152 * _linearize(color.g) +
        0.0722 * _linearize(color.b);
  }

  /// 兩色對比度，範圍 1:1 至 21:1。與參數順序無關。
  static double ratio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 色相角度（0-360）。無彩度（灰階）回傳 -1。
  static double hue(Color color) {
    final h = HSLColor.fromColor(color);
    return h.saturation == 0 ? -1.0 : h.hue;
  }

  /// 前景色以指定 alpha 疊加在背景色之上的合成色（straight alpha over 合成）。
  ///
  /// 用於文字底色是半透明疊色、而非純色平面背景的情境——例如裝飾用底色
  /// 以 `withValues(alpha: ...)` 疊加在卡片背景上時，文字實際承載的對比
  /// 對象是「合成後」的顏色，不是卡片背景本身。逐通道套用
  /// `result = alpha * foreground + (1 - alpha) * background`，
  /// 與渲染管線的標準 over 合成一致（假設背景不透明）。
  ///
  /// [foreground] 必須是完全不透明色（`foreground.a == 1.0`）——疊加程度一律
  /// 由 [alpha] 參數指定。若把已經帶 alpha 的 `Color`（例如
  /// `decoration.color` 本身）直接傳入，其 alpha 會被忽略而非自動套用，
  /// 是常見誤用，故以 assert 攔截而非靜默算出錯誤結果。
  static Color compositeOver(Color foreground, Color background, double alpha) {
    assert(
      foreground.a == 1.0,
      'compositeOver 的 foreground 必須不透明；欲混合的透明度請透過 alpha '
      '參數指定，foreground 自帶的 alpha 不會被套用（得到 ${foreground.a}）。',
    );
    assert(
      alpha >= 0.0 && alpha <= 1.0,
      'compositeOver 的 alpha 必須介於 0.0-1.0（得到 $alpha）。',
    );
    return Color.from(
      alpha: 1.0,
      red: alpha * foreground.r + (1 - alpha) * background.r,
      green: alpha * foreground.g + (1 - alpha) * background.g,
      blue: alpha * foreground.b + (1 - alpha) * background.b,
    );
  }
}

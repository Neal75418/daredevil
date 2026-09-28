import 'package:intl/intl.dart';

/// 統一數字格式化工具（純 Dart）
///
/// 提供千分位、正負號、貨幣等格式化方法。**必須維持純 Dart**（只 import
/// intl，不可 easy_localization/flutter）：rule_accuracy_service 等
/// domain 消費者在 tool/daily_update.dart 的 launchd 鏈上，混入 dart:ui
/// 依賴會讓自動更新編譯失敗且靜默斷更（2026-07-18 事故，斷 13 天）。
/// 依語系分級的 [LocalizedNumberFormat.compact]（吃 dart:ui `Locale`）已拆至
/// 另一檔。守門測試：test/tool/tool_chain_pure_dart_test.dart。
class AppNumberFormat {
  AppNumberFormat._();

  static final _intFormat = NumberFormat('#,##0');
  static final _decFormat = NumberFormat('#,##0.0');
  static final _dec2Format = NumberFormat('#,##0.00');

  /// 整數千分位格式（如 1,234,567）
  static String integer(double value) => _intFormat.format(value);

  /// 帶正負號的千分位整數（如 +1,234 / -567）
  static String signedInteger(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${_intFormat.format(value)}';
  }

  /// NT$ 貨幣格式（如 NT$1,234 / NT$123.45）
  static String currency(double value, {int decimals = 0}) {
    final formatted = switch (decimals) {
      0 => _intFormat.format(value),
      1 => _decFormat.format(value),
      _ => _dec2Format.format(value),
    };
    return 'NT\$$formatted';
  }

  /// 帶正負號的 NT$ 貨幣格式（如 +NT$1,234 / -NT$567）
  static String signedCurrency(double value, {int decimals = 0}) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${currency(value, decimals: decimals)}';
  }

  /// 依顯示精度捨入，供「文字」與「配色/方向」共用同一個值。
  ///
  /// 例：`roundForDisplay(-0.004, 2) == 0`——顯示為 0.00% 時，配色與箭頭
  /// 也應據此判為中性（不著漲跌色、不指方向），避免文字與顏色互相矛盾。
  static double roundForDisplay(double value, int decimals) =>
      double.parse(value.toStringAsFixed(decimals));

  /// 帶正負號的定點小數：**先依 [decimals] 捨入再判正負**。
  ///
  /// 平盤（或微負值捨入後歸零）一律回傳正零（如 `0.00`），
  /// 不帶 `+`、也不會出現 `-0.00` 負零。
  static String signedFixed(double value, {int decimals = 2}) {
    final rounded = roundForDisplay(value, decimals);
    if (rounded == 0) return 0.0.toStringAsFixed(decimals);
    return '${rounded > 0 ? '+' : ''}${rounded.toStringAsFixed(decimals)}';
  }

  /// 帶正負號的百分比：**先捨入再判正負**（如 +1.67% / 0.00% / -2.30%）。
  ///
  /// 平盤與微負值捨入後歸零時顯示 `0.00%`（不帶 `+`、非 `-0.00%`）。
  static String signedPercent(double value, {int decimals = 2}) =>
      '${signedFixed(value, decimals: decimals)}%';
}

import 'dart:ui';

import 'package:intl/intl.dart';

import 'package:daredevil/core/utils/number_formatter.dart';

/// 依語系分級的數字格式化——**presentation 專用**。
///
/// 與 [AppNumberFormat] 拆開的原因:這裡的 API 吃 dart:ui 的 `Locale`,
/// 而 AppNumberFormat 有 domain 消費者位於 tool/daily_update.dart 的
/// launchd 純 Dart 鏈上——2026-07-18 兩者同檔(當時是 `.tr()` 的
/// easy_localization 依賴)時,自動更新編譯失敗靜默斷了 13 天。守門:
/// test/tool/tool_chain_pure_dart_test.dart。
class LocalizedNumberFormat {
  LocalizedNumberFormat._();

  /// 依 [locale] 的進位制縮寫大數值，固定一位小數：中文 萬/億/兆
  /// （1e4/1e8/1e12）、英文 K/M/B/T（1e3/1e6/1e9/1e12）。
  ///
  /// 分級倍數與單位字都取自 CLDR（intl `NumberFormat.compact`），兩者不會
  /// 對不上——不可改回「中文倍數＋翻譯單位字」，英文會差 10 倍。未達最小
  /// 單位時退回千分位整數。呼叫端傳 `Localizations.localeOf(context)`。
  static String compact(double value, Locale locale) {
    // intl compact 對 NaN／Infinity 會拋例外
    if (!value.isFinite) return '--';
    final formatted =
        (NumberFormat.compact(locale: locale.toString())
              ..significantDigitsInUse = false
              ..minimumFractionDigits = 1
              ..maximumFractionDigits = 1)
            .format(value);
    // 沒有單位字＝未達該語系最小單位，intl 會輸出 "9999.0"，改用整數
    if (!_unitLetter.hasMatch(formatted)) {
      return AppNumberFormat.integer(value);
    }
    return formatted;
  }

  static final _unitLetter = RegExp(r'\p{L}', unicode: true);

  /// [locale] 是否採中文萬進位（萬/億）。畫面有中文專屬格式（例如固定以
  /// 「億」顯示、「千萬」一級）時用它分流，其餘語系走 [compact]。
  static bool usesChineseUnits(Locale locale) => locale.languageCode == 'zh';

  /// 以千元儲存的財報金額（月營收、季報淨利、產業 EPS 淨利等）轉成元，再交給
  /// [compact] 分級顯示。
  static String compactFromThousands(double thousands, Locale locale) =>
      compact(thousands * 1000, locale);
}

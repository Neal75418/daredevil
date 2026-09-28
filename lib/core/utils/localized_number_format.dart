import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/utils/number_formatter.dart';

/// 需要 i18n(`.tr()`)的數字格式化——**presentation 專用**。
///
/// 與 [AppNumberFormat] 拆開的原因:`.tr()` 來自 easy_localization
/// (依賴 dart:ui),而 AppNumberFormat 有 domain 消費者位於
/// tool/daily_update.dart 的 launchd 純 Dart 鏈上——2026-07-18 兩者同檔
/// 時,自動更新編譯失敗靜默斷了 13 天。守門:
/// test/tool/daily_update_pure_dart_test.dart。
class LocalizedNumberFormat {
  LocalizedNumberFormat._();

  /// 自動選擇本地化單位：億/B、萬/K、千分位
  ///
  /// 用於成交量、金額等大數值的友善顯示。
  static String compact(double value) {
    if (value.abs() >= 1e8) {
      return '${(value / 1e8).toStringAsFixed(1)}${'unit.billion'.tr()}';
    }
    if (value.abs() >= 1e4) {
      return '${(value / 1e4).toStringAsFixed(1)}${'unit.tenThousand'.tr()}';
    }
    return AppNumberFormat.integer(value);
  }

  /// 以千元儲存的財報金額（月營收、季報淨利、產業 EPS 淨利等）轉成元，再交給
  /// [compact] 分級顯示。
  static String compactFromThousands(double thousands) =>
      compact(thousands * 1000);
}

import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert/alert_distance.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';

/// 價位提醒的距離文字(2026-10-06,路線圖第 2 項)。只是放在旁邊的資訊:
/// 中性灰字、不閃色,不改觸發邏輯。
abstract final class AlertDistanceText {
  /// 快捷鈕用:「-2.1%」。現價已越過目標(按鈕另標「已成立」)或沒有現價 →
  /// null
  static String? percent({
    required bool upward,
    required double target,
    required double? price,
  }) {
    final p = price;
    if (p == null) return null;
    if (AlertDistance.isReached(upward: upward, target: target, price: p)) {
      return null;
    }
    final pct = AlertDistance.percent(target: target, price: p);
    return pct == null ? null : AppNumberFormat.signedPercent(pct, decimals: 1);
  }

  /// 已掛提醒用:「距現價 -2.1%」或「已達到」。只顯示在啟用中、還沒觸發的
  /// 價位型提醒(突破／跌破);漲跌幅、量、RSI 等不是價位,不顯示。沒有現價
  /// 回 null
  static String? forAlert(PriceAlertEntry alert, double? price) {
    final type = AlertType.tryFromValue(alert.alertType);
    if (type != AlertType.above && type != AlertType.below) return null;
    if (!alert.isActive || alert.triggeredAt != null) return null;
    final p = price;
    if (p == null) return null;
    final upward = type == AlertType.above;
    if (AlertDistance.isReached(
      upward: upward,
      target: alert.targetValue,
      price: p,
    )) {
      return 'alert.reached'.tr();
    }
    final text = percent(upward: upward, target: alert.targetValue, price: p);
    return text == null
        ? null
        : 'alert.distanceFromPrice'.tr(namedArgs: {'percent': text});
  }
}

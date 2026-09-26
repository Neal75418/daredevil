import 'package:daredevil/core/constants/data_freshness.dart';

/// 當沖比例（%）＝當沖成交股數 ÷ 當日成交量 × 100，夾在
/// `[0, DataFreshness.dayTradingMaxValidRatio]`。
///
/// 分母缺失或 ≤ 0 時回 null，由呼叫端決定語意：每日寫入寫 0（沿用既有
/// 行為）、重算保留原值、回補工具跳過該列。三處共用此函式，避免公式分岐。
double? computeDayTradingRatio({
  required double? tradeVolume,
  required double? totalVolume,
}) {
  if (tradeVolume == null || totalVolume == null || totalVolume <= 0) {
    return null;
  }
  final ratio = tradeVolume / totalVolume * 100;
  return ratio.clamp(0.0, DataFreshness.dayTradingMaxValidRatio).toDouble();
}

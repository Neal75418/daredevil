import 'package:meta/meta.dart';

/// 大盤判定的讀數：評分日候選股的 [lookbackDays] 日報酬（見
/// `PriceCalculator.marketRegimeReading`）。回檔類規則依 [isUptrend] 開關，
/// 畫面依它說明回檔訊號為何暫停
@immutable
class MarketRegimeReading {
  const MarketRegimeReading({
    required this.eligibleCount,
    required this.upCount,
    required this.medianReturn,
    required this.isUptrend,
    required this.lookbackDays,
  });

  /// 有效股數（評分日有當日 K 棒、歷史夠長、價格可用的候選股）
  final int eligibleCount;

  /// 報酬大於 0 的檔數（比 [lookbackDays] 日前高）
  final int upCount;

  /// 報酬中位數（比例，0.05＝5%）
  final double medianReturn;

  /// 判定結果：中位數大於 0 為多頭
  final bool isUptrend;

  /// 計算時用的回看交易日數
  final int lookbackDays;

  /// 比 [lookbackDays] 日前高的比例（%），無條件捨去到整數
  int get upPercentFloor => upCount * 100 ~/ eligibleCount;

  @override
  bool operator ==(Object other) =>
      other is MarketRegimeReading &&
      other.eligibleCount == eligibleCount &&
      other.upCount == upCount &&
      other.medianReturn == medianReturn &&
      other.isUptrend == isUptrend &&
      other.lookbackDays == lookbackDays;

  @override
  int get hashCode => Object.hash(
    eligibleCount,
    upCount,
    medianReturn,
    isUptrend,
    lookbackDays,
  );
}

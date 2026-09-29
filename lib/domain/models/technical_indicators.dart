/// 規則評估用的技術指標
class TechnicalIndicators {
  const TechnicalIndicators({
    this.rsi,
    this.kdK,
    this.kdD,
    this.prevKdK,
    this.prevKdD,
    this.ma5,
    this.ma10,
    this.ma20,
    this.ma60,
    this.volumeMA20,
  });

  /// RSI 相對強弱指標
  final double? rsi;

  /// KD 指標 K 值（當日）
  final double? kdK;

  /// KD 指標 D 值（當日）
  final double? kdD;

  /// KD 指標 K 值（前一日，用於交叉判斷）
  final double? prevKdK;

  /// KD 指標 D 值（前一日，用於交叉判斷）
  final double? prevKdD;

  /// 5 日移動平均線
  final double? ma5;

  /// 10 日移動平均線
  final double? ma10;

  /// 20 日移動平均線
  final double? ma20;

  /// 60 日移動平均線
  final double? ma60;

  /// 今日之前 20 日的均量（不含今日，見 TechnicalIndicatorService.latestVolumeMA）
  final double? volumeMA20;
}

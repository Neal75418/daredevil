/// 台股盤中交易時段(盤中提醒與盤中即時報價共用的單一來源)
abstract final class MarketSession {
  /// 09:00 開盤(自午夜起算的分鐘數)
  static const int openMinutes = 9 * 60;

  /// 13:30 收盤(含尾盤集合競價)
  static const int closeMinutes = 13 * 60 + 30;
}

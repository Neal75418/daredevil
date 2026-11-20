/// 台股（上市、上櫃普通股）的升降單位與漲跌停價。
///
/// 漲停價＝平盤價 × 1.1 往下取到升降單位，跌停價＝平盤價 × 0.9 往上取到
/// 升降單位，升降單位看算出來的價格落在哪個區間。只用漲跌幅推算（±9.85%）
/// 會漏掉取整落差大的價位（例：平盤 134.5 的漲停價 147.5 只漲 9.665%）。
/// ETF 的升降單位不同，不適用。
abstract final class TwPriceTick {
  /// 價格區間上限（不含）與該區間的升降單位，單位是千分之一元
  static const List<({double upper, int tickMilli})> _bands = [
    (upper: 10, tickMilli: 10),
    (upper: 50, tickMilli: 50),
    (upper: 100, tickMilli: 100),
    (upper: 500, tickMilli: 500),
    (upper: 1000, tickMilli: 1000),
  ];

  /// 1000 元以上的升降單位（千分之一元）
  static const int _topTickMilli = 5000;

  static int _tickMilliFor(double price) {
    for (final band in _bands) {
      if (price < band.upper) return band.tickMilli;
    }
    return _topTickMilli;
  }

  /// [price] 所在區間的升降單位（元）
  static double tickFor(double price) => _tickMilliFor(price) / 1000;

  /// 以平盤價算漲停、跌停價。用千分之一元的整數運算，避免浮點誤差讓
  /// 取整差一個升降單位。
  static ({double up, double down}) limitPrices(double basePrice) {
    final baseMilli = (basePrice * 1000).round();
    // 漲停：平盤 × 11 ÷ 10，單位是萬分之一元，往下取到升降單位
    final upRaw = baseMilli * 11;
    final upTick = _tickMilliFor(upRaw / 10000);
    final up = upRaw ~/ (10 * upTick) * upTick;
    // 跌停：平盤 × 9 ÷ 10，往上取到升降單位
    final downRaw = baseMilli * 9;
    final downTick = _tickMilliFor(downRaw / 10000);
    final step = 10 * downTick;
    final down = (downRaw + step - 1) ~/ step * downTick;
    return (up: up / 1000, down: down / 1000);
  }
}

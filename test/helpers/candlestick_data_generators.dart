import 'package:daredevil/data/database/app_database.dart';

/// K 線型態測試資料產生器
///
/// 提供各種經典 K 線型態的建構方法，搭配 candlestick_rules_test 使用。

// ==========================================
// 單根 K 線
// ==========================================

/// 建立十字線（Doji）
///
/// 特徵：小實體、大振幅。body / range <= PatternParams.dojiBodyMaxRatio
DailyPriceEntry createDojiCandle({
  required DateTime date,
  required double price,
  double range = 10.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  // 開收幾乎相同，上下影線長
  return DailyPriceEntry(
    symbol: symbol,
    date: date,
    open: price + 0.1,
    high: price + range / 2,
    low: price - range / 2,
    close: price,
    volume: volume,
  );
}

/// 建立錘子線（Hammer）
///
/// 特徵：
/// - 下影線 >= body * 2
/// - 上影線 <= body * 0.5
/// - body >= range * 5%
DailyPriceEntry createHammerCandle({
  required DateTime date,
  double close = 100.0,
  double bodySize = 2.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  final open = close - bodySize; // 陽線
  final lowerShadow = bodySize * 2.5;
  final upperShadow = bodySize * 0.3;
  return DailyPriceEntry(
    symbol: symbol,
    date: date,
    open: open,
    high: close + upperShadow,
    low: open - lowerShadow,
    close: close,
    volume: volume,
  );
}

// ==========================================
// 雙根 K 線型態
// ==========================================

/// 建立多頭吞噬型態（Bullish Engulfing）
///
/// - prev: 陰線（close < open）
/// - today: 陽線完全包覆 prev 實體（today.open <= prev.close, today.close >= prev.open）
({DailyPriceEntry prev, DailyPriceEntry today}) createBullishEngulfingPair({
  required DateTime prevDate,
  required DateTime todayDate,
  double basePrice = 100.0,
  double volume = 2000,
  String symbol = 'TEST',
}) {
  final prev = DailyPriceEntry(
    symbol: symbol,
    date: prevDate,
    open: basePrice + 2.0,
    high: basePrice + 3.0,
    low: basePrice - 1.0,
    close: basePrice,
    volume: volume * 0.8,
  );
  final today = DailyPriceEntry(
    symbol: symbol,
    date: todayDate,
    open: basePrice - 0.5, // <= prev.close
    high: basePrice + 4.0,
    low: basePrice - 1.5,
    close: basePrice + 3.0, // >= prev.open
    volume: volume,
  );
  return (prev: prev, today: today);
}

/// 建立空頭吞噬型態（Bearish Engulfing）
({DailyPriceEntry prev, DailyPriceEntry today}) createBearishEngulfingPair({
  required DateTime prevDate,
  required DateTime todayDate,
  double basePrice = 100.0,
  double volume = 2000,
  String symbol = 'TEST',
}) {
  final prev = DailyPriceEntry(
    symbol: symbol,
    date: prevDate,
    open: basePrice - 2.0,
    high: basePrice + 1.0,
    low: basePrice - 3.0,
    close: basePrice,
    volume: volume * 0.8,
  );
  final today = DailyPriceEntry(
    symbol: symbol,
    date: todayDate,
    open: basePrice + 0.5, // >= prev.close
    high: basePrice + 1.5,
    low: basePrice - 4.0,
    close: basePrice - 3.0, // <= prev.open
    volume: volume,
  );
  return (prev: prev, today: today);
}

/// 建立跳空上漲型態（Gap Up）
///
/// today.low > prev.high
({DailyPriceEntry prev, DailyPriceEntry today}) createGapUpPair({
  required DateTime prevDate,
  required DateTime todayDate,
  double basePrice = 100.0,
  double gapSize = 3.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  final prev = DailyPriceEntry(
    symbol: symbol,
    date: prevDate,
    open: basePrice - 1.0,
    high: basePrice + 1.0,
    low: basePrice - 2.0,
    close: basePrice,
    volume: volume,
  );
  final todayLow = basePrice + 1.0 + gapSize; // > prev.high
  final today = DailyPriceEntry(
    symbol: symbol,
    date: todayDate,
    open: todayLow + 1.0,
    high: todayLow + 3.0,
    low: todayLow,
    close: todayLow + 2.0,
    volume: volume,
  );
  return (prev: prev, today: today);
}

/// 建立跳空下跌型態（Gap Down）
///
/// today.high < prev.low
({DailyPriceEntry prev, DailyPriceEntry today}) createGapDownPair({
  required DateTime prevDate,
  required DateTime todayDate,
  double basePrice = 100.0,
  double gapSize = 3.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  final prev = DailyPriceEntry(
    symbol: symbol,
    date: prevDate,
    open: basePrice + 1.0,
    high: basePrice + 2.0,
    low: basePrice - 1.0,
    close: basePrice,
    volume: volume,
  );
  final todayHigh = basePrice - 1.0 - gapSize; // < prev.low
  final today = DailyPriceEntry(
    symbol: symbol,
    date: todayDate,
    open: todayHigh - 1.0,
    high: todayHigh,
    low: todayHigh - 3.0,
    close: todayHigh - 2.0,
    volume: volume,
  );
  return (prev: prev, today: today);
}

// ==========================================
// 三根 K 線型態
// ==========================================

/// 建立晨星型態（Morning Star）
///
/// - C1: 長黑（陰線）
/// - C2: 小實體（星）
/// - C3: 長紅（陽線），收盤高於 C1 中點
List<DailyPriceEntry> createMorningStarPattern({
  required DateTime startDate,
  double basePrice = 100.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  final c1 = DailyPriceEntry(
    symbol: symbol,
    date: startDate,
    open: basePrice + 5.0,
    high: basePrice + 6.0,
    low: basePrice - 1.0,
    close: basePrice, // 長黑
    volume: volume,
  );
  final c2 = DailyPriceEntry(
    symbol: symbol,
    date: startDate.add(const Duration(days: 1)),
    open: basePrice - 2.0,
    high: basePrice - 1.0,
    low: basePrice - 3.0,
    close: basePrice - 2.2, // 小實體
    volume: volume * 0.5,
  );
  final c3 = DailyPriceEntry(
    symbol: symbol,
    date: startDate.add(const Duration(days: 2)),
    open: basePrice - 1.0,
    high: basePrice + 4.0,
    low: basePrice - 1.5,
    close: basePrice + 3.5, // 收盤 > C1 中點 (102.5)
    volume: volume * 1.5,
  );
  return [c1, c2, c3];
}

/// 建立暮星型態（Evening Star）
List<DailyPriceEntry> createEveningStarPattern({
  required DateTime startDate,
  double basePrice = 100.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  final c1 = DailyPriceEntry(
    symbol: symbol,
    date: startDate,
    open: basePrice - 5.0,
    high: basePrice + 1.0,
    low: basePrice - 6.0,
    close: basePrice, // 長紅
    volume: volume,
  );
  final c2 = DailyPriceEntry(
    symbol: symbol,
    date: startDate.add(const Duration(days: 1)),
    open: basePrice + 2.0,
    high: basePrice + 3.0,
    low: basePrice + 1.0,
    close: basePrice + 2.2, // 小實體
    volume: volume * 0.5,
  );
  final c3 = DailyPriceEntry(
    symbol: symbol,
    date: startDate.add(const Duration(days: 2)),
    open: basePrice + 1.0,
    high: basePrice + 1.5,
    low: basePrice - 4.0,
    close: basePrice - 3.5, // 收盤 < C1 中點 (97.5)
    volume: volume * 1.5,
  );
  return [c1, c2, c3];
}

/// 建立三白兵型態（Three White Soldiers）
///
/// 3 根連續陽線，收盤價遞增
List<DailyPriceEntry> createThreeWhiteSoldiersPattern({
  required DateTime startDate,
  double basePrice = 100.0,
  double increment = 3.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  return List.generate(3, (i) {
    final open = basePrice + (i * increment);
    final close = open + increment * 0.8;
    return DailyPriceEntry(
      symbol: symbol,
      date: startDate.add(Duration(days: i)),
      open: open,
      high: close + 0.5,
      low: open - 0.5,
      close: close,
      volume: volume,
    );
  });
}

/// 建立三黑鴉型態（Three Black Crows）
///
/// 3 根連續陰線，收盤價遞減
List<DailyPriceEntry> createThreeBlackCrowsPattern({
  required DateTime startDate,
  double basePrice = 110.0,
  double decrement = 3.0,
  double volume = 1000,
  String symbol = 'TEST',
}) {
  return List.generate(3, (i) {
    final open = basePrice - (i * decrement);
    final close = open - decrement * 0.8;
    return DailyPriceEntry(
      symbol: symbol,
      date: startDate.add(Duration(days: i)),
      open: open,
      high: open + 0.5,
      low: close - 0.5,
      close: close,
      volume: volume,
    );
  });
}

// ==========================================
// 基底價格附加型態
// ==========================================

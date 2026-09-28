/// K 線型態參數
abstract final class PatternParams {
  /// 錘子線實體最小比例（5%）
  ///
  /// 實體須至少占振幅的 5%，過小視為十字線。
  static const double hammerBodyMinRatio = 0.05;

  /// 錘子線下影線倍數（2 倍實體）
  ///
  /// 下影線須至少為實體的 2 倍。
  static const double hammerLowerShadowMultiplier = 2.0;

  /// 錘子線上影線最大倍數（0.5 倍實體）
  ///
  /// 上影線不可超過實體的 0.5 倍。
  static const double hammerUpperShadowMaxRatio = 0.5;

  /// 錘子線在支撐-壓力區間中的最大位置（0.5 = 下半部）
  ///
  /// 錘子線為「低檔」反轉訊號，收盤須落在 [support, resistance] 區間的下半部
  /// （近支撐）才符合「低檔錘子線」語意。位置 = (close - lower)/(upper - lower)，
  /// 超過此值視為近壓力、不觸發（高檔錘子形狀交由 HangingManRule 處理）。
  /// audit data #3：2542 於 2026-07-17 close 在 band 61.9%（近壓力）卻誤觸發。
  static const double hammerMaxBandPosition = 0.5;

  /// 三白兵/三黑鴉每根 K 線最小實體比例（1%）
  ///
  /// 每根 K 線的 |open - close| / close 須 >= 1%，
  /// 避免微小漲跌幅的 K 線誤觸發。
  static const double threeLineMinBodyRatio = 0.01;

  /// 十字線實體最大比例（10%）
  ///
  /// 實體小於振幅的 10% 視為十字線。
  static const double dojiBodyMaxRatio = 0.1;

  /// 跳空缺口最小比例（0.5%）
  ///
  /// 缺口須至少為前日收盤的 0.5%。
  static const double gapMinThreshold = 0.005;

  /// 星線小實體最大比例（0.5 倍第一根）
  ///
  /// 第二根 K 線實體不可超過第一根的 0.5 倍。
  static const double starSmallBodyMaxRatio = 0.5;

  /// 晨/暮星第二根跳空容差上界（2%）
  ///
  /// 星體中點允許略高於第一根收盤價（不強制完美跳空）。
  static const double starGapToleranceUpper = 1.02;

  /// 晨/暮星第二根跳空容差下界（2%）
  static const double starGapToleranceLower = 0.98;
}

/// 投資組合績效卡的參數
abstract final class PortfolioParams {
  /// 「日」報酬的窗口：近 1 個交易日
  static const dailyWindowTradingDays = 1;

  /// 「週」報酬的窗口：近 5 個交易日
  static const weeklyWindowTradingDays = 5;

  /// 「月」報酬的窗口：近 20 個交易日
  static const monthlyWindowTradingDays = 20;

  /// 期間報酬讀收盤價往回的日曆天數：20 個交易日加上農曆年長假仍夠用
  static const periodHistoryCalendarDays = 45;

  /// 一年的天數（換算年化用）
  static const daysPerYear = 365;

  /// 持有滿這麼多天才換算年化報酬（未滿一年的報酬外推成一年沒有意義）
  static const minAnnualizeDays = daysPerYear;
}

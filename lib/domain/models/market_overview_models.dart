// 大盤總覽資料模型
// 從 presentation/providers/market_overview_provider.dart 抽出，
// 供 domain services 與 presentation 共用，避免循環依賴。

/// 漲跌家數
class AdvanceDecline {
  const AdvanceDecline({
    this.advance = 0,
    this.decline = 0,
    this.unchanged = 0,
  });

  final int advance;
  final int decline;
  final int unchanged;

  int get total => advance + decline + unchanged;
}

/// 法人買賣超總額（元）
class InstitutionalTotals {
  const InstitutionalTotals({
    this.foreignNet = 0,
    this.trustNet = 0,
    this.dealerNet = 0,
    this.totalNet = 0,
  });

  final double foreignNet;
  final double trustNet;
  final double dealerNet;
  final double totalNet;
}

/// 融資融券彙總（張）
class MarginTradingTotals {
  const MarginTradingTotals({
    this.marginBalance = 0,
    this.marginChange = 0,
    this.shortBalance = 0,
    this.shortChange = 0,
  });

  final double marginBalance;
  final double marginChange;
  final double shortBalance;
  final double shortChange;
}

/// 成交額統計（元）
class TradingTurnover {
  const TradingTurnover({this.totalTurnover = 0});

  final double totalTurnover; // 單位：元
}

/// 漲停/跌停家數
class LimitUpDown {
  const LimitUpDown({this.limitUp = 0, this.limitDown = 0});

  final int limitUp;
  final int limitDown;
}

/// 成交額 vs 均量比較
class TurnoverComparison {
  const TurnoverComparison({this.todayTurnover = 0, this.avg5dTurnover = 0});

  final double todayTurnover;
  final double avg5dTurnover;

  /// 與 5 日均量的變化百分比
  double get changePercent => avg5dTurnover > 0
      ? (todayTurnover - avg5dTurnover) / avg5dTurnover * 100
      : 0;
}

/// 注意/處置股家數
class WarningCounts {
  const WarningCounts({this.attention = 0, this.disposal = 0});

  final int attention;
  final int disposal;

  int get total => attention + disposal;
}

/// 法人連續買賣超天數
class InstitutionalStreak {
  const InstitutionalStreak({
    this.foreignStreak = 0,
    this.trustStreak = 0,
    this.dealerStreak = 0,
  });

  /// 正數 = 連續買超天數，負數 = 連續賣超天數
  final int foreignStreak;
  final int trustStreak;
  final int dealerStreak;
}

/// 產業表現
class IndustrySummary {
  const IndustrySummary({
    required this.industry,
    required this.stockCount,
    required this.avgChangePct,
    required this.advance,
    required this.decline,
  });

  final String industry;
  final int stockCount;
  final double avgChangePct;
  final int advance;
  final int decline;
}

/// 帶日期的歷史資料點（時序排列 oldest→newest）
///
/// 情緒綜合（[HistoryTrends] 的四個 sentiment-input 欄位）需要 [date] 才能
/// 依日期 inner-join 對齊，避免不同 coverage 來源的序列按 array index 錯位
/// 拼接（filter 過的漲跌比/成交額 vs 未 filter 的法人/融資餘額日期集不同）。
typedef DatedValue = ({DateTime date, double value});

/// 30 日歷史趨勢資料（供 sparkline / bar chart，時序排列 oldest→newest）
///
/// 將 5 個同型別的歷史趨勢欄位封裝為一個物件，
/// 避免 [MarketOverviewState] 中的 data clump。
///
/// 四個 sentiment-input 欄位（[institutionalTotalNet]、[turnover]、
/// [marginBalance]、[advanceRatio]）攜帶日期，供
/// [MarketSentimentService.calculateHistoricalScores] 依日期對齊。個別
/// sparkline 仍取各自完整序列的 `.value`，不受對齊影響。
class HistoryTrends {
  const HistoryTrends({
    this.institutionalTotalNet = const {},
    this.turnover = const {},
    this.marginBalance = const {},
    this.shortBalance = const {},
    this.advanceRatio = const {},
  });

  /// 法人合計淨額（元）
  final Map<String, List<DatedValue>> institutionalTotalNet;

  /// 成交量（元）
  final Map<String, List<DatedValue>> turnover;

  /// 融資餘額（張）
  final Map<String, List<DatedValue>> marginBalance;

  /// 融券餘額（張）— 僅供 sparkline，不參與情緒對齊
  final Map<String, List<double>> shortBalance;

  /// 漲跌比 (advance/total, 0~1)
  final Map<String, List<DatedValue>> advanceRatio;
}

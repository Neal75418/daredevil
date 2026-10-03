import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';

/// 規則評估所需的市場資料物件
class StockData {
  const StockData({
    required this.symbol,
    required this.prices,
    required this.dividends,
    this.institutional,
    this.news,
    this.latestRevenue,
    this.latestValuation,
    this.revenueHistory,
    this.epsHistory,
    this.roeHistory,
    this.maxHistoricalRevenue,
  });

  final String symbol;
  final List<DailyPriceEntry> prices;

  /// 除權除息情境（52 週新高／新低還原價格用）：完整時帶窗口內、評分日以前
  /// 的事件；不完整時用到還原價的規則不觸發。刻意必填——評分兩條路徑與工具
  /// 都必須明確決定，漏傳會讓 52 週規則用原始價格判斷或靜默停發
  final DividendContext dividends;
  final List<DailyInstitutionalEntry>? institutional;
  final List<NewsItemEntry>? news;

  /// 最新月營收資料（用於基本面規則）
  final MonthlyRevenueEntry? latestRevenue;

  /// 最新估值資料（PE、PBR、殖利率）
  final StockValuationEntry? latestValuation;

  /// 近期月營收歷史（用於月增率追蹤）
  ///
  /// 需依時間降序排列（最新在前）
  final List<MonthlyRevenueEntry>? revenueHistory;

  /// EPS 歷史（最近 8 季，依時間降序）
  final List<FinancialDataEntry>? epsHistory;

  /// ROE 歷史（最近 8 季，依時間降序，虛擬 FinancialDataEntry）
  final List<FinancialDataEntry>? roeHistory;

  /// 歷史最高月營收（用於營收創新高規則）
  final double? maxHistoricalRevenue;

  /// 取得最新價格，若無資料則為 null
  DailyPriceEntry? get latestPrice => prices.isEmpty ? null : prices.last;

  /// 取得最新收盤價，若無資料則為 null
  double? get latestClose => latestPrice?.close;
}

/// 股票分析規則的基礎介面
abstract class StockRule {
  const StockRule();

  /// 規則的唯一識別碼
  String get id;

  /// 對股票資料評估此規則
  ///
  /// 若規則符合則回傳 [TriggeredReason]，否則回傳 null
  TriggeredReason? evaluate(AnalysisContext context, StockData data);
}

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

/// StockData 測試建構工具
///
/// 提供 StockData 及相關 Entry 的便捷建構方法，
/// 減少規則測試中的重複程式碼。

// ==========================================
// StockData Builder
// ==========================================

/// 建構測試用 StockData
StockData createTestStockData({
  String symbol = 'TEST',
  List<DailyPriceEntry>? prices,
  List<DailyInstitutionalEntry>? institutional,
  List<NewsItemEntry>? news,
  MonthlyRevenueEntry? latestRevenue,
  StockValuationEntry? latestValuation,
  List<MonthlyRevenueEntry>? revenueHistory,
  List<FinancialDataEntry>? epsHistory,
  List<FinancialDataEntry>? roeHistory,
  double? maxHistoricalRevenue,
  DividendContext dividends = DividendContext.noEvents,
}) {
  return StockData(
    symbol: symbol,
    prices: prices ?? [],
    dividends: dividends,
    institutional: institutional,
    news: news,
    latestRevenue: latestRevenue,
    latestValuation: latestValuation,
    revenueHistory: revenueHistory,
    epsHistory: epsHistory,
    roeHistory: roeHistory,
    maxHistoricalRevenue: maxHistoricalRevenue,
  );
}

// ==========================================
// MonthlyRevenueEntry Builder
// ==========================================

/// 建構測試用月營收資料
MonthlyRevenueEntry createTestMonthlyRevenue({
  String symbol = 'TEST',
  DateTime? date,
  int? revenueYear,
  int? revenueMonth,
  double revenue = 1000000,
  double? momGrowth,
  double? yoyGrowth,
}) {
  final d = date ?? DateTime.now();
  return MonthlyRevenueEntry(
    symbol: symbol,
    date: d,
    revenueYear: revenueYear ?? d.year,
    revenueMonth: revenueMonth ?? d.month,
    revenue: revenue,
    momGrowth: momGrowth,
    yoyGrowth: yoyGrowth,
  );
}

// ==========================================
// StockValuationEntry Builder
// ==========================================

/// 建構測試用估值資料
StockValuationEntry createTestValuation({
  String symbol = 'TEST',
  DateTime? date,
  double? per,
  double? pbr,
  double? dividendYield,
}) {
  return StockValuationEntry(
    symbol: symbol,
    date: date ?? DateTime.now(),
    per: per,
    pbr: pbr,
    dividendYield: dividendYield,
  );
}

// ==========================================
// FinancialDataEntry Builder (EPS / ROE)
// ==========================================

/// 建構測試用財務資料（EPS 或 ROE）
FinancialDataEntry createTestFinancialData({
  String symbol = 'TEST',
  required DateTime date,
  String statementType = 'INCOME',
  String dataType = 'EPS',
  double? value,
}) {
  return FinancialDataEntry(
    symbol: symbol,
    date: date,
    statementType: statementType,
    dataType: dataType,
    value: value,
  );
}

// ==========================================
// 趨勢資料產生器
// ==========================================

/// 產生 EPS 歷史（依時間降序，最新在前）
///
/// [quarters] 季數
/// [baseEps] 起始 EPS
/// [quarterlyGrowth] 每季 EPS 增量（可負值表示衰退）
List<FinancialDataEntry> generateEpsHistory({
  int quarters = 4,
  double baseEps = 1.0,
  double quarterlyGrowth = 0.2,
  String symbol = 'TEST',
  DateTime? anchor,
}) {
  final base = anchor ?? DateTime(2025, 12, 15);
  return List.generate(quarters, (i) {
    // 最新在前（i=0 = 最近季度），用固定日期避免跨年邊界問題
    final quarterDate = DateTime(base.year, base.month - (i * 3), 1);
    final eps = baseEps + (quarterlyGrowth * (quarters - 1 - i));
    return createTestFinancialData(
      symbol: symbol,
      date: quarterDate,
      dataType: 'EPS',
      value: eps,
    );
  });
}

/// 產生 ROE 歷史（依時間降序，最新在前）
List<FinancialDataEntry> generateRoeHistory({
  int quarters = 4,
  double baseRoe = 10.0,
  double quarterlyChange = 2.0,
  String symbol = 'TEST',
  DateTime? anchor,
}) {
  final base = anchor ?? DateTime(2025, 12, 15);
  return List.generate(quarters, (i) {
    final quarterDate = DateTime(base.year, base.month - (i * 3), 1);
    final roe = baseRoe + (quarterlyChange * (quarters - 1 - i));
    return createTestFinancialData(
      symbol: symbol,
      date: quarterDate,
      statementType: 'BALANCE',
      dataType: 'ROE',
      value: roe,
    );
  });
}

/// 產生月營收歷史（依時間降序，最新在前）
///
/// [months] 月數
/// [baseRevenue] 起始營收
/// [momGrowthValues] 指定各月的月增率列表（index 0 = 最新月）
/// [yoyGrowthValues] 指定各月的年增率列表（index 0 = 最新月）
List<MonthlyRevenueEntry> generateRevenueHistory({
  int months = 6,
  double baseRevenue = 1000000,
  List<double>? momGrowthValues,
  List<double>? yoyGrowthValues,
  String symbol = 'TEST',
  DateTime? anchor,
}) {
  final base = anchor ?? DateTime(2025, 12, 15);
  return List.generate(months, (i) {
    final date = DateTime(base.year, base.month - i, 1);
    return createTestMonthlyRevenue(
      symbol: symbol,
      date: date,
      revenueYear: date.year,
      revenueMonth: date.month,
      revenue: baseRevenue,
      momGrowth: momGrowthValues != null && i < momGrowthValues.length
          ? momGrowthValues[i]
          : null,
      yoyGrowth: yoyGrowthValues != null && i < yoyGrowthValues.length
          ? yoyGrowthValues[i]
          : null,
    );
  });
}

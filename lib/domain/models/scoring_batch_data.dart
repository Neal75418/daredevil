import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_data_groups.dart';

/// 外資持股資料
class ShareholdingData {
  const ShareholdingData({
    this.foreignSharesRatio,
    this.foreignSharesRatioChange,
    this.concentrationRatio,
  });

  factory ShareholdingData.fromMap(Map<String, dynamic> map) =>
      ShareholdingData(
        foreignSharesRatio: map['foreignSharesRatio'] as double?,
        foreignSharesRatioChange: map['foreignSharesRatioChange'] as double?,
        concentrationRatio: map['concentrationRatio'] as double?,
      );

  final double? foreignSharesRatio;
  final double? foreignSharesRatioChange;
  final double? concentrationRatio;

  Map<String, double?> toMap() => {
    'foreignSharesRatio': foreignSharesRatio,
    'foreignSharesRatioChange': foreignSharesRatioChange,
    'concentrationRatio': concentrationRatio,
  };
}

/// 評分用批次資料封裝
///
/// 將評分所需的 14+ 個 Map 參數按語意分為三大群組：
/// - [institutional] 法人與籌碼面
/// - [fundamental] 基本面（營收 + 估值）
/// - [financialHealth] 財務健康（EPS + ROE + 股利）
///
/// 保留 forwarding getters 確保現有消費者不需立即改動。
class ScoringBatchData {
  /// 原始建構子 — 接受個別 Map 參數，內部組裝為語意群組。
  ///
  /// 目前只有測試使用；生產路徑（BatchDataLoader）走 [ScoringBatchData.grouped]。
  /// 注意：因內部需組裝群組物件，此建構子無法標記為 `const`。
  ScoringBatchData({
    required this.pricesMap,
    required this.newsMap,
    Map<String, List<DailyInstitutionalEntry>>? institutionalMap,
    Map<String, MonthlyRevenueEntry>? revenueMap,
    Map<String, StockValuationEntry>? valuationMap,
    Map<String, List<MonthlyRevenueEntry>>? revenueHistoryMap,
    Map<String, List<FinancialDataEntry>>? epsHistoryMap,
    Map<String, List<FinancialDataEntry>>? roeHistoryMap,
    Map<String, List<DividendHistoryEntry>>? dividendHistoryMap,
    this.dayTradingMap,
    Map<String, ShareholdingData>? shareholdingMap,
    Map<String, WarningDataContext>? warningMap,
    Map<String, InsiderDataContext>? insiderMap,
    Map<String, double>? maxHistoricalRevenueMap,
  }) : institutional = InstitutionalIntelligence(
         institutionalMap: institutionalMap,
         shareholdingMap: shareholdingMap,
         warningMap: warningMap,
         insiderMap: insiderMap,
       ),
       fundamental = FundamentalDataGroup(
         revenueMap: revenueMap,
         valuationMap: valuationMap,
         revenueHistoryMap: revenueHistoryMap,
         maxHistoricalRevenueMap: maxHistoricalRevenueMap,
       ),
       financialHealth = FinancialHealthGroup(
         epsHistoryMap: epsHistoryMap,
         roeHistoryMap: roeHistoryMap,
         dividendHistoryMap: dividendHistoryMap,
       );

  /// 群組建構子 — 直接接受語意群組，供新程式碼使用。
  const ScoringBatchData.grouped({
    required this.pricesMap,
    required this.newsMap,
    this.institutional = const InstitutionalIntelligence(),
    this.fundamental = const FundamentalDataGroup(),
    this.financialHealth = const FinancialHealthGroup(),
    this.dayTradingMap,
  });

  // ==================================================
  // 核心欄位（不屬於任何群組）
  // ==================================================

  /// 股價歷史（symbol → 日K列表）
  final Map<String, List<DailyPriceEntry>> pricesMap;

  /// 新聞（symbol → 新聞列表）
  final Map<String, List<NewsItemEntry>> newsMap;

  /// 當沖比例（symbol → ratio）
  final Map<String, double>? dayTradingMap;

  // ==================================================
  // 語意群組
  // ==================================================

  /// 法人與籌碼面資料
  final InstitutionalIntelligence institutional;

  /// 基本面（營收 + 估值）資料
  final FundamentalDataGroup fundamental;

  /// 財務健康（EPS + ROE + 股利）資料
  final FinancialHealthGroup financialHealth;

  // ==================================================
  // Forwarding getters（向後相容）
  // ==================================================

  /// 法人買賣超（symbol → 日法人列表）
  Map<String, List<DailyInstitutionalEntry>>? get institutionalMap =>
      institutional.institutionalMap;

  /// 最新月營收（symbol → 單筆營收）
  Map<String, MonthlyRevenueEntry>? get revenueMap => fundamental.revenueMap;

  /// 最新估值（symbol → PE/PBR/殖利率）
  Map<String, StockValuationEntry>? get valuationMap =>
      fundamental.valuationMap;

  /// 營收歷史（symbol → 近6個月營收列表）
  Map<String, List<MonthlyRevenueEntry>>? get revenueHistoryMap =>
      fundamental.revenueHistoryMap;

  /// EPS 歷史（symbol → 近8季 EPS）
  Map<String, List<FinancialDataEntry>>? get epsHistoryMap =>
      financialHealth.epsHistoryMap;

  /// ROE 歷史（symbol → 近8季 ROE）
  Map<String, List<FinancialDataEntry>>? get roeHistoryMap =>
      financialHealth.roeHistoryMap;

  /// 股利歷史（symbol → 歷年股利）
  Map<String, List<DividendHistoryEntry>>? get dividendHistoryMap =>
      financialHealth.dividendHistoryMap;

  /// 外資持股（symbol → 持股資料）
  Map<String, ShareholdingData>? get shareholdingMap =>
      institutional.shareholdingMap;

  /// 警示資料（symbol → 警示上下文）
  Map<String, WarningDataContext>? get warningMap => institutional.warningMap;

  /// 董監持股（symbol → 董監上下文）
  Map<String, InsiderDataContext>? get insiderMap => institutional.insiderMap;

  /// 歷史最高月營收（symbol → maxRevenue）
  Map<String, double>? get maxHistoricalRevenueMap =>
      fundamental.maxHistoricalRevenueMap;
}

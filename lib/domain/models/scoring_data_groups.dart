import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';

/// 法人與籌碼面資料群組
///
/// 包含法人買賣超、外資持股、警示/處置、董監持股等
/// 影響短中期股價走勢的籌碼面因子。
class InstitutionalIntelligence {
  const InstitutionalIntelligence({
    this.institutionalMap,
    this.shareholdingMap,
    this.warningMap,
    this.insiderMap,
  });

  /// 法人買賣超（symbol → 日法人列表）
  final Map<String, List<DailyInstitutionalEntry>>? institutionalMap;

  /// 外資持股（symbol → 持股資料）
  final Map<String, ShareholdingData>? shareholdingMap;

  /// 警示資料（symbol → 警示上下文）
  final Map<String, WarningDataContext>? warningMap;

  /// 董監持股（symbol → 董監上下文）
  final Map<String, InsiderDataContext>? insiderMap;
}

/// 基本面（營收 + 估值）資料群組
///
/// 包含月營收、PE/PBR/殖利率估值、營收歷史趨勢、
/// 歷史最高營收等基本面因子。
class FundamentalDataGroup {
  const FundamentalDataGroup({
    this.revenueMap,
    this.valuationMap,
    this.revenueHistoryMap,
    this.maxHistoricalRevenueMap,
  });

  /// 最新月營收（symbol → 單筆營收）
  final Map<String, MonthlyRevenueEntry>? revenueMap;

  /// 最新估值（symbol → PE/PBR/殖利率）
  final Map<String, StockValuationEntry>? valuationMap;

  /// 營收歷史（symbol → 近6個月營收列表）
  final Map<String, List<MonthlyRevenueEntry>>? revenueHistoryMap;

  /// 歷史最高月營收（symbol → maxRevenue）
  final Map<String, double>? maxHistoricalRevenueMap;
}

/// 財務健康（EPS + ROE）資料群組
///
/// 包含近 8 季 EPS/ROE 趨勢，用於評估公司長期獲利能力。
class FinancialHealthGroup {
  const FinancialHealthGroup({this.epsHistoryMap, this.roeHistoryMap});

  /// EPS 歷史（symbol → 近8季 EPS）
  final Map<String, List<FinancialDataEntry>>? epsHistoryMap;

  /// ROE 歷史（symbol → 近8季 ROE）
  final Map<String, List<FinancialDataEntry>>? roeHistoryMap;
}

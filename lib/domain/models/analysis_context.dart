import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/models/technical_indicators.dart';

/// 傳遞給所有規則的評估上下文
class AnalysisContext {
  const AnalysisContext({
    required this.trendState,
    required this.evaluationTime,
    this.reversalState = ReversalState.none,
    this.supportLevel,
    this.resistanceLevel,
    this.rangeTop,
    this.rangeBottom,
    this.marketData,
    this.indicators,
    this.isMarketUptrend,
  });

  final TrendState trendState;
  final ReversalState reversalState;
  final double? supportLevel;
  final double? resistanceLevel;
  final double? rangeTop;
  final double? rangeBottom;
  final MarketDataContext? marketData;
  final TechnicalIndicators? indicators;

  /// 大盤是否處於上升 regime（全市場 120 交易日**中位數**報酬 > 0，
  /// 等價於「過半股票在漲」；2026-08-29 由等權平均改，見
  /// [PriceCalculator.marketUptrendOrNull]）。
  ///
  /// null = 不知道（資料不足）→ 規則採 permissive 不擋。
  /// 回檔類規則（buy-the-dip）在空頭 regime 一律不觸發——2026-07-10
  /// 回放分段實證 edge 幾乎全來自多頭（MA20 60D 多頭 +6.47% vs
  /// 空頭 -0.65%）；momentum 類因子空頭反轉（backtest IC -0.078）。
  final bool? isMarketUptrend;

  /// 評估時間點，供規則判斷資料新鮮度等時間相關邏輯。
  ///
  /// M13 fix：required。之前是 nullable + caller 自己 `?? DateTime.now()`
  /// fallback，違反 [rule engine 純函數契約](CLAUDE.md) — 3 個生產 caller
  /// (scoring_isolate / scoring_service / replay_calibrator) 都顯式傳值，
  /// rule 內部 fallback 是 dormant bug 種子，改 required 拔掉。
  final DateTime evaluationTime;
}

/// 第四階段訊號所需的額外市場資料
class MarketDataContext {
  const MarketDataContext({
    this.foreignSharesRatio,
    this.foreignSharesRatioChange,
    this.dayTradingRatio,
    this.concentrationRatio,
    // Killer Features 資料
    this.warningData,
    this.insiderData,
  });

  /// 從四項市場資料建構，全部為 null 時回傳 null
  static MarketDataContext? fromComponents({
    double? dayTradingRatio,
    ShareholdingData? shareholding,
    WarningDataContext? warning,
    InsiderDataContext? insider,
  }) {
    if (dayTradingRatio == null &&
        shareholding == null &&
        warning == null &&
        insider == null) {
      return null;
    }
    return MarketDataContext(
      dayTradingRatio: dayTradingRatio,
      foreignSharesRatio: shareholding?.foreignSharesRatio,
      foreignSharesRatioChange: shareholding?.foreignSharesRatioChange,
      concentrationRatio: shareholding?.concentrationRatio,
      warningData: warning,
      insiderData: insider,
    );
  }

  final double? foreignSharesRatio;
  final double? foreignSharesRatioChange;
  final double? dayTradingRatio;
  final double? concentrationRatio;

  // Killer Features 資料
  final WarningDataContext? warningData;
  final InsiderDataContext? insiderData;
}

/// 注意/處置股票資料
class WarningDataContext {
  const WarningDataContext({
    this.isAttention = false,
    this.isDisposal = false,
    this.warningType,
    this.reasonDescription,
    this.disposalMeasures,
    this.disposalEndDate,
  });

  factory WarningDataContext.fromMap(Map<String, dynamic> map) {
    final warningType = map['warningType'] as String?;
    return WarningDataContext(
      isAttention: warningType == 'ATTENTION',
      isDisposal: warningType == 'DISPOSAL',
      warningType: warningType,
      reasonDescription: map['reasonDescription'] as String?,
      disposalMeasures: map['disposalMeasures'] as String?,
      disposalEndDate: map['disposalEndDate'] != null
          ? DateTime.tryParse(map['disposalEndDate'] as String)
          : null,
    );
  }

  /// 是否為注意股票
  final bool isAttention;

  /// 是否為處置股票
  final bool isDisposal;

  /// 警示類型（ATTENTION / DISPOSAL）
  final String? warningType;

  /// 警示原因描述
  final String? reasonDescription;

  /// 處置措施
  final String? disposalMeasures;

  /// 處置結束日期
  final DateTime? disposalEndDate;

  Map<String, dynamic> toMap() => {
    'warningType': warningType,
    'reasonDescription': reasonDescription,
    'disposalMeasures': disposalMeasures,
    'disposalEndDate': disposalEndDate?.toIso8601String(),
  };
}

/// 董監持股資料
class InsiderDataContext {
  const InsiderDataContext({
    this.insiderRatio,
    this.pledgeRatio,
    this.hasSellingStreak = false,
    this.sellingStreakMonths = 0,
    this.hasSignificantBuying = false,
    this.buyingChange,
  });

  factory InsiderDataContext.fromMap(Map<String, dynamic> map) =>
      InsiderDataContext(
        insiderRatio: map['insiderRatio'] as double?,
        pledgeRatio: map['pledgeRatio'] as double?,
        hasSellingStreak: map['hasSellingStreak'] as bool? ?? false,
        sellingStreakMonths: map['sellingStreakMonths'] as int? ?? 0,
        hasSignificantBuying: map['hasSignificantBuying'] as bool? ?? false,
        buyingChange: map['buyingChange'] as double?,
      );

  /// 董監持股比例（%）
  final double? insiderRatio;

  /// 質押比例（%）
  final double? pledgeRatio;

  /// 是否連續減持
  final bool hasSellingStreak;

  /// 連續減持月數
  final int sellingStreakMonths;

  /// 是否有顯著增持
  final bool hasSignificantBuying;

  /// 增持變化幅度（%）
  final double? buyingChange;

  Map<String, dynamic> toMap() => {
    'insiderRatio': insiderRatio,
    'pledgeRatio': pledgeRatio,
    'hasSellingStreak': hasSellingStreak,
    'sellingStreakMonths': sellingStreakMonths,
    'hasSignificantBuying': hasSignificantBuying,
    'buyingChange': buyingChange,
  };
}

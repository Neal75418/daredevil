import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/fundamental_technical_filter.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';

// ==================================================
// 第 6 階段：基本面分析規則
// ==================================================

/// 檢查估值資料是否已過時（超過 [FundamentalParams.valuationMaxStaleDays] 天）
bool _isValuationStale(StockValuationEntry valuation, AnalysisContext context) {
  final dataAge = context.evaluationTime.difference(valuation.date).inDays;
  return dataAge > FundamentalParams.valuationMaxStaleDays;
}

/// 規則：營收年增暴增
///
/// 當月營收年增率 ≥ 30% 且股價站上 MA60 時觸發
class RevenueYoYSurgeRule extends StockRule with FundamentalTechnicalFilter {
  const RevenueYoYSurgeRule();

  @override
  String get id => 'revenue_yoy_surge';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final revenue = data.latestRevenue;
    if (revenue == null) return null;

    final yoyGrowth = revenue.yoyGrowth ?? 0;
    if (yoyGrowth < FundamentalParams.revenueYoySurgeThreshold) return null;

    final filter = checkAboveMAWithMomentum(
      context: context,
      data: data,
      maSelector: (i) => i.ma60,
    );
    if (filter == null) return null;

    return TriggeredReason(
      type: ReasonType.revenueYoySurge,
      score: RuleScores.revenueYoySurge,
      description: '營收年增 ${yoyGrowth.toStringAsFixed(1)}% (站上季線且長紅)',
      evidence: {
        'yoyGrowth': yoyGrowth,
        'revenueMonth': revenue.revenueMonth,
        'ma60': filter.ma,
        'changePct': filter.changePct * 100,
      },
    );
  }
}

/// 規則：營收年減警示
///
class RevenueYoYDeclineRule extends StockRule {
  const RevenueYoYDeclineRule();

  @override
  String get id => 'revenue_yoy_decline';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final revenue = data.latestRevenue;
    if (revenue == null) return null;

    final yoyGrowth = revenue.yoyGrowth ?? 0;

    if (yoyGrowth <= -FundamentalParams.revenueYoyDeclineThreshold) {
      return TriggeredReason(
        type: ReasonType.revenueYoyDecline,
        score: RuleScores.revenueYoyDecline,
        description: '營收年減 ${yoyGrowth.abs().toStringAsFixed(1)}%',
        evidence: {
          'yoyGrowth': yoyGrowth,
          'revenueMonth': revenue.revenueMonth,
        },
      );
    }

    return null;
  }
}

/// 規則：營收月增持續
///
/// 當月營收月增 ≥10%（revenueMomGrowthThreshold）且通過技術動能過濾
/// （站上 MA20＋近日漲幅確認）時觸發
class RevenueMomGrowthRule extends StockRule with FundamentalTechnicalFilter {
  const RevenueMomGrowthRule();

  @override
  String get id => 'revenue_mom_growth';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final history = data.revenueHistory;
    if (history == null ||
        history.length < FundamentalParams.revenueMomConsecutiveMonths) {
      return null;
    }

    // 連續月增計數(revenueMomConsecutiveMonths 現值=1 → 實際只看當月;
    // 迴圈機制保留供調參)
    int consecutiveMonths = 0;
    final growthRates = <double>[];

    for (
      int i = 0;
      i < history.length && i < FundamentalParams.revenueMomConsecutiveMonths;
      i++
    ) {
      final momGrowth = history[i].momGrowth ?? 0;
      if (momGrowth >= FundamentalParams.revenueMomGrowthThreshold) {
        consecutiveMonths++;
        growthRates.add(momGrowth);
      } else {
        break;
      }
    }

    if (consecutiveMonths < FundamentalParams.revenueMomConsecutiveMonths) {
      return null;
    }

    // 技術面過濾：站上 MA20 且漲幅 > 1.5%
    final filter = checkAboveMAWithMomentum(
      context: context,
      data: data,
      maSelector: (i) => i.ma20,
    );
    if (filter == null) return null;

    final avgGrowth = growthRates.reduce((a, b) => a + b) / growthRates.length;
    // 註:revenueMomConsecutiveMonths 現值=1,else 分支現行不觸發——這是
    // config-dead 不是結構死碼,調高參數即活,機制刻意保留(2026-08-15 審計)
    final description = consecutiveMonths == 1
        ? '本月營收月增 ${avgGrowth.toStringAsFixed(1)}% (站上月線)'
        : '營收月增連續 $consecutiveMonths 個月 (站上月線)';

    return TriggeredReason(
      type: ReasonType.revenueMomGrowth,
      score: RuleScores.revenueMomGrowth,
      description: description,
      evidence: {
        'consecutiveMonths': consecutiveMonths,
        'avgMomGrowth': avgGrowth,
        'ma20': filter.ma,
      },
    );
  }
}

/// 規則：營收創歷史新高
///
/// 當月營收超過歷史最高記錄，搭配站上 MA20
class RevenueNewHighRule extends StockRule with FundamentalTechnicalFilter {
  const RevenueNewHighRule();

  @override
  String get id => 'revenue_new_high';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final revenue = data.latestRevenue;
    final maxRevenue = data.maxHistoricalRevenue;
    if (revenue == null || maxRevenue == null || maxRevenue <= 0) return null;

    final currentRevenue = revenue.revenue;
    if (currentRevenue <= 0) return null;

    // 當月營收必須超過歷史最高
    if (currentRevenue <= maxRevenue) return null;

    // 技術面過濾：站上 MA20
    final filter = checkAboveMA(
      context: context,
      data: data,
      maSelector: (i) => i.ma20,
    );
    if (filter == null) return null;

    final revenueInBillion = currentRevenue / 100000;
    final surpassPct = (currentRevenue - maxRevenue) / maxRevenue * 100;

    return TriggeredReason(
      type: ReasonType.revenueNewHigh,
      score: RuleScores.revenueNewHigh,
      description: '營收 ${revenueInBillion.toStringAsFixed(1)} 億創歷史新高',
      evidence: {
        'currentRevenue': currentRevenue,
        'maxHistoricalRevenue': maxRevenue,
        'revenueMonth': revenue.revenueMonth,
        'surpassPct': surpassPct,
      },
    );
  }
}

/// 規則：高殖利率
class HighDividendYieldRule extends StockRule {
  const HighDividendYieldRule();

  @override
  String get id => 'high_dividend_yield';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final valuation = data.latestValuation;
    if (valuation == null) return null;

    // 資料新鮮度檢查：確保估值資料在有效期限內
    // TWSE 並非每日更新所有股票，過時資料可能導致誤判
    if (_isValuationStale(valuation, context)) {
      final dataAge = context.evaluationTime.difference(valuation.date).inDays;
      AppLogger.debug(
        'HighYieldRule',
        '${data.symbol}: 資料過時 ($dataAge 天)，跳過評估',
      );
      return null;
    }

    // TWSE 和 FinMind 的殖利率已經是百分比格式（5.23 = 5.23%）
    // 不需要額外正規化
    final dividendYield = valuation.dividendYield ?? 0;

    // 診斷日誌：記錄所有被評估的殖利率數值（僅記錄 >= 4% 的以減少雜訊）
    if (dividendYield >= FundamentalParams.scanDividendYieldMin) {
      AppLogger.debug(
        'HighYieldRule',
        '${data.symbol}: 殖利率=${dividendYield.toStringAsFixed(2)}%, '
            '日期=${valuation.date.toIso8601String().substring(0, 10)}',
      );
    }

    // 過濾無效或過低殖利率（< 5.5%，highDividendYieldThreshold）
    if (dividendYield < FundamentalParams.highDividendYieldThreshold) {
      return null;
    }

    // 過濾異常高殖利率（> 20% 通常為資料錯誤或特殊情況）
    if (dividendYield > FundamentalParams.scanDividendYieldMax) {
      return null;
    }

    return TriggeredReason(
      type: ReasonType.highDividendYield,
      score: RuleScores.highDividendYield,
      description: '殖利率 ${dividendYield.toStringAsFixed(2)}%',
      evidence: {
        'dividendYield': dividendYield,
        'date': valuation.date.toIso8601String(),
      },
    );
  }
}

/// 規則：PE 低估
class PEUndervaluedRule extends StockRule with FundamentalTechnicalFilter {
  const PEUndervaluedRule();

  @override
  String get id => 'pe_undervalued';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final valuation = data.latestValuation;
    if (valuation == null) return null;

    // 資料新鮮度檢查
    if (_isValuationStale(valuation, context)) return null;

    final pe = valuation.per ?? 0;
    if (pe <= 0 || pe > FundamentalParams.peUndervaluedThreshold) return null;

    // 過濾條件：須顯示強勢跡象（股價 > MA20）
    final filter = checkAboveMA(
      context: context,
      data: data,
      maSelector: (i) => i.ma20,
    );
    if (filter == null) return null;

    return TriggeredReason(
      type: ReasonType.peUndervalued,
      score: RuleScores.peUndervalued,
      description: 'PE 僅 ${pe.toStringAsFixed(2)} 倍 (站上月線)',
      evidence: {'pe': pe, 'ma20': filter.ma},
    );
  }
}

/// 規則：PE 偏高
class PEOvervaluedRule extends StockRule {
  const PEOvervaluedRule();

  @override
  String get id => 'pe_overvalued';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final valuation = data.latestValuation;
    if (valuation == null) return null;

    // 資料新鮮度檢查
    if (_isValuationStale(valuation, context)) return null;

    final pe = valuation.per ?? 0;

    if (pe >= FundamentalParams.peOvervaluedThreshold) {
      // 過濾條件：須處於過熱狀態（RSI > 75，scanRsiOverboughtThreshold）
      // 優先使用 context.indicators.rsi（含 Wilder smoothing），
      // 若 indicators 為 null（價格資料 < 60 天）則 fallback 到直接計算
      final rsi =
          context.indicators?.rsi ??
          TechnicalIndicatorService.latestRSI(data.prices);
      if (rsi != null && rsi > FundamentalParams.scanRsiOverboughtThreshold) {
        return TriggeredReason(
          type: ReasonType.peOvervalued,
          score: RuleScores.peOvervalued,
          description: 'PE 高達 ${pe.toStringAsFixed(1)} 倍 (RSI過熱)',
          evidence: {'pe': pe, 'rsi': rsi},
        );
      }
    }
    return null;
  }
}

/// 規則：PBR 低估
class PBRUndervaluedRule extends StockRule {
  const PBRUndervaluedRule();

  @override
  String get id => 'pbr_undervalued';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final valuation = data.latestValuation;
    if (valuation == null) return null;

    // 資料新鮮度檢查
    if (_isValuationStale(valuation, context)) return null;

    final pbr = valuation.pbr ?? 0;

    if (pbr > 0 && pbr <= FundamentalParams.pbrUndervaluedThreshold) {
      return TriggeredReason(
        type: ReasonType.pbrUndervalued,
        score: RuleScores.pbrUndervalued,
        description: 'PBR 僅 ${pbr.toStringAsFixed(2)} 倍',
        evidence: {'pbr': pbr},
      );
    }
    return null;
  }
}

// ==================================================
// 第 7 階段：EPS 分析規則
// ==================================================

/// 規則：EPS 年增暴增
///
/// 最新一季 EPS 年增率 ≥ 50%，搭配站上季線(MA60) + 長紅
class EPSYoYSurgeRule extends StockRule with FundamentalTechnicalFilter {
  const EPSYoYSurgeRule();

  @override
  String get id => 'eps_yoy_surge';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final eps = data.epsHistory;
    if (eps == null || eps.length < FundamentalParams.epsYearLookback) {
      return null;
    }

    // 最新一季 & 去年同季（降序排列，index 0 = 最新）
    final latest = eps[0];
    final latestEps = latest.value;
    if (latestEps == null || latestEps <= 0) return null;

    // 找去年同季（用季度編號比較）
    // FinancialDataEntry.date 為季度截止日（FinMind 損益表回傳日曆日期如
    // 2024-03-31，由 parseQuarterDate 的非 "YYYY-QN" 分支原樣解析），
    // 例如 Q1 = 3月, Q2 = 6月, Q3 = 9月, Q4 = 12月，非申報日期。
    // (month - 1) ~/ 3 對季末(3/6/9/12)與季初(1/4/7/10)月份都映射到季度編號 0~3，故仍正確。
    final latestQuarter = (latest.date.month - 1) ~/ 3;
    double? lastYearEps;
    for (int i = FundamentalParams.epsQuarterOffset; i < eps.length; i++) {
      final candidateQuarter = (eps[i].date.month - 1) ~/ 3;
      if (candidateQuarter == latestQuarter) {
        lastYearEps = eps[i].value;
        break;
      }
    }
    if (lastYearEps == null || lastYearEps <= 0) return null;

    final yoyGrowth = (latestEps - lastYearEps) / lastYearEps * 100;
    if (yoyGrowth < FundamentalParams.epsYoYSurgeThreshold) return null;

    // 技術面過濾：站上 MA60 + 長紅
    final filter = checkAboveMAWithMomentum(
      context: context,
      data: data,
      maSelector: (i) => i.ma60,
    );
    if (filter == null) return null;

    return TriggeredReason(
      type: ReasonType.epsYoYSurge,
      score: RuleScores.epsYoYSurge,
      description:
          'EPS 年增 ${yoyGrowth.toStringAsFixed(1)}% '
          '(${latestEps.toStringAsFixed(2)} 元, 站上季線)',
      evidence: {
        'eps': latestEps,
        'lastYearEps': lastYearEps,
        'yoyGrowth': yoyGrowth,
        'ma60': filter.ma,
        'changePct': filter.changePct * 100,
      },
    );
  }
}

/// 規則：EPS 連續成長
///
/// 連續 ≥ 2 季 EPS 季增 ≥ 10%，搭配站上月線(MA20)
class EPSConsecutiveGrowthRule extends StockRule
    with FundamentalTechnicalFilter {
  const EPSConsecutiveGrowthRule();

  @override
  String get id => 'eps_consecutive_growth';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final eps = data.epsHistory;
    if (eps == null ||
        eps.length < FundamentalParams.epsConsecutiveQuarters + 1) {
      return null;
    }

    // 檢查連續季增
    int consecutive = 0;
    final growthRates = <double>[];

    for (int i = 0; i < eps.length - 1; i++) {
      final current = eps[i].value;
      final previous = eps[i + 1].value;
      if (current == null || previous == null) break;
      // 前一季 EPS <= 0 時無法計算有意義的成長率，中斷連續序列
      if (previous <= 0) break;

      final growth = (current - previous) / previous * 100;
      if (growth >= FundamentalParams.epsGrowthThreshold) {
        consecutive++;
        growthRates.add(growth);
      } else {
        break;
      }
    }

    if (consecutive < FundamentalParams.epsConsecutiveQuarters) return null;

    // 技術面過濾：站上 MA20
    final filter = checkAboveMA(
      context: context,
      data: data,
      maSelector: (i) => i.ma20,
    );
    if (filter == null) return null;

    final avgGrowth = growthRates.reduce((a, b) => a + b) / growthRates.length;
    return TriggeredReason(
      type: ReasonType.epsConsecutiveGrowth,
      score: RuleScores.epsConsecutiveGrowth,
      description:
          'EPS 連續 $consecutive 季成長 '
          '(平均 ${avgGrowth.toStringAsFixed(1)}%, 站上月線)',
      evidence: {
        'consecutiveQuarters': consecutive,
        'avgGrowth': avgGrowth,
        'latestEps': eps[0].value,
        'ma20': filter.ma,
      },
    );
  }
}

/// 規則：EPS 由負轉正
///
/// 前季虧損、本季 EPS ≥ 0.3 元，搭配站上月線或 RSI > 50
class EPSTurnaroundRule extends StockRule {
  const EPSTurnaroundRule();

  @override
  String get id => 'eps_turnaround';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final eps = data.epsHistory;
    if (eps == null || eps.length < 2) return null;

    final latestEps = eps[0].value;
    final previousEps = eps[1].value;
    if (latestEps == null || previousEps == null) return null;

    // 前季虧損，本季獲利 ≥ 門檻
    if (previousEps >= 0 ||
        latestEps < FundamentalParams.epsTurnaroundThreshold) {
      return null;
    }

    // 技術面過濾：站上 MA20 或 RSI > 50
    final ma20 = context.indicators?.ma20;
    final close = data.prices.isNotEmpty ? data.prices.last.close : null;
    // 優先使用 context.indicators.rsi，fallback 到直接計算（需 15 vs 60 data points）
    final rsi =
        context.indicators?.rsi ??
        TechnicalIndicatorService.latestRSI(data.prices);

    final aboveMA20 = ma20 != null && close != null && close > ma20;
    final rsiPositive =
        rsi != null && rsi > FundamentalParams.scanRsiMomentumThreshold;

    if (aboveMA20 || rsiPositive) {
      return TriggeredReason(
        type: ReasonType.epsTurnaround,
        score: RuleScores.epsTurnaround,
        description:
            'EPS 由虧轉盈 '
            '(${previousEps.toStringAsFixed(2)} → ${latestEps.toStringAsFixed(2)} 元)',
        evidence: {
          'latestEps': latestEps,
          'previousEps': previousEps,
          'aboveMA20': aboveMA20,
          'rsi': rsi,
        },
      );
    }
    return null;
  }
}

/// 規則：EPS 衰退警示（扣分）
///
/// 連續 2 季 EPS 季減 ≥ 20%
class EPSDeclineWarningRule extends StockRule {
  const EPSDeclineWarningRule();

  @override
  String get id => 'eps_decline_warning';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final eps = data.epsHistory;
    if (eps == null || eps.length < 3) return null;

    // 檢查連續 2 季衰退
    int declineCount = 0;
    final declineRates = <double>[];

    for (int i = 0; i < eps.length - 1 && declineCount < 2; i++) {
      final current = eps[i].value;
      final previous = eps[i + 1].value;
      if (current == null || previous == null) break;

      // previous <= 0 時無法計算百分比衰退率
      // 仍判斷是否持續惡化，但不加入 declineRates 避免混用單位
      if (previous <= 0) {
        if (current < previous) {
          declineCount++;
        } else {
          break;
        }
        continue;
      }

      final decline = (previous - current) / previous * 100;
      if (decline >= FundamentalParams.epsDeclineThreshold) {
        declineCount++;
        declineRates.add(decline);
      } else {
        break;
      }
    }

    if (declineCount >= 2) {
      final avgDecline = declineRates.isNotEmpty
          ? declineRates.reduce((a, b) => a + b) / declineRates.length
          : null;
      final description = avgDecline != null
          ? 'EPS 連續 $declineCount 季衰退 '
                '(平均衰退 ${avgDecline.toStringAsFixed(1)}%)'
          : 'EPS 連續 $declineCount 季衰退';
      return TriggeredReason(
        type: ReasonType.epsDeclineWarning,
        score: RuleScores.epsDeclineWarning,
        description: description,
        evidence: {
          'declineQuarters': declineCount,
          // ignore: use_null_aware_elements
          if (avgDecline != null) 'avgDecline': avgDecline,
          'latestEps': eps[0].value,
        },
      );
    }
    return null;
  }
}

// ==================================================
// ROE 分析規則
// ==================================================

/// 規則：ROE 優異
///
/// 最新季 ROE ≥ 15%，搭配站上 MA20
class ROEExcellentRule extends StockRule {
  const ROEExcellentRule();

  @override
  String get id => 'roe_excellent';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final roe = data.roeHistory;
    if (roe == null || roe.isEmpty) return null;

    final latestRoe = roe[0].value;
    if (latestRoe == null ||
        latestRoe < FundamentalParams.roeExcellentThreshold) {
      return null;
    }

    // 技術面過濾：站上 MA20
    final ma20 = context.indicators?.ma20;
    final close = data.latestClose;
    if (ma20 == null || close == null || close <= ma20) return null;

    return TriggeredReason(
      type: ReasonType.roeExcellent,
      score: RuleScores.roeExcellent,
      description:
          'ROE ${latestRoe.toStringAsFixed(1)}% '
          '(≥${FundamentalParams.roeExcellentThreshold.toInt()}%, 站上月線)',
      evidence: {'roe': latestRoe, 'ma20': ma20, 'close': close},
    );
  }
}

/// 規則：ROE 持續改善
///
/// 連續 ≥ 2 季 ROE 改善 ≥ 5pt，搭配站上 MA20
class ROEImprovingRule extends StockRule with FundamentalTechnicalFilter {
  const ROEImprovingRule();

  @override
  String get id => 'roe_improving';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final roe = data.roeHistory;
    if (roe == null || roe.length < FundamentalParams.roeMinQuarters + 1) {
      return null;
    }

    // 檢查連續改善
    int improvingCount = 0;
    double totalImprovement = 0;

    for (int i = 0; i < roe.length - 1; i++) {
      final current = roe[i].value;
      final previous = roe[i + 1].value;
      if (current == null || previous == null) break;

      final improvement = current - previous;
      if (improvement >= FundamentalParams.roeImprovingThreshold) {
        improvingCount++;
        totalImprovement += improvement;
      } else {
        break;
      }
    }

    if (improvingCount < FundamentalParams.roeMinQuarters) return null;

    // 技術面過濾：站上 MA20
    final filter = checkAboveMA(
      context: context,
      data: data,
      maSelector: (i) => i.ma20,
    );
    if (filter == null) return null;

    final avgImprovement = totalImprovement / improvingCount;
    return TriggeredReason(
      type: ReasonType.roeImproving,
      score: RuleScores.roeImproving,
      description:
          'ROE 連續 $improvingCount 季改善 '
          '(平均 +${avgImprovement.toStringAsFixed(1)}pt)',
      evidence: {
        'improvingQuarters': improvingCount,
        'avgImprovement': avgImprovement,
        'latestRoe': roe[0].value,
      },
    );
  }
}

/// 規則：ROE 衰退
///
/// 連續 ≥ 2 季 ROE 衰退 ≥ 5pt（扣分規則）
class ROEDecliningRule extends StockRule {
  const ROEDecliningRule();

  @override
  String get id => 'roe_declining';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final roe = data.roeHistory;
    if (roe == null || roe.length < FundamentalParams.roeMinQuarters + 1) {
      return null;
    }

    // 檢查連續衰退
    int decliningCount = 0;
    double totalDecline = 0;

    for (int i = 0; i < roe.length - 1; i++) {
      final current = roe[i].value;
      final previous = roe[i + 1].value;
      if (current == null || previous == null) break;

      final decline = previous - current;
      if (decline >= FundamentalParams.roeDecliningThreshold) {
        decliningCount++;
        totalDecline += decline;
      } else {
        break;
      }
    }

    if (decliningCount < FundamentalParams.roeMinQuarters) return null;

    final avgDecline = totalDecline / decliningCount;
    return TriggeredReason(
      type: ReasonType.roeDeclining,
      score: RuleScores.roeDeclining,
      description:
          'ROE 連續 $decliningCount 季衰退 '
          '(平均 -${avgDecline.toStringAsFixed(1)}pt)',
      evidence: {
        'decliningQuarters': decliningCount,
        'avgDecline': avgDecline,
        'latestRoe': roe[0].value,
      },
    );
  }
}

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

// ==================================================
// 第 4 階段：擴展市場資料規則
// ==================================================

/// 規則：外資持股增加
///
/// 當外資持股比例顯著增加時觸發
class ForeignShareholdingIncreasingRule extends StockRule {
  const ForeignShareholdingIncreasingRule();

  @override
  String get id => 'foreign_shareholding_increasing';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final marketData = context.marketData;
    if (marketData == null) return null;

    final change = marketData.foreignSharesRatioChange;
    if (change == null) return null;

    // 當外資持股增加達到門檻時觸發
    if (change >= InstitutionalParams.foreignShareholdingIncreaseThreshold) {
      return TriggeredReason(
        type: ReasonType.foreignShareholdingIncreasing,
        score: RuleScores.foreignShareholdingIncreasing,
        description: '外資持股比例增加 ${change.toStringAsFixed(2)}%',
        evidence: {'change': change, 'ratio': marketData.foreignSharesRatio},
      );
    }

    return null;
  }
}

/// 規則：外資持股減少
///
/// 當外資持股比例顯著減少時觸發
class ForeignShareholdingDecreasingRule extends StockRule {
  const ForeignShareholdingDecreasingRule();

  @override
  String get id => 'foreign_shareholding_decreasing';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final marketData = context.marketData;
    if (marketData == null) return null;

    final change = marketData.foreignSharesRatioChange;
    if (change == null) return null;

    // 加速流出(≤ foreignExodusThreshold)由 ForeignExodusRule(−20)代表,
    // 本規則只負責「顯著但未加速」那一段——兩條讀同一個
    // foreignSharesRatioChange、門檻是包含關係,不設上界會讓同一個量測被
    // 扣兩次(2026-08-15 稽核實測共現率 52/52 = 100%,實扣 −32 而非 −20)。
    // 走條件互斥而非 mutex group:mutex 取「分數最高」,對負分會選中扣得
    // 最少的那條(−12 勝過 −20),方向相反;此修法沿用 2026-07-18
    // PULLBACK_MA10 × MA20 的既有慣例。
    if (change <= FundamentalParams.foreignExodusThreshold) return null;

    // 當外資持股減少達到門檻時觸發
    if (change <= -InstitutionalParams.foreignShareholdingIncreaseThreshold) {
      return TriggeredReason(
        type: ReasonType.foreignShareholdingDecreasing,
        score: RuleScores.foreignShareholdingDecreasing,
        description: '外資持股比例減少 ${change.abs().toStringAsFixed(2)}%',
        evidence: {'change': change, 'ratio': marketData.foreignSharesRatio},
      );
    }

    return null;
  }
}

/// 規則：高當沖比例
///
/// 當當沖比例超過門檻時觸發
class DayTradingHighRule extends StockRule {
  const DayTradingHighRule();

  @override
  String get id => 'day_trading_high';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final marketData = context.marketData;
    if (marketData == null) return null;

    final ratio = marketData.dayTradingRatio;
    if (ratio == null) return null;

    // 過濾條件：成交量需達門檻
    final lastPrice = data.prices.isNotEmpty ? data.prices.last : null;
    if (lastPrice == null ||
        lastPrice.volume == null ||
        lastPrice.volume! < RuleParams.minDayTradingVolumeShares) {
      return null;
    }

    // 診斷日誌：記錄高當沖比例股票
    if (ratio >= DataFreshness.dayTradingHighRatio) {
      AppLogger.debug(
        'DayTradingRule',
        '${data.symbol}: 當沖比例=${ratio.toStringAsFixed(1)}%',
      );
    }

    // 當當沖比例超過高門檻時觸發
    if (ratio >= InstitutionalParams.dayTradingHighThreshold &&
        ratio < InstitutionalParams.dayTradingExtremeThreshold) {
      return TriggeredReason(
        type: ReasonType.dayTradingHigh,
        score: RuleScores.dayTradingHigh,
        description: '當沖比例 ${ratio.toStringAsFixed(1)}%',
        evidence: {'dayTradingRatio': ratio},
      );
    }

    return null;
  }
}

/// 規則：極高當沖比例
///
/// 當當沖比例極高時觸發（投機警示）
class DayTradingExtremeRule extends StockRule {
  const DayTradingExtremeRule();

  @override
  String get id => 'day_trading_extreme';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final marketData = context.marketData;
    if (marketData == null) return null;

    final ratio = marketData.dayTradingRatio;
    if (ratio == null) return null;

    // 過濾條件：成交量 >= 3 萬張（minDayTradingExtremeVolumeShares，30,000,000 股）
    final lastPrice = data.prices.isNotEmpty ? data.prices.last : null;
    if (lastPrice == null ||
        lastPrice.volume == null ||
        lastPrice.volume! < RuleParams.minDayTradingExtremeVolumeShares) {
      return null;
    }

    // 當當沖比例超過極端門檻時觸發
    if (ratio >= InstitutionalParams.dayTradingExtremeThreshold) {
      return TriggeredReason(
        type: ReasonType.dayTradingExtreme,
        score: RuleScores.dayTradingExtreme,
        description: '當沖比例極高 ${ratio.toStringAsFixed(1)}%(警示)',
        evidence: {'dayTradingRatio': ratio},
      );
    }

    return null;
  }
}

/// 規則：籌碼集中
///
/// 當大戶持股集中度超過門檻時觸發
class ConcentrationHighRule extends StockRule {
  const ConcentrationHighRule();

  @override
  String get id => 'concentration_high';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final marketData = context.marketData;
    if (marketData == null) return null;

    final ratio = marketData.concentrationRatio;
    if (ratio == null) return null;

    // 當籌碼集中度超過門檻時觸發
    if (ratio >= InstitutionalParams.concentrationHighThreshold) {
      return TriggeredReason(
        type: ReasonType.concentrationHigh,
        score: RuleScores.concentrationHigh,
        description: '大戶持股比例 ${ratio.toStringAsFixed(1)}%',
        evidence: {'concentrationRatio': ratio},
      );
    }

    return null;
  }
}

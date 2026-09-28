import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

// ==================================================
// 反轉規則
// ==================================================

/// 規則：弱轉強反轉
///
/// 當趨勢由下跌轉為上漲（底部型態確立）時觸發。
class WeakToStrongRule extends StockRule {
  const WeakToStrongRule();

  @override
  String get id => 'reversal_w2s';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (context.reversalState == ReversalState.weakToStrong) {
      return TriggeredReason(
        type: ReasonType.reversalW2S,
        score: RuleScores.reversalW2S,
        description: '底部型態確立 / 突破區間整理',
        evidence: {'trend': context.trendState.toString()},
      );
    }
    return null;
  }
}

/// 規則：強轉弱反轉
///
/// 當趨勢由上漲轉為下跌（頭部型態確立）時觸發。
class StrongToWeakRule extends StockRule {
  const StrongToWeakRule();

  @override
  String get id => 'reversal_s2w';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    // 轉弱判定刻意不設 MA20 過濾（只有轉強 W2S 有，見
    // TrendDetectionService.checkWeakToStrong）
    if (context.reversalState == ReversalState.strongToWeak) {
      return TriggeredReason(
        type: ReasonType.reversalS2W,
        score: RuleScores.reversalS2W,
        description: '頭部型態確立 / 跌破支撐',
        evidence: {'trend': context.trendState.toString()},
      );
    }
    return null;
  }
}

// ==================================================
// 突破/跌破規則
// ==================================================

/// 規則：向上突破
///
/// 當股價突破關鍵壓力位且有量能配合時觸發。
class BreakoutRule extends StockRule {
  const BreakoutRule();

  @override
  String get id => 'tech_breakout';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.isEmpty) return null;
    final today = data.prices.last;
    final close = today.close;
    if (close == null) return null;

    if (context.resistanceLevel != null) {
      // 使用突破緩衝區（TrendParams.breakoutBuffer = 3%）
      final breakoutLevel =
          context.resistanceLevel! * (1 + TrendParams.breakoutBuffer);
      if (close > breakoutLevel) {
        // MA20 過濾：需站上 MA20 才確認有效突破
        final ma20 = context.indicators?.ma20;
        if (ma20 != null && close < ma20) return null;

        // 成交量確認：需有量能配合
        if (!_hasBreakoutVolume(data.prices)) return null;

        return TriggeredReason(
          type: ReasonType.techBreakout,
          score: RuleScores.techBreakout,
          description: '突破關鍵壓力位',
          evidence: {
            'close': close,
            'resistance': context.resistanceLevel,
            'breakoutLevel': breakoutLevel,
          },
        );
      }
    }
    return null;
  }
}

/// 規則：向下跌破
///
/// 當股價跌破關鍵支撐位且有量能配合時觸發。
class BreakdownRule extends StockRule {
  const BreakdownRule();

  @override
  String get id => 'tech_breakdown';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.isEmpty) return null;
    final today = data.prices.last;
    final close = today.close;
    if (close == null) return null;

    double? support = context.supportLevel;
    if (support == null && data.prices.length >= RuleParams.volMa) {
      support = _calculate20DayLow(data.prices);
    }

    if (support != null) {
      // 使用跌破緩衝區（3%）
      final breakdownLevel = support * (1 - TrendParams.breakdownBuffer);
      if (close < breakdownLevel) {
        // 成交量確認：恐慌性下跌通常伴隨放量
        if (!_hasBreakdownVolume(data.prices)) return null;

        return TriggeredReason(
          type: ReasonType.techBreakdown,
          score: RuleScores.techBreakdown,
          description: '跌破關鍵支撐位',
          evidence: {
            'close': close,
            'support': support,
            'breakdownLevel': breakdownLevel,
          },
        );
      }
    }
    return null;
  }
}

/// 計算 volMa 日低點（排除今日）
double? _calculate20DayLow(List<DailyPriceEntry> prices) {
  if (prices.length < RuleParams.volMa) return null;

  double minLow = double.infinity;
  for (
    var i = prices.length - 2;
    i >= prices.length - (RuleParams.volMa + 1) && i >= 0;
    i--
  ) {
    final low = prices[i].low ?? prices[i].close ?? double.infinity;
    if (low > 0 && low < minLow) minLow = low;
  }

  return minLow == double.infinity ? null : minLow;
}

/// 檢查是否有跌破所需的成交量（空方）
///
/// 今日成交量需達 20 日均量的 1.5 倍（恐慌性下跌通常伴隨放量）
bool _hasBreakdownVolume(List<DailyPriceEntry> prices) =>
    _hasVolumeConfirmation(prices, TrendParams.reversalVolumeConfirm);

// ==================================================
// 輔助方法
// ==================================================

bool _hasBreakoutVolume(List<DailyPriceEntry> prices) =>
    _hasVolumeConfirmation(prices, TrendParams.reversalVolumeConfirm);

/// 今日成交量是否達到 20 日均量的指定倍數
bool _hasVolumeConfirmation(List<DailyPriceEntry> prices, double multiplier) {
  if (prices.length < RuleParams.volMa + 1) return true; // 資料不足則放行

  final todayVolume = prices.last.volume;
  if (todayVolume == null || todayVolume <= 0) return false;

  double sum = 0;
  int count = 0;

  for (
    var i = prices.length - 2;
    i >= prices.length - (RuleParams.volMa + 1) && i >= 0;
    i--
  ) {
    final vol = prices[i].volume;
    if (vol != null && vol > 0) {
      sum += vol;
      count++;
    }
  }

  if (count == 0) return true; // 無歷史資料則放行

  final avgVolume = sum / count;
  return todayVolume >= avgVolume * multiplier;
}

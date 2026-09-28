import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

// ==================================================
// K 線型態規則
// ==================================================

/// 判斷 K 棒是否為錘子/吊人形態
///
/// 錘子線與吊人線形狀相同：
/// - 下影線 >= 實體 * 2
/// - 上影線 <= 實體 * 0.5
/// - 實體 >= 振幅 * 5%
bool isHammerShape(DailyPriceEntry candle) {
  if (!candle.hasValidOHLC) return false;

  final range = candle.range;
  if (range == 0) return false;

  final body = candle.bodySize;
  if (body < range * PatternParams.hammerBodyMinRatio) return false;

  return candle.lowerShadow >=
          body * PatternParams.hammerLowerShadowMultiplier &&
      candle.upperShadow <= body * PatternParams.hammerUpperShadowMaxRatio;
}

/// 判斷是否為吞噬型態
///
/// [bullish] 為 true 表示多頭吞噬，false 表示空頭吞噬
/// - 多頭吞噬：前一日黑 K、今日紅 K，今日實體包覆前一日
/// - 空頭吞噬：前一日紅 K、今日黑 K，今日實體包覆前一日
bool isEngulfing(
  DailyPriceEntry today,
  DailyPriceEntry prev, {
  required bool bullish,
}) {
  if (!today.hasValidOpenClose || !prev.hasValidOpenClose) return false;

  if (bullish) {
    // 多頭吞噬：前一日空方 K 線，今日多方 K 線
    if (!prev.isBearish || !today.isBullish) return false;
    // 吞噬邏輯：今日開盤 <= 前日收盤 且 今日收盤 >= 前日開盤
    return today.open! <= prev.close! && today.close! >= prev.open!;
  } else {
    // 空頭吞噬：前一日多方 K 線，今日空方 K 線
    if (!prev.isBullish || !today.isBearish) return false;
    // 吞噬邏輯：今日開盤 >= 前日收盤 且 今日收盤 <= 前日開盤
    return today.open! >= prev.close! && today.close! <= prev.open!;
  }
}

/// 規則：十字線型態（市場猶豫不決）
class DojiRule extends StockRule {
  const DojiRule();

  @override
  String get id => 'pattern_doji';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.isEmpty) return null;
    final today = data.prices.last;

    if (_isDoji(today)) {
      // 需要 RSI 判定位置：無 RSI 時無法區分高低檔，跳過
      final rsi = context.indicators?.rsi;
      if (rsi == null) return null;
      // 只在極端區觸發；門檻值本身屬極端區（與 RSI 超買／超賣規則的
      // >=、<= 一致）。高低檔各判斷一次，過濾與分類共用，邊界不會分歧
      final isHigh = rsi >= IndicatorParams.rsiNeutralHigh;
      final isLow = rsi <= IndicatorParams.rsiExtremeOversold;
      if (!isHigh && !isLow) return null;

      // 根據位置給不同分數：高檔十字線偏空，低檔十字線偏多
      final isBearish = isHigh;
      final score = isBearish
          ? RuleScores.patternDojiBearish
          : RuleScores.patternDoji;
      final description = isBearish ? '高檔十字線（偏空警告）' : '低檔十字線（反轉訊號）';

      return TriggeredReason(
        type: isBearish
            ? ReasonType.patternDojiBearish
            : ReasonType.patternDoji,
        score: score,
        description: description,
        evidence: {
          'open': today.open,
          'close': today.close,
          'high': today.high,
          'low': today.low,
          'rsi': rsi,
        },
      );
    }
    return null;
  }

  bool _isDoji(DailyPriceEntry candle) {
    if (!candle.hasValidOHLC) return false;

    final range = candle.range;
    if (range == 0) return true; // 無波動為十字線

    // 實體小於總振幅的指定比例
    return candle.bodySize <= range * PatternParams.dojiBodyMaxRatio;
  }
}

/// 規則：多頭吞噬型態
class BullishEngulfingRule extends StockRule {
  const BullishEngulfingRule();

  @override
  String get id => 'pattern_bullish_engulfing';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 2) return null;

    // 僅在下跌趨勢或區間底部有效
    if (context.trendState == TrendState.up) return null;

    final today = data.prices.last;
    final yesterday = data.prices[data.prices.length - 2];

    if (isEngulfing(today, yesterday, bullish: true)) {
      // 過濾條件：成交量須 > 5 日均量的 1.5 倍（與空頭吞噬對稱）
      if (!PriceCalculator.isVolumeAboveAverage(
        data.prices,
        days: TrendParams.priceVolumeLookbackDays,
      )) {
        return null;
      }

      return TriggeredReason(
        type: ReasonType.patternBullishEngulfing,
        score: RuleScores.patternEngulfingBullish,
        description: '多頭吞噬型態 (一紅吃一黑)',
        evidence: {
          'today_open': today.open,
          'today_close': today.close,
          'prev_open': yesterday.open,
          'prev_close': yesterday.close,
        },
      );
    }
    return null;
  }
}

/// 規則：空頭吞噬型態
class BearishEngulfingRule extends StockRule {
  const BearishEngulfingRule();

  @override
  String get id => 'pattern_bearish_engulfing';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 2) return null;

    // 僅在上漲趨勢或區間頂部有效
    if (context.trendState == TrendState.down) return null;

    final today = data.prices.last;
    final yesterday = data.prices[data.prices.length - 2];

    if (isEngulfing(today, yesterday, bullish: false)) {
      // 過濾條件：成交量須 > 5 日均量的 1.5 倍
      if (!PriceCalculator.isVolumeAboveAverage(
        data.prices,
        days: TrendParams.priceVolumeLookbackDays,
      )) {
        return null;
      }

      return TriggeredReason(
        type: ReasonType.patternBearishEngulfing,
        score: RuleScores.patternEngulfingBearish,
        description: '空頭吞噬型態 (一黑吃一紅)',
        evidence: {
          'today_open': today.open,
          'today_close': today.close,
          'prev_open': yesterday.open,
          'prev_close': yesterday.close,
        },
      );
    }
    return null;
  }
}

/// 規則：錘子線（多方反轉訊號）
class HammerRule extends StockRule {
  const HammerRule();

  @override
  String get id => 'pattern_hammer';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.isEmpty) return null;
    // 僅在下跌或盤整趨勢有效（上漲趨勢的錘子形狀為吊人線，交由 HangingManRule）
    if (context.trendState == TrendState.up) return null;

    final today = data.prices.last;
    if (!isHammerShape(today)) return null;

    // 位置守衛（audit data #3）：錘子線為「低檔」反轉訊號，收盤須落在
    // 支撐-壓力區間的下半部（近支撐）。否則盤整區近壓力的錘子形狀會被誤判為
    // 「低檔錘子線」灌 +18 多方分。區間邊界未知時 permissive 不擋
    // （與 codebase null → 放行語意一致）。
    final close = today.close;
    final lower = context.supportLevel ?? context.rangeBottom;
    final upper = context.resistanceLevel ?? context.rangeTop;
    if (close != null && lower != null && upper != null && upper > lower) {
      final position = (close - lower) / (upper - lower);
      if (position > PatternParams.hammerMaxBandPosition) return null;
    }

    return TriggeredReason(
      type: ReasonType.patternHammer,
      score: RuleScores.patternHammerBullish,
      description: '低檔錘子線 (下影線長)',
      evidence: {
        'open': today.open,
        'close': today.close,
        'high': today.high,
        'low': today.low,
      },
    );
  }
}

/// 規則：吊人線（空方反轉訊號）
class HangingManRule extends StockRule {
  const HangingManRule();

  @override
  String get id => 'pattern_hanging_man';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.isEmpty) return null;
    // 吊人線為頭部反轉訊號，必須嚴格處於上漲趨勢
    if (context.trendState != TrendState.up) return null;

    final today = data.prices.last;
    // 吊人線與錘子線形狀相同，但出現在頂部
    if (isHammerShape(today)) {
      return TriggeredReason(
        type: ReasonType.patternHangingMan,
        score: RuleScores.patternHammerBearish,
        description: '高檔吊人線 (需確認)',
        evidence: {
          'open': today.open,
          'close': today.close,
          'high': today.high,
          'low': today.low,
        },
      );
    }
    return null;
  }
}

/// 規則：向上跳空缺口（多方訊號）
class GapUpRule extends StockRule {
  const GapUpRule();

  @override
  String get id => 'pattern_gap_up';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 2) return null;

    // 趨勢過濾：下跌趨勢中的跳空上漲可能只是技術反彈
    if (context.trendState == TrendState.down) return null;

    final today = data.prices.last;
    final prev = data.prices[data.prices.length - 2];

    if (today.low == null || prev.high == null || prev.close == null) {
      return null;
    }

    final gapSize = today.low! - prev.high!;
    final threshold = prev.close! * PatternParams.gapMinThreshold;

    if (gapSize > 0 && gapSize >= threshold) {
      return TriggeredReason(
        type: ReasonType.patternGapUp,
        score: RuleScores.patternGapUp,
        description: '向上跳空缺口',
        evidence: {
          'today_low': today.low,
          'prev_high': prev.high,
          'gap': gapSize,
        },
      );
    }
    return null;
  }
}

/// 規則：向下跳空缺口（空方訊號）
class GapDownRule extends StockRule {
  const GapDownRule();

  @override
  String get id => 'pattern_gap_down';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 2) return null;

    // 趨勢過濾：上漲趨勢中的跳空下跌可能只是正常回調
    if (context.trendState == TrendState.up) return null;

    final today = data.prices.last;
    final prev = data.prices[data.prices.length - 2];

    if (today.high == null || prev.low == null || prev.close == null) {
      return null;
    }

    final gapSize = prev.low! - today.high!;
    final threshold = prev.close! * PatternParams.gapMinThreshold;

    if (gapSize > 0 && gapSize >= threshold) {
      return TriggeredReason(
        type: ReasonType.patternGapDown,
        score: RuleScores.patternGapDown,
        description: '向下跳空缺口',
        evidence: {
          'today_high': today.high,
          'prev_low': prev.low,
          'gap': gapSize,
        },
      );
    }
    return null;
  }
}

/// 判斷是否為星線型態
///
/// [bullish] 為 true 表示晨星（多頭反轉），false 表示暮星（空頭反轉）
/// - 晨星：長黑 K + 小實體（靠近底部）+ 長紅 K 收在中點上
/// - 暮星：長紅 K + 小實體（靠近頂部）+ 長黑 K 收在中點下
///
/// 第二根 K 線（星體）必須小實體，第三根必須收過第一根中點。
bool isStarPattern(
  DailyPriceEntry c1,
  DailyPriceEntry c2,
  DailyPriceEntry c3, {
  required bool bullish,
}) {
  if (!c1.hasValidOpenClose || !c2.hasValidOpenClose || !c3.hasValidOpenClose) {
    return false;
  }

  final c1Body = c1.bodySize;

  // 第二根 K 線：小實體（星線）
  if (c2.bodySize > c1Body * PatternParams.starSmallBodyMaxRatio) return false;

  final c1Mid = (c1.open! + c1.close!) / 2;
  final c2Mid = (c2.open! + c2.close!) / 2;

  if (bullish) {
    // 晨星：第一根長黑 K
    if (!c1.isBearish) return false;

    // 不強制要求跳空
    if (c2Mid > c1.close! * PatternParams.starGapToleranceUpper) return false;

    // 第三根長紅 K，收盤高於第一根中點
    if (!c3.isBullish) return false;
    if (c3.close! < c1Mid) return false;
  } else {
    // 暮星：第一根長紅 K
    if (!c1.isBullish) return false;

    // 不強制要求跳空
    if (c2Mid < c1.close! * PatternParams.starGapToleranceLower) return false;

    // 第三根長黑 K，收盤低於第一根中點
    if (!c3.isBearish) return false;
    if (c3.close! > c1Mid) return false;
  }

  return true;
}

/// 規則：晨星型態（多方反轉訊號）
class MorningStarRule extends StockRule {
  const MorningStarRule();

  @override
  String get id => 'pattern_morning_star';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 3) return null;
    if (context.trendState == TrendState.up) return null;

    final c3 = data.prices.last;
    final c2 = data.prices[data.prices.length - 2];
    final c1 = data.prices[data.prices.length - 3];

    if (isStarPattern(c1, c2, c3, bullish: true)) {
      return TriggeredReason(
        type: ReasonType.patternMorningStar,
        score: RuleScores.patternMorningStar,
        description: '晨星型態 (底部反轉)',
        evidence: {
          'c1_close': c1.close,
          'c2_close': c2.close,
          'c3_close': c3.close,
        },
      );
    }
    return null;
  }
}

/// 規則：暮星型態（空方反轉訊號）
class EveningStarRule extends StockRule {
  const EveningStarRule();

  @override
  String get id => 'pattern_evening_star';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 3) return null;
    if (context.trendState == TrendState.down) return null;

    final c3 = data.prices.last;
    final c2 = data.prices[data.prices.length - 2];
    final c1 = data.prices[data.prices.length - 3];

    if (isStarPattern(c1, c2, c3, bullish: false)) {
      return TriggeredReason(
        type: ReasonType.patternEveningStar,
        score: RuleScores.patternEveningStar,
        description: '暮星型態 (頭部反轉)',
        evidence: {
          'c1_close': c1.close,
          'c2_close': c2.close,
          'c3_close': c3.close,
        },
      );
    }
    return null;
  }
}

/// 規則：紅三兵型態（強勢多方訊號）
class ThreeWhiteSoldiersRule extends StockRule {
  const ThreeWhiteSoldiersRule();

  @override
  String get id => 'pattern_three_white_soldiers';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 3) return null;

    final c3 = data.prices.last;
    final c2 = data.prices[data.prices.length - 2];
    final c1 = data.prices[data.prices.length - 3];

    if (context.trendState == TrendState.up) return null;

    if (_isThreeWhiteSoldiers(c1, c2, c3)) {
      return TriggeredReason(
        type: ReasonType.patternThreeWhiteSoldiers,
        score: RuleScores.patternThreeWhiteSoldiers,
        description: '紅三兵型態 (強勢上攻)',
        evidence: {
          'c1_close': c1.close,
          'c2_close': c2.close,
          'c3_close': c3.close,
        },
      );
    }
    return null;
  }

  bool _isThreeWhiteSoldiers(
    DailyPriceEntry c1,
    DailyPriceEntry c2,
    DailyPriceEntry c3,
  ) {
    if (!c1.hasValidOpenClose ||
        !c2.hasValidOpenClose ||
        !c3.hasValidOpenClose) {
      return false;
    }

    // 三根 K 線皆為紅 K
    if (!c1.isBullish || !c2.isBullish || !c3.isBullish) return false;

    // 每根 K 線實體比例須 >= 門檻，避免微小漲幅誤觸發
    for (final c in [c1, c2, c3]) {
      final bodyRatio = (c.close! - c.open!).abs() / c.close!;
      if (bodyRatio < PatternParams.threeLineMinBodyRatio) return false;
    }

    // 連續創高收盤
    if (c2.close! <= c1.close!) return false;
    if (c3.close! <= c2.close!) return false;

    return true;
  }
}

/// 規則：三黑鴉型態（強勢空方訊號）
class ThreeBlackCrowsRule extends StockRule {
  const ThreeBlackCrowsRule();

  @override
  String get id => 'pattern_three_black_crows';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < 3) return null;
    if (context.trendState == TrendState.down) return null;

    final c3 = data.prices.last;
    final c2 = data.prices[data.prices.length - 2];
    final c1 = data.prices[data.prices.length - 3];

    if (_isThreeBlackCrows(c1, c2, c3)) {
      return TriggeredReason(
        type: ReasonType.patternThreeBlackCrows,
        score: RuleScores.patternThreeBlackCrows,
        description: '三黑鴉型態 (連續下跌)',
        evidence: {
          'c1_close': c1.close,
          'c2_close': c2.close,
          'c3_close': c3.close,
        },
      );
    }
    return null;
  }

  bool _isThreeBlackCrows(
    DailyPriceEntry c1,
    DailyPriceEntry c2,
    DailyPriceEntry c3,
  ) {
    if (!c1.hasValidOpenClose ||
        !c2.hasValidOpenClose ||
        !c3.hasValidOpenClose) {
      return false;
    }

    // 三根 K 線皆為黑 K
    if (!c1.isBearish || !c2.isBearish || !c3.isBearish) return false;

    // 每根 K 線實體比例須 >= 門檻，避免微小跌幅誤觸發
    for (final c in [c1, c2, c3]) {
      final bodyRatio = (c.open! - c.close!).abs() / c.close!;
      if (bodyRatio < PatternParams.threeLineMinBodyRatio) return false;
    }

    // 連續創低收盤
    if (c2.close! >= c1.close!) return false;
    if (c3.close! >= c2.close!) return false;

    return true;
  }
}

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

// ==================================================
// 第 5 階段：價量背離規則
// ==================================================

/// 規則：價漲量縮
///
/// 價格上漲但成交量萎縮 - 警示訊號
class PriceVolumeWeakRallyRule extends StockRule {
  const PriceVolumeWeakRallyRule();

  @override
  String get id => 'price_volume_bullish_divergence';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < TrendParams.priceVolumeLookbackDays + 1) {
      return null;
    }

    const lookback = TrendParams.priceVolumeLookbackDays;
    final recentPrices = data.prices.reversed.take(lookback + 1).toList();

    final todayClose = recentPrices[0].close;
    final pastClose = recentPrices[lookback].close;
    final todayVolume = recentPrices[0].volume;

    if (todayClose == null ||
        pastClose == null ||
        pastClose == 0 ||
        todayVolume == null) {
      return null;
    }

    // 回溯期均量:接現成 helper(2026-08-15 審計——skipLast+filterZero
    // 與原 inline 迴圈逐位元等價:排除今日、取 lookback 日、濾停牌)
    final avgVolume = PriceCalculator.calculateAverageVolume(
      data.prices,
      days: lookback,
      skipLast: true,
      filterZero: true,
    );
    if (avgVolume == null) return null;

    // 檢查背離
    final priceChange = (todayClose - pastClose) / pastClose * 100;
    final volumeChange = (todayVolume - avgVolume) / avgVolume * 100;

    // 價格上漲但成交量下降
    // 原先：1.5% 價格 / -15% 成交量（仍過於嚴格）
    // 目前：1.0% 價格 / -10% 成交量
    if (priceChange >= TrendParams.divergencePriceThreshold &&
        volumeChange <= -TrendParams.divergenceVolumeThreshold) {
      AppLogger.debug(
        'PriceVolumeWeakRally',
        '${data.symbol}: 價漲${priceChange.toStringAsFixed(1)}%, 量縮${volumeChange.toStringAsFixed(1)}%',
      );
      return TriggeredReason(
        type: ReasonType.priceVolumeWeakRally,
        score: RuleScores.priceVolumeWeakRally,
        description:
            '價漲量縮：價格上漲${priceChange.toStringAsFixed(1)}%，成交量萎縮${volumeChange.abs().toStringAsFixed(0)}%',
        evidence: {
          'priceChange': priceChange,
          'volumeChange': volumeChange,
          'todayVolume': todayVolume,
          'avgVolume': avgVolume,
        },
      );
    }

    return null;
  }
}

/// 規則：價跌量增
///
/// 價格下跌且成交量增加 - 恐慌訊號
class PriceVolumeBearishDivergenceRule extends StockRule {
  const PriceVolumeBearishDivergenceRule();

  @override
  String get id => 'price_volume_bearish_divergence';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < TrendParams.priceVolumeLookbackDays + 1) {
      return null;
    }

    const lookback = TrendParams.priceVolumeLookbackDays;
    final recentPrices = data.prices.reversed.take(lookback + 1).toList();

    final todayClose = recentPrices[0].close;
    final pastClose = recentPrices[lookback].close;
    final todayVolume = recentPrices[0].volume;

    if (todayClose == null ||
        pastClose == null ||
        pastClose == 0 ||
        todayVolume == null) {
      return null;
    }

    // 回溯期均量:接現成 helper(2026-08-15 審計——skipLast+filterZero
    // 與原 inline 迴圈逐位元等價:排除今日、取 lookback 日、濾停牌)
    final avgVolume = PriceCalculator.calculateAverageVolume(
      data.prices,
      days: lookback,
      skipLast: true,
      filterZero: true,
    );
    if (avgVolume == null) return null;

    final priceChange = (todayClose - pastClose) / pastClose * 100;
    final volumeChange = (todayVolume - avgVolume) / avgVolume * 100;

    // 價格下跌且成交量上升
    // 原先：-1.5% 價格 / +15% 成交量（仍過於嚴格）
    // 目前：-1.0% 價格 / +10% 成交量
    if (priceChange <= -TrendParams.divergencePriceThreshold &&
        volumeChange >= TrendParams.divergenceVolumeThreshold) {
      AppLogger.debug(
        'PriceVolumeBearishDivergence',
        '${data.symbol}: 價跌${priceChange.toStringAsFixed(1)}%, 量增${volumeChange.toStringAsFixed(1)}%',
      );
      return TriggeredReason(
        type: ReasonType.priceVolumeBearishDivergence,
        score: RuleScores.priceVolumeBearishDivergence,
        description:
            '價跌量增：價格下跌${priceChange.abs().toStringAsFixed(1)}%，成交量放大${volumeChange.toStringAsFixed(0)}%',
        evidence: {
          'priceChange': priceChange,
          'volumeChange': volumeChange,
          'todayVolume': todayVolume,
          'avgVolume': avgVolume,
        },
      );
    }

    return null;
  }
}

/// 規則：高檔爆量
///
/// 價格處於高檔且成交量暴增
class HighVolumeBreakoutRule extends StockRule {
  const HighVolumeBreakoutRule();

  @override
  String get id => 'high_volume_breakout';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < RuleParams.rangeLookback) return null;

    final today = data.prices.last;
    final close = today.close;
    final volume = today.volume;

    if (close == null || volume == null) return null;

    // 計算 60 日區間
    double maxHigh = 0;
    double minLow = double.infinity;
    double volumeSum = 0;
    int volumeCount = 0;

    for (
      int i = data.prices.length - RuleParams.rangeLookback;
      i < data.prices.length - 1;
      i++
    ) {
      final p = data.prices[i];
      final high = p.high ?? p.close ?? 0;
      final low = p.low ?? p.close ?? double.infinity;
      final vol = p.volume ?? 0;

      if (high > maxHigh) maxHigh = high;
      if (low > 0 && low < minLow) minLow = low;
      if (vol > 0) {
        volumeSum += vol;
        volumeCount++;
      }
    }

    if (maxHigh <= minLow || volumeCount == 0) return null;

    final range = maxHigh - minLow;
    final position = (close - minLow) / range; // 0 = 低點, 1 = 高點
    final avgVolume = volumeSum / volumeCount;

    // 高檔位置（前 15%）且成交量暴增（4 倍）
    if (position >= TrendParams.highPositionThreshold &&
        volume >= avgVolume * TrendParams.volumeSpikeMult) {
      return TriggeredReason(
        type: ReasonType.highVolumeBreakout,
        score: RuleScores.highVolumeBreakout,
        description: '高檔爆量突破',
        evidence: {
          'position': position,
          'volumeMultiple': volume / avgVolume,
          'close': close,
          'rangeHigh': maxHigh,
        },
      );
    }

    return null;
  }
}

/// 規則：低檔吸籌
///
/// 價格處於低檔且成交量萎縮 - 可能正在吸籌
class LowVolumeAccumulationRule extends StockRule {
  const LowVolumeAccumulationRule();

  @override
  String get id => 'low_volume_accumulation';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < RuleParams.rangeLookback) return null;

    final today = data.prices.last;
    final close = today.close;
    final volume = today.volume;

    if (close == null || volume == null) return null;

    double maxHigh = 0;
    double minLow = double.infinity;
    double volumeSum = 0;
    int volumeCount = 0;

    for (
      int i = data.prices.length - RuleParams.rangeLookback;
      i < data.prices.length - 1;
      i++
    ) {
      final p = data.prices[i];
      final high = p.high ?? p.close ?? 0;
      final low = p.low ?? p.close ?? double.infinity;
      final vol = p.volume ?? 0;

      if (high > maxHigh) maxHigh = high;
      if (low > 0 && low < minLow) minLow = low;
      if (vol > 0) {
        volumeSum += vol;
        volumeCount++;
      }
    }

    if (maxHigh <= minLow || volumeCount == 0) return null;

    final range = maxHigh - minLow;
    final position = (close - minLow) / range;
    final avgVolume = volumeSum / volumeCount;

    // 低檔位置（後 25%）且成交量低迷（低於平均的 60%）
    if (position <= TrendParams.lowPositionThreshold &&
        volume < avgVolume * TrendParams.lowAccumulationVolumeRatio) {
      AppLogger.debug(
        'LowVolumeAccumulation',
        '${data.symbol}: 位置=${(position * 100).toStringAsFixed(1)}%, 量比=${(volume / avgVolume * 100).toStringAsFixed(0)}%',
      );
      return TriggeredReason(
        type: ReasonType.lowVolumeAccumulation,
        score: RuleScores.lowVolumeAccumulation,
        description: '低檔縮量整理',
        evidence: {
          'position': position,
          'volumeRatio': volume / avgVolume,
          'close': close,
          'rangeLow': minLow,
        },
      );
    }

    return null;
  }
}

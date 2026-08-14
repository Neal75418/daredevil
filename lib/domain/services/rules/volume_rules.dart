import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

/// 規則：放量異常
///
/// 當成交量超過均量 N 倍且伴隨價格變動時觸發
class VolumeSpikeRule extends StockRule {
  const VolumeSpikeRule();

  @override
  String get id => 'volume_spike';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    if (data.prices.length < RuleParams.volMa + 1) return null;

    final today = data.prices.last;
    final todayVolume = today.volume;

    if (todayVolume == null || todayVolume <= 0) return null;

    // 檢查最小價格變動（+/- 1.5%）
    // 單純放量無價格配合的意義較低
    final todayClose = today.close;
    final yesterday = data.prices[data.prices.length - 2];
    final yesterdayClose = yesterday.close;

    if (todayClose != null && yesterdayClose != null && yesterdayClose > 0) {
      final pctChange = ((todayClose - yesterdayClose) / yesterdayClose).abs();
      if (pctChange < TrendParams.minPriceChangeForVolume) return null;
    }

    // MA20 均量:接現成 helper(2026-08-15 審計——排除今日、濾停牌、
    // 近 20 日須至少 minValidDays 個有效交易日,與原 inline 等價)
    final avgVolume = PriceCalculator.calculateAverageVolume(
      data.prices,
      days: RuleParams.volMa,
      skipLast: true,
      filterZero: true,
      minValidDays: (RuleParams.volMa * RuleParams.volMaMinValidDayRatio)
          .floor(),
    );
    if (avgVolume == null) return null;

    // 檢查門檻（均量的 4 倍）
    if (avgVolume > 0 &&
        todayVolume >= avgVolume * TrendParams.volumeSpikeMult) {
      return TriggeredReason(
        type: ReasonType.volumeSpike,
        score: RuleScores.volumeSpike,
        description: '成交量異常放大 ${TrendParams.volumeSpikeMult} 倍以上',
        evidence: {
          'volume': todayVolume,
          'avgVolume': avgVolume,
          'multiple': todayVolume / avgVolume,
        },
      );
    }

    return null;
  }
}

/// 規則：價格急漲
///
/// 當單日漲幅超過 [TrendParams.priceSpikePercent]（5%）且伴隨
/// [TrendParams.priceSpikeVolumeMult]（1.5 倍）均量配合時觸發。
///
/// **2026-07-18 修正（audit）**：原本用 `pctChange.abs()` 判斷，重挫日會
/// 跟急漲日拿到相同的 +15 強勢分——36 次重挫觸發中 33% 為負報酬。收斂為
/// 僅正向觸發；空方已由 PriceVolumeBearishDivergenceRule（量增價跌）與
/// BreakdownRule（跌破支撐）覆蓋，不另闢負分 reason type。
class PriceSpikeRule extends StockRule {
  const PriceSpikeRule();

  @override
  String get id => 'price_spike';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    // 需要足夠歷史資料計算均量
    if (data.prices.length < RuleParams.volMa + 1) return null;

    final today = data.prices.last;
    final yesterday = data.prices[data.prices.length - 2];

    final todayClose = today.close;
    final yesterdayClose = yesterday.close;
    final todayVolume = today.volume;

    if (todayClose == null || yesterdayClose == null || yesterdayClose <= 0) {
      return null;
    }

    final pctChange = ((todayClose - yesterdayClose) / yesterdayClose) * 100;

    // 僅正向（急漲）觸發，下跌不再計分（見上方 class doc 的 audit 說明）。
    if (pctChange < TrendParams.priceSpikePercent) {
      return null;
    }

    // 成交量確認：過濾無量異動
    if (todayVolume == null || todayVolume <= 0) return null;

    // MA20 均量:接現成 helper(2026-08-15 審計——排除今日、濾停牌、
    // 近 20 日須至少 minValidDays 個有效交易日,與原 inline 等價)
    final avgVolume = PriceCalculator.calculateAverageVolume(
      data.prices,
      days: RuleParams.volMa,
      skipLast: true,
      filterZero: true,
      minValidDays: (RuleParams.volMa * RuleParams.volMaMinValidDayRatio)
          .floor(),
    );
    if (avgVolume == null) return null;

    // 成交量需達均量 1.5 倍以上
    if (avgVolume <= 0 ||
        todayVolume < avgVolume * TrendParams.priceSpikeVolumeMult) {
      return null;
    }

    final volumeMultiple = todayVolume / avgVolume;

    return TriggeredReason(
      type: ReasonType.priceSpike,
      score: RuleScores.priceSpike,
      description:
          '股價單日漲幅超過 ${TrendParams.priceSpikePercent}%，量增 ${volumeMultiple.toStringAsFixed(1)} 倍',
      evidence: {
        'pctChange': pctChange,
        'close': todayClose,
        'prevClose': yesterdayClose,
        'volume': todayVolume,
        'avgVolume': avgVolume,
        'volumeMultiple': volumeMultiple,
      },
    );
  }
}

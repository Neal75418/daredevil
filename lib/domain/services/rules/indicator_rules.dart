import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_adjuster.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/domain/services/price_continuity.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

// ==================================================
// 第 3 階段：技術訊號規則
// ==================================================

/// 52 週規則不評估的原因（每輪觀測計數用）
enum Week52Block {
  /// 窗口內除權除息資料不完整（含缺價格）
  incomplete,

  /// 還原後仍有水位斷點（減資、分割、面額變更等不在除權除息列表的事件）
  discontinuity,
}

/// 52 週新高／新低用的還原價格與閘門，規則與每輪觀測共用同一個判斷：
///
/// - 不足 [IndicatorParams.week52Days] 根：兩者皆 null（規則本來就不評估，
///   不計入觀測）
/// - 股利情境不完整：block 為 [Week52Block.incomplete]
/// - 以交易所除權息參考價還原（[DividendAdjuster]，截止日＝最後一根的日期，
///   評分時由候選資格保證它就是評分日）後仍有水位斷點：block 為
///   [Week52Block.discontinuity]
/// - 其餘：adjusted 為還原後的整段價格
({List<DailyPriceEntry>? adjusted, Week52Block? block}) week52AdjustedPrices(
  StockData data,
) {
  if (data.prices.length < IndicatorParams.week52Days) {
    return (adjusted: null, block: null);
  }
  final dividends = data.dividends;
  if (dividends is! DividendComplete) {
    return (adjusted: null, block: Week52Block.incomplete);
  }
  final adjusted = DividendAdjuster.adjust(
    data.prices,
    dividends.events,
    asOf: data.prices.last.date,
  );
  if (adjusted.contiguousSuffix().length < adjusted.length) {
    return (adjusted: null, block: Week52Block.discontinuity);
  }
  return (adjusted: adjusted, block: null);
}

/// 52 週新高/新低的方向
enum _Week52Direction { high, low }

/// [series] 排除最後一根（今日）的極值與有效根數；沒有有效值時回 null
({double value, int validCount})? _week52Extreme(
  List<DailyPriceEntry> series, {
  required bool isHigh,
}) {
  double? extreme;
  var validCount = 0;
  for (var i = 0; i < series.length - 1; i++) {
    final p = series[i];
    final value = isHigh ? (p.high ?? p.close) : (p.low ?? p.close);
    if (value == null || value <= 0) continue;
    validCount++;
    if (extreme == null || (isHigh ? value > extreme : value < extreme)) {
      extreme = value;
    }
  }
  return extreme == null ? null : (value: extreme, validCount: validCount);
}

/// 52 週新高/新低規則的共用基底類別
///
/// 極值以 [week52AdjustedPrices] 還原後的價格計算（2026-10 起；之前從極值扣掉
/// 窗內現金股利，但除息日幾乎全空，扣除額幾乎為 0），evidence 同時保留原始
/// 極值。股利資料不完整或還原後仍有水位斷點時不觸發。
abstract class _Week52RuleBase extends StockRule {
  const _Week52RuleBase({
    required _Week52Direction direction,
    required String ruleId,
    required String ruleName,
    required ReasonType reasonType,
    required int ruleScore,
    required double threshold,
  }) : _direction = direction,
       _ruleId = ruleId,
       _ruleName = ruleName,
       _reasonType = reasonType,
       _ruleScore = ruleScore,
       _threshold = threshold;

  final _Week52Direction _direction;
  final String _ruleId;
  final String _ruleName;
  final ReasonType _reasonType;
  final int _ruleScore;
  final double _threshold;

  @override
  String get id => _ruleId;

  /// 子類別可覆寫以加入額外過濾條件（例如 MA 空頭確認）；[adjusted] 是還原後
  /// 的整段價格。回傳 true 表示應過濾掉（不觸發）。
  bool additionalFilter(
    String symbol,
    List<DailyPriceEntry> adjusted,
    double close,
  ) => false;

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final isHigh = _direction == _Week52Direction.high;

    // 診斷：資料不足時記錄
    if (data.prices.length < IndicatorParams.week52Days) {
      if (data.prices.length >= IndicatorParams.historicalDataMinDays) {
        AppLogger.debug(
          _ruleName,
          '${data.symbol}: 資料不足 (${data.prices.length}/${IndicatorParams.week52Days})',
        );
      }
      return null;
    }

    final close = data.prices.last.close;
    if (close == null) return null;

    final adjusted = week52AdjustedPrices(data).adjusted;
    if (adjusted == null) return null;

    // 從「過去」的價格歷史計算 52 週極值（排除今日），避免前瞻偏差
    final adj = _week52Extreme(adjusted, isHigh: isHigh);
    if (adj == null || adj.validCount < IndicatorParams.week52MinValidBars) {
      return null;
    }
    // 還原只乘正數因子、不改變哪幾根有效，所以原始極值必有值
    final raw = _week52Extreme(data.prices, isHigh: isHigh)!;

    // 收盤是否處於或接近還原後的 52 週極值（在門檻範圍內）；今日不受任何
    // 事件影響，收盤就是還原後的收盤
    final extreme = adj.value;
    final thresholdPrice = isHigh
        ? extreme * (1 - _threshold)
        : extreme * (1 + _threshold);
    final isInRange = isHigh
        ? close >= thresholdPrice
        : close <= thresholdPrice;
    if (!isInRange) return null;

    // 子類別額外過濾（例如 Week52Low 的 MA 空頭趨勢確認）
    if (additionalFilter(data.symbol, adjusted, close)) return null;

    final isNew = isHigh ? close >= extreme : close <= extreme;
    final extremeLabel = isHigh ? '高' : '低';
    AppLogger.debug(
      _ruleName,
      '${data.symbol}: 收盤=${close.toStringAsFixed(2)}, '
      '52週$extremeLabel=${raw.value.toStringAsFixed(2)}, '
      '還原後=${extreme.toStringAsFixed(2)}, '
      '新$extremeLabel=$isNew',
    );
    return TriggeredReason(
      type: _reasonType,
      score: _ruleScore,
      description: isNew ? '創 52 週新$extremeLabel' : '接近 52 週新$extremeLabel',
      evidence: {
        'close': close,
        if (isHigh) 'week52High': raw.value else 'week52Low': raw.value,
        if (isHigh) 'adjustedHigh': extreme else 'adjustedLow': extreme,
        'dividendAdjustment': raw.value - extreme,
        if (isHigh) 'isNewHigh': isNew else 'isNewLow': isNew,
      },
    );
  }
}

/// 規則：52 週新高偵測
///
/// 當收盤價處於或接近 52 週高點時觸發
class Week52HighRule extends _Week52RuleBase {
  const Week52HighRule()
    : super(
        direction: _Week52Direction.high,
        ruleId: 'week_52_high',
        ruleName: '52週新高',
        reasonType: ReasonType.week52High,
        ruleScore: RuleScores.week52High,
        threshold: IndicatorParams.week52HighThreshold,
      );
}

/// 規則：52 週新低偵測
///
/// 當收盤價處於或接近 52 週低點時觸發
class Week52LowRule extends _Week52RuleBase {
  const Week52LowRule()
    : super(
        direction: _Week52Direction.low,
        ruleId: 'week_52_low',
        ruleName: '52週新低',
        reasonType: ReasonType.week52Low,
        ruleScore: RuleScores.week52Low,
        threshold: IndicatorParams.week52LowThreshold,
      );

  /// 精準度過濾：確認近期確實處於下跌趨勢，避免長期盤整在低檔區的股票誤觸發。
  /// 均線以還原後收盤計算——原始價格的 MA60 含除權息前的較高價格，除權息的
  /// 跳空會讓「收盤 < MA20 < MA60」看似成立
  @override
  bool additionalFilter(
    String symbol,
    List<DailyPriceEntry> adjusted,
    double close,
  ) {
    final ma20 = TechnicalIndicatorService.latestSMA(adjusted, 20);
    final ma60 = TechnicalIndicatorService.latestSMA(adjusted, 60);

    // 過濾條件：收盤價 < MA20 且 MA20 < MA60（空頭趨勢確認）
    if (ma20 != null && ma60 != null) {
      if (close >= ma20 || ma20 >= ma60) {
        AppLogger.debug(
          _ruleName,
          '$symbol: 過濾（未確認空頭趨勢 close=$close, MA20=$ma20, MA60=$ma60）',
        );
        return true;
      }
    }
    return false;
  }
}

/// 規則：均線多頭排列
///
/// 當 MA5 > MA10 > MA20 > MA60 時觸發
class MAAlignmentBullishRule extends StockRule {
  const MAAlignmentBullishRule();

  @override
  String get id => 'ma_alignment_bullish';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    // 至少需要最大均線週期的資料
    final maxPeriod = IndicatorParams.maAlignmentPeriods.reduce(
      (a, b) => a > b ? a : b,
    );
    if (data.prices.length < maxPeriod) return null;

    final ma5 = context.indicators?.ma5;
    final ma10 = context.indicators?.ma10;
    final ma20 = context.indicators?.ma20;
    final ma60 = context.indicators?.ma60;

    if (ma5 == null || ma10 == null || ma20 == null || ma60 == null) {
      return null;
    }

    // 檢查多頭排列：MA5 > MA10 > MA20 > MA60
    // 並檢查最小間距
    const minSep = IndicatorParams.maMinSeparation;
    if (ma5 > ma10 * (1 + minSep) &&
        ma10 > ma20 * (1 + minSep) &&
        ma20 > ma60 * (1 + minSep)) {
      // 過濾條件：收盤 > MA5 且乖離率不超過門檻
      // 備註：台股常有「量縮上漲」現象
      final today = data.prices.last;
      final close = today.close;
      final vol = today.volume;
      if (close == null || vol == null || vol <= 0) return null;

      if (close <= ma5) return null;
      if ((close - ma5) / ma5 >= IndicatorParams.maDeviationThreshold) {
        return null;
      }

      // 無 MA20 資料時跳過量能過濾（資料不足不應否定 MA pattern）
      final volMA20 = context.indicators?.volumeMA20;
      if (volMA20 != null &&
          vol <= volMA20 * IndicatorParams.maAlignmentVolumeMultiplier) {
        return null;
      }

      return TriggeredReason(
        type: ReasonType.maAlignmentBullish,
        score: RuleScores.maAlignmentBullish,
        description: '均線多頭排列 (5>10>20>60)',
        evidence: {'ma5': ma5, 'ma10': ma10, 'ma20': ma20, 'ma60': ma60},
      );
    }

    return null;
  }
}

/// 規則：均線空頭排列
///
/// 當 MA5 < MA10 < MA20 < MA60 時觸發
class MAAlignmentBearishRule extends StockRule {
  const MAAlignmentBearishRule();

  @override
  String get id => 'ma_alignment_bearish';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    // 至少需要最大均線週期的資料
    final maxPeriod = IndicatorParams.maAlignmentPeriods.reduce(
      (a, b) => a > b ? a : b,
    );
    if (data.prices.length < maxPeriod) return null;

    final ma5 = context.indicators?.ma5;
    final ma10 = context.indicators?.ma10;
    final ma20 = context.indicators?.ma20;
    final ma60 = context.indicators?.ma60;

    if (ma5 == null || ma10 == null || ma20 == null || ma60 == null) {
      return null;
    }

    // 檢查空頭排列：MA5 < MA10 < MA20 < MA60
    const minSep = IndicatorParams.maMinSeparation;
    if (ma5 < ma10 * (1 - minSep) &&
        ma10 < ma20 * (1 - minSep) &&
        ma20 < ma60 * (1 - minSep)) {
      // 移除成交量過濾，讓更多股票能觸發
      final today = data.prices.last;
      final close = today.close;
      if (close == null) return null;

      if (close >= ma5) return null;
      if ((close - ma5) / ma5 <= -IndicatorParams.maDeviationThreshold) {
        return null;
      }

      return TriggeredReason(
        type: ReasonType.maAlignmentBearish,
        score: RuleScores.maAlignmentBearish,
        description: '均線空頭排列 (5<10<20<60)',
        evidence: {'ma5': ma5, 'ma10': ma10, 'ma20': ma20, 'ma60': ma60},
      );
    }

    return null;
  }
}

/// 規則：RSI 極度超買
///
/// 當 RSI >= 85 時觸發（高風險警示）
class RSIExtremeOverboughtRule extends StockRule {
  const RSIExtremeOverboughtRule();

  @override
  String get id => 'rsi_extreme_overbought';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final rsi = context.indicators?.rsi;
    if (rsi == null) return null;

    if (rsi >= IndicatorParams.rsiExtremeOverbought) {
      AppLogger.debug(
        'RSIExtremeOverbought',
        '${data.symbol}: RSI=${rsi.toStringAsFixed(1)} >= ${IndicatorParams.rsiExtremeOverbought}',
      );
      return TriggeredReason(
        type: ReasonType.rsiExtremeOverbought,
        score: RuleScores.rsiExtremeOverboughtSignal,
        description: 'RSI 極度超買 (${rsi.toStringAsFixed(1)})',
        evidence: {
          'rsi': rsi,
          'threshold': IndicatorParams.rsiExtremeOverbought,
        },
      );
    }

    return null;
  }
}

/// 規則：RSI 極度超賣
///
/// 當 RSI <= 30 時觸發（潛在反彈機會）
class RSIExtremeOversoldRule extends StockRule {
  const RSIExtremeOversoldRule();

  @override
  String get id => 'rsi_extreme_oversold';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final rsi = context.indicators?.rsi;
    if (rsi == null) return null;

    if (rsi <= IndicatorParams.rsiExtremeOversold) {
      AppLogger.debug(
        'RSIExtremeOversold',
        '${data.symbol}: RSI=${rsi.toStringAsFixed(1)} <= ${IndicatorParams.rsiExtremeOversold}',
      );
      return TriggeredReason(
        type: ReasonType.rsiExtremeOversold,
        score: RuleScores.rsiExtremeOversoldSignal,
        description: 'RSI 極度超賣 (${rsi.toStringAsFixed(1)})',
        evidence: {'rsi': rsi, 'threshold': IndicatorParams.rsiExtremeOversold},
      );
    }

    return null;
  }
}

/// 規則：KD 黃金交叉
///
/// 當 K 線向上穿越 D 線時觸發，最佳情況為超賣區
class KDGoldenCrossRule extends StockRule {
  const KDGoldenCrossRule();

  @override
  String get id => 'kd_golden_cross';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final ind = context.indicators;
    if (ind == null ||
        ind.kdK == null ||
        ind.kdD == null ||
        ind.prevKdK == null ||
        ind.prevKdD == null) {
      return null;
    }

    final k = ind.kdK!;
    final d = ind.kdD!;
    final prevK = ind.prevKdK!;
    final prevD = ind.prevKdD!;

    // 黃金交叉：昨日 K < D，今日 K > D
    if (prevK < prevD && k > d) {
      // 過濾 1：僅在低檔區觸發
      if (prevK >= IndicatorParams.kdGoldenCrossZone) return null;

      // 過濾 2：成交量確認（今日 > 5 日均量的 1.5 倍）
      // 使用 PriceCalculator 統一計算，排除今日以正確比較
      if (!PriceCalculator.isVolumeAboveAverage(
        data.prices,
        days: TrendParams.priceVolumeLookbackDays,
      )) {
        return null;
      }

      // 過濾 3：價格強度
      // 確認黃金交叉有實際價格動能支撐
      if (data.prices.length >= 2) {
        final today = data.prices.last;
        final prev = data.prices[data.prices.length - 2];
        if (today.close != null && prev.close != null && prev.close! > 0) {
          final changePct = (today.close! - prev.close!) / prev.close!;
          if (changePct < IndicatorParams.kdCrossPriceChangeThreshold) {
            return null;
          }
        }
      }

      final isOversold = prevK < IndicatorParams.kdOversold;

      return TriggeredReason(
        type: ReasonType.kdGoldenCross,
        score: RuleScores.kdGoldenCross,
        description: isOversold ? '低檔 KD 黃金交叉 (量增價漲)' : 'KD 黃金交叉 (低檔量增價漲)',
        evidence: {'k': k, 'd': d, 'prevK': prevK, 'prevD': prevD},
      );
    }

    return null;
  }
}

/// 規則：KD 死亡交叉
class KDDeathCrossRule extends StockRule {
  const KDDeathCrossRule();

  @override
  String get id => 'kd_death_cross';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final ind = context.indicators;
    if (ind == null ||
        ind.kdK == null ||
        ind.kdD == null ||
        ind.prevKdK == null ||
        ind.prevKdD == null) {
      return null;
    }

    final k = ind.kdK!;
    final d = ind.kdD!;
    final prevK = ind.prevKdK!;
    final prevD = ind.prevKdD!;

    // 死亡交叉：昨日 K > D，今日 K < D
    if (prevK > prevD && k < d) {
      // 過濾 1：僅在高檔區觸發
      if (prevK <= IndicatorParams.kdDeathCrossZone) return null;

      // 過濾 2：成交量確認（今日 > 5 日均量的 1.5 倍）
      // 使用 PriceCalculator 統一計算，排除今日以正確比較
      if (!PriceCalculator.isVolumeAboveAverage(
        data.prices,
        days: TrendParams.priceVolumeLookbackDays,
      )) {
        return null;
      }

      final isOverbought = prevK > IndicatorParams.kdOverbought;

      return TriggeredReason(
        type: ReasonType.kdDeathCross,
        score: RuleScores.kdDeathCross,
        description: isOverbought ? '高檔 KD 死亡交叉 (量增)' : 'KD 死亡交叉 (高檔量增)',
        evidence: {'k': k, 'd': d, 'prevK': prevK, 'prevD': prevD},
      );
    }
    return null;
  }
}

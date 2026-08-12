import 'dart:collection';
import 'dart:math';

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 大盤位階（均線排列）分類
///
/// 依加權指數收盤價與 MA20/MA60 的相對位置判斷趨勢結構，
/// 對應 Weinstein 階段分析，作為各項籌碼/法人訊號多空意義的錨點。
enum MarketStage {
  /// 多頭排列：收盤 > MA20 > MA60
  bullish,

  /// 空頭排列：收盤 < MA20 < MA60
  bearish,

  /// 均線糾結：未形成明確多空排列（子狀態見 [MarketStageResult.neutralDetail]）
  neutral,

  /// 資料不足：有效收盤價少於 MA60 所需筆數
  insufficient,
}

/// [MarketStage.neutral] 的子狀態——由 close/MA20/MA60 三值的相對位置完整
/// 分割,**不引入新閾值**(2026-08-12)。
///
/// 動機:neutral 一律顯示「均線糾結」誤導——8/12 實況 TAIEX 收盤已站上
/// 雙均線(+4.4%/+2.3%)、只是崩跌後 20MA 尚未上穿 60MA,「糾結」讀起來
/// 像盤整。判定邏輯不變,只是把 neutral 說清楚。
enum NeutralStageDetail {
  /// 收盤在雙均線之上,但 20MA 仍在 60MA 下(修復中、待黃金交叉)
  reclaimAwaitCross,

  /// 收盤在雙均線之下,但 20MA 仍在 60MA 上(轉弱中、待死亡交叉)
  breakdownWeakening,

  /// 收盤夾在兩均線之間,20MA 在下(反彈站上 20MA,60MA 壓力未過)
  aboveShortBelowLong,

  /// 收盤夾在兩均線之間,20MA 在上(跌破 20MA,60MA 支撐之上)
  belowShortAboveLong,
}

/// 大盤位階計算結果
///
/// [stage] 為 [MarketStage.insufficient] 時，[ma60]/[biasMa60] 可能為 null。
class MarketStageResult {
  const MarketStageResult({
    required this.stage,
    this.latestClose,
    this.ma20,
    this.ma60,
    this.biasMa20,
    this.biasMa60,
  });

  /// 資料不足（少於 MA60 所需筆數）的固定結果
  static const insufficient = MarketStageResult(
    stage: MarketStage.insufficient,
  );

  final MarketStage stage;
  final double? latestClose;
  final double? ma20;
  final double? ma60;

  /// 距 MA20 乖離率（%），正值表示收盤在均線之上
  final double? biasMa20;

  /// 距 MA60 乖離率（%），正值表示收盤在均線之上
  final double? biasMa60;

  /// [MarketStage.neutral] 的子狀態;非 neutral 或值缺失時為 null。
  ///
  /// 分割邏輯(與 [TechnicalIndicatorService.calculateMarketStage] 的
  /// 排列判定互補,合起來覆蓋所有 close/MA20/MA60 排列):
  /// - 收盤 ≥ 雙均線 → [NeutralStageDetail.reclaimAwaitCross]
  /// - 收盤 ≤ 雙均線 → [NeutralStageDetail.breakdownWeakening]
  /// - 夾層且 20MA<60MA → [NeutralStageDetail.aboveShortBelowLong]
  /// - 夾層且 20MA≥60MA → [NeutralStageDetail.belowShortAboveLong]
  NeutralStageDetail? get neutralDetail {
    if (stage != MarketStage.neutral) return null;
    final c = latestClose, s = ma20, l = ma60;
    if (c == null || s == null || l == null) return null;
    // 「待黃金/死亡交叉」是**交叉宣稱**,條件必須保證均線次序(2026-08-12
    // 審查實測:死平盤 c==s==l 或 c==s>l 的等值邊界,原本會被第一支吃掉、
    // 標成「待黃金交叉」——但交叉早發生了)。s==l = 正在交叉點上,回 null
    // 讓 UI 落回「均線糾結」——那是字面上唯一正確的詞。
    if (c >= s && c >= l && s < l) {
      return NeutralStageDetail.reclaimAwaitCross;
    }
    if (c <= s && c <= l && s > l) {
      return NeutralStageDetail.breakdownWeakening;
    }
    if (s == l) return null;
    return s < l
        ? NeutralStageDetail.aboveShortBelowLong
        : NeutralStageDetail.belowShortAboveLong;
  }
}

/// 技術指標計算服務
///
/// 提供各種技術分析指標的計算方法，包含 SMA、EMA、RSI、KD、MACD、布林通道等
class TechnicalIndicatorService {
  /// 計算簡單移動平均線 (SMA)
  ///
  /// 回傳與輸入相同長度的列表，資料不足的位置為 null
  List<double?> calculateSMA(List<double> prices, int period) {
    if (prices.isEmpty || period <= 0) return [];
    if (period > prices.length) {
      return List<double?>.filled(prices.length, null);
    }

    final result = List<double?>.filled(prices.length, null);

    // 計算初始 window 的加總
    var sum = 0.0;
    for (int i = 0; i < period - 1; i++) {
      sum += prices[i];
    }

    // Sliding window：每次加入新值、移除最舊值，O(n) 取代 O(n×period)
    for (int i = period - 1; i < prices.length; i++) {
      sum += prices[i];
      result[i] = sum / period;
      sum -= prices[i - period + 1];
    }

    return result;
  }

  /// 計算大盤位階（均線排列 + 乖離率）
  ///
  /// [closes] 須為時間升序（最舊→最新）的收盤價列表。
  /// 複用 [calculateSMA] 取得最新的 MA20/MA60，並計算收盤價對兩條均線的
  /// 乖離率（%）。當有效資料少於 MA60 所需筆數時回傳
  /// [MarketStageResult.insufficient]。
  ///
  /// 位階判定：
  /// - 多頭排列：收盤 > MA20 > MA60
  /// - 空頭排列：收盤 < MA20 < MA60
  /// - 均線糾結：其餘情況
  MarketStageResult calculateMarketStage(List<double> closes) {
    const shortPeriod = AnalysisParams.marketStageShortMaPeriod;
    const longPeriod = AnalysisParams.marketStageLongMaPeriod;

    if (closes.length < longPeriod) return MarketStageResult.insufficient;

    final ma20 = calculateSMA(closes, shortPeriod).last;
    final ma60 = calculateSMA(closes, longPeriod).last;

    // MA60 為 null 表示有效資料不足（防禦：理論上長度已 >= longPeriod）
    if (ma20 == null || ma60 == null || ma20 == 0 || ma60 == 0) {
      return MarketStageResult.insufficient;
    }

    final latestClose = closes.last;
    final biasMa20 = (latestClose - ma20) / ma20 * 100;
    final biasMa60 = (latestClose - ma60) / ma60 * 100;

    final MarketStage stage;
    if (latestClose > ma20 && ma20 > ma60) {
      stage = MarketStage.bullish;
    } else if (latestClose < ma20 && ma20 < ma60) {
      stage = MarketStage.bearish;
    } else {
      stage = MarketStage.neutral;
    }

    return MarketStageResult(
      stage: stage,
      latestClose: latestClose,
      ma20: ma20,
      ma60: ma60,
      biasMa20: biasMa20,
      biasMa60: biasMa60,
    );
  }

  /// 計算指數移動平均線 (EMA)
  List<double?> calculateEMA(List<double> prices, int period) {
    if (prices.isEmpty || period <= 0) return [];

    final result = <double?>[];
    final multiplier = 2 / (period + 1);

    // 第一個 EMA 使用 SMA 計算
    double? ema;
    for (int i = 0; i < prices.length; i++) {
      if (i < period - 1) {
        result.add(null);
      } else if (i == period - 1) {
        // 計算初始 SMA
        double sum = 0;
        for (int j = 0; j < period; j++) {
          sum += prices[j];
        }
        ema = sum / period;
        result.add(ema);
      } else {
        // EMA = (Close - EMA(prev)) * multiplier + EMA(prev)
        ema = (prices[i] - ema!) * multiplier + ema;
        result.add(ema);
      }
    }

    return result;
  }

  /// 計算相對強弱指標 (RSI)
  ///
  /// [period] 預設為 14 日。
  ///
  /// [gapBefore]（選填，通常來自 [OhlcvData.gapBefore]）：與 [prices] 等長，
  /// `gapBefore[i] == true` 表示 `prices[i]` 與 `prices[i-1]` 之間跨越了
  /// 停牌/無成交缺口。此時該筆價差**不會**被採計進漲跌幅平均——避免把
  /// 「跨數個交易日的累積價差」誤當成單一交易日變動，產生虛假極端 RSI。
  /// 語意與 [latestRSI] 的缺口處理一致（該步驟凍結、不衰減、不採計）。
  /// 省略時維持過去行為（不做缺口偵測），向後相容既有呼叫端。
  List<double?> calculateRSI(
    List<double> prices, {
    int period = 14,
    List<bool>? gapBefore,
  }) {
    if (prices.length < period + 1) {
      return List.filled(prices.length, null);
    }

    final result = <double?>[];

    // 計算價格變動，並標記每筆變動是否跨越缺口
    final changes = <double>[];
    final isGapDelta = <bool>[];
    for (int i = 1; i < prices.length; i++) {
      changes.add(prices[i] - prices[i - 1]);
      isGapDelta.add(gapBefore != null && i < gapBefore.length && gapBefore[i]);
    }

    // 第一個 RSI 需要 period + 1 個資料點
    for (int i = 0; i < period; i++) {
      result.add(null);
    }

    // 計算初始平均漲跌幅
    // 跨缺口的變動不採計進分子，但分母固定為 period（與 latestRSI 的
    // seed window 一致：缺口視為「無資訊」而非「單日零變動」，寧可讓
    // 平均略為保守也不虛增波動）
    double avgGain = 0;
    double avgLoss = 0;
    for (int i = 0; i < period; i++) {
      if (isGapDelta[i]) continue;
      if (changes[i] > 0) {
        avgGain += changes[i];
      } else {
        avgLoss += changes[i].abs();
      }
    }
    avgGain /= period;
    avgLoss /= period;

    // 計算第一個 RSI
    // 邊界情況：若漲跌幅皆為 0，RSI 應為中性值 (50)
    double rsi;
    if (avgGain == 0 && avgLoss == 0) {
      rsi = 50.0; // 中性 - 無價格變動
    } else if (avgLoss == 0) {
      rsi = 100.0; // 全部上漲，無下跌
    } else {
      final rs = avgGain / avgLoss;
      rsi = 100 - (100 / (1 + rs));
    }
    result.add(rsi);

    // 使用平滑平均計算後續 RSI
    for (int i = period; i < changes.length; i++) {
      if (isGapDelta[i]) {
        // 跨缺口：凍結目前平均（不套用平滑衰減、不採計此步價差），
        // RSI 維持缺口前的最後數值，直到下一筆真正相鄰的交易日出現
        result.add(rsi);
        continue;
      }

      final change = changes[i];
      final gain = change > 0 ? change : 0.0;
      final loss = change < 0 ? change.abs() : 0.0;

      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;

      // 與初始 RSI 相同的邊界情況處理
      double subsequentRsi;
      if (avgGain == 0 && avgLoss == 0) {
        subsequentRsi = 50.0; // 中性
      } else if (avgLoss == 0) {
        subsequentRsi = 100.0; // 全部上漲
      } else {
        final rs = avgGain / avgLoss;
        subsequentRsi = 100 - (100 / (1 + rs));
      }
      rsi = subsequentRsi;
      result.add(subsequentRsi);
    }

    return result;
  }

  /// 計算隨機震盪指標 (KD)
  ///
  /// [kPeriod] K 值週期，預設 9 日
  /// [dPeriod] D 值週期，預設 3 日
  ///
  /// 注意（gap-bridging root cause 修復的範圍界定）：此函式**不**做缺口
  /// 偵測。RSV 視窗以「N 個有效交易日」為準本就是標準 Stochastic 語意，
  /// 停牌期間無資料可採，沿用停牌前最後 K/D 並在復牌當日與新 RSV 混合
  /// 也是時間序列指標處理缺口的標準做法——K/D 數值本身沒有虛增問題。
  /// 真正的問題在於**呼叫端**把 `k[len-2]` 當成「前一交易日」用於交叉/
  /// 單日跌幅判斷，若前一筆其實跨了停牌缺口就會誤判；此防呆已在呼叫端
  /// 用 [OhlcvData.gapBefore] 處理（見 AnalysisCoordinatorService.
  /// calculateTechnicalIndicators、AlertEvaluationService 的 KD 交叉檢查）。
  ({List<double?> k, List<double?> d}) calculateKD(
    List<double> highs,
    List<double> lows,
    List<double> closes, {
    int kPeriod = 9,
    int dPeriod = 3,
  }) {
    if (highs.length != lows.length || lows.length != closes.length) {
      return (k: [], d: []);
    }

    final length = closes.length;
    final kValues = List<double?>.filled(length, null);
    final dValues = List<double?>.filled(length, null);

    // 計算 %K：使用單調雙端佇列求滑動視窗最大/最小值，O(n)
    final maxDeque = Queue<int>(); // 索引，highs 遞減排列
    final minDeque = Queue<int>(); // 索引，lows 遞增排列
    for (int i = 0; i < length; i++) {
      while (maxDeque.isNotEmpty && highs[maxDeque.last] <= highs[i]) {
        maxDeque.removeLast();
      }
      maxDeque.addLast(i);
      if (maxDeque.first <= i - kPeriod) maxDeque.removeFirst();

      while (minDeque.isNotEmpty && lows[minDeque.last] >= lows[i]) {
        minDeque.removeLast();
      }
      minDeque.addLast(i);
      if (minDeque.first <= i - kPeriod) minDeque.removeFirst();

      if (i >= kPeriod - 1) {
        final highestHigh = highs[maxDeque.first];
        final lowestLow = lows[minDeque.first];
        final range = highestHigh - lowestLow;
        kValues[i] = range == 0
            ? 50.0
            : ((closes[i] - lowestLow) / range) * 100;
      }
    }

    // 台灣標準 Slow Stochastic：
    // RSV = raw %K（已在 kValues 中計算）
    // %K = K_prev × (1 - 1/kSmooth) + RSV × (1/kSmooth)
    // %D = D_prev × (1 - 1/dPeriod) + K × (1/dPeriod)
    // 預設 kSmooth=3, dPeriod=3 → smoothing factor 皆為 1/3
    // 初始值：K₀ = D₀ = 50
    const kSmoothFactor = 1.0 / 3.0; // K 的平滑係數固定為 1/3（台灣標準）
    final dSmoothFactor = 1.0 / dPeriod; // D 的平滑係數由 dPeriod 決定
    double prevK = 50.0;
    double prevD = 50.0;

    // kValues 目前存放 RSV，改為存放 smoothed %K
    for (int i = kPeriod - 1; i < length; i++) {
      final rsv = kValues[i]!;
      final smoothedK = prevK * (1 - kSmoothFactor) + rsv * kSmoothFactor;
      final smoothedD = prevD * (1 - dSmoothFactor) + smoothedK * dSmoothFactor;

      kValues[i] = smoothedK;
      dValues[i] = smoothedD;

      prevK = smoothedK;
      prevD = smoothedD;
    }

    return (k: kValues, d: dValues);
  }

  /// 計算 MACD 指標
  ///
  /// [fastPeriod] 快線週期，預設 12 日
  /// [slowPeriod] 慢線週期，預設 26 日
  /// [signalPeriod] 訊號線週期，預設 9 日
  ({List<double?> macd, List<double?> signal, List<double?> histogram})
  calculateMACD(
    List<double> prices, {
    int fastPeriod = 12,
    int slowPeriod = 26,
    int signalPeriod = 9,
  }) {
    final fastEMA = calculateEMA(prices, fastPeriod);
    final slowEMA = calculateEMA(prices, slowPeriod);

    // MACD 線 = 快線 EMA - 慢線 EMA
    final macdLine = <double?>[];
    for (int i = 0; i < prices.length; i++) {
      if (fastEMA[i] == null || slowEMA[i] == null) {
        macdLine.add(null);
      } else {
        macdLine.add(fastEMA[i]! - slowEMA[i]!);
      }
    }

    // 訊號線 = MACD 線的 EMA
    final nonNullMacd = macdLine.whereType<double>().toList();
    final signalEMA = calculateEMA(nonNullMacd, signalPeriod);

    final signalLine = <double?>[];
    int signalIndex = 0;
    for (int i = 0; i < prices.length; i++) {
      if (macdLine[i] == null) {
        signalLine.add(null);
      } else {
        if (signalIndex < signalEMA.length) {
          signalLine.add(signalEMA[signalIndex]);
          signalIndex++;
        } else {
          signalLine.add(null);
        }
      }
    }

    // 柱狀圖 = MACD 線 - 訊號線
    final histogram = <double?>[];
    for (int i = 0; i < prices.length; i++) {
      if (macdLine[i] == null || signalLine[i] == null) {
        histogram.add(null);
      } else {
        histogram.add(macdLine[i]! - signalLine[i]!);
      }
    }

    return (macd: macdLine, signal: signalLine, histogram: histogram);
  }

  /// 計算布林通道
  ///
  /// [period] 週期，預設 20 日
  /// [stdDevMultiplier] 標準差倍數，預設 2 倍
  ({List<double?> upper, List<double?> middle, List<double?> lower})
  calculateBollingerBands(
    List<double> prices, {
    int period = 20,
    double stdDevMultiplier = 2.0,
  }) {
    final middle = calculateSMA(prices, period);
    final upper = <double?>[];
    final lower = <double?>[];

    // Sliding window 標準差：O(n) 取代 O(n×period)
    // 維護 sum 和 sumSq，每次只加入新值、移除舊值
    double sum = 0;
    double sumSq = 0;

    for (int i = 0; i < prices.length; i++) {
      sum += prices[i];
      sumSq += prices[i] * prices[i];

      if (i >= period) {
        sum -= prices[i - period];
        sumSq -= prices[i - period] * prices[i - period];
      }

      if (i < period - 1 || middle[i] == null) {
        upper.add(null);
        lower.add(null);
      } else {
        final mean = sum / period;
        final variance = (sumSq / period) - (mean * mean);
        final stdDev = sqrt(variance.abs()); // abs() 防浮點誤差產生微小負數

        upper.add(middle[i]! + (stdDevMultiplier * stdDev));
        lower.add(middle[i]! - (stdDevMultiplier * stdDev));
      }
    }

    return (upper: upper, middle: middle, lower: lower);
  }

  /// 計算能量潮指標 (OBV - On Balance Volume)
  ///
  /// OBV 是累積成交量指標，用於衡量買賣壓力
  /// - 價格上漲時累加當日成交量
  /// - 價格下跌時累減當日成交量
  /// - 價格持平時成交量不計入
  List<double> calculateOBV(List<double> closes, List<double> volumes) {
    if (closes.isEmpty || volumes.isEmpty) return [];
    if (closes.length != volumes.length) return [];

    final result = <double>[];
    double obv = 0;

    // 第一天 OBV 設為 0
    result.add(obv);

    for (int i = 1; i < closes.length; i++) {
      if (closes[i] > closes[i - 1]) {
        // 價格上漲：累加成交量
        obv += volumes[i];
      } else if (closes[i] < closes[i - 1]) {
        // 價格下跌：累減成交量
        obv -= volumes[i];
      }
      // 價格持平：OBV 不變
      result.add(obv);
    }

    return result;
  }

  /// 計算平均真實波幅 (ATR - Average True Range)
  ///
  /// ATR 是衡量價格波動性的指標，計算方式：
  /// True Range = max(高-低, |高-前收|, |低-前收|)
  /// ATR = True Range 的移動平均
  ///
  /// [period] 週期，預設 14 日
  List<double?> calculateATR(
    List<double> highs,
    List<double> lows,
    List<double> closes, {
    int period = 14,
  }) {
    if (highs.length != lows.length || lows.length != closes.length) {
      return [];
    }
    if (closes.length < 2) return List.filled(closes.length, null);

    final trueRanges = <double>[];
    final result = <double?>[];

    // 計算 True Range
    for (int i = 0; i < closes.length; i++) {
      if (i == 0) {
        // 第一天的 TR 就是高低價差
        trueRanges.add(highs[i] - lows[i]);
      } else {
        final prevClose = closes[i - 1];
        final tr1 = highs[i] - lows[i]; // 當日高低差
        final tr2 = (highs[i] - prevClose).abs(); // 當日高與前收差
        final tr3 = (lows[i] - prevClose).abs(); // 當日低與前收差
        trueRanges.add([tr1, tr2, tr3].reduce(max));
      }
    }

    // 計算 ATR（使用 Wilder's 平滑方法）
    for (int i = 0; i < closes.length; i++) {
      if (i < period - 1) {
        result.add(null);
      } else if (i == period - 1) {
        // 第一個 ATR 使用簡單平均
        double sum = 0;
        for (int j = 0; j < period; j++) {
          sum += trueRanges[j];
        }
        result.add(sum / period);
      } else {
        // 後續使用 Wilder's 平滑
        // ATR = ((前ATR * (period-1)) + 當日TR) / period
        final prevATR = result[i - 1]!;
        final currentATR = (prevATR * (period - 1) + trueRanges[i]) / period;
        result.add(currentATR);
      }
    }

    return result;
  }

  /// 計算最新的 OBV 值（供規則使用）
  ///
  /// [prices] DailyPriceEntry 列表，需依日期升序排列
  static double? latestOBV(List<DailyPriceEntry> prices) {
    if (prices.length < 2) return null;

    double obv = 0;
    for (int i = 1; i < prices.length; i++) {
      final current = prices[i].close;
      final previous = prices[i - 1].close;
      final volume = prices[i].volume;
      if (current == null || previous == null || volume == null) continue;

      if (current > previous) {
        obv += volume;
      } else if (current < previous) {
        obv -= volume;
      }
    }

    return obv;
  }

  /// 計算最新的 ATR 值（供規則使用）
  ///
  /// [prices] DailyPriceEntry 列表，需依日期升序排列
  /// [period] 計算週期，預設 14
  static double? latestATR(List<DailyPriceEntry> prices, {int period = 14}) {
    if (prices.length < period) return null;

    // 計算 True Range
    final trueRanges = <double>[];
    for (int i = 0; i < prices.length; i++) {
      final high = prices[i].high;
      final low = prices[i].low;
      final close = prices[i].close;
      if (high == null || low == null || close == null) continue;

      if (i == 0) {
        trueRanges.add(high - low);
      } else {
        final prevClose = prices[i - 1].close;
        if (prevClose == null) continue;

        final tr1 = high - low;
        final tr2 = (high - prevClose).abs();
        final tr3 = (low - prevClose).abs();
        trueRanges.add([tr1, tr2, tr3].reduce(max));
      }
    }

    if (trueRanges.length < period) return null;

    // 計算 ATR（Wilder's 平滑）
    // 先計算初始 SMA
    double atr = 0;
    for (int i = 0; i < period; i++) {
      atr += trueRanges[i];
    }
    atr /= period;

    // 再套用 Wilder's smoothing
    for (int i = period; i < trueRanges.length; i++) {
      atr = (atr * (period - 1) + trueRanges[i]) / period;
    }

    return atr;
  }

  // ==================================================
  // 靜態方法 - 供規則評估使用
  // ==================================================

  /// 計算最新的 SMA 值（僅供規則使用）
  ///
  /// 從價格物件列表中提取收盤價並計算 SMA
  /// [prices] 每日收盤價列表
  /// [period] 計算週期
  static double? latestSMA(List<DailyPriceEntry> prices, int period) {
    if (prices.length < period) return null;

    double sum = 0;
    int count = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      final close = prices[i].close;
      if (close != null) {
        sum += close;
        count++;
      }
    }
    return count == period ? sum / count : null;
  }

  /// 計算最新的 RSI 值（使用 Wilder's 平滑法）
  ///
  /// 從完整歷史初始化 Wilder's smoothed average，確保與 [calculateRSI] 結果一致。
  /// [prices] 每日收盤價列表
  /// [period] 計算週期，預設 14
  static double? latestRSI(List<DailyPriceEntry> prices, {int period = 14}) {
    if (prices.length < period + 1) return null;

    // 步驟 1：從資料起點計算初始平均漲跌幅（前 period 筆變動）
    double initialGains = 0;
    double initialLosses = 0;
    int validCount = 0;

    for (int i = 1; i <= period; i++) {
      final current = prices[i].close;
      final previous = prices[i - 1].close;
      if (current == null || previous == null) continue;

      final change = current - previous;
      if (change > 0) {
        initialGains += change;
      } else {
        initialLosses += -change;
      }
      validCount++;
    }

    if (validCount < period ~/ 2) return null;

    double avgGain = initialGains / period;
    double avgLoss = initialLosses / period;

    // 步驟 2：從 period+1 開始，對所有後續資料套用 Wilder's 平滑
    for (int i = period + 1; i < prices.length; i++) {
      final current = prices[i].close;
      final previous = prices[i - 1].close;
      if (current == null || previous == null) continue;

      final change = current - previous;
      final currentGain = change > 0 ? change : 0.0;
      final currentLoss = change < 0 ? -change : 0.0;

      avgGain = (avgGain * (period - 1) + currentGain) / period;
      avgLoss = (avgLoss * (period - 1) + currentLoss) / period;
    }

    if (avgLoss == 0) return 100;

    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  /// 計算成交量 MA 並比較今日成交量
  ///
  /// [prices] 每日收盤價列表
  /// [period] 計算週期
  /// 回傳 (volumeMA, 今日成交量)
  ///
  /// 停牌/無成交列的 volume 為 0.0（非 null），計算均量時會排除（而非計為
  /// 0 的有效觀測值稀釋均量），且要求窗口內至少 [RuleParams.volMaMinValidDayRatio]
  /// 比例的有效交易日，否則回傳 null——口徑與 volume_rules.dart 的
  /// VolumeSpikeRule/PriceSpikeRule 均量計算一致（同一份缺口語意的共用邏輯）。
  static ({double? volumeMA, double? todayVolume}) latestVolumeMA(
    List<DailyPriceEntry> prices,
    int period,
  ) {
    if (prices.isEmpty) return (volumeMA: null, todayVolume: null);

    final todayVol = prices.last.volume;
    if (prices.length < period) return (volumeMA: null, todayVolume: todayVol);

    double volSum = 0;
    int count = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      final vol = prices[i].volume;
      if (vol != null && vol > 0) {
        volSum += vol;
        count++;
      }
    }

    final minValidDays = (period * RuleParams.volMaMinValidDayRatio).floor();
    if (count < minValidDays) {
      return (volumeMA: null, todayVolume: todayVol);
    }

    return (volumeMA: volSum / count, todayVolume: todayVol);
  }
}

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart'
    show MarketStage;

/// 判讀文字的語氣（決定 UI 的強調色）
///
/// - [positive]：偏正面 / 健康（維持 muted，不上色）
/// - [warning]：留意 / 過熱（amber 提示）
/// - [negative]：偏負面 / 賣壓（沿用台股下跌色）
/// - [neutral]：中性 / 觀望（維持 muted，不上色）
enum InterpretationTone { positive, warning, negative, neutral }

/// 單則大盤判讀結果
///
/// [messageKey] 為 i18n key（`marketOverview.reading.*`），由 UI 以 `.tr()`
/// 解析；[args] 為帶參數的 namedArgs——綜合判讀(rule 0)等分支會帶
/// pct/breadthPct/netAmount 等參數,無參數的判讀為 null。
class MarketReading {
  const MarketReading({
    required this.messageKey,
    required this.tone,
    this.args,
  });

  final String messageKey;
  final InterpretationTone tone;
  final Map<String, String>? args;
}

/// 大盤判讀服務（判讀層 / P2）
///
/// 將「大盤總覽」各區塊的原始數字轉成一行分析師口吻的判讀，讓 dashboard
/// 不再只是一面數字牆。
///
/// 純函式、無 IO，全部分支可單元測試。所有門檻集中於 [AnalysisParams]，
/// 不含魔術數字；輸出僅為 label，不影響任何評分。
class MarketReadingService {
  const MarketReadingService._();

  /// 量價判讀（成交額 vs 5 日均量 + 指數漲跌）
  ///
  /// [todayTurnover] 今日成交額、[avg5dTurnover] 5 日均量、
  /// [indexChangePercent] 大盤（加權指數）漲跌幅（%）。
  ///
  /// 量能變化 = (今日 - 均量) / 均量 × 100；均量 ≤ 0 時視為「量能持平」。
  static MarketReading interpretVolumePrice({
    required double todayTurnover,
    required double avg5dTurnover,
    required double indexChangePercent,
  }) {
    final isUp = indexChangePercent > 0;
    final turnoverDeltaPct = avg5dTurnover > 0
        ? (todayTurnover - avg5dTurnover) / avg5dTurnover * 100
        : 0.0;

    const threshold = AnalysisParams.kVolumeSurgePct;

    if (isUp && turnoverDeltaPct > threshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.volumePrice.healthyUp',
        tone: InterpretationTone.positive,
      );
    }
    if (isUp && turnoverDeltaPct < -threshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.volumePrice.weakUp',
        tone: InterpretationTone.warning,
      );
    }
    if (!isUp && turnoverDeltaPct > threshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.volumePrice.heavySelloff',
        tone: InterpretationTone.negative,
      );
    }
    if (!isUp && turnoverDeltaPct < -threshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.volumePrice.quietConsolidation',
        tone: InterpretationTone.neutral,
      );
    }
    // |delta| <= threshold：量能持平
    return const MarketReading(
      messageKey: 'marketOverview.reading.volumePrice.flat',
      tone: InterpretationTone.neutral,
    );
  }

  /// 籌碼槓桿判讀（融資增減 vs 指數漲跌）
  ///
  /// [marginChange] 融資增減量（正 = 增、負 = 減），方向有意義；
  /// [indexChangePercent] 大盤漲跌幅（%）。
  static MarketReading interpretMarginLeverage({
    required double marginChange,
    required double indexChangePercent,
  }) {
    if (marginChange == 0) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.marginLeverage.stable',
        tone: InterpretationTone.neutral,
      );
    }

    final isUp = indexChangePercent > 0;

    if (marginChange > 0 && isUp) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.marginLeverage.overheating',
        tone: InterpretationTone.warning,
      );
    }
    if (marginChange < 0 && isUp) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.marginLeverage.healthyWashout',
        tone: InterpretationTone.positive,
      );
    }
    if (marginChange > 0 && !isUp) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.marginLeverage.trapped',
        tone: InterpretationTone.negative,
      );
    }
    // marginChange < 0 && !isUp
    return const MarketReading(
      messageKey: 'marketOverview.reading.marginLeverage.deleveraging',
      tone: InterpretationTone.neutral,
    );
  }

  /// 廣度判讀（上漲 / 下跌家數）
  ///
  /// 占比 = 上漲 / (上漲 + 下跌)；分母 ≤ 0 時視為「漲跌互現」。
  static MarketReading interpretBreadth({
    required int advance,
    required int decline,
  }) {
    final denom = advance + decline;
    final ratio = denom > 0 ? advance / denom : 0.5;

    if (ratio > AnalysisParams.kBreadthBroadUpRatio) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.breadth.broadUp',
        tone: InterpretationTone.positive,
      );
    }
    if (ratio < AnalysisParams.kBreadthBroadDownRatio) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.breadth.broadDown',
        tone: InterpretationTone.negative,
      );
    }
    return const MarketReading(
      messageKey: 'marketOverview.reading.breadth.mixed',
      tone: InterpretationTone.neutral,
    );
  }

  /// 廣度趨勢判讀（52 週新高/新低家數 vs 指數漲跌）
  ///
  /// 結合廣度趨勢（新高 / 新低家數）與指數方向，偵測「廣度確認」或
  /// 「廣度背離」。純比較家數、threshold-free（不含魔術數字）。
  ///
  /// - 指數漲 & 新高 > 新低：新高擴張，廣度確認多方（positive）
  /// - 指數漲 & 新低 ≥ 新高：指數漲但新低未縮，留意廣度背離（warning）
  /// - 指數跌 & 新低 > 新高：新低擴散，弱勢未止（negative）
  /// - 其餘：廣度中性（neutral）
  static MarketReading interpretBreadthTrend({
    required int newHighs,
    required int newLows,
    required double indexChangePercent,
  }) {
    final isUp = indexChangePercent > 0;

    if (isUp && newHighs > newLows) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.breadthTrend.confirmUp',
        tone: InterpretationTone.positive,
      );
    }
    if (isUp && newLows >= newHighs) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.breadthTrend.divergence',
        tone: InterpretationTone.warning,
      );
    }
    if (!isUp && newLows > newHighs) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.breadthTrend.weakDown',
        tone: InterpretationTone.negative,
      );
    }
    return const MarketReading(
      messageKey: 'marketOverview.reading.breadthTrend.neutral',
      tone: InterpretationTone.neutral,
    );
  }

  /// 位階乖離判讀（增強既有「大盤位階」單行）
  ///
  /// 僅在極端乖離時回傳補充判讀，其餘回傳 null（位階 chip 已足夠表達）。
  ///
  /// - 多頭排列 & MA60 正乖離 > [AnalysisParams.kBiasOverheatPct]：短線偏熱
  /// - 空頭排列 & MA60 負乖離 < -門檻：超跌、留意反彈
  /// - 其餘：null
  static MarketReading? interpretStageBias({
    required MarketStage stage,
    required double biasMa60,
  }) {
    const threshold = AnalysisParams.kBiasOverheatPct;

    if (stage == MarketStage.bullish && biasMa60 > threshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.stageBias.overheated',
        tone: InterpretationTone.warning,
      );
    }
    if (stage == MarketStage.bearish && biasMa60 < -threshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.stageBias.oversold',
        tone: InterpretationTone.positive,
      );
    }
    return null;
  }

  /// 綜合判讀（大盤層級，非單一區塊）
  ///
  /// 綜合指數漲跌、個股廣度（漲跌家數）與外資/法人合計方向，抓出「指數
  /// 表現 vs 個股/籌碼實際狀況」的背離訊號。窄規則、依序判斷，命中即回傳：
  ///
  /// 0. **最高優先**：|[indexChangePercent]| >=
  ///    [AnalysisParams.kSynthesisExtremeDayPct]（極端日，如崩盤/暴漲）
  ///    → 系統性風險日/亢奮日，個股多空訊號參考性降低（negative / warning），
  ///    蓋過以下 rule 1～3。若同時符合 rule 2 的法人背離條件（方向相反 +
  ///    金額達市場門檻），於訊息末端附加「背離待後續確認」附註（沿用
  ///    rule 2 同一組門檻常數）。
  /// 1. 指數平盤（|[indexChangePercent]| < [AnalysisParams.kSynthesisFlatIndexPct]）
  ///    且下跌（或上漲）家數占比 >= [AnalysisParams.kSynthesisInternalSkewRatio]
  ///    → 「權值撐盤/壓盤、內部偏弱/偏強」（negative / positive）
  /// 2. 指數方向與法人合計方向相反，且 |[institutionalTotalNet]| 達市場門檻
  ///    （[AnalysisParams.kSynthesisInstDivergenceAmountTwse] /
  ///    [AnalysisParams.kSynthesisInstDivergenceAmountTpex]，依 [market]）
  ///    → 點名籌碼與指數背離（warning）
  /// 3. 其餘 → 中性「家數與法人無背離」(2026-08-12 改詞:原「多空訊號無
  ///    明顯背離」與同頁 52 週廣度警告「留意廣度背離」撞詞——本判讀只看
  ///    家數與法人,不含 52 週新高低,措辭把範圍說清楚)
  ///
  /// [market] 使用 [MarketCode.twse] / [MarketCode.tpex]，決定 rule 0 附註與
  /// rule 2 的金額門檻（上櫃成交及法人量級遠小於上市，需獨立門檻）；
  /// [advance]/[decline] 分母 <= 0 時占比預設 0.5（不觸發 rule 0/1 的偏向判斷，
  /// 行為對齊 [interpretBreadth]）。
  ///
  /// **兩種佔比口徑並存（刻意不同，勿合併）**：
  /// - **顯示口徑**（rule 0 極端日 `breadthPct`）：分母含 [unchanged]，對齊
  ///   漲跌家數區（大盤總覽的 AdvanceDeclineGauge）的 `decline /
  ///   (advance+decline+unchanged)`，避免同頁兩處百分比不一致（如 92% vs 89%）。
  /// - **門檻判定口徑**（rule 1 的 [AnalysisParams.kSynthesisInternalSkewRatio]
  ///   55% 比較）：分母刻意排除 [unchanged]，維持原定義——該常數是依「排除
  ///   持平」的比例校準，改分母會改變觸發敏感度，故不隨顯示口徑一併更動。
  static MarketReading interpretCompositeSynthesis({
    required String market,
    required double indexChangePercent,
    required int advance,
    required int decline,
    required int unchanged,
    required double institutionalTotalNet,
  }) {
    // 金額門檻（依市場而定）；rule 0 的背離附註與 rule 2 皆沿用同一組門檻。
    final amountThreshold = market == MarketCode.twse
        ? AnalysisParams.kSynthesisInstDivergenceAmountTwse
        : AnalysisParams.kSynthesisInstDivergenceAmountTpex;

    // Rule 0（最高優先）：極端日 — 崩盤/暴漲等系統性行情下，個股多空訊號的
    // 參考性大幅降低；即使 rule 1/2 的窄規則也會命中，仍應優先呈現「極端
    // 日」框架，避免「無明顯背離」之類雲淡風輕的措辭掩蓋系統性風險。
    if (indexChangePercent.abs() >= AnalysisParams.kSynthesisExtremeDayPct) {
      final isDown = indexChangePercent < 0;
      // 顯示口徑：分母含持平，對齊漲跌家數區同一頁的百分比（見上方 dartdoc
      // 「兩種佔比口徑並存」），與下方 rule 1 的門檻判定口徑刻意不同。
      final displayTotal = advance + decline + unchanged;
      final breadthRatio = displayTotal > 0
          ? (isDown ? decline / displayTotal : advance / displayTotal)
          : 0.5;
      final args = {
        'pct': indexChangePercent.abs().toStringAsFixed(2),
        'breadthPct': (breadthRatio * 100).toStringAsFixed(0),
      };
      final tone = isDown
          ? InterpretationTone.negative
          : InterpretationTone.warning;

      // 是否同時符合 rule 2 的法人背離條件（方向與指數相反 + 金額達門檻）
      final hasInstitutionalDivergence =
          institutionalTotalNet.abs() >= amountThreshold &&
          (isDown ? institutionalTotalNet > 0 : institutionalTotalNet < 0);

      if (!hasInstitutionalDivergence) {
        return MarketReading(
          messageKey: isDown
              ? 'marketOverview.reading.synthesis.extremeDown'
              : 'marketOverview.reading.synthesis.extremeUp',
          tone: tone,
          args: args,
        );
      }
      return MarketReading(
        messageKey: isDown
            ? 'marketOverview.reading.synthesis.extremeDownDivergence'
            : 'marketOverview.reading.synthesis.extremeUpDivergence',
        tone: tone,
        args: {
          ...args,
          'netAmount': (institutionalTotalNet.abs() / 100000000)
              .toStringAsFixed(0),
        },
      );
    }

    // Rule 1：指數平盤 + 內部家數明顯偏向一邊
    //
    // 門檻判定口徑：分母刻意排除持平（不含 unchanged），與上方 rule 0 的
    // 顯示口徑不同——55% 門檻常數是依「排除持平」的比例校準，若改分母會
    // 改變觸發敏感度，故不隨顯示口徑一併更動（見上方 dartdoc 說明）。
    if (indexChangePercent.abs() < AnalysisParams.kSynthesisFlatIndexPct) {
      final total = advance + decline;
      final declineRatio = total > 0 ? decline / total : 0.5;
      final advanceRatio = total > 0 ? advance / total : 0.5;

      if (declineRatio >= AnalysisParams.kSynthesisInternalSkewRatio) {
        return const MarketReading(
          messageKey: 'marketOverview.reading.synthesis.weightSupport',
          tone: InterpretationTone.negative,
        );
      }
      if (advanceRatio >= AnalysisParams.kSynthesisInternalSkewRatio) {
        return const MarketReading(
          messageKey: 'marketOverview.reading.synthesis.weightPressure',
          tone: InterpretationTone.positive,
        );
      }
    }

    // Rule 2：指數方向與法人合計方向相反，且金額顯著（門檻依市場而定）
    if (indexChangePercent > 0 &&
        institutionalTotalNet < 0 &&
        institutionalTotalNet.abs() >= amountThreshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.synthesis.divergenceSell',
        tone: InterpretationTone.warning,
      );
    }
    if (indexChangePercent < 0 &&
        institutionalTotalNet > 0 &&
        institutionalTotalNet.abs() >= amountThreshold) {
      return const MarketReading(
        messageKey: 'marketOverview.reading.synthesis.divergenceBuy',
        tone: InterpretationTone.warning,
      );
    }

    // Rule 3：其餘 — 無明顯背離
    return const MarketReading(
      messageKey: 'marketOverview.reading.synthesis.neutral',
      tone: InterpretationTone.neutral,
    );
  }
}

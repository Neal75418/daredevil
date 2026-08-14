import 'package:daredevil/core/constants/reason_type.dart';

/// 風險嚴重度 — Today 卡片警示徽章的分級
enum RiskSeverity {
  /// 🔴 嚴重 — 強制風險（處置 / 監管 / 籌碼崩壞 / 趨勢破壞）
  severe,

  /// 🟡 中度 — 投機 / 轉弱 / 基本面 lagging
  moderate,
}

/// 警示訊號 allowlist + 嚴重度分級（option B 風險徽章資料來源）
///
/// **背景**：階段重設計（Mode C v2 + 2026-06-20 階段歸位）把警訊（空頭排列 /
/// 死叉 / 處置股 / 高當沖…）全移進 [ScoringMode.neutral]。neutral 訊號的 chip
/// 不在 Today 卡片顯示（只在個股詳情頁）→ 主畫面失去「這檔有紅旗」的可見性。
/// 這裡定義「哪些 neutral 訊號該以風險徽章浮回卡片」+ 各自嚴重度。
///
/// **界定鐵律 — 不能用「取所有 neutral」或「取所有負分」**：
/// - [ReasonType.dayTradingHigh] 分數為 **0**（2026-07-18 由 +12 demote，見
///   [RuleScores.dayTradingHigh]）但語意是「高換手 / 投機接刀」警訊 → 必須
///   allowlist 強制納入（看語意不看分數；0 分同樣選不到）。
/// - [ReasonType.revenueYoySurge] +20 / [ReasonType.highDividendYield] +18 等是
///   **利多**、絕不納入警訊桶。
/// - [ReasonType.concentrationHigh] / [ReasonType.week52Low] 是 noise、不納入。
///
/// 故 [severe] ∪ [moderate] 是 warning-class 的**唯一真相來源**。所有成員都應是
/// [ScoringMode.neutral]（由 risk_warnings_test 的 invariant 守護）。
///
/// 放獨立檔（非 scoring_mode.dart）：scoring_mode.dart 被 reason_type.dart import、
/// 反向引用 [ReasonType] 會 cycle（同 [ModeFilters.modeCRequiredAnyOf] 為何用字串）。
/// 本檔在 import 下游，可安全用 typed [ReasonType]。
abstract final class RiskWarnings {
  /// 🔴 嚴重（7 條）— 強制風險、稀有且嚴重，徽章紅底
  ///
  /// **鐵律：紅色要稀有才有意義**。注意股**不**在此（見 [moderate] 的降級說明）。
  static const Set<ReasonType> severe = {
    ReasonType.tradingWarningDisposal, // 處置股 (-50)
    ReasonType.insiderSellingStreak, // 內部人連續減持 (-25)
    ReasonType.foreignExodus, // 外資加速流出 (-20)
    ReasonType.techBreakdown, // 跌破支撐 / 破底 (-20)
    ReasonType.highPledgeRatio, // 高質押比例 (-18)
    ReasonType.maAlignmentBearish, // 空頭排列 (-15)
    ReasonType.priceVolumeBearishDivergence, // 價跌量增 / 恐慌 (-15)
  };

  /// 🟡 中度（20 條）— 投機 / 轉弱 / 基本面 lagging，徽章琥珀底
  ///
  /// **2026-06-20 設計報告外的修正**：報告漏列 [ReasonType.patternDojiBearish]
  /// (-5)，它與已納入的 [ReasonType.patternHangingMan] / [ReasonType.dayTradingExtreme]
  /// (同 -5) 同屬高檔反轉警訊，排除不一致 → 補進中度。
  ///
  /// **2026-06-20 上線後降級**：[ReasonType.tradingWarningAttention]（注意股）從
  /// severe 降 moderate。理由 (1) 注意股是 TWSE **最輕級**監管旗標（異常成交/週轉/
  /// 本益比），遠輕於有交易限制的處置股；(2) 既有 [WarningBadgeType] 早就把注意設
  /// 橘、處置設紅，把它設 severe 自打嘴巴；(3) live 實測注意股單日 fire 53 檔、其他
  /// severe 合計才 18 檔 → 當 severe 會讓強勢 tab 變紅海、淹沒真正稀有的處置股(1)。
  static const Set<ReasonType> moderate = {
    ReasonType.tradingWarningAttention, // 注意股 (-15)，最輕監管旗標、高頻
    ReasonType.reversalS2W, // 趨勢翻轉 (-25)
    ReasonType.patternThreeBlackCrows, // 三烏鴉 (-18)
    ReasonType.institutionalSellStreak, // 法人連賣 (-15)
    ReasonType.epsDeclineWarning, // EPS 衰退 (-12)
    ReasonType.foreignShareholdingDecreasing, // 外資減碼 (-12)
    ReasonType.institutionalSell, // 法人賣超 (-12)
    ReasonType.kdDeathCross, // KD 死叉 (-12)
    ReasonType.patternHangingMan, // 高檔吊人線 (-12)
    ReasonType.patternEveningStar, // 暮星 (-10)
    ReasonType.patternBearishEngulfing, // 空頭吞噬 (-10)
    ReasonType.revenueYoyDecline, // 營收年減 (-10)
    ReasonType.roeDeclining, // ROE 下滑 (-10)
    ReasonType.patternGapDown, // 跳空下跌 (-8)
    ReasonType.rsiExtremeOverbought, // RSI 超買 (-8)
    ReasonType.priceVolumeWeakRally, // 價漲量縮 / 漲勢無力 (-8)
    ReasonType.foreignConcentrationWarning, // 外資集中警示 (-8)
    ReasonType.patternDojiBearish, // 高檔十字 (-5)
    ReasonType.dayTradingExtreme, // 極端當沖 (-5)
    ReasonType.dayTradingHigh, // 高當沖 (0 分，語意警訊、強制納入)
  };

  /// 全部 warning-class（severe ∪ moderate）
  static const Set<ReasonType> all = {...severe, ...moderate};

  /// 查嚴重度；非 warning-class（利多 / noise / 非 neutral）回 `null`。
  static RiskSeverity? severityOf(ReasonType type) {
    if (severe.contains(type)) return RiskSeverity.severe;
    if (moderate.contains(type)) return RiskSeverity.moderate;
    return null;
  }

  /// 取一組警訊中**最高**嚴重度（任一 severe → severe），空集合回 `null`。
  static RiskSeverity? topSeverity(Iterable<ReasonType> warnings) {
    RiskSeverity? top;
    for (final w in warnings) {
      final s = severityOf(w);
      if (s == RiskSeverity.severe) return RiskSeverity.severe;
      if (s == RiskSeverity.moderate) top = RiskSeverity.moderate;
    }
    return top;
  }
}

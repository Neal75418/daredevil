import 'package:daredevil/core/constants/rule_scores.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';

/// 推薦理由類型
enum ReasonType {
  reversalW2S('REVERSAL_W2S'),
  reversalS2W('REVERSAL_S2W'),
  techBreakout('TECH_BREAKOUT'),
  techBreakdown('TECH_BREAKDOWN'),
  volumeSpike('VOLUME_SPIKE'),
  priceSpike('PRICE_SPIKE'),
  institutionalBuy('INSTITUTIONAL_BUY'),
  institutionalSell('INSTITUTIONAL_SELL'),
  newsRelated('NEWS_RELATED'),
  // 技術指標訊號
  kdGoldenCross('KD_GOLDEN_CROSS'),
  kdDeathCross('KD_DEATH_CROSS'),
  institutionalBuyStreak('INSTITUTIONAL_BUY_STREAK'),
  institutionalSellStreak('INSTITUTIONAL_SELL_STREAK'),
  // K 線型態訊號
  patternDoji('PATTERN_DOJI'),
  patternDojiBearish('PATTERN_DOJI_BEARISH'),
  patternBullishEngulfing('PATTERN_BULLISH_ENGULFING'),
  patternBearishEngulfing('PATTERN_BEARISH_ENGULFING'),
  patternHammer('PATTERN_HAMMER'),
  patternHangingMan('PATTERN_HANGING_MAN'),
  patternGapUp('PATTERN_GAP_UP'),
  patternGapDown('PATTERN_GAP_DOWN'),
  patternMorningStar('PATTERN_MORNING_STAR'),
  patternEveningStar('PATTERN_EVENING_STAR'),
  patternThreeWhiteSoldiers('PATTERN_THREE_WHITE_SOLDIERS'),
  patternThreeBlackCrows('PATTERN_THREE_BLACK_CROWS'),
  // 第三階段：掃描/提醒訊號
  week52High('WEEK_52_HIGH'),
  week52Low('WEEK_52_LOW'),
  maAlignmentBullish('MA_ALIGNMENT_BULLISH'),
  maAlignmentBearish('MA_ALIGNMENT_BEARISH'),
  // MA 穿越事件(2026-07-31):站回=修復期領先者偵測、跌破=持股風控。
  // neutral(不進 3-tab 計分)+低分起步,累積 rule_accuracy 一季後由
  // 校準實證判決升格或歸零——分數唯一正確的制定方式是實證管道。
  reclaimMa20('RECLAIM_MA20'),
  reclaimMa60('RECLAIM_MA60'),
  breakMa20('BREAK_MA20'),
  breakMa60('BREAK_MA60'),
  // 蓄勢區(2026-07-31):貼線下 0~3%+60D>10% 的「還沒噴」事前狀態,
  // 與站回(事件)/回踩(進場)構成完整生命週期
  coilingBelowMa20('COILING_BELOW_MA20'),
  coilingBelowMa60('COILING_BELOW_MA60'),
  rsiExtremeOverbought('RSI_EXTREME_OVERBOUGHT'),
  rsiExtremeOversold('RSI_EXTREME_OVERSOLD'),
  // 第四階段：延伸市場資料訊號
  foreignShareholdingIncreasing('FOREIGN_SHAREHOLDING_INCREASING'),
  foreignShareholdingDecreasing('FOREIGN_SHAREHOLDING_DECREASING'),
  dayTradingHigh('DAY_TRADING_HIGH'),
  dayTradingExtreme('DAY_TRADING_EXTREME'),
  concentrationHigh('CONCENTRATION_HIGH'),
  // 第五階段：價量背離訊號
  //
  // **語意修正 2026-06-18**：`priceVolumeWeakRally`（價漲量縮）原識別子叫
  // priceVolumeBullishDivergence，但實際是「漲勢無力警示」（hardcoded
  // score -8）— bullish 命名跟 bearish 行為矛盾，會誤導 future calibration
  // 設計者。改為語意精確的 priceVolumeWeakRally。DB code 保留舊字串避免
  // 遷移 daily_reason / rule_accuracy / calibrated JSON 既存資料；新讀者請
  // 以 Dart 識別子為準。
  priceVolumeWeakRally('PRICE_VOLUME_BULLISH_DIVERGENCE'),
  priceVolumeBearishDivergence('PRICE_VOLUME_BEARISH_DIVERGENCE'),
  highVolumeBreakout('HIGH_VOLUME_BREAKOUT'),
  lowVolumeAccumulation('LOW_VOLUME_ACCUMULATION'),
  // 第六階段：基本面分析訊號
  revenueYoySurge('REVENUE_YOY_SURGE'),
  revenueYoyDecline('REVENUE_YOY_DECLINE'),
  revenueMomGrowth('REVENUE_MOM_GROWTH'),
  revenueNewHigh('REVENUE_NEW_HIGH'),
  highDividendYield('HIGH_DIVIDEND_YIELD'),
  peUndervalued('PE_UNDERVALUED'),
  peOvervalued('PE_OVERVALUED'),
  pbrUndervalued('PBR_UNDERVALUED'),
  // Killer Features 訊號
  tradingWarningAttention('TRADING_WARNING_ATTENTION'),
  tradingWarningDisposal('TRADING_WARNING_DISPOSAL'),
  insiderSellingStreak('INSIDER_SELLING_STREAK'),
  insiderSignificantBuying('INSIDER_SIGNIFICANT_BUYING'),
  highPledgeRatio('HIGH_PLEDGE_RATIO'),
  foreignConcentrationWarning('FOREIGN_CONCENTRATION_WARNING'),
  foreignExodus('FOREIGN_EXODUS'),
  // EPS 訊號
  epsYoYSurge('EPS_YOY_SURGE'),
  epsConsecutiveGrowth('EPS_CONSECUTIVE_GROWTH'),
  epsTurnaround('EPS_TURNAROUND'),
  epsDeclineWarning('EPS_DECLINE_WARNING'),

  // ROE 訊號
  roeExcellent('ROE_EXCELLENT'),
  roeImproving('ROE_IMPROVING'),
  roeDeclining('ROE_DECLINING'),

  // 第 9 階段：強股回檔進場（Mode C v2 - 回檔觀察）
  // 2026-06-19 workflow wf_6676643c-0e9 設計、4 條 buy-signal rule（2026-06-20 追加 MA10）識別「**之前強、
  // 現在剛開始拉回**」的進場時機。score 正分（跟 Mode A/B 一致）— 打破舊「Mode C 全
  // 負分」invariant，因為新 Mode C 是「觀察機會 tab」而非「警示 tab」。
  pullbackToMa20('PULLBACK_TO_MA20'),
  pullbackToMa10('PULLBACK_TO_MA10'),
  hammerAtSupport('HAMMER_AT_SUPPORT'),
  kdHighPullback('KD_HIGH_PULLBACK');

  const ReasonType(this.code);

  final String code;

  int get score => switch (this) {
    ReasonType.reversalW2S => RuleScores.reversalW2S,
    ReasonType.reversalS2W => RuleScores.reversalS2W,
    ReasonType.techBreakout => RuleScores.techBreakout,
    ReasonType.techBreakdown => RuleScores.techBreakdown,
    ReasonType.volumeSpike => RuleScores.volumeSpike,
    ReasonType.priceSpike => RuleScores.priceSpike,

    ReasonType.institutionalBuy => RuleScores.institutionalShift,
    ReasonType.institutionalSell => RuleScores.institutionalShiftSell,
    ReasonType.newsRelated => RuleScores.newsRelated,
    ReasonType.kdGoldenCross => RuleScores.kdGoldenCross,
    ReasonType.kdDeathCross => RuleScores.kdDeathCross,
    ReasonType.institutionalBuyStreak => RuleScores.institutionalBuyStreak,
    ReasonType.institutionalSellStreak => RuleScores.institutionalSellStreak,
    // K 線型態（多空分離）
    ReasonType.patternDoji => RuleScores.patternDoji,
    ReasonType.patternDojiBearish => RuleScores.patternDojiBearish,
    ReasonType.patternBullishEngulfing => RuleScores.patternEngulfingBullish,
    ReasonType.patternBearishEngulfing => RuleScores.patternEngulfingBearish,
    ReasonType.patternHammer => RuleScores.patternHammerBullish,
    ReasonType.patternHangingMan => RuleScores.patternHammerBearish,
    ReasonType.patternGapUp => RuleScores.patternGapUp,
    ReasonType.patternGapDown => RuleScores.patternGapDown,
    ReasonType.patternMorningStar => RuleScores.patternMorningStar,
    ReasonType.patternEveningStar => RuleScores.patternEveningStar,
    ReasonType.patternThreeWhiteSoldiers =>
      RuleScores.patternThreeWhiteSoldiers,
    ReasonType.patternThreeBlackCrows => RuleScores.patternThreeBlackCrows,
    // 第三階段訊號
    ReasonType.week52High => RuleScores.week52High,
    ReasonType.week52Low => RuleScores.week52Low,
    ReasonType.maAlignmentBullish => RuleScores.maAlignmentBullish,
    ReasonType.reclaimMa20 => RuleScores.reclaimMa20,
    ReasonType.reclaimMa60 => RuleScores.reclaimMa60,
    ReasonType.breakMa20 => RuleScores.breakMa20,
    ReasonType.breakMa60 => RuleScores.breakMa60,
    ReasonType.coilingBelowMa20 => RuleScores.coilingBelowMa20,
    ReasonType.coilingBelowMa60 => RuleScores.coilingBelowMa60,
    ReasonType.maAlignmentBearish => RuleScores.maAlignmentBearish,
    ReasonType.rsiExtremeOverbought => RuleScores.rsiExtremeOverboughtSignal,
    ReasonType.rsiExtremeOversold => RuleScores.rsiExtremeOversoldSignal,
    // 第四階段訊號
    ReasonType.foreignShareholdingIncreasing =>
      RuleScores.foreignShareholdingIncreasing,
    ReasonType.foreignShareholdingDecreasing =>
      RuleScores.foreignShareholdingDecreasing,
    ReasonType.dayTradingHigh => RuleScores.dayTradingHigh,
    ReasonType.dayTradingExtreme => RuleScores.dayTradingExtreme,
    ReasonType.concentrationHigh => RuleScores.concentrationHigh,
    // 第五階段訊號
    ReasonType.priceVolumeWeakRally => RuleScores.priceVolumeWeakRally,
    ReasonType.priceVolumeBearishDivergence =>
      RuleScores.priceVolumeBearishDivergence,
    ReasonType.highVolumeBreakout => RuleScores.highVolumeBreakout,
    ReasonType.lowVolumeAccumulation => RuleScores.lowVolumeAccumulation,
    // 第六階段訊號
    ReasonType.revenueYoySurge => RuleScores.revenueYoySurge,
    ReasonType.revenueYoyDecline => RuleScores.revenueYoyDecline,
    ReasonType.revenueMomGrowth => RuleScores.revenueMomGrowth,
    ReasonType.revenueNewHigh => RuleScores.revenueNewHigh,
    ReasonType.highDividendYield => RuleScores.highDividendYield,
    ReasonType.peUndervalued => RuleScores.peUndervalued,
    ReasonType.peOvervalued => RuleScores.peOvervalued,
    ReasonType.pbrUndervalued => RuleScores.pbrUndervalued,
    // Killer Features 訊號
    ReasonType.tradingWarningAttention => RuleScores.tradingWarningAttention,
    ReasonType.tradingWarningDisposal => RuleScores.tradingWarningDisposal,
    ReasonType.insiderSellingStreak => RuleScores.insiderSellingStreak,
    ReasonType.insiderSignificantBuying => RuleScores.insiderSignificantBuying,
    ReasonType.highPledgeRatio => RuleScores.highPledgeRatio,
    ReasonType.foreignConcentrationWarning =>
      RuleScores.foreignConcentrationWarning,
    ReasonType.foreignExodus => RuleScores.foreignExodus,
    // EPS 訊號
    ReasonType.epsYoYSurge => RuleScores.epsYoYSurge,
    ReasonType.epsConsecutiveGrowth => RuleScores.epsConsecutiveGrowth,
    ReasonType.epsTurnaround => RuleScores.epsTurnaround,
    ReasonType.epsDeclineWarning => RuleScores.epsDeclineWarning,
    ReasonType.roeExcellent => RuleScores.roeExcellent,
    ReasonType.roeImproving => RuleScores.roeImproving,
    ReasonType.roeDeclining => RuleScores.roeDeclining,
    // 第 9 階段：強股回檔進場
    ReasonType.pullbackToMa20 => RuleScores.pullbackToMa20,
    ReasonType.pullbackToMa10 => RuleScores.pullbackToMa10,
    ReasonType.hammerAtSupport => RuleScores.hammerAtSupport,
    ReasonType.kdHighPullback => RuleScores.kdHighPullback,
  };
}

/// ScoringMode 分類擴充：將 ReasonType 對應到 user-facing scoring mode
///
/// 用 switch (compiler 強制 exhaustive) 確保每條新增 ReasonType 都要顯式
/// 給定 mode，避免 silent miss 進 neutral 而被無視。
extension ReasonTypeScoringMode on ReasonType {
  /// 該 rule 屬於哪個 mode
  ///
  /// **Rule 分類原則**（依使用者「找股目的」而非「rule 類型」）：
  /// - momentumEntry: 反轉 / 突破 / 底部訊號，以及部分基本面與估值訊號 — 上升
  ///   趨勢中順勢初升的進場點（名冊與 60D>0 gate 的張力見 [ScoringMode.momentumEntry]）
  /// - strengthObserve: 大漲 / 帶量突破 / 法人連買 / 多頭排列 — 你想追蹤強勢股、等回檔
  /// - weaknessObserve: 強股回檔到均線 / 支撐錘子 / KD 高檔回落 — 找回檔進場點
  /// - neutral: 看空 K 線、監管與籌碼警示、待校準的訊號、觸發頻繁但無 alpha 的
  ///   訊號 — 仍寫進 daily_reason（掃描、詳情頁可見；今日分頁不顯示成理由，警示
  ///   類改為風險徽章），但不影響任何 mode 排名
  ScoringMode get scoringMode => switch (this) {
    // ============ Mode A: 起漲候選（15 條 — 含 patternHammer 2026-06-20 回歸）============
    // 反轉 / 突破 / 底部 / 逆勢買進訊號 — user mental model「趨勢中順勢初升進場」。
    ReasonType.reversalW2S => ScoringMode.momentumEntry,
    ReasonType.techBreakout => ScoringMode.momentumEntry,
    ReasonType.patternBullishEngulfing => ScoringMode.momentumEntry,
    ReasonType.patternHammer =>
      ScoringMode.momentumEntry, // 低檔錘子反轉（trendState != up 才 fire）
    ReasonType.patternMorningStar => ScoringMode.momentumEntry,
    ReasonType.patternThreeWhiteSoldiers => ScoringMode.momentumEntry,
    ReasonType.lowVolumeAccumulation =>
      ScoringMode.momentumEntry, // 唯一真 Stage 1 蓄勢（20D -14.6% 真沒漲）
    // **2026-06-20 階段重設計移出**：maAlignmentBullish（多頭排列）= 趨勢已確立
    // = Weinstein Stage 2「已在漲」（20D +36.9%、76% 已漲>15%），不是「即將起漲」
    // → 搬 Mode B。這是「已漲卡 A」的最大單一來源。
    // **同移出**：highVolumeBreakout（高檔爆量突破、已突破）→ Mode B
    // **2026-06-20 階段重設計移入**：kdGoldenCross = 低檔金叉 = Stage 1→2 反轉啟動、
    // 屬「準備起漲」（rule 自身要求低檔、放「已漲強勢」tab 自相矛盾）。
    ReasonType.kdGoldenCross => ScoringMode.momentumEntry,
    ReasonType.epsTurnaround => ScoringMode.momentumEntry,
    ReasonType.revenueMomGrowth => ScoringMode.momentumEntry,
    ReasonType.roeImproving => ScoringMode.momentumEntry,
    ReasonType.insiderSignificantBuying => ScoringMode.momentumEntry,
    ReasonType.pbrUndervalued =>
      ScoringMode.momentumEntry, // 唯一 backtest 正 alpha
    // **2026-06-19 audit 移入 Mode A**：hardcoded 正分、原本歸 Mode C 不合理：
    ReasonType.patternDoji => ScoringMode.momentumEntry, // +10 低檔十字線反轉
    // **2026-06-20 A/B 體檢移出 week52Low**：0 fire ever（前提空頭 close<MA20<MA60
    // 與 momentum 母體 75% UP 互斥）+ backtest hit 0.27 強反指標 → 搬 neutral
    ReasonType.rsiExtremeOversold => ScoringMode.momentumEntry, // +10 RSI 超賣反彈
    // ============ Mode B: 強勢觀察（= Weinstein Stage 2 上漲中、強勢領導）============
    // 已漲 / 趨勢確立 / 籌碼面強 — user mental model「追蹤強勢、等回檔」。
    // **2026-06-20 階段重設計移入**：maAlignmentBullish（多頭排列 = 趨勢確立的定義）
    // + highVolumeBreakout（已突破）— 兩條都是 Stage 2「已在漲」訊號。
    // **移出**：kdGoldenCross（低檔金叉 = Stage 1→2 反轉 → 搬 Mode A）；
    //          dayTradingHigh（高當沖 = 投機過熱/散戶接刀警訊、非趨勢強度 → 搬 neutral）。
    ReasonType.priceSpike => ScoringMode.strengthObserve,
    ReasonType.patternGapUp => ScoringMode.strengthObserve,
    ReasonType.week52High => ScoringMode.strengthObserve, // 最乾淨 Stage 2 marker
    ReasonType.institutionalBuyStreak => ScoringMode.strengthObserve,
    ReasonType.foreignShareholdingIncreasing => ScoringMode.strengthObserve,
    ReasonType.institutionalBuy => ScoringMode.strengthObserve,
    ReasonType.volumeSpike => ScoringMode.strengthObserve,
    ReasonType.newsRelated =>
      ScoringMode.neutral, // RSS 標題 keyword 情緒為弱訊號 → 移出選股評分（新聞頁 + 證據 chip 仍顯示）
    ReasonType.roeExcellent => ScoringMode.strengthObserve,
    ReasonType.highVolumeBreakout => ScoringMode.strengthObserve, // 已突破
    ReasonType.maAlignmentBullish =>
      ScoringMode.strengthObserve, // 多頭排列 = 趨勢確立 Stage 2
    // ============ Mode C: 回檔觀察（v2.1 — 強股回檔進場、4 條正分主訊號）============
    // **2026-06-19 v2 audit 重定義**：user 真實意圖是「**強股剛開始回檔、找進場時機**」。
    // identifier `weaknessObserve` 保留避免 DB migration、tab name i18n 改「回檔觀察」。
    //
    // 組成：**只有 4 條正分主訊號**（gate 必過、from pullback_rules.dart）：
    //     pullbackToMa20 (+15) / pullbackToMa10 (+12) / hammerAtSupport (+18) /
    //     kdHighPullback (+12)
    //
    // **2026-06-20 早期體檢修正 A（warning 壓分 bug）**：原本還掛 7 條負分 warning
    // (吊人線 -12 等) 當 context chip，但它們污染 Mode C score 加總 — 例 2637 fire
    // HAMMER_AT_SUPPORT +18 + PATTERN_HANGING_MAN -12 → Mode C SUM=6 < gate 12 →
    // 合格的強股回檔被冤枉隱藏。7 條 warning 全移到 neutral（仍 fire 寫 daily_reason、
    // 只是不污染 Mode C 排名）。Mode C 變純正分「進場機會」tab、不再有負分扣分。
    //
    // **2026-06-20 早期體檢修正 P0**：patternHammer 移回 Mode A（HammerRule 要
    // trendState != up、跟強股互斥 → 死碼）。強股錘子角色由 HammerAtSupportRule 擔。
    ReasonType.pullbackToMa20 => ScoringMode.weaknessObserve, // 主 +15 深回檔
    ReasonType.pullbackToMa10 =>
      ScoringMode.weaknessObserve, // 主 +12 淺回檔（2026-06-20 B2 加）
    ReasonType.hammerAtSupport => ScoringMode.weaknessObserve, // 主 +18
    ReasonType.kdHighPullback => ScoringMode.weaknessObserve, // 主 +12
    // ============ Neutral（不參與三模式選股）============
    // **2026-06-20 修正 A 移入 7 條**（原 Mode C warning context、會壓分 bug）：
    ReasonType.patternHangingMan => ScoringMode.neutral, // 高檔吊人線
    ReasonType.patternDojiBearish => ScoringMode.neutral, // 高檔十字
    ReasonType.patternEveningStar => ScoringMode.neutral, // 暮星
    ReasonType.patternBearishEngulfing => ScoringMode.neutral, // 空頭吞噬
    ReasonType.patternGapDown => ScoringMode.neutral, // 跳空下跌
    ReasonType.rsiExtremeOverbought => ScoringMode.neutral, // RSI 超買
    ReasonType.foreignConcentrationWarning => ScoringMode.neutral, // 外資集中警示
    // ============ Neutral（v2 大幅擴充）============
    // **2026-06-19 v2 移入 20 條從舊 Mode C**：「已弱化趨勢」類訊號 — 不符「**剛開始**
    // 回檔」mental model：
    ReasonType.reversalS2W => ScoringMode.neutral, // 趨勢翻轉、已弱化
    ReasonType.techBreakdown => ScoringMode.neutral, // 已破支撐
    ReasonType.priceVolumeBearishDivergence => ScoringMode.neutral, // 跟「量縮」相反
    ReasonType.patternThreeBlackCrows => ScoringMode.neutral, // 三烏鴉、已過頭
    ReasonType.maAlignmentBearish => ScoringMode.neutral, // 空頭排列、趨勢已破
    ReasonType.kdDeathCross => ScoringMode.neutral, // 已死叉、新 rule C 反面
    ReasonType.foreignShareholdingDecreasing => ScoringMode.neutral, // lagging
    ReasonType.institutionalSell => ScoringMode.neutral, // lagging
    ReasonType.institutionalSellStreak => ScoringMode.neutral, // 趨勢性鬆動
    ReasonType.foreignExodus => ScoringMode.neutral, // 趨勢破壞前兆
    ReasonType.tradingWarningAttention => ScoringMode.neutral, // 監管警示、非進場時機
    ReasonType.tradingWarningDisposal => ScoringMode.neutral, // 處置股絕不在 buy mode
    ReasonType.insiderSellingStreak => ScoringMode.neutral, // 公司面警訊
    ReasonType.highPledgeRatio => ScoringMode.neutral, // 質押風險無關回檔
    ReasonType.dayTradingExtreme => ScoringMode.neutral, // 投機、非健康回檔
    // **2026-06-20 階段重設計移入**：dayTradingHigh（高當沖比例）= 投機過熱 /
    // 散戶接刀換手率、非趨勢強度；跟 dayTradingExtreme 同 namespace 對齊入 neutral。
    ReasonType.dayTradingHigh => ScoringMode.neutral,
    // MA 穿越 4 條與均線下方蓄勢 2 條(2026-07-31):零歷史紀錄,neutral 起步收 rule_accuracy,
    // 一季後由校準實證判決升格進 mode 或歸零
    ReasonType.reclaimMa20 => ScoringMode.neutral,
    ReasonType.reclaimMa60 => ScoringMode.neutral,
    ReasonType.breakMa20 => ScoringMode.neutral,
    ReasonType.breakMa60 => ScoringMode.neutral,
    ReasonType.coilingBelowMa20 => ScoringMode.neutral,
    ReasonType.coilingBelowMa60 => ScoringMode.neutral,
    ReasonType.peOvervalued => ScoringMode.neutral, // 強股 feature、誤殺
    ReasonType.revenueYoyDecline => ScoringMode.neutral, // 基本面 lagging
    ReasonType.epsDeclineWarning => ScoringMode.neutral, // 基本面 lagging
    ReasonType.roeDeclining => ScoringMode.neutral, // 基本面 lagging
    // 既有 neutral（背景 filter / value rule 等）
    ReasonType.concentrationHigh => ScoringMode.neutral, // demote 至 0
    ReasonType.revenueNewHigh => ScoringMode.neutral, // demote 至 0
    ReasonType.revenueYoySurge => ScoringMode.neutral, // calibrated cut
    ReasonType.highDividendYield => ScoringMode.neutral, // value 非 momentum
    ReasonType.peUndervalued => ScoringMode.neutral, // 跟 PBR redundant
    ReasonType.epsConsecutiveGrowth => ScoringMode.neutral,
    ReasonType.epsYoYSurge => ScoringMode.neutral,
    ReasonType.priceVolumeWeakRally => ScoringMode.neutral, // 觸發條件「價漲量縮」與弱勢矛盾
    // **2026-06-20 A/B 體檢移入**：52 週低 = 空頭創低、放「起漲」自相矛盾、且 0 fire
    // ever（前提空頭與 momentum 母體互斥）+ backtest 強反指標。
    ReasonType.week52Low => ScoringMode.neutral,
  };
}

/// i18n 鍵擴充：將 ReasonType 對應到翻譯鍵
extension ReasonTypeI18n on ReasonType {
  /// 取得理由標籤的 i18n 鍵
  String get i18nLabelKey => switch (this) {
    ReasonType.reversalW2S => 'reasons.reversalW2S',
    ReasonType.reversalS2W => 'reasons.reversalS2W',
    ReasonType.techBreakout => 'reasons.breakout',
    ReasonType.techBreakdown => 'reasons.breakdown',
    ReasonType.volumeSpike => 'reasons.volumeSpike',
    ReasonType.priceSpike => 'reasons.priceSpike',
    ReasonType.institutionalBuy => 'reasons.institutionalBuy',
    ReasonType.institutionalSell => 'reasons.institutionalSell',
    ReasonType.newsRelated => 'reasons.news',
    ReasonType.kdGoldenCross => 'reasons.kdGoldenCross',
    ReasonType.kdDeathCross => 'reasons.kdDeathCross',
    ReasonType.institutionalBuyStreak => 'reasons.institutionalBuyStreak',
    ReasonType.institutionalSellStreak => 'reasons.institutionalSellStreak',
    // K 線型態
    ReasonType.patternDoji => 'reasons.patternDoji',
    ReasonType.patternDojiBearish => 'reasons.patternDojiBearish',
    ReasonType.patternBullishEngulfing => 'reasons.patternBullishEngulfing',
    ReasonType.patternBearishEngulfing => 'reasons.patternBearishEngulfing',
    ReasonType.patternHammer => 'reasons.patternHammer',
    ReasonType.patternHangingMan => 'reasons.patternHangingMan',
    ReasonType.patternGapUp => 'reasons.patternGapUp',
    ReasonType.patternGapDown => 'reasons.patternGapDown',
    ReasonType.patternMorningStar => 'reasons.patternMorningStar',
    ReasonType.patternEveningStar => 'reasons.patternEveningStar',
    ReasonType.patternThreeWhiteSoldiers => 'reasons.patternThreeWhiteSoldiers',
    ReasonType.patternThreeBlackCrows => 'reasons.patternThreeBlackCrows',
    // 52 週高低點與均線排列
    ReasonType.week52High => 'reasons.week52High',
    ReasonType.week52Low => 'reasons.week52Low',
    ReasonType.maAlignmentBullish => 'reasons.maAlignmentBullish',
    ReasonType.reclaimMa20 => 'reasons.reclaimMa20',
    ReasonType.reclaimMa60 => 'reasons.reclaimMa60',
    ReasonType.breakMa20 => 'reasons.breakMa20',
    ReasonType.breakMa60 => 'reasons.breakMa60',
    ReasonType.coilingBelowMa20 => 'reasons.coilingBelowMa20',
    ReasonType.coilingBelowMa60 => 'reasons.coilingBelowMa60',
    ReasonType.maAlignmentBearish => 'reasons.maAlignmentBearish',
    ReasonType.rsiExtremeOverbought => 'reasons.rsiExtremeOverbought',
    ReasonType.rsiExtremeOversold => 'reasons.rsiExtremeOversold',
    // 擴展市場資料
    ReasonType.foreignShareholdingIncreasing =>
      'reasons.foreignShareholdingIncreasing',
    ReasonType.foreignShareholdingDecreasing =>
      'reasons.foreignShareholdingDecreasing',
    ReasonType.dayTradingHigh => 'reasons.dayTradingHigh',
    ReasonType.dayTradingExtreme => 'reasons.dayTradingExtreme',
    ReasonType.concentrationHigh => 'reasons.concentrationHigh',
    // 量價背離
    ReasonType.priceVolumeWeakRally => 'reasons.priceVolumeWeakRally',
    ReasonType.priceVolumeBearishDivergence =>
      'reasons.priceVolumeBearishDivergence',
    ReasonType.highVolumeBreakout => 'reasons.highVolumeBreakout',
    ReasonType.lowVolumeAccumulation => 'reasons.lowVolumeAccumulation',
    // 基本面訊號
    ReasonType.revenueYoySurge => 'reasons.revenueYoySurge',
    ReasonType.revenueYoyDecline => 'reasons.revenueYoyDecline',
    ReasonType.revenueMomGrowth => 'reasons.revenueMomGrowth',
    ReasonType.revenueNewHigh => 'reasons.revenueNewHigh',
    ReasonType.highDividendYield => 'reasons.highDividendYield',
    ReasonType.peUndervalued => 'reasons.peUndervalued',
    ReasonType.peOvervalued => 'reasons.peOvervalued',
    ReasonType.pbrUndervalued => 'reasons.pbrUndervalued',
    // EPS 分析
    ReasonType.epsYoYSurge => 'reasons.epsYoYSurge',
    ReasonType.epsConsecutiveGrowth => 'reasons.epsConsecutiveGrowth',
    ReasonType.epsTurnaround => 'reasons.epsTurnaround',
    ReasonType.epsDeclineWarning => 'reasons.epsDeclineWarning',
    // ROE 分析
    ReasonType.roeExcellent => 'reasons.roeExcellent',
    ReasonType.roeImproving => 'reasons.roeImproving',
    ReasonType.roeDeclining => 'reasons.roeDeclining',
    // 警示與內部人訊號
    ReasonType.tradingWarningAttention => 'reasons.tradingWarningAttention',
    ReasonType.tradingWarningDisposal => 'reasons.tradingWarningDisposal',
    ReasonType.insiderSellingStreak => 'reasons.insiderSellingStreak',
    ReasonType.insiderSignificantBuying => 'reasons.insiderSignificantBuying',
    ReasonType.highPledgeRatio => 'reasons.highPledgeRatio',
    ReasonType.foreignConcentrationWarning =>
      'reasons.foreignConcentrationWarning',
    ReasonType.foreignExodus => 'reasons.foreignExodus',
    // 第 9 階段：強股回檔進場
    ReasonType.pullbackToMa20 => 'reasons.pullbackToMa20',
    ReasonType.pullbackToMa10 => 'reasons.pullbackToMa10',
    ReasonType.hammerAtSupport => 'reasons.hammerAtSupport',
    ReasonType.kdHighPullback => 'reasons.kdHighPullback',
  };

  /// 取得理由說明的 i18n 鍵（用於 tooltip），無對應則回傳 null
  String? get i18nTooltipKey => switch (this) {
    ReasonType.reversalW2S => 'summary.reversalW2S',
    ReasonType.reversalS2W => 'summary.reversalS2W',
    ReasonType.techBreakout => 'summary.breakout',
    ReasonType.techBreakdown => 'summary.breakdown',
    ReasonType.volumeSpike => 'reasonTip.volumeSpike',
    ReasonType.priceSpike => 'reasonTip.priceSpike',
    ReasonType.institutionalBuy => 'reasonTip.institutional',
    ReasonType.institutionalSell => 'reasonTip.institutional',
    ReasonType.newsRelated => 'reasonTip.news',
    ReasonType.kdGoldenCross => 'summary.kdGoldenCross',
    ReasonType.kdDeathCross => 'summary.kdDeathCross',
    ReasonType.institutionalBuyStreak => 'summary.institutionalBuyStreak',
    ReasonType.institutionalSellStreak => 'summary.institutionalSellStreak',
    // K 線型態
    ReasonType.patternDoji => 'summary.patternDoji',
    ReasonType.patternDojiBearish => 'reasonTip.patternDojiBearish',
    ReasonType.patternBullishEngulfing => 'summary.patternBullishEngulfing',
    ReasonType.patternBearishEngulfing => 'summary.patternBearishEngulfing',
    ReasonType.patternHammer => 'summary.patternHammer',
    ReasonType.patternHangingMan => 'summary.patternHangingMan',
    ReasonType.patternMorningStar => 'summary.patternMorningStar',
    ReasonType.patternEveningStar => 'summary.patternEveningStar',
    ReasonType.patternThreeWhiteSoldiers => 'summary.patternThreeWhiteSoldiers',
    ReasonType.patternThreeBlackCrows => 'summary.patternThreeBlackCrows',
    ReasonType.patternGapUp => 'summary.patternGapUp',
    ReasonType.patternGapDown => 'summary.patternGapDown',
    // 52 週高低點與均線排列
    ReasonType.week52High => 'summary.week52High',
    ReasonType.week52Low => 'summary.week52Low',
    ReasonType.maAlignmentBullish => 'summary.maAlignmentBullish',
    ReasonType.reclaimMa20 => 'summary.reclaimMa20',
    ReasonType.reclaimMa60 => 'summary.reclaimMa60',
    ReasonType.breakMa20 => 'summary.breakMa20',
    ReasonType.breakMa60 => 'summary.breakMa60',
    ReasonType.coilingBelowMa20 => 'summary.coilingBelowMa20',
    ReasonType.coilingBelowMa60 => 'summary.coilingBelowMa60',
    ReasonType.maAlignmentBearish => 'summary.maAlignmentBearish',
    ReasonType.rsiExtremeOverbought => 'reasonTip.rsiOverbought',
    ReasonType.rsiExtremeOversold => 'reasonTip.rsiOversold',
    // 擴展市場資料
    ReasonType.foreignShareholdingIncreasing => 'reasonTip.foreignIncreasing',
    ReasonType.foreignShareholdingDecreasing => 'reasonTip.foreignDecreasing',
    ReasonType.dayTradingHigh => 'reasonTip.dayTradingHigh',
    ReasonType.dayTradingExtreme => 'reasonTip.dayTradingHigh',
    ReasonType.concentrationHigh => 'reasonTip.concentrationHigh',
    // 量價背離
    ReasonType.priceVolumeWeakRally => 'reasonTip.priceVolumeWeakRally',
    ReasonType.priceVolumeBearishDivergence => 'reasonTip.bearishDivergence',
    ReasonType.highVolumeBreakout => 'reasonTip.highVolumeBreakout',
    ReasonType.lowVolumeAccumulation => 'reasonTip.lowVolumeAccumulation',
    // 基本面訊號
    ReasonType.revenueYoySurge => 'reasonTip.revenueYoySurge',
    ReasonType.revenueYoyDecline => 'reasonTip.revenueYoyDecline',
    ReasonType.revenueMomGrowth => 'reasonTip.revenueMomGrowth',
    ReasonType.revenueNewHigh => 'reasonTip.revenueNewHigh',
    ReasonType.highDividendYield => 'reasonTip.highDividendYield',
    ReasonType.peUndervalued => 'reasonTip.peUndervalued',
    ReasonType.peOvervalued => 'reasonTip.peOvervalued',
    ReasonType.pbrUndervalued => 'reasonTip.pbrUndervalued',
    // EPS 分析
    ReasonType.epsYoYSurge => 'reasonTip.epsYoYSurge',
    ReasonType.epsConsecutiveGrowth => 'reasonTip.epsConsecutiveGrowth',
    ReasonType.epsTurnaround => 'reasonTip.epsTurnaround',
    ReasonType.epsDeclineWarning => 'reasonTip.epsDecline',
    // ROE 分析
    ReasonType.roeExcellent => 'reasonTip.roeExcellent',
    ReasonType.roeImproving => 'reasonTip.roeImproving',
    ReasonType.roeDeclining => 'reasonTip.roeDeclining',
    // 警示與內部人訊號
    ReasonType.tradingWarningAttention => 'summary.warningAttention',
    ReasonType.tradingWarningDisposal => 'summary.warningDisposal',
    ReasonType.insiderSellingStreak => 'reasonTip.insiderSelling',
    ReasonType.insiderSignificantBuying => 'summary.insiderBuying',
    ReasonType.highPledgeRatio => 'summary.highPledge',
    ReasonType.foreignConcentrationWarning => 'reasonTip.foreignConcentration',
    ReasonType.foreignExodus => 'reasonTip.foreignExodus',
    // 第 9 階段：強股回檔進場
    ReasonType.pullbackToMa20 => 'reasonTip.pullbackToMa20',
    ReasonType.pullbackToMa10 => 'reasonTip.pullbackToMa10',
    ReasonType.hammerAtSupport => 'reasonTip.hammerAtSupport',
    ReasonType.kdHighPullback => 'reasonTip.kdHighPullback',
  };
}

/// 從原因代碼字串查找對應的 [ReasonType]
///
/// 支援 SNAKE_CASE（DB 原始碼）、camelCase（JSON 格式）及歷史別名。
final _reasonCodeMap = <String, ReasonType>{
  for (final rt in ReasonType.values) ...<String, ReasonType>{
    rt.code: rt,
    rt.name: rt,
  },
  // Legacy aliases
  'INSTITUTIONAL_SHIFT': ReasonType.institutionalBuy,
  'institutionalShift': ReasonType.institutionalBuy,
};

ReasonType? reasonTypeFromCode(String code) => _reasonCodeMap[code];

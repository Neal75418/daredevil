/// 篩選模式 — Today screen 主 tab 的分類軸
///
/// **動機**：使用者用 Daredevil 不是只找「會漲的股票」，是 3 種觀察心智：
/// - Mode A：起漲候選 — 上升趨勢中、貼近均線未過熱、剛出現進場訊號的順勢
///   初升股（60D>0 gate 篩掉長期弱勢反彈；非底部抄底）
/// - Mode B：強勢觀察 — 已大漲的股票，等回檔時機進場
/// - Mode C：回檔觀察 — 之前強、剛開始拉回的股票，找回檔進場時機（v2 重定義）
///
/// 跟 [Horizon] 是**正交**的兩個維度：mode 是用戶的觀察類型、horizon 是
/// 評估的時間軸。同一檔股票可同時出現在多個 mode、每個 mode 內各有 5D
/// 跟 60D 兩個 score。
enum ScoringMode {
  /// 起漲候選 — 上升趨勢中的順勢初升進場點
  ///
  /// 用於「我想在上升趨勢裡、趁還沒過熱找順勢進場點」。**60D>0 gate**
  /// 要求已有既定動能 → 是「順勢初升（趨勢中的淺回貼均線）」而非「底部
  /// 抄底 / 還沒漲」。
  ///
  /// ⚠️ 名冊含反轉/底部訊號（弱轉強、KD低檔金叉、錘子、量縮蓄勢、RSI
  /// 超賣、PBR 低估——唯一有 backtest alpha 的 value rule），但這些多為
  /// 「崩跌後打底」設計、其母體 60D 常 <0，會被 60D>0 gate 擋掉；實際只
  /// 在「60D 為正但近期淺回」的窄族群觸發（gate 與規則設計意圖的已知張力）。
  momentumEntry,

  /// 強勢觀察 — 已漲、等回檔
  ///
  /// 用於「我想追蹤強勢股、等回檔機會進場」。
  /// 包含：大漲、跳空、52 週高、法人連買、外資加碼、KD 黃金、爆量、新聞
  /// 帶量、RSI 超買（警示中夾雜進場資訊）。
  strengthObserve,

  /// 回檔觀察 — 強股剛開始回檔、找進場時機（identifier 沿用 weaknessObserve
  /// 避免 DB migration；tab name 已改「回檔觀察」）
  ///
  /// **2026-06-19 v2 重定義**：原為「弱勢警示」tab、現為「強股回檔進場」。
  /// 只含 3 條正分主訊號（回檔到 MA20 / MA10、支撐錘子、KD 高檔回落）。
  /// 舊弱勢警訊（空頭排列 / 注意股 / 處置股 / 質押 / 超買…）已全移 [neutral]，
  /// 改由 Today 卡片的 RiskBadgeCluster 風險徽章呈現（見 RiskWarnings）。
  weaknessObserve,

  /// 中性 — 不貢獻任何 mode score（背景 filter / value rule）
  ///
  /// 這些 rule 仍會 fire 寫進 daily_reason、evidence chip 仍顯示，但**不影響**
  /// 任何 mode 的排名。包含：CONCENTRATION_HIGH（已 demote）、REVENUE_NEW_HIGH
  /// （已 demote）、HIGH_DIVIDEND_YIELD（value 非 momentum）、PE_UNDERVALUED
  /// （跟 PBR_UNDERVALUED redundant）等。
  ///
  /// 等 calibration 累積資料、threshold 調好後可考慮重新歸類。
  neutral;

  /// 中文顯示名
  String get displayKey => switch (this) {
    ScoringMode.momentumEntry => 'scoringMode.momentumEntry',
    ScoringMode.strengthObserve => 'scoringMode.strengthObserve',
    ScoringMode.weaknessObserve => 'scoringMode.weaknessObserve',
    ScoringMode.neutral => 'scoringMode.neutral',
  };

  /// Mode routing priority — eligibility-first assignment 時的優先順序
  ///
  /// **2026-06-19 v2 audit 引入**：當一檔股票對多個 mode 都 eligible（罕見、但
  /// edge case 存在）時，按此優先順序選擇 mode，數字越大優先級越高、tiebreak 用
  /// max |modeScoreShort|。
  ///
  /// 設計理由：
  /// - **weaknessObserve (pullbackEntry) 3 — 最 actionable**：「強股回檔進場」是
  ///   user 真正下單的時刻、最該被 surface 出來
  /// - **momentumEntry 2 — 中**：「起漲候選」是研究階段
  /// - **strengthObserve 1 — 監控**：「強勢觀察」純監控、不急
  ///
  /// 實務上 Mode B / Mode C eligibility 已透過 todayPct (>0 vs ≤0) 互斥，這個
  /// priority 主要處理 Mode A / Mode C 邊界 case（罕見）。
  int get routingPriority => switch (this) {
    ScoringMode.weaknessObserve => 3, // pullbackEntry — 最 actionable
    ScoringMode.momentumEntry => 2,
    ScoringMode.strengthObserve => 1,
    ScoringMode.neutral => 0,
  };

  /// Tab 是否在 Today 顯示（neutral 不顯示為 tab）
  bool get isUserFacing => this != ScoringMode.neutral;

  /// User-facing modes (Today screen tabs)
  static const userFacingModes = [
    ScoringMode.momentumEntry,
    ScoringMode.strengthObserve,
    ScoringMode.weaknessObserve,
  ];
}

/// Mode-aware UI filter thresholds（2026-06-19 audit Action 5）
///
/// 治掉「**已大漲股票卡在 Mode A 起漲候選**」與「**漲停股出現在 Mode C 弱勢
/// 觀察**」兩種違反 mental model 的 case：
/// - 1907 永豐餘 5D +9.73% 還在「起漲」（已漲一波）
/// - 4551 智伸科 漲停 +9.93% 還在「弱勢」（RSI 超買 + 吊人線 fires 但今天漲）
///
/// 跟 mode-aware sort（[ScoringMode.weaknessObserve] 用 sum ASC）配套：先按
/// score 排再 anti-filter、被踢的不算 quota；filter 後不足 30 也照舊。
abstract final class ModeFilters {
  /// Mode A（起漲候選）MA20 正乖離率上限（+15%）— **2026-06-20 Wave 2a**
  ///
  /// analyst「初升可進 vs 已延伸」看的是「離 MA20 多遠（延伸度 / 乖離）」而非
  /// 「最近漲幅」。`(close − MA20) / MA20 > +15%` = 已漲一波、過度延伸、不符
  /// 「順勢初升、未過熱」語意 → 踢出（若強勢會自動導去 Mode B）。
  ///
  /// **取代**舊「5D 漲幅 8% + score≥50 豁免 + 20D≤20% 副條件」整套補丁：漲幅
  /// proxy + 豁免特例反覆漏掉「強反轉**已漲一波**」（6742 乖離+15.7% / 6770
  /// 20D+25.5% 霸榜）。乖離率直接量延伸度、無需豁免。
  ///
  /// +15% = 台股標準「正乖離偏熱」線（實測當日 107 檔候選踢 33 檔/31%，清掉
  /// >20% 大幅延伸的 24 檔 + 12-20% 段、保留 ≤15% 早期移動股）。
  /// **CALIBRATION_PENDING**：缺 forward backtest，上線後看 fire 範圍再調。
  static const double modeAMaxBiasMa20Pct = 15.0;

  /// Mode A 會動底線：60D 報酬 ≤ 此值（%）者不得入起漲候選。
  ///
  /// **2026-07-21 回測依據**（calibration.db 2017-05~2026-07、A 價格包絡
  /// 代理宇宙、次日開盤進場、cross-sectional demean）：60D≤0 桶 20D 前瞻
  /// 超額 −0.39% vs >0 桶 +0.43%（差 −0.81pp、|t|≈54），三分期符號全
  /// 穩定且近段最強（−1.26pp）。實例：2026-07-21 大漲日 A 榜前 30 有
  /// 20 檔 60D 為負（最深 −20%），台積電（60D+16%）反被擠到第 28 名。
  /// 「起漲」語意要求已證明的動能；長期弱勢的低基期反彈不屬於此 tab。
  /// null（history < 61）permissive 不擋，同其他 price gate 原則。
  static const double modeAMinRet60Pct = 0.0;

  /// Mode A 剔除「**當日**漲幅 > 8%」（無豁免）
  ///
  /// 跟 [modeAMaxBiasMa20Pct] 互補：乖離 gate 擋「累積已延伸」、今日 filter
  /// 擋「**今天突然爆衝**」（5D 累積還沒高但今天 gap up +9.92% 漲停的 case，
  /// 如 6651 全宇昕 / 3090 日電貿 — 從低於 MA20 跳上來、乖離未必過線）。
  ///
  /// **沒有強訊號豁免**：分數再高、今天就漲 +9% 也算追高、自動導去 Mode B。
  ///
  /// 跟 [modeCMaxTodayPct] (0%) 同一條 user mental model 軸：
  /// - 起漲候選：今日漲幅應「適度」（≤ 8%）
  /// - 回檔觀察：今日漲幅應「不正」（≤ 0%）
  static const double modeAExcludeTodayPct = 8.0;

  /// Mode C（回檔觀察 v2）今日漲幅上限
  ///
  /// **2026-06-19 v2 audit 重定義 Mode C 為「強股回檔進場」**：今日須收黑或平盤
  /// 才算「剛開始回檔」、上漲就不是回檔。strict `>` 比較讓 0.00% 平盤 stays。
  static const double modeCMaxTodayPct = 0.0;

  /// Mode C 今日跌幅下限（-4%、深 V 不算健康回檔）
  ///
  /// 「健康回檔」mental model = 強股**小幅**拉回提供進場時機。今日大跌 > 4% 通常
  /// 是恐慌賣壓 / 突發利空、不是 sweet spot 進場點。設 -4% 作 floor 過濾深 V。
  ///
  /// **CALIBRATION_PENDING**：-4% 是直覺值、缺 backtest。上線後看實際 fire 範圍
  /// 再調。
  static const double modeCMinTodayPct = -4.0;

  /// Mode C 最低 mode score（≥ +12）
  ///
  /// v2 Mode C 從「全負分警示」改為「正分機會」tab、score 門檻改正分。+12 對應
  /// 最弱的主訊號 `kdHighPullback`（單獨 fire 也夠 actionable）。
  static const double modeCMinScore = 12.0;

  /// Mode C eligibility 必過 gate：至少 1 條主訊號 rule fire
  ///
  /// 4 條主訊號 rule 提供「回檔進場時機」確認、舊負分 warning rule 單獨 fire 不
  /// 足以入 Mode C（避免「純警示無進場點」雜訊）。
  ///
  /// 這 3 條 rule 識別子用字串避免循環 import（ReasonType import scoring_mode、
  /// 反方向會 cycle）— 從 ReasonType.code 比對。
  ///
  /// **2026-06-20 早期體檢修正**：移除 PATTERN_HAMMER。HammerRule 要 trendState
  /// != up 才 fire、跟 Mode C「強股回檔」(trendState == up) 互斥 → 永遠 0 fire
  /// 的死碼 gate 入口。已搬回 Mode A、強股錘子角色由 HAMMER_AT_SUPPORT 擔。
  static const Set<String> modeCRequiredAnyOf = {
    'PULLBACK_TO_MA20', // 深回檔
    'PULLBACK_TO_MA10', // 淺回檔（2026-06-20 B2 加、日常可用頻率）
    'HAMMER_AT_SUPPORT',
    'KD_HIGH_PULLBACK',
  };

  /// 每個 tab 顯示上限 — **2026-06-20 Wave 2b** 從寫死 30 抽成具名常數
  ///
  /// 配合 Mode B 改 60D 報酬排序：排序修好後 top N 就是真正最強 N 檔、cap 才有
  /// 意義（舊 score 排序 corr+0.17、cut 點隨機，cap 30 砍掉的不見得比留的差）。
  /// 維持 30：30 檔是一天好掃的清單、#31+ 的 60D 確實較弱、漏的不多；要更廣覆蓋
  /// 改大此值即可（一行）。三個 tab 共用。
  static const int modeRecommendationCap = 30;

  /// 指派 floor：best-eligible mode 的 |modeScoreShort| 必須 ≥ 10 才指派
  ///
  /// 避免 eligibility-first 把「主要 mode 不合格、次要 mode 只有 trivial
  /// 分數」的股票塞進非主要 tab。
  ///
  /// 範例：股票 X 有 A=80（但 today +10% 被擋）/ B=0 / C=-2（today -1%）
  /// - 無 floor：C(-2) 是唯一合格 → 出現在 Mode C 弱勢 tab 但 score -2
  ///   是噪音、排在 -50 處置股下面也很怪
  /// - 有 floor ≥ 10：bestAbs = 2 < 10 → 整檔 drop ✅（今天訊號狀態不穩、
  ///   跳過比誤導好）
  static const int minRoutedAbsScore = 10;
}

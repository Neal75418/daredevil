/// 各推薦類型的分數
///
/// 分數層級反映訊號可靠性：
/// - 反轉訊號 (35)：最高 - 趨勢改變最具操作價值
/// - 技術訊號 (25)：中等 - 壓力/支撐突破
/// - 成交量異動 (22)：中等 - 現需 4 倍量 + 1.5% 價格變動
/// - 價格異動 (15)：較低 - 無量配合可能是雜訊
/// - 法人買超 (18)：台股重要指標 - 法人資金流入
/// - 法人賣超 (-12)：空方扣分 - 法人資金流出
/// - 新聞 (8)：輔助 - 僅提供背景資訊
///
/// ## 分數校準原則
///
/// | 層級 | 分數範圍 | 訊號類型 | 校準依據 |
/// |------|---------|---------|---------|
/// | S | 35 | 反轉訊號 (W2S) | 趨勢改變最具操作價值 |
/// | A | 20–28 | 突破/K線/法人連買/52週高 | 有明確方向且經量確認 |
/// | B | 15–18 | 法人轉向/KD/外資/殖利率 | 單一維度但可靠 |
/// | C | 8–12 | 新聞/十字線/52週低 | 輔助訊號或中性 |
/// | 扣分 | −5 ~ −50 | 空方/風險訊號 | 處置股最重(−50)，技術空方中等(−12~−25) |
///
/// 最高分數限制為 80，避免多訊號造成分數膨脹。
abstract final class RuleScores {
  /// 最高分數上限
  static const int maxScore = 80;

  /// 最低分數下限（Stage 5a clamp boundary）
  ///
  /// 對應現有最負面規則 `tradingWarningDisposal = -50`（處置股）。
  /// Calibrated JSON 載入時若出現 `score < -50`，會被 clamp 到 -50。
  static const int minScore = -50;

  // ==================================================
  // 多方訊號（正分）
  // ==================================================

  /// 弱轉強分數（強多頭訊號）
  static const int reversalW2S = 35;

  /// 向上突破分數
  static const int techBreakout = 25;

  /// 成交量爆增分數
  static const int volumeSpike = 22;

  /// 價格急漲分數
  static const int priceSpike = 15;

  /// 法人買超轉向分數
  static const int institutionalShift = 18;

  /// 法人賣超轉向分數（空方訊號，扣分）
  static const int institutionalShiftSell = -12;

  /// 新聞相關分數
  static const int newsRelated = 8;

  // 組合加成（breakoutVolumeBonus / reversalVolumeBonus / institutionalComboBonus /
  // patternVolumeBonus）已於 2026-04 移除：個別規則本身已要求量能配合（VOLUME_SPIKE
  // 需 4x 均量、TECH_BREAKOUT 需 MA20 + 量能確認），再加 bonus 等於重複計分，
  // 且會讓強訊號股票全部黏在 maxScore 80 失去區分度。

  /// KD 黃金交叉分數（多方）
  static const int kdGoldenCross = 18;

  /// 法人連續買超分數（多方）
  static const int institutionalBuyStreak = 20;

  /// 投信主導時的額外加減分（投信為主動型法人，買賣超更具意圖性）
  static const int institutionalTrustDominantBonus = 5;

  // ==================================================
  // 空方訊號（負分）- 扣分以降低推薦機率
  // ==================================================

  /// 強轉弱分數（空方訊號，扣分）
  static const int reversalS2W = -25;

  /// 向下跌破分數（空方訊號，扣分）
  static const int techBreakdown = -20;

  /// KD 死亡交叉分數（空方訊號，扣分）
  static const int kdDeathCross = -12;

  /// 法人連續賣超分數（空方訊號，扣分）
  static const int institutionalSellStreak = -15;

  // ==================================================
  // K 線型態分數（多空分離）
  // ==================================================

  /// 十字線分數 — 低檔（RSI < 30，偏多反轉）
  static const int patternDoji = 10;

  /// 十字線分數 — 高檔（RSI > 70，偏空警告）
  static const int patternDojiBearish = -5;

  /// 多頭吞噬分數（多方）
  static const int patternEngulfingBullish = 22;

  /// 空頭吞噬分數（空方，扣分）
  ///
  /// **2026-06-19 v2 audit 降級 -18 → -10**：Mode C 改為「強股回檔進場」、降為
  /// 拉回 warning context。
  static const int patternEngulfingBearish = -10;

  /// 錘子線分數（多方，底部反轉）
  static const int patternHammerBullish = 18;

  /// 吊人線分數（空方，扣分）
  static const int patternHammerBearish = -12;

  /// 跳空上漲分數（多方）
  static const int patternGapUp = 20;

  /// 跳空下跌分數（空方，扣分）
  ///
  /// **2026-06-19 v2 audit 降級 -15 → -8**：Mode C 改為「強股回檔進場」、降為
  /// 急回檔 warning context。
  static const int patternGapDown = -8;

  /// 晨星分數（多方，底部反轉）
  static const int patternMorningStar = 25;

  /// 暮星分數（空方，扣分）
  ///
  /// **2026-06-19 v2 audit 降級 -20 → -10**：Mode C 改為「強股回檔進場」混合
  /// tab、暮星從「反轉確認」降為「拉回起點 warning」。
  static const int patternEveningStar = -10;

  /// 三白兵分數（多方）
  static const int patternThreeWhiteSoldiers = 22;

  /// 三黑鴉分數（空方，扣分）
  static const int patternThreeBlackCrows = -18;

  // ==================================================
  // 技術指標分數（第三階段）
  // ==================================================

  /// 52 週新高分數（強多頭）
  static const int week52High = 28;

  /// 52 週新低分數（逆勢買入機會，小正分）
  ///
  /// 搭配反轉訊號可能是底部，但單獨出現風險高。
  static const int week52Low = 8;

  /// 均線多頭排列分數（5>10>20>60）
  static const int maAlignmentBullish = 22;

  /// MA 穿越事件 4 條(2026-07-31,neutral 起步)。±8 為「觀察區壓線」的
  /// 保守標記分——不進 3-tab 計分,存在意義是落 daily_reason 供掃描與
  /// rule_accuracy 累積;一季後由校準實證判決。刻意對稱、刻意不精算:
  /// 分數唯一正確的制定方式是實證管道,起始值只需要「可觀察」。
  static const int reclaimMa20 = 8;
  static const int reclaimMa60 = 8;
  static const int breakMa20 = -8;
  static const int breakMa60 = -8;

  /// 蓄勢區 2 條(+8 同家族語意:過落庫門檻的觀察標記,不進 tab)
  static const int coilingBelowMa20 = 8;
  static const int coilingBelowMa60 = 8;

  /// 均線空頭排列分數（空方，扣分）
  static const int maAlignmentBearish = -15;

  /// RSI 極度超買分數（警示訊號，小扣分）
  static const int rsiExtremeOverboughtSignal = -8;

  /// RSI 極度超賣分數（逆勢反彈機會，小正分）
  static const int rsiExtremeOversoldSignal = 10;

  // ==================================================
  // 第四階段：延伸市場資料分數
  // ==================================================

  /// 外資持股增加分數（多方）
  static const int foreignShareholdingIncreasing = 18;

  /// 外資持股減少分數（空方，扣分）
  static const int foreignShareholdingDecreasing = -12;

  /// 高當沖比例分數（50-70%）— **2026-07-18 demote 至 0**
  ///
  /// 原為 `+12`「熱門股，中性偏多」。實證顯示這個正分方向是**錯的**：
  ///
  /// **(1) 自有資料反證**（production DB 32,097 筆、29 個交易日、進場 = T+1 open）：
  /// 50-70% bucket 的 1D excess 報酬 **−0.495%、勝率 37.4%**——是全表**最差**的一格；
  /// 流動股池（vol ≥ 1 萬張）內 −0.410%、勝率 37.0%（t=−2.03）。
  /// 1D 勝率隨當沖率單調遞減（<20% 為 42.1% → 50-70% 為 37.4%），
  /// 三個 horizon 的 rank IC 全為負（1D −0.129）。
  ///
  /// **(2) 來源可追溯為 lookahead bias**：`rule_accuracy_service.dart` 於 2026-07-18
  /// 才把進場價從「訊號日 close」改成「隔日 open」。用**舊**慣例重跑，50-70% 的
  /// 5D excess 是 **+0.120**（正）；改用**修正後**慣例即翻為 **−0.229**（負）。
  /// 機制是隔夜跳空：高當沖股隔天確實開高（+0.14pp excess、開高機率 55.3%），
  /// 但盤中就吐回去。舊回測在 T 收盤買進、把這段跳空算進報酬，於是誤判「高當沖 = 偏多」；
  /// 真實使用者只能在 T+1 open 進場，拿不到這段跳空。
  ///
  /// **(3) 監管/學理定位**：TWSE 把「當沖比率明顯過高」列為**注意交易資訊**異常標準
  /// （警示旗標），不是報酬預測指標。高當沖代表**投機/波動**，與次日報酬無關。
  ///
  /// **處置**：分數歸零、規則**仍 fire** — evidence chip、[RiskWarnings.moderate]
  /// 風險徽章、個股詳情頁均保留「這檔當沖很高」的資訊，只是不再貢獻 ranking 分數。
  /// 比照 [concentrationHigh] 的 demote-to-0 前例。
  /// [ReasonType.dayTradingHigh] 早於 2026-06-20 移入 [ScoringMode.neutral]
  /// （不路由到 mode tab），本次補上分數面的一致性。
  static const int dayTradingHigh = 0;

  /// 極高當沖比例分數（>= 70%，投機警示，小扣分）
  ///
  /// **維持 −5，但無實證基礎**：70%+ 全樣本僅 90 筆、流動股池僅 **37 筆**，
  /// t 值介於 −1.09 ~ −0.16。樣本量不足以支持或否定此分數，
  /// 保留作為稀有事件（p99.7）的警示標記，**不宣稱有實證依據**。
  ///
  /// ✅ **市場不對稱已消除（2026-08-23）**。先前本規則僅對上市生效——專案沒有
  /// TPEx 當沖來源、`day_trading` 表全期 0 筆上櫃列，900+ 檔上櫃股結構性吃不到
  /// 這 −5。現已接上兩條路徑：每日走櫃買 `/www/zh-tw/intraday/stat`（免費、
  /// 842 檔），歷史走 FinMind `TaiwanStockDayTrading`（一次性 CLI
  /// `tool/backfill_tpex_day_trading.dart`）。app DB 已回補 2025-06-10 起
  /// 59,098 列 / 295 個交易日 / 748 檔。兩市場現在競爭在同一個評分尺度上。
  ///
  /// **上櫃樣本的初步觀察（2026-08-23，295 天，粗略統計非正式回測）**：
  /// 60 日前瞻報酬 EXTREME +25.6%（n=549）vs baseline +22.7%（n=38,419），
  /// 方向與 −5 的預期相反。但該樣本期為單一多頭段、窗口重疊未去化、未控
  /// regime，**不足以據此改分**，與上方「維持 −5 但無實證基礎」的立場一致。
  /// 正式結論須待 replay + walk-forward，且 `tool/calibration.db` 尚未回補
  /// 上櫃當沖（僅 9,714 列，來自上櫃轉上市個股）。
  static const int dayTradingExtreme = -5;

  /// 高籌碼集中度分數
  ///
  /// **2026-06-19 demote 至 0**（rule audit workflow wf_3db81e3c）：
  /// - rule_accuracy 5D 統計：n=94, hit=33% < baseline 35.85%, avg_ret=-1.04%
  /// - 觸發頻率異常高（今天 41 檔、占 top 20 的 95%）→ 純 noise filter
  /// - threshold 60% 剛好坐在市場中位數 P50=60.59% 上 → 等同隨機
  /// - 規則仍 fire、evidence chip 仍顯示（Mode B 籌碼觀察用），但不影響
  ///   ranking score，避免 17 檔 38 分平手 cliff
  ///
  /// 不從 rule_registry 移除 — 等待 [tool/recalibrate.dart] 改 threshold
  /// 到 P75（~75%）再考慮是否恢復分數。
  static const int concentrationHigh = 0;

  // ==================================================
  // 第五階段：價量背離分數
  // ==================================================

  /// 價漲量縮背離分數（警示訊號，小扣分）
  static const int priceVolumeWeakRally = -8;

  /// 價跌量增背離分數（恐慌訊號，扣分）
  static const int priceVolumeBearishDivergence = -15;

  /// 高檔爆量突破分數（強多頭）
  static const int highVolumeBreakout = 22;

  /// 低檔吸籌分數（潛在反轉，多方）
  static const int lowVolumeAccumulation = 12;

  // ==================================================
  // 第六階段：基本面分析分數
  // ==================================================

  /// 營收年增暴增分數（強基本面）
  static const int revenueYoySurge = 20;

  /// 營收年減衰退分數（空方，扣分）
  static const int revenueYoyDecline = -10;

  /// 營收月增持續成長分數（多方）
  static const int revenueMomGrowth = 15;

  /// 營收創新高分數
  ///
  /// **2026-06-19 demote 至 0**（rule audit workflow wf_3db81e3c）：
  /// - rule_accuracy 5D 統計：n=99, hit=31.3% < baseline 35.85%, avg_ret=**-2.14%**
  /// - 觸發後 5 天平均跌 2.14% — 是反向訊號
  /// - 觸發頻率高（今天 37 檔），跟 CONCENTRATION_HIGH 共同造成 38 分 cliff
  /// - DB 月營收只 4 個月歷史「創新高」語意已誇大（i18n 已改「創近期新高」）
  ///
  /// 規則仍 fire、evidence chip 仍顯示給 user（基本面參考），但不影響
  /// ranking score。等 monthly_revenue 累積 ≥24 個月 + rule_accuracy 累積
  /// 更多樣本後再 re-evaluate。
  static const int revenueNewHigh = 0;

  /// 高殖利率分數（多方）
  static const int highDividendYield = 18;

  /// 本益比低估分數（多方）
  static const int peUndervalued = 15;

  /// 本益比高估分數（空方，扣分）
  static const int peOvervalued = -8;

  /// 股價淨值比低估分數（多方）
  static const int pbrUndervalued = 12;

  // ==================================================
  // Killer Features 分數（注意/處置股、董監持股）
  // ==================================================

  /// 注意股票分數（警示訊號，扣分）
  static const int tradingWarningAttention = -15;

  /// 處置股票分數（高風險，大幅扣分）
  static const int tradingWarningDisposal = -50;

  /// 董監連續減持分數（強賣訊號，大幅扣分）
  static const int insiderSellingStreak = -25;

  /// 董監顯著增持分數（買進訊號）
  static const int insiderSignificantBuying = 20;

  /// 高質押比例分數（風險警示，扣分）
  static const int highPledgeRatio = -18;

  /// 外資持股高度集中分數（風險警示，小扣分）
  static const int foreignConcentrationWarning = -8;

  /// 外資加速流出分數（強賣訊號，扣分）
  static const int foreignExodus = -20;

  // ==================================================
  // EPS 規則分數
  // ==================================================

  /// EPS 年增暴增分數（強基本面）
  static const int epsYoYSurge = 22;

  /// EPS 連續成長分數（持續成長訊號）
  static const int epsConsecutiveGrowth = 18;

  /// EPS 由負轉正分數（轉機訊號）
  static const int epsTurnaround = 15;

  /// EPS 衰退警示分數（扣分）
  static const int epsDeclineWarning = -12;

  // ROE 規則分數
  /// ROE 優異（多方）
  static const int roeExcellent = 18;

  /// ROE 持續改善（多方）
  static const int roeImproving = 15;

  /// ROE 衰退（空方）
  static const int roeDeclining = -10;

  // ==================================================
  // 第 9 階段：強股回檔進場（Mode C v2）— 2026-06-19
  // ==================================================
  //
  // 「強股剛開始拉回、找進場時機」4 條主訊號 rule（2026-06-20 追加 MA10 淺回檔）。
  // **正分**（buy signal）— 打破舊「Mode C 全負分 warning tab」invariant，
  // 因為新 Mode C 是觀察機會 tab。
  //
  // **已校準（2026-07-09，2 年回放）**：5D 無孤立 edge、60D 方向正但低於
  // active 門檻 → calibrated score 0 → fallback 以下手調分（行為不變）。
  // 詳見 pullback_rules.dart 檔頭與 docs/CALIBRATION.md 校準紀錄。

  /// 強勢回檔至 MA20（深回檔、量縮）
  ///
  /// 強股拉回 MA20 動態支撐位 + 量能縮減 + 多頭排列維持。較深的回檔、較高把握。
  static const int pullbackToMa20 = 15;

  /// 強勢回檔至 MA10（淺回檔、量縮）
  ///
  /// 2026-06-20 B2 加：強股拉回 MA10（close 仍在 MA20 上方、與 MA20 深回檔互斥）。
  /// 「buy the dip」的經典淺回檔進場帶、頻率較高、給分稍低（最頻繁＝最低分 tier）。
  static const int pullbackToMa10 = 12;

  /// 支撐位錘子線（強股止跌）
  ///
  /// 強股拉回 MA20 / MA60 + 出現錘子線 K 線型態 + 收盤站穩支撐。比單純 pullback
  /// 多了「**止跌確認**」、給分稍高。
  static const int hammerAtSupport = 18;

  /// KD 高檔回落未死叉（動能稍歇）
  ///
  /// KD 從 78+ 回落到 [60, 80) 區間但 K > D（未死叉）+ 多頭排列維持。技術指標
  /// proxy、相對較弱訊號、給分較低。參數見 rule_params_pullback.dart。
  static const int kdHighPullback = 12;
}

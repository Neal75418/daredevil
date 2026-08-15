/// 分析摘要服務的判斷參數
///
/// 集中管理 [AnalysisSummaryService] 使用的評分門檻、
/// 情緒判斷比例和信心度計分規則。
abstract final class AnalysisParams {
  // ==================================================
  // 分數評級門檻
  // ==================================================

  /// 卓越信號分數門檻
  static const int scoreExceptionalThreshold = 70;

  /// 強烈信號分數門檻
  static const int scoreStrongThreshold = 60;

  /// 值得觀察分數門檻
  static const int scoreWorthwatchingThreshold = 45;

  /// 值得關注分數門檻
  static const int scoreWatchThreshold = 35;

  /// 中性分數門檻（低於此值為「謹慎」）
  static const int scoreNeutralThreshold = 15;

  // ==================================================
  // 摘要標籤門檻（label-only，不影響評分）
  // ==================================================

  /// PE 摘要標籤的「低估」上限（寬鬆門檻，僅控制 UI 文字）
  ///
  /// **語意**：此值是 [AnalysisSummaryService] 顯示「PE 低估 / 高估」標籤
  /// 的二分點，與規則加分**無關**。
  ///
  /// 規則加分由 [FundamentalParams.peUndervaluedThreshold]（嚴格 10.0）
  /// 決定；摘要側使用較寬鬆的 15.0 是為了讓「12 倍 PE」仍能顯示「低估」
  /// 提示，但不會替標的加分。兩個門檻語意不同、刻意分離。
  ///
  /// 過去命名為 `peUndervaluedThreshold`，與 [FundamentalParams] 同名易
  /// 引起「為何兩處不同值」的誤判，已改名為 `peSummaryLowLabelThreshold`
  /// 凸顯 label-only 性質。
  static const double peSummaryLowLabelThreshold = 15.0;

  /// 殖利率摘要標籤的「高殖利率」門檻（label-only）
  ///
  /// **語意**：[AnalysisSummaryService] 顯示「高殖利率」提示用，與規則
  /// 加分無關。規則加分使用 [FundamentalParams.highDividendYieldThreshold]
  /// （嚴格 5.5）。摘要側 4.0 較寬鬆，覆蓋台股平均 4-6% 的合理區間。
  static const double dividendYieldSummaryLabelThreshold = 4.0;

  /// 預期年度股利的回溯**年度**窗口(2026-08-15 數值稽核)。
  ///
  /// 舊實作用 `history.take(3)` 取「最近 3 筆」——但實測 dividend_history
  /// 的年度分布有大空洞(2021–2024 幾乎無資料),**745 檔的完整歷史只有
  /// 2018–2020**,於是六到八年前的配息被當成「最近三年平均」餵進殖利率。
  /// 改以年度過濾:只採計 `year >= 今年 - dividendLookbackYears`。
  static const int dividendLookbackYears = 3;

  /// 營收年增率顯著變動門檻（正負皆適用）
  static const double revenueYoySignificantThreshold = 20.0;

  // ==================================================
  // 基本面修正參數
  // ==================================================

  /// PE 深度低估門檻（修正加分）
  static const double peDeepValueThreshold = 10.0;

  /// 高殖利率修正門檻
  static const double highYieldBiasThreshold = 5.5;

  /// 營收強勁成長修正門檻
  static const double revenueStrongGrowthThreshold = 30.0;

  /// 營收顯著衰退修正門檻
  static const double revenueSignificantDeclineThreshold = -20.0;

  /// 基本面修正分值
  static const double fundamentalBiasPoints = 5.0;

  // ==================================================
  // 風險報酬比判讀
  // ==================================================

  /// 風險報酬比「偏佳」門檻（上檔空間 ≥ 下檔風險的此倍數視為相對有利）
  static const double riskRewardFavorableThreshold = 2.0;

  // ==================================================
  // 情緒判斷門檻
  // ==================================================

  /// 衝突狀態下的看多門檻（比例）
  static const double conflictBullRatioThreshold = 0.65;

  /// 衝突狀態下的看多最低分數
  static const int conflictBullScoreThreshold = 35;

  /// 衝突狀態下的看空門檻（比例）
  static const double conflictBearRatioThreshold = 0.35;

  /// 衝突狀態下的看空分數上限
  static const int conflictBearScoreThreshold = 15;

  /// 強力看多門檻（比例）
  static const double strongBullRatioThreshold = 0.75;

  /// 強力看多最低分數
  static const int strongBullScoreThreshold = 55;

  /// 一般看多門檻（比例）
  static const double bullRatioThreshold = 0.6;

  /// 一般看多最低分數
  static const int bullScoreThreshold = 30;

  /// 一般看空門檻（比例）
  static const double bearRatioThreshold = 0.4;

  /// 一般看空分數上限
  static const int bearScoreThreshold = 20;

  /// 強力看空門檻（比例）
  static const double strongBearRatioThreshold = 0.25;

  /// 強力看空分數上限（exclusive：score < 此值才判定為 strongBearish）
  static const int strongBearScoreThreshold = 10;

  // ==================================================
  // 信心度計分
  // ==================================================

  /// 高信心度門檻（累計點數）
  static const int confidenceHighThreshold = 5;

  /// 中等信心度門檻（累計點數）
  static const int confidenceMediumThreshold = 3;

  /// 高品質訊號門檻（|ruleScore| >= 此值視為高品質）
  static const double highQualitySignalThreshold = 15.0;

  /// 多訊號加分門檻（>= 此值加 2 分）
  static const int manySignalsThreshold = 5;

  /// 少量訊號加分門檻（>= 此值加 1 分）
  static const int someSignalsThreshold = 3;

  // ==================================================
  // 交易成本
  // ==================================================

  /// 台灣券商手續費率（0.1425%）
  static const double brokerageFeeRate = 0.001425;

  /// 台灣證交稅率（0.3%）
  static const double transactionTaxRate = 0.003;

  /// 台灣券商最低手續費（元）
  static const double minBrokerageFee = 20;

  // ==================================================
  // 摘要顯示上限
  // ==================================================

  /// 分析摘要每類別（訊號/風險）最大顯示條目數
  static const int summaryMaxItems = 5;

  // ==================================================
  // 大盤洞察門檻
  // ==================================================

  // ==================================================
  // 判讀層（MarketReadingService）門檻
  // ==================================================
  //
  // 供 [MarketReadingService] 將大盤總覽各區塊的原始數字轉成一行分析師
  // 口吻的判讀文字。皆為 label-only，不影響任何評分。

  /// 量價判讀的「量能顯著變動」門檻（百分比）
  ///
  /// 今日成交額相對 5 日均量的變化超過 ±此值，才視為「量增 / 量縮」，
  /// 落在區間內視為「量能持平」。
  static const double kVolumeSurgePct = 10.0;

  /// 廣度判讀的「普漲」上漲家數占比門檻（0~1）
  ///
  /// 上漲家數 / (上漲 + 下跌) 高於此值視為普漲。
  static const double kBreadthBroadUpRatio = 0.60;

  /// 廣度判讀的「普跌」上漲家數占比門檻（0~1）
  ///
  /// 上漲家數 / (上漲 + 下跌) 低於此值視為普跌；
  /// 介於 [kBreadthBroadDownRatio] 與 [kBreadthBroadUpRatio] 間視為漲跌互現。
  static const double kBreadthBroadDownRatio = 0.40;

  /// 位階乖離判讀的「乖離偏大」門檻（百分比，正負對稱）
  ///
  /// 多頭排列下 MA60 正乖離超過此值視為「短線偏熱」；
  /// 空頭排列下 MA60 負乖離超過此值視為「超跌」。
  static const double kBiasOverheatPct = 15.0;

  /// 綜合判讀「指數平盤」門檻（漲跌幅絕對值百分比）
  ///
  /// |indexChangePercent| 低於此值才視為指數平盤，才會進一步檢查「內部
  /// 家數是否偏向一邊」（見 [kSynthesisInternalSkewRatio]）。
  static const double kSynthesisFlatIndexPct = 0.3;

  /// 綜合判讀「內部偏向」家數占比門檻（0~1）
  ///
  /// 指數平盤時，下跌（或上漲）家數 / (上漲+下跌) 達此比例，視為「指數
  /// 被權值股撐/壓住、內部其實偏弱/偏強」。
  static const double kSynthesisInternalSkewRatio = 0.55;

  /// 綜合判讀「法人合計背離」金額門檻（元）— 上市
  ///
  /// 指數方向與外資/法人合計方向相反時，合計淨額絕對值達此門檻才視為
  /// 「金額顯著」而點名背離，避免小額雜訊觸發。200 億為上市量級的門檻。
  static const double kSynthesisInstDivergenceAmountTwse = 20000000000.0;

  /// 綜合判讀「法人合計背離」金額門檻（元）— 上櫃
  ///
  /// 上櫃成交與法人動向量級遠小於上市，套用上市門檻會使上櫃背離訊號永遠
  /// 不觸發，故另訂 30 億（約為上市門檻的 1/6～1/7，對應兩市場典型量級差）。
  static const double kSynthesisInstDivergenceAmountTpex = 3000000000.0;

  /// 綜合判讀「極端日」門檻（漲跌幅絕對值百分比）— 最高優先規則
  ///
  /// |indexChangePercent| 達此值時觸發最高優先的「極端日」規則（見
  /// [MarketReadingService.interpretCompositeSynthesis]），蓋過既有三規則。
  ///
  /// **語意**：極端日分界（台股單日 ±3% 罕見；語意啟發值非最佳化參數）。
  /// 2026-07-17 歷史性 -6.47% 崩盤日，原三規則輸出「無明顯背離」/買超背離，
  /// 雲淡風輕——需最高優先的極端日規則。
  static const double kSynthesisExtremeDayPct = 3.0;

  // ==================================================
  // 大盤位階（均線乖離）門檻
  // ==================================================

  /// 大盤位階短期均線週期（MA20）
  ///
  /// 用於 [TechnicalIndicatorService.calculateMarketStage] 判斷加權指數
  /// 相對短期均線的位置，對應 Weinstein 階段分析的趨勢結構錨點。
  static const int marketStageShortMaPeriod = 20;

  /// 大盤位階長期均線週期（MA60）
  ///
  /// 多頭排列需 MA20 > MA60，至少需 [marketStageShortMaPeriod] +
  /// [marketStageLongMaPeriod] 個有效交易日才能完整計算。
  static const int marketStageLongMaPeriod = 60;
}

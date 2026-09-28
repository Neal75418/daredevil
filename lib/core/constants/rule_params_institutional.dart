/// 法人動向 / 籌碼面 / 延伸市場資料參數
abstract final class InstitutionalParams {
  // ==================================================
  // 法人連續買賣超規則
  // ==================================================

  /// 法人資料回溯天數（**顯示用**：個股詳情、比較頁的近期法人動向）
  ///
  /// 評分規則請勿使用此值——連續買賣超規則需要 [institutionalStreakLookbackDays]，
  /// 否則 streak 會被窗口截斷（見該常數註解）。
  static const int institutionalLookbackDays = 10;

  /// 評分用法人回溯天數（連續買賣超規則的取數窗）
  ///
  /// 曾與 [institutionalLookbackDays] 共用 10 日曆日 → 從 7/24 往回只含 9 個
  /// 交易日，DB 實證 streakDays 分布在 9 出現硬牆（4:82 / 5:58 / 6:49 / 7:41
  /// / 8:39 / 9:17、**10 以上 0 筆**），與窗大小完全吻合，是截斷而非自然分布。
  ///
  /// 放寬至 90（與 [kStreakLookbackDays] 同）於真實資料實測：45 檔觸發者
  /// **觸發結果零變動**（無新增、無消失），僅 8 檔的天數被修正——2357/2884/
  /// 6414 由 9 日修正為 17 日。查詢成本亦無差異（90 日窗即全表，41ms vs 42ms）。
  static const int institutionalStreakLookbackDays = kStreakLookbackDays;

  /// 法人連續買賣天數門檻
  static const int institutionalStreakDays = 4;

  /// 法人連續買賣超「連續天數」徽章的回溯天數上限
  ///
  /// 市場總覽連續買賣超徽章（[InstitutionalStreak]）的取數窗口。預設 30 會
  /// 把真實連續天數截斷在 30（DB 內 dealer 曾連 47 日淨買、卻顯示「連30日」），
  /// 故獨立放寬至 90。徽章於 streak 觸頂時顯示「90+」。
  static const int kStreakLookbackDays = 90;

  /// 法人每日最低淨買賣門檻（股）
  ///
  /// 每日淨買賣超須達此門檻才算有效交易日。
  static const int institutionalMinDailyNetShares = 50000;

  /// 法人每日顯著淨買賣門檻（股）
  ///
  /// 超過此門檻的交易日視為「顯著」交易日。
  static const int institutionalSignificantDailyNetShares = 150000;

  /// 法人連買總量門檻（股）
  ///
  /// 連續買超期間的總淨買超須達此門檻。
  /// 從 2,000,000 降至 1,500,000，因三重過濾（連續天數 + 總量 + 日均）
  /// 導致觸發率過低（0-2 檔/日）。
  static const int institutionalBuyTotalThresholdShares = 1500000;

  /// 法人連買日均門檻（股）
  ///
  /// 連續買超期間的日均淨買超須達此門檻。
  /// 從 300,000 降至 200,000，配合總量門檻調降。
  static const int institutionalBuyDailyAvgThresholdShares = 200000;

  /// 法人連賣總量門檻（股）
  ///
  /// 連續賣超期間的總淨賣超須達此門檻（負值）。
  ///
  /// **不對稱性**：賣超門檻 (-2M / -300k) 比買超門檻 (1.5M / 200k) 嚴。
  /// 動機：連賣多為市場 noise（外資 hedge / 月底 rebalance），門檻過鬆
  /// 會讓警示氾濫降低訊號可信度。當買超門檻於 2026-04 由 2M → 1.5M
  /// 微調以提升觸發率時，賣超門檻刻意保持不動避免 risk path 失真。
  ///
  /// 等 Stage 4 calibration 累積 forward data 後丟進 backtest 重新對齊。
  static const int institutionalSellTotalThresholdShares = -2000000;

  /// 法人連賣日均門檻（股）
  ///
  /// 連續賣超期間的日均淨賣超須達此門檻（負值）。對等於
  /// [institutionalSellTotalThresholdShares] 的不對稱設計。
  static const int institutionalSellDailyAvgThresholdShares = -300000;

  // ==================================================
  // 法人成交量與比例門檻
  // ==================================================

  /// 法人分析最低成交量（1000 張 = 1,000,000 股）
  static const double institutionalMinVolumeShares = 1000000;

  /// 法人數據有效最低成交量（2000 張 = 2,000,000 股）
  static const double institutionalValidVolumeShares = 2000000;

  /// 法人佔總成交量顯著比例門檻
  static const double institutionalSignificantRatio = 0.35;

  /// 法人佔總成交量爆量比例門檻
  static const double institutionalExplosiveRatio = 0.50;

  /// 法人反轉訊號最低量（500 張 = 500,000 股）
  static const double institutionalReversalShares = 500000;

  /// 法人小量方向判斷門檻（100 張 = 100,000 股）
  static const double institutionalSmallShares = 100000;

  /// 法人大量訊號門檻（5000 張 = 5,000,000 股）
  static const double institutionalLargeSignalShares = 5000000;

  /// 法人加速買賣倍數門檻
  static const double institutionalAccelerationMult = 2.0;

  /// 法人加速買賣最低量（1000 張 = 1,000,000 股）
  static const double institutionalAccelerationMinShares = 1000000;

  /// 法人大量訊號價格變動確認門檻（1%）
  static const double institutionalSignificantPriceChange = 0.01;

  /// 法人方向計算取樣數
  static const int institutionalDirectionSampleSize = 5;

  // ==================================================
  // 延伸市場資料（外資持股 / 當沖 / 集中度）
  // ==================================================

  /// 外資持股增加門檻（%）
  ///
  /// N 天內外資持股增加此百分比時觸發。
  static const double foreignShareholdingIncreaseThreshold = 0.5;

  /// 外資持股變化回溯天數
  static const int foreignShareholdingLookbackDays = 5;

  /// 外資持股資料可接受的最大陳舊度（**交易日**）
  ///
  /// 外資持股於 T 日盤後公布，正常同步當日即可取得；容許 1 個交易日涵蓋
  /// 發布延遲。超過此值代表該股**未被本輪配額覆蓋**（上櫃候選受 20/269 限制），
  /// 此時最新一筆是數日前的死值——2026-07-25 實測 3479 連四天以同一筆 7/21
  /// 資料觸發 +18，且因 prev 端隨日期往回滾，訊號強度還「自己變強」
  /// （change 0.84→1.23→1.22→1.22，ratio 恆為 7.63）。
  ///
  /// 用交易日而非日曆天：週一用上週五資料是 3 日曆天但僅隔 1 交易日。
  static const int foreignShareholdingMaxStaleTradingDays = 2;

  /// 外資持股**水位**可接受的最大陳舊度（交易日）
  ///
  /// 與 [foreignShareholdingMaxStaleTradingDays]（管**變化量**）刻意分開：
  /// - **水位**（ratio）是真實觀測值，持股比例以月為單位緩慢移動，隔幾天仍
  ///   具參考性。`ForeignConcentrationWarningRule`(-8) 只讀水位、不碰變化量，
  ///   若與變化量同閘門一起關掉，等於**隱藏真實風險**（fail-open）。
  /// - **變化量**（change）在 stale 時是捏造值：current 端凍結、prev 端隨
  ///   evaluationDate 往回滾，訊號強度會「自己變強」。
  ///
  /// 取 20 個交易日（約一個月）為寬鬆上界，避免用季度前的水位當現況。
  static const int foreignShareholdingLevelMaxStaleTradingDays = 20;

  /// 高當沖比例門檻（50%）
  static const double dayTradingHighThreshold = 50.0;

  /// 極高當沖比例門檻（70%）
  static const double dayTradingExtremeThreshold = 70.0;

  /// 大戶持股集中度門檻（%）
  ///
  /// 400 張以上大戶持有此比例的股票。
  static const double concentrationHighThreshold = 60.0;
}

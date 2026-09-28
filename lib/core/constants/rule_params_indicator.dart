/// RSI / KD / 均線 / 52 週高低點參數
abstract final class IndicatorParams {
  // ==================================================
  // RSI
  // ==================================================

  /// RSI 週期（預設 14）
  static const int rsiPeriod = 14;

  /// RSI 超買/超賣「極端區」門檻 — 兩側刻意不對稱，勿改成對稱。
  ///
  /// 命名雖同為 extreme，兩側距中心（50）刻意不等距：
  /// - 超買側 85：真正的「超買力竭」門檻（距中心 +35），僅在極端過熱時示警（-8）。
  /// - 超賣側 30：實為「輕度超賣的反彈觸發」門檻（距中心 -20），比慣例超賣線
  ///   （20~25）寬鬆，故「extreme oversold」名不符實；為對超賣反彈保持靈敏而刻意
  ///   設寬（+10 較易觸發）。此為刻意的多頭傾斜，非對稱錯誤——請勿為對齊 85 而下修 30。
  ///
  /// 註：值與分數的調整屬訊號校準（需回測），不在此命名/文件清理範圍。
  static const double rsiExtremeOverbought = 85.0;

  /// RSI 超賣訊號門檻（30）— 見 [rsiExtremeOverbought] 的不對稱說明。
  ///
  /// 30 = 輕度超賣的反彈觸發點（非慣例 20~25 的「極度超賣」）。
  static const double rsiExtremeOversold = 30.0;

  /// RSI 中性區上界（K 線型態過濾用）
  ///
  /// RSI 嚴格介於 rsiExtremeOversold 與 rsiNeutralHigh 之間視為中性；
  /// 兩個門檻值本身屬極端區。十字線等型態需 RSI 處於極端區域才有意義。
  static const double rsiNeutralHigh = 70.0;

  // ==================================================
  // KD
  // ==================================================

  /// KD %K 計算週期
  static const int kdPeriodK = 9;

  /// KD %D 平滑週期
  static const int kdPeriodD = 3;

  /// KD 超買門檻
  static const double kdOverbought = 80.0;

  /// KD 超賣門檻
  static const double kdOversold = 20.0;

  /// KD 黃金交叉有效區域（低檔區）
  ///
  /// K 值需低於此門檻才視為有效黃金交叉。
  static const double kdGoldenCrossZone = 30.0;

  /// KD 死亡交叉有效區域（高檔區）
  ///
  /// K 值需高於此門檻才視為有效死亡交叉。
  static const double kdDeathCrossZone = 70.0;

  /// KD 交叉價格動能門檻（1%）
  ///
  /// 黃金交叉需有至少此漲幅才算有效。
  static const double kdCrossPriceChangeThreshold = 0.01;

  // ==================================================
  // 52 週高低點
  // ==================================================

  /// 一年交易日數（約 52 週 * 5 天）
  static const int week52Days = 250;

  /// 52 週極值計算的最低有效 bar 數
  ///
  /// 在 [week52Days]（250）窗口內，至少要有此數量的有效價格 bar
  /// （非 null、>0）才回傳結果。低於此值視為樣本不足，可能因新上市
  /// 或長期停牌造成統計失真。
  ///
  /// 20 對 250-day 窗口為 8% 覆蓋率，僅作為「完全沒資料」的硬下限。
  /// 真正「資料完整」門檻見 [historicalDataMinDays]（200）。
  static const int week52MinValidBars = 20;

  /// 歷史資料完成度最低天數
  ///
  /// 股票需有此天數以上的價格資料，才視為「歷史資料完整」。
  /// 200 天約涵蓋 10 個月的交易日，可進行大部分技術分析。
  static const int historicalDataMinDays = 200;

  /// 歷史資料接近完整門檻
  ///
  /// 已有此天數以上資料的股票跳過回補同步（資料已接近完整，不值得再花 API 配額補齊）。
  /// 低於此值的股票才會進入歷史資料回補流程。
  static const int historyNearCompleteThreshold = 180;

  /// 接近 52 週新高緩衝百分比
  ///
  /// 收盤價在 52 週最高價的 1% 範圍內觸發。
  /// 維持嚴格門檻確保只有真正突破的股票才觸發。
  static const double week52HighThreshold = 0.01;

  /// 接近 52 週新低緩衝百分比
  ///
  /// 收盤價在 52 週最低價的 3% 範圍內觸發。
  /// 比新高稍寬鬆（3% vs 1%），因為：
  /// 1. 新低是逆勢操作，需要更多緩衝
  /// 2. 底部區域通常有支撐震盪
  /// 3. 避免 0 個新低的極端情況
  static const double week52LowThreshold = 0.03;

  // ==================================================
  // 均線排列
  // ==================================================

  /// 排列檢查用均線週期
  static const List<int> maAlignmentPeriods = [5, 10, 20, 60];

  /// 有效排列的均線最小間距（0.3%）
  ///
  /// 從 0.5% 降至 0.3%，在高價股（如 500 元以上）
  /// 0.5% 間距僅 2.5 元，容易誤判均線糾結為有效排列。
  static const double maMinSeparation = 0.003;

  /// 均線乖離率過濾門檻（5%）
  ///
  /// 收盤價離 MA 超過此距離時過濾，避免追高殺低
  static const double maDeviationThreshold = 0.05;

  /// 多頭排列成交量倍數門檻
  ///
  /// 成交量需達 20 日均量的此倍數。
  /// 1.3 倍（原設計 2.0 倍）考量台股常有量縮上漲現象。
  static const double maAlignmentVolumeMultiplier = 1.3;
}

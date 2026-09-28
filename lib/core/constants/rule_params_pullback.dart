/// 強股回檔進場參數（Mode C v2）
///
/// **已校準（2026-07-09，2 年回放）**：5D 無孤立 edge、60D 方向正
/// （詳見 pullback_rules.dart 檔頭與 docs/CALIBRATION.md）。閾值維持
/// 直覺值。集中於此供日後一處調參。
abstract final class PullbackParams {
  // ---- 共用 helper ----

  /// 強勢 baseline：N 日累積漲幅 ≥ 5%（ma20Now > pastClose × 1.05）。
  static const double wasStrongMinRatio = 1.05;

  /// 強勢確認回溯天數。
  static const int strongLookbackDays = 20;

  /// 跌停 guard：當日跌幅 ≤ -9.5%（台股 ±10%、留 0.5% margin）一律 short-circuit。
  ///
  /// 與 `PriceLimit.isLimitDown`（-9.85%，tick 捨入容差 0.15%）是**刻意不同**
  /// 的兩個閾值：這裡是保守 guard（寧可多擋接近跌停的恐慌日），PriceLimit
  /// 是精準的「觸及跌停板」顯示判斷。調整任一側時先確認語意差異仍成立。
  static const double limitDownRatio = -0.095;

  /// 過去 N 日內找至少 1 根紅 K 的窗口（過濾瀑布跌）。
  static const int recentBullishCandleDays = 5;

  /// 規則所需最少 K 棒數。
  static const int minHistoryDays = 21;

  // ---- Rule A: PULLBACK_TO_MA20 ----

  /// 拉回 MA20 區間下界（-1.5%）。
  static const double ma20PullbackBandLow = -0.015;

  /// 拉回 MA20 區間上界（+3%）。
  static const double ma20PullbackBandHigh = 0.03;

  /// 量縮判定：今日量 < volumeMA20 × 0.85（Rule A / A2 共用）。
  static const double volumeShrinkRatio = 0.85;

  // ---- Rule A2: PULLBACK_TO_MA10（淺回檔）----

  /// 拉回 MA10 區間下界（-1.5%）。
  static const double ma10PullbackBandLow = -0.015;

  /// 拉回 MA10 區間上界（+2.5%）。
  static const double ma10PullbackBandHigh = 0.025;

  // ---- Rule B: HAMMER_AT_SUPPORT ----

  /// 下影線觸及支撐的容差 ±4%（MA20 / MA60 共用）。
  static const double hammerSupportTouchBand = 0.04;

  /// 收盤站穩支撐：close ≥ supportLevel × 0.985。
  static const double hammerCloseHoldRatio = 0.985;

  /// close 上界：≤ MA20 × 1.06（排除明顯高檔；與 HangingMan 仍可能同時觸發）。
  static const double hammerCloseMaxMa20Ratio = 1.06;

  /// 跳空下跌認定：(prevClose − open) / prevClose > 1%。
  static const double hammerGapDownRatio = 0.01;

  // ---- Rule C: KD_HIGH_PULLBACK ----

  /// 前日 KD 高檔門檻（prevKdK ≥ 78）。
  static const double kdHighPrevMin = 78;

  /// 今日 K 回落區間下界（含，60）。
  static const double kdPullbackBandLow = 60;

  /// 今日 K 回落區間上界（不含，80）。
  static const double kdPullbackBandHigh = 80;

  /// 收盤未破 MA20 過深：close ≥ MA20 × 0.99。
  static const double kdCloseMinMa20Ratio = 0.99;

  /// 單日 K 跌幅上限（≤ 30，panic 防護）。
  static const double kdMaxDailyDrop = 30;

  // ==========================================================================
  // 蓄勢區(COILING,2026-07-31)——「還沒噴」的事前偵測
  // ==========================================================================

  /// 蓄勢區:收盤距 MA 下方的最大距離(%)。一根中紅即可完成突破的範圍。
  ///
  /// 3% 為三個歷史日實證校定(2026-07-22/24/31):搭配 [coilingMin60dReturnPct]
  /// 質量閂命中 30-55 檔/日;無質量閂時同窗高達 658 檔(纯位置=雜訊)。
  static const double coilingMaxDistancePct = 3.0;

  /// 蓄勢區:60 日報酬下限(%)——質量閂。同樣貼在線下,正動能股是蓄勢、
  /// 弱勢股是反彈撞壓力;此門檻分開兩個世界(實證同上)。
  static const double coilingMin60dReturnPct = 10.0;
}

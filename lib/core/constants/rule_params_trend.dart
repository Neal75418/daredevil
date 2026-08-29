/// 趨勢 / 反轉 / 支撐壓力 / 價量背離參數
///
/// Used by: volume_rules.dart, technical_rules.dart, divergence_rules.dart,
/// trend_detection_service.dart, fundamental_technical_filter.dart
abstract final class TrendParams {
  // ==================================================
  // 價格 / 成交量異動
  // ==================================================

  /// 價格異動門檻百分比（5%）
  ///
  /// 從 7% 降至 5%，原 7% 接近台股漲跌幅極值（10%），
  /// 導致 5-6% 的顯著異動被錯過。
  static const double priceSpikePercent = 5.0;

  /// 價格異動成交量確認倍數
  ///
  /// 成交量需達 20 日均量的此倍數以上，避免無量異動雜訊。
  static const double priceSpikeVolumeMult = 1.5;

  /// 成交量異動倍數（相對 20 日均量）
  ///
  /// 4.0 倍具高度選擇性，僅捕捉異常成交量。
  /// 同時需要價格變動（見 minPriceChangeForVolume）。
  static const double volumeSpikeMult = 4.0;

  /// 成交量異動訊號所需最低價格變動
  ///
  /// 過濾無實質價格變動的成交量異動，1.5% 確保量價配合。
  static const double minPriceChangeForVolume = 0.015;

  // ==================================================
  // 突破 / 跌破 / 支撐壓力
  // ==================================================

  /// 突破緩衝容差（3% 以獲得更乾淨的訊號）
  ///
  /// 收緊門檻以過濾假突破，需明確突破壓力 3% 以上。
  static const double breakoutBuffer = 0.03;

  /// 跌破緩衝容差（3%）
  ///
  /// 收緊門檻以過濾假跌破，需明確跌破支撐 3% 以上。
  static const double breakdownBuffer = 0.03;

  /// 壓力/支撐有效最大距離
  ///
  /// 超過此距離的壓力/支撐將被忽略，8% 可偵測近期水位並過濾無關水位。
  static const double maxSupportResistanceDistance = 0.08;

  // ==================================================
  // 趨勢偵測 / 反轉確認
  // ==================================================

  /// 波段點聚類閾值（2%）
  ///
  /// 將差距在此範圍內的波段點聚類為同一價格區域。
  static const double clusterThreshold = 0.02;

  /// 趨勢偵測上升閾值（每日 0.08%）
  ///
  /// 標準化斜率超過此值視為上升趨勢。
  /// 每日 0.08% = 20 天約 1.6%
  static const double trendUpThreshold = 0.08;

  /// 趨勢偵測下降閾值（每日 -0.08%）
  ///
  /// 標準化斜率低於此值視為下降趨勢。
  static const double trendDownThreshold = -0.08;

  /// 反轉訊號分析所需最少資料點數（近期 + 前期各半）
  static const int reversalMinDataPoints = 40;

  /// 反轉訊號近期/前期分析窗口（各佔一半）
  static const int reversalHalfWindow = 20;

  /// 更高低點確認緩衝（7%）
  ///
  /// 近期低點需高於前期低點 7% 才確認為「更高低點」。
  /// 收緊門檻以大幅提升精準度，只保留明確反轉訊號。
  static const double higherLowBuffer = 1.07;

  /// 更低高點確認緩衝（5%）
  ///
  /// 近期高點需低於前期高點 5% 才確認為「更低高點」。
  /// 頭部反轉不需要像底部反轉那樣嚴格。
  static const double lowerHighBuffer = 0.95;

  /// 反轉/突破訊號成交量確認門檻（多方）
  ///
  /// 近期成交量需達前期平均的此倍數以上。
  /// 用於弱轉強（底部反轉）訊號確認。
  static const double reversalVolumeConfirm = 1.5;

  // ==================================================
  // ATR 與支撐壓力搜尋
  // ==================================================

  /// ATR 距離乘數（支撐/壓力搜尋半徑）
  ///
  /// 使用 ATR × 此乘數 / 現價 作為動態搜尋距離。
  static const double atrDistanceMultiplier = 3.0;

  /// ATR 動態搜尋半徑的**上界**（24%）
  ///
  /// [atrDistanceMultiplier] 把 ATR/價格比放大後當搜尋半徑，而那個結果原本
  /// 完全沒有上界——實測 2,135 檔（本機 DB，2025-06-10～2026-08-28）：54.3%
  /// 的半徑比靜態的 [maxSupportResistanceDistance] 寬、p90 = 17.3%、
  /// **max = 181.5%**。半徑超過 100% 時 `minSupport` 變成負數，現價下方的
  /// 每一個價格區都「在範圍內」，等於完全沒有下界。
  ///
  /// **24% 的依據**：排除價格斷點股後（N=2,118）該分布的 p99 = 22.9%，取整到
  /// 24%。以生產母體重算（N=2,137 = `prices.length >= 40` 且 ATR 可算者，
  /// 其 p99 = 23.0%）實際只夾住 **16 檔（0.75%）**。它恰好也等於
  /// `maxSupportResistanceDistance × atrDistanceMultiplier`，但**刻意獨立成
  /// 常數而不是那樣寫**——那會讓「動態半徑的縮放倍數」與「上界」變成同一個
  /// 旋鈕，日後有人把倍數調成 2.0 想收窄半徑，上界會跟著悄悄收到 16%。
  static const double maxAtrSupportResistanceDistance = 0.24;

  /// 支撐壓力距離衰減因子
  ///
  /// 用於計算 distanceFactor = 1 / (1 + (distance/price) * factor)。
  /// 數值越大，距離衰減越快（越近的關卡分數越高）。
  static const double distanceDecayFactor = 10.0;

  /// 趨勢偵測最少資料點數
  ///
  /// 收盤價序列需達此數量才進行趨勢判斷。
  static const int minTrendDataPoints = 5;

  // ==================================================
  // 價量背離
  // ==================================================

  /// 價量背離分析回溯天數
  static const int priceVolumeLookbackDays = 5;

  /// 「高檔爆量」訊號的高位門檻（百分位）
  ///
  /// 價格需在 60 日區間前 X% 才視為「高位」。
  static const double highPositionThreshold = 0.85;

  /// 「低檔吸籌」訊號的低位門檻（百分位）
  ///
  /// 價格需在 60 日區間後 25% 才視為「低位」。
  static const double lowPositionThreshold = 0.25;

  /// 背離價格變動門檻（%）
  static const double divergencePriceThreshold = 1.0;

  /// 背離成交量變動門檻（%）
  static const double divergenceVolumeThreshold = 10.0;

  /// 低檔吸籌成交量比率門檻
  static const double lowAccumulationVolumeRatio = 0.6;
}

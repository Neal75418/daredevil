/// 漲跌停狀態(見 [PriceLimit.statusOf])
enum PriceLimitStatus {
  none,
  limitUp,
  limitUpLocked,
  limitDown,
  limitDownLocked;

  bool get isUp => this == limitUp || this == limitUpLocked;
  bool get isDown => this == limitDown || this == limitDownLocked;
  bool get isLocked => this == limitUpLocked || this == limitDownLocked;
}

/// 台股漲跌停板檢測工具
///
/// 台股普通股漲跌幅限制為前一交易日收盤價的 ±10%。
/// 漲跌停價以「tick 級距」進位/截斷，此處以百分比近似判斷。
class PriceLimit {
  PriceLimit._();

  /// 漲跌幅限制百分比
  static const double _limitPercent = 10.0;

  /// 判斷為漲/跌停的容差（考慮 tick 級距捨入誤差）
  ///
  /// 注意：`PullbackParams.limitDownRatio`（-9.5%）是另一個**刻意較寬**的
  /// 跌停 guard（回檔規則用，寧可多擋恐慌日）；此處 -9.85% 是精準的
  /// 「觸及跌停板」判斷。兩者語意不同，勿混用或擅自對齊。
  static const double _tolerance = 0.15;

  /// 判斷是否觸及漲停
  ///
  /// [changePercent] 漲跌幅百分比（正數為漲）
  static bool isLimitUp(double? changePercent) {
    if (changePercent == null) return false;
    return changePercent >= _limitPercent - _tolerance;
  }

  /// 判斷是否觸及跌停
  ///
  /// [changePercent] 漲跌幅百分比（負數為跌）
  static bool isLimitDown(double? changePercent) {
    if (changePercent == null) return false;
    return changePercent <= -(_limitPercent - _tolerance);
  }

  /// 漲跌停狀態——畫面上所有漲跌停標示都走這一個判斷。
  ///
  /// 有交易所給的漲跌停價([limitUp]／[limitDown],盤中即時報價才有)時以
  /// 價格精確比對,鎖住與否看委買委賣([limitUpLocked]／[limitDownLocked]);
  /// 沒有時(盤後資料)以漲跌幅推算([isLimitUp]／[isLimitDown]),推算不出
  /// 鎖住。低價股差一檔未達漲停也會被推算判成漲停(例:昨收 40、漲停
  /// 44.00,43.95 為 +9.875%),所以有漲跌停價時不看漲跌幅。
  static PriceLimitStatus statusOf({
    required double? changePercent,
    double? price,
    double? limitUp,
    double? limitDown,
    bool limitUpLocked = false,
    bool limitDownLocked = false,
  }) {
    if (limitUp != null || limitDown != null) {
      if (price != null && price == limitUp) {
        return limitUpLocked
            ? PriceLimitStatus.limitUpLocked
            : PriceLimitStatus.limitUp;
      }
      if (price != null && price == limitDown) {
        return limitDownLocked
            ? PriceLimitStatus.limitDownLocked
            : PriceLimitStatus.limitDown;
      }
      return PriceLimitStatus.none;
    }
    if (isLimitUp(changePercent)) return PriceLimitStatus.limitUp;
    if (isLimitDown(changePercent)) return PriceLimitStatus.limitDown;
    return PriceLimitStatus.none;
  }
}

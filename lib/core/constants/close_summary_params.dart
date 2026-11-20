/// 收盤摘要的門檻（設計見 `docs/plans/2026-11-20-close-summary-design.md`）。
///
/// 依使用者交易決策表 v3；v3 沒寫數字的（籌碼章的買超下限）由本機資料量測
/// 補上，讀取天數則是算這些條件需要的資料長度；依據見設計文件與各欄說明。強者榜的
/// 月漲幅與均量沿用 `SectorParams`、成本守門價的倍數與週期沿用
/// `AlertParams`，這裡只放摘要自己才用的。
abstract final class CloseSummaryParams {
  /// 月線（均線週期）
  static const int maPeriod = 20;

  /// 油門的 5 日門檻＝資料日之前這麼多個交易日的收盤平均
  static const int throttleThresholdDays = 4;

  /// 強者榜連續收在月線下這麼多天就標「連 N 日收破月線」
  static const int demotionBelowMaDays = 2;

  /// 同產業同一天跌破月線的自選股達到這個檔數，標「族群退燒」
  static const int sectorCoolingMinStocks = 2;

  /// 結構 C：資料日收盤高於之前這麼多根的最高價
  static const int structureCLookbackDays = 20;

  /// 結構 B 的支撐均線，由短到長；成立時回報最短的那條
  static const List<int> structureBSupportPeriods = [5, 10, 20];

  /// 結構 B 要求資料日收在這條均線之上
  static const int structureBTrendMaPeriod = 10;

  /// 結構 B：資料日最低價碰到支撐（≤ 支撐 × 此值）
  static const double structureBTouchRatio = 1.015;

  /// 結構 B：資料日收盤守住支撐（≥ 支撐 × 此值）
  static const double structureBHoldRatio = 0.995;

  /// 結構觸發當天漲跌幅不高於此值（%）就降級
  static const double triggerDayDowngradePct = -5.0;

  /// 前提條件：月線乖離上限（%，需小於）
  static const double maxBiasPct = 15.0;

  /// 前提條件：營收年增近 3 月平均下限（%，需大於）
  static const double minRevenueYoy3mPct = 30.0;

  /// 前提條件：資料日成交量下限（股，需大於）
  static const double minDayVolumeShares = 3000000;

  /// 籌碼章：外資或投信連續買超的交易日數
  static const int chipStreakDays = 3;

  /// 籌碼章：每天買超至少佔當天成交量的比例
  static const double chipMinVolumeShare = 0.01;

  /// 進場後這麼多個交易日內收盤沒到過 +1R 就標「8 日未達 +1R」
  static const int timeStopTradingDays = 8;

  /// 讀價格與法人往回的日曆天數：夠 61 根（60 日漲幅）再加上長假
  static const int priceLookbackCalendarDays = 130;

  /// 持股另外往進場日之前多讀的日曆天數：成本守門價的 ATR(20) 要 21 根
  static const int holdingAtrLeadCalendarDays = 45;

  /// 讀營收的月數：`yoy3mAvg` 要最新 3 個不同月份，多讀幾個月涵蓋公布空窗
  static const int revenueLookbackMonths = 6;

  /// 分組名稱（使用者自訂的名稱，以名稱辨認 v3 的角色）
  static const String strongListGroupName = '強者榜';
  static const String delistReviewGroupName = '除名重審';
  static const String thermometerGroupName = '大盤溫度計';
}

/// 盤中即時報價參數(2026-10-05 設計,值見設計文件的參數表)
abstract final class LiveQuoteParams {
  /// 盤中輪詢間隔(批數 > 2 時由 `LiveQuoteSchedule.pollInterval` 拉長)
  static const Duration pollInterval = Duration(seconds: 15);

  /// 任何 60 秒內最多幾個 MIS 請求(盤中提醒 CLI 另計,約每分鐘 0.4 次)
  static const int maxRequestsPerMinute = 8;

  /// 相鄰兩個請求至少間隔(同一輪內批與批之間)
  static const Duration minRequestGap = Duration(seconds: 2);

  /// 計算請求量的窗口
  static const Duration requestWindow = Duration(minutes: 1);

  /// 報價中心時鐘的解析度:`AppClock` 的 `SystemClock` 走 `TaiwanTime.now()`,
  /// 只到整秒(毫秒被丟掉),記下的送出時刻最多比實際早 1 秒。節流的間隔與
  /// 窗口各加這個邊界,實際時間才保證 [minRequestGap] 與
  /// [maxRequestsPerMinute]
  static const Duration clockResolution = Duration(seconds: 1);

  /// 盤中提醒 CLI 每幾分鐘跑一次(`ops/launchd/com.neo.daredevil.intraday.plist`
  /// 的 StartCalendarInterval:交易日 09:00–13:30 每 5 分鐘)
  static const int cliEveryMinutes = 5;

  /// CLI 整點後讓開多久
  static const Duration cliAvoidWindow = Duration(seconds: 10);

  /// 收盤後每檔抓取間隔
  static const Duration afterCloseRetryInterval = Duration(minutes: 1);

  /// 收盤後每檔最多幾次「有回應但不是收盤報價」(網路失敗、限流不計)
  static const int afterCloseMaxAttempts = 10;

  /// 視為暫停的無回應時間下限(實際取 max(此值, 2 × 輪詢間隔))
  static const Duration stallFloor = Duration(seconds: 60);

  /// 暫停後每次失敗間隔加倍的上限
  static const Duration maxBackoff = Duration(minutes: 2);

  /// 撞到限流後整個報價中心暫停多久(之後先用 1 個請求試探)
  static const Duration rateLimitPause = Duration(minutes: 5);

  /// 報價中心專用逾時(盤中提醒與 CLI 維持 ApiConfig 的 30／60 秒)
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration receiveTimeout = Duration(seconds: 8);

  /// 報價中心的節拍:登記變動、可見性變動都等下一拍才動作
  static const Duration tick = Duration(seconds: 1);

  /// 閃色淡出(第 2 段畫面使用)
  static const Duration flashFade = Duration(milliseconds: 600);

  /// 閃色底色最濃時的透明度。現價數字是一般文字色(不是紅綠),疊在 20% 的
  /// 紅綠底上兩種主題對比都遠高於 4.5(`stock_card_test` 的閃色對比度測試)
  static const double flashTintAlpha = 0.2;

  /// 大盤指數在 MIS 的代號(市場別硬對應,不查主檔)
  static const String twseIndexSymbol = 't00';
  static const String tpexIndexSymbol = 'o00';
}

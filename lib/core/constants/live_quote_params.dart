import 'package:daredevil/core/constants/market_codes.dart';

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

  /// 一次閃色維持多久（2026-10-07 實機後改成券商看盤軟體的做法：價格那一格
  /// 整塊實心紅／綠、數字反色，時間到一次收掉。原本 20% 淡色、0.6 秒一出現
  /// 就淡、只襯在數字後面，盯著看也幾乎察覺不到。不留淡出：試過停留後淡出、
  /// 濃度剩一半時數字才切回原色，切換那一刻深色主題對比只有約 2.2）
  static const Duration flashDuration = Duration(milliseconds: 600);

  /// 閃色底色的透明度：實心。數字同時改成 `PriceColors.onFlash`
  static const double flashTintAlpha = 1.0;

  /// 價格色塊左右比數字寬出多少（往外擴、不推動版面）。上下不擴：數字那一
  /// 行的行框本身已含字上下的空白，再往外擴會壓到緊貼在上下的元件（個股頁
  /// 現價正下方就是漲跌幅膠囊、中間沒有間距）
  static const double flashChipPadH = 4;

  /// 大盤指數在 MIS 的代號(市場別硬對應,不查主檔)
  static const String twseIndexSymbol = 't00';
  static const String tpexIndexSymbol = 'o00';

  /// 市場別 → 大盤指數的 MIS 代號(上市 t00、上櫃 o00)
  static String indexSymbolOf(String market) =>
      market == MarketCode.twse ? twseIndexSymbol : tpexIndexSymbol;
}

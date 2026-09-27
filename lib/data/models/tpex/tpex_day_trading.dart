/// 上櫃現股當沖交易統計（逐檔）
///
/// 來源：`/www/zh-tw/intraday/stat`（免費、無額度）。
///
/// 帶 `date=YYYY/MM/DD` 可取歷史（2026-09-26 實測回到 2024-01）；不帶時
/// 永遠回最新交易日（2026-08-23 曾實測六個不同日期回傳同一份資料，md5
/// 相同，當時尚未發現 `date` 參數其實有效）。[date] 一律取自回應的 `date`
/// 欄位——即使有帶請求日期，仍以回應為準並比對是否相符（見
/// `TpexClient.getAllDayTradingData`），不符就整批丟棄，避免把最新資料寫成
/// 歷史日期。
///
/// 欄位語意與 [TwseDayTrading] 一致（實測 2026-08-21 兩市場各 6 檔 × 3 欄位
/// 與官方逐位元相符），故共用 `day_trading` 表。
class TpexDayTrading {
  const TpexDayTrading({
    required this.date,
    required this.code,
    required this.name,
    required this.buyVolume,
    required this.sellVolume,
    required this.totalVolume,
  });

  /// 資料日（取自回應的 `date`，非請求日期）
  final DateTime date;
  final String code;
  final String name;

  /// 當沖買進成交金額（元）
  final double buyVolume;

  /// 當沖賣出成交金額（元）
  final double sellVolume;

  /// 當沖成交股數
  final double totalVolume;
}

/// 上櫃現股當沖交易統計（逐檔）
///
/// 來源：`/www/zh-tw/intraday/stat`（免費、無額度）。
///
/// ⚠️ **此端點無視 `date` 參數，永遠回最新交易日**——2026-08-23 實測六個不同
/// 日期回傳同一份資料（md5 相同）。因此 [date] 取自回應的 `date` 欄位，
/// 不可用請求日期，否則會把最新資料寫成歷史日期。上市端相反：TWTB4U 吃日期，
/// 那條路是「回應日期 ≠ 請求日期就整批丟棄」。
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

import 'package:daredevil/core/utils/json_parsers.dart';

/// FinMind 當沖資料（`TaiwanStockDayTrading`）
///
/// **較久遠歷史回補專用**。每日同步與 40 天窗回補都走免費的官方端點（上市
/// TWTB4U、上櫃 `/www/zh-tw/intraday/stat`，皆可帶 `date` 取歷史，上櫃
/// 2026-09-26 實測回到 2024-01）；只有回補到官方端點涵蓋不到的更久以前
/// （見 `tool/backfill_tpex_day_trading.dart`）才需要它，FinMind 逐檔一次
/// 呼叫就能拉整段歷史（實測回到 2020-03）。
///
/// 2026-08-21 實測：`Volume`／`BuyAmount`／`SellAmount` 與兩市場官方端點
/// 逐位元相符（上櫃 6 檔、上市 5 檔），故可與官方資料寫入同一張表。
class FinMindDayTrading {
  const FinMindDayTrading({
    required this.stockId,
    required this.date,
    required this.volume,
    required this.buyAmount,
    required this.sellAmount,
  });

  /// 從 JSON 解析（含驗證）；缺必要欄位拋 [FormatException]
  factory FinMindDayTrading.fromJson(Map<String, dynamic> json) {
    final stockId = json['stock_id'];
    final date = json['date'];
    if (stockId == null || stockId.toString().isEmpty) {
      throw FormatException('Missing required field: stock_id', json);
    }
    if (date == null || date.toString().isEmpty) {
      throw FormatException('Missing required field: date', json);
    }

    // 三個數值欄位缺一不可。**0 是合法值**（當日無當沖），不可與缺值混淆——
    // 這與價格欄位相反（價格 0 是停牌 sentinel）。
    final volume = JsonParsers.parseDouble(json['Volume']);
    final buy = JsonParsers.parseDouble(json['BuyAmount']);
    final sell = JsonParsers.parseDouble(json['SellAmount']);
    if (volume == null || buy == null || sell == null) {
      throw FormatException('Missing day-trading amounts', json);
    }

    return FinMindDayTrading(
      stockId: stockId.toString(),
      date: date.toString(),
      volume: volume,
      buyAmount: buy,
      sellAmount: sell,
    );
  }

  /// 寬鬆解析：格式錯誤回 null 由呼叫端跳過
  static FinMindDayTrading? tryFromJson(Map<String, dynamic> json) {
    try {
      return FinMindDayTrading.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  final String stockId;

  /// `YYYY-MM-DD`
  final String date;

  /// 當沖成交股數
  final double volume;

  /// 當沖買進成交金額（元）
  final double buyAmount;

  /// 當沖賣出成交金額（元）
  final double sellAmount;
}

/// TPEX 每日價格資料
class TpexDailyPrice {
  const TpexDailyPrice({
    required this.date,
    required this.code,
    required this.name,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.change,
    this.turnover,
    this.noComparison = false,
  });

  final DateTime date;
  final String code;
  final String name;
  final double? open;
  final double? high;
  final double? low;
  final double? close;
  final double? volume;
  final double? change;
  final double? turnover;

  /// 漲跌欄是文字（除息／除權／除權息）＝當天不比價，漲跌要用 exDailyQ 的
  /// 開始交易基準價算（除權息漲跌修正）；沒成交的 `---`、`--`、空白不算。
  final bool noComparison;
}

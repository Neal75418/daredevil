/// 除權除息計算結果：一次除權息一列（TWSE TWT49U / TPEx exDailyQ 共用模型）
///
/// 股利歷史的來源，可回溯歷史、附除權息交易日（`t187ap45_L` 已宣告股利
/// 只是近期快照、不帶日期）。TPEx 列表分欄給現金股利與每仟股無償配股；
/// TWSE 列表只給「權值+息值」合計，「權」「權息」列要以 TWT49UDetail
/// 的 [ExRightDetail] 補齊（[withDetail]）。
class ExRightResult {
  const ExRightResult({
    required this.symbol,
    required this.exDate,
    required this.cashDividend,
    required this.stockSharesPerThousand,
  });

  final String symbol;

  /// 除權息交易日（當地午夜）
  final DateTime exDate;

  /// 每股現金股利（元）；null＝列表拆不出（TWSE 權息同除），需查明細
  final double? cashDividend;

  /// 每千股無償配股（股）；null＝列表拆不出（TWSE 除權、權息），需查明細
  final double? stockSharesPerThousand;

  bool get needsDetail =>
      cashDividend == null || stockSharesPerThousand == null;

  /// 以 TWT49UDetail 的明細取代列表推得的金額
  ExRightResult withDetail(ExRightDetail detail) => ExRightResult(
    symbol: symbol,
    exDate: exDate,
    cashDividend: detail.cashDividend,
    stockSharesPerThousand: detail.stockSharesPerThousand,
  );
}

/// TWSE 除權除息明細（TWT49UDetail）：拆開「權值+息值」合計
class ExRightDetail {
  const ExRightDetail({
    required this.symbol,
    required this.cashDividend,
    required this.stockSharesPerThousand,
  });

  final String symbol;

  /// 每股現金股利（元）
  final double cashDividend;

  /// 按普通股股東持股比例每千股無償配股（股）；不含員工紅利轉增資與
  /// 現金增資
  final double stockSharesPerThousand;
}

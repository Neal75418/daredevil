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
    this.closeBefore,
    this.dividendAdjustedReference,
  });

  final String symbol;

  /// 除權息交易日（當地午夜）
  final DateTime exDate;

  /// 每股現金股利（元）；null＝列表拆不出（TWSE 權息同除），需查明細
  final double? cashDividend;

  /// 每千股無償配股（股）；null＝列表拆不出（TWSE 除權、權息），需查明細
  final double? stockSharesPerThousand;

  /// 除權息前收盤價（TWSE 列表；核對明細用）
  final double? closeBefore;

  /// 減除股利參考價：只扣股利、不含現金增資的參考價（TWSE 列表；核對明細用）
  final double? dividendAdjustedReference;

  bool get needsDetail =>
      cashDividend == null || stockSharesPerThousand == null;

  /// 以 TWT49UDetail 的明細取代列表推得的金額
  ExRightResult withDetail(ExRightDetail detail) => ExRightResult(
    symbol: symbol,
    exDate: exDate,
    cashDividend: detail.cashDividend,
    stockSharesPerThousand: detail.stockSharesPerThousand,
    closeBefore: closeBefore,
    dividendAdjustedReference: dividendAdjustedReference,
  );

  /// 明細與列表是否指同一次除權息：以明細的現金與配股推算
  /// (前收 − 現金) ÷ (1 + 配股 ÷ 1000)，須與列表的減除股利參考價相差
  /// 不到 0.01（列表值 TWSE 捨去到 0.01）。明細的配股只顯示到小數 1 位
  /// （6446 2025-09 反推約 109.73 股、明細寫 109.7），高價股差 0.03 股推算值
  /// 就差 0.016，所以配股大於 0 時以 ±0.1 股推出一個區間，列表值落在區間
  /// 外 0.01 以內都算一致；配股 0 視為精確（明細寫 0 就是沒有配股）。
  /// 2026-09-29 以 10 筆實測樣本驗證。
  /// TWT49UDetail 的回應沒有日期欄，這是唯一能確認「查到的是這一次」的方式。
  /// 列表沒有核對欄位時（上櫃列）無從核對，回 true。
  bool matchesReference(ExRightDetail detail) {
    final close = closeBefore;
    final reference = dividendAdjustedReference;
    if (close == null || reference == null) return true;
    final base = close - detail.cashDividend;
    final shares = detail.stockSharesPerThousand;
    final margin = shares > 0 ? _sharesDisplayPrecision : 0.0;
    final highest = base / (1 + (shares - margin) / 1000);
    final lowest = base / (1 + (shares + margin) / 1000);
    return reference > lowest - _referenceTolerance &&
        reference < highest + _referenceTolerance;
  }

  /// 捨去到 0.01 的誤差上限，外加浮點餘裕
  static const _referenceTolerance = 0.01 + 1e-6;

  /// 明細配股股數的顯示精度（每千股，小數 1 位）
  static const _sharesDisplayPrecision = 0.1;
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

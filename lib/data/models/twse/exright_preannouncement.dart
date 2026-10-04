import 'package:daredevil/core/utils/tw_parse_utils.dart';

/// 除權除息預告（TWSE TWT48U_ALL / TPEx tpex_exright_prepost 共用模型）
///
/// 兩端點欄位名不同但語意同構：民國緊湊日期＋代碼＋類別（TWSE：息/權/權息；
/// TPEx：除息/除權/除權息——「含息/權字」的判定對兩者皆成立）。
/// 這是行事曆除權息事件的**唯一資料源**：大宗「已宣告股利」只帶金額不帶
/// 日期；除權除息配發表（dividend_distribution）只有已發生的除權息，
/// 沒有預告（見 EventRepository.syncDividendEvents）。
class ExRightPreannouncement {
  const ExRightPreannouncement({
    required this.symbol,
    required this.date,
    required this.hasDividend,
    required this.hasRights,
    this.cashDividend,
    this.stockDividendRatio,
  });

  final String symbol;

  /// 除權息交易日
  final DateTime date;

  /// 是否除息
  final bool hasDividend;

  /// 是否除權
  final bool hasRights;

  /// 現金股利（元）；來源空字串時為 null
  final double? cashDividend;

  /// 配股率；來源空字串或 0 時為 null
  final double? stockDividendRatio;

  /// TWSE TWT48U_ALL 列。缺代碼/日期無效/類別無息無權時回 null。
  static ExRightPreannouncement? tryFromTwseJson(Map<String, dynamic> json) {
    return _tryParse(
      code: json['Code']?.toString(),
      rocDate: json['Date']?.toString(),
      kind: json['Exdividend']?.toString(),
      cash: json['CashDividend']?.toString(),
      stockRatio: json['StockDividendRatio']?.toString(),
    );
  }

  /// TPEx tpex_exright_prepost 列。
  static ExRightPreannouncement? tryFromTpexJson(Map<String, dynamic> json) {
    return _tryParse(
      code: json['SecuritiesCompanyCode']?.toString(),
      rocDate: json['ExRrightsExDividendDate']?.toString(),
      kind: json['ExRrightsExDividend']?.toString(),
      cash: json['CashDividend']?.toString(),
      stockRatio: json['StockDividendRatio']?.toString(),
    );
  }

  static ExRightPreannouncement? _tryParse({
    required String? code,
    required String? rocDate,
    required String? kind,
    String? cash,
    String? stockRatio,
  }) {
    if (code == null || code.isEmpty || kind == null) return null;
    final date = TwParseUtils.parseCompactRocDate(rocDate);
    if (date == null) return null;
    final hasDividend = kind.contains('息');
    final hasRights = kind.contains('權');
    if (!hasDividend && !hasRights) return null;

    double? positiveOrNull(String? raw) {
      final v = double.tryParse(raw ?? '');
      return (v == null || v <= 0) ? null : v;
    }

    return ExRightPreannouncement(
      symbol: code,
      date: date,
      hasDividend: hasDividend,
      hasRights: hasRights,
      cashDividend: positiveOrNull(cash),
      stockDividendRatio: positiveOrNull(stockRatio),
    );
  }
}

import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/core/utils/logger.dart';

/// 季度綜合損益表快照(TWSE t187ap06_L_* / TPEx mopsfin_t187ap06_O_*,
/// 六業別 × 兩市場,2026-08-06 最新一季財報總覽)。
///
/// 兩市場的財務欄名完全一致(中文),只有 metadata 欄不同:TWSE 用
/// 公司代號/年度/季別/公司名稱,TPEx 用 SecuritiesCompanyCode/Year/
/// Season/CompanyName——單一 parser 以雙 key fallback 吃兩邊,不需
/// 各養一個 factory。
///
/// 數字口徑(對 live 快照驗證):淨利/營收=千元、EPS=元,**皆為累計制**
/// (Q2=上半年)。注意 financial_data 的 FinMind EPS 是**單季**值,
/// 口徑不同——YoY 比較須在 DAO 層加總去年各季。
class QuarterlyReportEntry {
  const QuarterlyReportEntry({
    required this.symbol,
    required this.companyName,
    required this.year,
    required this.quarter,
    this.eps,
    this.netIncome,
    this.revenue,
  });

  factory QuarterlyReportEntry.fromJson(Map<String, dynamic> json) {
    String field(String zhKey, String enKey) =>
        (json[zhKey] ?? json[enKey])?.toString().trim() ?? '';

    final symbol = field('公司代號', 'SecuritiesCompanyCode');
    if (symbol.length < 4 || symbol.length > 6) {
      throw FormatException('無效的公司代號: "$symbol"', json);
    }

    // 年度為 ROC 紀年;範圍防線沿月營收 dirty-data filter 同款
    // (2026-08-05 複審):官方端點曾出現離譜年月列,越界即拒收。
    final rocYear = int.tryParse(field('年度', 'Year'));
    if (rocYear == null || rocYear < 90 || rocYear > 200) {
      throw FormatException('無效的年度: "$rocYear"', json);
    }

    final quarter = int.tryParse(field('季別', 'Season'));
    if (quarter == null || quarter < 1 || quarter > 4) {
      throw FormatException('無效的季別: "$quarter"', json);
    }

    double? parseNum(String key) {
      final s = json[key]?.toString().trim() ?? '';
      if (s.isEmpty) return null;
      return TwParseUtils.parseFormattedDouble(s);
    }

    final eps = parseNum('基本每股盈餘（元）');
    final netIncome = parseNum('本期淨利（淨損）');
    // 兩個核心數字皆缺=空殼列(佔位/格式異常),整列拒收;營收非核心
    // (金融業別本來就無此欄),缺了照收。
    if (eps == null && netIncome == null) {
      throw FormatException('EPS 與淨利皆空', json);
    }

    return QuarterlyReportEntry(
      symbol: symbol,
      companyName: field('公司名稱', 'CompanyName'),
      year: rocYear + 1911,
      quarter: quarter,
      eps: eps,
      netIncome: netIncome,
      revenue: parseNum('營業收入'),
    );
  }

  static QuarterlyReportEntry? tryFromJson(Map<String, dynamic> json) {
    try {
      return QuarterlyReportEntry.fromJson(json);
    } catch (e) {
      AppLogger.debug(
        'QuarterlyReport',
        '解析季報失敗: ${json['公司代號'] ?? json['SecuritiesCompanyCode']} ($e)',
      );
      return null;
    }
  }

  final String symbol;
  final String companyName;

  /// 西元年度(來源為 ROC 紀年,+1911)
  final int year;

  /// 季別 1~4
  final int quarter;

  /// 基本每股盈餘(元,累計)
  final double? eps;

  /// 本期淨利(千元,累計)
  final double? netIncome;

  /// 營業收入(千元,累計;金融業別無此欄)
  final double? revenue;
}

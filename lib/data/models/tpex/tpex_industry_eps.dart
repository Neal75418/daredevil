import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/constants/api_config.dart';

/// TPEX 產業別 EPS 資料（來源：櫃買中心 ap14_O API）
///
/// 解析各產業公司的基本每股盈餘、營收、營業利益、稅後淨利。
/// 為季報資料，每季更新一次。
class TpexIndustryEps {
  const TpexIndustryEps({
    required this.symbol,
    required this.companyName,
    required this.industry,
    required this.year,
    required this.quarter,
    required this.eps,
    required this.revenue,
    required this.operatingProfit,
    required this.netIncome,
  });

  factory TpexIndustryEps.fromJson(Map<String, dynamic> json) {
    final symbol = json['SecuritiesCompanyCode']?.toString().trim() ?? '';

    if (symbol.isEmpty || symbol.length < 4 || symbol.length > 6) {
      throw FormatException('無效的公司代號: "$symbol"', json);
    }

    final yearStr = json['Year']?.toString().trim() ?? '';
    final rocYear = int.tryParse(yearStr);
    if (rocYear == null) {
      throw FormatException('無效的年度: "$yearStr"', json);
    }
    final year = rocYear + ApiConfig.rocYearOffset;

    final quarterStr = json['季別']?.toString().trim() ?? '';
    final quarter = int.tryParse(quarterStr);
    if (quarter == null || quarter < 1 || quarter > 4) {
      throw FormatException('無效的季別: "$quarterStr"', json);
    }

    final epsStr = json['基本每股盈餘']?.toString().trim() ?? '0';
    final eps = TwParseUtils.parseFormattedDouble(epsStr) ?? 0;

    final revenueStr = json['營業收入']?.toString().trim() ?? '0';
    final revenue = TwParseUtils.parseFormattedDouble(revenueStr) ?? 0;

    final opProfitStr = json['營業利益']?.toString().trim() ?? '0';
    final operatingProfit = TwParseUtils.parseFormattedDouble(opProfitStr) ?? 0;

    final netIncomeStr = json['稅後淨利']?.toString().trim() ?? '0';
    final netIncome = TwParseUtils.parseFormattedDouble(netIncomeStr) ?? 0;

    return TpexIndustryEps(
      symbol: symbol,
      companyName: json['CompanyName']?.toString().trim() ?? '',
      industry: json['產業別']?.toString().trim() ?? '',
      year: year,
      quarter: quarter,
      eps: eps,
      revenue: revenue,
      operatingProfit: operatingProfit,
      netIncome: netIncome,
    );
  }

  static TpexIndustryEps? tryFromJson(Map<String, dynamic> json) {
    try {
      return TpexIndustryEps.fromJson(json);
    } catch (e) {
      AppLogger.debug(
        'TPEX',
        '解析 TpexIndustryEps 失敗: ${json['SecuritiesCompanyCode']}',
      );
      return null;
    }
  }

  final String symbol; // 公司代號
  final String companyName; // 公司名稱
  final String industry; // 產業別
  final int year; // 年度（西元年）
  final int quarter; // 季別 (1-4)
  final double eps; // 基本每股盈餘
  final double revenue; // 營業收入（千元）
  final double operatingProfit; // 營業利益（千元）
  final double netIncome; // 稅後淨利（千元）
}

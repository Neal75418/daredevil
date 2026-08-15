import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/data/models/shared/ytd_yoy_parser.dart';

/// TWSE Open Data 月營收資料
class TwseMonthlyRevenue {
  const TwseMonthlyRevenue({
    required this.year,
    required this.month,
    required this.code,
    required this.name,
    required this.revenue,
    required this.momGrowth,
    required this.yoyGrowth,
    this.ytdYoyGrowth,
  });

  factory TwseMonthlyRevenue.fromJson(Map<String, dynamic> json) {
    // 欄位: "資料年月"(11201), "公司代號", "公司名稱", "營業收入-當月營收",
    // "營業收入-上月比較增減(%)", "營業收入-去年同月增減(%)"

    final ym = json['資料年月']?.toString() ?? '';
    int year = 0;
    int month = 0;
    if (ym.length >= 5) {
      final yStr = ym.substring(0, ym.length - 2);
      final mStr = ym.substring(ym.length - 2);
      year = (int.tryParse(yStr) ?? 0) + ApiConfig.rocYearOffset;
      month = int.tryParse(mStr) ?? 0;
    }

    // 解析含逗號的數字字串（OpenData 通常沒有，但以防萬一）
    double parseVal(String? key) {
      if (key == null) return 0.0;
      final val = json[key]?.toString() ?? '';
      return TwParseUtils.parseFormattedDouble(val) ?? 0.0;
    }

    double? parseNullable(String key) {
      final val = json[key]?.toString() ?? '';
      return TwParseUtils.parseFormattedDouble(val);
    }

    return TwseMonthlyRevenue(
      year: year,
      month: month,
      code: json['公司代號']?.toString() ?? '',
      name: json['公司名稱']?.toString() ?? '',
      revenue: parseVal('營業收入-當月營收'),
      momGrowth: parseVal('營業收入-上月比較增減(%)'),
      yoyGrowth: parseVal('營業收入-去年同月增減(%)'),
      ytdYoyGrowth: parseSelfCheckedYtdYoy(
        ytdCurrent: parseNullable('累計營業收入-當月累計營收'),
        ytdPrior: parseNullable('累計營業收入-去年累計營收'),
        ytdPct: parseNullable('累計營業收入-前期比較增減(%)'),
      ),
    );
  }

  final int year;
  final int month;
  final String code;
  final String name;
  final double revenue; // 千元（通常）
  final double momGrowth; // 月增率 %
  final double yoyGrowth; // 年增率 %

  /// 累計年增率 %(年初至當月 vs 去年同期;自洽檢核失配或缺欄為 null)
  final double? ytdYoyGrowth;
}

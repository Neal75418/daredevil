import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/data/models/shared/ytd_yoy_parser.dart';

/// TPEX 月營收資料
class TpexMonthlyRevenue {
  const TpexMonthlyRevenue({
    required this.date,
    required this.code,
    required this.name,
    required this.revenue,
    required this.revenueYear,
    required this.revenueMonth,
    this.momGrowth,
    this.yoyGrowth,
    this.ytdYoyGrowth,
  });

  /// 解析 openapi mopsfin_t187ap05_O 單筆;非股票代碼/年月無法解析回 null。
  ///
  /// 2026-08-13 自 TpexClient._parseMonthlyRevenueItem 搬移:model 自帶
  /// 解析才能被直接測(累計欄的自洽政策見 [parseSelfCheckedYtdYoy])。
  /// 呼叫端負責 try/catch 與記錄——本方法對壞形狀回 null 不丟。
  static TpexMonthlyRevenue? fromJson(Map<String, dynamic> json) {
    final code = json['公司代號']?.toString().trim() ?? '';
    if (code.isEmpty) return null;
    if (!StockPatterns.isTpexCode(code)) return null;

    final dataYearMonth = json['資料年月']?.toString() ?? '';
    if (dataYearMonth.length < 5) return null;

    final rocYear = int.tryParse(dataYearMonth.substring(0, 3));
    final month = int.tryParse(dataYearMonth.substring(3));
    if (rocYear == null || month == null) return null;
    if (month < 1 || month > 12) return null;

    final year = rocYear + ApiConfig.rocYearOffset;

    double? parseValue(dynamic value) {
      if (value == null || value == '' || value == '-') return null;
      final str = value.toString().replaceAll(',', '').trim();
      if (str.isEmpty) return null;
      return double.tryParse(str);
    }

    return TpexMonthlyRevenue(
      date: DateTime(year, month),
      code: code,
      name: json['公司名稱']?.toString().trim() ?? '',
      revenue: parseValue(json['營業收入-當月營收']) ?? 0,
      revenueYear: year,
      revenueMonth: month,
      momGrowth: parseValue(json['營業收入-上月比較增減(%)']),
      yoyGrowth: parseValue(json['營業收入-去年同月增減(%)']),
      ytdYoyGrowth: parseSelfCheckedYtdYoy(
        ytdCurrent: parseValue(json['累計營業收入-當月累計營收']),
        ytdPrior: parseValue(json['累計營業收入-去年累計營收']),
        ytdPct: parseValue(json['累計營業收入-前期比較增減(%)']),
      ),
    );
  }

  final DateTime date;
  final String code;
  final String name;
  final double revenue; // 當月營收（千元）
  final int revenueYear; // 營收年份（西元）
  final int revenueMonth; // 營收月份
  final double? momGrowth; // 月增率 (%)
  final double? yoyGrowth; // 年增率 (%)

  /// 累計年增率 %(自洽檢核失配或缺欄為 null)
  final double? ytdYoyGrowth;
}

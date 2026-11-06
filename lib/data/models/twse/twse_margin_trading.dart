import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/models/twse/twse_daily_price.dart';
import 'package:daredevil/core/utils/device_time.dart';

/// TWSE 融資融券資料
class TwseMarginTrading {
  const TwseMarginTrading({
    required this.date,
    required this.code,
    required this.name,
    required this.marginBuy,
    required this.marginSell,
    required this.marginBalance,
    required this.shortBuy,
    required this.shortSell,
    required this.shortBalance,
  });

  factory TwseMarginTrading.fromJson(Map<String, dynamic> json) {
    final code = json['Code'];
    final dateStr = json['Date'];

    if (code == null || code.toString().isEmpty) {
      throw FormatException('Missing Code', json);
    }

    return TwseMarginTrading(
      date: dateStr != null
          ? TwseDailyPrice.parseRocDate(dateStr.toString())
          : DeviceTime.now(),
      code: code.toString(),
      name: json['Name']?.toString() ?? '',
      marginBuy: _parseDouble(json['MarginPurchase']) ?? 0,
      marginSell: _parseDouble(json['MarginSell']) ?? 0,
      marginBalance: _parseDouble(json['MarginBalance']) ?? 0,
      shortBuy: _parseDouble(json['ShortCovering']) ?? 0,
      shortSell: _parseDouble(json['ShortSale']) ?? 0,
      shortBalance: _parseDouble(json['ShortBalance']) ?? 0,
    );
  }

  static TwseMarginTrading? tryFromJson(Map<String, dynamic> json) {
    try {
      return TwseMarginTrading.fromJson(json);
    } catch (e) {
      AppLogger.debug('TWSE', '解析 TwseMarginTrading 失敗: ${json['Code']}');
      return null;
    }
  }

  final DateTime date;
  final String code;
  final String name;
  final double marginBuy; // 融資買進
  final double marginSell; // 融資賣出
  final double marginBalance; // 融資餘額
  final double shortBuy; // 融券買進 (回補)
  final double shortSell; // 融券賣出
  final double shortBalance; // 融券餘額

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(',', '').trim();
      if (cleaned.isEmpty || cleaned == '--') return null;
      return double.tryParse(cleaned);
    }
    return null;
  }
}

import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/data/models/twse/twse_daily_price.dart';
import 'package:daredevil/core/utils/device_time.dart';

/// TWSE 法人買賣超資料
class TwseInstitutional {
  const TwseInstitutional({
    required this.date,
    required this.code,
    required this.name,
    required this.foreignBuy,
    required this.foreignSell,
    required this.foreignNet,
    required this.investmentTrustBuy,
    required this.investmentTrustSell,
    required this.investmentTrustNet,
    required this.dealerBuy,
    required this.dealerSell,
    required this.dealerNet,
    required this.totalNet,
    this.dealerSelfNet = 0,
  });

  factory TwseInstitutional.fromJson(Map<String, dynamic> json) {
    final code = json['Code'];
    final dateStr = json['Date'];

    if (code == null || code.toString().isEmpty) {
      throw FormatException('Missing Code', json);
    }

    return TwseInstitutional(
      date: dateStr != null
          ? TwseDailyPrice.parseRocDate(dateStr.toString())
          : DeviceTime.now(),
      code: code.toString(),
      name: json['Name']?.toString() ?? '',
      foreignBuy:
          TwParseUtils.parseFormattedDouble(json['ForeignInvestorsBuy']) ?? 0,
      foreignSell:
          TwParseUtils.parseFormattedDouble(json['ForeignInvestorsSell']) ?? 0,
      foreignNet:
          TwParseUtils.parseFormattedDouble(
            json['ForeignInvestorsNetBuySell'],
          ) ??
          0,
      investmentTrustBuy:
          TwParseUtils.parseFormattedDouble(json['InvestmentTrustBuy']) ?? 0,
      investmentTrustSell:
          TwParseUtils.parseFormattedDouble(json['InvestmentTrustSell']) ?? 0,
      investmentTrustNet:
          TwParseUtils.parseFormattedDouble(
            json['InvestmentTrustNetBuySell'],
          ) ??
          0,
      dealerBuy: TwParseUtils.parseFormattedDouble(json['DealerTotalBuy']) ?? 0,
      dealerSell:
          TwParseUtils.parseFormattedDouble(json['DealerTotalSell']) ?? 0,
      dealerNet:
          TwParseUtils.parseFormattedDouble(json['DealerTotalNetBuySell']) ?? 0,
      totalNet: TwParseUtils.parseFormattedDouble(json['TotalNetBuySell']) ?? 0,
      // 此 named-key JSON 路徑（非每日 daily-sync 路徑）無自行買賣欄位，預設 0
      dealerSelfNet: 0,
    );
  }

  static TwseInstitutional? tryFromJson(Map<String, dynamic> json) {
    try {
      return TwseInstitutional.fromJson(json);
    } catch (e) {
      AppLogger.debug('TWSE', '解析 TwseInstitutional 失敗: ${json['Code']}');
      return null;
    }
  }

  final DateTime date;
  final String code;
  final String name;
  final double foreignBuy;
  final double foreignSell;
  final double foreignNet;
  final double investmentTrustBuy;
  final double investmentTrustSell;
  final double investmentTrustNet;
  final double dealerBuy;
  final double dealerSell;
  final double dealerNet;
  final double totalNet;

  /// 自營商「自行買賣」買賣超（不含避險），供真實主動方向 streak。
  /// daily-sync 路徑由 T86 row[14] 解析；named-key fromJson 路徑無此欄，預設 0。
  final double dealerSelfNet;
}

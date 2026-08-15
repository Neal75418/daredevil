import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/core/utils/logger.dart';

/// TPEX 融券賣出排行資料（來源：櫃買中心 short_sell API）
///
/// 解析櫃買中心融券賣出排行 Top 20 資料，包含前日餘額、當日餘額及增減。
class TpexShortSellRanking {
  const TpexShortSellRanking({
    required this.rank,
    required this.symbol,
    required this.companyName,
    required this.previousBalance,
    required this.currentBalance,
    required this.shortSell,
  });

  factory TpexShortSellRanking.fromJson(Map<String, dynamic> json) {
    final symbol = json['SecuritiesCompanyCode']?.toString().trim() ?? '';

    if (symbol.isEmpty || symbol.length < 4 || symbol.length > 6) {
      throw FormatException('無效的公司代號: "$symbol"', json);
    }

    final rankStr = json['Rank']?.toString().trim() ?? '';
    final rank = int.tryParse(rankStr);
    if (rank == null) {
      throw FormatException('無效的排名: "$rankStr"', json);
    }

    final previousBalance = _parseIntField(json, 'PreviousBalance');
    final currentBalance = _parseIntField(json, 'CurrentBalance');
    final shortSell = _parseIntField(json, 'Used');

    return TpexShortSellRanking(
      rank: rank,
      symbol: symbol,
      companyName: json['CompanyName']?.toString().trim() ?? '',
      previousBalance: previousBalance,
      currentBalance: currentBalance,
      shortSell: shortSell,
    );
  }

  static TpexShortSellRanking? tryFromJson(Map<String, dynamic> json) {
    try {
      return TpexShortSellRanking.fromJson(json);
    } catch (e) {
      AppLogger.debug(
        'TPEX',
        '解析 TpexShortSellRanking 失敗: ${json['SecuritiesCompanyCode']}',
      );
      return null;
    }
  }

  final int rank; // 排名
  final String symbol; // 公司代號
  final String companyName; // 公司名稱
  final int previousBalance; // 前日餘額（張）
  final int currentBalance; // 當日餘額（張）
  final int shortSell; // 融券賣出量（張）

  /// 餘額增減（當日 - 前日）
  int get balanceChange => currentBalance - previousBalance;

  static int _parseIntField(Map<String, dynamic> json, String key) {
    final str = json[key]?.toString().trim() ?? '0';
    return TwParseUtils.parseFormattedInt(str) ?? 0;
  }
}

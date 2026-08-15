import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/tw_parse_utils.dart';

/// TPEX 內部人轉讓持股資料（來源：櫃買中心 ap12_O API）
///
/// 解析櫃買中心「內部人持股轉讓申報」資料，包含董事、經理人、大股東
/// 的轉讓股數、轉讓方式及有效轉讓期間。
class TpexInsiderTransfer {
  const TpexInsiderTransfer({
    required this.symbol,
    required this.companyName,
    required this.reportDate,
    required this.identity,
    required this.name,
    required this.transferMethod,
    required this.transferShares,
    required this.currentHolding,
    this.validPeriodStart,
    this.validPeriodEnd,
  });

  factory TpexInsiderTransfer.fromJson(Map<String, dynamic> json) {
    final symbol = json['SecuritiesCompanyCode']?.toString().trim() ?? '';

    if (symbol.isEmpty || symbol.length < 4 || symbol.length > 6) {
      throw FormatException('無效的公司代號: "$symbol"', json);
    }

    final reportDateStr = json['Date']?.toString().trim() ?? '';
    final reportDate = TwParseUtils.parseCompactRocDate(reportDateStr);
    if (reportDate == null) {
      throw FormatException('無效的申報日期: "$reportDateStr"', json);
    }

    // ⚠️ TPEx OpenAPI (mopsfin_t187ap12_O) 的實際 key 帶群組前綴，舊版讀
    // '轉讓股數'/'目前持有股數' 等不存在的 key → 全部 fallback 成 0（已驗 17/17 筆
    // 皆 0 的 bug）。以下 key 已對 live API 核實。
    //
    // 「預定轉讓方式及股數-轉讓股數」只有「一般交易/鉅額逐筆」(走市場、有每日限額)
    // 才填；信託/贈與/洽特定人該欄為空，股數改放「預定轉讓總股數-自有持股」。故空值
    // 時 fallback 到後者（已對 live API 用持股算術驗證：目前持有 − 轉讓後持股 = 該值）。
    // 採「自有持股」與下方 currentHolding（亦自有持股）口徑一致。
    final methodSpecificSharesStr =
        json['預定轉讓方式及股數-轉讓股數']?.toString().trim() ?? '';
    final totalOwnSharesStr = json['預定轉讓總股數-自有持股']?.toString().trim() ?? '';
    final transferSharesStr = methodSpecificSharesStr.isNotEmpty
        ? methodSpecificSharesStr
        : totalOwnSharesStr;
    final transferShares =
        TwParseUtils.parseFormattedInt(transferSharesStr) ?? 0;

    // 目前持有採「自有持股」（另有「保留運用決定權信託股數」未計入）
    final currentHoldingStr = json['目前持有股數-自有持股']?.toString().trim() ?? '';
    final currentHolding =
        TwParseUtils.parseFormattedInt(currentHoldingStr) ?? 0;

    final validPeriodStr = json['有效轉讓期間']?.toString().trim() ?? '';
    final (validPeriodStart, validPeriodEnd) = _parseValidPeriod(
      validPeriodStr,
    );

    return TpexInsiderTransfer(
      symbol: symbol,
      companyName: json['CompanyName']?.toString() ?? '',
      reportDate: reportDate,
      identity: json['申請人身分']?.toString() ?? '',
      name: json['姓名']?.toString() ?? '',
      transferMethod: json['預定轉讓方式及股數-轉讓方式']?.toString() ?? '',
      transferShares: transferShares,
      currentHolding: currentHolding,
      validPeriodStart: validPeriodStart,
      validPeriodEnd: validPeriodEnd,
    );
  }

  /// TWSE 版(t187ap12_L,2026-08-05 上市源補接)。
  ///
  /// 與 TPEx(mopsfin_t187ap12_O)同構但欄名不同:代號=「公司代號」
  /// (非 SecuritiesCompanyCode)、日期=「出表日期」(非 Date)、身分=
  /// 「申報人身分」(TPEx 是「申請人身分」)。**值帶前導空格**(live 實測
  /// " 一般交易…"/" 150000"),一律 trim。股數 fallback 規則與 TPEx 同:
  /// 方式別股數空(信託/贈與)→「預定轉讓總股數-自有持股」。
  factory TpexInsiderTransfer.fromTwseJson(Map<String, dynamic> json) {
    String field(String key) => json[key]?.toString().trim() ?? '';

    final symbol = field('公司代號');
    if (symbol.isEmpty || symbol.length < 4 || symbol.length > 6) {
      throw FormatException('無效的公司代號: "$symbol"', json);
    }

    final reportDateStr = field('出表日期');
    final reportDate = TwParseUtils.parseCompactRocDate(reportDateStr);
    if (reportDate == null) {
      throw FormatException('無效的出表日期: "$reportDateStr"', json);
    }

    final methodSpecificShares = field('預定轉讓方式及股數-轉讓股數');
    final totalOwnShares = field('預定轉讓總股數-自有持股');
    final transferSharesStr = methodSpecificShares.isNotEmpty
        ? methodSpecificShares
        : totalOwnShares;
    final transferShares =
        TwParseUtils.parseFormattedInt(transferSharesStr) ?? 0;

    final currentHolding =
        TwParseUtils.parseFormattedInt(field('目前持有股數-自有持股')) ?? 0;

    final (validPeriodStart, validPeriodEnd) = _parseValidPeriod(
      field('有效轉讓期間'),
    );

    return TpexInsiderTransfer(
      symbol: symbol,
      companyName: field('公司名稱'),
      reportDate: reportDate,
      identity: field('申報人身分'),
      name: field('姓名'),
      transferMethod: field('預定轉讓方式及股數-轉讓方式'),
      transferShares: transferShares,
      currentHolding: currentHolding,
      validPeriodStart: validPeriodStart,
      validPeriodEnd: validPeriodEnd,
    );
  }

  static TpexInsiderTransfer? tryFromTwseJson(Map<String, dynamic> json) {
    try {
      return TpexInsiderTransfer.fromTwseJson(json);
    } catch (e) {
      AppLogger.debug('TWSE', '解析內部人轉讓失敗: ${json['公司代號']} ($e)');
      return null;
    }
  }

  static TpexInsiderTransfer? tryFromJson(Map<String, dynamic> json) {
    try {
      return TpexInsiderTransfer.fromJson(json);
    } catch (e) {
      AppLogger.debug(
        'TPEX',
        '解析 TpexInsiderTransfer 失敗: ${json['SecuritiesCompanyCode']} ($e)',
      );
      return null;
    }
  }

  final String symbol; // 公司代號
  final String companyName; // 公司名稱
  final DateTime reportDate; // 申報日期
  final String identity; // 申請人身分 (董事、經理人、大股東)
  final String name; // 姓名
  final String transferMethod; // 轉讓方式
  final int transferShares; // 轉讓股數
  final int currentHolding; // 目前持有股數
  final DateTime? validPeriodStart; // 有效轉讓期間 - 起始日
  final DateTime? validPeriodEnd; // 有效轉讓期間 - 結束日

  /// 解析有效轉讓期間（格式: "1150317~1150416"）
  static (DateTime?, DateTime?) _parseValidPeriod(String period) {
    if (period.isEmpty || !period.contains('~')) {
      return (null, null);
    }

    final parts = period.split('~');
    if (parts.length != 2) {
      return (null, null);
    }

    final start = TwParseUtils.parseCompactRocDate(parts[0].trim());
    final end = TwParseUtils.parseCompactRocDate(parts[1].trim());

    return (start, end);
  }
}

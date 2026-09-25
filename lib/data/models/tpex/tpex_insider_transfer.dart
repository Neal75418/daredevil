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
    // 目前持有採「自有持股」（另有「保留運用決定權信託股數」未計入）
    final currentHoldingStr = json['目前持有股數-自有持股']?.toString().trim() ?? '';
    final currentHolding =
        TwParseUtils.parseFormattedInt(currentHoldingStr) ?? 0;
    String raw(String key) => json[key]?.toString().trim() ?? '';
    final transferShares = _transferShares(
      totalOwn: raw('預定轉讓總股數-自有持股'),
      totalTrust: raw('預定轉讓總股數-保留運用決定權信託股數'),
      methodSpecific: raw('預定轉讓方式及股數-轉讓股數'),
      holdingOwn: currentHolding,
      holdingTrust: raw('目前持有股數-保留運用決定權信託股數'),
      symbol: symbol,
    );

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
  /// " 一般交易…"/" 150000"),一律 trim。轉讓股數規則與 TPEx 同(見
  /// [_transferShares]):以總股數(自有＋信託)為準。
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

    final currentHolding =
        TwParseUtils.parseFormattedInt(field('目前持有股數-自有持股')) ?? 0;
    final transferShares = _transferShares(
      totalOwn: field('預定轉讓總股數-自有持股'),
      totalTrust: field('預定轉讓總股數-保留運用決定權信託股數'),
      methodSpecific: field('預定轉讓方式及股數-轉讓股數'),
      holdingOwn: currentHolding,
      holdingTrust: field('目前持有股數-保留運用決定權信託股數'),
      symbol: symbol,
    );

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

  /// 轉讓股數（上市、上櫃同一規則）。
  ///
  /// 以「預定轉讓總股數」為準：自有持股＋保留運用決定權信託股數兩格，各自是
  /// 單一數字。兩種方式並存時，官方把兩個方式與兩個股數各自接在同一格——
  /// 3189 景碩 2026-08-28「一般交易(每日得轉讓股數限制)鉅額逐筆交易」、
  /// 8000000 與 8000000 無分隔被讀成 80000008000000（持股僅 67037104）；
  /// 2442 2026-08-18 兩方式以空格相隔、解析失敗存成 0。總股數兩格都解析
  /// 不出數字（舊資料、空值或「--」）才退回「預定轉讓方式及股數-轉讓股數」。
  ///
  /// 計畫轉讓不可能超過持有（自有＋信託）：讀出更多代表格式又不如預期，丟
  /// [ImplausibleInsiderTransferException] 讓整筆被跳過（持股不明時無從比較）。
  static int _transferShares({
    required String totalOwn,
    required String totalTrust,
    required String methodSpecific,
    required int holdingOwn,
    required String holdingTrust,
    required String symbol,
  }) {
    final own = TwParseUtils.parseFormattedInt(totalOwn);
    final trust = TwParseUtils.parseFormattedInt(totalTrust);
    final shares = own == null && trust == null
        ? TwParseUtils.parseFormattedInt(methodSpecific) ?? 0
        : (own ?? 0) + (trust ?? 0);
    final holding =
        holdingOwn + (TwParseUtils.parseFormattedInt(holdingTrust) ?? 0);
    if (holding > 0 && shares > holding) {
      throw ImplausibleInsiderTransferException(
        symbol: symbol,
        transferShares: shares,
        currentHolding: holding,
      );
    }
    return shares;
  }

  static TpexInsiderTransfer? tryFromTwseJson(Map<String, dynamic> json) {
    try {
      return TpexInsiderTransfer.fromTwseJson(json);
    } on ImplausibleInsiderTransferException catch (e) {
      AppLogger.warning('TWSE', '跳過內部人轉讓: $e');
      return null;
    } catch (e) {
      AppLogger.debug('TWSE', '解析內部人轉讓失敗: ${json['公司代號']} ($e)');
      return null;
    }
  }

  static TpexInsiderTransfer? tryFromJson(Map<String, dynamic> json) {
    try {
      return TpexInsiderTransfer.fromJson(json);
    } on ImplausibleInsiderTransferException catch (e) {
      AppLogger.warning('TPEX', '跳過內部人轉讓: $e');
      return null;
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

/// 轉讓股數大於目前持股——格式不如預期的訊號（見 `_transferShares`）。
///
/// 獨立型別：一般解析失敗（例如 TPEx 每日回傳的空白列）記 debug，這種記
/// warning，才不會被每天的空白列淹沒。
class ImplausibleInsiderTransferException implements Exception {
  const ImplausibleInsiderTransferException({
    required this.symbol,
    required this.transferShares,
    required this.currentHolding,
  });

  final String symbol;
  final int transferShares;
  final int currentHolding;

  @override
  String toString() =>
      '$symbol 轉讓股數 $transferShares 大於目前持股 $currentHolding，視為格式異常';
}

import 'package:daredevil/core/utils/tw_parse_utils.dart';

/// 全市場財報的一列(TWSE t187ap06/t187ap07、TPEx mopsfin_ 對應)
///
/// **為什麼接這個**:財報是 FinMind 額度的唯一瓶頸——逐檔、且損益表與
/// 資產負債表各一次。129 檔待回填 = 258 次呼叫,佔小時額度 43%,實測
/// 2026-08-16 因額度保留只跑了 10 檔。免費端點一次拿全市場(上市 975 +
/// 上櫃 863 筆),而且涵蓋我們**實際消費的全部四個欄位**。
///
/// **只寫有消費者的四個 data_type**(2026-08-16 grep 實證):
/// - INCOME:`EPS`(3 處)、`GrossProfit`(2 處)
/// - BALANCE:`Equity`(2 處,ROE 的分母)、`TotalAssets`(1 處)
///
/// 其餘十餘個欄位(`CashAndCashEquivalents`、`Liabilities`、`OrdinaryShare`、
/// `TotalLiabilitiesEquity` …)全是 0 處消費者。與 margin 那組「已備料未
/// 消費」的差別在於**這是新增**:免費端點隨時可再抓,不寫沒有不可逆的
/// 損失,寫了只是讓已有 99 萬列的表繼續膨脹。
class MarketWideFinancial {
  const MarketWideFinancial({
    required this.symbol,
    required this.date,
    required this.statementType,
    required this.dataType,
    required this.value,
  });

  final String symbol;
  final DateTime date;
  final String statementType;
  final String dataType;
  final double value;

  // ⚠️ **刻意不提供 parseIncome**(2026-08-16):t187ap06 的損益表是
  // **年度累計**,而 financial_data 的 INCOME 語意是**單季**(FinMind)。
  // 實測台泥:FinMind Q1 6,208,390 + Q2 6,783,334 = 12,991,724 千元,
  // 恰為 TWSE 的「營業毛利」。混寫會讓 2026-08-16 才改成同季 YoY 的 EPS
  // 規則靜默錯亂——數字看起來全都合理。EPS 更不能靠相減還原單季:它用
  // 加權平均股數計算(Q1 0.1 + Q2 0.29 = 0.39,而 TWSE 給 0.38)。
  // 損益表維持 FinMind 逐檔。守門測試見 market_wide_financial_test。

  /// 資產負債表(t187ap07)
  ///
  /// ⚠️ `Equity` 取**權益總計**而非「歸屬於母公司業主之權益合計」:兩者在
  /// 有非控制權益的公司差距很大(台泥 299,322,066 vs 237,429,168),而
  /// FinMind 的 `Equity` 是合併總額——取錯會讓 ROE 系統性偏高。
  static List<MarketWideFinancial> parseBalance(Map<String, dynamic> json) =>
      _parse(json, 'BALANCE', const {'Equity': '權益總計', 'TotalAssets': '資產總計'});

  /// 官方財報端點的金額單位是**千元**,而 `financial_data` 既有資料
  /// (FinMind)是**元**——實測 1101 的 Equity:FinMind 299,322,066,000
  /// vs TWSE 299,322,066。混寫會讓 ROE 的分母差三個數量級,而且不會有
  /// 任何錯誤訊息。
  static const double _thousandsToUnits = 1000;

  static List<MarketWideFinancial> _parse(
    Map<String, dynamic> json,
    String statementType,
    Map<String, String> fieldMap,
  ) {
    // 代號欄名兩市場不同(2026-08-16 實測):TWSE 用「公司代號」、
    // TPEx 用 `SecuritiesCompanyCode`,而數值欄名相同。只認中文欄名時
    // 上櫃 857 筆會全部解析失敗——實跑只出 4 筆。同 QuarterlyReportEntry。
    final symbol =
        (json['公司代號'] ?? json['SecuritiesCompanyCode'])?.toString().trim() ??
        '';
    if (symbol.isEmpty) return const [];

    final date = _quarterEndDate(json);
    if (date == null) return const [];

    return [
      for (final e in fieldMap.entries)
        if (TwParseUtils.parseFormattedDouble(json[e.value]?.toString())
            case final v?)
          MarketWideFinancial(
            symbol: symbol,
            date: date,
            statementType: statementType,
            dataType: e.key,
            value: v * _thousandsToUnits,
          ),
    ];
  }

  /// ROC 年 + 季別 → 季末日
  ///
  /// **必須與 FinMind 既有資料同格式**(實測 `financial_data` 存的是季末日:
  /// 2026-06-30、2026-03-31),否則 ROE 的近四季合計與 EPS 的去年同季比對
  /// 都會撈不到——那會是「資料寫進去了但規則照樣沉默」的無聲失敗。
  static DateTime? _quarterEndDate(Map<String, dynamic> json) {
    final rocYear = int.tryParse(json['年度']?.toString().trim() ?? '');
    final quarter = int.tryParse(json['季別']?.toString().trim() ?? '');
    if (rocYear == null || quarter == null) return null;
    if (quarter < 1 || quarter > 4) return null;
    return switch (quarter) {
      1 => DateTime(rocYear + 1911, 3, 31),
      2 => DateTime(rocYear + 1911, 6, 30),
      3 => DateTime(rocYear + 1911, 9, 30),
      _ => DateTime(rocYear + 1911, 12, 31),
    };
  }
}

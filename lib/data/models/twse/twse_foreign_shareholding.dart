import 'package:daredevil/core/utils/tw_parse_utils.dart';

/// TWSE MI_QFIIS「外資及陸資投資持股統計」的一列
///
/// 補上市股外資持股覆蓋的缺口:原本只靠 FinMind 逐檔呼叫、且只同步
/// 「自選 + 熱門」約 48 檔。2026-08-14 實測上市候選 344 檔僅 82 檔有資料
/// (24%),上櫃因有輪替機制是 116/116 —— 上櫃股拿到外資加分的機會因此
/// 是上市股的 4 倍,那是資料缺口不是市場事實。本端點一次回全市場、免費、
/// 支援歷史日期,欄位與 `shareholding` 表一一對應。
class TwseForeignShareholding {
  const TwseForeignShareholding({
    required this.symbol,
    required this.date,
    this.sharesIssued,
    this.foreignRemainingShares,
    this.foreignSharesRatio,
    this.foreignUpperLimitRatio,
  });

  /// 欄位順序(2026-08-16 對 live API 驗證,共 12 欄):
  /// [0] 證券代號 [1] 證券名稱 [2] 國際證券編碼 [3] 發行股數
  /// [4] 外資及陸資尚可投資股數 [5] 全體外資及陸資持有股數
  /// [6] 外資及陸資尚可投資比率 [7] **全體外資及陸資持股比率**
  /// [8] 外資及陸資共用法令投資上限比率 [9] 陸資法令投資上限比率
  /// [10] 與前日異動原因 [11] 最近一次申報異動日期
  ///
  /// ⚠️ [6] 與 [7] 相加約等於 100,取錯會讓幾乎每檔都像「外資持股 95%」
  /// ——方向完全相反。
  ///
  /// ⚠️ 同一列的型別**不一致**:股數欄是帶千分位的字串,比率欄 [6][7]
  /// API 直接給 double,而 [8][9] 又是字串。逐欄按實際型別處理。
  static TwseForeignShareholding? fromRow(List<dynamic> row, DateTime date) {
    if (row.length < 9) return null;
    final symbol = row[0]?.toString().trim() ?? '';
    if (symbol.isEmpty) return null;

    return TwseForeignShareholding(
      symbol: symbol,
      date: date,
      sharesIssued: _num(row[3]),
      foreignRemainingShares: _num(row[4]),
      foreignSharesRatio: _num(row[7]),
      foreignUpperLimitRatio: _num(row[8]),
    );
  }

  /// 數值容忍 num / 千分位字串兩種型別;無法解析一律 null。
  ///
  /// **不落 0**:持股比率 0 的語意是「外資完全沒持股」,與「這欄拿不到值」
  /// 完全不同(同 2026-08-15 per=0 的教訓)。
  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    return TwParseUtils.parseFormattedDouble(v?.toString());
  }

  final String symbol;
  final DateTime date;

  /// 發行股數
  final double? sharesIssued;

  /// 外資及陸資尚可投資股數
  final double? foreignRemainingShares;

  /// 全體外資及陸資持股比率(%)
  final double? foreignSharesRatio;

  /// 外資及陸資共用法令投資上限比率(%)
  final double? foreignUpperLimitRatio;
}

/// 基本面資料儲存庫介面
///
/// 提供營收、估值、股利、財報的同步功能。
/// 支援測試時的 Mock 及不同實作。
abstract class IFundamentalRepository {
  /// 同步單檔股票月營收
  Future<int> syncMonthlyRevenue({
    required String symbol,
    required DateTime startDate,
    required DateTime endDate,
  });

  /// 同步單檔股票估值資料（PE/PB/殖利率）
  Future<int> syncValuationData({
    required String symbol,
    required DateTime startDate,
    required DateTime endDate,
  });

  /// 同步全市場估值資料（TWSE API）
  Future<int> syncAllMarketValuation(DateTime date, {bool force = false});

  /// 同步上櫃估值資料
  Future<int> syncOtcValuation(
    List<String> symbols, {
    DateTime? date,
    bool force = false,
  });

  /// 同步全市場月營收。回傳同步筆數，null 表示已快取（跳過同步）。
  Future<int?> syncAllMarketRevenue(DateTime date, {bool force = false});

  /// 同步上櫃月營收
  ///
  /// 不收日期：TPEX 全市場端點不吃日期，新鮮度判定用的是「現在幾號」
  /// （由實作的 clock 提供），不是資料日。
  Future<int> syncOtcRevenue(List<String> symbols, {bool force = false});

  /// 同步財務報表
  Future<int> syncFinancialStatements({
    required String symbol,
    required DateTime startDate,
    required DateTime endDate,
  });
}

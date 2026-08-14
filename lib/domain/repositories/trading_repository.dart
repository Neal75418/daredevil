import 'package:daredevil/data/database/app_database.dart';

/// 交易資料儲存庫介面
///
/// 處理當沖與融資融券資料的查詢、同步與分析功能。
/// 支援測試時的 Mock 及不同實作。
abstract class ITradingRepository {
  // ==================================================
  // 當沖
  // ==================================================

  /// 取得當沖歷史資料
  Future<List<DayTradingEntry>> getDayTradingHistory(
    String symbol, {
    int days = 30,
  });

  /// 從 TWSE 同步全市場當沖資料（上市）
  ///
  /// 無上櫃對等 method — TPEX 當沖端點被 Cloudflare 擋、OpenAPI 也無替代。
  Future<int> syncAllDayTradingFromTwse({DateTime? date, bool force = false});

  // ==================================================
  // 融資融券
  // ==================================================

  /// 取得融資融券歷史資料
  Future<List<MarginTradingEntry>> getMarginTradingHistory(
    String symbol, {
    int days = 30,
  });

  /// 從 TWSE/TPEX 同步全市場融資融券資料。回傳同步筆數，null 表示已快取（跳過同步）。
  Future<int?> syncAllMarginTrading({DateTime? date, bool force = false});

  /// 回補**指定歷史交易日**、**指定市場**的融資融券資料。
  ///
  /// 與 [syncAllMarginTrading] 的差異：
  /// - 每日路徑刻意不傳日期（TPEx 有 T+1 延遲，端點自動回最新可用日）；
  ///   回補路徑明確指定日期，並丟棄「entry 日期 ≠ 請求日期」的列
  ///   （端點無視日期參數時的防護）。
  /// - [markets] 只抓**確實缺漏**的市場（`MarketCode.twse` / `.tpex`）。
  ///   若無條件抓全部，重寫已存在的市場也會讓回傳筆數 > 0，caller 會誤判
  ///   為「有進度」→ 單一市場端點永久失效時將無限重試、吃光單次上限。
  ///
  /// 回傳**各市場**寫入筆數。caller 需據此逐市場判斷「是否跨過缺漏門檻」——
  /// 合併成單一數字會讓「上市成功、上櫃永久失敗」看起來像有進度。
  Future<({int twseRows, int tpexRows})> backfillMarginTradingByDate({
    required DateTime date,
    required Set<String> markets,
  });
}

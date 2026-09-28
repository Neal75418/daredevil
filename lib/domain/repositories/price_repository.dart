import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';

/// 價格資料儲存庫介面
///
/// 支援測試時的 Mock 及不同實作（如本機資料庫、遠端 API、記憶體快取）
abstract class IPriceRepository {
  // ==================================================
  // 價格資料查詢
  // ==================================================

  /// 取得分析用的價格歷史
  ///
  /// 若有足夠資料，至少回傳 [RuleParams.lookbackPrice] 天
  Future<List<DailyPriceEntry>> getPriceHistory(
    String symbol, {
    int? days,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// 取得股票最新價格
  Future<DailyPriceEntry?> getLatestPrice(String symbol);

  /// 取得特定日期的收盤價
  Future<DailyPriceEntry?> getPriceOnDate(String symbol, DateTime date);

  // ==================================================
  // 同步作業
  // ==================================================

  /// 同步單一股票價格（依市場分流：上市逐月打 TWSE、上櫃整段 1 次打 FinMind）
  Future<int> syncStockPrices(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  });

  /// 同步最新交易日所有價格並回傳快速篩選候選股
  ///
  /// ⚠️ 只有全市場抓取可傳 [ledger]；部分股票的呼叫（例如 tool/backfill 的
  /// targetSymbols 子集）不得傳，否則會把缺股的日子標成定案。
  Future<MarketSyncResult> syncAllPricesForDate(
    DateTime date, {
    bool force = false,
    MarketDayFetchLedger? ledger,
  });

  /// 用 TWSE batch endpoint 回補單一交易日**所有**上市股票價格
  ///
  /// 用於 backfill：相較於 [syncStockPrices] 對每檔股票分別呼叫 TWSE 月度
  /// API（per-symbol × per-month，2 年 backfill 數萬次 calls 會觸發 TWSE
  /// IP-based rate limit "Redirect loop detected"），本方法走 TWSE
  /// MI_INDEX 歷史端點（STOCK_DAY_ALL 自 2026-06 起忽略 date 參數），
  /// **一次 call 回該日全部上市股票**。完整 2 年 backfill 從約 1400×24 ≈ 33,000 次降到約 500 次，
  /// 且 TWSE 該 endpoint 也免費沒額度。
  ///
  /// 與 [backfillTpexPricesByDate] 採完全對稱 pattern。
  ///
  /// 回傳實際寫入的 price row 數。
  ///
  /// 例外政策：[RateLimitException] / [NetworkException] rethrow；其他例外
  /// 包成 [DatabaseException]。
  ///
  /// ⚠️ 只有全市場抓取可傳 [ledger]；部分股票的呼叫（例如 tool/backfill 的
  /// targetSymbols 子集）不得傳，否則會把缺股的日子標成定案。
  Future<int> backfillTwsePricesByDate({
    required DateTime date,
    required Set<String> targetSymbols,
    MarketDayFetchLedger? ledger,
  });

  /// 用 TPEx OpenAPI batch endpoint 回補單一交易日**所有**上櫃股票價格
  ///
  /// 用於 backfill：相較於 `syncStockPrices(symbol)` 對每檔股票分別呼叫
  /// FinMind（per-symbol，2 年 backfill 數千 calls 必然吃光免費額度），
  /// 本方法走 TPEx `afterTrading/dailyQuotes` 歷史端點
  /// （`getAllDailyPricesHistorical`；官方口徑，含定價交易、含零股，與每日
  /// 端點 `daily_close_quotes` 相同——舊的 `afterTrading/otc` 是「不含定價、
  /// 整張」口徑，只有官方的 91–98%，已停用），**一次 call 回該日
  /// 全部上櫃股票**。完整 2 年 backfill 從約 8000×24 ≈ 19 萬次降到約 500 次，
  /// 且 TPEx OpenAPI 完全免費沒額度限制。
  ///
  /// [targetSymbols] 為要寫入 DB 的 symbol 白名單；其他從 API 回來但不在
  /// 白名單的股票（例如新上市但 stock_master 尚未同步到的）會被忽略。
  ///
  /// 回傳實際寫入的 price row 數。
  ///
  /// 例外政策：[RateLimitException] / [NetworkException] rethrow（交給呼叫端
  /// 決定 abort/retry）；其他例外包成 [DatabaseException]。
  ///
  /// ⚠️ 只有全市場抓取可傳 [ledger]；部分股票的呼叫（例如 tool/backfill 的
  /// targetSymbols 子集）不得傳，否則會把缺股的日子標成定案。
  Future<int> backfillTpexPricesByDate({
    required DateTime date,
    required Set<String> targetSymbols,
    MarketDayFetchLedger? ledger,
  });
}

/// 全市場價格同步結果
class MarketSyncResult {
  const MarketSyncResult({
    required this.count,
    required this.candidates,
    this.dataDate,
    this.skipped = false,
    this.emptyMarkets = const [],
  });

  final int count;
  final List<String> candidates;

  /// 主要資料日期（優先 TWSE）
  final DateTime? dataDate;

  final bool skipped;

  /// 本輪回傳零筆的市場（`MarketCode` 值）
  ///
  /// 來源失敗被 `safeAwait` 吞成空清單，只有**兩個市場皆空**才會被察覺；
  /// 若僅 TWSE 掛掉，TPEx 非空就不進該分支，等於用半個市場的資料照常評分
  /// 而無人知曉。呼叫端必須據此 `recordError`，讓 run 降級為 partial。
  ///
  /// 交易日空清單才代表異常——非交易日 TPEx 本就回零筆，故僅在有實際
  /// 抓取行為時填入（快取路徑不填）。
  final List<String> emptyMarkets;
}

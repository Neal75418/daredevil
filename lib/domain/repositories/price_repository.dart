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
  ///
  /// [withBasePrices]：價格之後抓同一天的平盤價（上市 TWT84U、上櫃
  /// exDailyQ）並寫進同一個 transaction，狀態在
  /// [MarketSyncResult.basePrices]。`false` 只給校準 DB（`tool/backfill`）
  /// 用，**不得與 [ledger] 同時傳**（assert）：會把缺平盤價的日子記成定案。
  Future<MarketSyncResult> syncAllPricesForDate(
    DateTime date, {
    bool force = false,
    MarketDayFetchLedger? ledger,
    bool withBasePrices = true,
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
  /// 回傳實際寫入的 price row 數與平盤價狀態（[MarketDayBackfillResult]）。
  ///
  /// 例外政策：價格本身的 [RateLimitException] / [NetworkException] rethrow；
  /// 其他例外包成 [DatabaseException]。**平盤價那一段的錯誤不拋**（價格與平盤
  /// 價寫進同一個 transaction，拋出會連價格都寫不進去），放進
  /// [MarketDayBackfillResult.basePrice]。
  ///
  /// ⚠️ 只有全市場抓取可傳 [ledger]；部分股票的呼叫（例如 tool/backfill 的
  /// targetSymbols 子集）不得傳，否則會把缺股的日子標成定案。
  /// [withBasePrices] 同 [syncAllPricesForDate]，不得與 [ledger] 同時傳。
  Future<MarketDayBackfillResult> backfillTwsePricesByDate({
    required DateTime date,
    required Set<String> targetSymbols,
    MarketDayFetchLedger? ledger,
    bool withBasePrices = true,
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
  /// 回傳實際寫入的 price row 數與平盤價狀態（[MarketDayBackfillResult]）。
  ///
  /// 例外政策：價格本身的 [RateLimitException] / [NetworkException] rethrow
  /// （交給呼叫端決定 abort/retry）；其他例外包成 [DatabaseException]。
  /// **平盤價那一段的錯誤不拋**，放進 [MarketDayBackfillResult.basePrice]。
  ///
  /// ⚠️ 只有全市場抓取可傳 [ledger]；部分股票的呼叫（例如 tool/backfill 的
  /// targetSymbols 子集）不得傳，否則會把缺股的日子標成定案。
  /// [withBasePrices] 同 [syncAllPricesForDate]，不得與 [ledger] 同時傳。
  Future<MarketDayBackfillResult> backfillTpexPricesByDate({
    required DateTime date,
    required Set<String> targetSymbols,
    MarketDayFetchLedger? ledger,
    bool withBasePrices = true,
  });
}

/// 平盤價抓取結果（除權息漲跌修正 spec 第 3 節狀態表）
enum BasePriceFetch {
  /// 回應可信
  fetched,

  /// 網路錯誤、回應不可信（stat／date／total 不符）、解析失敗、需要的列
  /// 一列都對不上
  failed,

  /// 限流（原始例外在 [BasePriceStatus.error]）
  rateLimited,

  /// 這批沒有需要平盤價的列（上櫃沒有文字標記），沒抓
  notNeeded,

  /// 價格回空，或 `withBasePrices: false`，沒抓
  skipped,
}

/// 市場日價格寫入後，每個市場的平盤價狀態：抓取結果＋N。
///
/// 平盤價那一段的錯誤不拋（價格與平盤價寫進同一個 transaction，拋出會連價格
/// 都寫不進去、呼叫端也拿不到回傳值），呼叫端只看 [rateLimited] 與
/// [shouldRecordError]。
class BasePriceStatus {
  const BasePriceStatus({
    required this.fetch,
    this.missing = 0,
    this.withheld = false,
    this.reason,
    this.error,
  });

  final BasePriceFetch fetch;

  /// 需要平盤價、合併後仍沒有的列數（N）
  final int missing;

  /// 本函式因平盤價而沒向 ledger 回報定案（這一天會被步驟 5.5 重抓）
  final bool withheld;

  final String? reason;
  final Object? error;

  bool get rateLimited => fetch == BasePriceFetch.rateLimited;

  /// 呼叫端要記 errors 的情況（spec 呼叫端表的「缺」）：沒回報定案、而且
  /// 不是限流（限流由呼叫端另設旗標）。`fetched` 而 N＞0 只記 warning；
  /// `failed` 而 N＝0 只記 log。
  bool get shouldRecordError => withheld && !rateLimited;

  static const notNeeded = BasePriceStatus(fetch: BasePriceFetch.notNeeded);
  static const skipped = BasePriceStatus(fetch: BasePriceFetch.skipped);

  @override
  String toString() =>
      'BasePriceStatus(${fetch.name}, missing: $missing, withheld: $withheld'
      '${reason == null ? '' : ', $reason'})';
}

/// 單一市場、單一交易日回補的結果
class MarketDayBackfillResult {
  const MarketDayBackfillResult({required this.rows, required this.basePrice});

  /// 實際寫入的價格列數
  final int rows;

  final BasePriceStatus basePrice;
}

/// 全市場價格同步結果
class MarketSyncResult {
  const MarketSyncResult({
    required this.count,
    required this.candidates,
    this.dataDate,
    this.skipped = false,
    this.emptyMarkets = const [],
    this.basePrices = const {},
  });

  final int count;
  final List<String> candidates;

  /// 每個市場（`MarketCode`）的平盤價狀態；提早回傳的分支（已定案跳過、
  /// 兩市場皆空）為空 Map
  final Map<String, BasePriceStatus> basePrices;

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

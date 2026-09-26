import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';

/// 三大法人買賣超資料儲存庫介面
///
/// 提供法人資料的查詢、同步與分析功能。
/// 支援測試時的 Mock 及不同實作。
abstract class IInstitutionalRepository {
  /// 取得法人資料歷史供分析使用
  Future<List<DailyInstitutionalEntry>> getInstitutionalHistory(
    String symbol, {
    int? days,
  });

  /// 同步單檔股票的法人資料
  Future<int> syncInstitutionalData(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  });

  /// 同步指定日期的全市場法人資料
  Future<int> syncAllMarketInstitutional(
    DateTime date, {
    bool force = false,
    MarketDayFetchLedger? ledger,
  });

  /// 用 TWSE + TPEx batch endpoint 回補單一交易日**指定股票**的法人資料
  ///
  /// 用於 backfill：相較於 `syncInstitutionalData(symbol, startDate, endDate)`
  /// 對每檔股票分別呼叫 FinMind（per-symbol，2 年 backfill 數千 calls 必然
  /// 吃光免費額度），本方法走 TWSE T86 + TPEx OpenAPI 的 daily batch，
  /// **一次 call 拿該日全市場法人資料**。完整 2 年 backfill 從約 8000×N
  /// 降到約 500×2 (TWSE + TPEx) ≈ 1000 次，且兩個 endpoint 都免費沒額度。
  ///
  /// 與 [syncAllMarketInstitutional] 的差別：本方法用 [targetSymbols] 作為
  /// 寫入白名單（對齊 backfill CLI 的 symbol 範圍語意），且不做 freshness
  /// skip check（resumability 由 idempotent upsert 保證）。
  ///
  /// 回傳實際寫入的 row 數。
  ///
  /// 例外政策：[RateLimitException] / [NetworkException] rethrow；其他例外
  /// 包成 [DatabaseException]。TWSE / TPEx 兩個 source 任一失敗會 fall back
  /// 到只用另一個 source（與 [syncAllMarketInstitutional] 的容錯一致）。
  Future<int> backfillInstitutionalByDate({
    required DateTime date,
    required Set<String> targetSymbols,
  });

  /// 清除所有法人資料
  Future<int> clearAllData();

  /// 口徑版本檢核：版本不符（或無記錄）即一次性清空重建並寫入 marker
  ///
  /// 回傳是否執行了遷移。
  Future<bool> ensureDataVersion();

  /// 該日法人資料是否已達完整門檻（上市+上櫃合計）
  ///
  /// 供回補迴圈**在節流延遲前**預檢——已完整的天不睡不打。
  Future<bool> isDayComplete(DateTime date);

  /// 該日法人兩市場是否都已定案（當日路徑的跳過判斷）
  Future<bool> isDayFinal(DateTime date);

  /// 口徑遷移後的深回補是否尚未完整跑完
  ///
  /// [ensureDataVersion] 遷移清空時落 pending marker；深回補（62 天窗）
  /// 完整跑完由 syncer 呼叫 [markDeepBackfillComplete] 蓋章。未蓋章前
  /// 每輪同步都維持深回補窗——限流打斷後靠 per-day 完整性檢查斷點續傳，
  /// 不再依賴一次性的遷移回傳值。
  Future<bool> isDeepBackfillPending();

  /// 深回補完整跑完（零錯誤）後蓋章，後續輪次恢復日常淺回補窗
  Future<void> markDeepBackfillComplete();
}

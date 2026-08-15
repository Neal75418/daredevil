import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

/// 持股相關 Repository
///
/// 處理：外資持股、股權分散表
class ShareholdingRepository {
  ShareholdingRepository({
    required AppDatabase database,
    required FinMindClient finMindClient,
    required TwseClient twseClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _client = finMindClient,
       _twse = twseClient,
       _clock = clock;

  final AppDatabase _db;
  final FinMindClient _client;
  final TwseClient _twse;
  final AppClock _clock;

  // ==================================================
  // 外資持股
  // ==================================================

  /// 全市場外資持股同步(TWSE MI_QFIIS,免費批次)
  ///
  /// **為什麼需要**:[syncShareholding] 走 FinMind 逐檔,受配額限制,而
  /// update_service 只餵它「自選 + 熱門」約 48 檔。2026-08-14 實測上市候選
  /// 344 檔僅 82 檔有外資資料(24%),上櫃因有輪替機制是 116/116(100%)
  /// ——上櫃股拿到 FOREIGN_* 加分的機會因此是上市股的 4 倍,那是資料缺口
  /// 不是市場事實。本方法一次補齊全市場上市股。
  ///
  /// 與當沖/融資融券同屬「免費批次 API」那一層,配額不是 bottleneck。
  Future<int> syncAllMarketShareholding({
    required DateTime date,
    bool force = false,
  }) async {
    try {
      // 新鮮度檢查用**覆蓋率**而非「有沒有列」(2026-08-16 實機修正)。
      //
      // 正式 DB 的 8/13 只有 213 筆——那是 FinMind 逐檔留下的零星結果,
      // 而全市場應有 1,200+ 筆。用 `> 0` 判斷會把這種半殘的日子永遠跳過:
      // 覆蓋看起來補了,實際上那天還是缺一千多檔,而且**再也不會被重抓**。
      if (!force) {
        final existing = await _db.countShareholdingForDate(date);
        final listed = await _db.countStocksByMarket(MarketCode.twse);
        final threshold =
            listed * ApiConfig.foreignShareholdingMinCoverageRatio;
        if (existing >= threshold) return 0;
      }

      final data = await _twse.getAllForeignShareholding(date: date);
      if (data.isEmpty) return 0;

      // FK 過濾:MI_QFIIS 含 ETF 與尚未進 stock_master 的新標的,
      // 直接寫會炸 foreign key constraint
      final known = (await _db.getAllActiveStocks())
          .map((s) => s.symbol)
          .toSet();
      final entries = [
        for (final item in data)
          if (known.contains(item.symbol))
            ShareholdingCompanion.insert(
              symbol: item.symbol,
              date: item.date,
              foreignRemainingShares: Value(item.foreignRemainingShares),
              foreignSharesRatio: Value(item.foreignSharesRatio),
              foreignUpperLimitRatio: Value(item.foreignUpperLimitRatio),
              sharesIssued: Value(item.sharesIssued),
            ),
      ];
      if (entries.isEmpty) return 0;

      await _db.insertShareholdingData(entries);
      AppLogger.info(
        'ShareholdingRepo',
        '全市場外資持股: ${entries.length} 筆 '
            '(來源 ${data.length} 筆,非在冊 ${data.length - entries.length} 筆)',
      );
      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync market-wide shareholding', e);
    }
  }

  /// 回補外資持股的歷史交易日(MI_QFIIS 支援 date 參數)
  ///
  /// **為什麼需要**:全市場同步補上了覆蓋,但 FOREIGN_SHAREHOLDING_
  /// INCREASING / DECREASING 讀的是**變化量**([InstitutionalParams.
  /// foreignShareholdingLookbackDays] 個交易日前的水位差)。新覆蓋的股票
  /// 只有當日一筆時,那些規則仍然不會觸發——覆蓋補上了、訊號還是沉默,
  /// 只是換了個原因。回補幾次呼叫就能讓規則立刻生效,不必等一週。
  ///
  /// **只補缺的日子**:已有資料的交易日直接跳過,所以重跑不會把整個窗口
  /// 重打一遍(回補迴圈收斂設計的第一條)。單日失敗不中斷其餘日子——
  /// 交易所對個別歷史日回空是常態,不該讓一天拖垮整輪。
  Future<int> backfillForeignShareholding({
    required DateTime asOf,
    int days = 5,
  }) async {
    var filled = 0;
    // ⚠️ 用 subtractTradingDays 而非 getPreviousTradingDay:後者的語意是
    // 「取得**含當天**的最近交易日」——傳一個交易日進去會原封不動回傳,
    // 游標永遠卡在同一天(2026-08-16 debug 探針實測)。
    final start = TaiwanCalendar.getPreviousTradingDay(
      DateContext.normalize(asOf),
    );
    for (var i = 0; i < days; i++) {
      final day = i == 0 ? start : TaiwanCalendar.subtractTradingDays(start, i);
      try {
        final written = await syncAllMarketShareholding(date: day);
        if (written > 0) filled++;
      } on RateLimitException {
        rethrow;
      } catch (e) {
        // 單日失敗不中斷:交易所對個別歷史日回空/異常是常態
        AppLogger.warning(
          'ShareholdingRepo',
          '外資持股回補 ${DateContext.formatYmd(day)} 失敗,續補其餘日子',
          e,
        );
      }
    }
    if (filled > 0) {
      AppLogger.info('ShareholdingRepo', '外資持股回補: $filled 個交易日');
    }
    return filled;
  }

  /// 取得外資持股歷史資料
  Future<List<ShareholdingEntry>> getShareholdingHistory(
    String symbol, {
    int days = 60,
  }) async {
    final startDate = _clock.now().subtract(Duration(days: days + 30));
    return _db.getShareholdingHistory(symbol, startDate: startDate);
  }

  /// 取得股票最新外資持股資料
  Future<ShareholdingEntry?> getLatestShareholding(String symbol) {
    return _db.getLatestShareholding(symbol);
  }

  /// 從 FinMind 同步外資持股資料
  ///
  /// 包含新鮮度檢查以避免不必要的 API 呼叫。
  /// 若 [endDate]（或今日）的資料已存在則跳過。
  Future<int> syncShareholding(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    try {
      // 新鮮度檢查：若已有目標日期資料則跳過
      final targetDate = endDate ?? _clock.now();
      final latest = await getLatestShareholding(symbol);
      if (latest != null && DateContext.isSameDay(latest.date, targetDate)) {
        return 0;
      }

      final data = await _client.getShareholding(
        stockId: symbol,
        startDate: DateContext.formatYmd(startDate),
        endDate: endDate != null ? DateContext.formatYmd(endDate) : null,
      );

      final entries = data.map((item) {
        return ShareholdingCompanion.insert(
          symbol: item.stockId,
          date: DateTime.parse(item.date),
          foreignRemainingShares: Value(item.foreignInvestmentRemainingShares),
          foreignSharesRatio: Value(item.foreignInvestmentSharesRatio),
          foreignUpperLimitRatio: Value(item.foreignInvestmentUpperLimitRatio),
          sharesIssued: Value(item.numberOfSharesIssued),
        );
      }).toList();

      await _db.insertShareholdingData(entries);
      return entries.length;
    } on RateLimitException {
      AppLogger.warning('ShareholdingRepo', '$symbol: 外資持股同步觸發 API 速率限制');
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync shareholding for $symbol', e);
    }
  }

  // ==================================================
  // 股權分散表
  // ==================================================

  /// 批次取得多檔股票的最新持股資料
  Future<Map<String, ShareholdingEntry>> getLatestShareholdingsBatch(
    List<String> symbols,
  ) {
    return _db.getLatestShareholdingsBatch(symbols);
  }

  /// 取得最新股權分散表
  Future<List<HoldingDistributionEntry>> getLatestHoldingDistribution(
    String symbol,
  ) {
    return _db.getLatestHoldingDistribution(symbol);
  }

  /// 批次計算多檔股票的籌碼集中度
  ///
  /// 回傳 symbol -> 大戶持股比例(%) 的 Map。
  /// 無資料的股票不會出現在結果中。
  Future<Map<String, double>> getConcentrationRatioBatch(
    List<String> symbols, {
    int thresholdLevel = ChipScoringParams.largeHolderMinLot,
  }) async {
    final batchData = await _db.getLatestHoldingDistributionBatch(symbols);
    final result = <String, double>{};

    for (final entry in batchData.entries) {
      double largeHolderPercent = 0;
      for (final dist in entry.value) {
        final minShares = _parseMinSharesFromLevel(dist.level);
        if (minShares >= thresholdLevel) {
          largeHolderPercent += dist.percent ?? 0;
        }
      }
      result[entry.key] = largeHolderPercent;
    }

    return result;
  }

  // ==================================================
  // 私有輔助方法
  // ==================================================

  /// 從級距字串解析最小持股數
  int _parseMinSharesFromLevel(String level) {
    // 處理 "1000以上" 或 "over 1000"
    if (level.contains('以上') || level.toLowerCase().contains('over')) {
      final numStr = level.replaceAll(RegExp(r'[^\d]'), '');
      return int.tryParse(numStr) ?? 0;
    }

    // 處理 "400-600" 格式
    final parts = level.split('-');
    if (parts.isNotEmpty) {
      final numStr = parts[0].replaceAll(RegExp(r'[^\d]'), '');
      return int.tryParse(numStr) ?? 0;
    }

    return 0;
  }
}

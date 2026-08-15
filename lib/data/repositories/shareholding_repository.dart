import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
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
      // 新鮮度檢查:當日已有資料就跳過(force 繞過)。門檻用「有沒有那天的
      // 列」而非筆數——全市場一次寫入,不會有寫一半的中間態
      if (!force) {
        final existing = await _db.countShareholdingForDate(date);
        if (existing > 0) return 0;
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

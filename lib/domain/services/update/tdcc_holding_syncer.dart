import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';

/// TDCC 股權分散表同步器
///
/// 從 TDCC 集保中心 Open Data 取得全市場股權分散表，
/// 篩選候選股票後寫入 HoldingDistribution 表。
///
/// - 資料每週更新（週五收盤後公布）
/// - 一次 API 呼叫取得全市場資料，無需逐檔查詢
/// - 內建新鮮度檢查，最新一期未滿一週不重複下載（每次約 9.8 MB）
class TdccHoldingSyncer {
  const TdccHoldingSyncer({
    required AppDatabase database,
    required TdccClient tdccClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _tdcc = tdccClient,
       _clock = clock;

  final AppDatabase _db;
  final TdccClient _tdcc;
  final AppClock _clock;

  /// 同步股權分散表資料
  ///
  /// [candidateSymbols] 若提供，則只寫入這些股票的資料（節省 DB 空間）。
  /// 若為 null 則寫入全市場。
  ///
  /// 回傳寫入的股票數。
  Future<int> sync({Set<String>? candidateSymbols}) async {
    if (await _hasLatestIssue()) {
      AppLogger.debug('TdccHoldingSyncer', '最新一期未滿一週，跳過同步');
      return 0;
    }

    try {
      final allData = await _tdcc.getAllHoldingDistribution();
      if (allData.isEmpty) {
        AppLogger.warning('TdccHoldingSyncer', 'TDCC API 回傳空資料');
        return 0;
      }

      // 取得 DB 中所有已知股票（FK constraint 要求 symbol 必須存在於 StockMaster）
      final knownStocks = await _db.getAllActiveStocks();
      final knownSymbols = knownStocks.map((s) => s.symbol).toSet();

      // 篩選：必須存在於 StockMaster + 可選候選過濾（toList 確保單次遍歷，避免 length 重複求值）
      final symbolsToSync = allData.keys
          .where(
            (s) =>
                knownSymbols.contains(s) &&
                (candidateSymbols == null || candidateSymbols.contains(s)),
          )
          .toList();

      final companions = <HoldingDistributionCompanion>[];

      for (final symbol in symbolsToSync) {
        final levels = allData[symbol]!;
        for (final level in levels) {
          companions.add(
            HoldingDistributionCompanion(
              symbol: Value(symbol),
              date: Value(level.date),
              level: Value(TdccClient.levelCodeToRangeString(level.level)),
              shareholders: Value(level.shareholders),
              percent: Value(level.percent),
              shares: Value(level.shares),
            ),
          );
        }
      }

      if (companions.isEmpty) {
        AppLogger.debug('TdccHoldingSyncer', '無需寫入的資料');
        return 0;
      }

      await _db.insertHoldingDistribution(companions);

      final syncedCount = symbolsToSync.length;
      AppLogger.info(
        'TdccHoldingSyncer',
        '同步完成: $syncedCount 檔股票 (${companions.length} 筆級距)',
      );
      return syncedCount;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('TdccHoldingSyncer', '同步失敗', e);
      rethrow;
    }
  }

  /// DB 的最新一期距今是否未滿一個公布週期
  ///
  /// 🚨 不可用「資料日與今天同一週」：資料日是上週最後交易日，平日永遠
  /// 與今天不同週，結果每輪更新都重抓（2026-09 日誌同一天下載兩次）。
  /// 以日曆天數比較，週五休市（資料日落在週四）也成立。
  Future<bool> _hasLatestIssue() async {
    // 用台積電 (2330) 作為哨兵檢查
    final latestDate = await _db.getLatestHoldingDistributionDate('2330');
    if (latestDate == null) return false;
    final now = _clock.now();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(
          DateTime.utc(latestDate.year, latestDate.month, latestDate.day),
        )
        .inDays;
    return days < DataFreshness.tdccIssueIntervalDays;
  }
}

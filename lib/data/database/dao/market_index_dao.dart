import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_index_tables.drift.dart';
import 'package:daredevil/core/utils/device_time.dart';

/// 大盤指數歷史資料存取
mixin MarketIndexDaoMixin on $AppDatabase {
  // ==================================================
  // 大盤指數歷史操作
  // ==================================================

  /// 批次寫入大盤指數資料（upsert on conflict (date, name)）
  Future<void> upsertMarketIndices(List<MarketIndexCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(
          marketIndex,
          entry,
          onConflict: DoUpdate(
            (_) => entry,
            target: [marketIndex.date, marketIndex.name],
          ),
        );
      }
    });
  }

  /// 取得多個指數的近 N 日歷史（批次）
  Future<Map<String, List<MarketIndexEntry>>> getIndexHistoryBatch(
    List<String> indexNames, {
    int days = 30,
    DateTime? now,
  }) async {
    final upperBound = now ?? DeviceTime.now();
    final cutoff = upperBound.subtract(Duration(days: days + 10));
    // 上界防護：未來日期的髒資料（曾因 parseAdDate 誤判而寫入）永遠不會被讀出，
    // 避免污染走勢圖（V 字毛刺）與均線計算。
    final rows =
        await (select(marketIndex)
              ..where(
                (t) =>
                    t.name.isIn(indexNames) &
                    t.date.isBiggerThanValue(cutoff) &
                    t.date.isSmallerOrEqualValue(upperBound),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.date)]))
            .get();

    final result = <String, List<MarketIndexEntry>>{};
    for (final row in rows) {
      result.putIfAbsent(row.name, () => []).add(row);
    }
    return result;
  }
}

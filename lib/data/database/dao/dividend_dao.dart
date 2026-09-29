import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 股利歷史操作
mixin DividendDaoMixin on $AppDatabase {
  /// 取得股票的股利歷史（依年度降冪排序）
  Future<List<DividendHistoryEntry>> getDividendHistory(String symbol) {
    return (select(dividendHistory)
          ..where((t) => t.symbol.equals(symbol))
          ..orderBy([(t) => OrderingTerm.desc(t.year)]))
        .get();
  }

  /// 批次新增股利資料
  Future<void> insertDividendData(
    List<DividendHistoryCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(dividendHistory, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 寫入股利配發（一次除權息一列）。同一除息日重抓以新值覆蓋。
  Future<void> upsertDividendDistributions(
    List<DividendDistributionCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(dividendDistribution, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 取得股票的股利配發（依除息日由新到舊）
  Future<List<DividendDistributionEntry>> getDividendDistributions(
    String symbol,
  ) {
    return (select(dividendDistribution)
          ..where((t) => t.symbol.equals(symbol))
          ..orderBy([(t) => OrderingTerm.desc(t.exDate)]))
        .get();
  }

  /// 批次取得多檔股票的股利配發（各檔依除息日由新到舊）
  Future<Map<String, List<DividendDistributionEntry>>>
  getDividendDistributionsBatch(List<String> symbols) async {
    if (symbols.isEmpty) return {};

    final result =
        await (select(dividendDistribution)
              ..where((t) => t.symbol.isIn(symbols))
              ..orderBy([(t) => OrderingTerm.desc(t.exDate)]))
            .get();

    final map = <String, List<DividendDistributionEntry>>{};
    for (final entry in result) {
      map.putIfAbsent(entry.symbol, () => []).add(entry);
    }
    return map;
  }

  /// 批次取得多檔股票的股利歷史
  Future<Map<String, List<DividendHistoryEntry>>> getDividendHistoryBatch(
    List<String> symbols,
  ) async {
    if (symbols.isEmpty) return {};

    final result =
        await (select(dividendHistory)
              ..where((t) => t.symbol.isIn(symbols))
              ..orderBy([(t) => OrderingTerm.desc(t.year)]))
            .get();

    final map = <String, List<DividendHistoryEntry>>{};
    for (final entry in result) {
      map.putIfAbsent(entry.symbol, () => []).add(entry);
    }
    return map;
  }
}

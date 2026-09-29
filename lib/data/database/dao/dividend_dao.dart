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

  /// 寫入除權除息（一次一列，含金額皆 0 的已處理列）。同一除息日重抓以
  /// 新值覆蓋。
  Future<void> upsertDividendDistributions(
    List<DividendDistributionCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(dividendDistribution, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 取得股票的股利配發（依除息日由新到舊）。只回有配發的列，不含只有
  /// 現金增資的除權。
  Future<List<DividendDistributionEntry>> getDividendDistributions(
    String symbol,
  ) {
    return (select(dividendDistribution)
          ..where((t) => t.symbol.equals(symbol) & _isDistribution(t))
          ..orderBy([(t) => OrderingTerm.desc(t.exDate)]))
        .get();
  }

  /// 批次取得多檔股票的股利配發（各檔依除息日由新到舊）。只回有配發的列。
  Future<Map<String, List<DividendDistributionEntry>>>
  getDividendDistributionsBatch(List<String> symbols) async {
    if (symbols.isEmpty) return {};

    final result =
        await (select(dividendDistribution)
              ..where((t) => t.symbol.isIn(symbols) & _isDistribution(t))
              ..orderBy([(t) => OrderingTerm.desc(t.exDate)]))
            .get();

    final map = <String, List<DividendDistributionEntry>>{};
    for (final entry in result) {
      map.putIfAbsent(entry.symbol, () => []).add(entry);
    }
    return map;
  }

  /// [from]～[to]（含頭尾）已處理的除權除息 (symbol, exDate)，含金額皆 0
  /// 的列。同步據此跳過已查過明細的列。
  Future<Set<(String, DateTime)>> getDividendDistributionKeys({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows =
        await (selectOnly(dividendDistribution)
              ..addColumns([
                dividendDistribution.symbol,
                dividendDistribution.exDate,
              ])
              ..where(dividendDistribution.exDate.isBetweenValues(from, to)))
            .get();
    return {
      for (final row in rows)
        (
          row.read(dividendDistribution.symbol)!,
          row.read(dividendDistribution.exDate)!,
        ),
    };
  }

  Expression<bool> _isDistribution($DividendDistributionTable t) =>
      t.cashDividend.isBiggerThanValue(0) |
      t.stockSharesPerThousand.isBiggerThanValue(0);

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

import 'package:drift/drift.dart';

import 'package:daredevil/core/utils/calendar_month.dart';
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

  /// 刪除一列除權除息（含金額皆 0 的已處理列）。回補發現 DB 裡的舊列與
  /// 明細不符時用：留著的話，下一輪會把它當成已處理、不再查明細。
  Future<void> deleteDividendDistribution(String symbol, DateTime exDate) =>
      (delete(
        dividendDistribution,
      )..where((t) => t.symbol.equals(symbol) & t.exDate.equals(exDate))).go();

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

  /// 全部逐月完成紀錄
  Future<List<DividendMonthLedgerEntry>> getDividendMonthLedgerEntries() =>
      select(dividendMonthLedger).get();

  /// 全部逐月失敗紀錄
  Future<List<DividendMonthFailureEntry>> getDividendMonthFailures() =>
      select(dividendMonthFailure).get();

  /// 在同一個 transaction 內：刪除該單位的失敗紀錄 → 寫入 [rows] → 核對
  /// [expectedKeys] 全部在庫（範圍＝該月 1 日至月底）→ 寫入完成紀錄。
  ///
  /// 缺任一鍵時整個 transaction 回滾（失敗紀錄與 [rows] 都不留），回傳缺的
  /// 鍵；回傳空集合代表已記為完成。「有完成紀錄＝資料在庫」因此是 commit
  /// 當下查核過的事實，不是從寫入順序推論出來的。
  ///
  /// 第一句刻意是寫入：drift 開的是 deferred BEGIN，WAL 下若先讀後寫、而
  /// 其他連線剛好 commit，會拋 SQLITE_BUSY_SNAPSHOT，busy_timeout 不會重試。
  ///
  /// [month] 必須早於 [completedAt] 所在月份（該月結束後才能記完成），否則
  /// 拋 [ArgumentError]。[expectedKeys] 的 DateTime 必須是當地午夜（與讀回
  /// 的值同一語意），UTC 值用 `==` 永遠比不到。
  Future<Set<(String, DateTime)>> completeDividendMonth({
    required String market,
    required CalendarMonth month,
    required List<DividendDistributionCompanion> rows,
    required Set<(String, DateTime)> expectedKeys,
    required int listedRows,
    required Set<String> skippedSymbols,
    required DateTime completedAt,
  }) async {
    if (!month.isBefore(CalendarMonth.of(completedAt))) {
      throw ArgumentError.value(month, 'month', '只能記錄 $completedAt 所在月份之前的月份');
    }
    try {
      await transaction<void>(() async {
        // 順序是正確性的一部分：這句寫入必須在任何讀取之前（見上）
        await (delete(dividendMonthFailure)..where(
              (t) =>
                  t.market.equals(market) &
                  t.year.equals(month.year) &
                  t.month.equals(month.month),
            ))
            .go();
        if (rows.isNotEmpty) await upsertDividendDistributions(rows);
        final present = await getDividendDistributionKeys(
          from: month.firstDay,
          to: month.lastDay,
        );
        final missing = expectedKeys.difference(present);
        if (missing.isNotEmpty) throw _IncompleteDividendMonth(missing);
        await into(dividendMonthLedger).insertOnConflictUpdate(
          DividendMonthLedgerCompanion.insert(
            market: market,
            year: month.year,
            month: month.month,
            completedAt: completedAt,
            listedRows: listedRows,
            knownRows: expectedKeys.length,
            skippedSymbols: encodeDividendSymbols(skippedSymbols),
          ),
        );
      });
      return const {};
    } on _IncompleteDividendMonth catch (e) {
      return e.missing;
    }
  }

  /// 記一次失敗：該單位的失敗次數加 1，時間、錯誤（截斷至 300 字）、明細
  /// 查不到的代號與列表狀態以這一次為準。單一 UPSERT，不先讀。
  Future<void> recordDividendMonthFailure({
    required String market,
    required CalendarMonth month,
    required DateTime failedAt,
    required String error,
    Set<String> failedSymbols = const {},
    required bool listOk,
  }) async {
    final truncated = error.length > _maxFailureErrorLength
        ? error.substring(0, _maxFailureErrorLength)
        : error;
    await into(dividendMonthFailure).insert(
      DividendMonthFailureCompanion.insert(
        market: market,
        year: month.year,
        month: month.month,
        failCount: 1,
        lastFailedAt: failedAt,
        lastError: truncated,
        failedSymbols: encodeDividendSymbols(failedSymbols),
        listOk: listOk,
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => DividendMonthFailureCompanion.custom(
          failCount: old.failCount + const Constant(1),
          lastFailedAt: excluded.lastFailedAt,
          lastError: excluded.lastError,
          failedSymbols: excluded.failedSymbols,
          listOk: excluded.listOk,
        ),
      ),
    );
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

/// 失敗紀錄保存的錯誤訊息長度上限（完整錯誤進回補摘要，這裡只供診斷）
const _maxFailureErrorLength = 300;

/// 代號集合的儲存格式：排序、去重、逗號分隔；空集合為空字串
String encodeDividendSymbols(Iterable<String> symbols) =>
    (symbols.toSet().toList()..sort()).join(',');

Set<String> _decodeDividendSymbols(String encoded) =>
    encoded.isEmpty ? const {} : encoded.split(',').toSet();

extension DividendMonthLedgerEntryX on DividendMonthLedgerEntry {
  CalendarMonth get calendarMonth => CalendarMonth(year, month);

  Set<String> get skippedSymbolSet => _decodeDividendSymbols(skippedSymbols);
}

extension DividendMonthFailureEntryX on DividendMonthFailureEntry {
  CalendarMonth get calendarMonth => CalendarMonth(year, month);

  Set<String> get failedSymbolSet => _decodeDividendSymbols(failedSymbols);
}

class _IncompleteDividendMonth implements Exception {
  const _IncompleteDividendMonth(this.missing);

  final Set<(String, DateTime)> missing;
}

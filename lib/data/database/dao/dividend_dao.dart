import 'package:drift/drift.dart';

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 股利操作：除權除息配發、逐月完成／失敗紀錄、完整度事實
mixin DividendDaoMixin on $AppDatabase {
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

  /// 以列表的值更新已在庫列的前收盤與除權息參考價；不動金額，不在庫的鍵
  /// 不新增。上市「權」「權息」列明細已查過、不再重查時用它補價。
  Future<void> updateDividendDistributionPrices(
    List<DividendListedPrice> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) {
      for (final r in rows) {
        b.update(
          dividendDistribution,
          DividendDistributionCompanion(
            closeBefore: Value(r.closeBefore),
            referencePrice: Value(r.referencePrice),
          ),
          where: (t) => t.symbol.equals(r.symbol) & t.exDate.equals(r.exDate),
        );
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

  /// 批次取得除權息日在 [from]～[to]（含頭尾）的除權除息列，**含只有現金
  /// 增資的 0/0 列**與前收盤、除權息參考價——還原價格用（畫面用
  /// [getDividendDistributionsBatch]，只回有配發的列）。各檔依除息日由舊到新。
  Future<Map<String, List<DividendDistributionEntry>>> getDividendEventsBatch(
    List<String> symbols, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (symbols.isEmpty) return {};
    final rows =
        await (select(dividendDistribution)
              ..where(
                (t) =>
                    t.symbol.isIn(symbols) & t.exDate.isBetweenValues(from, to),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.exDate)]))
            .get();
    final map = <String, List<DividendDistributionEntry>>{};
    for (final row in rows) {
      map.putIfAbsent(row.symbol, () => []).add(row);
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

  /// 全部列表日
  Future<List<DividendListingEntry>> getDividendListings() =>
      select(dividendListing).get();

  /// 全部未解決的列
  Future<List<DividendUnresolvedEntry>> getDividendUnresolved() =>
      select(dividendUnresolved).get();

  /// 缺前收盤或除權息參考價的配發列 (symbol, exDate)
  Future<Set<(String, DateTime)>> getDividendMissingPriceKeys() async {
    final rows = await (select(
      dividendDistribution,
    )..where((t) => t.closeBefore.isNull() | t.referencePrice.isNull())).get();
    return {for (final r in rows) (r.symbol, r.exDate)};
  }

  /// 列表成功後記錄完整度事實，一個 transaction：
  ///
  /// 1. 刪除 [market] 在 [from]～[to] 的未解決列（第一句是寫入，理由同
  ///    [completeDividendMonth]）
  /// 2. 讀範圍內已在庫的鍵；未解決＝[listedKnownKeys] − 在庫（原因取
  ///    [reasons]，沒有的記 pendingDetail），加上 [notInMasterKeys] − 在庫
  ///    （記 notInMaster）。「不在清單＝在庫」是交易當下查核的事實
  /// 3. [from] 所在月到 [listedThrough] 所在月的每個月，列表日前進到
  ///    min([listedThrough], 月底)；[listedThrough] 早於 [from] 時不前進。
  ///    只能連續前進：該月的範圍起點不是 1 日時，現有有效列表日（列表日或
  ///    完成紀錄的月底）必須 ≥ 起點前一天，否則中間有一段沒列過，不前進；
  ///    也不倒退
  ///
  /// [from]、[to]、[listedThrough] 為當地午夜，[listedThrough] ≤ [to]。
  Future<void> recordDividendListing({
    required String market,
    required DateTime from,
    required DateTime to,
    required DateTime listedThrough,
    required Set<(String, DateTime)> listedKnownKeys,
    required Set<(String, DateTime)> notInMasterKeys,
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
    required DateTime recordedAt,
  }) async {
    await transaction<void>(() async {
      // 順序是正確性的一部分：這句寫入必須在任何讀取之前
      await (delete(dividendUnresolved)..where(
            (t) => t.market.equals(market) & t.exDate.isBetweenValues(from, to),
          ))
          .go();
      final stored = await getDividendDistributionKeys(from: from, to: to);
      DividendUnresolvedCompanion entry(
        (String, DateTime) key,
        DividendUnresolvedReason reason,
      ) => DividendUnresolvedCompanion.insert(
        market: market,
        symbol: key.$1,
        exDate: key.$2,
        reason: reason.code,
        recordedAt: recordedAt,
      );
      final unresolved = [
        for (final key in listedKnownKeys.difference(stored))
          entry(key, reasons[key] ?? DividendUnresolvedReason.pendingDetail),
        for (final key in notInMasterKeys.difference(stored))
          entry(key, DividendUnresolvedReason.notInMaster),
      ];
      if (unresolved.isNotEmpty) {
        await batch(
          (b) => b.insertAll(
            dividendUnresolved,
            unresolved,
            mode: InsertMode.insertOrReplace,
          ),
        );
      }
      await _advanceDividendListing(
        market: market,
        from: from,
        listedThrough: listedThrough,
      );
    });
  }

  Future<void> _advanceDividendListing({
    required String market,
    required DateTime from,
    required DateTime listedThrough,
  }) async {
    final listed = {
      for (final e in await (select(
        dividendListing,
      )..where((t) => t.market.equals(market))).get())
        CalendarMonth(e.year, e.month): e.listedThrough,
    };
    final completed = {
      for (final e in await (select(
        dividendMonthLedger,
      )..where((t) => t.market.equals(market))).get())
        if (e.calendarMonth.isBefore(CalendarMonth.of(e.completedAt)))
          e.calendarMonth,
    };
    for (final month in CalendarMonth.descending(
      from: CalendarMonth.of(from),
      to: CalendarMonth.of(listedThrough),
    )) {
      final start = from.isAfter(month.firstDay) ? from : month.firstDay;
      final through = listedThrough.isBefore(month.lastDay)
          ? listedThrough
          : month.lastDay;
      final stored = listed[month];
      final existing = completed.contains(month) ? month.lastDay : stored;
      final dayBeforeStart = DateTime(start.year, start.month, start.day - 1);
      final contiguous =
          start == month.firstDay ||
          (existing != null && !existing.isBefore(dayBeforeStart));
      if (!contiguous) continue;
      if (existing != null && !through.isAfter(existing)) continue;
      await into(dividendListing).insertOnConflictUpdate(
        DividendListingCompanion.insert(
          market: market,
          year: month.year,
          month: month.month,
          listedThrough: through,
        ),
      );
    }
  }

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
            pricesRecorded: const Value(true),
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
}

/// 失敗紀錄保存的錯誤訊息長度上限（完整錯誤進回補摘要，這裡只供診斷）
const _maxFailureErrorLength = 300;

/// 列表上一列的前收盤與除權息參考價（補價用）
typedef DividendListedPrice = ({
  String symbol,
  DateTime exDate,
  double? closeBefore,
  double? referencePrice,
});

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

/// 列表上有、但不在配發表的原因（存 [code]）
enum DividendUnresolvedReason {
  /// 尚未查明細（預算用完、被中斷）
  pendingDetail('PENDING_DETAIL'),

  /// 明細查詢失敗或回應不可信
  detailFailed('DETAIL_FAILED'),

  /// 明細推算的參考價與列表不符（可能查到別次除權息）
  referenceMismatch('REFERENCE_MISMATCH'),

  /// 列表當時不在在市股票主檔
  notInMaster('NOT_IN_MASTER');

  const DividendUnresolvedReason(this.code);

  final String code;
}

class _IncompleteDividendMonth implements Exception {
  const _IncompleteDividendMonth(this.missing);

  final Set<(String, DateTime)> missing;
}

// dividend_month_ledger／dividend_month_failure 以 beforeOpen 的
// Migrator.createTable 補建，且與 dividend_distribution 同生共死
//
// 完成紀錄若在 fingerprint reset 時留下、資料卻被清掉，讀取端會把「沒資料」
// 讀成「沒配息」，回補也會跳過那些月份，變成永久缺洞。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dividend_backfill_schema');
    dbFile = File('${tempDir.path}/db.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('既有 DB 沒有四張股利紀錄表：開啟後補建，行情資料保留', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db1.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: DateTime(2026, 9, 24),
        close: const Value(100),
      ),
    ]);
    for (final table in [
      'dividend_month_ledger',
      'dividend_month_failure',
      'dividend_listing',
      'dividend_unresolved',
    ]) {
      await db1.customStatement('DROP TABLE $table');
    }
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    expect(await db2.getPricesForDate(DateTime(2026, 9, 24)), hasLength(1));
    expect(await db2.getDividendMonthLedgerEntries(), isEmpty);
    expect(await db2.getDividendMonthFailures(), isEmpty);
    expect(await db2.getDividendListings(), isEmpty);
    expect(await db2.getDividendUnresolved(), isEmpty);
    await db2.close();
  });

  test('fingerprint reset：五張股利表一起清空', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db1.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
      ),
    ]);
    expect(
      await db1.completeDividendMonth(
        market: 'TWSE',
        month: const CalendarMonth(2025, 9),
        rows: const [],
        expectedKeys: {('2330', DateTime(2025, 9, 16))},
        listedRows: 1,
        skippedSymbols: const {},
        completedAt: DateTime(2026, 9, 29),
      ),
      isEmpty,
    );
    await db1.recordDividendMonthFailure(
      market: 'TPEx',
      month: const CalendarMonth(2025, 9),
      failedAt: DateTime(2026, 9, 29),
      error: 'boom',
      listOk: false,
    );
    expect(await db1.getDividendMonthLedgerEntries(), hasLength(1));
    expect(await db1.getDividendMonthFailures(), hasLength(1));
    await db1.recordDividendListing(
      market: 'TWSE',
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 2),
      listedThrough: DateTime(2026, 10, 2),
      listedKnownKeys: {('2330', DateTime(2026, 10, 2))},
      notInMasterKeys: const {},
      recordedAt: DateTime(2026, 10, 2),
    );
    expect(await db1.getDividendListings(), hasLength(1));
    expect(await db1.getDividendUnresolved(), hasLength(1));
    await db1.close();

    final rawDb = raw.sqlite3.open(dbFile.path);
    rawDb.execute(
      "UPDATE _drift_schema_fingerprint SET value = 'stale-old-fingerprint'",
    );
    rawDb.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    expect(
      await db2.getDividendDistributionKeys(
        from: DateTime(2000),
        to: DateTime(2100),
      ),
      isEmpty,
    );
    expect(await db2.getDividendMonthLedgerEntries(), isEmpty);
    expect(await db2.getDividendMonthFailures(), isEmpty);
    expect(await db2.getDividendListings(), isEmpty);
    expect(await db2.getDividendUnresolved(), isEmpty);
    await db2.close();
  });
}

// 除權除息逐月完成紀錄（dividend_month_ledger）與失敗紀錄（dividend_month_failure）
//
// 完成紀錄一列＝該市場該月已知代號的除權息列全部在庫的事實，只能經
// completeDividendMonth 在同一個 transaction 內核對後寫入。
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  const sep = CalendarMonth(2025, 9);
  final completedAt = DateTime(2026, 9, 29, 21, 30);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '6488', name: '環球晶', market: 'TPEx'),
    ]);
  });

  tearDown(() => db.close());

  DividendDistributionCompanion row(String symbol, DateTime exDate) =>
      DividendDistributionCompanion.insert(
        symbol: symbol,
        exDate: exDate,
        cashDividend: 1,
        stockSharesPerThousand: 0,
      );

  Future<Set<(String, DateTime)>> complete({
    String market = 'TWSE',
    CalendarMonth month = sep,
    List<DividendDistributionCompanion> rows = const [],
    required Set<(String, DateTime)> expected,
    Set<String> skipped = const {},
  }) => db.completeDividendMonth(
    market: market,
    month: month,
    rows: rows,
    expectedKeys: expected,
    listedRows: 10,
    skippedSymbols: skipped,
    completedAt: completedAt,
  );

  group('completeDividendMonth', () {
    test('預期列全部在庫：寫入完成紀錄、只刪該單位的失敗紀錄、寫入傳入的列', () async {
      await db.upsertDividendDistributions([
        row('2330', DateTime(2025, 9, 16)),
      ]);
      for (final (market, month) in [
        ('TWSE', sep),
        ('TPEx', sep),
        ('TWSE', const CalendarMonth(2025, 8)),
        ('TWSE', const CalendarMonth(2026, 9)),
      ]) {
        await db.recordDividendMonthFailure(
          market: market,
          month: month,
          failedAt: completedAt,
          error: 'boom',
          listOk: false,
        );
      }

      final missing = await complete(
        rows: [row('6488', DateTime(2025, 9, 30))],
        expected: {
          ('2330', DateTime(2025, 9, 16)),
          ('6488', DateTime(2025, 9, 30)),
        },
        skipped: {'910322', '00950B'},
      );

      expect(missing, isEmpty);
      final ledger = (await db.getDividendMonthLedgerEntries()).single;
      expect(ledger.market, 'TWSE');
      expect(ledger.calendarMonth, sep);
      expect(ledger.listedRows, 10);
      expect(ledger.knownRows, 2);
      expect(ledger.skippedSymbols, '00950B,910322', reason: '排序');
      expect(ledger.skippedSymbolSet, {'00950B', '910322'});
      expect(ledger.completedAt, completedAt);
      expect(
        (await db.getDividendMonthFailures())
            .map((f) => '${f.market} ${f.calendarMonth}')
            .toSet(),
        {'TPEx 2025-09', 'TWSE 2025-08', 'TWSE 2026-09'},
      );
      expect(await db.getDividendDistributions('6488'), hasLength(1));
    });

    test('缺任一預期列：回傳缺的鍵、不寫完成紀錄、失敗紀錄保留、傳入的列回滾', () async {
      await db.recordDividendMonthFailure(
        market: 'TWSE',
        month: sep,
        failedAt: completedAt,
        error: 'boom',
        listOk: true,
      );

      final missing = await complete(
        rows: [row('6488', DateTime(2025, 9, 30))],
        expected: {
          ('6488', DateTime(2025, 9, 30)),
          ('2330', DateTime(2025, 9, 16)),
        },
      );

      expect(missing, {('2330', DateTime(2025, 9, 16))});
      expect(await db.getDividendMonthLedgerEntries(), isEmpty);
      expect(await db.getDividendMonthFailures(), hasLength(1));
      expect(await db.getDividendDistributions('6488'), isEmpty);
    });

    test('核對範圍涵蓋當月 1 日與月底', () async {
      await db.upsertDividendDistributions([
        row('2330', DateTime(2025, 9, 1)),
        row('6488', DateTime(2025, 9, 30)),
      ]);

      final missing = await complete(
        expected: {
          ('2330', DateTime(2025, 9, 1)),
          ('6488', DateTime(2025, 9, 30)),
        },
      );

      expect(missing, isEmpty);
    });

    test('預期列在別的月份不算在庫（上月底、下月初）', () async {
      await db.upsertDividendDistributions([
        row('2330', DateTime(2025, 8, 31)),
        row('6488', DateTime(2025, 10, 1)),
      ]);

      final missing = await complete(
        expected: {
          ('2330', DateTime(2025, 8, 31)),
          ('6488', DateTime(2025, 10, 1)),
        },
      );

      expect(missing, {
        ('2330', DateTime(2025, 8, 31)),
        ('6488', DateTime(2025, 10, 1)),
      });
    });

    test('只能記錄完成時間所在月份之前的月份', () async {
      for (final month in [
        const CalendarMonth(2026, 9),
        const CalendarMonth(2026, 10),
      ]) {
        await expectLater(
          complete(month: month, expected: const {}),
          throwsA(isA<ArgumentError>()),
          reason: '$month',
        );
      }
      expect(await db.getDividendMonthLedgerEntries(), isEmpty);
    });

    test('沒有預期列：記為完成，已知列數 0；略過代號為空字串', () async {
      expect(await complete(expected: const {}), isEmpty);
      final ledger = (await db.getDividendMonthLedgerEntries()).single;
      expect(ledger.knownRows, 0);
      expect(ledger.skippedSymbols, '');
      expect(ledger.skippedSymbolSet, isEmpty);
    });

    test('同一單位重新完成：只留一列，以最後一次為準', () async {
      await complete(expected: const {}, skipped: {'910322'});
      await complete(expected: const {});

      final ledger = (await db.getDividendMonthLedgerEntries()).single;
      expect(ledger.skippedSymbolSet, isEmpty);
    });

    test('不同市場、不同月份各自一列（含跨年）', () async {
      await complete(expected: const {});
      await complete(market: 'TPEx', expected: const {});
      await complete(month: const CalendarMonth(2025, 12), expected: const {});
      await complete(month: const CalendarMonth(2026, 1), expected: const {});

      final keys = (await db.getDividendMonthLedgerEntries())
          .map((e) => '${e.market} ${e.calendarMonth}')
          .toSet();
      expect(keys, {
        'TWSE 2025-09',
        'TPEx 2025-09',
        'TWSE 2025-12',
        'TWSE 2026-01',
      });
    });
  });

  group('recordDividendMonthFailure', () {
    test('累加失敗次數，時間、錯誤、失敗代號與列表狀態以最後一次為準', () async {
      await db.recordDividendMonthFailure(
        market: 'TWSE',
        month: sep,
        failedAt: DateTime(2026, 9, 28),
        error: 'first',
        failedSymbols: {'2836'},
        listOk: true,
      );
      await db.recordDividendMonthFailure(
        market: 'TWSE',
        month: sep,
        failedAt: DateTime(2026, 9, 29),
        error: 'second',
        listOk: false,
      );

      final f = (await db.getDividendMonthFailures()).single;
      expect(f.failCount, 2);
      expect(f.lastFailedAt, DateTime(2026, 9, 29));
      expect(f.lastError, 'second');
      expect(f.failedSymbolSet, isEmpty);
      expect(f.listOk, isFalse);
      expect(f.calendarMonth, sep);
    });

    test('錯誤訊息截斷到 300 字', () async {
      await db.recordDividendMonthFailure(
        market: 'TWSE',
        month: sep,
        failedAt: completedAt,
        error: 'x' * 500,
        listOk: false,
      );

      expect(
        (await db.getDividendMonthFailures()).single.lastError.length,
        300,
      );
    });

    test('不同單位互不影響', () async {
      for (final market in ['TWSE', 'TPEx']) {
        await db.recordDividendMonthFailure(
          market: market,
          month: sep,
          failedAt: completedAt,
          error: 'e',
          listOk: false,
        );
      }

      final failures = await db.getDividendMonthFailures();
      expect(failures.map((f) => f.failCount), [1, 1]);
    });
  });

  test('代號集合編碼：排序、去重、逗號分隔', () {
    expect(
      encodeDividendSymbols(['910322', '00950B', '910322']),
      '00950B,910322',
    );
    expect(encodeDividendSymbols(const []), '');
  });

  test('月份超出 1–12：資料庫 CHECK 拒絕', () async {
    await expectLater(
      db.customStatement(
        'INSERT INTO dividend_month_ledger (market, year, month, completed_at, '
        'listed_rows, known_rows, skipped_symbols) '
        "VALUES ('TWSE', 2025, 13, '2026-09-29T00:00:00.000', 0, 0, '')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}

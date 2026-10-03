// 除權除息完整度事實（dividend_listing、dividend_unresolved）的寫入
//
// 列表成功後以一個 transaction 記錄：未解決的列由 DB 現況推導、整批取代；
// 列表日只能連續前進，有效列表日含完成紀錄（完成＝列到月底）。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final recordedAt = DateTime(2026, 10, 2, 15, 30);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2836', name: '高雄銀', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  Future<void> record({
    String market = 'TWSE',
    required DateTime from,
    required DateTime to,
    DateTime? listedThrough,
    Set<(String, DateTime)> known = const {},
    Set<(String, DateTime)> notInMaster = const {},
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
  }) => db.recordDividendListing(
    market: market,
    from: from,
    to: to,
    listedThrough: listedThrough ?? to,
    listedKnownKeys: known,
    notInMasterKeys: notInMaster,
    reasons: reasons,
    recordedAt: recordedAt,
  );

  Future<Map<String, DateTime>> listings() async => {
    for (final e in await db.getDividendListings())
      '${e.market} ${CalendarMonth(e.year, e.month)}': e.listedThrough,
  };

  Future<Map<String, String>> unresolved() async => {
    for (final u in await db.getDividendUnresolved())
      '${u.market} ${u.symbol} ${u.exDate.month}/${u.exDate.day}': u.reason,
  };

  group('未解決的列', () {
    test('列表上的已知列減去在庫的列；原因依傳入，沒有的記 pendingDetail；未知代號記 notInMaster', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2330',
          exDate: DateTime(2026, 9, 16),
          cashDividend: 5,
          stockSharesPerThousand: 0,
        ),
      ]);

      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        known: {
          ('2330', DateTime(2026, 9, 16)),
          ('2836', DateTime(2026, 9, 17)),
          ('2836', DateTime(2026, 9, 18)),
        },
        notInMaster: {('00950B', DateTime(2026, 9, 18))},
        reasons: {
          ('2836', DateTime(2026, 9, 17)):
              DividendUnresolvedReason.referenceMismatch,
        },
      );

      expect(await unresolved(), {
        'TWSE 2836 9/17': 'REFERENCE_MISMATCH',
        'TWSE 2836 9/18': 'PENDING_DETAIL',
        'TWSE 00950B 9/18': 'NOT_IN_MASTER',
      });
    });

    test('整批取代：範圍內舊的未解決列被清掉，範圍外與另一市場的不動', () async {
      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        known: {('2836', DateTime(2026, 9, 17))},
      );
      await record(
        market: 'TPEx',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        notInMaster: {('6762', DateTime(2026, 9, 17))},
      );
      await record(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 31),
        known: {('2836', DateTime(2026, 8, 13))},
      );

      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));

      expect(await unresolved(), {
        'TPEx 6762 9/17': 'NOT_IN_MASTER',
        'TWSE 2836 8/13': 'PENDING_DETAIL',
      });
    });

    test('未知代號的列若已在庫（之前在主檔時寫入）不記為未解決', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2330',
          exDate: DateTime(2026, 9, 16),
          cashDividend: 5,
          stockSharesPerThousand: 0,
        ),
      ]);

      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        notInMaster: {('2330', DateTime(2026, 9, 16))},
      );

      expect(await unresolved(), isEmpty);
    });
  });

  group('列表日', () {
    test('回補整月：列到月底', () async {
      await record(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31));
      expect(await listings(), {'TWSE 2026-08': DateTime(2026, 8, 31)});
    });

    test('本月同步：記到列表日（資料日），範圍跨上個月尾巴時上個月要連續才前進', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 26));

      // 10/2 的本月同步：範圍 9/25～10/2，資料日 10/2
      await record(from: DateTime(2026, 9, 25), to: DateTime(2026, 10, 2));

      expect(await listings(), {
        'TWSE 2026-09': DateTime(2026, 9, 30),
        'TWSE 2026-10': DateTime(2026, 10, 2),
      });
    });

    test('上個月中間有一段沒列過：不前進（本月照記）', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 20));

      await record(from: DateTime(2026, 9, 25), to: DateTime(2026, 10, 2));

      expect(await listings(), {
        'TWSE 2026-09': DateTime(2026, 9, 20),
        'TWSE 2026-10': DateTime(2026, 10, 2),
      });
    });

    test('上個月有完成紀錄（舊版只寫完成紀錄）：視為列到月底，不需要再寫列表日', () async {
      await db.completeDividendMonth(
        market: 'TWSE',
        month: const CalendarMonth(2026, 8),
        rows: const [],
        expectedKeys: const {},
        listedRows: 0,
        skippedSymbols: const {},
        completedAt: DateTime(2026, 9, 1),
      );

      await record(from: DateTime(2026, 8, 26), to: DateTime(2026, 9, 2));

      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 2)});
    });

    test('凌晨補跑跨月：資料日 9/30、今天 10/1，不替 10 月記列表日', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 29));

      await record(
        from: DateTime(2026, 9, 24),
        to: DateTime(2026, 10, 1),
        listedThrough: DateTime(2026, 9, 30),
      );

      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 30)});
    });

    test('連續性邊界：已列到起點前一天 → 前進', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 24));
      await record(from: DateTime(2026, 9, 25), to: DateTime(2026, 9, 30));
      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 30)});
    });

    test('連續性邊界：只列到起點前兩天（中間缺一天）→ 不前進', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 23));
      await record(from: DateTime(2026, 9, 25), to: DateTime(2026, 9, 30));
      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 23)});
    });

    test('長假後：資料日早於範圍起點，不記列表日', () async {
      // 跨月：2/10 開工、資料日停在 1/30，範圍 2/1～2/10
      await record(
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 2, 10),
        listedThrough: DateTime(2026, 1, 30),
      );
      // 同月：2/3 開工、資料日停在 1/23，範圍 1/27～2/3；1 月只列到 1/23
      await record(from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 23));
      await record(
        from: DateTime(2026, 1, 27),
        to: DateTime(2026, 2, 3),
        listedThrough: DateTime(2026, 1, 23),
      );

      expect(await listings(), {'TWSE 2026-01': DateTime(2026, 1, 23)});
    });

    test('不倒退：較短的列表不覆蓋較長的列表日', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 26));
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 20));
      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 26)});
    });
  });

  test('缺前收盤或除權息參考價的配發列', () async {
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
        closeBefore: const Value(1000),
        referencePrice: const Value(995),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
        closeBefore: const Value(10.6),
      ),
    ]);

    expect(await db.getDividendMissingPriceKeys(), {
      ('2836', DateTime(2026, 9, 17)),
    });
  });
}

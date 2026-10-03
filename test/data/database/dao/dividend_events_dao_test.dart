// 還原用的除權除息事件查詢：含只有現金增資的 0/0 列與價格兩欄，
// 只回除權息日在範圍內的列
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '3149', name: '正達', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '3149',
        exDate: DateTime(2026, 7, 17),
        cashDividend: 0,
        stockSharesPerThousand: 0,
        closeBefore: const Value(93.5),
        referencePrice: const Value(86.68),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 7,
        stockSharesPerThousand: 0,
        closeBefore: const Value(2385),
        referencePrice: const Value(2377.99),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 6, 11),
        cashDividend: 6,
        stockSharesPerThousand: 0,
        closeBefore: const Value(1100),
        referencePrice: const Value(1094),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 6, 12),
        cashDividend: 4.5,
        stockSharesPerThousand: 0,
      ),
    ]);
  });

  tearDown(() => db.close());

  test('含 0/0 列與價格兩欄；只回除權息日在範圍內（含頭尾）的列，各檔由舊到新', () async {
    final events = await db.getDividendEventsBatch(
      ['3149', '2330', '9999'],
      from: DateTime(2026, 6, 11),
      to: DateTime(2026, 9, 16),
    );

    expect(
      {
        for (final e in events.entries)
          e.key: [for (final r in e.value) r.exDate],
      },
      {
        '3149': [DateTime(2026, 7, 17)],
        '2330': [DateTime(2026, 6, 11), DateTime(2026, 9, 16)],
      },
    );
    final rights = events['3149']!.single;
    expect(
      (
        rights.cashDividend,
        rights.stockSharesPerThousand,
        rights.closeBefore,
        rights.referencePrice,
      ),
      (0.0, 0.0, 93.5, 86.68),
    );
  });

  test('沒有代號時回空', () async {
    expect(
      await db.getDividendEventsBatch(
        const [],
        from: DateTime(2026),
        to: DateTime(2027),
      ),
      isEmpty,
    );
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902', '9903', '9904'])
        StockMasterCompanion.insert(symbol: s, name: '測$s', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  Future<void> hold(String symbol, double quantity) =>
      db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: symbol,
          quantity: Value(quantity),
        ),
      );

  test('自選∪持股（數量 > 0），已清倉的持股不算', () async {
    await db.addToWatchlist('9901');
    await db.addToWatchlist('9904');
    await hold('9902', 1000);
    await hold('9903', 0);
    await hold('9904', 500);

    expect(await db.getWatchlistAndHoldingSymbols(), {'9901', '9902', '9904'});
  });

  test('都沒有時回空集合', () async {
    expect(await db.getWatchlistAndHoldingSymbols(), isEmpty);
  });
}

// market_day_fetch 以 Migrator.createTable 補建（不 bump fingerprint）
//
// 模擬真實升級：帶著行情資料、但沒有這張表的既有 DB 被新版開啟。
// 若改成 bump fingerprint，行情表會被 drop，這條會紅。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mdf_schema_test');
    dbFile = File('${tempDir.path}/mdf.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('既有 DB 沒有 market_day_fetch：開啟後補建，行情資料保留', () async {
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
    await db1.customStatement('DROP TABLE market_day_fetch');
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final prices = await db2.getPricesForDate(DateTime(2026, 9, 24));
    expect(prices, hasLength(1), reason: '行情資料不得因補建而消失');
    expect(await db2.getMarketDayFetchesSince(DateTime(2000)), isEmpty);
    await db2.close();
  });
}

// dividend_distribution 以 beforeOpen 的 Migrator.createTable 補建
//
// 模擬真實升級：帶著行情資料、但沒有這張表的既有 DB 被新版開啟，表要被
// 補上、行情資料原封不動。不涵蓋「改成 bump fingerprint」：db1 開啟時已
// 寫入當前指紋，db2 不會進 wipe 路徑。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dividend_dist_schema_test');
    dbFile = File('${tempDir.path}/dd.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('既有 DB 沒有 dividend_distribution：開啟後補建，行情資料保留', () async {
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
    await db1.customStatement('DROP TABLE dividend_distribution');
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final prices = await db2.getPricesForDate(DateTime(2026, 9, 24));
    expect(prices, hasLength(1), reason: '行情資料不得因補建而消失');
    expect(await db2.getDividendDistributions('2330'), isEmpty);
    await db2.close();
  });
}

// market_regime 以 Migrator.createTable 補建（不 bump fingerprint）
//
// 模擬真實升級：帶著行情資料、但沒有這張表的既有 DB 被新版開啟。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/market_regime.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('market_regime_schema_test');
    dbFile = File('${tempDir.path}/regime.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('既有 DB 沒有 market_regime：開啟後補建，行情資料保留', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db1.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: DateTime(2026, 11, 24),
        close: const Value(100),
      ),
    ]);
    await db1.customStatement('DROP TABLE market_regime');
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final prices = await db2.getPricesForDate(DateTime(2026, 11, 24));
    expect(prices, hasLength(1), reason: '行情資料不得因補建而消失');
    expect(await db2.getMarketRegimeForDate(DateTime(2026, 11, 24)), isNull);
    await db2.close();
  });

  test('fingerprint reset：market_regime 一起清空（衍生資料）', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await AnalysisRepository(database: db1).replaceMarketRegimeForDate(
      DateTime(2026, 11, 24),
      const MarketRegimeReading(
        eligibleCount: 455,
        upCount: 132,
        medianReturn: -0.16,
        isUptrend: false,
        lookbackDays: 120,
      ),
    );
    expect(await db1.getMarketRegimeForDate(DateTime(2026, 11, 24)), isNotNull);
    await db1.close();

    final rawDb = raw.sqlite3.open(dbFile.path);
    rawDb.execute(
      "UPDATE _drift_schema_fingerprint SET value = 'stale-old-fingerprint'",
    );
    rawDb.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    expect(await db2.getMarketRegimeForDate(DateTime(2026, 11, 24)), isNull);
    await db2.close();
  });
}

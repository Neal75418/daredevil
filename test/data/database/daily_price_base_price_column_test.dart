// daily_price 補 base_price（交易所當天的平盤價）的 ALTER 升級路徑（2026-10-27）
//
// bump fingerprint 會 wipe 全部行情表，所以加欄走 beforeOpen 的 idempotent
// ALTER（先例：dividend_price_columns_migration_test）。這條測試模擬真實
// 升級：帶舊 schema＋資料的 DB 被新版開啟。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('daily_price_base_price');
    dbFile = File('${tempDir.path}/db.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<String> fingerprint(AppDatabase db) async =>
      (await db
              .customSelect('SELECT value FROM _drift_schema_fingerprint')
              .getSingle())
          .read<String>('value');

  test(
    '🚨 舊 DB 開啟後補 base_price 欄：既有列保留、base_price 為 null、fingerprint 不變',
    () async {
      final db1 = AppDatabase(NativeDatabase(dbFile));
      await db1.upsertStocks([
        StockMasterCompanion.insert(symbol: '9901', name: '甲', market: 'TWSE'),
      ]);
      await db1.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: DateTime(2026, 9, 16),
          close: const Value(2380.0),
          priceChange: const Value(0.0),
        ),
      ]);
      await db1.customStatement(
        'ALTER TABLE daily_price DROP COLUMN base_price',
      );
      final before = await fingerprint(db1);
      await db1.close();

      final db2 = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db2.close);
      final row = await db2.getLatestPrice('9901');
      expect(row!.close, 2380.0);
      expect(row.priceChange, 0.0);
      expect(row.basePrice, isNull);
      expect(await fingerprint(db2), before, reason: '加欄不 bump fingerprint');

      // 讀不到的欄位 drift 也回 null，要寫入再讀回才證明欄位真的補上了
      await db2.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: DateTime(2026, 9, 17),
          close: const Value(2425.0),
          basePrice: const Value(2380.0),
        ),
      ]);
      expect((await db2.getLatestPrice('9901'))!.basePrice, 2380.0);
    },
  );
}

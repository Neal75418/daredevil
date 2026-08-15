// 退役 schema 清理的迴歸測試(2026-08-15 全專案健檢)
//
// 背景:三張表(daily_recommendation / recommendation_validation /
// screening_strategy_table)零讀零寫、insider_holding 三欄 production
// 永遠 NULL(實測 3,936 列中非 NULL 列數 = 0)。已自 schema 宣告移除,
// 既有 DB 的殘留由 `_ensureRetiredSchemaDropped` 在 beforeOpen 清除。
//
// 沿 `_ensureDealerSelfNetColumn` 先例:**不 bump fingerprint**——指紋
// 變更會 wipe 全部非白名單表(59.7 萬列價格)。
//
// 上線前彩排(真實 production 副本,2026-08-15):DDL 0.03 秒、六項基準
// 指標逐項一致、integrity_check ok;完整 beforeOpen 走一遍後價格
// 597,539 列全數存活。本測試把該保證固化成迴歸守門。
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('retired_schema_test');
    dbFile = File('${tempDir.path}/retired.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// 模擬「退役前的既有 DB」:三張表 + insider 三欄都還在
  Future<void> buildLegacyDb() async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();

    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS daily_recommendation ('
      'date INTEGER NOT NULL, horizon TEXT NOT NULL, rank INTEGER NOT NULL, '
      'symbol TEXT NOT NULL, PRIMARY KEY (date, horizon, rank))',
    );
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS recommendation_validation ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, symbol TEXT NOT NULL)',
    );
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS screening_strategy_table ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
      'conditions_json TEXT NOT NULL)',
    );
    for (final col in const [
      'director_shares',
      'supervisor_shares',
      'manager_shares',
    ]) {
      await db.customStatement(
        'ALTER TABLE insider_holding ADD COLUMN $col REAL',
      );
    }

    // 使用者資料 + derived 資料各一份,驗證清理不波及
    await db
        .into(db.stockMaster)
        .insert(
          StockMasterCompanion.insert(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
          ),
        );
    await db
        .into(db.dailyPrice)
        .insert(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: DateTime(2026, 8, 14),
            close: const Value(2395.0),
          ),
        );
    await db
        .into(db.watchlist)
        .insert(WatchlistCompanion.insert(symbol: '2330'));
    await db
        .into(db.insiderHolding)
        .insert(
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: DateTime(2026, 8, 14),
            insiderRatio: const Value(12.3),
          ),
        );
    await db.close();
  }

  Future<Set<String>> tableNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<Set<String>> insiderColumns(AppDatabase db) async {
    final rows = await db
        .customSelect("PRAGMA table_info('insider_holding')")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  test('🚨 既有 DB 重開:三張退役表逐一清除', () async {
    await buildLegacyDb();

    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    final tables = await tableNames(db);

    // 逐一斷言——任一條 DROP 被拿掉都會紅(mutation 防護)
    expect(tables, isNot(contains('daily_recommendation')));
    expect(tables, isNot(contains('recommendation_validation')));
    expect(tables, isNot(contains('screening_strategy_table')));
    await db.close();
  });

  test('🚨 insider_holding 三個永遠 NULL 的欄位逐一清除,真實欄位留存', () async {
    await buildLegacyDb();

    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    final cols = await insiderColumns(db);

    expect(cols, isNot(contains('director_shares')));
    expect(cols, isNot(contains('supervisor_shares')));
    expect(cols, isNot(contains('manager_shares')));
    expect(
      cols,
      containsAll({
        'symbol',
        'date',
        'insider_ratio',
        'pledge_ratio',
        'shares_issued',
      }),
      reason: '有真實寫入的欄位不得被誤刪',
    );
    await db.close();
  });

  test('🚨 清理不得損失任何資料(fingerprint 未 bump → 不 wipe)', () async {
    await buildLegacyDb();

    final db = AppDatabase(NativeDatabase(dbFile));
    Future<int> count(String t) async =>
        (await db.customSelect('SELECT COUNT(*) c FROM $t').getSingle())
            .read<int>('c');

    expect(await count('daily_price'), 1, reason: 'derived 資料不得被 wipe');
    expect(await count('watchlist'), 1, reason: '使用者資料不得被 wipe');
    expect(await count('stock_master'), 1);
    expect(await count('insider_holding'), 1, reason: 'DROP COLUMN 保留列');

    final integrity = await db
        .customSelect('PRAGMA integrity_check')
        .getSingle();
    expect(integrity.data.values.first, 'ok');
    await db.close();
  });

  test('冪等:連開三次不炸(清理路徑每次啟動都會跑)', () async {
    await buildLegacyDb();
    for (var i = 0; i < 3; i++) {
      final db = AppDatabase(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
      expect(await tableNames(db), isNot(contains('daily_recommendation')));
      await db.close();
    }
  });
}

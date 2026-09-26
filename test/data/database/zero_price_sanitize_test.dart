import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

/// 歷史零價列的啟動清理(2026-07-30)。
///
/// TWSE STOCK_DAY_ALL 對「無成交」用 `0.00` 表達,parser 修正
/// (TwParseUtils.parsePrice)前已有 41 列 close=0 落庫(1472、1213 等
/// 停牌/極低流動股)。0 會污染 52 週窗(min 永遠 0 → 52週新低規則對
/// 該股靜默失效)與漲跌顯示(-100%)。beforeOpen 冪等收斂:close=0 的
/// 列四個價格欄一律 NULL 化(volume 不動,0 量合法)。
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zero_price_test');
    dbFile = File('${tempDir.path}/zp_test.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('beforeOpen 把 close=0 的列價格欄 NULL 化,正常列不動', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    for (final s in ['1472', '2330']) {
      await db1
          .into(db1.stockMaster)
          .insert(
            StockMasterCompanion.insert(
              symbol: s,
              name: '測試$s',
              market: 'TWSE',
            ),
          );
    }
    await db1
        .into(db1.dailyPrice)
        .insert(
          DailyPriceCompanion.insert(
            symbol: '1472',
            date: DateTime(2026, 7, 30),
            open: const Value(0),
            high: const Value(0),
            low: const Value(0),
            close: const Value(0),
            volume: const Value(17),
          ),
        );
    await db1
        .into(db1.dailyPrice)
        .insert(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: DateTime(2026, 7, 30),
            open: const Value(2205),
            high: const Value(2260),
            low: const Value(2190),
            close: const Value(2205),
            volume: const Value(51372177),
          ),
        );
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    final rows = await db2.select(db2.dailyPrice).get(); // 觸發 beforeOpen
    final r1472 = rows.firstWhere((r) => r.symbol == '1472');
    expect(r1472.close, isNull);
    expect(r1472.open, isNull);
    expect(r1472.high, isNull);
    expect(r1472.low, isNull);
    expect(r1472.volume, 17, reason: 'volume 不清(0 量合法、17 更是真值)');
    final r2330 = rows.firstWhere((r) => r.symbol == '2330');
    expect(r2330.close, 2205);
    expect(r2330.open, 2205);
  });

  test('sanitize 走 partial index,不再每次啟動全表掃描(2026-08-01 複審)', () async {
    // daily_price 已 3.5M+ 列且逐日成長,close 無索引時這條 UPDATE 每次
    // beforeOpen 都全表掃描——同檔其餘 _ensure* 步驟全都有「已完成則
    // no-op」防護,唯獨這步沒有。partial index 讓穩態(零命中)時的
    // 啟動成本趨近 O(1),又保留「持續兜底」語意(新混入的 0 仍會被清)。
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);
    await db.select(db.dailyPrice).get(); // 觸發 beforeOpen

    final idx = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name='idx_daily_price_zero_close'",
        )
        .get();
    expect(idx, hasLength(1), reason: 'partial index 必須存在');

    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN UPDATE daily_price SET open=NULL, high=NULL, '
          'low=NULL, close=NULL WHERE close = 0',
        )
        .get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' | ');
    expect(
      detail,
      contains('idx_daily_price_zero_close'),
      reason: 'UPDATE 必須走 partial index 而非全表掃描,實際計畫: $detail',
    );
  });
}

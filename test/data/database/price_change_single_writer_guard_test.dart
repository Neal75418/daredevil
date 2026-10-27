// 守門：寫 daily_price 的地方只能是 price_dao 的 insertPrices（唯一的新增／
// 覆寫入口，帶 price_change 的 upsert 規則）、applyBasePrices 與
// nullifyPriceChangeWithoutClose（修復工具只改兩欄）、cleanupInvalidStockCodes
// 的 DELETE，以及 app_database 的 _ensureZeroPriceSanitized。
//
// 除權息漲跌修正（2026-10）把 price_change 的語意定成「收盤 − 平盤價」，
// 規則集中在 insertPrices；若日後有人在別處 `into(dailyPrice)`、
// `b.insert(dailyPrice` 或寫 raw `UPDATE daily_price`，補正過的值會被洗掉
// 而且沒有任何測試會紅——這裡會。
//
// 兩條斷言互為 sanity floor：掃描器失效時「允許清單命中」會先變空而非套套邏輯。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = [
    for (final dir in ['lib', 'tool'])
      ...Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.endsWith('.drift.dart') &&
                !f.path.endsWith('.g.dart'),
          ),
  ];

  /// (檔案結尾, 允許的函式名)
  const allowed = {
    'lib/data/database/dao/price_dao.dart': {
      'insertPrices',
      'applyBasePrices',
      'nullifyPriceChangeWithoutClose',
      'cleanupInvalidStockCodes',
    },
    'lib/data/database/app_database.dart': {'_ensureZeroPriceSanitized'},
  };

  // (a) Drift API 的寫入動詞：`into(dailyPrice)`／`update(dailyPrice)`／
  //     `delete(dailyPrice)`、batch 的 `x.insert…(dailyPrice`、
  //     TableStatements 的 `dailyPrice.insertOne(`／`.update()`／
  //     `.replaceOne(`／`.deleteWhere(`，以及 managers；(b) raw SQL（含
  //     `OR IGNORE`、加引號的識別字、`${dailyPrice.actualTableName}`）
  final driftWrite = RegExp(
    r'\b(?:into|update|delete)\(\s*(?:\w+\.)*dailyPrice\b'
    r'|\b\w+\.(?:insert\w*|update|delete\w*|replace\w*)\(\s*(?:\w+\.)*dailyPrice\b'
    r'|\bdailyPrice\s*\.\s*(?:insert\w*|update|delete\w*|replace\w*)\('
    r'|\bmanagers\s*\.\s*dailyPrice\b',
  );
  final rawWrite = RegExp(
    r'\b(?:INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM|REPLACE\s+INTO)'
    r'\s+(?:["`\[]?daily_price\b|\$\{\s*dailyPrice\b)',
    caseSensitive: false,
  );
  // 函式標頭：static 可選、回傳型別（primitive 或大寫開頭的型別，含泛型與
  // ?）、名稱、左括號。小寫關鍵字（return／await／final）不會被當成型別。
  final fnHeader = RegExp(
    r'^\s*(?:static\s+)?(?:void|int|bool|double|num|[A-Z_$][\w$]*(?:<.*>)?\??)\s+(\w+)\s*\(',
    multiLine: true,
  );

  test('sanity：已知的違規寫法都要命中、非寫入不誤判', () {
    const writes = [
      'db.into(dailyPrice).insertOnConflictUpdate(e)',
      'await into(db.dailyPrice).insert(e)',
      'update(dailyPrice)..where((t) => t.symbol.equals(s))',
      'delete(dailyPrice).go()',
      'b.insert(\n  dailyPrice, e)',
      'batch.replace(dailyPrice, e)',
      'b.insertAllOnConflictUpdate(dailyPrice, rows)',
      'b.deleteWhere(dailyPrice, (t) => t.symbol.equals(s))',
      'db.dailyPrice.insertOnConflictUpdate(e)',
      'dailyPrice.insertOne(e)',
      'dailyPrice.update().write(c)',
      'dailyPrice.replaceOne(e)',
      'dailyPrice.deleteWhere((t) => t.symbol.equals(s))',
      'managers.dailyPrice.create((o) => o(symbol: s, date: d))',
      "customStatement('UPDATE daily_price SET price_change = 0')",
      "'INSERT OR REPLACE INTO daily_price VALUES (?)'",
      "'insert into daily_price values (?)'",
      "'UPDATE OR IGNORE daily_price SET close = 1'",
      "'UPDATE \"daily_price\" SET close = 1'",
      "'DELETE FROM daily_price WHERE 1'",
      r"'UPDATE ${dailyPrice.actualTableName} SET close = 1'",
    ];
    for (final s in writes) {
      expect(
        driftWrite.hasMatch(s) || rawWrite.hasMatch(s),
        isTrue,
        reason: '漏掉: $s',
      );
    }
    const nonWrites = [
      'select(dailyPrice)',
      'readsFrom: {dailyPrice}',
      'updates: {dailyPrice}',
      'db.insertPrices(entries)',
      "'SELECT COUNT(*) FROM daily_price'",
      "'CREATE INDEX IF NOT EXISTS i ON daily_price (close)'",
      "'ALTER TABLE daily_price ADD COLUMN base_price REAL'",
    ];
    for (final s in nonWrites) {
      expect(
        driftWrite.hasMatch(s) || rawWrite.hasMatch(s),
        isFalse,
        reason: '誤判: $s',
      );
    }
  });

  String enclosingFunction(String src, int offset) {
    String? name;
    for (final m in fnHeader.allMatches(src)) {
      if (m.start > offset) break;
      name = m.group(1);
    }
    return name ?? '(top-level)';
  }

  test('🚨 寫 daily_price 只能經唯一入口', () {
    expect(files.length, greaterThan(100), reason: 'sanity floor：掃描器要真的看到 lib');

    final violations = <String>[];
    final allowedHits = <String>{};
    for (final f in files) {
      final src = f.readAsStringSync();
      final matches = [
        ...driftWrite.allMatches(src),
        ...rawWrite.allMatches(src),
      ];
      for (final m in matches) {
        final fn = enclosingFunction(src, m.start);
        final key = allowed.keys.firstWhere(
          (k) => f.path.endsWith(k),
          orElse: () => '',
        );
        if (key.isNotEmpty && allowed[key]!.contains(fn)) {
          allowedHits.add(fn);
        } else {
          violations.add('${f.path}@${m.start} in $fn: ${m.group(0)}');
        }
      }
    }
    expect(violations, isEmpty, reason: '寫 daily_price 只能經唯一入口');
    expect(
      allowedHits,
      containsAll([
        'insertPrices',
        'applyBasePrices',
        'nullifyPriceChangeWithoutClose',
        'cleanupInvalidStockCodes',
        '_ensureZeroPriceSanitized',
      ]),
      reason: '掃描器失效時這裡先紅',
    );
  });
}

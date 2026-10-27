// insertPrices 的 upsert 規則（除權息漲跌修正 spec 第 2 節）
//
// 由 insert-or-replace 改成依 (symbol, date) upsert：平盤價「有帶就用新的、
// 否則保留舊的」；price_change 依序：
//   0. 新收盤 null → null
//   1. 合併後的平盤價非 null → ROUND(收盤 − 平盤價, 2)
//   2. 否則 entry 有帶漲跌欄（含明確空值）→ 用它
//   3. 否則（FinMind 這類沒帶漲跌欄）→ 收盤沒變保留舊漲跌，變了存 null
// insert 分支（沒有舊列）同樣套規則——SQLite 的 ON CONFLICT DO UPDATE 只在
// 衝突時生效，15:30 第一次寫入走的正是 insert 分支。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final d = DateContext.normalize(DateTime(2026, 9, 16));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9901', name: '甲', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9902', name: '乙', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  DailyPriceCompanion row({
    String symbol = '9901',
    double? close,
    Value<double?> change = const Value.absent(),
    double? base,
  }) => DailyPriceCompanion.insert(
    symbol: symbol,
    date: d,
    close: Value(close),
    priceChange: change,
    basePrice: base == null ? const Value.absent() : Value(base),
  );

  Future<DailyPriceEntry> get([String symbol = '9901']) async =>
      (await db.getLatestPrice(symbol))!;

  group('insert 分支（空表）', () {
    test('第 0 條：收盤 null → 漲跌 null，平盤價照存', () async {
      await db.insertPrices([
        row(close: null, change: const Value(0.0), base: 18.35),
      ]);
      final r = await get();
      expect(r.priceChange, isNull);
      expect(r.basePrice, 18.35);
    });

    test('第 1 條：有平盤價 → 收盤 − 平盤價（STOCK_DAY_ALL 給的 0 被蓋掉）', () async {
      await db.insertPrices([
        row(close: 2380, change: const Value(0.0), base: 2385),
      ]);
      expect((await get()).priceChange, -5.0);
    });

    test('第 1 條四捨五入到 0.01', () async {
      await db.insertPrices([row(close: 32.12, base: 32.44)]);
      expect((await get()).priceChange, -0.32);
    });

    test('第 2 條：沒平盤價、帶明確空值 → null', () async {
      await db.insertPrices([row(close: 10, change: const Value(null))]);
      expect((await get()).priceChange, isNull);
    });

    test('第 2 條：沒平盤價、帶數字 → 用它', () async {
      await db.insertPrices([row(close: 10, change: const Value(0.5))]);
      expect((await get()).priceChange, 0.5);
    });

    test('第 3 條：沒平盤價、沒帶漲跌欄、沒舊列 → null', () async {
      await db.insertPrices([row(close: 10)]);
      expect((await get()).priceChange, isNull);
    });
  });

  group('update 分支（已有列）', () {
    test('平盤價「有帶就用新的、否則保留舊的」；兩種 upsert 都套第 1 條', () async {
      await db.insertPrices([row(close: 10, base: 9.5)]);
      await db.insertPrices([row(close: 10.5)]);
      var r = await get();
      expect(r.basePrice, 9.5);
      expect(
        r.priceChange,
        1.0,
        reason: '沒帶漲跌欄那種 upsert 也套第 1 條（漏了會走第 3 條變 null）',
      );
      await db.insertPrices([row(close: 10.5, base: 9.6)]);
      r = await get();
      expect(r.basePrice, 9.6);
      expect(
        r.priceChange,
        0.9,
        reason: 'ROUND：10.5 − 9.6 在 IEEE 是 0.9000000000000004',
      );
    });

    test('🚨 覆寫時保留平盤價、用新收盤重算（21:30 重寫）', () async {
      await db.insertPrices([
        row(close: 2380, change: const Value(0.0), base: 2385),
      ]);
      await db.insertPrices([row(close: 2385, change: const Value(0.0))]);
      final r = await get();
      expect(r.priceChange, 0.0);
      expect(r.basePrice, 2385);
    });

    test('🚨 有平盤價時，明確空值（STOCK_DAY 的 X0.00）也被第 1 條蓋掉', () async {
      await db.insertPrices([row(close: 2380, base: 2385)]);
      await db.insertPrices([row(close: 2380, change: const Value(null))]);
      expect((await get()).priceChange, -5.0);
    });

    test('沒平盤價、明確空值 → 寫空值、不保留舊的 0', () async {
      await db.insertPrices([row(close: 10, change: const Value(0.0))]);
      await db.insertPrices([row(close: 10, change: const Value(null))]);
      expect((await get()).priceChange, isNull);
    });

    test(
      '🚨 第 0 條（沒平盤價）：舊列已是收盤 null／漲跌 0（本次修正前的既有資料），不帶漲跌欄的覆寫 → 漲跌 null',
      () async {
        // 帶漲跌欄的寫入在 Dart 端（_withInsertPriceChange）就已把收盤 null 的漲跌設成 null；
        // SQL 第 0 條擋的是這個情境：第 3 條的 `old.close IS excluded.close` 對 NULL IS NULL 為真，會把舊的 0 留下來。
        // 目前 lib 裡沒有寫入端會送「不帶漲跌欄＋收盤 null」（不帶漲跌欄的只有 FinMind 兩條路徑，
        // FinMindDailyPrice.fromJson 遇收盤 null／0 會拋），這條是給日後新寫入端的防線
        await db.insertPrices([row(close: 10, change: const Value(0.0))]);
        await db.customStatement(
          'UPDATE daily_price SET close = NULL',
        ); // 模擬修正前存下的「未成交、漲跌 0」列
        await db.insertPrices([row(close: null)]);
        expect((await get()).priceChange, isNull);
      },
    );

    test('FinMind（沒帶漲跌欄）收盤沒變 → 保留舊漲跌', () async {
      await db.insertPrices([row(close: 10, change: const Value(0.5))]);
      await db.insertPrices([row(close: 10)]);
      expect((await get()).priceChange, 0.5);
    });

    test('FinMind 收盤變了 → 空值', () async {
      await db.insertPrices([row(close: 10, change: const Value(0.5))]);
      await db.insertPrices([row(close: 10.5)]);
      expect((await get()).priceChange, isNull);
    });

    test('第 0 條優先：有平盤價但新收盤 null → 漲跌 null、平盤價保留', () async {
      await db.insertPrices([row(close: 10, base: 9.5)]);
      await db.insertPrices([row(close: null, change: const Value(0.0))]);
      final r = await get();
      expect(r.priceChange, isNull);
      expect(r.basePrice, 9.5);
    });

    test('開高低收、成交量用新值', () async {
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: d,
          open: const Value(1),
          high: const Value(2),
          low: const Value(0.5),
          close: const Value(1.5),
          volume: const Value(100),
        ),
      ]);
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: d,
          open: const Value(3),
          high: const Value(4),
          low: const Value(2.5),
          close: const Value(3.5),
          volume: const Value(200),
        ),
      ]);
      final r = await get();
      expect((r.open, r.high, r.low, r.close, r.volume), (3, 4, 2.5, 3.5, 200));
    });

    test('同一批混合 present／absent 各照各自規則', () async {
      await db.insertPrices([
        row(symbol: '9901', close: 10, change: const Value(0.5)),
        row(symbol: '9902', close: 10, change: const Value(0.5)),
      ]);
      await db.insertPrices([
        row(symbol: '9901', close: 10, change: const Value(null)), // 第 2 條
        row(symbol: '9902', close: 10), // 第 3 條
      ]);
      expect((await get('9901')).priceChange, isNull);
      expect((await get('9902')).priceChange, 0.5);
    });
  });
}

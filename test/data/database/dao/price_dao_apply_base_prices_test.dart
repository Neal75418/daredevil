// applyBasePrices／nullifyPriceChangeWithoutClose／countMissingBasePrice
// （除權息漲跌修正 spec 第 3、4 節；修復工具與市場日寫入的 N 判斷用）
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final d = DateContext.normalize(DateTime(2026, 9, 16));
  final d2 = DateContext.normalize(DateTime(2026, 9, 17));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9901', name: '甲', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9902', name: '乙', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9903', name: '丙', market: 'TPEx'),
    ]);
  });

  tearDown(() => db.close());

  DailyPriceCompanion row(
    String symbol,
    DateTime date, {
    double? close,
    double? change,
  }) => DailyPriceCompanion.insert(
    symbol: symbol,
    date: date,
    close: Value(close),
    priceChange: Value(change),
  );

  Future<DailyPriceEntry?> get(String symbol, DateTime date) async =>
      (await db.getPriceHistory(
        symbol,
        startDate: date,
        endDate: date,
      )).firstOrNull;

  group('applyBasePrices', () {
    test('只更新已存在的列；收盤 null 的列漲跌 null；不存在的不插入', () async {
      await db.insertPrices([
        row('9901', d, close: 2380, change: 0.0),
        row('9902', d, close: null, change: 0.0),
      ]);
      final n = await db.applyBasePrices([
        (symbol: '9901', date: d, basePrice: 2385),
        (symbol: '9902', date: d, basePrice: 10),
        (symbol: '9903', date: d, basePrice: 1),
      ]);
      expect(n, 2);
      final a = (await get('9901', d))!;
      expect((a.priceChange, a.basePrice), (-5.0, 2385.0));
      final b = (await get('9902', d))!;
      expect((b.priceChange, b.basePrice), (null, 10.0));
      expect(await get('9903', d), isNull);
    });

    test('四捨五入到 0.01', () async {
      await db.insertPrices([row('9901', d, close: 32.12)]);
      await db.applyBasePrices([(symbol: '9901', date: d, basePrice: 32.44)]);
      expect((await get('9901', d))!.priceChange, -0.32);
    });

    test('冪等：跑兩次結果相同', () async {
      await db.insertPrices([row('9901', d, close: 2380, change: 0.0)]);
      final rows = [(symbol: '9901', date: d, basePrice: 2385.0)];
      await db.applyBasePrices(rows);
      await db.applyBasePrices(rows);
      expect((await get('9901', d))!.priceChange, -5.0);
    });

    test('其他欄與其他日子不動', () async {
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: d,
          open: const Value(1),
          high: const Value(2),
          low: const Value(0.5),
          close: const Value(1.5),
          volume: const Value(100),
          priceChange: const Value(0.0),
        ),
        row('9901', d2, close: 3, change: 0.0),
      ]);
      await db.applyBasePrices([(symbol: '9901', date: d, basePrice: 1.0)]);
      final a = (await get('9901', d))!;
      expect((a.open, a.high, a.low, a.volume), (1, 2, 0.5, 100));
      expect((await get('9901', d2))!.priceChange, 0.0);
    });
  });

  group('nullifyPriceChangeWithoutClose', () {
    test('只動該日、該市場、收盤 null 的列', () async {
      await db.insertPrices([
        row('9901', d, close: null, change: 0.0),
        row('9902', d, close: 10, change: 0.0),
        row('9903', d, close: null, change: 0.0),
        row('9901', d2, close: null, change: 0.0),
      ]);
      // 先用 raw SQL 把 9901 的 price_change 塞回 0（insertPrices 第 0 條已會
      // 把它寫成 null，這裡要模擬舊資料）
      await db.customStatement(
        'UPDATE daily_price SET price_change = 0 WHERE close IS NULL',
      );
      final n = await db.nullifyPriceChangeWithoutClose(
        date: d,
        market: 'TWSE',
      );
      expect(n, 1);
      expect((await get('9901', d))!.priceChange, isNull);
      expect((await get('9902', d))!.priceChange, 0.0);
      expect((await get('9903', d))!.priceChange, 0.0, reason: '上櫃不動');
      expect((await get('9901', d2))!.priceChange, 0.0, reason: '別天不動');
    });
  });

  group('countMissingBasePrice', () {
    test('symbols 為空回 0；只數 base_price IS NULL 的列', () async {
      await db.insertPrices([
        row('9901', d, close: 10),
        DailyPriceCompanion.insert(
          symbol: '9902',
          date: d,
          close: const Value(10),
          basePrice: const Value(9.5),
        ),
        row('9903', d, close: 10),
        row('9901', d2, close: 10),
      ]);
      expect(await db.countMissingBasePrice(date: d, symbols: {}), 0);
      expect(
        await db.countMissingBasePrice(
          date: d,
          symbols: {'9901', '9902', '9903'},
        ),
        2,
      );
      expect(await db.countMissingBasePrice(date: d, symbols: {'9902'}), 0);
      expect(
        await db.countMissingBasePrice(date: d, symbols: {'9999'}),
        0,
        reason: '沒有列的代號不算缺',
      );
    });
  });
}

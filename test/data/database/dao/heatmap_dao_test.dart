import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/heatmap_dao.dart';

final _d1006 = DateContext.normalize(DateTime(2026, 10, 6));
final _d1007 = DateContext.normalize(DateTime(2026, 10, 7));
final _d1008 = DateContext.normalize(DateTime(2026, 10, 8));

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902', '9903', '9904'])
        StockMasterCompanion.insert(
          symbol: s,
          name: '測試$s',
          market: MarketCode.twse,
          industry: const Value('測試業'),
        ),
      for (final s in ['9911', '9912'])
        StockMasterCompanion.insert(
          symbol: s,
          name: '測試$s',
          market: MarketCode.tpex,
          industry: const Value('測試業'),
        ),
      StockMasterCompanion.insert(
        symbol: '9921',
        name: '測試9921',
        market: MarketCode.twse,
        isActive: const Value(false),
      ),
    ]);
  });

  tearDown(() => db.close());

  Future<void> price(
    String symbol,
    DateTime date, {
    double? close,
    double? change,
  }) => db
      .into(db.dailyPrice)
      .insert(
        DailyPriceCompanion.insert(
          symbol: symbol,
          date: date,
          close: Value(close),
          priceChange: Value(change),
        ),
      );

  Future<void> update(
    String symbol,
    DateTime date,
    DailyPriceCompanion companion,
  ) =>
      (db.update(db.dailyPrice)
            ..where((t) => t.symbol.equals(symbol) & t.date.equals(date)))
          .write(companion);

  Future<void> fetch(
    String market,
    DateTime date, {
    String dataset = 'prices',
  }) => db.upsertMarketDayFetch(
    dataset: dataset,
    market: market,
    date: date,
    fetchedAt: DateTime(2026, 10, 8, 9),
    rowCount: 1000,
  );

  group('正式資料日', () {
    test('兩個市場各自判斷', () async {
      await fetch(MarketCode.twse, _d1006);
      await fetch(MarketCode.twse, _d1007);
      await fetch(MarketCode.tpex, _d1006);
      expect(await db.getLatestFormalPriceDate(MarketCode.twse), _d1007);
      expect(await db.getLatestFormalPriceDate(MarketCode.tpex), _d1006);
    });

    test('只寫入一部分股票的日子不算正式資料', () async {
      await fetch(MarketCode.tpex, _d1006);
      await price('9911', _d1007, close: 50, change: 1);
      await price('9912', _d1007, close: 60, change: 1);
      expect(await db.getLatestFormalPriceDate(MarketCode.tpex), _d1006);
    });

    test('其他資料集的紀錄不算', () async {
      await fetch(MarketCode.twse, _d1007);
      await fetch(MarketCode.twse, _d1008, dataset: 'institutional');
      expect(await db.getLatestFormalPriceDate(MarketCode.twse), _d1007);
    });

    test('沒有任何紀錄回 null', () async {
      expect(await db.getLatestFormalPriceDate(MarketCode.twse), isNull);
      expect(await db.getHeatmapFingerprint(MarketCode.twse), isNull);
    });
  });

  group('價格列', () {
    test('排除下市、他市場、收盤空值', () async {
      await price('9901', _d1007, close: 105, change: 5);
      await price('9902', _d1007, close: null, change: null);
      await price('9921', _d1007, close: 10, change: 1);
      await price('9911', _d1007, close: 50, change: 1);
      final rows = await db.getHeatmapPriceRows(MarketCode.twse, _d1007);
      expect(rows.map((r) => r.symbol), ['9901']);
      final r = rows.single;
      expect(r.name, '測試9901');
      expect(r.industry, '測試業');
      expect(r.close, 105);
      expect(r.priceChange, 5);
    });

    test('只回指定那一天', () async {
      await price('9901', _d1006, close: 100, change: 1);
      await price('9901', _d1007, close: 105, change: 5);
      final rows = await db.getHeatmapPriceRows(MarketCode.twse, _d1006);
      expect(rows.single.close, 100);
    });

    test('漲跌空值照回、不退回前一筆收盤', () async {
      await price('9901', _d1006, close: 100, change: 1);
      await price('9901', _d1007, close: 105, change: null);
      final rows = await db.getHeatmapPriceRows(MarketCode.twse, _d1007);
      expect(rows.single.priceChange, isNull);
    });
  });

  group('內容指紋', () {
    // 同一市場同一天另有非空漲跌與非空收盤，合計不會從 0 變空值
    setUp(() async {
      await fetch(MarketCode.twse, _d1007);
      await price('9901', _d1007, close: 105, change: 5);
      await price('9902', _d1007, close: 50, change: 0);
      await price('9903', _d1007, close: null, change: null);
    });

    Future<HeatmapFingerprint> fp() async =>
        (await db.getHeatmapFingerprint(MarketCode.twse))!;

    test('四個成分與日期', () async {
      final f = await fp();
      expect(f.date, _d1007);
      expect(f.rows, 3);
      expect(f.changeRows, 2);
      expect(f.changeSum, 5);
      expect(f.closeSum, 155);
    });

    test('沒有改動時指紋相等', () async {
      expect(await fp(), await fp());
    });

    test('新增一列收盤與漲跌都空的：只有 rows 變', () async {
      final before = await fp();
      await price('9904', _d1007, close: null, change: null);
      final after = await fp();
      expect(after.rows, before.rows + 1);
      expect(
        (after.date, after.changeRows, after.changeSum, after.closeSum),
        (before.date, before.changeRows, before.changeSum, before.closeSum),
      );
    });

    test('0 改成空值：只有 changeRows 變', () async {
      final before = await fp();
      await update(
        '9902',
        _d1007,
        const DailyPriceCompanion(priceChange: Value(null)),
      );
      final after = await fp();
      expect(after.changeRows, before.changeRows - 1);
      expect(
        (after.date, after.rows, after.changeSum, after.closeSum),
        (before.date, before.rows, before.changeSum, before.closeSum),
      );
    });

    test('非空漲跌改成另一個非空值：只有 changeSum 變', () async {
      final before = await fp();
      await update(
        '9901',
        _d1007,
        const DailyPriceCompanion(priceChange: Value(6)),
      );
      final after = await fp();
      expect(after.changeSum, 6);
      expect(
        (after.date, after.rows, after.changeRows, after.closeSum),
        (before.date, before.rows, before.changeRows, before.closeSum),
      );
    });

    test('收盤由空值變有值：只有 closeSum 變', () async {
      final before = await fp();
      await update('9903', _d1007, const DailyPriceCompanion(close: Value(30)));
      final after = await fp();
      expect(after.closeSum, 185);
      expect(
        (after.date, after.rows, after.changeRows, after.changeSum),
        (before.date, before.rows, before.changeRows, before.changeSum),
      );
    });

    test('兩個市場分開：改上櫃的一列，上市指紋不變', () async {
      await fetch(MarketCode.tpex, _d1007);
      await price('9911', _d1007, close: 50, change: 1);
      final twse = await fp();
      final tpexBefore = await db.getHeatmapFingerprint(MarketCode.tpex);
      await update(
        '9911',
        _d1007,
        const DailyPriceCompanion(priceChange: Value(2)),
      );
      expect(await fp(), twse);
      expect(
        await db.getHeatmapFingerprint(MarketCode.tpex),
        isNot(tpexBefore),
      );
    });

    test('正式資料日之後的列不算進指紋', () async {
      final before = await fp();
      // 10/8 沒有 market_day_fetch：逐檔回補寫進的列
      await price('9904', _d1008, close: 1, change: 1);
      expect(await fp(), before);
    });

    test('最新資料日改變時指紋的日期跟著變', () async {
      await fetch(MarketCode.twse, _d1008);
      final f = await fp();
      expect(f.date, _d1008);
      expect(f.rows, 0);
    });
  });
}

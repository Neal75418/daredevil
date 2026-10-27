// 修復工具挑日：價格表裡有上市列、但沒有任何一列有平盤價的日子
// （除權息漲跌修正 spec 第 4 節；這個條件同時是「做過沒」的判斷）
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final d15 = DateContext.normalize(DateTime(2026, 9, 15));
  final d16 = DateContext.normalize(DateTime(2026, 9, 16));
  final d17 = DateContext.normalize(DateTime(2026, 9, 17));
  final d18 = DateContext.normalize(DateTime(2026, 9, 18));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9911', name: '9911', market: 'TPEx'),
    ]);
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '9901',
        date: d15,
        close: const Value(10),
      ),
      DailyPriceCompanion.insert(
        symbol: '9901',
        date: d16,
        close: const Value(10),
      ),
      DailyPriceCompanion.insert(
        symbol: '9902',
        date: d16,
        close: const Value(10),
      ),
      DailyPriceCompanion.insert(
        symbol: '9901',
        date: d17,
        close: const Value(10),
        basePrice: const Value(9.5),
      ),
      DailyPriceCompanion.insert(
        symbol: '9902',
        date: d17,
        close: const Value(10),
      ),
      DailyPriceCompanion.insert(
        symbol: '9911',
        date: d18,
        close: const Value(10),
      ),
    ]);
  });

  tearDown(() => db.close());

  test('只挑上市、整天沒有平盤價的日子，舊→新', () async {
    expect(await db.getTwseDaysWithoutBasePrice(), [d15, d16]);
  });

  test('有任何一列有平盤價的日子不挑（9/17）；只有上櫃列的日子不挑（9/18）', () async {
    final days = await db.getTwseDaysWithoutBasePrice();
    expect(days, isNot(contains(d17)));
    expect(days, isNot(contains(d18)));
  });

  test('🚨 「做過沒」是比例不是「有任何一列」：轉市場列被上櫃那一輪寫了平盤價，那天仍要挑', () async {
    // 9/18 三列上市：9901、9902 沒平盤價，9904（轉市場列）有 → 1/3 < 門檻，仍挑
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9904', name: '9904', market: 'TWSE'),
    ]);
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '9901',
        date: d18,
        close: const Value(10),
      ),
      DailyPriceCompanion.insert(
        symbol: '9902',
        date: d18,
        close: const Value(10),
      ),
      DailyPriceCompanion.insert(
        symbol: '9904',
        date: d18,
        close: const Value(41.45),
        basePrice: const Value(40),
      ),
    ]);
    expect(await db.getTwseDaysWithoutBasePrice(), [d15, d16, d18]);
  });

  test('from／to 範圍', () async {
    expect(await db.getTwseDaysWithoutBasePrice(from: d16), [d16]);
    expect(await db.getTwseDaysWithoutBasePrice(to: d15), [d15]);
    expect(await db.getTwseDaysWithoutBasePrice(from: d17), isEmpty);
  });
}

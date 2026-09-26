import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final day = DateTime(2026, 9, 24);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
    ]);
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '2330',
        date: day,
        dayTradingRatio: const Value(50),
        tradeVolume: const Value(500),
      ),
      DayTradingCompanion.insert(
        symbol: '2317',
        date: day,
        dayTradingRatio: const Value(40),
        tradeVolume: const Value(400),
      ),
    ]);
  });

  tearDown(() => db.close());

  Future<double?> ratio(String s) async =>
      (await db.getDayTradingHistory(s, startDate: day)).single.dayTradingRatio;

  test('成交量被更正後重算比例', () async {
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: day,
        volume: const Value(2000),
      ),
    ]);
    final n = await db.recomputeDayTradingRatios(day: day, symbols: {'2330'});
    expect(n, 1);
    expect(await ratio('2330'), 25.0);
  });

  test('分母缺失時保留原比例，不改寫成 0', () async {
    final n = await db.recomputeDayTradingRatios(day: day, symbols: {'2317'});
    expect(n, 0);
    expect(await ratio('2317'), 40.0);
  });

  test('只動指定代號', () async {
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: day,
        volume: const Value(2000),
      ),
      DailyPriceCompanion.insert(
        symbol: '2317',
        date: day,
        volume: const Value(4000),
      ),
    ]);
    await db.recomputeDayTradingRatios(day: day, symbols: {'2330'});
    expect(await ratio('2317'), 40.0);
  });

  test('價格列是同日變體時間戳也對得上（範圍查詢）', () async {
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: DateTime(2026, 9, 24, 8),
        volume: const Value(2000),
      ),
    ]);
    await db.recomputeDayTradingRatios(day: day, symbols: {'2330'});
    // 原比例 50；對上變體時間戳的分母 2000 才會變 25（用精確相等查詢會對不上而保留 50）
    expect(await ratio('2330'), 25.0);
  });
}

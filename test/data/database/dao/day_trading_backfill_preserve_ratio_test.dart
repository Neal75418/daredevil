// 回補不得洗掉既有比例
//
// insertDayTradingData 用 InsertMode.insertOrReplace——**整列覆寫**。歷史回補
// 只有原始量值（比例的分母來自價格表，由每日路徑計算），若直接 insert，
// 同一天既有的 dayTradingRatio 會被寫成 NULL。
//
// 2026-08-23 彩排實測：回補 3 檔就把 8/21 兩筆已算好的比例清掉。223 檔規模
// 下會洗掉一大片，而且 day_trading_ratio 是 DAY_TRADING_HIGH/EXTREME 唯一的
// 輸入——比例變 NULL 等於那些股票當天的當沖訊號消失，且筆數看起來正常。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final day = DateTime(2026, 8, 21);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '6811', name: 'X', market: 'TPEx'),
    ]);
    // 每日路徑已寫入含比例的一列
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '6811',
        date: day,
        buyVolume: const Value(100),
        sellVolume: const Value(90),
        dayTradingRatio: const Value(42.5),
        tradeVolume: const Value(7000),
      ),
    ]);
  });

  tearDown(() async => db.close());

  Future<double?> ratio() async {
    final rows = await db.getDayTradingHistory(
      '6811',
      startDate: day,
      endDate: day,
    );
    return rows.single.dayTradingRatio;
  }

  test('🚨 回補寫入同一天，不得把既有比例洗成 NULL', () async {
    await db.upsertDayTradingPreservingRatio([
      DayTradingCompanion.insert(
        symbol: '6811',
        date: day,
        buyVolume: const Value(111),
        sellVolume: const Value(99),
        tradeVolume: const Value(7000),
      ),
    ]);

    expect(
      await ratio(),
      42.5,
      reason: 'day_trading_ratio 是當沖規則唯一輸入，洗成 NULL 等於訊號消失',
    );
  });

  test('回補仍會更新量值欄位', () async {
    await db.upsertDayTradingPreservingRatio([
      DayTradingCompanion.insert(
        symbol: '6811',
        date: day,
        buyVolume: const Value(111),
        sellVolume: const Value(99),
        tradeVolume: const Value(8888),
      ),
    ]);

    final rows = await db.getDayTradingHistory(
      '6811',
      startDate: day,
      endDate: day,
    );
    expect(rows.single.tradeVolume, 8888);
    expect(rows.single.buyVolume, 111);
  });

  test('該日原本沒有列 → 正常寫入，比例為 null', () async {
    final other = DateTime(2026, 8, 20);
    await db.upsertDayTradingPreservingRatio([
      DayTradingCompanion.insert(
        symbol: '6811',
        date: other,
        buyVolume: const Value(1),
        sellVolume: const Value(2),
        tradeVolume: const Value(3),
      ),
    ]);

    final rows = await db.getDayTradingHistory(
      '6811',
      startDate: other,
      endDate: other,
    );
    expect(rows.single.tradeVolume, 3);
    expect(rows.single.dayTradingRatio, isNull);
  });

  test('🚨 回補即使帶了比例，既有值仍優先（每日路徑的分母才是權威）', () async {
    await db.upsertDayTradingPreservingRatio([
      DayTradingCompanion.insert(
        symbol: '6811',
        date: day,
        buyVolume: const Value(111),
        sellVolume: const Value(99),
        dayTradingRatio: const Value(88.8),
        tradeVolume: const Value(7000),
      ),
    ]);

    expect(
      await ratio(),
      42.5,
      reason:
          '本方法刻意只更新量值——回補算出的比例與每日路徑可能用不同分母，'
          '既有值優先。回補腳本因此只在該日「原本沒有列」時才貢獻比例',
    );
  });
}

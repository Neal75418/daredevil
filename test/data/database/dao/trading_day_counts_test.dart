// getDayTradingCountsByDayAndMarket / getMarginTradingCountsByDayAndMarket
// — 各(日, 市場)筆數聚合(真 in-memory DB)
//
// 籌碼缺漏日回補迴圈原本逐 (日, 市場) COUNT,40 天窗每輪每日更新
// ~140 次查詢(2026-08-29 效能稽核 #4;正是 getPriceCountsByDayAndMarket
// 批次化前例的未修 sibling)。核心保證與前例相同:對同一批資料,
// batch 與逐日版逐格等價。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '8069', name: '元太', market: 'TPEx'),
    ]);

    // 7/13:上市兩檔 + 上櫃一檔;7/14:僅上市一檔;7/10:窗外
    for (final (sym, d) in [
      ('2330', DateTime(2026, 7, 13)),
      ('2317', DateTime(2026, 7, 13)),
      ('8069', DateTime(2026, 7, 13)),
      ('2330', DateTime(2026, 7, 14)),
      ('2330', DateTime(2026, 7, 10)),
    ]) {
      await db.insertDayTradingData([
        DayTradingCompanion.insert(
          symbol: sym,
          date: d,
          dayTradingRatio: const Value(10),
        ),
      ]);
      await db.insertMarginTradingData([
        MarginTradingCompanion.insert(
          symbol: sym,
          date: d,
          marginBalance: const Value(1000),
        ),
      ]);
    }
  });

  tearDown(() async => db.close());

  final windowStart = DateTime(2026, 7, 11);
  final windowEnd = DateTime(2026, 7, 14);

  test('當沖:market → 日 → 筆數;窗外與零筆組缺鍵', () async {
    final counts = await db.getDayTradingCountsByDayAndMarket(
      startDate: windowStart,
      endDate: windowEnd,
    );
    expect(counts['TWSE'], {'2026-07-13': 2, '2026-07-14': 1});
    expect(counts['TPEx'], {'2026-07-13': 1});
  });

  test('融資:market → 日 → 筆數;窗外與零筆組缺鍵', () async {
    final counts = await db.getMarginTradingCountsByDayAndMarket(
      startDate: windowStart,
      endDate: windowEnd,
    );
    expect(counts['TWSE'], {'2026-07-13': 2, '2026-07-14': 1});
    expect(counts['TPEx'], {'2026-07-13': 1});
  });

  test('🚨 與逐 (日, 市場) 版逐格等價(兩張表)', () async {
    final dt = await db.getDayTradingCountsByDayAndMarket(
      startDate: windowStart,
      endDate: windowEnd,
    );
    final mt = await db.getMarginTradingCountsByDayAndMarket(
      startDate: windowStart,
      endDate: windowEnd,
    );
    for (final market in ['TWSE', 'TPEx']) {
      for (
        var day = windowStart;
        !day.isAfter(windowEnd);
        day = day.add(const Duration(days: 1))
      ) {
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        expect(
          dt[market]?[key] ?? 0,
          await db.getDayTradingCountForDateAndMarket(day, market),
          reason: '當沖 $market $key',
        );
        expect(
          mt[market]?[key] ?? 0,
          await db.countMarginTradingByDateAndMarket(day, market),
          reason: '融資 $market $key',
        );
      }
    }
  });
}

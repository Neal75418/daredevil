// 缺口偵測 — 上櫃當沖的專屬需求
//
// 上市、上櫃當沖漏掉的日子都由 `_backfillMissingTradingDays` 的 40 天窗自動
// 補回（上市 TWTB4U、上櫃 `/www/zh-tw/intraday/stat`，皆帶 date 取歷史）；
// 本檔測的 `findDayTradingGapDates` 查的是**回補跑完之後仍缺**的天數，多半
// 是該日上櫃價格覆蓋未達門檻（回補會整批跳過）或單輪回補天數上限尚未輪到。
// 實測近 60 天有 22 次 PARTIAL、1 次 FAILED（10.7%），所以缺口不是罕見情況。
//
// 40 天窗內、追蹤起始日以後未定案的日子由 `MarketDayRefetcher` 每輪重抓；
// 窗外只記 warning，需手動跑 `tool/refetch_market_days.dart --dataset
// dayTrading --market TPEx`（同一套官方端點，免額度）。官方端點實測可
// 回溯到 2024-01（更早未驗證，不是驗證過涵蓋不到）；2024-01 以前可先用
// 同一支工具試，不行再走 FinMind CLI（`tool/backfill_tpex_day_trading.dart`），
// 其成本與缺口大小無關——逐檔計費、單次可拉整段區間，補 3 天和補 6 年都
// 是 220 次呼叫。所以偵測要便宜（純 DB 查詢、零額度），補救要批次。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '6104', name: 'A', market: 'TPEx'),
      StockMasterCompanion.insert(symbol: '2330', name: 'B', market: 'TWSE'),
    ]);
  });

  tearDown(() async => db.close());

  Future<void> seedPrice(String symbol, DateTime d) => db.insertPrices([
    DailyPriceCompanion.insert(
      symbol: symbol,
      date: d,
      close: const Value(100),
      volume: const Value(1000),
    ),
  ]);

  Future<void> seedDayTrading(String symbol, DateTime d) =>
      db.insertDayTradingData([
        DayTradingCompanion.insert(
          symbol: symbol,
          date: d,
          buyVolume: const Value(1),
          sellVolume: const Value(1),
          dayTradingRatio: const Value(10),
          tradeVolume: const Value(1),
        ),
      ]);

  test('🚨 有價格但無當沖的交易日 → 列為缺口', () async {
    final d1 = DateTime(2026, 8, 19);
    final d2 = DateTime(2026, 8, 20); // 這天缺當沖
    final d3 = DateTime(2026, 8, 21);
    for (final d in [d1, d2, d3]) {
      await seedPrice('6104', d);
    }
    await seedDayTrading('6104', d1);
    await seedDayTrading('6104', d3);

    final gaps = await db.findDayTradingGapDates(
      market: 'TPEx',
      since: DateTime(2026, 8, 1),
    );

    expect(gaps.map((d) => d.day), [20]);
  });

  test('沒有價格的日子不算缺口（本來就休市）', () async {
    await seedPrice('6104', DateTime(2026, 8, 19));
    await seedDayTrading('6104', DateTime(2026, 8, 19));

    final gaps = await db.findDayTradingGapDates(
      market: 'TPEx',
      since: DateTime(2026, 8, 1),
    );

    expect(gaps, isEmpty);
  });

  test('🚨 只看指定市場——上市的缺口不算進上櫃', () async {
    final d = DateTime(2026, 8, 20);
    await seedPrice('2330', d); // 上市有價格
    await seedPrice('6104', d);
    await seedDayTrading('6104', d); // 上櫃有當沖、上市沒有

    final tpexGaps = await db.findDayTradingGapDates(
      market: 'TPEx',
      since: DateTime(2026, 8, 1),
    );
    final twseGaps = await db.findDayTradingGapDates(
      market: 'TWSE',
      since: DateTime(2026, 8, 1),
    );

    expect(tpexGaps, isEmpty, reason: '上櫃該日有資料');
    expect(twseGaps.map((d) => d.day), [20], reason: '上市該日缺');
  });

  test('since 之前的缺口不列入', () async {
    await seedPrice('6104', DateTime(2026, 7, 1)); // 缺當沖但在 since 之前
    await seedPrice('6104', DateTime(2026, 8, 20));
    await seedDayTrading('6104', DateTime(2026, 8, 20));

    final gaps = await db.findDayTradingGapDates(
      market: 'TPEx',
      since: DateTime(2026, 8, 1),
    );

    expect(gaps, isEmpty);
  });

  test('🚨 since 當日的變體時戳(08:00)不得被判成缺口', () async {
    // EXCEPT 右側帶 dt.date >= since——歷史上存在非午夜的變體時戳,
    // 這條釘住「同曆日任何時戳必 ≥ 午夜」的邊界前提。
    final d = DateTime(2026, 8, 1);
    await seedPrice('6104', d);
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '6104',
        date: DateTime(2026, 8, 1, 8), // 變體時戳
        buyVolume: const Value(1),
        sellVolume: const Value(1),
        dayTradingRatio: const Value(10),
        tradeVolume: const Value(1),
      ),
    ]);

    final gaps = await db.findDayTradingGapDates(market: 'TPEx', since: d);

    expect(gaps, isEmpty, reason: '該日有當沖資料(僅時戳非午夜),不是缺口');
  });
}

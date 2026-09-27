// 價格同步的定案判斷（spec §4.5(a)）
//
// 回歸測試：當天已有遠超舊門檻的列數、但還沒定案時，必須重抓。
// 舊邏輯（列數 > 1500 就跳過）正是 7 月起上市成交量停在 15:30 初值的原因。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/price_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockFinMindClient extends Mock implements FinMindClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late PriceRepository repo;
  final day = DateTime(2026, 9, 24);

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  TwseDailyPrice twsePrice(String code, double volume) => TwseDailyPrice(
    date: day,
    code: code,
    name: code,
    open: 10,
    high: 10,
    low: 10,
    close: 10,
    volume: volume,
    change: 0,
  );
  TpexDailyPrice tpexPrice(String code, double volume) => TpexDailyPrice(
    date: day,
    code: code,
    name: code,
    open: 10,
    high: 10,
    low: 10,
    close: 10,
    volume: volume,
    change: 0,
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['1101', '1102'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.twse,
        ),
      for (final s in ['3624', '6488'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.tpex,
        ),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    when(() => twse.getAllDailyPrices(date: any(named: 'date'))).thenAnswer(
      (_) async => [twsePrice('1101', 2000), twsePrice('1102', 3000)],
    );
    when(() => tpex.getAllDailyPrices(date: any(named: 'date'))).thenAnswer(
      (_) async => [tpexPrice('3624', 4000), tpexPrice('6488', 5000)],
    );
    repo = PriceRepository(
      database: db,
      finMindClient: MockFinMindClient(),
      twseClient: twse,
      tpexClient: tpex,
    );
  });

  tearDown(() => db.close());

  Future<void> markFinal(String market) => db.upsertMarketDayFetch(
    dataset: MarketDataset.prices.code,
    market: market,
    date: day,
    fetchedAt: DateTime(2026, 9, 25),
    rowCount: 2,
  );

  test('🚨 回歸：已有大量列但未定案 → 仍要重抓', () async {
    // 舊閘門：getPriceCountForDate(day) > fullMarketThreshold(1500) 就跳過。
    // 用其他市場代碼的 1501 檔塞滿列數，才不會改變上市／上櫃的 ledger 門檻。
    // 修改前這條必須紅（舊邏輯會跳過、不打 API）。
    await db.upsertStocks([
      for (var i = 0; i < 1501; i++)
        StockMasterCompanion.insert(
          symbol: 'X$i',
          name: 'X$i',
          market: 'OTHER',
        ),
    ]);
    await db.insertPrices([
      for (var i = 0; i < 1501; i++)
        DailyPriceCompanion.insert(symbol: 'X$i', date: day),
    ]);
    expect(await db.getPriceCountForDate(day), greaterThan(1500));
    await repo.syncAllPricesForDate(day);
    verify(() => twse.getAllDailyPrices(date: any(named: 'date'))).called(1);
    verify(() => tpex.getAllDailyPrices(date: any(named: 'date'))).called(1);
  });

  test('兩市場都已定案 → 跳過、不打 API', () async {
    await markFinal(MarketCode.twse);
    await markFinal(MarketCode.tpex);
    final r = await repo.syncAllPricesForDate(day);
    expect(r.skipped, isTrue);
    verifyNever(() => twse.getAllDailyPrices(date: any(named: 'date')));
  });

  test('只有上市定案 → 仍重抓', () async {
    await markFinal(MarketCode.twse);
    await repo.syncAllPricesForDate(day);
    verify(() => tpex.getAllDailyPrices(date: any(named: 'date'))).called(1);
  });

  test('只有上櫃定案 → 仍重抓（對稱，防止只檢查一個市場）', () async {
    await markFinal(MarketCode.tpex);
    await repo.syncAllPricesForDate(day);
    verify(() => twse.getAllDailyPrices(date: any(named: 'date'))).called(1);
  });

  test('ledger 逐市場記錄實際資料日與列數', () async {
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 24, 21, 30),
    );
    await repo.syncAllPricesForDate(day, ledger: ledger);
    expect(
      ledger.recorded.map((r) => (r.market, r.date, r.rows)),
      containsAll([(MarketCode.twse, day, 2), (MarketCode.tpex, day, 2)]),
    );
  });

  test('單一市場回空：只記錄有資料的市場', () async {
    when(
      () => tpex.getAllDailyPrices(date: any(named: 'date')),
    ).thenAnswer((_) async => []);
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: day);
    await repo.syncAllPricesForDate(day, ledger: ledger);
    expect(ledger.recorded.map((r) => r.market), [MarketCode.twse]);
  });

  test('寫入價格後重算同日當沖比例', () async {
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '1101',
        date: day,
        dayTradingRatio: const Value(90),
        tradeVolume: const Value(500),
      ),
    ]);
    await repo.syncAllPricesForDate(day);
    final dt = await db.getDayTradingHistory('1101', startDate: day);
    expect(dt.single.dayTradingRatio, 25.0, reason: '500 ÷ 2000 × 100');
  });

  test('回補（backfillTpexPricesByDate）也記錄並重算、且記在 TPEx（不是 TWSE）', () async {
    when(() => tpex.getAllDailyPricesHistorical(any())).thenAnswer(
      (_) async => [tpexPrice('3624', 4000), tpexPrice('6488', 5000)],
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 25),
    );
    await repo.backfillTpexPricesByDate(
      date: day,
      targetSymbols: {'3624', '6488'},
      ledger: ledger,
    );
    expect(ledger.recorded.single, (
      dataset: MarketDataset.prices,
      market: MarketCode.tpex,
      date: day,
      rows: 2,
    ));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.tpex,
        date: day,
      ),
      isTrue,
    );
  });

  test('回補（backfillTwsePricesByDate）也記錄並重算', () async {
    when(() => twse.getAllDailyPricesHistorical(any())).thenAnswer(
      (_) async => [twsePrice('1101', 2000), twsePrice('1102', 3000)],
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 25),
    );
    await repo.backfillTwsePricesByDate(
      date: day,
      targetSymbols: {'1101', '1102'},
      ledger: ledger,
    );
    expect(ledger.recorded.single.market, MarketCode.twse);
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isTrue,
    );
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late TradingRepository repo;
  final day = DateTime(2026, 9, 24);
  final prevDay = DateTime(2026, 9, 23);

  TwseMarginTrading twseMargin(String code, DateTime d) => TwseMarginTrading(
    date: d,
    code: code,
    name: code,
    marginBuy: 1,
    marginSell: 1,
    marginBalance: 10,
    shortBuy: 0,
    shortSell: 0,
    shortBalance: 0,
  );
  TpexMarginTrading tpexMargin(String code, DateTime d) => TpexMarginTrading(
    date: d,
    code: code,
    name: code,
    marginBuy: 1,
    marginSell: 1,
    marginBalance: 10,
    shortBuy: 0,
    shortSell: 0,
    shortBalance: 0,
  );

  setUpAll(() => registerFallbackValue(DateTime(2026)));

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
    repo = TradingRepository(database: db, twseClient: twse, tpexClient: tpex);
  });

  tearDown(() => db.close());

  test('上市當沖：寫入後回報 (dayTrading, TWSE, 資料日, 列數)', () async {
    await db.insertPrices([
      for (final s in ['1101', '1102'])
        DailyPriceCompanion.insert(
          symbol: s,
          date: day,
          volume: const Value(1000),
        ),
    ]);
    when(() => twse.getAllDayTradingData(date: any(named: 'date'))).thenAnswer(
      (_) async => [
        for (final s in ['1101', '1102'])
          TwseDayTrading(
            date: day,
            code: s,
            name: s,
            buyVolume: 1,
            sellVolume: 1,
            totalVolume: 100,
          ),
      ],
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 25),
    );
    await repo.syncAllDayTradingFromTwse(
      date: day,
      force: true,
      ledger: ledger,
    );
    final r = ledger.recorded.single;
    expect(
      (r.dataset, r.market, r.date, r.rows),
      (MarketDataset.dayTrading, MarketCode.twse, day, 2),
    );
  });

  test('融資券（每日，不帶日期）：兩市場回應日期不同時各自以回應日期回報', () async {
    when(
      () => twse.getAllMarginTradingData(date: any(named: 'date')),
    ).thenAnswer(
      (_) async => [twseMargin('1101', day), twseMargin('1102', day)],
    );
    when(
      () => tpex.getAllMarginTradingData(date: any(named: 'date')),
    ).thenAnswer(
      (_) async => [tpexMargin('3624', prevDay), tpexMargin('6488', prevDay)],
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 24, 15, 30),
    );
    await repo.syncAllMarginTrading(date: day, force: true, ledger: ledger);
    expect(
      ledger.recorded.map((r) => (r.market, r.date)),
      unorderedEquals([(MarketCode.twse, day), (MarketCode.tpex, prevDay)]),
    );
  });

  test('融資券回補：只回報有抓的市場', () async {
    when(
      () => tpex.getAllMarginTradingData(date: any(named: 'date')),
    ).thenAnswer(
      (_) async => [tpexMargin('3624', prevDay), tpexMargin('6488', prevDay)],
    );
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: day);
    await repo.backfillMarginTradingByDate(
      date: prevDay,
      markets: {MarketCode.tpex},
      ledger: ledger,
    );
    expect(ledger.recorded.map((r) => r.market), [MarketCode.tpex]);
    verifyNever(() => twse.getAllMarginTradingData(date: any(named: 'date')));
  });
}

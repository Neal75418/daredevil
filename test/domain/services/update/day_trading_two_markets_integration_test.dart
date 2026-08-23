// 兩市場當沖同日寫入 — 走完整 syncMarketWideData、真 in-memory DB
//
// 既有測試都在 repository 層驗 delete window 的限縮，或在 updater 層用 mock
// repo 驗接線。**沒有一條走完整條路徑**：TWSE 與 TPEx 各自的 _persistDayTrading
// 都會在同一天執行 delete（各自 market ∪ batchSymbols、±12h），後跑的那個
// 若限縮寫錯就會清掉前一個的成果——而且刪完立刻寫自己的，筆數看起來正常。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/tpex/models.dart';
import 'package:daredevil/data/models/twse/models.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/domain/services/update/market_data_updater.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockShareholdingRepository extends Mock
    implements ShareholdingRepository {}

class MockWarningRepository extends Mock implements WarningRepository {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late MarketDataUpdater updater;

  final day = DateTime(2026, 8, 21);

  setUp(() async {
    db = AppDatabase.forTesting();
    // 兩市場各 4 檔，價格全給（覆蓋率 100%，閘門必過）
    await db.upsertStocks([
      for (final s in ['2330', '2317', '2454', '2308'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
      for (final s in ['6104', '3105', '1815', '5483'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TPEx'),
    ]);
    await db.insertPrices([
      for (final s in [
        '2330',
        '2317',
        '2454',
        '2308',
        '6104',
        '3105',
        '1815',
        '5483',
      ])
        DailyPriceCompanion.insert(
          symbol: s,
          date: day,
          close: const Value(100),
          volume: const Value(10000),
        ),
    ]);

    twse = MockTwseClient();
    tpex = MockTpexClient();
    when(() => twse.getAllDayTradingData(date: any(named: 'date'))).thenAnswer(
      (_) async => [
        for (final s in ['2330', '2317'])
          TwseDayTrading(
            date: day,
            code: s,
            name: s,
            buyVolume: 100,
            sellVolume: 90,
            totalVolume: 2000,
          ),
      ],
    );
    when(() => tpex.getAllDayTradingData()).thenAnswer(
      (_) async => [
        for (final s in ['6104', '3105'])
          TpexDayTrading(
            date: day,
            code: s,
            name: s,
            buyVolume: 50,
            sellVolume: 45,
            totalVolume: 3000,
          ),
      ],
    );

    updater = MarketDataUpdater(
      database: db,
      tradingRepository: TradingRepository(
        database: db,
        twseClient: twse,
        tpexClient: tpex,
      ),
      shareholdingRepository: MockShareholdingRepository(),
      warningRepository: MockWarningRepository(),
      insiderRepository: MockInsiderRepository(),
      backfillCallDelay: Duration.zero,
    );
  });

  tearDown(() async => db.close());

  test('🚨 同日兩市場都寫得進去，互不清除', () async {
    final r = await updater.syncMarketWideData(date: day, force: true);

    expect(r.dayTradingCount, 2, reason: '上市');
    expect(r.tpexDayTradingCount, 2, reason: '上櫃');

    for (final s in ['2330', '2317', '6104', '3105']) {
      final rows = await db.getDayTradingHistory(
        s,
        startDate: day,
        endDate: day,
      );
      expect(rows, hasLength(1), reason: '$s 應恰好一列');
      expect(rows.single.dayTradingRatio, greaterThan(0), reason: '$s 比例應算得出來');
    }
  });

  test('🚨 重跑一次仍是各一列，不重複也不互刪', () async {
    await updater.syncMarketWideData(date: day, force: true);
    await updater.syncMarketWideData(date: day, force: true);

    for (final s in ['2330', '6104']) {
      expect(
        await db.getDayTradingHistory(s, startDate: day, endDate: day),
        hasLength(1),
        reason: '$s 重跑後仍應恰好一列',
      );
    }
    expect(await db.getDayTradingCountForDateAndMarket(day, 'TWSE'), 2);
    expect(await db.getDayTradingCountForDateAndMarket(day, 'TPEx'), 2);
  });
}

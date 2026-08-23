// 上櫃當沖同步（真 in-memory DB）
//
// 與上市路徑的關鍵差異：端點無視請求日期、永遠回最新交易日，故**寫入日期取自
// 回應**。上市那條的守衛是「回應日期 ≠ 請求日期就丟棄」，這裡反過來——若照抄
// 用請求日期寫入，會把最新資料寫成歷史日期，而且筆數正常、毫無訊號。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/tpex/models.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late AppDatabase db;
  late MockTpexClient mockTpex;
  late TradingRepository repo;

  final dataDay = DateTime(2026, 8, 21);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '6104', name: '創惟', market: 'TPEx'),
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    mockTpex = MockTpexClient();
    repo = TradingRepository(
      database: db,
      twseClient: MockTwseClient(),
      tpexClient: mockTpex,
    );
  });

  tearDown(() async => db.close());

  void stubTpex(List<TpexDayTrading> rows) {
    when(() => mockTpex.getAllDayTradingData()).thenAnswer((_) async => rows);
  }

  TpexDayTrading row(String code, {DateTime? date, double volume = 1000}) =>
      TpexDayTrading(
        date: date ?? dataDay,
        code: code,
        name: 'X',
        buyVolume: 5000,
        sellVolume: 4900,
        totalVolume: volume,
      );

  Future<void> seedPrice(String symbol, DateTime date, double volume) =>
      db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: symbol,
          date: date,
          close: const Value(100),
          volume: Value(volume),
        ),
      ]);

  test('寫入上櫃當沖並算出比例', () async {
    await seedPrice('6104', dataDay, 4000);
    stubTpex([row('6104', volume: 1000)]);

    final n = await repo.syncAllDayTradingFromTpex();

    expect(n, 1);
    final rows = await db.getDayTradingHistory(
      '6104',
      startDate: dataDay,
      endDate: dataDay,
    );
    expect(rows.single.dayTradingRatio, closeTo(25.0, 1e-9));
    expect(rows.single.tradeVolume, 1000);
  });

  test('🚨 寫入日期取自回應，不得用今天', () async {
    final older = DateTime(2026, 8, 19);
    await seedPrice('6104', older, 4000);
    stubTpex([row('6104', date: older)]);

    await repo.syncAllDayTradingFromTpex();

    final onOlder = await db.getDayTradingHistory(
      '6104',
      startDate: older,
      endDate: older,
    );
    expect(onOlder, isNotEmpty, reason: '端點無視請求日期；用今天寫入會把資料掛在錯誤的日子上');
  });

  test('🚨 不得刪掉同日的上市當沖資料', () async {
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '2330',
        date: dataDay,
        buyVolume: const Value(1),
        sellVolume: const Value(1),
        dayTradingRatio: const Value(42),
        tradeVolume: const Value(1),
      ),
    ]);
    await seedPrice('6104', dataDay, 4000);
    stubTpex([row('6104')]);

    await repo.syncAllDayTradingFromTpex();

    final twse = await db.getDayTradingHistory(
      '2330',
      startDate: dataDay,
      endDate: dataDay,
    );
    expect(twse, isNotEmpty, reason: 'delete window 必須限縮在上櫃');
    expect(twse.single.dayTradingRatio, 42);
  });

  test('回應為空 → 回 0、不動 DB', () async {
    stubTpex([]);
    expect(await repo.syncAllDayTradingFromTpex(), 0);
  });

  test('新鮮度：該日上櫃已有足量資料 → 跳過寫入', () async {
    await db.upsertStocks([
      for (var i = 0; i < 150; i++)
        StockMasterCompanion.insert(
          symbol: '8${i.toString().padLeft(3, '0')}',
          name: 'O$i',
          market: 'TPEx',
        ),
    ]);
    await db.insertDayTradingData([
      for (var i = 0; i < 150; i++)
        DayTradingCompanion.insert(
          symbol: '8${i.toString().padLeft(3, '0')}',
          date: dataDay,
          buyVolume: const Value(1),
          sellVolume: const Value(1),
          dayTradingRatio: const Value(5),
          tradeVolume: const Value(1),
        ),
    ]);
    await seedPrice('6104', dataDay, 4000);
    stubTpex([row('6104')]);

    final n = await repo.syncAllDayTradingFromTpex();

    expect(n, 0, reason: '> DataFreshness.twseBatchThreshold 視為已同步');
    expect(
      await db.getDayTradingHistory(
        '6104',
        startDate: dataDay,
        endDate: dataDay,
      ),
      isEmpty,
      reason: '跳過就是真的沒寫，不能只看回傳值',
    );
  });

  test('force 略過新鮮度', () async {
    await db.upsertStocks([
      for (var i = 0; i < 150; i++)
        StockMasterCompanion.insert(
          symbol: '8${i.toString().padLeft(3, '0')}',
          name: 'O$i',
          market: 'TPEx',
        ),
    ]);
    await db.insertDayTradingData([
      for (var i = 0; i < 150; i++)
        DayTradingCompanion.insert(
          symbol: '8${i.toString().padLeft(3, '0')}',
          date: dataDay,
          buyVolume: const Value(1),
          sellVolume: const Value(1),
          dayTradingRatio: const Value(5),
          tradeVolume: const Value(1),
        ),
    ]);
    await seedPrice('6104', dataDay, 4000);
    stubTpex([row('6104')]);

    expect(await repo.syncAllDayTradingFromTpex(force: true), 1);
  });

  test('無價格資料 → 比例 0（與上市同語意，不瞎猜）', () async {
    stubTpex([row('6104')]);

    await repo.syncAllDayTradingFromTpex();

    final rows = await db.getDayTradingHistory(
      '6104',
      startDate: dataDay,
      endDate: dataDay,
    );
    expect(rows.single.dayTradingRatio, 0.0);
  });

  test('比例超過 100% 仍鉗制', () async {
    await seedPrice('6104', dataDay, 1000);
    stubTpex([row('6104', volume: 3500)]);

    await repo.syncAllDayTradingFromTpex();

    final rows = await db.getDayTradingHistory(
      '6104',
      startDate: dataDay,
      endDate: dataDay,
    );
    expect(rows.single.dayTradingRatio, DataFreshness.dayTradingMaxValidRatio);
  });

  test('🚨 寫入失敗必須包成 DatabaseException（return future 會繞過 catch）', () async {
    // 未登錄在 stock_master 的代號 → FK 787。上櫃新掛牌、或 step 2 股票清單
    // 同步失敗（只記錯誤續跑）時，這是會真的發生的情況。
    await seedPrice('6104', dataDay, 4000);
    stubTpex([row('9999')]);

    await expectLater(
      repo.syncAllDayTradingFromTpex(),
      throwsA(isA<DatabaseException>()),
      reason:
          'Dart 的 `return future;` 在 try 內會先離開 try——catch 收不到，'
          '原始例外裸奔而出，上游的 on Exception catch 也接不到 Error 子型別',
    );
  });

  test('🚨 回應為空 → 不得刪掉該市場既有資料', () async {
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '6104',
        date: dataDay,
        buyVolume: const Value(1),
        sellVolume: const Value(1),
        dayTradingRatio: const Value(7),
        tradeVolume: const Value(1),
      ),
    ]);
    stubTpex([]);

    expect(await repo.syncAllDayTradingFromTpex(), 0);

    final rows = await db.getDayTradingHistory(
      '6104',
      startDate: dataDay,
      endDate: dataDay,
    );
    expect(rows, isNotEmpty, reason: '沒東西可寫時不該把既有資料清掉');
  });
}

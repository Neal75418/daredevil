// 融資融券歷史回補（TradingRepository.backfillMarginTradingByDate）
//
// 每日路徑（syncAllMarginTrading）刻意**不傳日期**——TPEx 有 T+1
// 延遲，省略日期時端點自動回最新可用日。回補是另一條路徑：明確指定歷史日期，
// 並以「entry 自身日期 == 請求日期」過濾（端點若無視日期參數只會回空，
// 不會寫出錯誤日期的列）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late MockAppDatabase mockDb;
  late MockTwseClient mockTwse;
  late MockTpexClient mockTpex;
  late TradingRepository repo;

  final targetDate = DateTime(2026, 7, 7);

  TwseMarginTrading twseEntry(String code, DateTime date) => TwseMarginTrading(
    date: date,
    code: code,
    name: code,
    marginBuy: 100,
    marginSell: 50,
    marginBalance: 950,
    shortBuy: 10,
    shortSell: 20,
    shortBalance: 40,
  );

  TpexMarginTrading tpexEntry(String code, DateTime date) => TpexMarginTrading(
    date: date,
    code: code,
    name: code,
    marginBuy: 5,
    marginSell: 3,
    marginBalance: 80,
    shortBuy: 1,
    shortSell: 2,
    shortBalance: 6,
  );

  StockMasterEntry stock(String symbol, String market) => StockMasterEntry(
    symbol: symbol,
    name: symbol,
    market: market,
    isActive: true,
    updatedAt: targetDate,
  );

  setUp(() {
    mockDb = MockAppDatabase();
    mockTwse = MockTwseClient();
    mockTpex = MockTpexClient();
    repo = TradingRepository(
      database: mockDb,
      twseClient: mockTwse,
      tpexClient: mockTpex,
    );

    when(
      () => mockDb.getAllActiveStocks(),
    ).thenAnswer((_) async => [stock('2330', 'TWSE'), stock('6488', 'TPEx')]);
    when(() => mockDb.insertMarginTradingData(any())).thenAnswer((_) async {});
    when(() => mockDb.transaction<void>(any())).thenAnswer((inv) async {
      await (inv.positionalArguments[0] as Future<void> Function())();
    });
  });

  group('backfillMarginTradingByDate', () {
    test('傳日期給兩個 client、合併寫入、回傳筆數', () async {
      when(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => [twseEntry('2330', targetDate)]);
      when(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => [tpexEntry('6488', targetDate)]);

      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: {MarketCode.twse, MarketCode.tpex},
      );

      expect(count.twseRows, 1);
      expect(count.tpexRows, 1);
      verify(
        () => mockTwse.getAllMarginTradingData(date: targetDate),
      ).called(1);
      verify(
        () => mockTpex.getAllMarginTradingData(date: targetDate),
      ).called(1);

      final written =
          verify(
                () => mockDb.insertMarginTradingData(captureAny()),
              ).captured.single
              as List<MarginTradingCompanion>;
      expect(written, hasLength(2));
      expect(
        written.every((e) => e.date.value == targetDate),
        isTrue,
        reason: '寫入日期必須是請求的歷史日期',
      );
    });

    test('端點回錯日期的列被丟棄（無視 date 參數的防護）', () async {
      // 端點回最新交易日（7/13）而非請求的 7/7
      when(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => [twseEntry('2330', DateTime(2026, 7, 13))]);
      when(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => [tpexEntry('6488', targetDate)]);

      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: {MarketCode.twse, MarketCode.tpex},
      );

      expect(count.twseRows, 0, reason: '上市回錯日期 → 全丟');
      expect(count.tpexRows, 1);
      final written =
          verify(
                () => mockDb.insertMarginTradingData(captureAny()),
              ).captured.single
              as List<MarginTradingCompanion>;
      expect(written.single.symbol.value, '6488');
    });

    test('兩邊皆空 → 回 0、不寫 DB', () async {
      when(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => []);
      when(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => []);

      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: {MarketCode.twse, MarketCode.tpex},
      );

      expect(count.twseRows, 0);
      expect(count.tpexRows, 0);
      verifyNever(() => mockDb.insertMarginTradingData(any()));
    });

    test('單邊失敗不影響另一邊（錯誤隔離）', () async {
      // 非同步拋（真實 client 的失敗都在 Future 內部，safeAwait 才接得住）
      when(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => throw Exception('TWSE 掛了'));
      when(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => [tpexEntry('6488', targetDate)]);

      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: {MarketCode.twse, MarketCode.tpex},
      );

      expect(count.tpexRows, 1, reason: '上櫃仍應寫入');
      expect(count.twseRows, 0);
    });

    test('不在 stock_master 的代碼被過濾（FK 保護）', () async {
      when(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer(
        (_) async => [
          twseEntry('2330', targetDate),
          twseEntry('9999', targetDate), // 不在 master
        ],
      );
      when(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => []);

      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: {MarketCode.twse, MarketCode.tpex},
      );

      expect(count.twseRows, 1, reason: '9999 不在 master → 濾掉');
    });

    test('markets 只含上櫃 → 完全不打 TWSE（避免重寫已存在市場＝假進度）', () async {
      when(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      ).thenAnswer((_) async => [tpexEntry('6488', targetDate)]);

      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: {MarketCode.tpex},
      );

      expect(count.tpexRows, 1);
      expect(count.twseRows, 0);
      verifyNever(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      );
    });

    test('markets 為空 → 回 0、不打任何 API', () async {
      final count = await repo.backfillMarginTradingByDate(
        date: targetDate,
        markets: const {},
      );

      expect(count.twseRows, 0);
      expect(count.tpexRows, 0);
      verifyNever(
        () => mockTwse.getAllMarginTradingData(date: any(named: 'date')),
      );
      verifyNever(
        () => mockTpex.getAllMarginTradingData(date: any(named: 'date')),
      );
    });
  });
}

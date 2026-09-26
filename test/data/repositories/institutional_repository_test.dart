import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/portfolio_data_builders.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockClient;
  late MockTwseClient mockTwseClient;
  late MockTpexClient mockTpexClient;
  late InstitutionalRepository repo;

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockClient = MockFinMindClient();
    mockTwseClient = MockTwseClient();
    mockTpexClient = MockTpexClient();
    repo = InstitutionalRepository(
      database: mockDb,
      finMindClient: mockClient,
      twseClient: mockTwseClient,
      tpexClient: mockTpexClient,
    );
    when(() => mockDb.transaction<void>(any())).thenAnswer((inv) async {
      await (inv.positionalArguments[0] as Future<void> Function())();
    });
    when(
      () => mockDb.deleteInstitutionalRows(
        day: any(named: 'day'),
        symbols: any(named: 'symbols'),
      ),
    ).thenAnswer((_) async => 0);
  });

  // ==========================================
  // syncInstitutionalData
  // ==========================================
  group('syncInstitutionalData', () {
    test('success — inserts data and returns count', () async {
      final startDate = DateTime(2025, 1, 1);
      when(
        () => mockClient.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer(
        (_) async => [
          const FinMindInstitutional(
            stockId: '2330',
            date: '2025-01-15',
            foreignBuy: 1000,
            foreignSell: 500,
            investmentTrustBuy: 200,
            investmentTrustSell: 100,
            dealerBuy: 50,
            dealerSell: 30,
          ),
        ],
      );
      when(
        () => mockDb.insertInstitutionalData(any()),
      ).thenAnswer((_) async {});

      final result = await repo.syncInstitutionalData(
        '2330',
        startDate: startDate,
      );

      expect(result, equals(1));
      verify(() => mockDb.insertInstitutionalData(any())).called(1);
    });

    test('rethrows RateLimitException', () async {
      when(
        () => mockClient.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException('Rate limited'));

      await expectLater(
        () =>
            repo.syncInstitutionalData('2330', startDate: DateTime(2025, 1, 1)),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('wraps other exceptions in DatabaseException', () async {
      when(
        () => mockClient.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('unknown error'));

      await expectLater(
        () =>
            repo.syncInstitutionalData('2330', startDate: DateTime(2025, 1, 1)),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  // ==========================================
  // syncAllMarketInstitutional
  // ==========================================
  group('syncAllMarketInstitutional', () {
    test('skips when freshness threshold met', () async {
      final date = DateTime(2025, 1, 15);
      when(
        () => mockDb.getInstitutionalCountForDate(any()),
      ).thenAnswer((_) async => 2000);

      final result = await repo.syncAllMarketInstitutional(date);

      expect(result, equals(2000));
      verifyNever(
        () => mockTwseClient.getAllInstitutionalData(date: any(named: 'date')),
      );
    });

    test('fetches TWSE and TPEX data when not fresh', () async {
      final date = DateTime(2025, 1, 15);
      when(
        () => mockDb.getInstitutionalCountForDate(any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockTwseClient.getAllInstitutionalData(date: any(named: 'date')),
      ).thenAnswer(
        (_) async => [
          TwseInstitutional(
            date: date,
            code: '2330',
            name: '台積電',
            foreignBuy: 1000,
            foreignSell: 500,
            foreignNet: 500,
            investmentTrustBuy: 200,
            investmentTrustSell: 100,
            investmentTrustNet: 100,
            dealerBuy: 50,
            dealerSell: 30,
            dealerNet: 20,
            totalNet: 620,
          ),
        ],
      );
      when(
        () => mockTpexClient.getAllInstitutionalData(date: any(named: 'date')),
      ).thenAnswer((_) async => <TpexInstitutional>[]);
      when(() => mockDb.getAllActiveStocks()).thenAnswer(
        (_) async => [
          createTestStockMaster(symbol: '2330', name: '台積電', market: 'TWSE'),
        ],
      );
      when(
        () => mockDb.insertInstitutionalData(any()),
      ).thenAnswer((_) async {});

      final result = await repo.syncAllMarketInstitutional(date);

      expect(result, equals(1));
    });

    test('filters out invalid symbols not in stock master', () async {
      final date = DateTime(2025, 1, 15);
      when(
        () => mockDb.getInstitutionalCountForDate(any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockTwseClient.getAllInstitutionalData(date: any(named: 'date')),
      ).thenAnswer(
        (_) async => [
          TwseInstitutional(
            date: date,
            code: '9999',
            name: '不存在',
            foreignBuy: 100,
            foreignSell: 50,
            foreignNet: 50,
            investmentTrustBuy: 0,
            investmentTrustSell: 0,
            investmentTrustNet: 0,
            dealerBuy: 0,
            dealerSell: 0,
            dealerNet: 0,
            totalNet: 50,
          ),
        ],
      );
      when(
        () => mockTpexClient.getAllInstitutionalData(date: any(named: 'date')),
      ).thenAnswer((_) async => <TpexInstitutional>[]);
      when(
        () => mockDb.getAllActiveStocks(),
      ).thenAnswer((_) async => <StockMasterEntry>[]);
      when(
        () => mockDb.insertInstitutionalData(any()),
      ).thenAnswer((_) async {});

      final result = await repo.syncAllMarketInstitutional(date);

      // 9999 not in stock master → filtered out
      expect(result, equals(0));
    });
  });

  // ==========================================
  // backfillInstitutionalByDate — Phase 2: TWSE T86 + TPEx batch
  //
  // 確保正確性的核心測試：
  // - 不打 FinMind（Phase 2 的核心優勢）
  // - 從 TWSE + TPEx batch endpoint 拿資料，按 targetSymbols 過濾後寫 DB
  // - safeAwait 容錯：任一 source 失敗不阻斷另一個
  // - RateLimit / Network 必須 rethrow 讓 backfill abort
  // ==========================================
  group('backfillInstitutionalByDate', () {
    test('fetches batch from TWSE+TPEx (no FinMind call), filters to '
        'targetSymbols, inserts only matching rows', () async {
      final date = DateTime(2026, 5, 1);
      when(() => mockTwseClient.getAllInstitutionalData(date: date)).thenAnswer(
        (_) async => [
          TwseInstitutional(
            date: date,
            code: '2330',
            name: '台積電',
            foreignBuy: 0,
            foreignSell: 0,
            foreignNet: 1000,
            investmentTrustBuy: 0,
            investmentTrustSell: 0,
            investmentTrustNet: 200,
            dealerBuy: 0,
            dealerSell: 0,
            dealerNet: 0,
            dealerSelfNet: 15,
            totalNet: 1200,
          ),
          // 1234 不在 targetSymbols 內 → 應被過濾
          TwseInstitutional(
            date: date,
            code: '1234',
            name: '不關心',
            foreignBuy: 0,
            foreignSell: 0,
            foreignNet: 500,
            investmentTrustBuy: 0,
            investmentTrustSell: 0,
            investmentTrustNet: 0,
            dealerBuy: 0,
            dealerSell: 0,
            dealerNet: 0,
            totalNet: 500,
          ),
        ],
      );
      when(() => mockTpexClient.getAllInstitutionalData(date: date)).thenAnswer(
        (_) async => [
          TpexInstitutional(
            date: date,
            code: '6488',
            name: '環球晶',
            foreignBuy: 0,
            foreignSell: 0,
            foreignNet: 300,
            investmentTrustBuy: 0,
            investmentTrustSell: 0,
            investmentTrustNet: 0,
            dealerBuy: 0,
            dealerSell: 0,
            dealerNet: 0,
            dealerSelfNet: -8,
            totalNet: 300,
          ),
        ],
      );
      when(
        () => mockDb.insertInstitutionalData(any()),
      ).thenAnswer((_) async {});

      final inserted = await repo.backfillInstitutionalByDate(
        date: date,
        targetSymbols: {'2330', '6488'},
      );

      // 沒打 FinMind — 這是這次改動最關鍵的不變式
      verifyNever(
        () => mockClient.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );

      // 兩個 batch endpoint 各被呼叫一次
      verify(
        () => mockTwseClient.getAllInstitutionalData(date: date),
      ).called(1);
      verify(
        () => mockTpexClient.getAllInstitutionalData(date: date),
      ).called(1);

      // 確認過濾：插入 2330 + 6488，1234 被排除
      final captured =
          verify(
                () => mockDb.insertInstitutionalData(captureAny()),
              ).captured.single
              as List<DailyInstitutionalCompanion>;
      final symbols = captured.map((e) => e.symbol.value).toSet();
      expect(symbols, equals({'2330', '6488'}));
      expect(inserted, equals(2));

      // dealerSelfNet 必須一路串到 companion（自行買賣 streak 的資料來源）
      final bySymbol = {for (final c in captured) c.symbol.value: c};
      expect(bySymbol['2330']!.dealerSelfNet.value, 15);
      expect(bySymbol['6488']!.dealerSelfNet.value, -8);
    });

    test('skips rows with all-zero net values (no signal)', () async {
      final date = DateTime(2026, 5, 1);
      when(() => mockTwseClient.getAllInstitutionalData(date: date)).thenAnswer(
        (_) async => [
          // 2330 全 0 → 視為無訊號，filter 掉
          TwseInstitutional(
            date: date,
            code: '2330',
            name: '台積電',
            foreignBuy: 0,
            foreignSell: 0,
            foreignNet: 0,
            investmentTrustBuy: 0,
            investmentTrustSell: 0,
            investmentTrustNet: 0,
            dealerBuy: 0,
            dealerSell: 0,
            dealerNet: 0,
            totalNet: 0,
          ),
        ],
      );
      when(
        () => mockTpexClient.getAllInstitutionalData(date: date),
      ).thenAnswer((_) async => []);

      final inserted = await repo.backfillInstitutionalByDate(
        date: date,
        targetSymbols: {'2330'},
      );

      expect(inserted, equals(0));
      verifyNever(() => mockDb.insertInstitutionalData(any()));
    });

    test('TWSE failure does not block TPEx (safeAwait isolation)', () async {
      final date = DateTime(2026, 5, 1);
      // 用 thenAnswer + async throw 才會在 Future 內部 throw（safeAwait
      // 才接得到）。thenThrow 是同步 throw，會直接從 mockClient call site
      // 拋出來，繞過 safeAwait 的容錯。
      when(
        () => mockTwseClient.getAllInstitutionalData(date: date),
      ).thenAnswer((_) async => throw Exception('TWSE temporarily down'));
      when(() => mockTpexClient.getAllInstitutionalData(date: date)).thenAnswer(
        (_) async => [
          TpexInstitutional(
            date: date,
            code: '6488',
            name: '環球晶',
            foreignBuy: 0,
            foreignSell: 0,
            foreignNet: 300,
            investmentTrustBuy: 0,
            investmentTrustSell: 0,
            investmentTrustNet: 0,
            dealerBuy: 0,
            dealerSell: 0,
            dealerNet: 0,
            totalNet: 300,
          ),
        ],
      );
      when(
        () => mockDb.insertInstitutionalData(any()),
      ).thenAnswer((_) async {});

      final inserted = await repo.backfillInstitutionalByDate(
        date: date,
        targetSymbols: {'6488'},
      );

      // TPEx 部分仍寫入
      expect(inserted, equals(1));
    });

    test('rethrows RateLimitException without wrapping', () async {
      final date = DateTime(2026, 5, 1);
      // safeAwait 不攔 RateLimitException → 它會傳到 method 級別的 catch
      when(
        () => mockTwseClient.getAllInstitutionalData(date: date),
      ).thenThrow(const RateLimitException());
      when(
        () => mockTpexClient.getAllInstitutionalData(date: date),
      ).thenAnswer((_) async => []);

      await expectLater(
        () => repo.backfillInstitutionalByDate(
          date: date,
          targetSymbols: {'2330'},
        ),
        throwsA(isA<RateLimitException>()),
      );
    });
  });

  // ==========================================
  // clearAllData
  // ==========================================
  group('clearAllData', () {
    test('delegates to database', () async {
      when(
        () => mockDb.clearAllInstitutionalData(),
      ).thenAnswer((_) async => 42);

      final result = await repo.clearAllData();

      expect(result, equals(42));
      verify(() => mockDb.clearAllInstitutionalData()).called(1);
    });
  });
}

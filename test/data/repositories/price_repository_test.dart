import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';

// Mocks
class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockFinMindClient;
  late MockTwseClient mockTwseClient;
  late MockTpexClient mockTpexClient;
  late PriceRepository repository;

  setUpAll(() {
    registerFallbackValue(MarketDataset.prices);
    registerFallbackValue(<String>{});
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockFinMindClient = MockFinMindClient();
    mockTwseClient = MockTwseClient();
    mockTpexClient = MockTpexClient();

    when(
      () => mockDb.isMarketDayFinal(
        dataset: any(named: 'dataset'),
        market: any(named: 'market'),
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) async => false);
    when(
      () => mockDb.recomputeDayTradingRatios(
        day: any(named: 'day'),
        symbols: any(named: 'symbols'),
      ),
    ).thenAnswer((_) async => 0);
    when(() => mockDb.transaction<void>(any())).thenAnswer((inv) async {
      await (inv.positionalArguments[0] as Future<void> Function())();
    });

    repository = PriceRepository(
      database: mockDb,
      finMindClient: mockFinMindClient,
      twseClient: mockTwseClient,
      tpexClient: mockTpexClient,
    );
  });

  group('PriceRepository', () {
    group('getPriceHistory', () {
      test('calls database with correct parameters', () async {
        when(
          () => mockDb.getPriceHistory(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => []);

        await repository.getPriceHistory('2330', days: 30);

        verify(
          () => mockDb.getPriceHistory(
            '2330',
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      });

      test('returns price entries from database', () async {
        final mockEntries = [
          DailyPriceEntry(
            symbol: '2330',
            date: DateTime(2024, 6, 14),
            open: 500.0,
            high: 510.0,
            low: 495.0,
            close: 505.0,
            volume: 20000000,
          ),
          DailyPriceEntry(
            symbol: '2330',
            date: DateTime(2024, 6, 15),
            open: 505.0,
            high: 520.0,
            low: 500.0,
            close: 515.0,
            volume: 25000000,
          ),
        ];

        when(
          () => mockDb.getPriceHistory(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => mockEntries);

        final result = await repository.getPriceHistory('2330');

        expect(result.length, equals(2));
        expect(result.first.symbol, equals('2330'));
        expect(result.last.close, equals(515.0));
      });
    });

    group('getLatestPrice', () {
      test('returns latest price from database', () async {
        final mockEntry = DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2024, 6, 15),
          open: 505.0,
          high: 520.0,
          low: 500.0,
          close: 515.0,
          volume: 25000000,
        );

        when(
          () => mockDb.getLatestPrice(any()),
        ).thenAnswer((_) async => mockEntry);

        final result = await repository.getLatestPrice('2330');

        expect(result, isNotNull);
        expect(result!.close, equals(515.0));
      });

      test('returns null when no price data', () async {
        when(() => mockDb.getLatestPrice(any())).thenAnswer((_) async => null);

        final result = await repository.getLatestPrice('2330');

        expect(result, isNull);
      });
    });

    group('syncAllPricesForDate', () {
      // Ruling: 舊測試斷言「列數 > 1500 就跳過」，是 spec §4.5(a) 判為錯誤
      // 的舊邏輯本身（15:30 抓到的初值列數已夠、但當天不可能定案）。改寫
      // 為新語意：只有兩市場皆 isMarketDayFinal 才跳過。
      test('兩市場皆已定案 → 跳過，不打 API', () async {
        when(
          () => mockDb.isMarketDayFinal(
            dataset: any(named: 'dataset'),
            market: any(named: 'market'),
            date: any(named: 'date'),
          ),
        ).thenAnswer((_) async => true);
        when(
          () => mockDb.getPriceCountForDate(any()),
        ).thenAnswer((_) async => 1600);
        when(() => mockDb.getPricesForDate(any())).thenAnswer((_) async => []);

        final result = await repository.syncAllPricesForDate(DateTime.now());

        expect(result.skipped, isTrue);
        verifyNever(() => mockTwseClient.getAllDailyPrices());
      });

      test('forces refresh when force is true', () async {
        when(
          () => mockDb.getPriceCountForDate(any()),
        ).thenAnswer((_) async => 1600);
        when(
          () => mockTwseClient.getAllDailyPrices(),
        ).thenAnswer((_) async => []);
        when(
          () => mockTpexClient.getAllDailyPrices(date: any(named: 'date')),
        ).thenAnswer((_) async => []);

        final result = await repository.syncAllPricesForDate(
          DateTime.now(),
          force: true,
        );

        expect(result.count, equals(0));
        verify(() => mockTwseClient.getAllDailyPrices()).called(1);
      });

      test('syncs from TWSE and TPEX APIs', () async {
        when(
          () => mockDb.getPriceCountForDate(any()),
        ).thenAnswer((_) async => 0);

        final twsePrices = [
          TwseDailyPrice(
            code: '2330',
            name: '台積電',
            date: DateTime(2024, 6, 15),
            open: 500.0,
            high: 510.0,
            low: 495.0,
            close: 505.0,
            change: 5.0,
            volume: 20000000,
          ),
        ];

        final tpexPrices = [
          TpexDailyPrice(
            code: '6533',
            name: '晶心科',
            date: DateTime(2024, 6, 15),
            open: 100.0,
            high: 105.0,
            low: 98.0,
            close: 103.0,
            change: 3.0,
            volume: 5000000,
          ),
        ];

        when(
          () => mockTwseClient.getAllDailyPrices(),
        ).thenAnswer((_) async => twsePrices);
        when(
          () => mockTpexClient.getAllDailyPrices(date: any(named: 'date')),
        ).thenAnswer((_) async => tpexPrices);
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(() => mockDb.insertPrices(any())).thenAnswer((_) async {});

        final result = await repository.syncAllPricesForDate(
          DateTime(2024, 6, 15),
        );

        expect(result.count, equals(2));
        expect(result.candidates, isNotEmpty);
        verify(() => mockDb.insertPrices(any())).called(1);
      });

      test('returns empty result when both APIs fail', () async {
        when(
          () => mockDb.getPriceCountForDate(any()),
        ).thenAnswer((_) async => 0);
        when(() => mockTwseClient.getAllDailyPrices()).thenAnswer((_) async {
          throw Exception('API Error');
        });
        when(
          () => mockTpexClient.getAllDailyPrices(date: any(named: 'date')),
        ).thenAnswer((_) async {
          throw Exception('API Error');
        });

        final result = await repository.syncAllPricesForDate(DateTime.now());

        expect(result.count, equals(0));
        expect(result.candidates, isEmpty);
      });

      test('continues when one API fails', () async {
        when(
          () => mockDb.getPriceCountForDate(any()),
        ).thenAnswer((_) async => 0);

        final twsePrices = [
          TwseDailyPrice(
            code: '2330',
            name: '台積電',
            date: DateTime(2024, 6, 15),
            open: 500.0,
            high: 510.0,
            low: 495.0,
            close: 505.0,
            change: 5.0,
            volume: 20000000,
          ),
        ];

        when(
          () => mockTwseClient.getAllDailyPrices(),
        ).thenAnswer((_) async => twsePrices);
        when(
          () => mockTpexClient.getAllDailyPrices(date: any(named: 'date')),
        ).thenAnswer((_) async {
          throw Exception('TPEX Error');
        });
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(() => mockDb.insertPrices(any())).thenAnswer((_) async {});

        final result = await repository.syncAllPricesForDate(
          DateTime(2024, 6, 15),
        );

        expect(result.count, equals(1));
        // producer 端斷言：safeAwait 把 TPEx 例外吞成空清單，這正是
        // 「僅單一市場掛掉、流程照常走完」的情境——必須讓呼叫端看得見，
        // 否則會用半個市場的資料照常評分且無人知曉。
        expect(
          result.emptyMarkets,
          equals([MarketCode.tpex]),
          reason: 'TPEx 抓取失敗必須回報，且不得誤報 TWSE',
        );
      });

      test('兩個市場都有資料時 emptyMarkets 為空', () async {
        when(
          () => mockDb.getPriceCountForDate(any()),
        ).thenAnswer((_) async => 0);
        when(() => mockTwseClient.getAllDailyPrices()).thenAnswer(
          (_) async => [
            TwseDailyPrice(
              code: '2330',
              name: '台積電',
              date: DateTime(2024, 6, 15),
              open: 500.0,
              high: 510.0,
              low: 495.0,
              close: 505.0,
              change: 5.0,
              volume: 20000000,
            ),
          ],
        );
        when(
          () => mockTpexClient.getAllDailyPrices(date: any(named: 'date')),
        ).thenAnswer(
          (_) async => [
            TpexDailyPrice(
              code: '6488',
              name: '環球晶',
              date: DateTime(2024, 6, 15),
              open: 500.0,
              high: 510.0,
              low: 495.0,
              close: 505.0,
              change: 5.0,
              volume: 5000000,
            ),
          ],
        );
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(() => mockDb.insertPrices(any())).thenAnswer((_) async {});

        final result = await repository.syncAllPricesForDate(
          DateTime(2024, 6, 15),
        );

        expect(result.emptyMarkets, isEmpty, reason: '正常路徑不得產生假警告（會造成警告疲勞）');
      });
    });

    group('syncStockPrices', () {
      test('skips when all months have sufficient data', () async {
        // Generate sufficient data for 2 months
        final mockEntries = List.generate(
          50,
          (i) => DailyPriceEntry(
            symbol: '2330',
            date: DateTime(2024, 5, 1).add(Duration(days: i)),
            open: 500.0,
            high: 510.0,
            low: 495.0,
            close: 505.0,
            volume: 20000000,
          ),
        );

        when(
          () => mockDb.getPriceHistory(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => mockEntries);

        final result = await repository.syncStockPrices(
          '2330',
          startDate: DateTime(2024, 5, 1),
          endDate: DateTime(2024, 6, 15),
        );

        expect(result, equals(0));
        verifyNever(
          () => mockTwseClient.getStockMonthlyPrices(
            code: any(named: 'code'),
            year: any(named: 'year'),
            month: any(named: 'month'),
          ),
        );
      });

      test('uses FinMind for OTC stocks', () async {
        when(
          () => mockDb.getPriceHistory(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => []);
        when(() => mockDb.getStock(any())).thenAnswer(
          (_) async => StockMasterEntry(
            symbol: '6533',
            name: '晶心科',
            market: 'TPEx',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
        );
        when(
          () => mockFinMindClient.getDailyPrices(
            stockId: any(named: 'stockId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => []);

        await repository.syncStockPrices(
          '6533',
          startDate: DateTime(2024, 5, 1),
        );

        verify(
          () => mockFinMindClient.getDailyPrices(
            stockId: '6533',
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      });

      test('throws DatabaseException on error', () async {
        when(
          () => mockDb.getPriceHistory(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenThrow(Exception('DB Error'));

        await expectLater(
          () => repository.syncStockPrices(
            '2330',
            startDate: DateTime(2024, 5, 1),
          ),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    // ============================================================
    // backfillTwsePricesByDate — TWSE STOCK_DAY_ALL batch backfill
    //
    // 確保正確性的關鍵測試（pattern mirrors backfillTpexPricesByDate）：
    // - TWSE STOCK_DAY_ALL endpoint 被呼叫，且傳入正確的 date 參數
    // - 按 targetSymbols 過濾後只寫匹配的 row
    // - RateLimit / Network exception 必須 rethrow（讓 backfill abort）
    // ============================================================
    group('backfillTwsePricesByDate', () {
      test('fetches batch from TwseClient with date param, filters to '
          'targetSymbols, inserts only matching rows', () async {
        final testDate = DateTime(2026, 5, 1);
        final batchResponse = <TwseDailyPrice>[
          TwseDailyPrice(
            date: testDate,
            code: '2330',
            name: '台積電',
            open: 500.0,
            high: 510.0,
            low: 495.0,
            close: 505.0,
            volume: 30000,
            change: 5.0,
          ),
          TwseDailyPrice(
            date: testDate,
            code: '2317',
            name: '鴻海',
            open: 100.0,
            high: 102.0,
            low: 99.0,
            close: 101.0,
            volume: 25000,
            change: 1.0,
          ),
          TwseDailyPrice(
            date: testDate,
            code: '3296',
            name: '勝德',
            open: 30.0,
            high: 31.0,
            low: 29.5,
            close: 30.5,
            volume: 1000,
            change: 0.5,
          ),
        ];

        when(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).thenAnswer((_) async => batchResponse);
        when(() => mockDb.insertPrices(any())).thenAnswer((_) async {});

        final inserted = await repository.backfillTwsePricesByDate(
          date: testDate,
          targetSymbols: {'2330', '3296'}, // 2317 should be filtered out
        );

        // 核心不變式：date 參數真的有傳到 client（不是抓今日預設）
        verify(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).called(1);

        final captured =
            verify(() => mockDb.insertPrices(captureAny())).captured.single
                as List<DailyPriceCompanion>;
        final insertedSymbols = captured.map((e) => e.symbol.value).toSet();
        expect(insertedSymbols, equals({'2330', '3296'}));
        expect(insertedSymbols.contains('2317'), isFalse);
        expect(inserted, equals(2));
      });

      test('response 日期 ≠ 請求日期（端點忽略 date 參數）→ 丟棄、回 0、不寫 DB', () async {
        // TWSE 2026-06 起 STOCK_DAY_ALL 忽略 date 參數、永遠回最新交易日。
        // 寫入這批資料會讓 per-day backfill 誤以為有進展（實際是同一天
        // 反覆重寫）→ 必須按請求日期過濾。
        final requested = DateTime(2025, 9, 10);
        final latest = DateTime(2026, 7, 9); // 端點實際回的日子
        when(
          () => mockTwseClient.getAllDailyPricesHistorical(requested),
        ).thenAnswer(
          (_) async => [
            TwseDailyPrice(
              date: latest,
              code: '2330',
              name: '台積電',
              open: 500.0,
              high: 510.0,
              low: 495.0,
              close: 505.0,
              volume: 30000,
              change: 5.0,
            ),
          ],
        );

        final inserted = await repository.backfillTwsePricesByDate(
          date: requested,
          targetSymbols: {'2330'},
        );

        expect(inserted, 0);
        verifyNever(() => mockDb.insertPrices(any()));
      });

      test('returns 0 when batch response is empty', () async {
        final testDate = DateTime(2026, 1, 1);
        when(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).thenAnswer((_) async => []);

        final inserted = await repository.backfillTwsePricesByDate(
          date: testDate,
          targetSymbols: {'2330'},
        );

        expect(inserted, equals(0));
        verifyNever(() => mockDb.insertPrices(any()));
      });

      test('returns 0 when no batch rows match targetSymbols', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).thenAnswer(
          (_) async => [
            TwseDailyPrice(
              date: testDate,
              code: '2317',
              name: '鴻海',
              open: 100.0,
              high: 100.0,
              low: 100.0,
              close: 100.0,
              volume: 1.0,
              change: 0.0,
            ),
          ],
        );

        final inserted = await repository.backfillTwsePricesByDate(
          date: testDate,
          targetSymbols: {'9999'},
        );

        expect(inserted, equals(0));
        verifyNever(() => mockDb.insertPrices(any()));
      });

      test('rethrows RateLimitException without wrapping', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).thenThrow(const RateLimitException());

        await expectLater(
          () => repository.backfillTwsePricesByDate(
            date: testDate,
            targetSymbols: {'2330'},
          ),
          throwsA(isA<RateLimitException>()),
        );
      });

      test('rethrows NetworkException without wrapping', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).thenThrow(const NetworkException('connection refused'));

        await expectLater(
          () => repository.backfillTwsePricesByDate(
            date: testDate,
            targetSymbols: {'2330'},
          ),
          throwsA(isA<NetworkException>()),
        );
      });

      test('wraps generic exception in DatabaseException', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTwseClient.getAllDailyPricesHistorical(testDate),
        ).thenAnswer(
          (_) async => [
            TwseDailyPrice(
              date: testDate,
              code: '2330',
              name: 'TSMC',
              open: 1,
              high: 1,
              low: 1,
              close: 1,
              volume: 1,
              change: 0,
            ),
          ],
        );
        when(() => mockDb.insertPrices(any())).thenThrow(Exception('DB error'));

        await expectLater(
          () => repository.backfillTwsePricesByDate(
            date: testDate,
            targetSymbols: {'2330'},
          ),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    // ============================================================
    // backfillTpexPricesByDate — TPEx OpenAPI batch backfill
    //
    // 確保正確性的關鍵測試：
    // - 不打 FinMind（會省下大量 API 額度的核心優勢）
    // - 從 batch endpoint 拿一天所有上櫃股票，按 targetSymbols 過濾後寫 DB
    // - RateLimit / Network exception 必須 rethrow（讓 backfill abort）
    // ============================================================
    group('backfillTpexPricesByDate', () {
      test('response 日期 ≠ 請求日期 → 丟棄、回 0、不寫 DB（與 TWSE 對稱）', () async {
        final requested = DateTime(2025, 9, 10);
        final latest = DateTime(2026, 7, 9);
        when(
          () => mockTpexClient.getAllDailyPricesHistorical(requested),
        ).thenAnswer(
          (_) async => [
            TpexDailyPrice(
              date: latest,
              code: '5347',
              name: '世界',
              open: 100.0,
              high: 102.0,
              low: 99.0,
              close: 101.0,
              volume: 5000,
              change: 1.0,
            ),
          ],
        );

        final inserted = await repository.backfillTpexPricesByDate(
          date: requested,
          targetSymbols: {'5347'},
        );

        expect(inserted, 0);
        verifyNever(() => mockDb.insertPrices(any()));
      });

      test('fetches batch from TpexClient (no FinMind call), filters to '
          'targetSymbols, inserts only matching rows', () async {
        final testDate = DateTime(2026, 5, 1);
        final batchResponse = <TpexDailyPrice>[
          TpexDailyPrice(
            date: testDate,
            code: '6488',
            name: '環球晶',
            open: 500.0,
            high: 510.0,
            low: 495.0,
            close: 505.0,
            volume: 12345,
            change: 5.0,
            turnover: 0.0,
          ),
          TpexDailyPrice(
            date: testDate,
            code: '8086',
            name: '宏捷科',
            open: 100.0,
            high: 102.0,
            low: 99.0,
            close: 101.0,
            volume: 6789,
            change: 1.0,
            turnover: 0.0,
          ),
          TpexDailyPrice(
            date: testDate,
            code: '8905',
            name: '裕國',
            open: 30.0,
            high: 31.0,
            low: 29.5,
            close: 30.5,
            volume: 1000,
            change: 0.5,
            turnover: 0.0,
          ),
        ];

        when(
          () => mockTpexClient.getAllDailyPricesHistorical(testDate),
        ).thenAnswer((_) async => batchResponse);
        when(() => mockDb.insertPrices(any())).thenAnswer((_) async {});

        final inserted = await repository.backfillTpexPricesByDate(
          date: testDate,
          // 只關心 6488 和 8905，8086 應被過濾掉
          targetSymbols: {'6488', '8905'},
        );

        // 沒打 FinMind — 這是這次改動最關鍵的不變式
        verifyNever(
          () => mockFinMindClient.getDailyPrices(
            stockId: any(named: 'stockId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        );

        // batch endpoint 只被呼叫一次
        verify(
          () => mockTpexClient.getAllDailyPricesHistorical(testDate),
        ).called(1);

        // 確認過濾正確：插入的只有 6488 + 8905
        final captured =
            verify(() => mockDb.insertPrices(captureAny())).captured.single
                as List<DailyPriceCompanion>;
        final insertedSymbols = captured.map((e) => e.symbol.value).toSet();
        expect(insertedSymbols, equals({'6488', '8905'}));
        expect(insertedSymbols.contains('8086'), isFalse);
        expect(inserted, equals(2));
      });

      test(
        'returns 0 when batch response is empty (non-trading day)',
        () async {
          final testDate = DateTime(2026, 1, 1); // 假設非交易日

          when(
            () => mockTpexClient.getAllDailyPricesHistorical(testDate),
          ).thenAnswer((_) async => []);

          final inserted = await repository.backfillTpexPricesByDate(
            date: testDate,
            targetSymbols: {'6488'},
          );

          expect(inserted, equals(0));
          // batch endpoint 仍被呼叫一次（caller 用 TaiwanCalendar 預過濾才是
          // 最佳實踐，但 repository 不主動 skip non-trading day）
          verifyNever(() => mockDb.insertPrices(any()));
        },
      );

      test(
        'returns 0 (no insert) when batch has rows but none match targetSymbols',
        () async {
          final testDate = DateTime(2026, 5, 1);
          when(
            () => mockTpexClient.getAllDailyPricesHistorical(testDate),
          ).thenAnswer(
            (_) async => [
              TpexDailyPrice(
                date: testDate,
                code: '8086',
                name: '宏捷科',
                open: 100.0,
                high: 100.0,
                low: 100.0,
                close: 100.0,
                volume: 1.0,
                change: 0.0,
                turnover: 0.0,
              ),
            ],
          );

          final inserted = await repository.backfillTpexPricesByDate(
            date: testDate,
            targetSymbols: {'9999'}, // 不在 batch 內
          );

          expect(inserted, equals(0));
          verifyNever(() => mockDb.insertPrices(any()));
        },
      );

      test('rethrows RateLimitException without wrapping', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTpexClient.getAllDailyPricesHistorical(testDate),
        ).thenThrow(const RateLimitException('API rate limit', null));

        await expectLater(
          () => repository.backfillTpexPricesByDate(
            date: testDate,
            targetSymbols: {'6488'},
          ),
          throwsA(isA<RateLimitException>()),
        );
      });

      test('rethrows NetworkException without wrapping', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTpexClient.getAllDailyPricesHistorical(testDate),
        ).thenThrow(const NetworkException('connection timeout', null));

        await expectLater(
          () => repository.backfillTpexPricesByDate(
            date: testDate,
            targetSymbols: {'6488'},
          ),
          throwsA(isA<NetworkException>()),
        );
      });

      test('wraps generic exception in DatabaseException', () async {
        final testDate = DateTime(2026, 5, 1);
        when(
          () => mockTpexClient.getAllDailyPricesHistorical(testDate),
        ).thenAnswer(
          (_) async => [
            TpexDailyPrice(
              date: testDate,
              code: '6488',
              name: '環球晶',
              open: 1,
              high: 1,
              low: 1,
              close: 1,
              volume: 1,
              change: 0,
              turnover: 0,
            ),
          ],
        );
        when(() => mockDb.insertPrices(any())).thenThrow(Exception('DB error'));

        await expectLater(
          () => repository.backfillTpexPricesByDate(
            date: testDate,
            targetSymbols: {'6488'},
          ),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('MarketSyncResult', () {
      test('creates with default values', () {
        const result = MarketSyncResult(
          count: 100,
          candidates: ['2330', '2317'],
        );

        expect(result.count, equals(100));
        expect(result.candidates, equals(['2330', '2317']));
        expect(result.skipped, isFalse);
        expect(result.dataDate, isNull);
      });

      test('creates with all values', () {
        final dataDate = DateTime(2024, 6, 15);
        final result = MarketSyncResult(
          count: 100,
          candidates: ['2330'],
          dataDate: dataDate,
          skipped: true,
        );

        expect(result.skipped, isTrue);
        expect(result.dataDate, equals(dataDate));
      });
    });
  });
}

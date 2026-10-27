// 上市市場日寫入帶平盤價（除權息漲跌修正 spec 第 3 節）
//
// 三個市場日寫入函式在價格之後抓同一天的 TWT84U，寫進同一個 transaction；
// 寫完查「需要平盤價的列」還缺幾列（N），依狀態表決定要不要回報定案。
// 平盤價的錯誤放進回傳值、不拋。真 in-memory DB、mock client。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockFinMindClient extends Mock implements FinMindClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late PriceRepository repo;
  late MarketDayFetchLedger ledger;
  final day = DateContext.normalize(DateTime(2026, 9, 16));
  final prevDay = DateContext.normalize(DateTime(2026, 9, 15));

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  TwseDailyPrice p(
    String code, {
    DateTime? date,
    double? close,
    double? change,
    double? volume = 1000,
  }) => TwseDailyPrice(
    date: date ?? day,
    code: code,
    name: code,
    open: close,
    high: close,
    low: close,
    close: close,
    volume: volume,
    change: change,
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.twse,
        ),
      StockMasterCompanion.insert(
        symbol: '9911',
        name: '9911',
        market: MarketCode.tpex,
      ),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    when(
      () => tpex.getAllDailyPrices(date: any(named: 'date')),
    ).thenAnswer((_) async => []);
    when(
      () => tpex.getAllDailyPricesHistorical(any()),
    ).thenAnswer((_) async => []);
    repo = PriceRepository(
      database: db,
      finMindClient: MockFinMindClient(),
      twseClient: twse,
      tpexClient: tpex,
      basePriceDelay: Duration.zero,
    );
    ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 17, 9),
    );
  });

  tearDown(() => db.close());

  void stubHist(List<TwseDailyPrice> rows) => when(
    () => twse.getAllDailyPricesHistorical(any()),
  ).thenAnswer((_) async => rows);
  void stubDaily(List<TwseDailyPrice> rows) => when(
    () => twse.getAllDailyPrices(date: any(named: 'date')),
  ).thenAnswer((_) async => rows);
  void stubBase(Map<String, double> bases) => when(
    () => twse.getOpeningBasePrices(any()),
  ).thenAnswer((_) async => bases);
  void failBase(Object e) =>
      when(() => twse.getOpeningBasePrices(any())).thenThrow(e);
  Future<DailyPriceEntry> price(String symbol, [DateTime? d]) async =>
      (await db.getPriceHistory(
        symbol,
        startDate: d ?? day,
        endDate: d ?? day,
      )).single;
  Future<MarketDayBackfillResult> backfill({
    MarketDayFetchLedger? withLedger,
    bool withBasePrices = true,
  }) => repo.backfillTwsePricesByDate(
    date: day,
    targetSymbols: {'9901', '9902'},
    ledger: withLedger,
    withBasePrices: withBasePrices,
  );

  group('backfillTwsePricesByDate（MI_INDEX）', () {
    test('🚨 X 列拿到平盤價 → 漲跌＝收盤−平盤價、fetched／N=0、回報定案', () async {
      stubHist([
        p('9901', close: 2380, change: null),
        p('9902', close: 10, change: 0.5),
      ]);
      stubBase({'9901': 2385, '9902': 9.5});
      final r = await backfill(withLedger: ledger);
      expect(r.rows, 2);
      expect(r.basePrice.fetch, BasePriceFetch.fetched);
      expect(r.basePrice.missing, 0);
      expect(r.basePrice.withheld, isFalse);
      final a = await price('9901');
      expect((a.priceChange, a.basePrice), (-5.0, 2385.0));
      final b = await price('9902');
      expect((b.priceChange, b.basePrice), (0.5, 9.5), reason: '一般日也存平盤價');
      expect(ledger.recorded.single.market, MarketCode.twse);
    });

    test('Review Focus 3：價格回空 → 不打 TWT84U、skipped、不回報', () async {
      stubHist([]);
      final r = await backfill(withLedger: ledger);
      expect(r.rows, 0);
      expect(r.basePrice.fetch, BasePriceFetch.skipped);
      verifyNever(() => twse.getOpeningBasePrices(any()));
      expect(ledger.recorded, isEmpty);
    });

    for (final (e, reason) in <(Object, String)>[
      (const ApiException('回應日期不符', 200), '回應不可信'),
      (const FormatException('x'), '抓取失敗'),
      (StateError('x'), '抓取失敗'),
    ]) {
      test(
        '🚨 平盤價那一段的任何錯誤都不拋（${e.runtimeType}）→ failed、reason「$reason」、價格照寫',
        () async {
          stubHist([
            p('9901', close: 2380, change: null),
            p('9902', close: 10, change: 0.5),
          ]);
          failBase(e);
          final r = await backfill(withLedger: ledger);
          expect(r.rows, 2);
          expect(r.basePrice.fetch, BasePriceFetch.failed);
          expect(r.basePrice.reason, reason);
          expect(r.basePrice.error, same(e));
          expect((await price('9901')).priceChange, isNull);
          expect(ledger.recorded, isEmpty);
        },
      );
    }

    test('🚨 平盤價網路錯誤、N>0 → 價格照寫、X 列空值、failed／withheld、不回報、當沖比例照算', () async {
      await db.insertDayTradingData([
        DayTradingCompanion.insert(
          symbol: '9901',
          date: day,
          dayTradingRatio: const Value(90),
          tradeVolume: const Value(500),
        ),
      ]);
      stubHist([
        p('9901', close: 2380, change: null),
        p('9902', close: 10, change: 0.5),
      ]);
      failBase(const NetworkException('x'));
      final r = await backfill(withLedger: ledger);
      expect(r.rows, 2);
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.reason, '網路錯誤');
      expect(r.basePrice.missing, 1);
      expect(r.basePrice.withheld, isTrue);
      expect(r.basePrice.shouldRecordError, isTrue);
      final a = await price('9901');
      expect((a.priceChange, a.basePrice), (null, null));
      expect((await price('9902')).priceChange, 0.5);
      expect(ledger.recorded, isEmpty);
      final dt = await db.getDayTradingHistory('9901', startDate: day);
      expect(dt.single.dayTradingRatio, 50.0, reason: '500 ÷ 1000 × 100');
    });

    test('平盤價失敗、但 X 列先前已有平盤價（N=0）→ 用新收盤重算、回報、不記 errors', () async {
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: day,
          close: const Value(2370),
          basePrice: const Value(2385),
        ),
      ]);
      stubHist([
        p('9901', close: 2380, change: null),
        p('9902', close: 10, change: 0.5),
      ]);
      failBase(const NetworkException('x'));
      final r = await backfill(withLedger: ledger);
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.missing, 0);
      expect(r.basePrice.withheld, isFalse);
      expect(r.basePrice.shouldRecordError, isFalse);
      expect((await price('9901')).priceChange, -5.0);
      expect(ledger.recorded, hasLength(1));
    });

    test('平盤價限流 → 價格照寫、rateLimited、函式不拋；N>0 不回報', () async {
      stubHist([
        p('9901', close: 2380, change: null),
        p('9902', close: 10, change: 0.5),
      ]);
      failBase(const RateLimitException('r'));
      final r = await backfill(withLedger: ledger);
      expect(r.rows, 2);
      expect(r.basePrice.rateLimited, isTrue);
      expect(r.basePrice.reason, '限流');
      expect(r.basePrice.withheld, isTrue);
      expect(r.basePrice.shouldRecordError, isFalse);
      expect(r.basePrice.error, isA<RateLimitException>());
      expect(ledger.recorded, isEmpty);
    });

    test('Review Focus 5：X 列不在清單（fetched／N>0）→ 回報定案、withheld=false', () async {
      stubHist([
        p('9901', close: 2380, change: null),
        p('9902', close: 10, change: 0.5),
      ]);
      stubBase({'9902': 9.5});
      final r = await backfill(withLedger: ledger);
      expect(r.basePrice.fetch, BasePriceFetch.fetched);
      expect(r.basePrice.missing, 1);
      expect(r.basePrice.withheld, isFalse);
      expect((await price('9901')).priceChange, isNull);
      expect(ledger.recorded, hasLength(1));
    });

    test('需要的列一列都不在清單（含回空 Map）→ 視同 failed、不回報', () async {
      stubHist([
        p('9901', close: 2380, change: null),
        p('9902', close: 10, change: 0.5),
      ]);
      stubBase({});
      final r = await backfill(withLedger: ledger);
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.missing, 1);
      expect(r.basePrice.withheld, isTrue);
      expect(ledger.recorded, isEmpty);
    });

    test('漲跌是非 0 數字的列不需要平盤價：清單沒有這檔也不影響 N、照常回報', () async {
      stubHist([
        p('9901', close: 10, change: 0.5),
        p('9902', close: 10, change: -0.5),
      ]);
      stubBase({'9902': 10.5});
      final r = await backfill(withLedger: ledger);
      expect(r.basePrice.fetch, BasePriceFetch.fetched);
      expect(r.basePrice.missing, 0);
      expect(r.basePrice.shouldRecordError, isFalse);
      expect(ledger.recorded, hasLength(1));
      expect((await price('9901')).basePrice, isNull);
      expect((await price('9902')).basePrice, 10.5);
    });

    test('清單整個對不上（空 Map）、但沒有需要的列 → failed／N=0、照常回報、不記 errors', () async {
      stubHist([
        p('9901', close: 10, change: 0.5),
        p('9902', close: 10, change: -0.5),
      ]);
      stubBase({});
      final r = await backfill(withLedger: ledger);
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.missing, 0);
      expect(r.basePrice.withheld, isFalse);
      expect(r.basePrice.shouldRecordError, isFalse);
      expect(ledger.recorded, hasLength(1));
    });

    test('價格本身限流／網路錯誤照舊拋', () async {
      when(
        () => twse.getAllDailyPricesHistorical(any()),
      ).thenThrow(const RateLimitException('r'));
      await expectLater(backfill(), throwsA(isA<RateLimitException>()));
      when(
        () => twse.getAllDailyPricesHistorical(any()),
      ).thenThrow(const NetworkException('n'));
      await expectLater(backfill(), throwsA(isA<NetworkException>()));
    });

    test(
      'withBasePrices=false → 不打 TWT84U、skipped；與 ledger 同時傳 → assert',
      () async {
        stubHist([
          p('9901', close: 2380, change: null),
          p('9902', close: 10, change: 0.5),
        ]);
        final r = await backfill(withBasePrices: false);
        verifyNever(() => twse.getOpeningBasePrices(any()));
        expect(r.basePrice.fetch, BasePriceFetch.skipped);
        expect((await price('9901')).priceChange, isNull);
        expect(
          () => backfill(withLedger: ledger, withBasePrices: false),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('請求順序：先價格、等 basePriceDelay、再 TWT84U', () async {
      final slow = PriceRepository(
        database: db,
        finMindClient: MockFinMindClient(),
        twseClient: twse,
        tpexClient: tpex,
        basePriceDelay: const Duration(milliseconds: 200),
      );
      final sw = Stopwatch()..start();
      int? tHist;
      int? tBase;
      when(() => twse.getAllDailyPricesHistorical(any())).thenAnswer((_) async {
        tHist = sw.elapsedMilliseconds;
        return [
          p('9901', close: 2380, change: null),
          p('9902', close: 10, change: 0.5),
        ];
      });
      when(() => twse.getOpeningBasePrices(any())).thenAnswer((_) async {
        tBase = sw.elapsedMilliseconds;
        return {'9901': 2385};
      });
      await slow.backfillTwsePricesByDate(
        date: day,
        targetSymbols: {'9901', '9902'},
      );
      expect(tHist, isNotNull);
      expect(tBase, isNotNull);
      expect(
        tBase! - tHist!,
        greaterThanOrEqualTo(200),
        reason: 'delay 要夾在價格請求與 TWT84U 之間，不是放在價格之前',
      );
      verifyInOrder([
        () => twse.getAllDailyPricesHistorical(any()),
        () => twse.getOpeningBasePrices(day),
      ]);
    });
  });

  group('syncAllPricesForDate 上市半邊（STOCK_DAY_ALL）', () {
    test(
      '🚨 0 列拿到平盤價 → 第 1 條；非 0 列照來源；回報定案；basePrices[TWSE] fetched',
      () async {
        stubDaily([
          p('9901', close: 2380, change: 0),
          p('9902', close: 10, change: 0.5),
        ]);
        stubBase({'9901': 2385, '9902': 9.5});
        final r = await repo.syncAllPricesForDate(day, ledger: ledger);
        expect(r.count, 2);
        final s = r.basePrices[MarketCode.twse]!;
        expect(s.fetch, BasePriceFetch.fetched);
        expect(s.missing, 0);
        expect((await price('9901')).priceChange, -5.0);
        expect((await price('9902')).priceChange, 0.5);
        expect(ledger.recorded.map((e) => e.market), [MarketCode.twse]);
      },
    );

    test('🚨 平盤價失敗 → 0 列存空值（不是 0）、非 0 列照來源、withheld、不回報', () async {
      stubDaily([
        p('9901', close: 2380, change: 0),
        p('9902', close: 10, change: 0.5),
      ]);
      failBase(const NetworkException('x'));
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      expect(r.count, 2, reason: '價格照寫');
      final s = r.basePrices[MarketCode.twse]!;
      expect(s.fetch, BasePriceFetch.failed);
      expect(s.missing, 1);
      expect(s.withheld, isTrue);
      expect(s.shouldRecordError, isTrue);
      expect((await price('9901')).priceChange, isNull);
      expect((await price('9902')).priceChange, 0.5);
      expect(ledger.recorded, isEmpty);
    });

    test('Review Focus 5 例外二：0 列不在清單（fetched／N>0）→ 不回報（交給 MI_INDEX）', () async {
      stubDaily([
        p('9901', close: 2380, change: 0),
        p('9902', close: 10, change: 0.5),
      ]);
      stubBase({'9902': 9.5});
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      final s = r.basePrices[MarketCode.twse]!;
      expect(s.fetch, BasePriceFetch.fetched);
      expect(s.missing, 1);
      expect(s.withheld, isTrue);
      expect(s.shouldRecordError, isTrue);
      expect((await price('9901')).priceChange, isNull);
      expect(ledger.recorded, isEmpty);
    });

    test('21:30 重寫：先前已有平盤價、這次 TWT84U 失敗 → 用新收盤重算、N=0、回報', () async {
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: day,
          close: const Value(2370),
          basePrice: const Value(2385),
        ),
      ]);
      stubDaily([
        p('9901', close: 2380, change: 0),
        p('9902', close: 10, change: 0.5),
      ]);
      failBase(const NetworkException('x'));
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      final s = r.basePrices[MarketCode.twse]!;
      expect(s.fetch, BasePriceFetch.failed);
      expect(s.missing, 0);
      expect(s.withheld, isFalse);
      expect((await price('9901')).priceChange, -5.0);
      expect(ledger.recorded, hasLength(1));
    });

    test('以 STOCK_DAY_ALL 回應的資料日抓 TWT84U（端點還是前一天時抓前一天）', () async {
      stubDaily([
        p('9901', date: prevDay, close: 2380, change: 0),
        p('9902', date: prevDay, close: 10, change: 0.5),
      ]);
      stubBase({'9901': 2385});
      await repo.syncAllPricesForDate(day);
      verify(() => twse.getOpeningBasePrices(prevDay)).called(1);
      expect((await price('9901', prevDay)).priceChange, -5.0);
    });

    test('已定案跳過／兩市場皆空 → basePrices 為空 Map', () async {
      for (final m in [MarketCode.twse, MarketCode.tpex]) {
        await db.upsertMarketDayFetch(
          dataset: MarketDataset.prices.code,
          market: m,
          date: day,
          fetchedAt: DateTime(2026, 9, 17),
          rowCount: 2,
        );
      }
      final skipped = await repo.syncAllPricesForDate(day);
      expect(skipped.skipped, isTrue);
      expect(skipped.basePrices, isEmpty);

      final db2 = AppDatabase.forTesting();
      addTearDown(db2.close);
      final repo2 = PriceRepository(
        database: db2,
        finMindClient: MockFinMindClient(),
        twseClient: twse,
        tpexClient: tpex,
        basePriceDelay: Duration.zero,
      );
      stubDaily([]);
      final empty = await repo2.syncAllPricesForDate(day);
      expect(empty.count, 0);
      expect(empty.basePrices, isEmpty);
      verifyNever(() => twse.getOpeningBasePrices(any()));
    });
  });

  group('syncStockPrices（上市 STOCK_DAY 月資料）', () {
    test('🚨 覆寫已有平盤價的列：X0.00 不會洗掉正確值（驗證第 4 點）', () async {
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '9901',
          date: day,
          close: const Value(2380),
          basePrice: const Value(2385),
        ),
      ]);
      expect((await price('9901')).priceChange, -5.0, reason: '前提');
      when(
        () => twse.getStockMonthlyPrices(code: '9901', year: 2026, month: 9),
      ).thenAnswer((_) async => [p('9901', close: 2380, change: null)]);
      await repo.syncStockPrices(
        '9901',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 30),
      );
      verify(
        () => twse.getStockMonthlyPrices(code: '9901', year: 2026, month: 9),
      ).called(1);
      final a = await price('9901');
      expect((a.priceChange, a.basePrice), (-5.0, 2385.0));
    });
  });
}

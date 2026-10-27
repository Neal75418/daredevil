// 上櫃市場日寫入帶平盤價（除權息漲跌修正 spec 第 3 節）
//
// 上櫃只在這批有文字標記（除息／除權／除權息）的列時，才抓 exDailyQ 單日的
// 「開始交易基準價」；需要的列一列都對不上（含回空清單）視同抓取失敗
// （例外一）。兩市場的狀態各自獨立。真 in-memory DB、mock client。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
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
  late MockFinMindClient finMind;
  late PriceRepository repo;
  late MarketDayFetchLedger ledger;
  final day = DateContext.normalize(DateTime(2026, 10, 27));
  final otherDay = DateContext.normalize(DateTime(2026, 10, 22));

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  TpexDailyPrice tp(
    String code, {
    DateTime? date,
    double? close,
    double? change,
    bool noComparison = false,
  }) => TpexDailyPrice(
    date: date ?? day,
    code: code,
    name: code,
    open: close,
    high: close,
    low: close,
    close: close,
    volume: 1000,
    change: change,
    noComparison: noComparison,
  );

  TwseDailyPrice tw(String code, {double? close, double? change}) =>
      TwseDailyPrice(
        date: day,
        code: code,
        name: code,
        open: close,
        high: close,
        low: close,
        close: close,
        volume: 1000,
        change: change,
      );

  ExRightResult ex(String code, DateTime exDate, {double? base}) =>
      ExRightResult(
        symbol: code,
        exDate: exDate,
        cashDividend: 1,
        stockSharesPerThousand: 0,
        tradingBasePrice: base,
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9911', '9912'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.tpex,
        ),
      for (final s in ['9901', '9902'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.twse,
        ),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    finMind = MockFinMindClient();
    when(
      () => twse.getAllDailyPrices(date: any(named: 'date')),
    ).thenAnswer((_) async => []);
    when(
      () => twse.getAllDailyPricesHistorical(any()),
    ).thenAnswer((_) async => []);
    when(() => twse.getOpeningBasePrices(any())).thenAnswer((_) async => {});
    when(
      () => tpex.getAllDailyPrices(date: any(named: 'date')),
    ).thenAnswer((_) async => []);
    repo = PriceRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
      tpexClient: tpex,
      basePriceDelay: Duration.zero,
    );
    ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 10, 28, 9),
    );
  });

  tearDown(() => db.close());

  void stubHist(List<TpexDailyPrice> rows) => when(
    () => tpex.getAllDailyPricesHistorical(any()),
  ).thenAnswer((_) async => rows);
  void stubDaily(List<TpexDailyPrice> rows) => when(
    () => tpex.getAllDailyPrices(date: any(named: 'date')),
  ).thenAnswer((_) async => rows);
  void stubEx(List<ExRightResult> rows) => when(
    () => tpex.getExRightResults(
      startDate: any(named: 'startDate'),
      endDate: any(named: 'endDate'),
    ),
  ).thenAnswer((_) async => rows);
  void failEx(Object e) => when(
    () => tpex.getExRightResults(
      startDate: any(named: 'startDate'),
      endDate: any(named: 'endDate'),
    ),
  ).thenThrow(e);
  Future<DailyPriceEntry> price(String symbol) async =>
      (await db.getPriceHistory(symbol, startDate: day, endDate: day)).single;
  Future<MarketDayBackfillResult> backfill() => repo.backfillTpexPricesByDate(
    date: day,
    targetSymbols: {'9911', '9912'},
    ledger: ledger,
  );
  void verifyNoExRight() => verifyNever(
    () => tpex.getExRightResults(
      startDate: any(named: 'startDate'),
      endDate: any(named: 'endDate'),
    ),
  );

  group('backfillTpexPricesByDate', () {
    test('🚨 有文字標記 → 抓 exDailyQ 單日、漲跌＝收盤−開始交易基準價、回報', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 814, change: -12),
      ]);
      stubEx([ex('9911', day, base: 32.44)]);
      final r = await backfill();
      expect(r.rows, 2);
      expect(r.basePrice.fetch, BasePriceFetch.fetched);
      expect(r.basePrice.missing, 0);
      final a = await price('9911');
      expect((a.priceChange, a.basePrice), (-0.32, 32.44));
      expect((await price('9912')).priceChange, -12);
      verify(
        () => tpex.getExRightResults(startDate: day, endDate: day),
      ).called(1);
      expect(ledger.recorded.single.market, MarketCode.tpex);
    });

    test('沒有文字標記 → 不打 exDailyQ、notNeeded、回報', () async {
      stubHist([
        tp('9911', close: 10, change: 0.5),
        tp('9912', close: 10, change: null),
      ]);
      final r = await backfill();
      verifyNoExRight();
      expect(r.basePrice.fetch, BasePriceFetch.notNeeded);
      expect(r.basePrice.shouldRecordError, isFalse);
      expect(ledger.recorded, hasLength(1));
    });

    test(
      '不比價以 targetSymbols 過濾後的列判斷：唯一的文字標記列不在 targetSymbols → notNeeded',
      () async {
        stubHist([
          tp('9913', close: 10, noComparison: true),
          tp('9911', close: 10, change: 0.5),
          tp('9912', close: 10, change: 0.5),
        ]);
        final r = await backfill();
        verifyNoExRight();
        expect(r.basePrice.fetch, BasePriceFetch.notNeeded);
        expect(r.rows, 2);
      },
    );

    test('例外一：有文字標記、exDailyQ 回空清單 → failed、不回報', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      stubEx([]);
      final r = await backfill();
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.reason, startsWith('清單整個對不上'));
      expect(r.basePrice.missing, 1);
      expect(r.basePrice.withheld, isTrue);
      expect(r.basePrice.shouldRecordError, isTrue);
      expect((await price('9911')).priceChange, isNull);
      expect(ledger.recorded, isEmpty);
    });

    test('例外一：回了別檔、需要的一列都對不上 → failed、不回報', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      stubEx([ex('9999', day, base: 5)]);
      final r = await backfill();
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.reason, startsWith('清單整個對不上'));
      expect(r.basePrice.withheld, isTrue);
      expect(ledger.recorded, isEmpty);
    });

    test('部分對上（清單不全）→ fetched／N>0、回報、不記 errors', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 119.5, noComparison: true),
      ]);
      stubEx([ex('9911', day, base: 32.44)]);
      final r = await backfill();
      expect(r.basePrice.fetch, BasePriceFetch.fetched);
      expect(r.basePrice.missing, 1);
      expect(r.basePrice.withheld, isFalse);
      expect(r.basePrice.shouldRecordError, isFalse);
      expect((await price('9911')).priceChange, -0.32);
      expect((await price('9912')).priceChange, isNull);
      expect(ledger.recorded, hasLength(1));
    });

    test('exDailyQ 限流 → rateLimited、不拋、N>0 不回報', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      failEx(const RateLimitException('r'));
      final r = await backfill();
      expect(r.rows, 2);
      expect(r.basePrice.rateLimited, isTrue);
      expect(r.basePrice.error, isA<RateLimitException>());
      expect(r.basePrice.withheld, isTrue);
      expect(ledger.recorded, isEmpty);
    });

    test('exDailyQ 網路錯誤 → failed、不拋', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      failEx(const NetworkException('n'));
      final r = await backfill();
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.shouldRecordError, isTrue);
    });

    test('tradingBasePrice 為 null 的列不算對上（部分對上的形狀：拔掉過濾會變 failed）', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 119.5, noComparison: true),
      ]);
      stubEx([ex('9911', day, base: null), ex('9912', day, base: 109)]);
      final r = await backfill();
      expect(r.basePrice.fetch, BasePriceFetch.fetched);
      expect(r.basePrice.missing, 1);
      expect((await price('9911')).basePrice, isNull);
      expect((await price('9912')).priceChange, 10.5);
    });

    test('exDate 不是這一天的列不算對上（走共用的 coverage 判斷）', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      stubEx([ex('9911', otherDay, base: 33.94)]);
      final r = await backfill();
      expect(r.basePrice.fetch, BasePriceFetch.failed);
      expect(r.basePrice.reason, startsWith('清單整個對不上'));
      expect((await price('9911')).basePrice, isNull);
    });

    test('withBasePrices=false → 不打 exDailyQ、skipped', () async {
      stubHist([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      final r = await repo.backfillTpexPricesByDate(
        date: day,
        targetSymbols: {'9911', '9912'},
        withBasePrices: false,
      );
      verifyNoExRight();
      expect(r.basePrice.fetch, BasePriceFetch.skipped);
    });
  });

  group('syncAllPricesForDate 兩市場', () {
    test('🚨 Review Focus 1：上市平盤價失敗、上櫃成功 → 只有上櫃回報；兩個狀態各自獨立', () async {
      when(() => twse.getAllDailyPrices(date: any(named: 'date'))).thenAnswer(
        (_) async => [
          tw('9901', close: 2380, change: 0),
          tw('9902', close: 10, change: 0.5),
        ],
      );
      when(
        () => twse.getOpeningBasePrices(any()),
      ).thenThrow(const NetworkException('x'));
      stubDaily([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      stubEx([ex('9911', day, base: 32.44)]);
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      expect(r.count, 4);
      expect(r.basePrices[MarketCode.twse]!.withheld, isTrue);
      expect(r.basePrices[MarketCode.tpex]!.fetch, BasePriceFetch.fetched);
      expect(r.basePrices[MarketCode.tpex]!.withheld, isFalse);
      expect(ledger.recorded.map((e) => e.market), [MarketCode.tpex]);
      expect((await price('9901')).priceChange, isNull);
      expect((await price('9911')).priceChange, -0.32);
    });

    test(
      '🚨 Review Focus 4：上市 fetched、上櫃 exDailyQ 限流 → TPEx rateLimited、上市照常回報、函式不拋',
      () async {
        when(() => twse.getAllDailyPrices(date: any(named: 'date'))).thenAnswer(
          (_) async => [
            tw('9901', close: 2380, change: 0),
            tw('9902', close: 10, change: 0.5),
          ],
        );
        when(
          () => twse.getOpeningBasePrices(any()),
        ).thenAnswer((_) async => {'9901': 2385, '9902': 9.5});
        stubDaily([
          tp('9911', close: 32.12, noComparison: true),
          tp('9912', close: 10, change: 0.5),
        ]);
        failEx(const RateLimitException('r'));
        final r = await repo.syncAllPricesForDate(day, ledger: ledger);
        expect(r.count, 4);
        expect(r.basePrices[MarketCode.twse]!.fetch, BasePriceFetch.fetched);
        expect(r.basePrices[MarketCode.tpex]!.rateLimited, isTrue);
        expect(ledger.recorded.map((e) => e.market), [MarketCode.twse]);
        expect((await price('9901')).priceChange, -5.0);
      },
    );

    test('每日路徑：上櫃沒有文字標記 → 不打 exDailyQ、notNeeded', () async {
      stubDaily([
        tp('9911', close: 10, change: 0.5),
        tp('9912', close: 10, change: null),
      ]);
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      verifyNoExRight();
      expect(r.basePrices[MarketCode.tpex]!.fetch, BasePriceFetch.notNeeded);
      expect(ledger.recorded.map((e) => e.market), [MarketCode.tpex]);
    });

    test('🚨 以上櫃回應的資料日抓 exDailyQ（端點還是前一天時抓前一天，不是請求日）', () async {
      stubDaily([
        tp('9911', date: otherDay, close: 32.12, noComparison: true),
        tp('9912', date: otherDay, close: 10, change: 0.5),
      ]);
      stubEx([ex('9911', otherDay, base: 32.44)]);
      await repo.syncAllPricesForDate(day);
      verify(
        () => tpex.getExRightResults(startDate: otherDay, endDate: otherDay),
      ).called(1);
      final a = (await db.getPriceHistory(
        '9911',
        startDate: otherDay,
        endDate: otherDay,
      )).single;
      expect((a.priceChange, a.basePrice), (-0.32, 32.44));
    });

    test('每日路徑：例外一（exDailyQ 回空）→ failed、上櫃不回報', () async {
      stubDaily([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 10, change: 0.5),
      ]);
      stubEx([]);
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      final s = r.basePrices[MarketCode.tpex]!;
      expect(s.fetch, BasePriceFetch.failed);
      expect(s.withheld, isTrue);
      expect(
        ledger.recorded.where((e) => e.market == MarketCode.tpex),
        isEmpty,
      );
    });

    test('每日路徑：部分對上 → fetched／N>0、withheld=false（上櫃沒有例外二）、上櫃回報', () async {
      stubDaily([
        tp('9911', close: 32.12, noComparison: true),
        tp('9912', close: 119.5, noComparison: true),
      ]);
      stubEx([ex('9911', day, base: 32.44)]);
      final r = await repo.syncAllPricesForDate(day, ledger: ledger);
      final s = r.basePrices[MarketCode.tpex]!;
      expect(s.fetch, BasePriceFetch.fetched);
      expect(s.missing, 1);
      expect(s.withheld, isFalse);
      expect(ledger.recorded.map((e) => e.market), contains(MarketCode.tpex));
    });
  });

  group('syncStockPrices（上櫃 FinMind，沒帶漲跌欄）', () {
    FinMindDailyPrice fm(double close) => FinMindDailyPrice(
      stockId: '9911',
      date: '2026-10-27',
      open: close,
      high: close,
      low: close,
      close: close,
      volume: 1000,
    );

    Future<void> seed() => db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '9911',
        date: day,
        close: const Value(32.12),
        basePrice: const Value(32.44),
      ),
    ]);

    test('🚨 覆寫已有平盤價的列：收盤沒變 → 正確值不變（驗證第 4 點）', () async {
      await seed();
      when(
        () => finMind.getDailyPrices(
          stockId: '9911',
          startDate: '2026-10-01',
          endDate: '2026-10-31',
        ),
      ).thenAnswer((_) async => [fm(32.12)]);
      await repo.syncStockPrices(
        '9911',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );
      final a = await price('9911');
      expect((a.priceChange, a.basePrice), (-0.32, 32.44));
    });

    test('收盤變了 → 用保留的平盤價與新收盤重算', () async {
      await seed();
      when(
        () => finMind.getDailyPrices(
          stockId: '9911',
          startDate: '2026-10-01',
          endDate: '2026-10-31',
        ),
      ).thenAnswer((_) async => [fm(32.5)]);
      await repo.syncStockPrices(
        '9911',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );
      final a = await price('9911');
      expect((a.priceChange, a.basePrice), (0.06, 32.44));
    });
  });
}

// 除權除息歷史回補（DividendBackfiller）
//
// 由新到舊、同月先上櫃；每個（市場, 月）：列表 → 空月與範圍檢查 → 上櫃整月
// 在完成交易內寫入／上市息列先寫、權與權息列逐筆查明細（核對參考價）→
// completeDividendMonth 核對預期列都在庫後才記完成。失敗記進失敗紀錄（退避
// 用），網路錯誤只停該市場、不累積；限流整輪停止。
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update/dividend_backfiller.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockAppDatabase extends Mock implements AppDatabase {}

const aug = CalendarMonth(2026, 8);
const jul = CalendarMonth(2026, 7);

ExRightResult _cash(String symbol, DateTime exDate, double cash) =>
    ExRightResult(
      symbol: symbol,
      exDate: exDate,
      cashDividend: cash,
      stockSharesPerThousand: 0,
      closeBefore: 100,
      referencePrice: 100 - cash,
    );

/// 權息列（2836 2021-01-13 的真實數字：前收 10.60、減除股利參考價 10.00，
/// 明細 0.15 元／45 股；沒有現金增資，除權息參考價同為 10.00）
ExRightResult _rightsAndCash(String symbol, DateTime exDate) => ExRightResult(
  symbol: symbol,
  exDate: exDate,
  cashDividend: null,
  stockSharesPerThousand: null,
  closeBefore: 10.60,
  referencePrice: 10.00,
  dividendAdjustedReference: 10.00,
);

/// 只有現金增資的權列（前收＝減除股利參考價，明細 0 元／0 股；除權息
/// 參考價反映增資，低於前收）
ExRightResult _rightsIssue(String symbol, DateTime exDate) => ExRightResult(
  symbol: symbol,
  exDate: exDate,
  cashDividend: 0,
  stockSharesPerThousand: null,
  closeBefore: 25.20,
  referencePrice: 24.80,
  dividendAdjustedReference: 25.20,
);

const _detailOk = ExRightDetail(
  symbol: '',
  cashDividend: 0.15,
  stockSharesPerThousand: 45,
);

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  final now = DateTime(2026, 9, 29, 15, 30);

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(<DividendDistributionCompanion>[]);
    registerFallbackValue(<DividendListedPrice>[]);
    registerFallbackValue(<(String, DateTime)>{});
    registerFallbackValue(<(String, DateTime), DividendUnresolvedReason>{});
    registerFallbackValue(const CalendarMonth(2000, 1));
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final (symbol, market) in [
        ('2330', 'TWSE'),
        ('2836', 'TWSE'),
        ('4108', 'TWSE'),
        ('6488', 'TPEx'),
        ('6762', 'TPEx'),
      ])
        StockMasterCompanion.insert(
          symbol: symbol,
          name: symbol,
          market: market,
        ),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
  });

  tearDown(() => db.close());

  DividendBackfiller backfiller({
    TwseClient? twseClient,
    TpexClient? tpexClient,
    bool noTpex = false,
    int minStocks = 1,
    AppDatabase? database,
  }) => DividendBackfiller(
    database: database ?? db,
    twseClient: twseClient ?? twse,
    tpexClient: noTpex ? null : (tpexClient ?? tpex),
    callDelay: Duration.zero,
    minActiveStocksPerMarket: minStocks,
  );

  void listTpex(CalendarMonth m, List<ExRightResult> rows) => when(
    () => tpex.getExRightResults(startDate: m.firstDay, endDate: m.lastDay),
  ).thenAnswer((_) async => rows);

  void listTwse(CalendarMonth m, List<ExRightResult> rows) => when(
    () => twse.getExRightResults(startDate: m.firstDay, endDate: m.lastDay),
  ).thenAnswer((_) async => rows);

  void detail(String symbol, ExRightDetail d) =>
      when(() => twse.getExRightDetail(symbol, any())).thenAnswer(
        (_) async => ExRightDetail(
          symbol: symbol,
          cashDividend: d.cashDividend,
          stockSharesPerThousand: d.stockSharesPerThousand,
        ),
      );

  /// 8 月、7 月兩市場都有一列可完成的資料
  void stubHealthyMonths() {
    for (final m in [aug, jul]) {
      listTpex(m, [_cash('6488', DateTime(m.year, m.month, 10), 3)]);
      listTwse(m, [_cash('2330', DateTime(m.year, m.month, 12), 5)]);
    }
  }

  Future<DividendBackfillSummary> run({
    int maxCalls = 30,
    DividendBackfillScope scope = const DividendBackfillScope(
      from: jul,
      to: aug,
    ),
    DividendBackfiller? b,
    DateTime? at,
  }) => (b ?? backfiller()).backfill(
    now: at ?? now,
    maxCalls: maxCalls,
    scope: scope,
  );

  Future<Set<String>> ledgerKeys() async => {
    for (final e in await db.getDividendMonthLedgerEntries())
      '${e.market} ${e.calendarMonth}',
  };

  Future<Map<String, DividendMonthFailureEntry>> failures() async => {
    for (final f in await db.getDividendMonthFailures())
      '${f.market} ${f.calendarMonth}': f,
  };

  group('順序與完成', () {
    test('由新到舊、同月先上櫃', () async {
      stubHealthyMonths();

      final summary = await run();

      verifyInOrder([
        () => tpex.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
        () => tpex.getExRightResults(
          startDate: jul.firstDay,
          endDate: jul.lastDay,
        ),
        () => twse.getExRightResults(
          startDate: jul.firstDay,
          endDate: jul.lastDay,
        ),
      ]);
      expect(summary.completed, hasLength(4));
      expect(summary.calls, 4);
      expect(await ledgerKeys(), {
        'TPEx 2026-08',
        'TWSE 2026-08',
        'TPEx 2026-07',
        'TWSE 2026-07',
      });
    });

    test('上櫃：已知代號整月寫入，不在主檔的略過並記在完成紀錄', () async {
      listTpex(aug, [
        _cash('6488', DateTime(2026, 8, 10), 3),
        _cash('00950B', DateTime(2026, 8, 11), 0.08),
        _cash('00950B', DateTime(2026, 8, 20), 0.08),
      ]);

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.tpex},
        ),
      );

      final ledger = (await db.getDividendMonthLedgerEntries()).single;
      expect(ledger.listedRows, 3);
      expect(ledger.knownRows, 1);
      expect(ledger.skippedSymbolSet, {'00950B'});
      expect(await db.getDividendDistributions('6488'), hasLength(1));
    });

    test('上市：息列直接寫、權息與權列查明細；只有現金增資的列存成 0', () async {
      listTwse(aug, [
        _cash('2330', DateTime(2026, 8, 12), 5),
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsIssue('4108', DateTime(2026, 8, 14)),
      ]);
      detail('2836', _detailOk);
      detail(
        '4108',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0,
          stockSharesPerThousand: 0,
        ),
      );

      final summary = await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(summary.completed, [(market: MarketCode.twse, month: aug)]);
      expect(summary.calls, 3);
      final ledger = (await db.getDividendMonthLedgerEntries()).single;
      expect(ledger.knownRows, 3);
      final rows = await db.getDividendDistributionsBatch(['2836', '4108']);
      expect(rows['2836']!.single.stockSharesPerThousand, 45);
      expect(rows.containsKey('4108'), isFalse, reason: '0 列不回給讀取端');
      expect(
        await db.getDividendDistributionKeys(
          from: aug.firstDay,
          to: aug.lastDay,
        ),
        hasLength(3),
      );
    });

    test('DB 已有的權息列不再查明細，該月照樣完成', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2836',
          exDate: DateTime(2026, 8, 13),
          cashDividend: 0.15,
          stockSharesPerThousand: 45,
        ),
      ]);
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);

      final summary = await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      verifyNever(() => twse.getExRightDetail(any(), any()));
      verify(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).called(1);
      expect(summary.completed, hasLength(1));
    });

    test('列表有列但全不在主檔：記為完成，已知列數 0', () async {
      listTpex(aug, [_cash('00950B', DateTime(2026, 8, 11), 0.08)]);

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.tpex},
        ),
      );

      expect((await db.getDividendMonthLedgerEntries()).single.knownRows, 0);
    });
  });

  group('列表檢查', () {
    for (final market in dividendMarkets) {
      test('$market 過去整月 0 列：記失敗、不記完成，繼續下一個單位', () async {
        stubHealthyMonths();
        if (market == MarketCode.tpex) {
          listTpex(aug, const []);
        } else {
          listTwse(aug, const []);
        }

        final summary = await run();

        final f = (await failures())['$market 2026-08']!;
        expect(f.failCount, 1);
        expect(f.listOk, isFalse);
        expect(await ledgerKeys(), isNot(contains('$market 2026-08')));
        expect(summary.completed, hasLength(3));
      });
    }

    test('任一列日期不在請求月份：不寫任何列、記失敗', () async {
      listTwse(aug, [
        _cash('2330', DateTime(2026, 8, 12), 5),
        _cash('2836', DateTime(2026, 9, 1), 1),
      ]);

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(
        await db.getDividendDistributionKeys(
          from: DateTime(2026),
          to: DateTime(2027),
        ),
        isEmpty,
      );
      expect((await failures())['TWSE 2026-08']!.failCount, 1);
    });

    test('列表不可信（ApiException）：記失敗（列表失敗）', () async {
      when(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).thenThrow(const ApiException('TWSE 除權除息計算結果: 回應不可信', 200));

      final summary = await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      final f = (await failures())['TWSE 2026-08']!;
      expect(f.listOk, isFalse);
      expect(f.lastError, contains('回應不可信'));
      expect(summary.failures.single.key, (
        market: MarketCode.twse,
        month: aug,
      ));
    });
  });

  group('明細', () {
    test('單筆明細失敗：其他列照寫，不記完成，失敗紀錄帶代號與列表成功', () async {
      listTwse(aug, [
        _cash('2330', DateTime(2026, 8, 12), 5),
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsIssue('4108', DateTime(2026, 8, 14)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('TWSE 除權除息明細: 回應不可信', 200));
      detail(
        '4108',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0,
          stockSharesPerThousand: 0,
        ),
      );

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await ledgerKeys(), isEmpty);
      final f = (await failures())['TWSE 2026-08']!;
      expect(f.failedSymbolSet, {'2836'});
      expect(f.listOk, isTrue);
      expect(
        await db.getDividendDistributionKeys(
          from: aug.firstDay,
          to: aug.lastDay,
        ),
        {('2330', DateTime(2026, 8, 12)), ('4108', DateTime(2026, 8, 14))},
      );
    });

    test('明細推算的參考價與列表不符：當成明細失敗，不寫該列', () async {
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);
      // (10.60 − 0.5) ÷ 1 = 10.10，與列表的 10.00 不符
      detail(
        '2836',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0.5,
          stockSharesPerThousand: 0,
        ),
      );

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect((await failures())['TWSE 2026-08']!.failedSymbolSet, {'2836'});
      expect(await db.getDividendDistributions('2836'), isEmpty);
    });

    test('🚨 recheck 發現 DB 舊列與明細不符：刪掉舊列，下一輪正常回補重查、不直接記完成', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2836',
          exDate: DateTime(2026, 8, 13),
          cashDividend: 0.5,
          stockSharesPerThousand: 0,
        ),
      ]);
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);
      // (10.60 − 0.5) ÷ 1 = 10.10，與列表的 10.00 不符
      detail(
        '2836',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0.5,
          stockSharesPerThousand: 0,
        ),
      );
      const scope = DividendBackfillScope(
        from: aug,
        to: aug,
        markets: {MarketCode.twse},
      );

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
          recheck: true,
        ),
      );
      expect(await db.getDividendDistributions('2836'), isEmpty);

      await run(scope: scope);
      verify(() => twse.getExRightDetail('2836', any())).called(2);
      expect(await ledgerKeys(), isEmpty);
      expect((await failures())['TWSE 2026-08']!.failCount, 2);
    });

    test('核對失敗（寫入後資料不見）：記失敗、不記完成；下一輪重列表後完成', () async {
      listTwse(aug, [
        _cash('2330', DateTime(2026, 8, 12), 5),
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
      ]);
      var first = true;
      when(() => twse.getExRightDetail('2836', any())).thenAnswer((_) async {
        if (first) {
          first = false;
          // 模擬另一個行程在寫列與寫完成紀錄之間清掉了息列
          await db.customStatement(
            "DELETE FROM dividend_distribution WHERE symbol = '2330'",
          );
        }
        return const ExRightDetail(
          symbol: '2836',
          cashDividend: 0.15,
          stockSharesPerThousand: 45,
        );
      });
      const scope = DividendBackfillScope(
        from: aug,
        to: aug,
        markets: {MarketCode.twse},
      );

      final summary = await run(scope: scope);
      expect(await ledgerKeys(), isEmpty);
      expect(summary.failures.single.error, contains('2330'));

      await run(scope: scope);
      expect(await ledgerKeys(), {'TWSE 2026-08'});
    });
  });

  group('預算', () {
    test('上限 0：一次都不打，仍回傳完整度', () async {
      stubHealthyMonths();

      final summary = await run(maxCalls: 0);

      expect(summary.calls, 0);
      verifyZeroInteractions(tpex);
      verifyZeroInteractions(twse);
      expect(summary.coverage.unitCount(from: jul, to: aug), 4);
      expect(summary.stoppedAt, (market: MarketCode.tpex, month: aug));
    });

    test('上限 1：只完成上櫃 8 月，停在上市 8 月', () async {
      stubHealthyMonths();

      final summary = await run(maxCalls: 1);

      expect(await ledgerKeys(), {'TPEx 2026-08'});
      expect(summary.stoppedAt, (market: MarketCode.twse, month: aug));
    });

    test('上市月中途用完：息列與已查明細保留、沒有完成與失敗；下一輪只查剩下的', () async {
      listTwse(aug, [
        _cash('2330', DateTime(2026, 8, 12), 5),
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsIssue('4108', DateTime(2026, 8, 14)),
      ]);
      detail('2836', _detailOk);
      detail(
        '4108',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0,
          stockSharesPerThousand: 0,
        ),
      );
      const scope = DividendBackfillScope(
        from: aug,
        to: aug,
        markets: {MarketCode.twse},
      );

      final first = await run(maxCalls: 2, scope: scope);

      expect(first.calls, 2);
      expect(await ledgerKeys(), isEmpty);
      expect(await failures(), isEmpty);
      expect(
        await db.getDividendDistributionKeys(
          from: aug.firstDay,
          to: aug.lastDay,
        ),
        {('2330', DateTime(2026, 8, 12)), ('2836', DateTime(2026, 8, 13))},
      );

      await run(scope: scope);
      verify(() => twse.getExRightDetail('2836', any())).called(1);
      verify(() => twse.getExRightDetail('4108', any())).called(1);
      expect(await ledgerKeys(), {'TWSE 2026-08'});
    });
  });

  group('排程：完成、退避、重開', () {
    test('已完成的單位跳過；失敗 3 次且未滿 7 天的跳過；失敗 1 次的重試', () async {
      stubHealthyMonths();
      await db.completeDividendMonth(
        market: MarketCode.tpex,
        month: aug,
        rows: const [],
        expectedKeys: const {},
        listedRows: 1,
        skippedSymbols: const {},
        completedAt: now,
      );
      for (var i = 0; i < 3; i++) {
        await db.recordDividendMonthFailure(
          market: MarketCode.twse,
          month: aug,
          failedAt: now.subtract(const Duration(days: 1)),
          error: 'boom',
          listOk: false,
        );
      }
      await db.recordDividendMonthFailure(
        market: MarketCode.tpex,
        month: jul,
        failedAt: now.subtract(const Duration(days: 1)),
        error: 'boom',
        listOk: false,
      );

      await run();

      verifyNever(
        () => tpex.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      );
      verifyNever(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      );
      verify(
        () => tpex.getExRightResults(
          startDate: jul.firstDay,
          endDate: jul.lastDay,
        ),
      ).called(1);
      expect(await ledgerKeys(), contains('TPEx 2026-07'));
    });

    test('當時略過的代號進了主檔：該月重開並補上', () async {
      listTpex(aug, [
        _cash('6488', DateTime(2026, 8, 10), 3),
        _cash('00950B', DateTime(2026, 8, 11), 0.08),
      ]);
      const scope = DividendBackfillScope(
        from: aug,
        to: aug,
        markets: {MarketCode.tpex},
      );
      await run(scope: scope);
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '00950B',
          name: '債券 ETF',
          market: 'TPEx',
        ),
      ]);

      await run(scope: scope);

      verify(
        () => tpex.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).called(2);
      expect(await db.getDividendDistributions('00950B'), hasLength(1));
      final coverage = await loadDividendCoverage(db, now: now);
      expect(
        coverage.isMonthComplete((market: MarketCode.tpex, month: aug)),
        isTrue,
      );
    });

    test('recheck：已完成的月份重列表並重查明細，完成時間更新', () async {
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);
      detail('2836', _detailOk);
      const scope = DividendBackfillScope(
        from: aug,
        to: aug,
        markets: {MarketCode.twse},
      );
      await run(scope: scope);

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
          recheck: true,
        ),
        at: DateTime(2026, 9, 30, 21, 30),
      );

      verify(() => twse.getExRightDetail('2836', any())).called(2);
      expect(
        (await db.getDividendMonthLedgerEntries()).single.completedAt,
        DateTime(2026, 9, 30, 21, 30),
      );
    });

    test('ignoreBackoff：退避中的單位照樣處理', () async {
      listTwse(aug, [_cash('2330', DateTime(2026, 8, 12), 5)]);
      for (var i = 0; i < 3; i++) {
        await db.recordDividendMonthFailure(
          market: MarketCode.twse,
          month: aug,
          failedAt: now,
          error: 'boom',
          listOk: false,
        );
      }

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
          ignoreBackoff: true,
        ),
      );

      expect(await ledgerKeys(), {'TWSE 2026-08'});
    });
  });

  group('補價：2026-10 以前的完成紀錄', () {
    Future<void> legacyComplete(String market, CalendarMonth m) => db
        .into(db.dividendMonthLedger)
        .insert(
          DividendMonthLedgerCompanion.insert(
            market: market,
            year: m.year,
            month: m.month,
            completedAt: now,
            listedRows: 1,
            knownRows: 1,
            skippedSymbols: '',
          ),
        );

    const twseAug = DividendBackfillScope(
      from: aug,
      to: aug,
      markets: {MarketCode.twse},
    );
    const tpexAug = DividendBackfillScope(
      from: aug,
      to: aug,
      markets: {MarketCode.tpex},
    );

    test('上市：重開只打列表、不重查明細，已在庫列補上兩欄並記為已存價格', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2836',
          exDate: DateTime(2026, 8, 13),
          cashDividend: 0.15,
          stockSharesPerThousand: 45,
        ),
      ]);
      await legacyComplete(MarketCode.twse, aug);
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);

      final summary = await run(scope: twseAug);

      expect(summary.calls, 1);
      verifyNever(() => twse.getExRightDetail(any(), any()));
      final r = (await db.getDividendDistributions('2836')).single;
      expect(
        (r.cashDividend, r.closeBefore, r.referencePrice),
        (0.15, 10.60, 10.00),
      );
      expect(
        (await db.getDividendMonthLedgerEntries()).single.pricesRecorded,
        isTrue,
      );
    });

    test('上櫃：重開只打 1 次列表，列以列表值重寫並記為已存價格', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '6488',
          exDate: DateTime(2026, 8, 10),
          cashDividend: 3,
          stockSharesPerThousand: 0,
        ),
      ]);
      await legacyComplete(MarketCode.tpex, aug);
      listTpex(aug, [_cash('6488', DateTime(2026, 8, 10), 3)]);

      final summary = await run(scope: tpexAug);

      expect(summary.calls, 1);
      final r = (await db.getDividendDistributions('6488')).single;
      expect((r.closeBefore, r.referencePrice), (100.0, 97.0));
      expect(
        (await db.getDividendMonthLedgerEntries()).single.pricesRecorded,
        isTrue,
      );
    });

    test('重開過一次後不再重開（即使列表本身缺值）', () async {
      await legacyComplete(MarketCode.tpex, aug);
      listTpex(aug, [
        ExRightResult(
          symbol: '6488',
          exDate: DateTime(2026, 8, 10),
          cashDividend: 3,
          stockSharesPerThousand: 0,
        ),
      ]);

      await run(scope: tpexAug);
      await run(scope: tpexAug);

      verify(
        () => tpex.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).called(1);
    });
  });

  group('完整度事實', () {
    Future<Map<String, String>> unresolved() async => {
      for (final u in await db.getDividendUnresolved())
        '${u.market} ${u.symbol}': u.reason,
    };

    test('上櫃整月完成：只剩未知代號；列表日由完成紀錄推導、不另寫', () async {
      listTpex(aug, [
        _cash('6488', DateTime(2026, 8, 10), 3),
        _cash('00950B', DateTime(2026, 8, 11), 0.08),
      ]);

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.tpex},
        ),
      );

      expect(await unresolved(), {'TPEx 00950B': 'NOT_IN_MASTER'});
      expect(await db.getDividendListings(), isEmpty);
      expect(await ledgerKeys(), {'TPEx 2026-08'});
    });

    test('上市預算中途用完：已查的明細在庫，未查的記 pendingDetail，列表日記到月底', () async {
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsIssue('4108', DateTime(2026, 8, 14)),
      ]);
      detail('2836', _detailOk);

      await run(
        maxCalls: 2,
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await unresolved(), {'TWSE 4108': 'PENDING_DETAIL'});
      expect(
        (await db.getDividendListings()).single.listedThrough,
        aug.lastDay,
      );
    });

    test('上市明細失敗與參考價不符：各記原因', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '1101',
          name: '1101',
          market: 'TWSE',
        ),
      ]);
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsAndCash('1101', DateTime(2026, 8, 14)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('改版', 200));
      detail(
        '1101',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0.5,
          stockSharesPerThousand: 0,
        ),
      );

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await unresolved(), {
        'TWSE 2836': 'DETAIL_FAILED',
        'TWSE 1101': 'REFERENCE_MISMATCH',
      });
    });

    test('列表失敗：不記事實', () async {
      when(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).thenThrow(const ApiException('改版', 200));

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await db.getDividendListings(), isEmpty);
      expect(await db.getDividendUnresolved(), isEmpty);
    });
  });

  group('停止條件', () {
    test('斷路器：同一市場連續 3 次一般失敗停掉該市場，另一市場照常', () async {
      for (final m in [aug, jul, const CalendarMonth(2026, 6)]) {
        when(
          () =>
              twse.getExRightResults(startDate: m.firstDay, endDate: m.lastDay),
        ).thenThrow(const ApiException('改版', 200));
        listTpex(m, [_cash('6488', DateTime(m.year, m.month, 10), 3)]);
      }
      const may = CalendarMonth(2026, 5);
      listTpex(may, [_cash('6488', DateTime(2026, 5, 10), 3)]);
      listTwse(may, [_cash('2330', DateTime(2026, 5, 12), 5)]);

      final summary = await run(
        scope: const DividendBackfillScope(from: may, to: aug),
      );

      verifyNever(
        () => twse.getExRightResults(
          startDate: may.firstDay,
          endDate: may.lastDay,
        ),
      );
      verify(
        () => tpex.getExRightResults(
          startDate: may.firstDay,
          endDate: may.lastDay,
        ),
      ).called(1);
      expect(summary.marketStops[MarketCode.twse], contains('連續'));
    });

    test('斷路器：列表內容失敗（連續 3 個月 0 列）也計入', () async {
      const may = CalendarMonth(2026, 5);
      for (final m in [aug, jul, const CalendarMonth(2026, 6)]) {
        listTwse(m, const []);
      }
      listTwse(may, [_cash('2330', DateTime(2026, 5, 12), 5)]);

      final summary = await run(
        scope: const DividendBackfillScope(
          from: may,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      verifyNever(
        () => twse.getExRightResults(
          startDate: may.firstDay,
          endDate: may.lastDay,
        ),
      );
      expect(summary.marketStops[MarketCode.twse], contains('連續 3 次'));
    });

    test('斷路器：中間有成功就歸零（失敗 2、成功 1、失敗 2 不停）', () async {
      final months = [
        aug,
        jul,
        const CalendarMonth(2026, 6),
        const CalendarMonth(2026, 5),
        const CalendarMonth(2026, 4),
      ];
      for (final (i, m) in months.indexed) {
        if (i == 2) {
          listTwse(m, [_cash('2330', DateTime(m.year, m.month, 12), 5)]);
        } else {
          when(
            () => twse.getExRightResults(
              startDate: m.firstDay,
              endDate: m.lastDay,
            ),
          ).thenThrow(const ApiException('暫時', 200));
        }
      }

      final summary = await run(
        scope: DividendBackfillScope(
          from: months.last,
          to: months.first,
          markets: const {MarketCode.twse},
        ),
      );

      expect(summary.marketStops, isEmpty);
      verify(
        () => twse.getExRightResults(
          startDate: months.last.firstDay,
          endDate: months.last.lastDay,
        ),
      ).called(1);
    });

    group('斷路器：明細', () {
      const symbols = ['1101', '1102', '2330', '2836', '4108'];
      const scope = DividendBackfillScope(
        from: jul,
        to: aug,
        markets: {MarketCode.twse},
      );
      setUp(() async {
        await db.upsertStocks([
          for (final s in ['1101', '1102'])
            StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
        ]);
        listTwse(aug, [
          for (final (i, s) in symbols.indexed)
            _rightsAndCash(s, DateTime(2026, 8, 3 + i)),
        ]);
        listTwse(jul, [_cash('2330', DateTime(2026, 7, 12), 5)]);
      });

      const mismatch = ExRightDetail(
        symbol: '',
        cashDividend: 0.5,
        stockSharesPerThousand: 0,
      );

      for (final (label, fail) in [
        ('一般失敗', () => const ApiException('改版', 200)),
        ('參考價不符', null),
      ]) {
        test('連續 3 筆$label：停掉該市場，之後的明細與月份都不再打', () async {
          for (final s in symbols) {
            if (fail != null) {
              when(() => twse.getExRightDetail(s, any())).thenThrow(fail());
            } else {
              detail(s, mismatch);
            }
          }

          final summary = await run(scope: scope);

          for (final s in symbols.take(3)) {
            verify(() => twse.getExRightDetail(s, any())).called(1);
          }
          for (final s in symbols.skip(3)) {
            verifyNever(() => twse.getExRightDetail(s, any()));
          }
          verifyNever(
            () => twse.getExRightResults(
              startDate: jul.firstDay,
              endDate: jul.lastDay,
            ),
          );
          expect(summary.marketStops[MarketCode.twse], contains('連續 3 次'));
          expect(
            (await failures())['TWSE 2026-08']!.failedSymbolSet,
            symbols.take(3).toSet(),
          );
        });
      }

      test('明細通過核對就歸零（失敗 2、成功 1、失敗 2 不停）', () async {
        for (final (i, s) in symbols.indexed) {
          if (i == 2) {
            detail(s, _detailOk);
          } else {
            detail(s, mismatch);
          }
        }

        final summary = await run(scope: scope);

        expect(summary.marketStops, isEmpty);
        verify(() => twse.getExRightDetail('4108', any())).called(1);
        expect(await ledgerKeys(), {'TWSE 2026-07'});
      });
    });

    test('明細失敗後預算用完：已發生的明細失敗照記（失敗次數才會累積到退避）', () async {
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsAndCash('4108', DateTime(2026, 8, 14)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('暫時', 200));

      final summary = await run(
        maxCalls: 2,
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      verifyNever(() => twse.getExRightDetail('4108', any()));
      expect(summary.stoppedAt, (market: MarketCode.twse, month: aug));
      final f = (await failures())['TWSE 2026-08']!;
      expect(f.failedSymbolSet, {'2836'});
      expect(f.listOk, isTrue);
    });

    test('明細失敗後撞到網路錯誤：已發生的明細失敗照記', () async {
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsAndCash('4108', DateTime(2026, 8, 14)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('暫時', 200));
      when(
        () => twse.getExRightDetail('4108', any()),
      ).thenThrow(const NetworkException('timeout'));

      final summary = await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(summary.marketStops[MarketCode.twse], contains('網路'));
      expect((await failures())['TWSE 2026-08']!.failedSymbolSet, {'2836'});
      expect(await ledgerKeys(), isEmpty);
    });

    test('網路錯誤：該市場本輪停止、不記失敗；另一市場照常', () async {
      stubHealthyMonths();
      when(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).thenThrow(const NetworkException('timeout'));

      final summary = await run();

      expect(await failures(), isEmpty);
      verifyNever(
        () => twse.getExRightResults(
          startDate: jul.firstDay,
          endDate: jul.lastDay,
        ),
      );
      expect(await ledgerKeys(), {'TPEx 2026-08', 'TPEx 2026-07'});
      expect(summary.marketStops[MarketCode.twse], contains('網路'));
    });

    test('限流：整輪停止，先前完成的保留，被打斷的單位不記失敗', () async {
      stubHealthyMonths();
      when(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).thenThrow(const RateLimitException('redirect loop'));

      final summary = await run();

      expect(summary.rateLimited, isTrue);
      expect(await ledgerKeys(), {'TPEx 2026-08'});
      expect(await failures(), isEmpty);
      verifyNever(
        () => tpex.getExRightResults(
          startDate: jul.firstDay,
          endDate: jul.lastDay,
        ),
      );
    });

    test('限流打斷的單位本輪已有明細失敗：失敗照記', () async {
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsIssue('4108', DateTime(2026, 8, 14)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('壞', 200));
      when(
        () => twse.getExRightDetail('4108', any()),
      ).thenThrow(const RateLimitException('redirect loop'));

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect((await failures())['TWSE 2026-08']!.failedSymbolSet, {'2836'});
    });

    for (final (name, make) in [
      ('上櫃在市主檔不足門檻', () => backfiller(minStocks: 3)),
      ('沒有上櫃 client', () => backfiller(noTpex: true)),
    ]) {
      test('$name：不打上櫃，上市照常', () async {
        stubHealthyMonths();

        final summary = await run(b: make());

        verifyZeroInteractions(tpex);
        verify(
          () => twse.getExRightResults(
            startDate: aug.firstDay,
            endDate: aug.lastDay,
          ),
        ).called(1);
        expect(summary.marketStops.keys, [MarketCode.tpex]);
      });
    }

    test('scope.to 為本月：拋 ArgumentError，不打任何 API', () async {
      await expectLater(
        run(
          scope: const DividendBackfillScope(
            from: jul,
            to: CalendarMonth(2026, 9),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      verifyZeroInteractions(tpex);
      verifyZeroInteractions(twse);
    });

    test('DB 寫入失敗：往外拋，之後不再打 API', () async {
      final mockDb = MockAppDatabase();
      when(() => mockDb.getAllActiveStocks()).thenAnswer(
        (_) async => [
          for (final (s, m) in [('2330', 'TWSE'), ('6488', 'TPEx')])
            StockMasterEntry(
              symbol: s,
              name: s,
              market: m,
              isActive: true,
              updatedAt: DateTime(2026, 9, 1),
            ),
        ],
      );
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => []);
      when(() => mockDb.getDividendMonthFailures()).thenAnswer((_) async => []);
      when(
        () => mockDb.completeDividendMonth(
          market: any(named: 'market'),
          month: any(named: 'month'),
          rows: any(named: 'rows'),
          expectedKeys: any(named: 'expectedKeys'),
          listedRows: any(named: 'listedRows'),
          skippedSymbols: any(named: 'skippedSymbols'),
          completedAt: any(named: 'completedAt'),
        ),
      ).thenThrow(Exception('disk I/O error'));
      when(
        () => mockDb.updateDividendDistributionPrices(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDb.recordDividendListing(
          market: any(named: 'market'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          listedThrough: any(named: 'listedThrough'),
          listedKnownKeys: any(named: 'listedKnownKeys'),
          notInMasterKeys: any(named: 'notInMasterKeys'),
          reasons: any(named: 'reasons'),
          recordedAt: any(named: 'recordedAt'),
        ),
      ).thenAnswer((_) async {});
      stubHealthyMonths();

      await expectLater(
        run(b: backfiller(database: mockDb)),
        throwsA(isA<Exception>()),
      );
      verifyZeroInteractions(twse);
    });
  });

  test('每次呼叫前都等 2 秒（正式預設值），第一次也等', () {
    fakeAsync((async) {
      // 真的 in-memory DB 在 fakeAsync 裡推進不了，改用 mock
      final mockDb = MockAppDatabase();
      when(() => mockDb.getAllActiveStocks()).thenAnswer(
        (_) async => [
          for (final (s, m) in [('2836', 'TWSE'), ('6488', 'TPEx')])
            StockMasterEntry(
              symbol: s,
              name: s,
              market: m,
              isActive: true,
              updatedAt: DateTime(2026, 9, 1),
            ),
        ],
      );
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => []);
      when(() => mockDb.getDividendMonthFailures()).thenAnswer((_) async => []);
      when(
        () => mockDb.completeDividendMonth(
          market: any(named: 'market'),
          month: any(named: 'month'),
          rows: any(named: 'rows'),
          expectedKeys: any(named: 'expectedKeys'),
          listedRows: any(named: 'listedRows'),
          skippedSymbols: any(named: 'skippedSymbols'),
          completedAt: any(named: 'completedAt'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => mockDb.upsertDividendDistributions(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDb.updateDividendDistributionPrices(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDb.recordDividendListing(
          market: any(named: 'market'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          listedThrough: any(named: 'listedThrough'),
          listedKnownKeys: any(named: 'listedKnownKeys'),
          notInMasterKeys: any(named: 'notInMasterKeys'),
          reasons: any(named: 'reasons'),
          recordedAt: any(named: 'recordedAt'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockDb.getDividendDistributionKeys(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => {});
      listTpex(aug, [_cash('6488', DateTime(2026, 8, 10), 3)]);
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);
      detail('2836', _detailOk);

      DividendBackfiller(
        database: mockDb,
        twseClient: twse,
        tpexClient: tpex,
        minActiveStocksPerMarket: 1,
      ).backfill(
        now: now,
        maxCalls: 30,
        scope: const DividendBackfillScope(from: aug, to: aug),
      );

      Future<List<ExRightResult>> tpexList() =>
          tpex.getExRightResults(startDate: aug.firstDay, endDate: aug.lastDay);
      Future<List<ExRightResult>> twseList() =>
          twse.getExRightResults(startDate: aug.firstDay, endDate: aug.lastDay);

      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1999));
      verifyZeroInteractions(tpex);
      async.elapse(const Duration(milliseconds: 1));
      verify(tpexList).called(1);
      async.elapse(const Duration(milliseconds: 1999));
      verifyNever(twseList);
      async.elapse(const Duration(milliseconds: 1));
      verify(twseList).called(1);
      async.elapse(const Duration(milliseconds: 1999));
      verifyNever(() => twse.getExRightDetail(any(), any()));
      async.elapse(const Duration(milliseconds: 1));
      verify(() => twse.getExRightDetail('2836', any())).called(1);
    });
  });

  group('摘要', () {
    test('日誌行含本輪完成數、呼叫數、累計進度與下一個單位', () async {
      stubHealthyMonths();

      final summary = await run(maxCalls: 2);
      final line = summary.toLogLine();

      expect(line, contains('本輪完成 2'));
      expect(line, contains('呼叫 2/2'));
      expect(line, contains('累計 2/136'));
      expect(line, contains('下一個 TPEx 2026-07'));
      expect(line, contains('停止：預算'));
      expect(summary.warningLine(), isNull);
    });

    test('沒有待重試的失敗、但有市場被停掉：仍有警示行', () async {
      stubHealthyMonths();
      when(
        () => tpex.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).thenThrow(const NetworkException('timeout'));

      final summary = await run();

      expect(await failures(), isEmpty);
      expect(summary.warningLine(), contains('停掉的市場：TPEx 網路錯誤'));
    });

    test('剛好 10 個待重試單位：全部列出、不加「…」', () async {
      final from = aug.addMonths(-9);
      for (final m in CalendarMonth.descending(from: from, to: aug)) {
        for (var i = 0; i < 3; i++) {
          await db.recordDividendMonthFailure(
            market: MarketCode.twse,
            month: m,
            failedAt: now,
            error: '列表 0 列',
            listOk: false,
          );
        }
      }

      final summary = await run(
        scope: DividendBackfillScope(
          from: from,
          to: aug,
          markets: const {MarketCode.twse},
        ),
      );
      final warning = summary.warningLine()!;

      expect(warning, contains('10 個單位待重試'));
      expect(warning, contains('TWSE 2025-11'));
      expect(warning, isNot(contains('…')));
    });

    test('回補範圍內有待重試的失敗：警示行最多列 10 筆，並附修復工具指令', () async {
      final from = aug.addMonths(-10);
      for (final m in CalendarMonth.descending(from: from, to: aug)) {
        for (var i = 0; i < 3; i++) {
          await db.recordDividendMonthFailure(
            market: MarketCode.twse,
            month: m,
            failedAt: now,
            error: '列表 0 列',
            listOk: false,
          );
        }
      }

      final summary = await run(
        scope: DividendBackfillScope(
          from: from,
          to: aug,
          markets: const {MarketCode.twse},
        ),
      );
      final warning = summary.warningLine()!;

      expect(summary.calls, 0, reason: '全部在退避中');
      expect(warning, contains('11 個單位待重試'));
      expect(warning, contains('TWSE 2026-08'));
      expect(warning, isNot(contains('TWSE 2025-10')), reason: '第 11 筆不列');
      expect(warning, contains('…'));
      expect(warning, contains('tool/backfill_dividend_distributions.dart'));
    });
  });
}

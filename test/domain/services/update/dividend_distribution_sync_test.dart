// 本月除權除息同步（DividendSyncer.syncDistributions，更新步驟 6.6）
//
// 範圍＝本月初或 7 天前（取較早者）～今天。先上櫃、再上市，各 1 次列表；
// TWSE「權」「權息」列要查明細才拆得開，DB 已有該列（含只有現金增資、
// 金額皆 0 的列）就不再查。不在股票主檔的代號在查明細之前就略過。列表與
// 明細合計受每輪上限約束，每筆明細查到就寫入。
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update/dividend_syncer.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockAppDatabase extends Mock implements AppDatabase {}

ExRightResult _row(
  String symbol,
  DateTime exDate, {
  double? cash,
  double? shares,
}) => ExRightResult(
  symbol: symbol,
  exDate: exDate,
  cashDividend: cash,
  stockSharesPerThousand: shares,
);

/// 事實寫入一律失敗的 DB（其餘照常），驗證本月同步不因此往外拋
class _FactsFailingDb extends AppDatabase {
  _FactsFailingDb() : super(NativeDatabase.memory());

  @override
  Future<void> recordDividendListing({
    required String market,
    required DateTime from,
    required DateTime to,
    required DateTime listedThrough,
    required Set<(String, DateTime)> listedKnownKeys,
    required Set<(String, DateTime)> notInMasterKeys,
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
    required DateTime recordedAt,
  }) => throw Exception('disk I/O error');
}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late DividendSyncer syncer;

  final today = DateTime(2026, 9, 29, 15, 30);
  final start = DateTime(2026, 9, 1);
  final end = DateTime(2026, 9, 29);

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(<DividendDistributionCompanion>[]);
    registerFallbackValue(<DividendListedPrice>[]);
    registerFallbackValue(<(String, DateTime)>{});
    registerFallbackValue(<(String, DateTime), DividendUnresolvedReason>{});
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2836', name: '高雄銀', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '4108', name: '懷特', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '6762', name: '達亞', market: 'TPEx'),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    syncer = DividendSyncer(
      database: db,
      twseClient: twse,
      tpexClient: tpex,
      detailCallDelay: Duration.zero,
    );
    when(
      () => twse.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
  });

  tearDown(() => db.close());

  void stubTwse(List<ExRightResult> rows) => when(
    () => twse.getExRightResults(
      startDate: any(named: 'startDate'),
      endDate: any(named: 'endDate'),
    ),
  ).thenAnswer((_) async => rows);

  void stubDetail(String symbol, double cash, double shares) =>
      when(() => twse.getExRightDetail(symbol, any())).thenAnswer(
        (_) async => ExRightDetail(
          symbol: symbol,
          cashDividend: cash,
          stockSharesPerThousand: shares,
        ),
      );

  test('寫入列帶列表的前收盤與除權息參考價（上櫃、上市息列、查過明細的列）', () async {
    stubTwse([
      ExRightResult(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 5.0,
        stockSharesPerThousand: 0,
        closeBefore: 1000,
        referencePrice: 995,
      ),
      ExRightResult(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: null,
        stockSharesPerThousand: null,
        closeBefore: 10.6,
        referencePrice: 10.0,
      ),
    ]);
    stubDetail('2836', 0.15, 45);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        ExRightResult(
          symbol: '6762',
          exDate: DateTime(2026, 9, 18),
          cashDividend: 0.3,
          stockSharesPerThousand: 150,
          closeBefore: 120,
          referencePrice: 104.08,
        ),
      ],
    );

    await syncer.syncDistributions(today: today, maxCalls: 30);

    Future<(double?, double?)> prices(String symbol) async {
      final r = (await db.getDividendDistributions(symbol)).single;
      return (r.closeBefore, r.referencePrice);
    }

    expect(await prices('2330'), (1000.0, 995.0));
    expect(await prices('2836'), (10.6, 10.0));
    expect(await prices('6762'), (120.0, 104.08));
  });

  test('已查過明細的權息列不重查，但以列表值補上前收盤與參考價', () async {
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);
    stubTwse([
      ExRightResult(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: null,
        stockSharesPerThousand: null,
        closeBefore: 10.6,
        referencePrice: 10.0,
      ),
    ]);

    await syncer.syncDistributions(today: today, maxCalls: 30);

    verifyNever(() => twse.getExRightDetail(any(), any()));
    final r = (await db.getDividendDistributions('2836')).single;
    expect(
      (r.cashDividend, r.closeBefore, r.referencePrice),
      (0.15, 10.6, 10.0),
    );
  });

  test('價格欄是 0 或負值：視為缺值存 null（還原因子會變成 0、負值或無限大）', () async {
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);
    stubTwse([
      ExRightResult(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: null,
        stockSharesPerThousand: null,
        closeBefore: -1,
        referencePrice: 0,
      ),
    ]);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        ExRightResult(
          symbol: '6762',
          exDate: DateTime(2026, 9, 18),
          cashDividend: 0.3,
          stockSharesPerThousand: 150,
          closeBefore: 0,
          referencePrice: -1,
        ),
      ],
    );

    await syncer.syncDistributions(today: today, maxCalls: 30);

    Future<(double?, double?)> prices(String symbol) async {
      final r = (await db.getDividendDistributions(symbol)).single;
      return (r.closeBefore, r.referencePrice);
    }

    // 兩列兩欄都是非正值、0 與負值各一：任一欄漏過濾、或只擋 0 都會讀到原值
    expect(await prices('6762'), (null, null), reason: '寫入列');
    expect(await prices('2836'), (null, null), reason: '已在庫列補價');
  });

  test('範圍：本月初至今天（本月已超過 7 天）', () async {
    await syncer.syncDistributions(today: today, maxCalls: 30);

    verify(
      () => twse.getExRightResults(startDate: start, endDate: end),
    ).called(1);
    verify(
      () => tpex.getExRightResults(startDate: start, endDate: end),
    ).called(1);
  });

  test('範圍：月初幾天內往前涵蓋 7 天（跨到上個月底）', () async {
    await syncer.syncDistributions(
      today: DateTime(2026, 10, 2, 21, 30),
      maxCalls: 30,
    );

    verify(
      () => twse.getExRightResults(
        startDate: DateTime(2026, 9, 25),
        endDate: DateTime(2026, 10, 2),
      ),
    ).called(1);
  });

  test('息列直接寫入；權息列查明細拆開；上櫃列直接寫入', () async {
    stubTwse([
      _row('2330', DateTime(2026, 9, 16), cash: 5.0, shares: 0),
      _row('2836', DateTime(2026, 9, 17)),
    ]);
    stubDetail('2836', 0.15, 45);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        _row('6762', DateTime(2026, 9, 18), cash: 0.3, shares: 150),
      ],
    );

    final result = await syncer.syncDistributions(today: today, maxCalls: 30);

    expect(result.errors, isEmpty);
    expect(result.written, 3);
    expect(result.calls, 3, reason: '上櫃列表＋上市列表＋1 次明細');
    final twseRows = await db.getDividendDistributionsBatch(['2330', '2836']);
    expect(twseRows['2330']!.single.cashDividend, 5.0);
    expect(twseRows['2836']!.single.cashDividend, 0.15);
    expect(twseRows['2836']!.single.stockSharesPerThousand, 45);
    expect(
      (await db.getDividendDistributions('6762')).single.stockSharesPerThousand,
      150,
    );
  });

  test('只有現金增資的除權：存成金額皆 0 的已處理列，下次不再查明細', () async {
    stubTwse([_row('4108', DateTime(2026, 9, 10), cash: 0)]);
    stubDetail('4108', 0, 0);

    await syncer.syncDistributions(today: today, maxCalls: 30);
    final second = await syncer.syncDistributions(today: today, maxCalls: 30);

    verify(
      () => twse.getExRightDetail('4108', DateTime(2026, 9, 10)),
    ).called(1);
    expect(second.calls, 2, reason: '只剩兩個列表');
    expect(await db.getDividendDistributions('4108'), isEmpty);
    expect(await db.getDividendDistributionKeys(from: start, to: end), {
      ('4108', DateTime(2026, 9, 10)),
    });
  });

  test('不在股票主檔的代號：不查明細、不寫入（外鍵會讓整批失敗）', () async {
    stubTwse([
      _row('910322', DateTime(2026, 9, 10)),
      _row('2887Z1', DateTime(2026, 9, 11), cash: 0.5, shares: 0),
      _row('2330', DateTime(2026, 9, 16), cash: 5.0, shares: 0),
    ]);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        _row('00950B', DateTime(2026, 9, 11), cash: 0.08, shares: 0),
        _row('6762', DateTime(2026, 9, 18), cash: 0.3, shares: 150),
      ],
    );

    final result = await syncer.syncDistributions(today: today, maxCalls: 30);

    verifyNever(() => twse.getExRightDetail(any(), any()));
    expect(result.errors, isEmpty);
    expect(result.written, 2);
    expect(await db.getDividendDistributions('6762'), hasLength(1));
  });

  test('明細與列表的參考價對不上（查到別次除權息）：記錯誤、不寫入', () async {
    stubTwse([
      ExRightResult(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: null,
        stockSharesPerThousand: null,
        closeBefore: 12.55,
        dividendAdjustedReference: 11.89,
      ),
      ExRightResult(
        symbol: '4108',
        exDate: DateTime(2026, 9, 18),
        cashDividend: 0,
        stockSharesPerThousand: null,
        closeBefore: 25.20,
        dividendAdjustedReference: 25.20,
      ),
    ]);
    stubDetail('2836', 0.15, 45); // 2021 那次的明細
    stubDetail('4108', 0, 0);

    final result = await syncer.syncDistributions(today: today, maxCalls: 30);

    expect(result.errors.single, allOf(contains('2836'), contains('參考價')));
    expect(await db.getDividendDistributionKeys(from: start, to: end), {
      ('4108', DateTime(2026, 9, 18)),
    });
  });

  test('單列明細失敗：記錯誤、其餘列照寫', () async {
    stubTwse([
      _row('2836', DateTime(2026, 9, 17)),
      _row('2330', DateTime(2026, 9, 16), cash: 5.0, shares: 0),
    ]);
    when(
      () => twse.getExRightDetail('2836', any()),
    ).thenThrow(const ApiException('TWSE 除權除息明細: 回應不可信', 200));

    final result = await syncer.syncDistributions(today: today, maxCalls: 30);

    expect(result.errors.single, contains('2836'));
    expect(await db.getDividendDistributions('2330'), hasLength(1));
    expect(await db.getDividendDistributions('2836'), isEmpty);
  });

  test('上櫃列表失敗：記錯誤，上市照常同步', () async {
    stubTwse([_row('2330', DateTime(2026, 9, 16), cash: 5.0, shares: 0)]);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(const ApiException('TPEX 除權除息計算結果: 回應不可信', 200));

    final result = await syncer.syncDistributions(today: today, maxCalls: 30);

    expect(result.errors.single, contains('TPEX'));
    expect(await db.getDividendDistributions('2330'), hasLength(1));
  });

  test('上市列表失敗：記錯誤，上櫃照常同步', () async {
    when(
      () => twse.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(const ApiException('TWSE 除權除息計算結果: 回應不可信', 200));
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        _row('6762', DateTime(2026, 9, 18), cash: 0.3, shares: 150),
      ],
    );

    final result = await syncer.syncDistributions(today: today, maxCalls: 30);

    expect(result.errors.single, contains('TWSE'));
    expect(await db.getDividendDistributions('6762'), hasLength(1));
  });

  test('限流與網路錯誤往上拋（限流由 UpdateService 中止本輪，網路錯誤記錯誤續跑）', () async {
    when(
      () => twse.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(const RateLimitException('redirect loop'));
    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<RateLimitException>()),
    );

    stubTwse([_row('2836', DateTime(2026, 9, 17))]);
    when(
      () => twse.getExRightDetail('2836', any()),
    ).thenThrow(const NetworkException('timeout'));
    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<NetworkException>()),
    );

    when(
      () => twse.getExRightDetail('2836', any()),
    ).thenThrow(const RateLimitException('redirect loop'));
    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<RateLimitException>()),
    );
  });

  test('上櫃列表的限流與網路錯誤也往上拋', () async {
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(const NetworkException('timeout'));
    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<NetworkException>()),
    );

    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(const RateLimitException('redirect loop'));
    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<RateLimitException>()),
    );
  });

  group('完整度事實', () {
    Future<Map<String, String>> unresolved() async => {
      for (final u in await db.getDividendUnresolved())
        '${u.market} ${u.symbol}': u.reason,
    };

    test('兩市場列表成功：列表日記到資料日；預算用完、明細失敗、參考價不符、未知代號各記原因', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: '1101', name: '台泥', market: 'TWSE'),
      ]);
      stubTwse([
        _row('2836', DateTime(2026, 9, 17)),
        ExRightResult(
          symbol: '4108',
          exDate: DateTime(2026, 9, 18),
          cashDividend: null,
          stockSharesPerThousand: null,
          closeBefore: 10.6,
          dividendAdjustedReference: 10.0,
        ),
        _row('1101', DateTime(2026, 9, 19)),
        _row('910322', DateTime(2026, 9, 19), cash: 1, shares: 0),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('改版', 200));
      // (10.6 − 0.5) ÷ 1 = 10.1，與列表的 10.0 不符
      stubDetail('4108', 0.5, 0);

      final result = await syncer.syncDistributions(
        today: today,
        maxCalls: 4,
        dataDate: DateTime(2026, 9, 29),
      );

      expect(result.pendingDetails, 1);
      expect(await unresolved(), {
        'TWSE 2836': 'DETAIL_FAILED',
        'TWSE 4108': 'REFERENCE_MISMATCH',
        'TWSE 1101': 'PENDING_DETAIL',
        'TWSE 910322': 'NOT_IN_MASTER',
      });
      expect(
        {
          for (final e in await db.getDividendListings())
            e.market: e.listedThrough,
        },
        {'TPEx': end, 'TWSE': end},
      );
    });

    test('凌晨補跑：資料日早於今天時列表日記資料日，不替 10 月記任何列表日', () async {
      for (final market in ['TWSE', 'TPEx']) {
        await db.recordDividendListing(
          market: market,
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 29),
          listedThrough: DateTime(2026, 9, 29),
          listedKnownKeys: const {},
          notInMasterKeys: const {},
          recordedAt: today,
        );
      }

      await syncer.syncDistributions(
        today: DateTime(2026, 10, 1, 1, 0),
        maxCalls: 30,
        dataDate: DateTime(2026, 9, 30),
      );

      expect(
        {
          for (final e in await db.getDividendListings())
            '${e.market} ${e.month}': e.listedThrough,
        },
        {'TWSE 9': DateTime(2026, 9, 30), 'TPEx 9': DateTime(2026, 9, 30)},
      );
    });

    test('資料日晚於今天（時鐘或資料異常）：列表日不超過今天', () async {
      await syncer.syncDistributions(
        today: today,
        maxCalls: 30,
        dataDate: DateTime(2026, 10, 3),
      );

      expect(
        {
          for (final e in await db.getDividendListings())
            '${e.market} ${e.month}': e.listedThrough,
        },
        {'TWSE 9': end, 'TPEx 9': end},
      );
    });

    test('尚未在庫的權息列前收盤是 0：明細核對不符，不寫入、記 REFERENCE_MISMATCH', () async {
      stubTwse([
        ExRightResult(
          symbol: '4108',
          exDate: DateTime(2026, 9, 18),
          cashDividend: null,
          stockSharesPerThousand: null,
          closeBefore: 0,
          referencePrice: 9.5,
          dividendAdjustedReference: 9.52,
        ),
      ]);
      // 前收盤 0 推算 (0 − 0.5) ÷ 1.05 < 0，與列表的 9.52 不符
      stubDetail('4108', 0.5, 50);

      await syncer.syncDistributions(today: today, maxCalls: 30);

      expect(await db.getDividendDistributions('4108'), isEmpty);
      expect(await unresolved(), {'TWSE 4108': 'REFERENCE_MISMATCH'});
    });

    test('🚨 明細查到一半被限流：事實照記（未查的列為 pendingDetail），例外照常往外拋', () async {
      stubTwse([
        _row('2836', DateTime(2026, 9, 17)),
        _row('4108', DateTime(2026, 9, 18)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const RateLimitException('redirect loop'));

      await expectLater(
        syncer.syncDistributions(today: today, maxCalls: 30),
        throwsA(isA<RateLimitException>()),
      );

      expect(await unresolved(), {
        'TWSE 2836': 'PENDING_DETAIL',
        'TWSE 4108': 'PENDING_DETAIL',
      });
      expect(
        (await db.getDividendListings()).map((e) => e.market),
        contains('TWSE'),
      );
    });

    test('列表失敗：不記事實', () async {
      when(
        () => twse.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const ApiException('改版', 200));

      await syncer.syncDistributions(today: today, maxCalls: 30);

      expect(
        (await db.getDividendListings()).map((e) => e.market),
        isNot(contains('TWSE')),
      );
    });

    test('事實寫入失敗：記進 errors、不往外拋，配發列照寫', () async {
      final failing = _FactsFailingDb();
      addTearDown(failing.close);
      await failing.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);
      stubTwse([_row('2330', DateTime(2026, 9, 16), cash: 5, shares: 0)]);

      final result = await DividendSyncer(
        database: failing,
        twseClient: twse,
        detailCallDelay: Duration.zero,
      ).syncDistributions(today: today, maxCalls: 30);

      expect(result.errors.single, contains('完整度紀錄'));
      expect(await failing.getDividendDistributions('2330'), hasLength(1));
    });
  });

  test('每次查明細前等 2 秒（正式預設值，防 TWSE 限流）', () {
    fakeAsync((async) {
      final mockDb = MockAppDatabase();
      when(() => mockDb.getAllActiveStocks()).thenAnswer(
        (_) async => [
          for (final s in ['2836', '4108'])
            StockMasterEntry(
              symbol: s,
              name: s,
              market: 'TWSE',
              isActive: true,
              updatedAt: DateTime(2026, 9, 1),
            ),
        ],
      );
      when(
        () => mockDb.getDividendDistributionKeys(
          from: any(named: 'from'),
          to: any(named: 'to'),
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
      stubTwse([
        _row('2836', DateTime(2026, 9, 17)),
        _row('4108', DateTime(2026, 9, 18), cash: 0),
      ]);
      stubDetail('2836', 0.15, 45);
      stubDetail('4108', 0, 0);

      // 不傳 detailCallDelay：釘住正式環境的預設值
      DividendSyncer(
        database: mockDb,
        twseClient: twse,
      ).syncDistributions(today: today, maxCalls: 30);

      async.flushMicrotasks();
      verify(
        () => twse.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
      async.elapse(const Duration(milliseconds: 1999));
      verifyNever(() => twse.getExRightDetail(any(), any()));
      async.elapse(const Duration(milliseconds: 1));
      verify(() => twse.getExRightDetail(any(), any())).called(1);
      async.elapse(const Duration(milliseconds: 1999));
      verifyNever(() => twse.getExRightDetail(any(), any()));
      async.elapse(const Duration(milliseconds: 1));
      verify(() => twse.getExRightDetail(any(), any())).called(1);
    });
  });

  test('每輪上限：列表與明細合計，沒查到的明細下一輪接續、不重查', () async {
    stubTwse([
      _row('2836', DateTime(2026, 9, 17)),
      _row('4108', DateTime(2026, 9, 18), cash: 0),
      _row('2330', DateTime(2026, 9, 19), cash: 0),
    ]);
    stubDetail('2836', 0.15, 45);
    stubDetail('4108', 0, 0);
    stubDetail('2330', 0, 0);

    final first = await syncer.syncDistributions(today: today, maxCalls: 3);
    expect(first.calls, 3, reason: '兩個列表＋1 次明細');
    expect(first.pendingDetails, 2);

    final second = await syncer.syncDistributions(today: today, maxCalls: 30);
    expect(second.calls, 4, reason: '兩個列表＋剩下 2 次明細');
    expect(second.pendingDetails, 0);
    verify(() => twse.getExRightDetail('2836', any())).called(1);
  });

  test('上限為 0：一次都不打', () async {
    final result = await syncer.syncDistributions(today: today, maxCalls: 0);

    expect(result.calls, 0);
    verifyNever(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    );
    verifyNever(
      () => twse.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    );
  });

  test('上限只夠上櫃：上市這輪整個略過', () async {
    await syncer.syncDistributions(today: today, maxCalls: 1);

    verify(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).called(1);
    verifyNever(
      () => twse.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    );
  });

  test('明細中途撞到限流：已查到的保留，下一輪不重查', () async {
    stubTwse([
      _row('2330', DateTime(2026, 9, 16), cash: 5.0, shares: 0),
      _row('2836', DateTime(2026, 9, 17)),
      _row('4108', DateTime(2026, 9, 18), cash: 0),
    ]);
    stubDetail('2836', 0.15, 45);
    when(
      () => twse.getExRightDetail('4108', any()),
    ).thenThrow(const RateLimitException('redirect loop'));

    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<RateLimitException>()),
    );
    expect(await db.getDividendDistributionKeys(from: start, to: end), {
      ('2330', DateTime(2026, 9, 16)),
      ('2836', DateTime(2026, 9, 17)),
    });

    stubDetail('4108', 0, 0);
    await syncer.syncDistributions(today: today, maxCalls: 30);
    verify(() => twse.getExRightDetail('2836', any())).called(1);
  });

  test('上市撞到限流時，先做的上櫃已寫入', () async {
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        _row('6762', DateTime(2026, 9, 18), cash: 0.3, shares: 150),
      ],
    );
    when(
      () => twse.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(const RateLimitException('redirect loop'));

    await expectLater(
      syncer.syncDistributions(today: today, maxCalls: 30),
      throwsA(isA<RateLimitException>()),
    );
    expect(await db.getDividendDistributions('6762'), hasLength(1));
  });
}

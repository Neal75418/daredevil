// tool/backfill_base_prices.dart：既有資料的平盤價修復（除權息漲跌修正 spec 第 4 節）
//
// 上市逐日抓 TWT84U、上櫃逐月抓 exDailyQ，只改 base_price 與 price_change
// 兩欄、不重抓整天、不動 ledger。真 in-memory DB、mock client。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

import '../../tool/backfill_base_prices.dart';

class _MockTwseClient extends Mock implements TwseClient {}

class _MockTpexClient extends Mock implements TpexClient {}

/// 讓 nullify 拋錯，驗證「每天一個 transaction」
class _NullifyThrows extends AppDatabase {
  _NullifyThrows() : super.forTesting();

  @override
  Future<int> nullifyPriceChangeWithoutClose({
    required DateTime date,
    required String market,
  }) => throw StateError('nullify boom');
}

void main() {
  late AppDatabase db;
  late _MockTwseClient twse;
  late _MockTpexClient tpex;
  final d15 = DateContext.normalize(DateTime(2026, 9, 15));
  final d16 = DateContext.normalize(DateTime(2026, 9, 16));
  final d17 = DateContext.normalize(DateTime(2026, 9, 17));
  final exDay = DateContext.normalize(DateTime(2026, 10, 27));
  final oldExDay = DateContext.normalize(DateTime(2025, 9, 9));

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902', '9903', '9904'])
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
    twse = _MockTwseClient();
    tpex = _MockTpexClient();
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
  });

  tearDown(() => db.close());

  Future<int> run(List<String> args, {List<String>? logs}) =>
      runBasePriceBackfill(
        args,
        twse: twse,
        tpex: tpex,
        db: db,
        callDelay: Duration.zero,
        log: logs?.add,
        today: DateTime(2026, 12, 31), // 測資的月份都在今天之前，不夾
      );

  DailyPriceCompanion row(
    String symbol,
    DateTime date, {
    double? close,
    double? change,
    double? base,
  }) => DailyPriceCompanion.insert(
    symbol: symbol,
    date: date,
    open: Value(close),
    high: Value(close),
    low: Value(close),
    close: Value(close),
    volume: const Value(1000),
    priceChange: Value(change),
    basePrice: base == null ? const Value.absent() : Value(base),
  );

  Future<DailyPriceEntry> price(String symbol, DateTime d) async =>
      (await db.getPriceHistory(symbol, startDate: d, endDate: d)).single;

  ExRightResult ex(String code, DateTime exDate, {double? base}) =>
      ExRightResult(
        symbol: code,
        exDate: exDate,
        cashDividend: 1,
        stockSharesPerThousand: 0,
        tradingBasePrice: base,
      );

  group('parseBasePriceArgs', () {
    final errs = <String>[];
    setUp(errs.clear);

    test('預設 both、live 路徑、不 dry-run', () {
      final a = parseBasePriceArgs(const [], errs.add)!;
      expect(a.market, 'both');
      expect(
        a.dbPath,
        contains('com.neo.afterclose/Data/Documents/afterclose.sqlite'),
      );
      expect(a.dryRun, isFalse);
      expect((a.from, a.to), (null, null));
    });

    test('完整參數', () {
      final a = parseBasePriceArgs(const [
        '--db',
        '/tmp/x.db',
        '--market',
        'TWSE',
        '--from',
        '2025-06-10',
        '--to',
        '2026-10-22',
        '--dry-run',
      ], errs.add)!;
      expect(a.market, MarketCode.twse);
      expect(a.dbPath, '/tmp/x.db');
      expect((a.from, a.to), (DateTime(2025, 6, 10), DateTime(2026, 10, 22)));
      expect(a.dryRun, isTrue);
    });

    test('--from 晚於 --to、--market 不認得、日期格式錯 → null 並報錯', () {
      expect(
        parseBasePriceArgs(const [
          '--from',
          '2026-10-22',
          '--to',
          '2025-06-10',
        ], errs.add),
        isNull,
      );
      expect(parseBasePriceArgs(const ['--market', 'OTC'], errs.add), isNull);
      expect(
        parseBasePriceArgs(const ['--from', '2026/10/22'], errs.add),
        isNull,
      );
      expect(errs, hasLength(3));
    });
  });

  group('上市（逐日 TWT84U）', () {
    test('🚨 只挑「沒有任何一列有平盤價」的日子；跑第二次 0 個請求（冪等、可中斷接續）', () async {
      await db.insertPrices([
        row('9901', d16, close: 2380, change: 0),
        row('9902', d16, close: 10, change: 0.5),
        row('9901', d17, close: 2425, change: 45, base: 2380),
        row('9902', d17, close: 10, change: 0),
      ]);
      when(
        () => twse.getOpeningBasePrices(d16),
      ).thenAnswer((_) async => {'9901': 2385, '9902': 9.5});
      expect(await run(['--market', 'TWSE']), 0);
      verify(() => twse.getOpeningBasePrices(d16)).called(1);
      verifyNever(() => twse.getOpeningBasePrices(d17));
      expect((await price('9901', d16)).priceChange, -5.0);

      expect(await run(['--market', 'TWSE']), 0);
      verifyNever(() => twse.getOpeningBasePrices(any()));
    });

    test(
      '🚨 套用：X 列 0 → 收盤−平盤價；收盤 null 的列漲跌 → null；一般列值不變；其他欄與 ledger 不動',
      () async {
        await db.insertPrices([
          row('9901', d16, close: 2380, change: 0),
          row('9902', d16, close: 10, change: 0.5),
          row('9903', d16, close: null, change: 0),
          row('9911', d16, close: null, change: 0),
        ]);
        // insertPrices 的第 0 條已把沒成交列寫成 null，這裡模擬舊資料存 0
        await db.customStatement(
          'UPDATE daily_price SET price_change = 0 WHERE close IS NULL',
        );
        await db.upsertMarketDayFetch(
          dataset: MarketDataset.prices.code,
          market: MarketCode.twse,
          date: d16,
          fetchedAt: d17,
          rowCount: 3,
        );
        when(
          () => twse.getOpeningBasePrices(d16),
        ).thenAnswer((_) async => {'9901': 2385, '9902': 9.5});
        expect(await run(['--market', 'TWSE']), 0);
        final a = await price('9901', d16);
        expect((a.priceChange, a.basePrice), (-5.0, 2385.0));
        expect((a.open, a.high, a.low, a.volume), (2380, 2380, 2380, 1000));
        final b = await price('9902', d16);
        expect((b.priceChange, b.basePrice), (0.5, 9.5));
        final c = await price('9903', d16);
        expect(
          (c.priceChange, c.basePrice),
          (null, null),
          reason: '沒成交列漲跌改空值（接上 nullify）',
        );
        expect(
          (await price('9911', d16)).priceChange,
          0,
          reason: '上櫃的沒成交列不動（市場參數）',
        );
        final fetches = await db.getMarketDayFetchesSince(d15);
        expect(fetches.single.rowCount, 3, reason: 'ledger 不動');
      },
    );

    test('某天網路錯誤 → 記失敗、繼續下一天、exit 1；已做的天保留', () async {
      await db.insertPrices([
        row('9901', d15, close: 10, change: 0),
        row('9901', d16, close: 2380, change: 0),
      ]);
      when(
        () => twse.getOpeningBasePrices(d15),
      ).thenThrow(const NetworkException('x'));
      when(
        () => twse.getOpeningBasePrices(d16),
      ).thenAnswer((_) async => {'9901': 2385});
      final logs = <String>[];
      expect(await run(['--market', 'TWSE'], logs: logs), 1);
      expect((await price('9901', d16)).priceChange, -5.0);
      expect((await price('9901', d15)).basePrice, isNull);
      expect(logs, anyElement(contains('2026-09-15')));
    });

    test('限流 → exit 4、之後的天不再打', () async {
      await db.insertPrices([
        row('9901', d15, close: 10, change: 0),
        row('9901', d16, close: 2380, change: 0),
      ]);
      when(
        () => twse.getOpeningBasePrices(d15),
      ).thenThrow(const RateLimitException('r'));
      expect(await run(['--market', 'TWSE']), 4);
      verifyNever(() => twse.getOpeningBasePrices(d16));
    });

    test('🚨 做過沒是比例：先跑上櫃把平盤價寫進轉市場列（主檔上市）後，那天仍會抓 TWT84U', () async {
      await db.insertPrices([
        row('9901', oldExDay, close: 10, change: 0),
        row('9902', oldExDay, close: 10, change: 0),
        row('9904', oldExDay, close: 41.45, change: null), // 8908 型
        row(
          '9911',
          DateContext.normalize(DateTime(2025, 9, 10)),
          close: 10,
          change: 0.5,
        ),
      ]);
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2025, 9, 1),
          endDate: DateTime(2025, 9, 30),
        ),
      ).thenAnswer((_) async => [ex('9904', oldExDay, base: 40)]);
      expect(await run(['--market', 'TPEx']), 0);
      expect(
        (await price('9904', oldExDay)).basePrice,
        40.0,
        reason: '前提：轉市場列已有平盤價',
      );

      when(
        () => twse.getOpeningBasePrices(oldExDay),
      ).thenAnswer((_) async => {'9901': 9.5, '9902': 9.5});
      expect(await run(['--market', 'TWSE']), 0);
      verify(() => twse.getOpeningBasePrices(oldExDay)).called(1);
      expect((await price('9901', oldExDay)).priceChange, 0.5);
    });

    test(
      '🚨 每天一個 transaction：nullify 拋錯 → 該天 rollback（base_price 仍 null）、exit 1、重跑會再挑到',
      () async {
        final throwing = _NullifyThrows();
        addTearDown(throwing.close);
        await throwing.upsertStocks([
          StockMasterCompanion.insert(
            symbol: '9901',
            name: '9901',
            market: MarketCode.twse,
          ),
        ]);
        await throwing.insertPrices([row('9901', d16, close: 2380, change: 0)]);
        when(
          () => twse.getOpeningBasePrices(d16),
        ).thenAnswer((_) async => {'9901': 2385});
        final code = await runBasePriceBackfill(
          ['--market', 'TWSE'],
          twse: twse,
          tpex: tpex,
          db: throwing,
          callDelay: Duration.zero,
          log: (_) {},
        );
        expect(code, 1);
        final a = (await throwing.getPriceHistory(
          '9901',
          startDate: d16,
          endDate: d16,
        )).single;
        expect(
          (a.priceChange, a.basePrice),
          (0.0, null),
          reason: 'apply 已做、nullify 拋錯 → 整天 rollback',
        );
        expect(await throwing.getTwseDaysWithoutBasePrice(), [
          d16,
        ], reason: '重跑會再挑到');
      },
    );

    test('上櫃當月的 endDate 夾到今天（迄日在未來的請求形狀沒驗過）', () async {
      await db.insertPrices([row('9911', exDay, close: 32.12, change: null)]);
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 27),
        ),
      ).thenAnswer((_) async => [ex('9911', exDay, base: 32.44)]);
      expect(
        await runBasePriceBackfill(
          ['--market', 'TPEx'],
          twse: twse,
          tpex: tpex,
          db: db,
          callDelay: Duration.zero,
          log: (_) {},
          today: DateTime(2026, 10, 27, 19, 30),
        ),
        0,
      );
      expect((await price('9911', exDay)).priceChange, -0.32);
    });

    test('--from／--to 限定範圍', () async {
      await db.insertPrices([
        row('9901', d15, close: 10, change: 0),
        row('9901', d16, close: 2380, change: 0),
      ]);
      when(
        () => twse.getOpeningBasePrices(any()),
      ).thenAnswer((_) async => {'9901': 9});
      expect(await run(['--market', 'TWSE', '--from', '2026-09-16']), 0);
      verify(() => twse.getOpeningBasePrices(d16)).called(1);
      verifyNever(() => twse.getOpeningBasePrices(d15));
    });
  });

  group('上櫃（逐月 exDailyQ）', () {
    test('🚨 逐月抓、套用到 (symbol, exDate) 已存在的列；主檔是上市的轉市場列也套（不依目前市場過濾）', () async {
      await db.insertPrices([
        row('9911', exDay, close: 32.12, change: null),
        row(
          '9911',
          DateContext.normalize(DateTime(2025, 9, 10)),
          close: 10,
          change: 0.5,
        ),
        row('9904', oldExDay, close: 41.45, change: null), // 8908 型：主檔上市、資料是上櫃
      ]);
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 31),
        ),
      ).thenAnswer((_) async => [ex('9911', exDay, base: 32.44)]);
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2025, 9, 1),
          endDate: DateTime(2025, 9, 30),
        ),
      ).thenAnswer((_) async => [ex('9904', oldExDay, base: 40)]);
      expect(await run(['--market', 'TPEx']), 0);
      final a = await price('9911', exDay);
      expect((a.priceChange, a.basePrice), (-0.32, 32.44));
      final b = await price('9904', oldExDay);
      expect((b.priceChange, b.basePrice), (1.45, 40.0));
      verify(
        () => tpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(2);
      verifyNever(() => twse.getOpeningBasePrices(any()));
    });

    test('tradingBasePrice null 的列不套；不存在的 (symbol, date) 不插入', () async {
      await db.insertPrices([row('9911', exDay, close: 32.12, change: null)]);
      when(
        () => tpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer(
        (_) async => [
          ex('9911', exDay, base: null),
          ex('9912', exDay, base: 5),
        ],
      );
      expect(await run(['--market', 'TPEx']), 0);
      final a = await price('9911', exDay);
      expect((a.priceChange, a.basePrice), (null, null));
      expect(
        await db.getPriceHistory('9912', startDate: exDay, endDate: exDay),
        isEmpty,
      );
    });

    test('上櫃某月限流 → exit 4；網路錯誤 → 記失敗、繼續、exit 1', () async {
      await db.insertPrices([
        row(
          '9911',
          DateContext.normalize(DateTime(2025, 9, 10)),
          close: 10,
          change: 0.5,
        ),
        row('9911', exDay, close: 32.12, change: null),
      ]);
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2025, 9, 1),
          endDate: DateTime(2025, 9, 30),
        ),
      ).thenThrow(const NetworkException('x'));
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 31),
        ),
      ).thenAnswer((_) async => [ex('9911', exDay, base: 32.44)]);
      expect(await run(['--market', 'TPEx']), 1);
      expect((await price('9911', exDay)).priceChange, -0.32);

      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2025, 9, 1),
          endDate: DateTime(2025, 9, 30),
        ),
      ).thenThrow(const RateLimitException('r'));
      expect(await run(['--market', 'TPEx']), 4);
    });
  });

  test('--dry-run 不開網路、只印數量', () async {
    await db.insertPrices([
      row('9901', d16, close: 2380, change: 0),
      row('9911', exDay, close: 32.12, change: null),
    ]);
    final logs = <String>[];
    expect(await run(['--dry-run'], logs: logs), 0);
    verifyNever(() => twse.getOpeningBasePrices(any()));
    verifyNever(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    );
    expect(logs.join('\n'), allOf(contains('1 天'), contains('1 個月')));
  });

  test('both：上市先、上櫃後，結尾印缺平盤價計數', () async {
    await db.insertPrices([
      row('9901', d16, close: 2380, change: 0),
      row('9911', exDay, close: 32.12, change: null),
    ]);
    when(
      () => twse.getOpeningBasePrices(d16),
    ).thenAnswer((_) async => {'9901': 2385});
    when(
      () => tpex.getExRightResults(
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      ),
    ).thenAnswer((_) async => [ex('9911', exDay, base: 32.44)]);
    final logs = <String>[];
    expect(await run(const [], logs: logs), 0);
    verifyInOrder([
      () => twse.getOpeningBasePrices(d16),
      () => tpex.getExRightResults(
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      ),
    ]);
    expect(logs.last, allOf(contains('上市 0'), contains('上櫃 0')));
  });
}

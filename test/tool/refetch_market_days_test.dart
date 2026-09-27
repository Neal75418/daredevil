import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';

import 'dart:io';

import '../../tool/refetch_market_days.dart';

class _MockPriceRepository extends Mock implements IPriceRepository {}

void main() {
  List<String> errs = [];
  RefetchArgs? parse(List<String> a, {DateTime? today}) {
    errs = [];
    return parseRefetchArgs(a, errs.add, today: today);
  }

  test('完整參數', () {
    final a = parse([
      '--dataset',
      'prices',
      '--market',
      'TPEx',
      '--from',
      '2025-06-10',
      '--to',
      '2026-09-24',
      '--dry-run',
    ]);
    expect(a!.dataset, MarketDataset.prices);
    expect(a.market, MarketCode.tpex);
    expect(a.from, DateTime(2025, 6, 10));
    expect(a.to, DateTime(2026, 9, 24));
    expect(a.dryRun, isTrue);
    expect(a.valuation, isFalse);
  });

  test('valuation 與 institutional 不需要 --market', () {
    expect(
      parse([
        '--dataset',
        'valuation',
        '--from',
        '2026-07-15',
        '--to',
        '2026-09-24',
      ])!.valuation,
      isTrue,
    );
    expect(
      parse([
        '--dataset',
        'institutional',
        '--from',
        '2026-07-16',
        '--to',
        '2026-08-19',
      ]),
      isNotNull,
    );
  });

  test('🚨 valuation／institutional 多帶 --market 被拒（不是自動忽略）', () {
    expect(
      parse([
        '--dataset',
        'valuation',
        '--market',
        'TWSE',
        '--from',
        '2026-07-15',
        '--to',
        '2026-09-24',
      ]),
      isNull,
    );
    expect(
      parse([
        '--dataset',
        'institutional',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-08-19',
      ]),
      isNull,
    );
    // 對照：不帶 --market 才接受（同上一組測試）
  });

  test('未知旗標被拒（打錯字不可默默落回預設 DB）', () {
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
        '--database',
        'x',
      ]),
      isNull,
    );
    expect(errs.join(), contains('--database'));
  });

  test('缺 --to、from 晚於 to、未知資料集、缺必要的 --market 都被拒', () {
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
      ]),
      isNull,
    );
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-09-24',
        '--to',
        '2026-07-16',
      ]),
      isNull,
    );
    expect(
      parse(['--dataset', 'foo', '--from', '2026-07-16', '--to', '2026-09-24']),
      isNull,
    );
    expect(
      parse([
        '--dataset',
        'margin',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
      ]),
      isNull,
    );
  });

  test('🚨 --db 缺值（在最末或後接旗標）被拒，不可落回實際 app DB', () {
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
        '--db',
      ]),
      isNull,
    );
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
        '--db',
        '--dry-run',
      ]),
      isNull,
    );
    expect(errs.join(), contains('--db'));
    // 對照：有給值時接受
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
        '--db',
        'copy.db',
      ])!.dbPath,
      'copy.db',
    );
  });

  test('🚨 沒被消化的 token 一律拒絕：單橫線／em dash／裸值／重複旗標', () {
    final base = [
      '--dataset',
      'prices',
      '--market',
      'TWSE',
      '--from',
      '2026-07-16',
      '--to',
      '2026-07-16',
    ];

    // 單橫線 `-db`：不是已知旗標，後面的路徑也不會被誤吃成值
    expect(parse([...base, '-db', '/tmp/copy.db']), isNull);
    expect(errs.join(), contains('-db'));
    // 對照：雙橫線正確
    expect(parse([...base, '--db', 'copy.db'])!.dbPath, 'copy.db');

    // em dash `—db`（U+2014，不是 ASCII 雙橫線，容易複製貼上時混入）
    expect(parse([...base, '—db', 'copy.db']), isNull);
    expect(errs.join(), contains('—db'));

    // 忘了寫旗標名，只留下裸路徑
    expect(parse([...base, 'copy.db']), isNull);
    expect(errs.join(), contains('copy.db'));

    // 單橫線 `-dry-run`：漏寫成單橫線時絕不能被忽略、變成真的執行
    expect(parse([...base, '-dry-run']), isNull);
    expect(errs.join(), contains('-dry-run'));
    // 對照：雙橫線正確
    expect(parse([...base, '--dry-run'])!.dryRun, isTrue);

    // 同一個值旗標重複出現
    expect(parse([...base, '--db', 'a', '--db', 'b']), isNull);
    expect(errs.join(), contains('--db'));
    // 對照：單一 --db 正確
    expect(parse([...base, '--db', 'a'])!.dbPath, 'a');
  });

  test('🚨 --to 是台北今天 → 被拒（當天的資料不會定案）', () {
    final today = DateTime(2026, 9, 24);
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
      ], today: today),
      isNull,
    );
    expect(errs.join(), contains('--to 必須早於台北今天（當天的資料不會定案）'));
    // 對照：--to 是前一天則接受
    expect(
      parse([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-23',
      ], today: today)!.to,
      DateTime(2026, 9, 23),
    );
  });

  test('--db 指到不存在的檔案 → 退出碼 2，不建立新 DB', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'refetch_market_days_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final path = '${tempDir.path}/nonexistent.db';
    expect(
      await runRefetchCli([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-07-16',
        '--db',
        path,
      ]),
      2,
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('🚨 --dry-run 搭配不存在的 --db → 回 0，且不建立檔案（dry-run 不開 DB）', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'refetch_market_days_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final path = '${tempDir.path}/nonexistent.db';
    expect(
      await runRefetchCli([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-07-16',
        '--db',
        path,
        '--dry-run',
      ]),
      0,
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('🚨 --db 指向非 SQLite 檔案 → 退出碼 2，內容不被更動（開 DB 前失敗，不連網）', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'refetch_market_days_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final path = '${tempDir.path}/fake.db';
    const content = 'this is not a sqlite file';
    File(path).writeAsStringSync(content);
    expect(
      await runRefetchCli([
        '--dataset',
        'prices',
        '--market',
        'TWSE',
        '--from',
        '2026-07-16',
        '--to',
        '2026-07-16',
        '--db',
        path,
      ]),
      2,
    );
    expect(File(path).readAsStringSync(), content);
  });

  test('外資持股只有上市', () {
    expect(
      parse([
        '--dataset',
        'foreignShareholding',
        '--market',
        'TPEx',
        '--from',
        '2026-07-16',
        '--to',
        '2026-09-24',
      ]),
      isNull,
    );
  });

  group('describeRemainingDays（純函式，組出續跑訊息）', () {
    test('全部嘗試完畢 → 訊息說明已全部嘗試，不需要續跑', () {
      final msg = describeRemainingDays(
        totalDays: 5,
        attemptedDays: 5,
        notAttempted: [],
      );
      expect(msg, contains('已全部嘗試'));
      expect(msg, contains('5'));
    });

    test('尚有未嘗試天數 → 訊息帶總數／已嘗試數／未嘗試數與續跑日期', () {
      // notAttempted 是 days 的尾段，新→舊排序；第一筆是其中最新的一天
      final notAttempted = [
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 17),
        DateTime(2026, 7, 16),
      ];
      final msg = describeRemainingDays(
        totalDays: 8,
        attemptedDays: 5,
        notAttempted: notAttempted,
      );
      expect(msg, contains('8'));
      expect(msg, contains('5'));
      expect(msg, contains('3'));
      expect(msg, contains('2026-07-20')); // 續跑日＝未嘗試中最新的一天
      expect(msg, contains('--to'));
    });
  });

  group('computeNotAttempted（純函式，修正 attempted 的 off-by-one）', () {
    // D1（最新）..D10（最舊），符合 days 的新→舊排序慣例
    final days = List<DateTime>.generate(10, (i) => DateTime(2026, 7, 10 - i));

    test('🚨 中止案例（限流或網路錯誤）：出事的那一天算回未嘗試', () {
      // MarketDayRefetcher._execute 在呼叫 fetch 前就先把 attempted 加 1，
      // 所以 D4 出事時 attempted 已經是 4，但 D4 的 fetch 其實沒有成功。
      final notAttempted = computeNotAttempted(days: days, attempted: 4);
      expect(notAttempted.length, 7);
      expect(notAttempted.first, days[3]); // D4，出事的那一天，不能被跳過
      expect(notAttempted.last, days[9]); // D10
    });

    test('正常完成（沒有中止）：attempted == days.length → 沒有未嘗試', () {
      expect(computeNotAttempted(days: days, attempted: 10), isEmpty);
    });
  });

  group('computeNotAttempted × MarketDayRefetcher（整合：驗證 stoppedAt 真的接上，'
      '不是靠 attempted 次數回推）', () {
    late AppDatabase db;
    late _MockPriceRepository price;

    setUpAll(() {
      registerFallbackValue(DateTime(2026));
      registerFallbackValue(<String>{});
    });

    setUp(() {
      db = AppDatabase.forTesting();
      price = _MockPriceRepository();
    });

    tearDown(() => db.close());

    // 由 [end] 往回數 [count] 個真實交易日（新→舊），與 days 的排序慣例
    // 一致；避免手動硬編日期還要對照假期表。
    List<DateTime> tradingDaysEndingAt(DateTime end, int count) {
      final result = <DateTime>[];
      var d = end;
      while (result.length < count) {
        if (TaiwanCalendar.isTradingDay(d)) result.add(d);
        d = DateTime(d.year, d.month, d.day - 1);
      }
      return result;
    }

    const group = (dataset: MarketDataset.prices, market: MarketCode.twse);

    test('🚨 在最後一天（範圍內最舊的候選日）中止 → 未嘗試 1 日，--to 是那一天'
        '（僅靠 attempted 次數回推會誤判成「已全部嘗試」，這是後備算法無法區分的邊界情況）', () async {
      final days = tradingDaysEndingAt(DateTime(2026, 9, 24), 10);
      final stoppedDay = days.last;
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((inv) async {
        final date = inv.namedArguments[#date] as DateTime;
        if (date == stoppedDay) throw const RateLimitException('429');
        return 1;
      });
      final refetcher = MarketDayRefetcher(
        database: db,
        priceRepository: price,
        callDelay: Duration.zero,
      );
      final ledger = MarketDayFetchLedger(database: db, fetchedAt: days.first);
      final summary = await refetcher.refetchRange(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        from: days.last,
        to: days.first,
        ledger: ledger,
      );
      final notAttempted = computeNotAttempted(
        days: days,
        attempted: summary.attempted[group] ?? 0,
        stoppedAt: summary.stoppedAt,
      );
      expect(notAttempted.length, 1);
      expect(notAttempted.first, stoppedDay);
    });

    test('🚨 只有 1 天、那天被限流 → 未嘗試 1 日（不是「已全部嘗試」）', () async {
      final days = tradingDaysEndingAt(DateTime(2026, 9, 24), 1);
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenThrow(const RateLimitException('429'));
      final refetcher = MarketDayRefetcher(
        database: db,
        priceRepository: price,
        callDelay: Duration.zero,
      );
      final ledger = MarketDayFetchLedger(database: db, fetchedAt: days.first);
      final summary = await refetcher.refetchRange(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        from: days.first,
        to: days.first,
        ledger: ledger,
      );
      final notAttempted = computeNotAttempted(
        days: days,
        attempted: summary.attempted[group] ?? 0,
        stoppedAt: summary.stoppedAt,
      );
      expect(notAttempted.length, 1);
    });

    test('🚨 網路錯誤（不是限流）在最後一天中止 → 未嘗試 1 日，--to 是那一天'
        '（涵蓋 stoppedAt 的 NetworkException 分支）', () async {
      final days = tradingDaysEndingAt(DateTime(2026, 9, 24), 10);
      final stoppedDay = days.last;
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((inv) async {
        final date = inv.namedArguments[#date] as DateTime;
        if (date == stoppedDay) throw const NetworkException('x');
        return 1;
      });
      final refetcher = MarketDayRefetcher(
        database: db,
        priceRepository: price,
        callDelay: Duration.zero,
      );
      final ledger = MarketDayFetchLedger(database: db, fetchedAt: days.first);
      final summary = await refetcher.refetchRange(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        from: days.last,
        to: days.first,
        ledger: ledger,
      );
      final notAttempted = computeNotAttempted(
        days: days,
        attempted: summary.attempted[group] ?? 0,
        stoppedAt: summary.stoppedAt,
      );
      expect(notAttempted.length, 1);
      expect(notAttempted.first, stoppedDay);
    });
  });

  group('resumeHint（純函式，接線 stoppedAt → describeRemainingDays）', () {
    test('沒有失敗也沒有被限流 → null（不需要印續跑提示）', () {
      final days = List<DateTime>.generate(5, (i) => DateTime(2026, 7, 5 - i));
      final summary = RefetchSummary();
      summary.attempted[(
            dataset: MarketDataset.prices,
            market: MarketCode.twse,
          )] =
          5;
      final hint = resumeHint(
        days: days,
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        summary: summary,
      );
      expect(hint, isNull);
    });

    test('中間中止：算出 --to 與未嘗試日數', () {
      final days = List<DateTime>.generate(
        10,
        (i) => DateTime(2026, 7, 10 - i),
      );
      const group = (dataset: MarketDataset.prices, market: MarketCode.twse);
      final summary = RefetchSummary()
        ..rateLimitError = Exception('429')
        ..stoppedAt = days[3];
      summary.attempted[group] = 4;
      final hint = resumeHint(
        days: days,
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        summary: summary,
      );
      expect(hint, isNotNull);
      expect(hint, contains('尚有 7 日未嘗試'));
      expect(hint, contains('--to ${DateContext.formatYmd(days[3])}'));
    });

    test('🚨 最後一天中止仍正確接上 stoppedAt（僅靠 attempted 的後備在此邊界'
        '會誤判成「已全部嘗試」）', () {
      final days = List<DateTime>.generate(
        10,
        (i) => DateTime(2026, 7, 10 - i),
      );
      const group = (dataset: MarketDataset.prices, market: MarketCode.twse);
      final summary = RefetchSummary()
        ..rateLimitError = Exception('429')
        ..stoppedAt = days.last;
      // 出事那天已被 attempt() 算進 attempted（見 MarketDayRefetcher._execute），
      // 剛好等於 days.length——這正是 stoppedAt 判準要解決的邊界。
      summary.attempted[group] = days.length;
      final hint = resumeHint(
        days: days,
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        summary: summary,
      );
      expect(hint, isNotNull);
      expect(hint, contains('尚有 1 日未嘗試'));
      expect(hint, contains('--to ${DateContext.formatYmd(days.last)}'));
    });

    test('institutional 取 TWSE 那組代表整體進度', () {
      final days = List<DateTime>.generate(5, (i) => DateTime(2026, 7, 5 - i));
      const twseGroup = (
        dataset: MarketDataset.institutional,
        market: MarketCode.twse,
      );
      const tpexGroup = (
        dataset: MarketDataset.institutional,
        market: MarketCode.tpex,
      );
      final summary = RefetchSummary()
        ..rateLimitError = Exception('429')
        ..stoppedAt = days[2];
      summary.attempted[twseGroup] = 2;
      summary.attempted[tpexGroup] = 2;
      final hint = resumeHint(
        days: days,
        dataset: MarketDataset.institutional,
        market: MarketCode.twse, // refetchRange 對 institutional 會忽略這個值
        summary: summary,
      );
      expect(hint, isNotNull);
      expect(hint, contains('--to ${DateContext.formatYmd(days[2])}'));
    });
  });
}

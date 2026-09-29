// 除權除息歷史回補修復工具（tool/backfill_dividend_distributions.dart）
//
// 與每輪更新共用 DividendBackfiller。這裡驗參數解析與「打 API 之前」就該
// 擋下的情況（全部在建立 client 之前返回，不連網）。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/domain/services/update/dividend_backfiller.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';

import '../../tool/backfill_dividend_distributions.dart';

class MockDividendBackfiller extends Mock implements DividendBackfiller {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  final now = DateTime(2026, 9, 29, 22, 0);
  var errs = <String>[];
  BackfillDividendArgs? parse(List<String> a) {
    errs = [];
    return parseBackfillDividendArgs(a, errs.add, now: now);
  }

  group('參數', () {
    test('預設：整個回補範圍、兩個市場、實際 app DB', () {
      final a = parse(const [])!;
      expect(a.from, const CalendarMonth(2021, 1));
      expect(a.to, const CalendarMonth(2026, 8));
      expect(a.markets, isNull);
      expect(a.recheck, isFalse);
      expect(a.dryRun, isFalse);
      expect(a.dbPath, contains('com.neo.afterclose'));
      expect(a.dbPath, endsWith('afterclose.sqlite'));
    });

    test('完整參數', () {
      final a = parse(const [
        '--from',
        '2025-06',
        '--to',
        '2025-09',
        '--market',
        'TPEx',
        '--recheck',
        '--db',
        '/tmp/copy.sqlite',
        '--dry-run',
      ])!;
      expect(a.from, const CalendarMonth(2025, 6));
      expect(a.to, const CalendarMonth(2025, 9));
      expect(a.markets, {MarketCode.tpex});
      expect(a.recheck, isTrue);
      expect(a.dbPath, '/tmp/copy.sqlite');
      expect(a.dryRun, isTrue);
    });

    test('🚨 沒被消化的 token 一律拒絕：未知、單橫線、em dash、裸值', () {
      for (final bad in [
        ['--database', 'x'],
        ['-db', 'x'],
        ['—db', 'x'],
        ['2025-06'],
        ['-dry-run'],
      ]) {
        expect(parse(bad), isNull, reason: '$bad');
        expect(errs.join(), contains('無法識別'), reason: '$bad');
      }
    });

    test('🚨 --db 缺值（在最末或後接旗標）被拒，不可落回實際 app DB', () {
      expect(parse(const ['--db']), isNull);
      expect(parse(const ['--db', '--dry-run']), isNull);
      expect(errs.join(), contains('缺值'));
    });

    test('重複旗標被拒', () {
      expect(parse(const ['--db', 'a', '--db', 'b']), isNull);
      expect(parse(const ['--recheck', '--recheck']), isNull);
      expect(errs.join(), contains('重複'));
    });

    test('月份格式與範圍：YYYY-MM、from ≤ to、早於本月、不早於回補範圍', () {
      for (final bad in [
        ['--from', '2026-9'],
        ['--from', '2026-13'],
        ['--from', '2026-06-01'],
        ['--from', '202606'],
        ['--from', '2026-07', '--to', '2026-06'],
        ['--to', '2026-09'],
        ['--from', '2020-12'],
      ]) {
        expect(parse(bad), isNull, reason: '$bad');
      }
    });

    test('市場必須是 TWSE 或 TPEx（大小寫完全一致）', () {
      expect(parse(const ['--market', 'TPEX']), isNull);
      expect(parse(const ['--market', 'TWSE'])!.markets, {MarketCode.twse});
    });
  });

  group('打 API 之前就擋下', () {
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('backfill_dividend_tool_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<int> run(List<String> args) =>
        runBackfillDividendCli(args, now: now);

    test('🚨 --dry-run 搭配不存在的 --db → 回 0，且不建立檔案', () async {
      final path = '${tempDir.path}/none.sqlite';
      expect(await run(['--db', path, '--dry-run']), 0);
      expect(File(path).existsSync(), isFalse);
    });

    test('--db 不存在 → 2，不建立新 DB', () async {
      final path = '${tempDir.path}/none.sqlite';
      expect(await run(['--db', path]), 2);
      expect(File(path).existsSync(), isFalse);
    });

    test('--db 不是 SQLite → 2，內容不變', () async {
      final path = '${tempDir.path}/fake.sqlite';
      File(path).writeAsStringSync('not sqlite');
      expect(await run(['--db', path]), 2);
      expect(File(path).readAsStringSync(), 'not sqlite');
    });

    Future<String> freshDb({
      int stocksPerMarket = 0,
      bool running = false,
    }) async {
      final path = '${tempDir.path}/db.sqlite';
      final db = AppDatabase(NativeDatabase(File(path)));
      await db.upsertStocks([
        for (final market in [MarketCode.twse, MarketCode.tpex])
          for (var i = 0; i < stocksPerMarket; i++)
            StockMasterCompanion.insert(
              symbol: '$market$i',
              name: '$market$i',
              market: market,
            ),
      ]);
      if (running) {
        await db.createUpdateRun(
          DateTime(2026, 9, 29),
          UpdateStatus.running.code,
        );
      }
      await db.close();
      return path;
    }

    test('有更新正在跑（最新一筆 RUNNING）→ 2', () async {
      final path = await freshDb(stocksPerMarket: 500, running: true);
      expect(await run(['--db', path]), 2);
    });

    test('RUNNING 超過孤兒門檻不算正在跑；門檻內、或最新一筆不是 RUNNING 才分得出', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final started = DateTime(2026, 9, 29, 20, 0);
      Future<String?> at(DateTime clock) =>
          runningUpdateNotice(db, clock: clock);

      expect(await at(started), isNull, reason: '沒有任何更新紀錄');
      await db
          .into(db.updateRun)
          .insert(
            UpdateRunCompanion.insert(
              runDate: DateTime(2026, 9, 29),
              status: UpdateStatus.running.code,
              startedAt: Value(started),
            ),
          );
      expect(await at(started.add(const Duration(hours: 2))), isNotNull);
      expect(
        await at(started.add(const Duration(hours: 2, minutes: 1))),
        isNull,
        reason: 'App 被強制結束留下的 RUNNING 不可永遠擋住工具',
      );
      await db
          .into(db.updateRun)
          .insert(
            UpdateRunCompanion.insert(
              runDate: DateTime(2026, 9, 29),
              status: UpdateStatus.success.code,
              startedAt: Value(started),
            ),
          );
      expect(await at(started), isNull, reason: '最新一筆已結束');
    });

    test('🚨 市場被停掉（斷路器、網路）後，之後的月份不再處理它；全部停掉就結束、回 1', () async {
      registerFallbackValue(const DividendBackfillScope());
      final path = await freshDb(stocksPerMarket: 500);
      final fake = MockDividendBackfiller();
      final calls = <String>[];
      when(
        () => fake.backfill(
          now: any(named: 'now'),
          maxCalls: any(named: 'maxCalls'),
          scope: any(named: 'scope'),
          breaker: any(named: 'breaker'),
        ),
      ).thenAnswer((inv) async {
        final scope = inv.namedArguments[#scope] as DividendBackfillScope;
        calls.add(
          '${scope.from} ${(scope.markets!.toList()..sort()).join(',')}',
        );
        return DividendBackfillSummary(
          calls: 1,
          maxCalls: 1 << 30,
          completed: const [],
          failures: const [],
          marketStops: switch (calls.length) {
            1 => {MarketCode.twse: 'TWSE 連續 3 次失敗，本輪停止'},
            2 => {MarketCode.tpex: 'TPEx 網路錯誤，本輪停止'},
            _ => const {},
          },
          rateLimitError: null,
          stoppedAt: null,
          coverage: DividendCoverage.compute(
            now: now,
            ledger: const [],
            failures: const [],
            knownSymbols: const {},
          ),
        );
      });

      final code = await runBackfillDividendCli(
        ['--db', path, '--from', '2026-05', '--to', '2026-08'],
        now: now,
        backfillerFactory: (_) => fake,
      );

      expect(calls, ['2026-08 TPEx,TWSE', '2026-07 TPEx']);
      expect(code, 1);
    });

    test('🚨 端點改版（每月列表都失敗）：斷路器計數跨月延續，連 3 個月就停，不把整個範圍白打一遍', () async {
      registerFallbackValue(DateTime(2000));
      final path = await freshDb(stocksPerMarket: 500);
      final tpex = MockTpexClient();
      when(
        () => tpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const ApiException('改版', 200));

      final code = await runBackfillDividendCli(
        [
          '--db',
          path,
          '--from',
          '2026-03',
          '--to',
          '2026-08',
          '--market',
          'TPEx',
        ],
        now: now,
        backfillerFactory: (db) => DividendBackfiller(
          database: db,
          tpexClient: tpex,
          callDelay: Duration.zero,
        ),
      );

      verify(
        () => tpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(3);
      expect(code, 1);
    });

    test('在市主檔不足門檻 → 2', () async {
      final path = await freshDb(stocksPerMarket: 10);
      expect(await run(['--db', path]), 2);
    });
  });

  test('退出碼：限流 4 優先；仍有未完成 1；全部完成 0', () {
    expect(backfillDividendExitCode(rateLimited: true, missing: 3), 4);
    expect(backfillDividendExitCode(rateLimited: true, missing: 0), 4);
    expect(backfillDividendExitCode(rateLimited: false, missing: 3), 1);
    expect(backfillDividendExitCode(rateLimited: false, missing: 0), 0);
  });
}

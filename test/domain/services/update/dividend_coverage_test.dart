// 除權除息逐月回補的完整度判準與規劃（dividend_coverage.dart）
//
// 回補排程、修復工具的退出碼、每輪日誌與第 3 段的讀取端共用同一份定義。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';

DividendMonthLedgerEntry _ledger(
  String market,
  CalendarMonth month, {
  String skipped = '',
  DateTime? completedAt,
}) => DividendMonthLedgerEntry(
  market: market,
  year: month.year,
  month: month.month,
  completedAt: completedAt ?? DateTime(2026, 9, 1),
  listedRows: 10,
  knownRows: 8,
  skippedSymbols: skipped,
);

DividendMonthFailureEntry _failure(
  String market,
  CalendarMonth month, {
  required int count,
  required DateTime at,
}) => DividendMonthFailureEntry(
  market: market,
  year: month.year,
  month: month.month,
  failCount: count,
  lastFailedAt: at,
  lastError: 'boom',
  failedSymbols: '',
  listOk: false,
);

void main() {
  final now = DateTime(2026, 9, 29, 15, 30);
  const aug = CalendarMonth(2026, 8);
  const jul = CalendarMonth(2026, 7);

  group('dividendBackfillTarget：上個月～今年往前 5 年的 1 月', () {
    test('2026-09-29 → 2021-01～2026-08（68 個月）', () {
      final t = dividendBackfillTarget(now);
      expect(t.from, const CalendarMonth(2021, 1));
      expect(t.to, aug);
      expect(CalendarMonth.descending(from: t.from, to: t.to), hasLength(68));
    });

    test('跨年：2027-01-05 → 2022-01～2026-12', () {
      final t = dividendBackfillTarget(DateTime(2027, 1, 5));
      expect(t.from, const CalendarMonth(2022, 1));
      expect(t.to, const CalendarMonth(2026, 12));
    });

    test('年底：2026-12-31 → 2021-01～2026-11', () {
      final t = dividendBackfillTarget(DateTime(2026, 12, 31, 23, 59));
      expect(t.from, const CalendarMonth(2021, 1));
      expect(t.to, const CalendarMonth(2026, 11));
    });

    test('深度取自 ApiConfig', () {
      expect(ApiConfig.dividendBackfillYears, 5);
    });
  });

  group('isDividendMonthComplete', () {
    const current = CalendarMonth(2026, 9);

    test('沒有完成紀錄 → 未完成', () {
      expect(
        isDividendMonthComplete(null, knownSymbols: {}, currentMonth: current),
        isFalse,
      );
    });

    test('有紀錄、沒有略過代號 → 完成', () {
      expect(
        isDividendMonthComplete(
          _ledger(MarketCode.twse, aug),
          knownSymbols: {'2330'},
          currentMonth: current,
        ),
        isTrue,
      );
    });

    test('當時略過的代號如今在市 → 未完成（要重開補齊）', () {
      expect(
        isDividendMonthComplete(
          _ledger(MarketCode.twse, aug, skipped: '00950B,910322'),
          knownSymbols: {'2330', '910322'},
          currentMonth: current,
        ),
        isFalse,
      );
    });

    test('當時略過的代號仍不在市 → 完成', () {
      expect(
        isDividendMonthComplete(
          _ledger(MarketCode.twse, aug, skipped: '00950B'),
          knownSymbols: {'2330'},
          currentMonth: current,
        ),
        isTrue,
      );
    });

    test('月中寫下的紀錄：下個月起也不算完成（只涵蓋到寫入當下）', () {
      expect(
        isDividendMonthComplete(
          _ledger(MarketCode.twse, aug, completedAt: DateTime(2026, 8, 15)),
          knownSymbols: const {},
          currentMonth: current,
        ),
        isFalse,
      );
    });

    test('本月或未來月份即使有紀錄也不算完成', () {
      for (final month in [current, const CalendarMonth(2026, 10)]) {
        expect(
          isDividendMonthComplete(
            _ledger(MarketCode.twse, month),
            knownSymbols: const {},
            currentMonth: current,
          ),
          isFalse,
          reason: '$month',
        );
      }
    });
  });

  group('isInRetryBackoff：第 3 次失敗起，7 天內不重試', () {
    test('失敗 2 次 → 不退避', () {
      expect(
        isInRetryBackoff(
          _failure(MarketCode.twse, aug, count: 2, at: now),
          now,
        ),
        isFalse,
      );
    });

    test('失敗 3 次、6 天 23 小時前 → 退避', () {
      expect(
        isInRetryBackoff(
          _failure(
            MarketCode.twse,
            aug,
            count: 3,
            at: now.subtract(const Duration(days: 6, hours: 23)),
          ),
          now,
        ),
        isTrue,
      );
    });

    test('失敗 3 次、剛好 7 天前 → 不退避', () {
      expect(
        isInRetryBackoff(
          _failure(
            MarketCode.twse,
            aug,
            count: 3,
            at: now.subtract(const Duration(days: 7)),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('上次失敗時間在未來（時鐘回撥）→ 視同過期，不退避', () {
      expect(
        isInRetryBackoff(
          _failure(
            MarketCode.twse,
            aug,
            count: 5,
            at: now.add(const Duration(days: 1)),
          ),
          now,
        ),
        isFalse,
      );
    });
  });

  group('dividendMarketSkipReason：在市主檔檔數門檻', () {
    test('剛好達門檻 → 放行', () {
      expect(dividendMarketSkipReason(MarketCode.twse, 500), isNull);
    });

    test('少於門檻 → 回傳原因（含市場與檔數）', () {
      final reason = dividendMarketSkipReason(MarketCode.tpex, 499);
      expect(reason, allOf(contains('TPEx'), contains('499')));
    });

    test('門檻可注入', () {
      expect(
        dividendMarketSkipReason(MarketCode.twse, 1, minStocks: 1),
        isNull,
      );
    });
  });

  group('DividendCoverage', () {
    DividendCoverage coverage({
      List<DividendMonthLedgerEntry> ledger = const [],
      List<DividendMonthFailureEntry> failures = const [],
      Set<String> known = const {'2330'},
    }) => DividendCoverage.compute(
      now: now,
      ledger: ledger,
      failures: failures,
      knownSymbols: known,
    );

    test('missing 由新到舊、同月上櫃在前；completedCount／unitCount', () {
      final c = coverage(ledger: [_ledger(MarketCode.tpex, aug)]);

      expect(c.missing(from: jul, to: aug), [
        (market: MarketCode.twse, month: aug),
        (market: MarketCode.tpex, month: jul),
        (market: MarketCode.twse, month: jul),
      ]);
      expect(c.completedCount(from: jul, to: aug), 1);
      expect(c.unitCount(from: jul, to: aug), 4);
    });

    test('只問單一市場時只算那個市場', () {
      final c = coverage(ledger: [_ledger(MarketCode.tpex, aug)]);

      expect(c.missing(from: jul, to: aug, markets: {MarketCode.twse}), [
        (market: MarketCode.twse, month: aug),
        (market: MarketCode.twse, month: jul),
      ]);
      expect(c.unitCount(from: jul, to: aug, markets: {MarketCode.twse}), 2);
    });

    test('failureOf：未完成單位回傳失敗紀錄；已完成單位殘留的失敗列忽略', () {
      final c = coverage(
        ledger: [_ledger(MarketCode.tpex, aug)],
        failures: [
          _failure(MarketCode.tpex, aug, count: 3, at: now),
          _failure(MarketCode.twse, aug, count: 1, at: now),
        ],
      );

      expect(c.failureOf((market: MarketCode.tpex, month: aug)), isNull);
      expect(c.failureOf((market: MarketCode.twse, month: aug))?.failCount, 1);
    });

    test('failureOf：重開的單位（有紀錄但略過代號如今在市）不忽略失敗', () {
      final c = coverage(
        ledger: [_ledger(MarketCode.twse, aug, skipped: '910322')],
        failures: [_failure(MarketCode.twse, aug, count: 3, at: now)],
        known: {'910322'},
      );

      expect(c.failureOf((market: MarketCode.twse, month: aug))?.failCount, 3);
    });

    group('plan', () {
      test('預設範圍＝回補目標，由新到舊、同月上櫃在前；三種動作', () {
        final c = coverage(
          ledger: [_ledger(MarketCode.tpex, aug)],
          failures: [_failure(MarketCode.twse, aug, count: 3, at: now)],
        );

        final plan = c.plan();
        expect(plan, hasLength(136));
        expect(plan.take(3).toList(), [
          (
            key: (market: MarketCode.tpex, month: aug),
            action: DividendUnitAction.skipComplete,
          ),
          (
            key: (market: MarketCode.twse, month: aug),
            action: DividendUnitAction.skipBackoff,
          ),
          (
            key: (market: MarketCode.tpex, month: jul),
            action: DividendUnitAction.process,
          ),
        ]);
        expect(plan.last.key, (
          market: MarketCode.twse,
          month: const CalendarMonth(2021, 1),
        ));
      });

      test('recheck：已完成的單位也要處理', () {
        final c = coverage(ledger: [_ledger(MarketCode.tpex, aug)]);

        expect(c.plan(from: aug, to: aug, recheck: true).map((u) => u.action), [
          DividendUnitAction.process,
          DividendUnitAction.process,
        ]);
      });

      test('ignoreBackoff：退避中的單位也要處理', () {
        final c = coverage(
          failures: [_failure(MarketCode.twse, aug, count: 3, at: now)],
        );

        expect(
          c.plan(from: aug, to: aug, ignoreBackoff: true).map((u) => u.action),
          [DividendUnitAction.process, DividendUnitAction.process],
        );
      });

      test('範圍上限夾在上個月：本月與未來月份不排入', () {
        expect(
          coverage()
              .plan(from: aug, to: const CalendarMonth(2026, 11))
              .map((u) => u.key.month)
              .toSet(),
          {aug},
        );
      });

      test('明確指定較早的上限時照用', () {
        expect(
          coverage()
              .plan(from: const CalendarMonth(2026, 6), to: jul)
              .map((u) => u.key.month)
              .toSet(),
          {jul, const CalendarMonth(2026, 6)},
        );
      });

      test('只指定上市：不產生任何上櫃單位', () {
        expect(
          coverage()
              .plan(from: jul, to: aug, markets: {MarketCode.twse})
              .map((u) => u.key.market)
              .toSet(),
          {MarketCode.twse},
        );
      });
    });
  });

  test('loadDividendCoverage：以在市主檔與兩張紀錄表組出完整度', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db.completeDividendMonth(
      market: MarketCode.twse,
      month: aug,
      rows: const [],
      expectedKeys: const {},
      listedRows: 3,
      skippedSymbols: const {'910322'},
      completedAt: now,
    );
    await db.recordDividendMonthFailure(
      market: MarketCode.tpex,
      month: aug,
      failedAt: now,
      error: 'boom',
      listOk: false,
    );

    final c = await loadDividendCoverage(db, now: now);

    expect(c.isMonthComplete((market: MarketCode.twse, month: aug)), isTrue);
    expect(c.isMonthComplete((market: MarketCode.tpex, month: aug)), isFalse);
    expect(c.failureOf((market: MarketCode.tpex, month: aug))?.failCount, 1);

    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '910322', name: 'DR', market: 'TWSE'),
    ]);
    final reopened = await loadDividendCoverage(db, now: now);
    expect(
      reopened.isMonthComplete((market: MarketCode.twse, month: aug)),
      isFalse,
      reason: '略過的代號進了在市主檔，該月重開',
    );
  });
}

// 股利摘要（dividend_summary.dart）：個股頁股利表、ETF 近一年殖利率、投資組合
// 預估共用。年度依除權息日的年份；不完整一律建置中，不顯示部分加總
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

final _now = DateTime(2026, 10, 2, 21, 30);
const _markets = [MarketCode.twse, MarketCode.tpex];

/// [now] 當下：回補範圍（今年往前 5 年的 1 月）到 [ledgerTo]（預設上個月）
/// 兩市場都有完成紀錄，[listedThrough]（預設 now 當天）所在月份列到那一天
DividendCompleteness _facts(
  DateTime now, {
  DateTime? listedThrough,
  CalendarMonth? ledgerTo,
  List<DividendUnresolvedEntry> unresolved = const [],
  List<(String, DateTime)> missingPrices = const [],
}) {
  final thisMonth = CalendarMonth.of(now);
  final through = listedThrough ?? DateTime(now.year, now.month, now.day);
  final listedMonth = CalendarMonth.of(through);
  return DividendCompleteness.compute(
    now: now,
    listings: [
      for (final market in _markets)
        DividendListingEntry(
          market: market,
          year: listedMonth.year,
          month: listedMonth.month,
          listedThrough: through,
        ),
    ],
    ledger: [
      for (final market in _markets)
        for (final m in CalendarMonth.descending(
          from: CalendarMonth(now.year - 5, 1),
          to: ledgerTo ?? thisMonth.previous,
        ))
          DividendMonthLedgerEntry(
            market: market,
            year: m.year,
            month: m.month,
            completedAt: thisMonth.firstDay,
            listedRows: 1,
            knownRows: 1,
            skippedSymbols: '',
            pricesRecorded: true,
          ),
    ],
    unresolved: unresolved,
    missingPriceKeys: missingPrices,
  );
}

DividendUnresolvedEntry _unresolved(String symbol, DateTime exDate) =>
    DividendUnresolvedEntry(
      market: MarketCode.twse,
      symbol: symbol,
      exDate: exDate,
      reason: DividendUnresolvedReason.pendingDetail.code,
      recordedAt: _now,
    );

DividendDistributionEntry _row(
  DateTime exDate, {
  String symbol = '2330',
  double cash = 0,
  double shares = 0,
  double? close = 100,
  double? reference = 95,
}) => DividendDistributionEntry(
  symbol: symbol,
  exDate: exDate,
  cashDividend: cash,
  stockSharesPerThousand: shares,
  closeBefore: close,
  referencePrice: reference,
);

DividendSummary _summary(
  List<DividendDistributionEntry> rows, {
  DividendCompleteness? facts,
  String symbol = '2330',
  String? name = '台積電',
}) => DividendSummary.compute(
  symbol: symbol,
  name: name,
  rows: rows,
  completeness: facts ?? _facts(_now),
);

void main() {
  group('年度狀態（依除權息日的年份）', () {
    test('今年＋前 5 個完整年度：去年到 5 年前新到舊', () {
      final s = _summary(const []);
      expect(s.current.year, 2026);
      expect(s.pastYears.map((r) => r.year), [2025, 2024, 2023, 2022, 2021]);
    });

    test('有配發：現金與配股各自加總；次數只數有現金的除權息', () {
      final s = _summary([
        _row(DateTime(2025, 3, 20), cash: 2.5),
        _row(DateTime(2025, 9, 18), cash: 2.5),
        _row(DateTime(2025, 9, 25), shares: 50), // 同一年的權另一天除
      ]);
      final y2025 = s.pastYears.first;
      expect(y2025.status, DividendYearStatus.paid);
      expect(y2025.cash, 5.0);
      expect(y2025.stockShares, 50);
      expect(y2025.cashCount, 2);
    });

    test('第一次除權息之前的空年是「無除權息紀錄」、之後的是「無除權息」', () {
      final s = _summary([_row(DateTime(2023, 7, 13), cash: 3)]);
      expect(
        {for (final r in s.pastYears) r.year: r.status},
        {
          2025: DividendYearStatus.none,
          2024: DividendYearStatus.none,
          2023: DividendYearStatus.paid,
          2022: DividendYearStatus.noRecord,
          2021: DividendYearStatus.noRecord,
        },
      );
    });

    test('第一次除權息在今年：前 5 年都是「無除權息紀錄」', () {
      final s = _summary([_row(DateTime(2026, 8, 1), cash: 1)]);
      expect(s.pastYears.map((r) => r.status).toSet(), {
        DividendYearStatus.noRecord,
      });
    });

    test('不完整的年度是建置中：DB 裡已有的列也不顯示（不顯示部分加總）', () {
      final s = _summary(
        [_row(DateTime(2024, 7, 11), cash: 4)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2024, 3, 20))],
        ),
      );
      final y2024 = s.pastYears.firstWhere((r) => r.year == 2024);
      expect(y2024.status, DividendYearStatus.building);
      expect(y2024.cash, 0);
    });

    test('建置中的年度在庫的列也算第一次除權息：之後完整、無事件的年度是「無除權息」', () {
      final s = _summary(
        [_row(DateTime(2021, 7, 15), cash: 1)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2021, 3, 1))],
        ),
      );
      expect(
        s.pastYears.firstWhere((r) => r.year == 2021).status,
        DividendYearStatus.building,
      );
      expect(
        s.pastYears.firstWhere((r) => r.year == 2022).status,
        DividendYearStatus.none,
      );
    });

    test('只有現金增資的 0/0 列不算配發', () {
      final s = _summary([_row(DateTime(2025, 7, 17))]);
      expect(s.pastYears.first.status, DividendYearStatus.noRecord);
    });

    test('年度表只看金額（requirePrices: false）：缺價格欄的年度照常顯示', () {
      final s = _summary([
        _row(DateTime(2025, 7, 17), cash: 3, close: null, reference: null),
      ], facts: _facts(_now, missingPrices: [('2330', DateTime(2025, 7, 17))]));
      expect(s.pastYears.first.status, DividendYearStatus.paid);
    });
  });

  group('今年', () {
    // 真實情況：2026-10-03 的 live DB 已有舊版 CLI 寫入的 10/1、10/2 列，
    // 10 月的列表事實要等新版第一輪才寫，顯示終點停在 9/30
    test('有除權息：算到顯示終點當天為止', () {
      final s = _summary([
        _row(DateTime(2026, 7, 16), cash: 3),
        _row(DateTime(2026, 10, 2), cash: 0.5), // 顯示終點當天：算
        _row(DateTime(2026, 10, 5), cash: 1), // 顯示終點之後：不算
      ]);
      expect(s.displayEnd, DateTime(2026, 10, 2));
      expect(s.current.status, DividendYearStatus.paid);
      expect(s.current.cash, 3.5);
      expect(s.current.cashCount, 2);
    });

    test('至顯示終點完整、還沒有除權息：尚未除息', () {
      expect(_summary(const []).current.status, DividendYearStatus.notYet);
    });

    test('今年不完整：建置中', () {
      final s = _summary(
        [_row(DateTime(2026, 7, 16), cash: 3)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2026, 8, 20))],
        ),
      );
      expect(s.current.status, DividendYearStatus.building);
    });

    test('年度表只看金額：今年缺價格欄照常顯示', () {
      final s = _summary([
        _row(DateTime(2026, 7, 21), cash: 1, close: null, reference: null),
      ], facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 7, 21))]));
      expect(s.current.status, DividendYearStatus.paid);
    });

    test('🚨 1 月初、當年第一輪更新前（顯示終點還在去年）：今年建置中，去年照常', () {
      final now = DateTime(2027, 1, 2, 8);
      final s = _summary(
        [_row(DateTime(2026, 7, 16), cash: 3)],
        facts: _facts(
          now,
          listedThrough: DateTime(2026, 12, 31),
          ledgerTo: const CalendarMonth(2026, 11),
        ),
      );
      expect(s.displayEnd, DateTime(2026, 12, 31));
      expect(s.current.year, 2027);
      expect(s.current.status, DividendYearStatus.building);
      expect(s.pastYears.first.year, 2026);
      expect(s.pastYears.first.status, DividendYearStatus.paid);
    });
  });

  group('整區建置中', () {
    test('🚨 完全沒有完整度事實（新安裝、手機回補中）：全部建置中', () {
      final s = DividendSummary.compute(
        symbol: '2330',
        name: '台積電',
        rows: [_row(DateTime(2025, 7, 17), cash: 3)],
        completeness: DividendCompleteness.compute(
          now: _now,
          listings: const [],
          ledger: const [],
          unresolved: const [],
          missingPriceKeys: const [],
        ),
      );
      expect(s.displayEnd, isNull);
      expect(s.allBuilding, isTrue);
      expect(s.average, isA<DividendAverageBuilding>());
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('前 5 年都建置中、今年不是：不是整區建置中', () {
      final s = _summary(
        const [],
        facts: _facts(
          _now,
          unresolved: [
            for (final y in [2021, 2022, 2023, 2024, 2025])
              _unresolved('2330', DateTime(y, 6, 1)),
          ],
        ),
      );
      expect(s.current.status, DividendYearStatus.notYet);
      expect(s.allBuilding, isFalse);
    });

    test('今年建置中、前幾年有不是建置中的：不是整區建置中', () {
      final s = _summary(
        const [],
        facts: _facts(
          _now,
          unresolved: [
            _unresolved('2330', DateTime(2026, 6, 1)),
            _unresolved('2330', DateTime(2024, 6, 1)),
          ],
        ),
      );
      expect(s.current.status, DividendYearStatus.building);
      expect(s.allBuilding, isFalse);
    });
  });

  group('平均（從第一次有除權息的完整年度到去年）', () {
    test('5 年都有配發：5 年平均', () {
      final s = _summary([
        for (final y in [2021, 2022, 2023, 2024, 2025])
          _row(DateTime(y, 7, 15), cash: y - 2020.0),
      ]);
      final avg = s.average as DividendAverageValue;
      expect(avg.fromYear, 2021);
      expect(avg.years, 5);
      expect(avg.cash, 3.0); // (1+2+3+4+5)/5
    });

    test('第一次除權息在 2023：2023 起 3 年平均，其間無除權息的年度計 0', () {
      final s = _summary([
        _row(DateTime(2023, 7, 13), cash: 3, shares: 30),
        _row(DateTime(2025, 7, 17), cash: 6),
      ]);
      final avg = s.average as DividendAverageValue;
      expect(avg.fromYear, 2023);
      expect(avg.years, 3);
      expect(avg.cash, 3.0); // (3 + 0 + 6) / 3
      expect(avg.stockShares, 10.0);
      // 第一次是 2023（不是最近有配發的 2025）：夾在中間的 2024 是無除權息
      expect(
        s.pastYears.firstWhere((r) => r.year == 2024).status,
        DividendYearStatus.none,
      );
    });

    test('今年的配發不計入平均', () {
      final s = _summary([
        _row(DateTime(2025, 7, 17), cash: 2),
        _row(DateTime(2026, 7, 16), cash: 10),
      ]);
      final avg = s.average as DividendAverageValue;
      expect(avg.fromYear, 2025);
      expect(avg.years, 1);
      expect(avg.cash, 2.0);
    });

    test('前 5 年任一年建置中：平均建置中（含第一次除權息之前的年度）', () {
      final s = _summary(
        [_row(DateTime(2024, 7, 11), cash: 4)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2021, 5, 5))],
        ),
      );
      expect(s.average, isA<DividendAverageBuilding>());
    });

    test('前 5 年都沒有除權息：沒有平均', () {
      expect(_summary([_row(DateTime(2026, 8, 1), cash: 1)]).average, isNull);
    });
  });

  group('面額（名稱帶 * 表示不是 10 元）', () {
    test('不帶 *：配股換算成元（每千股 ÷ 100），合計＝現金＋股票', () {
      final s = _summary(const [], name: '台積電');
      expect(s.parValueTen, isTrue);
      expect(s.stockYuan(50), 0.5);
      expect(s.totalYuan(2, 50), 2.5);
    });

    test('🚨 帶 *：不換算、合計為 null（畫面顯示「—」）', () {
      final s = _summary(const [], name: '世紀*');
      expect(s.parValueTen, isFalse);
      expect(s.stockYuan(3157.03), isNull);
      expect(s.totalYuan(0, 3157.03), isNull);
    });

    test('主檔查不到名稱：不假設面額', () {
      expect(_summary(const [], name: null).parValueTen, isFalse);
    });
  });

  group('近一年殖利率', () {
    test('🚨 0050 跨分割（2025-06-18）：逐次以前收盤正規化，不是總額 ÷ 現價', () {
      // 2025-08-01 當下：最近一次除息 2025-07-21，窗口從 2024-08-05 起
      final s = _summary(
        [
          _row(DateTime(2024, 7, 16), cash: 1.0, close: 196.7),
          _row(DateTime(2025, 1, 17), cash: 2.7, close: 198.05),
          _row(DateTime(2025, 7, 21), cash: 0.36, close: 51.45),
        ],
        symbol: '0050',
        name: '元大台灣50',
        facts: _facts(DateTime(2025, 8, 1, 21)),
      );
      final ratio = (s.trailingYield as TrailingYieldValue).ratio;
      expect(ratio, closeTo(2.7 / 198.05 + 0.36 / 51.45, 1e-12)); // 約 2.06%
      // 總額 ÷ 分割後股價（約 51）會是 6% 上下
      expect(ratio, lessThan(0.03));
    });

    test('窗口：最近一次除息日往前 350 天含、351 天不含', () {
      // 最近一次 2026-07-21；350 天前＝2025-08-05、351 天前＝2025-08-04
      final s = _summary([
        _row(DateTime(2025, 8, 4), cash: 5, close: 100),
        _row(DateTime(2025, 8, 5), cash: 1, close: 100),
        _row(DateTime(2026, 7, 21), cash: 0.6, close: 99.2),
      ]);
      expect(
        (s.trailingYield as TrailingYieldValue).ratio,
        closeTo(1 / 100 + 0.6 / 99.2, 1e-12),
      );
    });

    test('最近一次除息早於顯示終點 400 天：近一年無配息', () {
      // 顯示終點 2026-10-02；400 天前＝2025-08-28
      final s = _summary([_row(DateTime(2025, 8, 28), cash: 1)]);
      expect(s.trailingYield, isA<TrailingYieldNone>());
    });

    test('399 天：仍計算', () {
      final s = _summary([_row(DateTime(2025, 8, 29), cash: 1, close: 50)]);
      expect(
        (s.trailingYield as TrailingYieldValue).ratio,
        closeTo(0.02, 1e-12),
      );
    });

    test('沒有任何除息紀錄、近 400 天完整：近一年無配息', () {
      expect(_summary(const []).trailingYield, isA<TrailingYieldNone>());
    });

    test('🚨 只有配股的除權（現金 0）不是除息：不當最近一次除息日', () {
      final s = _summary([
        _row(DateTime(2025, 8, 20), cash: 1), // 400 天以上
        _row(DateTime(2026, 8, 14), shares: 3157), // 只有配股
      ]);
      expect(s.trailingYield, isA<TrailingYieldNone>());
    });

    test('顯示終點之後的除息不算（不前視）；顯示終點當天的要算', () {
      final after = _summary([
        _row(DateTime(2025, 8, 20), cash: 1),
        _row(DateTime(2026, 10, 5), cash: 1),
      ]);
      expect(after.trailingYield, isA<TrailingYieldNone>());

      final onEnd = _summary([
        _row(DateTime(2026, 10, 2), cash: 1, close: 100),
      ]);
      expect(
        (onEnd.trailingYield as TrailingYieldValue).ratio,
        closeTo(0.01, 1e-12),
      );
    });

    test('完整度窗口從最近除息日往前 350 天起：窗口內有未解決的列是建置中', () {
      final rows = [_row(DateTime(2026, 7, 21), cash: 1, close: 100)];
      // 窗口＝[2025-08-05, 2026-10-02]
      expect(
        _summary(
          rows,
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 5))],
          ),
        ).trailingYield,
        isA<TrailingYieldBuilding>(),
      );
      expect(
        _summary(
          rows,
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 4))],
          ),
        ).trailingYield,
        isA<TrailingYieldValue>(),
      );
    });

    test('近一年無配息也要近 400 天完整：窗口內有未解決的列是建置中', () {
      // 窗口＝[2025-08-28, 2026-10-02]
      expect(
        _summary(
          const [],
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 28))],
          ),
        ).trailingYield,
        isA<TrailingYieldBuilding>(),
      );
      expect(
        _summary(
          const [],
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 27))],
          ),
        ).trailingYield,
        isA<TrailingYieldNone>(),
      );
    });

    test('需要價格（requirePrices: true）：窗口內的配發列缺價格是建置中', () {
      final s = _summary([
        _row(DateTime(2026, 7, 21), cash: 1, close: null, reference: null),
      ], facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 7, 21))]));
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('近一年無配息的窗口也要求價格', () {
      // 窗口內只有一筆只有配股、缺價格的除權
      final s = _summary([
        _row(DateTime(2026, 8, 14), shares: 50, close: null, reference: null),
      ], facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 8, 14))]));
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('有除息時的窗口也要求價格：窗口內不是除息的列缺價格，照樣建置中', () {
      // 只有現金增資的 0/0 列不在配發列裡，但它缺價格的事實照樣讓窗口不完整
      // （spec §6：近一年殖利率 requirePrices: true）。除息列本身價格齊全，
      // 只靠逐筆檢查前收盤擋不到
      final s = _summary([
        _row(DateTime(2026, 7, 21), cash: 1, close: 100),
      ], facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 3, 2))]));
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('配發列缺前收盤、完整度卻沒記到（兩次查詢之間被改寫）：建置中，不拋例外', () {
      final s = _summary([_row(DateTime(2026, 7, 21), cash: 1, close: null)]);
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });
  });
}

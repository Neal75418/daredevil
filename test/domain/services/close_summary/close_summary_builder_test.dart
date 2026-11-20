import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/industry_names.dart';
import 'package:daredevil/core/constants/transaction_types.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/user_dao.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/close_summary_builder.dart';
import 'package:daredevil/domain/services/close_summary/price_checks.dart';

import 'close_summary_fixtures.dart';

/// 資料日＝第 60 個交易日
final _d = tradingDay(60);

final _strong = groupOf(11, '強者榜', 0);
final _backup = groupOf(12, '備取觀察', 1);
final _delist = groupOf(13, '除名重審', 2);
final _thermo = groupOf(14, '大盤溫度計', 3);

/// 收盤序列，最後一根落在資料日
List<DailyPriceEntry> _endAtD(
  String symbol,
  List<double> closes, {
  Map<int, double> highs = const {},
  Map<int, double> lows = const {},
  int endDay = 60,
}) => barsFrom(
  closes,
  symbol: symbol,
  highs: highs,
  lows: lows,
  startDay: endDay + 1 - closes.length,
);

List<double> get _flat => repeat(100, 61);

/// 最後兩天收在月線下
List<double> get _belowTwo => [...repeat(100, 59), 90, 90];

/// 強者榜四條件都過（也會突破 20 日高）
List<double> get _strong4 => [
  100,
  110,
  for (var i = 0; i < 18; i++) 110.0 + i * 0.5,
  120,
];

/// 只有結構 C（突破），強者榜條件不全過
List<double> get _breakoutOnly => [...repeat(100, 60), 106];

/// 沒有結構、沒有入選條件，資料日漲到 [last]
List<double> _quietUp(double last) => [
  ...repeat(100, 40),
  106,
  ...repeat(100, 19),
  last,
];

/// 資料日由均線上跌到均線下
List<double> get _crossBelow => [...repeat(100, 60), 90];

/// 結構 C＋前提條件都過（另外要給營收與法人）
List<double> get _dualSeal => [...repeat(90, 41), ...repeat(100, 19), 104];

/// 一路上漲到 160 後資料日收 [close]；配上資料日最低 148（`lows`）才會碰到 10 日線、成立結構 B
List<double> _structureB(double close) => [
  for (var i = 0; i <= 20; i++) 100.0 + 3 * i,
  close,
];

({double foreign, double trust}) _buy(double shares) =>
    (foreign: shares, trust: 0);

CloseSummaryInput _input({
  Map<String, List<DailyPriceEntry>> prices = const {},
  List<WatchlistWithGroup> watchlist = const [],
  List<WatchlistGroupEntry>? groups,
  List<PortfolioPositionEntry> positions = const [],
  Map<String, List<PortfolioTransactionEntry>> transactions = const {},
  Map<String, StockMasterEntry> stocks = const {},
  Map<String, List<DailyInstitutionalEntry>> institutional = const {},
  Map<String, List<MonthlyRevenueEntry>> revenues = const {},
  Map<String, bool> priceReady = const {'TWSE': true, 'TPEx': true},
  Map<String, bool> institutionalReady = const {'TWSE': true, 'TPEx': true},
  List<MarketIndexEntry>? taiex,
  DateTime? dataDate,
  DateTime? now,
}) {
  final symbols = {
    ...prices.keys,
    for (final w in watchlist) w.entry.symbol,
    for (final p in positions) p.symbol,
  };
  final date = dataDate ?? _d;
  return CloseSummaryInput(
    dataDate: date,
    now: now ?? date.add(const Duration(hours: 17)),
    priceReadyByMarket: priceReady,
    institutionalReadyByMarket: institutionalReady,
    taiex: taiex ?? taiexFrom(repeat(100, 61)),
    watchlist: watchlist,
    groups: groups ?? [_strong, _backup, _delist, _thermo],
    positions: positions,
    transactions: transactions,
    stocks: {for (final s in symbols) s: stockOf(s), ...stocks},
    prices: prices,
    institutional: institutional,
    revenues: revenues,
  );
}

CloseSummaryRow _row(CloseSummary summary, String symbol) => summary.sections
    .expand((s) => s.rows)
    .firstWhere((r) => r.symbol == symbol);

List<SummaryEventKind> _kinds(CloseSummaryRow row) => [
  for (final e in row.events) e.kind,
];

void main() {
  test('區段：持股在最前，其餘照分組順序、同名分組各自成段、未分組最後', () {
    final dup = groupOf(15, '備取觀察', 4);
    final summary = buildCloseSummary(
      _input(
        groups: [_strong, _backup, _delist, _thermo, dup],
        prices: {
          'A': _endAtD('A', _belowTwo),
          'B': _endAtD('B', _flat),
          'C': _endAtD('C', _flat),
          'D': _endAtD('D', _flat),
          'E': _endAtD('E', _flat),
        },
        watchlist: [
          watchOf('A', group: _strong),
          watchOf('B', group: _strong),
          watchOf('C', group: _backup),
          watchOf('D'),
          watchOf('E', group: dup),
        ],
        positions: [positionOf(symbol: 'A', quantity: 1000, avgCost: 100)],
        transactions: {
          'A': [txOn(0, TransactionTypes.buy, 1000, symbol: 'A')],
        },
      ),
    );

    final sections = summary.sections;
    expect(sections.map((s) => s.isHoldings), [
      true,
      false,
      false,
      false,
      false,
    ]);
    expect(sections.map((s) => s.groupId), [null, 11, 12, 15, null]);
    expect(sections.last.isUngrouped, isTrue);
    expect(sections.first.rows.map((r) => r.symbol), ['A']);
    expect(sections[1].rows.map((r) => r.symbol), ['B'], reason: '持股不在分組段重複');

    final a = sections.first.rows.single;
    expect(a.role, GroupRole.strongList);
    expect(a.holding, isNotNull);
    final streak = a.events.firstWhere(
      (e) => e.kind == SummaryEventKind.belowMaStreak,
    );
    expect(streak.days, 2);
  });

  test('段內排序：有待處理的在前，再依漲幅由高到低，沒有漲幅的最後', () {
    final summary = buildCloseSummary(
      _input(
        prices: {
          'W': _endAtD('W', [100]),
          'Z': _endAtD('Z', _quietUp(101)),
          'Y': _endAtD('Y', _quietUp(105)),
          'X': _endAtD('X', _strong4),
        },
        watchlist: [watchOf('W'), watchOf('Z'), watchOf('Y'), watchOf('X')],
      ),
    );
    final rows = summary.sections.single.rows;
    expect(rows.map((r) => r.symbol), ['X', 'Y', 'Z', 'W']);
    expect(rows.first.hasActionable, isTrue);
    expect(rows.skip(1).any((r) => r.hasActionable), isFalse);
  });

  group('角色與事件', () {
    test('除名重審：不標結構；四條件都過標入選條件', () {
      final summary = buildCloseSummary(
        _input(
          prices: {
            'R1': _endAtD('R1', _breakoutOnly),
            'R2': _endAtD('R2', _strong4),
          },
          watchlist: [
            watchOf('R1', group: _delist),
            watchOf('R2', group: _delist),
          ],
        ),
      );
      expect(_row(summary, 'R1').events, isEmpty);
      final r2 = _kinds(_row(summary, 'R2'));
      expect(r2, contains(SummaryEventKind.strongListQualified));
      expect(r2, isNot(contains(SummaryEventKind.structureC)));
    });

    test('強者榜：只有 1 天收在月線下 → 不標連 N 日收破月線', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'S2': _endAtD('S2', _crossBelow)},
          watchlist: [watchOf('S2', group: _strong)],
        ),
      );
      expect(
        _kinds(_row(summary, 'S2')),
        isNot(contains(SummaryEventKind.belowMaStreak)),
      );
    });

    test('強者榜：四條件都過不標入選條件，結構照標', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'S1': _endAtD('S1', _strong4)},
          watchlist: [watchOf('S1', group: _strong)],
        ),
      );
      final kinds = _kinds(_row(summary, 'S1'));
      expect(kinds, isNot(contains(SummaryEventKind.strongListQualified)));
      expect(kinds, contains(SummaryEventKind.structureC));
    });

    test('大盤溫度計：不標事件，只寫月線攻防（數到頭時標「至少」）', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'T1': _endAtD('T1', _breakoutOnly)},
          watchlist: [watchOf('T1', group: _thermo)],
        ),
      );
      final t1 = _row(summary, 'T1');
      expect(t1.events, isEmpty);
      // 61 根、均線從第 20 根起算得出來 → 42 天都在均線上（等於也算）
      expect(t1.thermometerStreak, 42);
      expect(t1.thermometerStreakAtLeast, isTrue);
    });

    test('溫度計同時是持股且收破成本守門價 → 只標收破', () {
      final summary = buildCloseSummary(
        _input(
          prices: {
            'T2': _endAtD(
              'T2',
              [...repeat(100, 21), 95, 90],
              highs: {for (var i = 0; i < 21; i++) i: 102},
              lows: {for (var i = 0; i < 21; i++) i: 98},
            ),
          },
          watchlist: [watchOf('T2', group: _thermo)],
          positions: [positionOf(symbol: 'T2', quantity: 1000, avgCost: 100)],
          transactions: {
            'T2': [txOn(58, TransactionTypes.buy, 1000, symbol: 'T2')],
          },
        ),
      );
      final t2 = _row(summary, 'T2');
      expect(t2.role, GroupRole.thermometer);
      expect(_kinds(t2), [SummaryEventKind.stopBroken]);
      expect(summary.sections.first.isHoldings, isTrue);
    });
  });

  test('找不到「強者榜」分組：改名那組 4/4 也不標入選條件，其他事件照常', () {
    final renamed = groupOf(11, '強者榜v2', 0);
    final summary = buildCloseSummary(
      _input(
        groups: [renamed, _backup],
        prices: {'S1': _endAtD('S1', _strong4)},
        watchlist: [watchOf('S1', group: renamed)],
      ),
    );
    expect(summary.strongListGroupMissing, isTrue);
    final kinds = _kinds(_row(summary, 'S1'));
    expect(kinds, isNot(contains(SummaryEventKind.strongListQualified)));
    expect(kinds, contains(SummaryEventKind.structureC));
  });

  test('一個分組都沒有 → 不提示找不到強者榜（從沒建過分組的人）', () {
    final summary = buildCloseSummary(
      _input(
        groups: const [],
        prices: {'S1': _endAtD('S1', _strong4)},
        watchlist: [watchOf('S1')],
      ),
    );
    expect(summary.strongListGroupMissing, isFalse);
  });

  group('族群退燒', () {
    final shipping = stockOf('K1', industry: '航運業');

    CloseSummary build(
      Map<String, List<DailyPriceEntry>> prices, {
      List<WatchlistWithGroup> watchlist = const [],
      List<PortfolioPositionEntry> positions = const [],
      Map<String, StockMasterEntry> stocks = const {},
    }) => buildCloseSummary(
      _input(
        prices: prices,
        watchlist: watchlist,
        positions: positions,
        stocks: {
          for (final s in prices.keys) s: stockOf(s, industry: '航運業'),
          ...stocks,
        },
      ),
    );

    bool cooling(CloseSummary s, String symbol) => _row(
      s,
      symbol,
    ).events.any((e) => e.kind == SummaryEventKind.sectorCooling);

    test('同產業 2 檔自選同日跌破月線 → 兩檔都標，寫正規化後的產業', () {
      final summary = build(
        {'K1': _endAtD('K1', _crossBelow), 'K2': _endAtD('K2', _crossBelow)},
        watchlist: [watchOf('K1'), watchOf('K2')],
      );
      expect(cooling(summary, 'K1'), isTrue);
      expect(cooling(summary, 'K2'), isTrue);
      final event = _row(
        summary,
        'K1',
      ).events.firstWhere((e) => e.kind == SummaryEventKind.sectorCooling);
      expect(event.industry, IndustryNames.normalize(shipping.industry!));
    });

    test('只有 1 檔 → 不標', () {
      final summary = build(
        {'K1': _endAtD('K1', _crossBelow)},
        watchlist: [watchOf('K1')],
      );
      expect(cooling(summary, 'K1'), isFalse);
    });

    test('另一檔是溫度計、只是持股、或資料日沒有成交 → 不計入', () {
      final thermo = build(
        {'K1': _endAtD('K1', _crossBelow), 'K3': _endAtD('K3', _crossBelow)},
        watchlist: [
          watchOf('K1'),
          watchOf('K3', group: _thermo),
        ],
      );
      expect(cooling(thermo, 'K1'), isFalse);

      final holdingOnly = build(
        {'K1': _endAtD('K1', _crossBelow), 'K4': _endAtD('K4', _crossBelow)},
        watchlist: [watchOf('K1')],
        positions: [positionOf(symbol: 'K4', quantity: 1000, avgCost: 100)],
      );
      expect(cooling(holdingOnly, 'K1'), isFalse);

      final noTrade = build(
        {
          'K1': _endAtD('K1', _crossBelow),
          'K5': _endAtD('K5', _crossBelow, endDay: 59),
        },
        watchlist: [watchOf('K1'), watchOf('K5')],
      );
      expect(cooling(noTrade, 'K1'), isFalse);
    });

    test('產業是 null 的略過，不丟例外', () {
      final summary = build(
        {'K1': _endAtD('K1', _crossBelow), 'K6': _endAtD('K6', _crossBelow)},
        watchlist: [watchOf('K1'), watchOf('K6')],
        stocks: {'K6': stockOf('K6', industry: null)},
      );
      expect(cooling(summary, 'K1'), isFalse);
      expect(cooling(summary, 'K6'), isFalse);
    });
  });

  test('市場行情未到 vs. 資料日沒有成交：都不標事件、不計入', () {
    final summary = buildCloseSummary(
      _input(
        priceReady: const {'TWSE': true, 'TPEx': false},
        prices: {
          'P1': _endAtD('P1', _strong4),
          'N1': _endAtD('N1', _strong4, endDay: 59),
        },
        stocks: {'P1': stockOf('P1', market: 'TPEx')},
        watchlist: [watchOf('P1'), watchOf('N1')],
      ),
    );
    final p1 = _row(summary, 'P1');
    expect(p1.status, RowDataStatus.marketPending);
    expect(p1.events, isEmpty);
    expect(p1.close, isNull);
    final n1 = _row(summary, 'N1');
    expect(n1.status, RowDataStatus.noTrade);
    expect(n1.events, isEmpty);
    expect(summary.pricePendingMarkets, {'TPEx'});
    expect(summary.actionableStockCount, 0);
  });

  test('只有 15 根 → 強者榜條件資料不足，不標入選條件與結構', () {
    final summary = buildCloseSummary(
      _input(
        prices: {
          'F1': _endAtD('F1', [...repeat(100, 14), 110]),
        },
        watchlist: [watchOf('F1')],
      ),
    );
    final f1 = _row(summary, 'F1');
    expect(f1.strongList!.ret20, CheckOutcome.insufficient);
    expect(f1.strongList!.aboveMa20, CheckOutcome.insufficient);
    expect(f1.events.where((e) => e.kind.isActionable), isEmpty);
  });

  test('上櫃法人未到：上櫃股票不判籌碼與雙章齊，上市照常', () {
    List<DailyInstitutionalEntry> inst(String s) => instFrom(
      [_buy(60000), _buy(60000), _buy(60000)],
      startDay: 58,
      symbol: s,
    );
    final summary = buildCloseSummary(
      _input(
        institutionalReady: const {'TWSE': true, 'TPEx': false},
        prices: {
          'Q1': _endAtD('Q1', _dualSeal),
          'Q2': _endAtD('Q2', _dualSeal),
        },
        stocks: {'Q1': stockOf('Q1', market: 'TPEx')},
        watchlist: [watchOf('Q1'), watchOf('Q2')],
        institutional: {'Q1': inst('Q1'), 'Q2': inst('Q2')},
        revenues: {'Q1': revenueOf('Q1', 50), 'Q2': revenueOf('Q2', 50)},
      ),
    );
    expect(summary.institutionalPendingMarkets, {'TPEx'});

    final q1 = _row(summary, 'Q1');
    expect(q1.chip, isNull);
    expect(_kinds(q1), isNot(contains(SummaryEventKind.dualSeal)));
    expect(_kinds(q1), contains(SummaryEventKind.structureC));

    final q2 = _row(summary, 'Q2');
    expect(q2.chip!.sealed, isTrue);
    expect(_kinds(q2), contains(SummaryEventKind.dualSeal));
  });

  test('籌碼章成立但對做 → 不標雙章齊', () {
    final summary = buildCloseSummary(
      _input(
        prices: {'Q3': _endAtD('Q3', _dualSeal)},
        watchlist: [watchOf('Q3')],
        institutional: {
          'Q3': instFrom(
            [_buy(60000), (foreign: 60000, trust: -180000), _buy(60000)],
            startDay: 58,
            symbol: 'Q3',
          ),
        },
        revenues: {'Q3': revenueOf('Q3', 50)},
      ),
    );
    final q3 = _row(summary, 'Q3');
    expect(q3.chip!.sealed, isTrue);
    expect(q3.chip!.opposed, isTrue);
    expect(_kinds(q3), isNot(contains(SummaryEventKind.dualSeal)));
    expect(_kinds(q3), contains(SummaryEventKind.structureC));
  });

  test('觸發日降級（結構 B）：跌 5.0% 只標降級，跌 4.99% 標結構 B', () {
    final summary = buildCloseSummary(
      _input(
        prices: {
          'G1': _endAtD('G1', _structureB(152), lows: {21: 148}),
          'G2': _endAtD('G2', _structureB(152.016), lows: {21: 148}),
        },
        watchlist: [watchOf('G1'), watchOf('G2')],
      ),
    );
    final g1 = _kinds(_row(summary, 'G1'));
    expect(g1, contains(SummaryEventKind.triggerDowngrade));
    expect(g1, isNot(contains(SummaryEventKind.structureB)));

    final g2 = _row(summary, 'G2');
    expect(_kinds(g2), isNot(contains(SummaryEventKind.triggerDowngrade)));
    final b = g2.events.firstWhere(
      (e) => e.kind == SummaryEventKind.structureB,
    );
    expect(b.supportPeriod, 10);
  });

  test('入口卡的數字：只算待處理事件；持股數照持股', () {
    final summary = buildCloseSummary(
      _input(
        prices: {
          'L1': _endAtD('L1', [
            ...repeat(100, 40),
            120,
            ...repeat(100, 19),
            110,
          ]),
          'A': _endAtD('A', _flat),
        },
        watchlist: [watchOf('L1')],
        positions: [positionOf(symbol: 'A', quantity: 1000, avgCost: 100)],
        transactions: {
          'A': [txOn(0, TransactionTypes.buy, 1000, symbol: 'A')],
        },
      ),
    );
    expect(_kinds(_row(summary, 'L1')), [SummaryEventKind.limitUp]);
    expect(summary.actionableStockCount, 0);
    expect(summary.holdingCount, 1);
  });

  test('加權指數最後一筆不是資料日 → 指數未到、沒有油門', () {
    final late = buildCloseSummary(_input(taiex: taiexFrom(repeat(100, 60))));
    expect(late.indexReady, isFalse);
    expect(late.throttle, isNull);

    final ready = buildCloseSummary(_input());
    expect(ready.indexReady, isTrue);
    expect(ready.throttle, isNotNull);
  });

  group('頁首的資料時間', () {
    ({bool awaitingToday, bool dataBehind}) at(
      DateTime now,
      DateTime dataDate,
    ) => closeSummaryTimeFlags(dataDate: dataDate, now: now);

    // 2026-01-12（一）～01-17（六）
    test('週三 14:00、資料到週二 → 等今天的更新', () {
      final s = at(DateTime(2026, 1, 14, 14), DateTime(2026, 1, 13));
      expect(s.awaitingToday, isTrue);
      expect(s.dataBehind, isFalse);
    });

    test('週三 17:00、資料到週二 → 落後', () {
      final s = at(DateTime(2026, 1, 14, 17), DateTime(2026, 1, 13));
      expect(s.dataBehind, isTrue);
      expect(s.awaitingToday, isFalse);
    });

    test('週三 14:00、資料只到週一 → 落後，不是等今天', () {
      final s = at(DateTime(2026, 1, 14, 14), DateTime(2026, 1, 12));
      expect(s.dataBehind, isTrue);
      expect(s.awaitingToday, isFalse);
    });

    test('週六、資料到週五 → 兩者都不是', () {
      final s = at(DateTime(2026, 1, 17, 10), DateTime(2026, 1, 16));
      expect(s.awaitingToday, isFalse);
      expect(s.dataBehind, isFalse);
    });
  });

  group('雙章齊的每個子條件各缺一項 → 不標', () {
    List<DailyInstitutionalEntry> inst(String s, double shares) => instFrom(
      [_buy(shares), _buy(shares), _buy(shares)],
      startDay: 58,
      symbol: s,
    );

    CloseSummaryRow rowOf(
      List<DailyPriceEntry> bars, {
      double instShares = 60000,
      double revenueYoy = 50,
    }) {
      final symbol = bars.first.symbol;
      final summary = buildCloseSummary(
        _input(
          prices: {symbol: bars},
          watchlist: [watchOf(symbol)],
          institutional: {symbol: inst(symbol, instShares)},
          revenues: {symbol: revenueOf(symbol, revenueYoy)},
        ),
      );
      return _row(summary, symbol);
    }

    List<SummaryEventKind> kindsOf(
      List<DailyPriceEntry> bars, {
      double instShares = 60000,
      double revenueYoy = 50,
    }) => _kinds(rowOf(bars, instShares: instShares, revenueYoy: revenueYoy));

    test('對照：條件都過 → 雙章齊', () {
      expect(
        kindsOf(_endAtD('V0', _dualSeal)),
        contains(SummaryEventKind.dualSeal),
      );
    });

    test('前提條件沒過（營收年增 30%）', () {
      expect(
        kindsOf(_endAtD('V1', _dualSeal), revenueYoy: 30),
        isNot(contains(SummaryEventKind.dualSeal)),
      );
    });

    test('籌碼章沒成立（每天買超 0.8%）', () {
      expect(
        kindsOf(_endAtD('V2', _dualSeal), instShares: 40000),
        isNot(contains(SummaryEventKind.dualSeal)),
      );
    });

    test('沒有價格章（沒有結構）', () {
      final row = rowOf(_endAtD('V3', [...repeat(90, 40), ...repeat(100, 21)]));
      // 其他子條件都成立，缺的只有價格章
      expect(row.chip!.sealed, isTrue);
      expect(row.prerequisites!.allPassed, isTrue);
      final kinds = _kinds(row);
      expect(kinds, isNot(contains(SummaryEventKind.dualSeal)));
      expect(kinds, isNot(contains(SummaryEventKind.structureB)));
      expect(kinds, isNot(contains(SummaryEventKind.structureC)));
    });

    test('觸發日降級 → 價格章不算，只標降級', () {
      final row = rowOf(
        _endAtD(
          'V4',
          [...repeat(100, 39), ..._structureB(152)],
          lows: {60: 148},
        ),
      );
      // 其他子條件都成立，缺的只有（被降級的）價格章
      expect(row.chip!.sealed, isTrue);
      expect(row.prerequisites!.allPassed, isTrue);
      expect(_kinds(row), [SummaryEventKind.triggerDowngrade]);
    });
  });

  group('角色對應的其他格', () {
    test('備取觀察（其他角色）四條件都過 → 標入選條件', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'O1': _endAtD('O1', _strong4)},
          watchlist: [watchOf('O1', group: _backup)],
        ),
      );
      expect(
        _kinds(_row(summary, 'O1')),
        contains(SummaryEventKind.strongListQualified),
      );
    });

    test('連 2 日收破月線只標強者榜：備取觀察與除名重審不標', () {
      final summary = buildCloseSummary(
        _input(
          prices: {
            'O2': _endAtD('O2', _belowTwo),
            'O3': _endAtD('O3', _belowTwo),
          },
          watchlist: [
            watchOf('O2', group: _backup),
            watchOf('O3', group: _delist),
          ],
        ),
      );
      for (final s in ['O2', 'O3']) {
        expect(
          _kinds(_row(summary, s)),
          isNot(contains(SummaryEventKind.belowMaStreak)),
        );
      }
    });

    test('持股 8 個交易日收盤都沒到 +1R → 標 8 日未達 +1R', () {
      final summary = buildCloseSummary(
        _input(
          prices: {
            'H1': _endAtD(
              'H1',
              repeat(100, 29),
              highs: {for (var i = 0; i < 21; i++) i: 102},
              lows: {for (var i = 0; i < 21; i++) i: 98},
            ),
          },
          positions: [positionOf(symbol: 'H1', quantity: 1000, avgCost: 100)],
          transactions: {
            'H1': [txOn(52, TransactionTypes.buy, 1000, symbol: 'H1')],
          },
        ),
      );
      final h1 = _row(summary, 'H1');
      expect(h1.holding!.stopPrice, 92);
      expect(_kinds(h1), [SummaryEventKind.timeStopExpired]);
    });
  });

  test('族群退燒依正規化後的產業分組（其他電子業＝其他電子類）', () {
    final summary = buildCloseSummary(
      _input(
        prices: {
          'J1': _endAtD('J1', _crossBelow),
          'J2': _endAtD('J2', _crossBelow),
        },
        stocks: {
          'J1': stockOf('J1', industry: '其他電子業'),
          'J2': stockOf('J2', industry: '其他電子類'),
        },
        watchlist: [watchOf('J1'), watchOf('J2')],
      ),
    );
    for (final s in ['J1', 'J2']) {
      final event = _row(
        summary,
        s,
      ).events.firstWhere((e) => e.kind == SummaryEventKind.sectorCooling);
      expect(event.industry, '其他電子類');
    }
  });

  group('日線的前處理', () {
    test('價格斷點（減資、分割）之前的資料不用：只剩 15 根 → 資料不足', () {
      final summary = buildCloseSummary(
        _input(
          prices: {
            'U1': _endAtD('U1', [...repeat(50, 46), ...repeat(100, 14), 110]),
          },
          watchlist: [watchOf('U1')],
        ),
      );
      expect(_row(summary, 'U1').strongList!.ret20, CheckOutcome.insufficient);
    });

    test('中間有一根收盤是 null → 去掉那根，不丟例外', () {
      final bars = _endAtD('U2', _strong4);
      bars[10] = bars[10].copyWith(close: const Value(null));
      final summary = buildCloseSummary(
        _input(prices: {'U2': bars}, watchlist: [watchOf('U2')]),
      );
      expect(_row(summary, 'U2').status, RowDataStatus.ok);
    });

    test('資料日之後的日線不用，資料日之後的跳空也不影響資料日', () {
      final bars = _endAtD('U3', [..._flat, 300], endDay: 61);
      final summary = buildCloseSummary(
        _input(prices: {'U3': bars}, watchlist: [watchOf('U3')]),
      );
      final u3 = _row(summary, 'U3');
      expect(u3.status, RowDataStatus.ok);
      expect(u3.close, 100);
    });
  });

  group('溫度計的連續天數', () {
    test('連 2 天在月線下、還沒數到頭 → −2、不是「至少」', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'T3': _endAtD('T3', _belowTwo)},
          watchlist: [watchOf('T3', group: _thermo)],
        ),
      );
      final t3 = _row(summary, 'T3');
      expect(t3.thermometerStreak, -2);
      expect(t3.thermometerStreakAtLeast, isFalse);
    });

    test('不足 20 根算不出均線 → 0、不是「至少」', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'T4': _endAtD('T4', repeat(100, 19))},
          watchlist: [watchOf('T4', group: _thermo)],
        ),
      );
      final t4 = _row(summary, 'T4');
      expect(t4.thermometerStreak, 0);
      expect(t4.thermometerStreakAtLeast, isFalse);
    });
  });

  test('週三 15:45、資料已是週三 → 不是等今天、也不是落後', () {
    final s = closeSummaryTimeFlags(
      dataDate: DateTime(2026, 1, 14),
      now: DateTime(2026, 1, 14, 15, 45),
    );
    expect(s.awaitingToday, isFalse);
    expect(s.dataBehind, isFalse);
  });

  group('資訊事件', () {
    test('漲停而外資賣超 → 漲停＋漲停但外資賣超', () {
      final summary = buildCloseSummary(
        _input(
          prices: {
            'I1': _endAtD('I1', [
              ...repeat(100, 40),
              120,
              ...repeat(100, 19),
              110,
            ]),
          },
          watchlist: [watchOf('I1')],
          institutional: {
            'I1': instFrom(
              [(foreign: -1000, trust: 0)],
              startDay: 60,
              symbol: 'I1',
            ),
          },
        ),
      );
      expect(_kinds(_row(summary, 'I1')), [
        SummaryEventKind.limitUp,
        SummaryEventKind.limitUpForeignSelling,
      ]);
    });

    test('收在升降單位算出的跌停價也標跌停（只跌 9.847%）', () {
      // 南亞 1303：平盤 228.5 的跌停價是 206
      final summary = buildCloseSummary(
        _input(
          prices: {
            'I3': _endAtD('I3', [...repeat(228.5, 60), 206]),
          },
          watchlist: [watchOf('I3')],
        ),
      );
      expect(_kinds(_row(summary, 'I3')), contains(SummaryEventKind.limitDown));
    });

    test('跌停 → 標跌停', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'I2': _endAtD('I2', _crossBelow)},
          watchlist: [watchOf('I2')],
        ),
      );
      expect(_kinds(_row(summary, 'I2')), contains(SummaryEventKind.limitDown));
    });
  });

  group('防禦與次序', () {
    test('數量為 0 的持股不列', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'Z1': _endAtD('Z1', _flat)},
          positions: [positionOf(symbol: 'Z1', quantity: 0, avgCost: 100)],
        ),
      );
      expect(summary.sections, isEmpty);
    });

    test('自選指到不存在的分組 → 放未分組', () {
      final ghost = groupOf(99, '已刪除', 9);
      final summary = buildCloseSummary(
        _input(
          prices: {'Z2': _endAtD('Z2', _flat)},
          watchlist: [watchOf('Z2', group: ghost)],
        ),
      );
      expect(summary.sections.single.isUngrouped, isTrue);
      expect(summary.sections.single.rows.single.symbol, 'Z2');
    });

    test('漲幅相同時依代號', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'Z4': _endAtD('Z4', _flat), 'Z3': _endAtD('Z3', _flat)},
          watchlist: [watchOf('Z4'), watchOf('Z3')],
        ),
      );
      expect(summary.sections.single.rows.map((r) => r.symbol), ['Z3', 'Z4']);
    });

    test('持股只剩配股股數（checkHolding 回 null）仍列在持股段', () {
      final summary = buildCloseSummary(
        _input(
          prices: {'Z5': _endAtD('Z5', _flat)},
          positions: [positionOf(symbol: 'Z5', quantity: 50, avgCost: 0)],
          transactions: {
            'Z5': [txOn(0, TransactionTypes.dividendStock, 50, symbol: 'Z5')],
          },
        ),
      );
      final section = summary.sections.single;
      expect(section.isHoldings, isTrue);
      expect(section.rows.single.holding, isNull);
      expect(summary.holdingCount, 1);
    });
  });
}

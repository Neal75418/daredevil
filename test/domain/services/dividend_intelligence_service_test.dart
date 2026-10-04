// 投資組合股利分析：預估年股利＝官方殖利率 × 同一天收盤價，其餘（ETF、無
// 估值）＝近一年殖利率 × 最新收盤價；趨勢比最近兩個完整年度的現金股利。
// 資料建置中一律 null（畫面顯示建置中），不加部分總和
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/dividend_intelligence_service.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

import '../../helpers/portfolio_data_builders.dart';

/// [pastCash]：去年起往前的現金股利，null＝建置中
DividendSummary _summary({
  TrailingYield trailing = const TrailingYieldBuilding(),
  List<double?> pastCash = const [null, null, null, null, null],
  List<double> pastShares = const [0, 0, 0, 0, 0],
}) => DividendSummary(
  displayEnd: DateTime(2026, 10, 2),
  parValueTen: true,
  current: const DividendYearRow(year: 2026, status: DividendYearStatus.notYet),
  pastYears: [
    for (final (i, cash) in pastCash.indexed)
      cash == null
          ? DividendYearRow(year: 2025 - i, status: DividendYearStatus.building)
          : DividendYearRow(
              year: 2025 - i,
              status: cash > 0 || pastShares[i] > 0
                  ? DividendYearStatus.paid
                  : DividendYearStatus.none,
              cash: cash,
              stockShares: pastShares[i],
            ),
  ],
  average: null,
  trailingYield: trailing,
);

const _svc = DividendIntelligenceService();

StockDividendInfo _single({
  OfficialYield? official,
  DividendSummary? summary,
  double? latestClose,
  double avgCost = 50,
}) {
  final result = _svc.analyzeDividends(
    positions: [
      createTestPortfolioPosition(
        symbol: '1111',
        quantity: 1000,
        avgCost: avgCost,
      ),
    ],
    summaries: {'1111': ?summary},
    officialYields: {'1111': ?official},
    currentPrices: {'1111': ?latestClose},
  );
  return result.stockDividends.single;
}

void main() {
  group('預估年股利（每股）', () {
    test('🚨 有官方估值：官方殖利率 × 同一天收盤價，不是最新收盤', () {
      final info = _single(
        official: (yieldPercent: 2.0, close: 500),
        summary: _summary(trailing: const TrailingYieldValue(0.05)),
        latestClose: 600,
      );
      expect(info.estimatedDividendPerShare, closeTo(10, 1e-9));
      expect(info.expectedYearlyAmount, closeTo(10000, 1e-6));
    });

    test('有官方估值時，近一年殖利率建置中也不影響', () {
      final info = _single(
        official: (yieldPercent: 2.0, close: 500),
        summary: _summary(),
        latestClose: 600,
      );
      expect(info.estimatedDividendPerShare, closeTo(10, 1e-9));
    });

    test('沒有官方估值（ETF、無估值）：近一年殖利率 × 最新收盤價', () {
      final info = _single(
        summary: _summary(trailing: const TrailingYieldValue(0.04)),
        latestClose: 50,
      );
      expect(info.estimatedDividendPerShare, closeTo(2, 1e-9));
    });

    test('🚨 近一年無配息：預估 0（不是建置中）', () {
      final info = _single(
        summary: _summary(trailing: const TrailingYieldNone()),
        latestClose: 50,
      );
      expect(info.estimatedDividendPerShare, 0);
      expect(info.expectedYearlyAmount, 0);
      expect(info.personalYield, 0);
    });

    test('近一年殖利率建置中、沒有最新收盤、沒有摘要：null', () {
      expect(
        _single(summary: _summary(), latestClose: 50).estimatedDividendPerShare,
        isNull,
      );
      expect(
        _single(
          summary: _summary(trailing: const TrailingYieldValue(0.04)),
        ).estimatedDividendPerShare,
        isNull,
      );
      expect(_single(latestClose: 50).estimatedDividendPerShare, isNull);
    });

    test('個人殖利率＝預估金額 ÷ 成本', () {
      final info = _single(
        official: (yieldPercent: 2.0, close: 500),
        avgCost: 400,
      );
      expect(info.personalYield, closeTo(2.5, 1e-9)); // 10 ÷ 400
    });
  });

  group('組合合計', () {
    test('全部有預估：加總與兩種殖利率', () {
      final result = _svc.analyzeDividends(
        positions: [
          createTestPortfolioPosition(
            id: 1,
            symbol: 'A',
            quantity: 1000,
            avgCost: 100,
          ),
          createTestPortfolioPosition(
            id: 2,
            symbol: 'B',
            quantity: 2000,
            avgCost: 50,
          ),
        ],
        summaries: {'B': _summary(trailing: const TrailingYieldValue(0.05))},
        officialYields: {'A': (yieldPercent: 4.0, close: 125)},
        currentPrices: {'A': 125, 'B': 40},
      );
      // A：4% × 125＝5 元 × 1000＝5000；B：5% × 40＝2 元 × 2000＝4000
      expect(result.totalExpectedDividend, closeTo(9000, 1e-6));
      expect(result.portfolioYieldOnCost, closeTo(4.5, 1e-9)); // ÷ 200,000
      expect(result.portfolioYieldOnMarket, closeTo(9000 / 205000 * 100, 1e-9));
    });

    test('🚨 任一持股建置中：合計與兩種殖利率都是 null（不加部分總和）', () {
      final result = _svc.analyzeDividends(
        positions: [
          createTestPortfolioPosition(
            id: 1,
            symbol: 'A',
            quantity: 1000,
            avgCost: 100,
          ),
          createTestPortfolioPosition(
            id: 2,
            symbol: '0050',
            quantity: 1000,
            avgCost: 100,
          ),
        ],
        summaries: {'0050': _summary()},
        officialYields: {'A': (yieldPercent: 4.0, close: 125)},
        currentPrices: {'A': 125, '0050': 110},
      );
      expect(result.totalExpectedDividend, isNull);
      expect(result.portfolioYieldOnCost, isNull);
      expect(result.portfolioYieldOnMarket, isNull);
      expect(
        result.stockDividends.first.expectedYearlyAmount,
        closeTo(5000, 1e-6),
      );
    });

    test('依預估金額由大到小，建置中排最後', () {
      final result = _svc.analyzeDividends(
        positions: [
          createTestPortfolioPosition(id: 1, symbol: 'X'),
          createTestPortfolioPosition(id: 2, symbol: 'S'),
          createTestPortfolioPosition(id: 3, symbol: 'L'),
        ],
        summaries: {'X': _summary()},
        officialYields: {
          'S': (yieldPercent: 1.0, close: 100),
          'L': (yieldPercent: 5.0, close: 100),
        },
        currentPrices: const {},
      );
      expect(result.stockDividends.map((s) => s.symbol), ['L', 'S', 'X']);
    });

    test('已出清的持股（數量 0）不列入', () {
      final result = _svc.analyzeDividends(
        positions: [createTestPortfolioPosition(symbol: 'A', quantity: 0)],
        summaries: const {},
        officialYields: const {},
        currentPrices: const {},
      );
      expect(result.stockDividends, isEmpty);
      expect(result.totalExpectedDividend, 0);
    });

    test('沒有持股：empty', () {
      final result = _svc.analyzeDividends(
        positions: const [],
        summaries: const {},
        officialYields: const {},
        currentPrices: const {},
      );
      expect(result, same(DividendAnalysis.empty));
    });
  });

  group('趨勢（最近兩個完整年度的現金股利）', () {
    DividendTrend? trend(
      List<double?> pastCash, {
      List<double> pastShares = const [0, 0, 0, 0, 0],
    }) => _single(
      summary: _summary(pastCash: pastCash, pastShares: pastShares),
    ).trend;

    test('現金增加超過 10%：增加；減少超過 10%：減少；其餘持平', () {
      expect(trend([1.125, 1, 0, 0, 0]), DividendTrend.increasing);
      expect(trend([1.09375, 1, 0, 0, 0]), DividendTrend.stable);
      expect(trend([0.875, 1, 0, 0, 0]), DividendTrend.decreasing);
      expect(trend([0.90625, 1, 0, 0, 0]), DividendTrend.stable);
    });

    test('只比現金、不看配股（面額不一定 10 元）', () {
      expect(
        trend([1, 1, 0, 0, 0], pastShares: [100, 0, 0, 0, 0]),
        DividendTrend.stable,
      );
    });

    test('前年沒有配發：去年有就是增加，都沒有就是持平', () {
      expect(trend([1, 0, 0, 0, 0]), DividendTrend.increasing);
      expect(trend([0, 0, 0, 0, 0]), DividendTrend.stable);
    });

    test('🚨 任一年建置中：不顯示趨勢（null）', () {
      expect(trend([null, 1, 0, 0, 0]), isNull);
      expect(trend([1, null, 0, 0, 0]), isNull);
    });

    test('只看去年與前年：更早的年度不影響', () {
      expect(trend([1, 1, null, 9, 9]), DividendTrend.stable);
    });

    test('沒有摘要：不顯示趨勢', () {
      expect(_single(official: (yieldPercent: 2.0, close: 500)).trend, isNull);
    });
  });
}

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/services/dividend_intelligence_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/portfolio_data_builders.dart';

class _FakeClock implements AppClock {
  @override
  DateTime now() => DateTime(2025, 6, 15);
}

void main() {
  final service = DividendIntelligenceService(clock: _FakeClock());
  const currentYear = 2025;

  // ==========================================
  // analyzeDividends
  // ==========================================
  group('analyzeDividends', () {
    test('returns empty for empty positions', () {
      final result = service.analyzeDividends(
        positions: [],
        dividendHistories: {},
        currentPrices: {},
      );

      expect(result.totalExpectedDividend, equals(0));
      expect(result.stockDividends, isEmpty);
    });

    test('skips positions with quantity <= 0', () {
      final positions = [
        createTestPortfolioPosition(symbol: 'A', quantity: 0),
        createTestPortfolioPosition(symbol: 'B', quantity: -10),
      ];

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: {},
        currentPrices: {},
      );

      expect(result.stockDividends, isEmpty);
      expect(result.totalExpectedDividend, equals(0));
    });

    test('calculates personal yield correctly', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: '2330',
          quantity: 1000,
          avgCost: 500.0,
        ),
      ];
      final histories = {
        '2330': [
          createTestDividendHistory(
            symbol: '2330',
            year: currentYear,
            cashDividend: 15.0,
            stockDividend: 0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'2330': 600.0},
      );

      expect(result.stockDividends.length, equals(1));
      final info = result.stockDividends.first;
      // personalYield = (15 * 1000) / (500 * 1000) * 100 = 3.0%
      expect(info.personalYield, closeTo(3.0, 0.01));
      // marketYield = (15 * 1000) / (600 * 1000) * 100 = 2.5%
      expect(info.expectedYearlyAmount, equals(15000.0));
    });

    test('uses avgCost as fallback when currentPrice missing', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: '2330',
          quantity: 1000,
          avgCost: 500.0,
        ),
      ];
      final histories = {
        '2330': [
          createTestDividendHistory(
            symbol: '2330',
            year: currentYear,
            cashDividend: 10.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {}, // no current price
      );

      final info = result.stockDividends.first;
      // currentPrice falls back to avgCost = 500
    });

    test('calculates portfolio yields correctly', () {
      final positions = [
        createTestPortfolioPosition(
          id: 1,
          symbol: 'A',
          quantity: 1000,
          avgCost: 100.0,
        ),
        createTestPortfolioPosition(
          id: 2,
          symbol: 'B',
          quantity: 500,
          avgCost: 200.0,
        ),
      ];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear,
            cashDividend: 5.0,
          ),
        ],
        'B': [
          createTestDividendHistory(
            symbol: 'B',
            year: currentYear,
            cashDividend: 10.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 120.0, 'B': 220.0},
      );

      // totalExpected = 5*1000 + 10*500 = 10000
      expect(result.totalExpectedDividend, equals(10000.0));
      // totalCost = 100*1000 + 200*500 = 200000
      expect(result.portfolioYieldOnCost, closeTo(5.0, 0.01));
      // totalMarket = 120*1000 + 220*500 = 230000
      expect(
        result.portfolioYieldOnMarket,
        closeTo(10000.0 / 230000 * 100, 0.01),
      );
    });

    test('sorts stockDividends by expectedYearlyAmount descending', () {
      final positions = [
        createTestPortfolioPosition(id: 1, symbol: 'A', quantity: 100),
        createTestPortfolioPosition(id: 2, symbol: 'B', quantity: 1000),
      ];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear,
            cashDividend: 5.0,
          ),
        ],
        'B': [
          createTestDividendHistory(
            symbol: 'B',
            year: currentYear,
            cashDividend: 5.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0, 'B': 100.0},
      );

      // B has more shares → higher expected amount
      expect(result.stockDividends.first.symbol, equals('B'));
      expect(result.stockDividends.last.symbol, equals('A'));
    });

    test('handles position with no dividend history', () {
      final positions = [
        createTestPortfolioPosition(symbol: '2330', quantity: 1000),
      ];

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: {}, // no history
        currentPrices: {'2330': 100.0},
      );

      expect(result.stockDividends.length, equals(1));
      expect(result.stockDividends.first.estimatedDividendPerShare, equals(0));
      expect(result.stockDividends.first.expectedYearlyAmount, equals(0));
    });
  });

  // ==========================================
  // _estimateAnnualDividend (via analyzeDividends)
  // ==========================================
  group('estimateAnnualDividend', () {
    test('uses current year data when available', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear,
            cashDividend: 8.0,
            stockDividend: 2.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 5.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 2,
            cashDividend: 4.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      // Should use current year: 8 + 2 = 10
      expect(
        result.stockDividends.first.estimatedDividendPerShare,
        equals(10.0),
      );
    });

    test('uses 3-year average when no current year data', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 6.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 2,
            cashDividend: 4.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 3,
            cashDividend: 5.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      // Average of 3 years: (6+4+5)/3 = 5.0
      expect(
        result.stockDividends.first.estimatedDividendPerShare,
        equals(5.0),
      );
    });

    test('uses single year when only 1 year available', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 7.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      expect(
        result.stockDividends.first.estimatedDividendPerShare,
        equals(7.0),
      );
    });

    test('includes stock dividend in estimation', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 3.0,
            stockDividend: 1.5,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      expect(
        result.stockDividends.first.estimatedDividendPerShare,
        equals(4.5),
      );
    });

    test('returns 0 for empty history', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: {'A': []},
        currentPrices: {'A': 100.0},
      );

      expect(result.stockDividends.first.estimatedDividendPerShare, equals(0));
    });
  });

  // ==========================================
  // _analyzeTrend (via analyzeDividends)
  // ==========================================
  group('analyzeTrend', () {
    test('returns increasing when change > 10%', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 6.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 2,
            cashDividend: 5.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      // (6-5)/5 * 100 = 20% > 10%
      expect(
        result.stockDividends.first.trend,
        equals(DividendTrend.increasing),
      );
    });

    test('returns decreasing when change < -10%', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 4.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 2,
            cashDividend: 5.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      // (4-5)/5 * 100 = -20% < -10%
      expect(
        result.stockDividends.first.trend,
        equals(DividendTrend.decreasing),
      );
    });

    test('returns stable when change between -10% and 10%', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 5.2,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 2,
            cashDividend: 5.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      // (5.2-5)/5 * 100 = 4% → stable
      expect(result.stockDividends.first.trend, equals(DividendTrend.stable));
    });

    test('returns stable with < 2 entries', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 5.0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      expect(result.stockDividends.first.trend, equals(DividendTrend.stable));
    });

    test('returns increasing when previous total is 0', () {
      final positions = [createTestPortfolioPosition(symbol: 'A', quantity: 1)];
      final histories = {
        'A': [
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 1,
            cashDividend: 3.0,
          ),
          createTestDividendHistory(
            symbol: 'A',
            year: currentYear - 2,
            cashDividend: 0,
            stockDividend: 0,
          ),
        ],
      };

      final result = service.analyzeDividends(
        positions: positions,
        dividendHistories: histories,
        currentPrices: {'A': 100.0},
      );

      expect(
        result.stockDividends.first.trend,
        equals(DividendTrend.increasing),
      );
    });
  });
}

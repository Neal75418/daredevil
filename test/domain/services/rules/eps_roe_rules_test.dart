import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/fundamental_scan_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';
import '../../../helpers/stock_data_builders.dart';

/// 建構站上 MA 且長紅的價格資料（給 EPS/ROE 規則用）
List<DailyPriceEntry> _generatePricesAboveMA({
  required int maPeriod,
  double basePrice = 100.0,
  double lastDayChangePct = 0.05,
}) {
  final days = maPeriod + 5;
  final now = DateTime(2025, 6, 1);
  return List.generate(days, (i) {
    final isLast = i == days - 1;
    final close = isLast ? basePrice * (1 + lastDayChangePct) : basePrice;
    return createTestPrice(
      date: now.subtract(Duration(days: days - i - 1)),
      close: close,
      volume: 1000,
    );
  });
}

/// 建構強力上升 RSI > 50 的價格資料
List<DailyPriceEntry> _generateStrongRsiPrices() {
  final now = DateTime(2025, 6, 1);
  return List.generate(30, (i) {
    return createTestPrice(
      date: now.subtract(Duration(days: 29 - i)),
      close: 100.0 + (i * 1.0), // Moderate uptrend → RSI > 50
      volume: 1000,
    );
  });
}

void main() {
  // ==========================================
  // EPSYoYSurgeRule
  // ==========================================
  group('EPSYoYSurgeRule', () {
    const rule = EPSYoYSurgeRule();

    test('triggers when EPS yoy growth >= 50% with MA60 confirmation', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      // Build EPS history: latest quarter EPS=3.0, same quarter last year EPS=1.5
      // yoy growth = (3.0-1.5)/1.5 * 100 = 100% >= 50%
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 3.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 2.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 6, 1),
          dataType: 'EPS',
          value: 2.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 9, 1),
          dataType: 'EPS',
          value: 1.8,
        ),
        // Same month as latest (i.e. same quarter last year) — at index >= epsQuarterOffset (4)
        createTestFinancialData(
          date: DateTime(now.year - 1, now.month, 1),
          dataType: 'EPS',
          value: 1.5,
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.epsYoYSurge));
      expect(result.score, equals(RuleScores.epsYoYSurge));
      expect(result.evidence!['yoyGrowth'], equals(100.0));
    });

    test('does not trigger when yoy growth is below threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      final now = DateTime(2025, 6, 1);
      // yoy growth = (1.2-1.0)/1.0 * 100 = 20% < 50%
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 1.2,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 1.1,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 6, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 9, 1),
          dataType: 'EPS',
          value: 0.9,
        ),
        createTestFinancialData(
          date: DateTime(now.year - 1, now.month, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when latest EPS is negative', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: -0.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 6, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 9, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year - 1, now.month, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient EPS history', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 3.0,
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // EPSConsecutiveGrowthRule
  // ==========================================
  group('EPSConsecutiveGrowthRule', () {
    const rule = EPSConsecutiveGrowthRule();

    test('triggers with >= 2 consecutive quarterly growth and MA20', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      // 2026-08-15:比較基準由 QoQ 改為**同季 YoY**,fixture 需 6 季
      // (最新兩季各要有去年同季當基期)。
      // 等差序列 baseEps=1.0、每季 +0.5 → 6 季為 3.5,3.0,2.5,2.0,1.5,1.0
      // 最新季 3.5 vs 去年同季 1.5 = +133%;次新 3.0 vs 1.0 = +200% → 連續 2 季
      final epsHistory = generateEpsHistory(
        quarters: 6,
        baseEps: 1.0,
        quarterlyGrowth: 0.5,
      );
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.epsConsecutiveGrowth));
      expect(result.score, equals(RuleScores.epsConsecutiveGrowth));
    });

    test('does not trigger when growth is below threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      // EPS: 1.05, 1.02, 1.0 (very small growth < 10%)
      final epsHistory = generateEpsHistory(
        quarters: 3,
        baseEps: 1.0,
        quarterlyGrowth: 0.025,
      );
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when price is below MA20', () {
      final prices = generateConstantPrices(days: 30, basePrice: 100.0);
      // Last price = 100, MA20 ≈ 100 → close not > MA20
      final epsHistory = generateEpsHistory(
        quarters: 3,
        baseEps: 1.0,
        quarterlyGrowth: 0.5,
      );
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient quarters', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final epsHistory = generateEpsHistory(quarters: 2, baseEps: 1.0);
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      // epsConsecutiveQuarters = 2, needs 3 entries (2+1)
      // Only 2 entries → length < 3 → returns null
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // EPSTurnaroundRule
  // ==========================================
  group('EPSTurnaroundRule', () {
    const rule = EPSTurnaroundRule();

    test('triggers when previous EPS < 0 and latest >= 0.3 with MA20', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.5, // >= 0.3 threshold
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: -0.8, // < 0 (previous loss)
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      // 提供 MA20 讓 aboveMA20 條件成立（close=105 > ma20=100）
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(ma20: 100),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.epsTurnaround));
      expect(result.score, equals(RuleScores.epsTurnaround));
    });

    test('triggers with RSI > 50 even without MA20', () {
      // Use strong RSI prices where close may not be > MA20 but RSI > 50
      final prices = _generateStrongRsiPrices();
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: -1.0,
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      // 提供 RSI > 50 讓 rsiPositive 條件成立
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(rsi: 60),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.epsTurnaround));
    });

    test('does not trigger when previous quarter is not a loss', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 0.2, // >= 0 → not a loss
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when latest EPS is below turnaround threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.1, // < 0.3 threshold
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: -0.5,
        ),
      ];
      final data = createTestStockData(prices: prices, epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // EPSDeclineWarningRule
  // ==========================================
  group('EPSDeclineWarningRule', () {
    const rule = EPSDeclineWarningRule();

    test('triggers with 2 consecutive quarters of decline >= 20%', () {
      final now = DateTime(2025, 6, 1);
      // 2026-08-15:比較基準由 QoQ 改為**同季 YoY**,fixture 需含去年同季。
      // 最新季 0.5 vs 去年同季 2.0 → 衰退 75%;
      // 次新季 1.0 vs 去年同季 2.5 → 衰退 60%。連續 2 季 ≥ 20% → 觸發。
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 6, 1),
          dataType: 'EPS',
          value: 1.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 9, 1),
          dataType: 'EPS',
          value: 2.2,
        ),
        createTestFinancialData(
          date: DateTime(now.year - 1, now.month, 1),
          dataType: 'EPS',
          value: 2.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year - 1, now.month - 3, 1),
          dataType: 'EPS',
          value: 2.5,
        ),
      ];
      final data = createTestStockData(epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.epsDeclineWarning));
      expect(result.score, equals(RuleScores.epsDeclineWarning));
      expect(result.evidence!['declineQuarters'], equals(2));
    });

    test('does not trigger when decline is less than 20%', () {
      final now = DateTime(2025, 6, 1);
      // Decline: (1.0-0.9)/1.0 = 10% < 20%
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.9,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 6, 1),
          dataType: 'EPS',
          value: 1.1,
        ),
      ];
      final data = createTestStockData(epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final now = DateTime(2025, 6, 1);
      final epsHistory = [
        createTestFinancialData(
          date: DateTime(now.year, now.month, 1),
          dataType: 'EPS',
          value: 0.5,
        ),
        createTestFinancialData(
          date: DateTime(now.year, now.month - 3, 1),
          dataType: 'EPS',
          value: 1.0,
        ),
      ];
      final data = createTestStockData(epsHistory: epsHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      // Needs length >= 3
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // ROEExcellentRule
  // ==========================================
  group('ROEExcellentRule', () {
    const rule = ROEExcellentRule();

    test('triggers when ROE >= 15% with MA20 confirmation', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final roeHistory = generateRoeHistory(
        quarters: 4,
        baseRoe: 18.0,
        quarterlyChange: 0.0,
      );
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.roeExcellent));
      expect(result.score, equals(RuleScores.roeExcellent));
    });

    test('does not trigger when ROE is below threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final roeHistory = generateRoeHistory(
        quarters: 4,
        baseRoe: 10.0,
        quarterlyChange: 0.0,
      );
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when price is below MA20', () {
      final prices = generateConstantPrices(days: 30, basePrice: 100.0);
      final roeHistory = generateRoeHistory(
        quarters: 4,
        baseRoe: 20.0,
        quarterlyChange: 0.0,
      );
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when ROE history is empty', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final data = createTestStockData(prices: prices);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // ROEImprovingRule
  // ==========================================
  group('ROEImprovingRule', () {
    const rule = ROEImprovingRule();

    test('triggers with >= 2 consecutive quarters of ROE improving >= 5pt', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      // ROE (newest first): 20, 14, 8
      // Improvement: 20-14=6 >= 5, 14-8=6 >= 5 → consecutive = 2
      final roeHistory = generateRoeHistory(
        quarters: 3,
        baseRoe: 8.0,
        quarterlyChange: 6.0,
      );
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.roeImproving));
      expect(result.score, equals(RuleScores.roeImproving));
    });

    test('does not trigger when improvement is below threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      // ROE (newest first): 12, 10, 8 → improvement = 2pt < 5pt
      final roeHistory = generateRoeHistory(
        quarters: 3,
        baseRoe: 8.0,
        quarterlyChange: 2.0,
      );
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when price is below MA20', () {
      final prices = generateConstantPrices(days: 30, basePrice: 100.0);
      final roeHistory = generateRoeHistory(
        quarters: 3,
        baseRoe: 8.0,
        quarterlyChange: 6.0,
      );
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient quarters', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final roeHistory = generateRoeHistory(quarters: 2, baseRoe: 10.0);
      final data = createTestStockData(prices: prices, roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      // roeMinQuarters = 2, needs length >= 3
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // ROEDecliningRule
  // ==========================================
  group('ROEDecliningRule', () {
    const rule = ROEDecliningRule();

    test('triggers with >= 2 consecutive quarters of ROE declining >= 5pt', () {
      // ROE (newest first): 8, 14, 20
      // Decline: 14-8=6 >= 5, 20-14=6 >= 5 → consecutive = 2
      final roeHistory = generateRoeHistory(
        quarters: 3,
        baseRoe: 20.0,
        quarterlyChange: -6.0,
      );
      final data = createTestStockData(roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.roeDeclining));
      expect(result.score, equals(RuleScores.roeDeclining));
      expect(result.evidence!['decliningQuarters'], equals(2));
    });

    test('does not trigger when decline is below threshold', () {
      // ROE: 10, 12, 14 → decline = 2pt < 5pt
      final roeHistory = generateRoeHistory(
        quarters: 3,
        baseRoe: 14.0,
        quarterlyChange: -2.0,
      );
      final data = createTestStockData(roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient quarters', () {
      final roeHistory = generateRoeHistory(quarters: 2, baseRoe: 20.0);
      final data = createTestStockData(roeHistory: roeHistory);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when ROE history is null', () {
      final data = createTestStockData();
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });
}

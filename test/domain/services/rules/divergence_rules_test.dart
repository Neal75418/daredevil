import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/divergence_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';

void main() {
  // ==========================================
  // PriceVolumeWeakRallyRule (價漲量縮)
  // ==========================================
  group('PriceVolumeWeakRallyRule', () {
    const rule = PriceVolumeWeakRallyRule();

    test('triggers when price rises but volume shrinks', () {
      final now = DateTime.now();
      // 6 entries (lookback=5 + 1):
      // entry[0] (oldest/past): close=100, vol=10000
      // entry[1..4]: close=100, vol=10000
      // entry[5] (today): close=102 (+2%), vol=8000 (-20%)
      final prices = List.generate(6, (i) {
        final isToday = i == 5;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          open: 100.0,
          high: isToday ? 103.0 : 101.0,
          low: 99.0,
          close: isToday ? 102.0 : 100.0,
          volume: isToday ? 8000 : 10000,
        );
      });
      // priceChange = (102-100)/100 * 100 = 2.0% >= 1.0% ✓
      // avgVolume = 10000
      // volumeChange = (8000-10000)/10000 * 100 = -20% <= -10% ✓

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.priceVolumeWeakRally));
      expect(result.score, equals(RuleScores.priceVolumeWeakRally));
    });

    test('does not trigger when price rise is too small', () {
      final now = DateTime.now();
      // close=100.3 (+0.3% < 1.0%)
      final prices = List.generate(6, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          open: 100.0,
          high: 101.0,
          low: 99.0,
          close: i == 5 ? 100.3 : 100.0,
          volume: i == 5 ? 8000 : 10000,
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when volume does not shrink enough', () {
      final now = DateTime.now();
      // vol=9500 → volumeChange = -5% > -10%
      final prices = List.generate(6, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          open: 100.0,
          high: 103.0,
          low: 99.0,
          close: i == 5 ? 102.0 : 100.0,
          volume: i == 5 ? 9500 : 10000,
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 3, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // PriceVolumeBearishDivergenceRule (價跌量增)
  // ==========================================
  group('PriceVolumeBearishDivergenceRule', () {
    const rule = PriceVolumeBearishDivergenceRule();

    test('triggers when price drops and volume increases', () {
      final now = DateTime.now();
      final prices = List.generate(6, (i) {
        final isToday = i == 5;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          open: 100.0,
          high: 101.0,
          low: isToday ? 97.0 : 99.0,
          close: isToday ? 98.0 : 100.0, // -2%
          volume: isToday ? 12000 : 10000, // +20%
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.priceVolumeBearishDivergence));
      expect(result.score, equals(RuleScores.priceVolumeBearishDivergence));
    });

    test('does not trigger when price drop is too small', () {
      final now = DateTime.now();
      final prices = List.generate(6, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          open: 100.0,
          high: 101.0,
          low: 99.0,
          close: i == 5 ? 99.8 : 100.0, // -0.2% > -1.0%
          volume: i == 5 ? 12000 : 10000,
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when volume does not increase enough', () {
      final now = DateTime.now();
      final prices = List.generate(6, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          open: 100.0,
          high: 101.0,
          low: 97.0,
          close: i == 5 ? 98.0 : 100.0,
          volume: i == 5 ? 10500 : 10000, // +5% < 10%
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // HighVolumeBreakoutRule (高檔爆量)
  // ==========================================
  group('HighVolumeBreakoutRule', () {
    const rule = HighVolumeBreakoutRule();

    test('triggers at high position with volume spike', () {
      final now = DateTime.now();
      // 60 days: close=100, high=102, low=98, vol=1000
      // Last day: close=102 (near top), vol=5000 (5x avg, > 4x threshold)
      final prices = List.generate(61, (i) {
        final isLast = i == 60;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 60 - i)),
          open: 100.0,
          high: 102.0,
          low: 98.0,
          close: isLast ? 102.0 : 100.0,
          volume: isLast ? 5000 : 1000,
        );
      });
      // range high=102, low=98, range=4
      // position = (102-98)/4 = 1.0 >= 0.85 ✓
      // volume 5000 >= 1000 * 4.0 = 4000 ✓

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.highVolumeBreakout));
      expect(result.score, equals(RuleScores.highVolumeBreakout));
    });

    test('does not trigger at low position', () {
      final now = DateTime.now();
      final prices = List.generate(61, (i) {
        final isLast = i == 60;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 60 - i)),
          open: 100.0,
          high: 102.0,
          low: 98.0,
          close: isLast ? 98.5 : 100.0, // Near low
          volume: isLast ? 5000 : 1000,
        );
      });
      // position = (98.5-98)/4 = 0.125 < 0.85

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with normal volume', () {
      final now = DateTime.now();
      final prices = List.generate(61, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 60 - i)),
          open: 100.0,
          high: 102.0,
          low: 98.0,
          close: i == 60 ? 102.0 : 100.0,
          volume: 1000, // Same volume → no spike
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 30, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // LowVolumeAccumulationRule (低檔吸籌)
  // ==========================================
  group('LowVolumeAccumulationRule', () {
    const rule = LowVolumeAccumulationRule();

    test('triggers at low position with shrinking volume', () {
      final now = DateTime.now();
      // 60 days: close=100, high=102, low=98, vol=1000
      // Last day: close=98.5 (near bottom), vol=400 (40% of avg, < 60%)
      final prices = List.generate(61, (i) {
        final isLast = i == 60;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 60 - i)),
          open: 100.0,
          high: 102.0,
          low: 98.0,
          close: isLast ? 98.5 : 100.0,
          volume: isLast ? 400 : 1000,
        );
      });
      // position = (98.5-98)/4 = 0.125 <= 0.25 ✓
      // volumeRatio = 400/1000 = 0.4 < 0.6 ✓

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.lowVolumeAccumulation));
      expect(result.score, equals(RuleScores.lowVolumeAccumulation));
    });

    test('does not trigger at high position', () {
      final now = DateTime.now();
      final prices = List.generate(61, (i) {
        final isLast = i == 60;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 60 - i)),
          open: 100.0,
          high: 102.0,
          low: 98.0,
          close: isLast ? 101.5 : 100.0, // Near high
          volume: isLast ? 400 : 1000,
        );
      });
      // position = (101.5-98)/4 = 0.875 > 0.25

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when volume is not low enough', () {
      final now = DateTime.now();
      final prices = List.generate(61, (i) {
        final isLast = i == 60;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 60 - i)),
          open: 100.0,
          high: 102.0,
          low: 98.0,
          close: isLast ? 98.5 : 100.0,
          volume: isLast ? 800 : 1000, // 80% of avg > 60%
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });
}

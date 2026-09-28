import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/indicator_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';

/// 建構帶成交量的上升趨勢資料
List<DailyPriceEntry> _generateUptrendWithVolume({
  required int days,
  double startPrice = 100.0,
  double dailyGain = 1.0,
  double volume = 5000,
  double lastVolume = 8000,
}) {
  final now = DateTime.now();
  return List.generate(days, (i) {
    final price = startPrice + (i * dailyGain);
    final isLast = i == days - 1;
    return DailyPriceEntry(
      symbol: 'TEST',
      date: now.subtract(Duration(days: days - i - 1)),
      open: price - 0.5,
      high: price + 1.0,
      low: price - 1.0,
      close: price,
      volume: isLast ? lastVolume : volume,
    );
  });
}

/// 建構帶成交量的下降趨勢資料
List<DailyPriceEntry> _generateDowntrendWithVolume({
  required int days,
  double startPrice = 200.0,
  double dailyLoss = 1.0,
  double volume = 5000,
  double lastVolume = 8000,
}) {
  final now = DateTime.now();
  return List.generate(days, (i) {
    final price = startPrice - (i * dailyLoss);
    final isLast = i == days - 1;
    return DailyPriceEntry(
      symbol: 'TEST',
      date: now.subtract(Duration(days: days - i - 1)),
      open: price + 0.5,
      high: price + 1.0,
      low: price - 1.0,
      close: price,
      volume: isLast ? lastVolume : volume,
    );
  });
}

void main() {
  // ==========================================
  // Week52HighRule
  // ==========================================
  group('Week52HighRule', () {
    const rule = Week52HighRule();

    test('triggers when close is a new 52-week high', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(
          date: DateTime.now(),
          open: 104.0,
          high: 106.0,
          low: 103.0,
          close: 105.0,
          volume: 1000,
        ),
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52High));
      expect(result.score, equals(RuleScores.week52High));
      expect(result.evidence!['isNewHigh'], isTrue);
    });

    test('triggers when close is near 52-week high (within threshold)', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 100.5, volume: 1000),
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52High));
      expect(result.evidence!['isNewHigh'], isFalse);
    });

    test('does not trigger when close is far from 52-week high', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 90.0, volume: 1000),
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data (< 250 days)', () {
      final prices = generateConstantPrices(days: 100, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when close is null', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(createTestPrice(date: DateTime.now()));
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('triggers with dividend adjustment (stock at adjusted high)', () {
      // 歷史高點 100, 期間內配 5 元現金股利
      // 調整後高點 = 100 - 5 = 95, 門檻 = 95 * 0.99 = 94.05
      // 收盤 96 > 94.05 → 應觸發
      final now = DateTime.now();
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(createTestPrice(date: now, close: 96.0, volume: 1000));

      // 期間內有除息紀錄
      final dividends = [
        DividendHistoryEntry(
          symbol: 'TEST',
          year: now.year,
          cashDividend: 5.0,
          stockDividend: 0,
          exDividendDate: now
              .subtract(const Duration(days: 30))
              .toIso8601String()
              .split('T')
              .first,
        ),
      ];

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividendHistory: dividends,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52High));
      expect(result.evidence!['dividendAdjustment'], equals(5.0));
    });

    test('does not trigger without dividend adjustment for same price', () {
      // 同上場景但無 dividend data → 96 < 99 (100*0.99) → 不觸發
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 96.0, volume: 1000),
      );

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // Week52LowRule
  // ==========================================
  group('Week52LowRule', () {
    const rule = Week52LowRule();

    test('triggers in downtrend with close near 52-week low', () {
      final prices = _generateDowntrendWithVolume(
        days: 250,
        startPrice: 200.0,
        dailyLoss: 0.3,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52Low));
      expect(result.score, equals(RuleScores.week52Low));
    });

    test('does not trigger when close is far from 52-week low', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 200.0, volume: 1000),
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when MA filter not confirmed (close >= MA20)', () {
      // Flat at 100 → close = MA20 ≈ MA60 ≈ 100, close >= MA20 → filtered
      final prices = generateConstantPrices(days: 250, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 100, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // MAAlignmentBullishRule
  // ==========================================
  group('MAAlignmentBullishRule', () {
    const rule = MAAlignmentBullishRule();

    test('triggers with strong uptrend + volume confirmation', () {
      final prices = _generateUptrendWithVolume(
        days: 70,
        startPrice: 100.0,
        dailyGain: 1.0,
        volume: 5000,
        lastVolume: 8000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
        indicators: indicatorsFromPrices(prices),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.maAlignmentBullish));
      expect(result.score, equals(RuleScores.maAlignmentBullish));
    });

    test('does not trigger when volume is insufficient', () {
      final prices = _generateUptrendWithVolume(
        days: 70,
        startPrice: 100.0,
        dailyGain: 1.0,
        volume: 5000,
        lastVolume: 5000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with flat prices (no MA separation)', () {
      final prices = generateConstantPrices(days: 70, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 30, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // MAAlignmentBearishRule
  // ==========================================
  group('MAAlignmentBearishRule', () {
    const rule = MAAlignmentBearishRule();

    test('triggers with strong downtrend', () {
      final prices = _generateDowntrendWithVolume(
        days: 70,
        startPrice: 200.0,
        dailyLoss: 1.0,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
        indicators: indicatorsFromPrices(prices),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.maAlignmentBearish));
      expect(result.score, equals(RuleScores.maAlignmentBearish));
    });

    test('does not trigger with flat prices', () {
      final prices = generateConstantPrices(days: 70, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 30, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // RSIExtremeOverboughtRule
  // ==========================================
  group('RSIExtremeOverboughtRule', () {
    const rule = RSIExtremeOverboughtRule();

    test('triggers when RSI >= rsiExtremeOverbought (85)', () {
      final prices = _generateUptrendWithVolume(
        days: 16,
        startPrice: 100.0,
        dailyGain: 2.0,
      );
      final rsi = TechnicalIndicatorService.latestRSI(
        prices,
        period: IndicatorParams.rsiPeriod,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
        indicators: TechnicalIndicators(rsi: rsi),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.rsiExtremeOverbought));
    });

    test('does not trigger when RSI is neutral', () {
      final prices = generateSwingPrices(days: 30, basePrice: 100.0);
      final rsi = TechnicalIndicatorService.latestRSI(
        prices,
        period: IndicatorParams.rsiPeriod,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: TechnicalIndicators(rsi: rsi),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // RSIExtremeOversoldRule
  // ==========================================
  group('RSIExtremeOversoldRule', () {
    const rule = RSIExtremeOversoldRule();

    test('triggers when RSI <= oversold threshold', () {
      final prices = _generateDowntrendWithVolume(
        days: 16,
        startPrice: 200.0,
        dailyLoss: 2.0,
      );
      final rsi = TechnicalIndicatorService.latestRSI(
        prices,
        period: IndicatorParams.rsiPeriod,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
        indicators: TechnicalIndicators(rsi: rsi),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.rsiExtremeOversold));
    });

    test('does not trigger when RSI is neutral', () {
      final prices = generateSwingPrices(days: 30, basePrice: 100.0);
      final rsi = TechnicalIndicatorService.latestRSI(
        prices,
        period: IndicatorParams.rsiPeriod,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: TechnicalIndicators(rsi: rsi),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // KDGoldenCrossRule
  // ==========================================
  group('KDGoldenCrossRule', () {
    const rule = KDGoldenCrossRule();

    test('triggers with golden cross in oversold zone + volume + price up', () {
      final now = DateTime.now();
      final prices = List.generate(7, (i) {
        final isLast = i == 6;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 6 - i)),
          open: 100.0,
          high: isLast ? 103.0 : 101.0,
          low: isLast ? 100.0 : 99.0,
          close: isLast ? 102.0 : 100.0,
          volume: isLast ? 3000 : 1000,
        );
      });

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
        indicators: const TechnicalIndicators(
          kdK: 35.0,
          kdD: 30.0,
          prevKdK: 25.0,
          prevKdD: 30.0,
        ),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.kdGoldenCross));
      expect(result.score, equals(RuleScores.kdGoldenCross));
    });

    test('does not trigger when prevK >= golden cross zone', () {
      final now = DateTime.now();
      final prices = List.generate(7, (i) {
        final isLast = i == 6;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 6 - i)),
          open: 100.0,
          high: isLast ? 103.0 : 101.0,
          low: 99.0,
          close: isLast ? 102.0 : 100.0,
          volume: isLast ? 3000 : 1000,
        );
      });

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(
          kdK: 55.0,
          kdD: 50.0,
          prevKdK: 50.0,
          prevKdD: 55.0,
        ),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger without volume confirmation', () {
      final now = DateTime.now();
      final prices = List.generate(7, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 6 - i)),
          open: 100.0,
          high: 102.0,
          low: 99.0,
          close: i == 6 ? 102.0 : 100.0,
          volume: 1000,
        );
      });

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
        indicators: const TechnicalIndicators(
          kdK: 35.0,
          kdD: 30.0,
          prevKdK: 25.0,
          prevKdD: 30.0,
        ),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when indicators are null', () {
      final prices = generateConstantPrices(days: 10, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // KDDeathCrossRule
  // ==========================================
  group('KDDeathCrossRule', () {
    const rule = KDDeathCrossRule();

    test('triggers with death cross in overbought zone + volume', () {
      final now = DateTime.now();
      final prices = List.generate(7, (i) {
        final isLast = i == 6;
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 6 - i)),
          open: 100.0,
          high: 101.0,
          low: isLast ? 97.0 : 99.0,
          close: isLast ? 98.0 : 100.0,
          volume: isLast ? 3000 : 1000,
        );
      });

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
        indicators: const TechnicalIndicators(
          kdK: 65.0,
          kdD: 70.0,
          prevKdK: 75.0,
          prevKdD: 70.0,
        ),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.kdDeathCross));
      expect(result.score, equals(RuleScores.kdDeathCross));
    });

    test('does not trigger when prevK <= death cross zone', () {
      final now = DateTime.now();
      final prices = List.generate(7, (i) {
        return DailyPriceEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 6 - i)),
          open: 100.0,
          high: 101.0,
          low: 99.0,
          close: 100.0,
          volume: i == 6 ? 3000 : 1000,
        );
      });

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(
          kdK: 45.0,
          kdD: 50.0,
          prevKdK: 50.0,
          prevKdD: 45.0,
        ),
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when indicators are null', () {
      final prices = generateConstantPrices(days: 10, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(symbol: 'TEST', prices: prices);

      expect(rule.evaluate(context, data), isNull);
    });
  });
}

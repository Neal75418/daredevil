import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/candlestick_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/candlestick_data_generators.dart';
import '../../../helpers/price_data_generators.dart';

void main() {
  // ==========================================
  // DojiRule
  // ==========================================

  group('DojiRule', () {
    const rule = DojiRule();

    test('triggers with doji candle when RSI is extreme (< 30)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
        indicators: const TechnicalIndicators(rsi: 25.0),
      );
      final now = DateTime.now();
      final doji = createDojiCandle(date: now, price: 100.0, range: 10.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [doji],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternDoji));
      expect(result.score, equals(RuleScores.patternDoji));
    });

    test('returns null when RSI is null (cannot determine position)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      final doji = createDojiCandle(date: now, price: 100.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [doji],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);
      expect(result, isNull);
    });

    test('triggers bearish doji when RSI > 70', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
        indicators: const TechnicalIndicators(rsi: 75.0),
      );
      final now = DateTime.now();
      final doji = createDojiCandle(date: now, price: 100.0, range: 10.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [doji],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternDojiBearish));
      expect(result.score, equals(RuleScores.patternDojiBearish));
    });

    test('does not trigger when RSI is in neutral zone (30-70)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(rsi: 50.0),
      );
      final now = DateTime.now();
      final doji = createDojiCandle(date: now, price: 100.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [doji],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);
      expect(result, isNull);
    });

    test('does not trigger with empty prices', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    // 門檻值本身屬極端區（與 RSI 超買／超賣規則的 >=、<= 一致）
    group('RSI 邊界', () {
      ReasonType? typeAt(double rsi) {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          indicators: TechnicalIndicators(rsi: rsi),
        );
        final doji = createDojiCandle(
          date: DateTime(2025, 6, 1),
          price: 100.0,
          range: 10.0,
        );
        return rule
            .evaluate(
              context,
              StockData(
                symbol: 'TEST',
                prices: [doji],
                dividends: DividendContext.noEvents,
              ),
            )
            ?.type;
      }

      test('RSI 恰為高檔門檻 → 高檔十字線（偏空）', () {
        expect(
          typeAt(IndicatorParams.rsiNeutralHigh),
          ReasonType.patternDojiBearish,
        );
      });

      test('RSI 恰為低檔門檻 → 低檔十字線（偏多）', () {
        expect(
          typeAt(IndicatorParams.rsiExtremeOversold),
          ReasonType.patternDoji,
        );
      });

      test('門檻內側一點點屬中性區，不觸發', () {
        expect(typeAt(IndicatorParams.rsiNeutralHigh - 0.01), isNull);
        expect(typeAt(IndicatorParams.rsiExtremeOversold + 0.01), isNull);
      });
    });
  });

  // ==========================================
  // BullishEngulfingRule
  // ==========================================

  group('BullishEngulfingRule', () {
    const rule = BullishEngulfingRule();

    test('triggers in downtrend with valid bullish engulfing', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final now = DateTime.now();

      // Build base prices with normal volume, then append engulfing pair
      final basePrices = generateConstantPrices(
        days: 5,
        basePrice: 100.0,
        volume: 1000,
      );
      final pair = createBullishEngulfingPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        volume: 2000, // above average
      );
      final allPrices = [...basePrices, pair.prev, pair.today];
      final data = StockData(
        symbol: 'TEST',
        prices: allPrices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternBullishEngulfing));
      expect(result.score, equals(RuleScores.patternEngulfingBullish));
    });

    test('triggers in range trend (not uptrend)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();

      final basePrices = generateConstantPrices(
        days: 5,
        basePrice: 100.0,
        volume: 1000,
      );
      final pair = createBullishEngulfingPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        volume: 2000,
      );
      final allPrices = [...basePrices, pair.prev, pair.today];
      final data = StockData(
        symbol: 'TEST',
        prices: allPrices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNotNull);
    });

    test('does not trigger in uptrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final now = DateTime.now();
      final pair = createBullishEngulfingPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [createTestPrice(date: DateTime.now(), close: 100.0)],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // BearishEngulfingRule
  // ==========================================

  group('BearishEngulfingRule', () {
    const rule = BearishEngulfingRule();

    test('triggers in uptrend with valid bearish engulfing + volume', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final now = DateTime.now();

      // Build base prices with normal volume, then append engulfing pair
      final basePrices = generateConstantPrices(
        days: 5,
        basePrice: 100.0,
        volume: 1000,
      );
      final pair = createBearishEngulfingPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        volume: 2000, // above average
      );
      final allPrices = [...basePrices, pair.prev, pair.today];
      final data = StockData(
        symbol: 'TEST',
        prices: allPrices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternBearishEngulfing));
    });

    test('does not trigger in downtrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final now = DateTime.now();
      final basePrices = generateConstantPrices(
        days: 5,
        basePrice: 100.0,
        volume: 1000,
      );
      final pair = createBearishEngulfingPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        volume: 2000,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [...basePrices, pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger without sufficient volume', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final now = DateTime.now();
      // Use high base volume so today's volume isn't above average
      final basePrices = generateConstantPrices(
        days: 5,
        basePrice: 100.0,
        volume: 5000,
      );
      final pair = createBearishEngulfingPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        volume: 1000, // below average
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [...basePrices, pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [createTestPrice(date: DateTime.now(), close: 100.0)],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // HammerRule
  // ==========================================

  group('HammerRule', () {
    const rule = HammerRule();

    test('triggers in downtrend with hammer candle', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final hammer = createHammerCandle(date: DateTime.now(), close: 100.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [hammer],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternHammer));
      expect(result.score, equals(RuleScores.patternHammerBullish));
    });

    test('does not trigger in uptrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final hammer = createHammerCandle(date: DateTime.now(), close: 100.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [hammer],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with non-hammer candle', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      // Normal candle - not a hammer shape
      final normal = createTestPrice(
        date: DateTime.now(),
        open: 98.0,
        high: 102.0,
        low: 97.0,
        close: 101.0,
        volume: 1000,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [normal],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with empty prices', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });

    test(
      'does not trigger when hammer sits high in S/R band (near resistance)',
      () {
        // audit data #3 實例：2542 於 2026-07-17 close 在 S/R band 61.9% 處
        // （近壓力）卻觸發「低檔錘子線」+18。支撐 90、壓力 110（寬 20）、
        // close 102.4 → position 0.62 > 0.5，非低檔，應被位置守衛擋下。
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          supportLevel: 90.0,
          resistanceLevel: 110.0,
        );
        final hammer = createHammerCandle(date: DateTime.now(), close: 102.4);
        final data = StockData(
          symbol: 'TEST',
          prices: [hammer],
          dividends: DividendContext.noEvents,
        );

        expect(rule.evaluate(context, data), isNull);
      },
    );

    test(
      'triggers when hammer sits low in S/R band (near support) in range',
      () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          supportLevel: 90.0,
          resistanceLevel: 110.0,
        );
        // close 92 → position (92-90)/20 = 0.10，近支撐
        final hammer = createHammerCandle(date: DateTime.now(), close: 92.0);
        final data = StockData(
          symbol: 'TEST',
          prices: [hammer],
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);
        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.patternHammer));
      },
    );
  });

  // ==========================================
  // HangingManRule
  // ==========================================

  group('HangingManRule', () {
    const rule = HangingManRule();

    test('triggers in uptrend with hammer-shaped candle', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final hammer = createHammerCandle(date: DateTime.now(), close: 100.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [hammer],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternHangingMan));
      expect(result.score, equals(RuleScores.patternHammerBearish));
    });

    test('does not trigger in downtrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final hammer = createHammerCandle(date: DateTime.now(), close: 100.0);
      final data = StockData(
        symbol: 'TEST',
        prices: [hammer],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with non-hammer shape', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final normal = createTestPrice(
        date: DateTime.now(),
        open: 98.0,
        high: 102.0,
        low: 97.0,
        close: 101.0,
        volume: 1000,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [normal],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // GapUpRule
  // ==========================================

  group('GapUpRule', () {
    const rule = GapUpRule();

    test('triggers when gap exceeds threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      final pair = createGapUpPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        gapSize: 3.0,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternGapUp));
      expect(result.score, equals(RuleScores.patternGapUp));
    });

    test('does not trigger when gap is too small', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      final pair = createGapUpPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        gapSize: 0.01, // tiny gap
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when no gap (overlap)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      // Create overlapping candles (no gap)
      final prev = createTestPrice(
        date: now.subtract(const Duration(days: 1)),
        open: 99.0,
        high: 101.0,
        low: 98.0,
        close: 100.0,
      );
      final today = createTestPrice(
        date: now,
        open: 100.5,
        high: 102.0,
        low: 99.0, // overlaps with prev.high
        close: 101.5,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [prev, today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [createTestPrice(date: DateTime.now(), close: 100.0)],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // GapDownRule
  // ==========================================

  group('GapDownRule', () {
    const rule = GapDownRule();

    test('triggers when gap exceeds threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      final pair = createGapDownPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        gapSize: 3.0,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternGapDown));
      expect(result.score, equals(RuleScores.patternGapDown));
    });

    test('does not trigger when gap is too small', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      final pair = createGapDownPair(
        prevDate: now.subtract(const Duration(days: 1)),
        todayDate: now,
        gapSize: 0.01,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [pair.prev, pair.today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when no gap (overlap)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final now = DateTime.now();
      final prev = createTestPrice(
        date: now.subtract(const Duration(days: 1)),
        open: 101.0,
        high: 102.0,
        low: 99.0,
        close: 100.0,
      );
      final today = createTestPrice(
        date: now,
        open: 99.5,
        high: 100.0, // overlaps with prev.low
        low: 97.0,
        close: 98.0,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [prev, today],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [createTestPrice(date: DateTime.now(), close: 100.0)],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // MorningStarRule
  // ==========================================

  group('MorningStarRule', () {
    const rule = MorningStarRule();

    test('triggers in downtrend with valid morning star pattern', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final pattern = createMorningStarPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternMorningStar));
      expect(result.score, equals(RuleScores.patternMorningStar));
    });

    test('does not trigger in uptrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final pattern = createMorningStarPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with invalid pattern (C2 body too large)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final now = DateTime.now();
      // C2 has a large body (not a star)
      final c1 = createTestPrice(
        date: now.subtract(const Duration(days: 2)),
        open: 105.0,
        high: 106.0,
        low: 99.0,
        close: 100.0,
      );
      final c2 = createTestPrice(
        date: now.subtract(const Duration(days: 1)),
        open: 96.0,
        high: 103.0,
        low: 95.0,
        close: 102.0, // large body, not a star
      );
      final c3 = createTestPrice(
        date: now,
        open: 101.0,
        high: 106.0,
        low: 100.0,
        close: 105.0,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [c1, c2, c3],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0),
          createTestPrice(
            date: DateTime.now().add(const Duration(days: 1)),
            close: 99.0,
          ),
        ],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // EveningStarRule
  // ==========================================

  group('EveningStarRule', () {
    const rule = EveningStarRule();

    test('triggers in uptrend with valid evening star pattern', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final pattern = createEveningStarPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternEveningStar));
      expect(result.score, equals(RuleScores.patternEveningStar));
    });

    test('does not trigger in downtrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final pattern = createEveningStarPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with invalid pattern', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final now = DateTime.now();
      // C1 is bearish (should be bullish for evening star)
      final c1 = createTestPrice(
        date: now.subtract(const Duration(days: 2)),
        open: 105.0,
        high: 106.0,
        low: 99.0,
        close: 100.0, // bearish
      );
      final c2 = createTestPrice(
        date: now.subtract(const Duration(days: 1)),
        open: 100.5,
        high: 101.0,
        low: 100.0,
        close: 100.3,
      );
      final c3 = createTestPrice(
        date: now,
        open: 100.0,
        high: 100.5,
        low: 95.0,
        close: 96.0,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [c1, c2, c3],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [createTestPrice(date: DateTime.now(), close: 100.0)],
        dividends: DividendContext.noEvents,
      );
      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // ThreeWhiteSoldiersRule
  // ==========================================

  group('ThreeWhiteSoldiersRule', () {
    const rule = ThreeWhiteSoldiersRule();

    test('triggers with 3 consecutive bullish candles (not in uptrend)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final pattern = createThreeWhiteSoldiersPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternThreeWhiteSoldiers));
      expect(result.score, equals(RuleScores.patternThreeWhiteSoldiers));
    });

    test('does not trigger in uptrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final pattern = createThreeWhiteSoldiersPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with tiny body candles (< 1% body ratio)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final now = DateTime.now();
      // 三根微小漲幅的 K 線：body/close < 1%
      final c1 = createTestPrice(
        date: now.subtract(const Duration(days: 2)),
        open: 100.0,
        high: 100.5,
        low: 99.5,
        close: 100.3, // body = 0.3%
      );
      final c2 = createTestPrice(
        date: now.subtract(const Duration(days: 1)),
        open: 100.3,
        high: 100.8,
        low: 100.0,
        close: 100.5, // body = 0.2%
      );
      final c3 = createTestPrice(
        date: now,
        open: 100.5,
        high: 101.0,
        low: 100.2,
        close: 100.8, // body = 0.3%
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [c1, c2, c3],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // ThreeBlackCrowsRule
  // ==========================================

  group('ThreeBlackCrowsRule', () {
    const rule = ThreeBlackCrowsRule();

    test('triggers with 3 consecutive bearish candles (not in downtrend)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final pattern = createThreeBlackCrowsPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.patternThreeBlackCrows));
      expect(result.score, equals(RuleScores.patternThreeBlackCrows));
    });

    test('does not trigger in downtrend', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.down,
      );
      final pattern = createThreeBlackCrowsPattern(
        startDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: pattern,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with tiny body candles (< 1% body ratio)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      );
      final now = DateTime.now();
      // 三根微小跌幅的 K 線：body/close < 1%
      final c1 = createTestPrice(
        date: now.subtract(const Duration(days: 2)),
        open: 100.3,
        high: 100.5,
        low: 99.8,
        close: 100.0, // body = 0.3%
      );
      final c2 = createTestPrice(
        date: now.subtract(const Duration(days: 1)),
        open: 100.0,
        high: 100.3,
        low: 99.5,
        close: 99.8, // body = 0.2%
      );
      final c3 = createTestPrice(
        date: now,
        open: 99.8,
        high: 100.0,
        low: 99.3,
        close: 99.5, // body = 0.3%
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [c1, c2, c3],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });
}

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

/// 從 2025-01-01 起逐日一根，高低為收盤 ±2%
List<DailyPriceEntry> _daily(List<double> closes) =>
    generatePriceHistoryFromList(
      prices: closes,
      startDate: DateTime(2025, 1, 1),
    );

/// 第 [i] 根的日期
DateTime _day(int i) => DateTime(2025, 1, 1).add(Duration(days: i));

List<double> _flat(int n, double value) => List.filled(n, value);

/// 第 200 根除息（前收 100 → 參考價 90，因子 0.9）的 260 根：第 50 根是原始
/// 高點 104（高 106.08），還原後只剩 95.47；第 230 根的 97（高 98.94）才是
/// 還原後的高點。今天收 99：原始差 6.7% 不觸發，還原後創新高
List<double> _adjustOnlyHighCloses() =>
    [..._flat(200, 100), ..._flat(59, 95), 99.0]
      ..[50] = 104
      ..[230] = 97;

final _exAt200 = DividendPriceEvent(
  exDate: _day(200),
  closeBefore: 100,
  referencePrice: 90,
);

AnalysisContext _ctx() =>
    AnalysisContext(evaluationTime: _day(259), trendState: TrendState.range);

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(_ctx(), data);

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(_ctx(), data);

      expect(result, isNotNull);
      expect(result!.evidence!['isNewHigh'], isFalse);
    });

    test('does not trigger when close is far from 52-week high', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 90.0, volume: 1000),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger with insufficient data (< 250 days)', () {
      final data = StockData(
        symbol: 'TEST',
        prices: generateConstantPrices(days: 100, basePrice: 100.0),
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger when close is null', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(createTestPrice(date: DateTime.now()));
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('🚨 還原後才創新高：極值以還原後價格判斷，evidence 保留原始極值與兩者差', () {
      final prices = _daily(_adjustOnlyHighCloses());

      expect(
        rule.evaluate(
          _ctx(),
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        ),
        isNull,
        reason: '前提：沒有除權息事件時，原始高點 106.08 讓今天的 99 差太遠',
      );

      final result = rule.evaluate(
        _ctx(),
        StockData(
          symbol: 'T',
          prices: prices,
          dividends: DividendContext.complete([_exAt200]),
        ),
      );

      expect(result, isNotNull);
      expect(result!.description, '創 52 週新高');
      final e = result.evidence!;
      expect(e['week52High'], closeTo(106.08, 1e-9), reason: '原始極值（第 50 根）');
      expect(e['adjustedHigh'], closeTo(98.94, 1e-9), reason: '還原後極值（第 230 根）');
      expect(e['dividendAdjustment'], closeTo(7.14, 1e-9));
      expect(e['isNewHigh'], isTrue);
    });

    test('🚨 股利資料不完整：原始價格會觸發也不觸發', () {
      final prices = _daily([..._flat(259, 100), 103.0]);

      expect(
        rule.evaluate(
          _ctx(),
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        ),
        isNotNull,
        reason: '前提：資料完整時照原始價格會觸發',
      );
      expect(
        rule.evaluate(
          _ctx(),
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: const DividendContext.incomplete(),
          ),
        ),
        isNull,
      );
    });

    test('🚨 還原後仍有水位斷點（減資、分割等不在除權除息列表）→ 不觸發', () {
      // 第 200 根起從 50 跳到 100；今天 101.5 在原始高點 102 的 1% 內
      final data = StockData(
        symbol: 'T',
        prices: _daily([..._flat(200, 50), ..._flat(59, 100), 101.5]),
        dividends: DividendContext.noEvents,
      );

      expect(week52AdjustedPrices(data).block, Week52Block.discontinuity);
      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('🚨 除權息日在今天之後的事件不套用（不得前視）', () {
      final data = StockData(
        symbol: 'T',
        prices: _daily(_adjustOnlyHighCloses()),
        dividends: DividendContext.complete([
          DividendPriceEvent(
            exDate: _day(260),
            closeBefore: 100,
            referencePrice: 90,
          ),
        ]),
      );

      expect(rule.evaluate(_ctx(), data), isNull);
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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(_ctx(), data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52Low));
      expect(result.score, equals(RuleScores.week52Low));
    });

    test('does not trigger when close is far from 52-week low', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 200.0, volume: 1000),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger when MA filter not confirmed (close >= MA20)', () {
      // 持平 100：收盤＝MA20，未確認空頭
      final data = StockData(
        symbol: 'TEST',
        prices: generateConstantPrices(days: 250, basePrice: 100.0),
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final data = StockData(
        symbol: 'TEST',
        prices: generateConstantPrices(days: 100, basePrice: 100.0),
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('🚨 均線用還原後收盤：除權息跳空造成的原始空頭排列不算數', () {
      // 第 250 根除息（因子 0.9），之後持平 90。原始 MA20＝95、MA60≈98.3，
      // 收盤 90 < MA20 < MA60 看似空頭；還原後整段持平 90，收盤不低於 MA20
      final prices = _daily([..._flat(250, 100), ..._flat(10, 90)]);
      final context = AnalysisContext(
        evaluationTime: _day(259),
        trendState: TrendState.down,
        indicators: indicatorsFromPrices(prices),
      );
      expect(
        context.indicators!.ma20! < context.indicators!.ma60!,
        isTrue,
        reason: '前提：原始均線呈空頭排列',
      );

      final data = StockData(
        symbol: 'T',
        prices: prices,
        dividends: DividendContext.complete([
          DividendPriceEvent(
            exDate: _day(250),
            closeBefore: 100,
            referencePrice: 90,
          ),
        ]),
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // week52AdjustedPrices（規則與每輪觀測共用）
  // ==========================================
  group('week52AdjustedPrices', () {
    test('不足 250 根：不評估、不計入觀測', () {
      final r = week52AdjustedPrices(
        StockData(
          symbol: 'T',
          prices: _daily(_flat(249, 100)),
          dividends: const DividendContext.incomplete(),
        ),
      );

      expect((r.adjusted, r.block), (null, null));
    });

    test('不完整 → incomplete', () {
      final r = week52AdjustedPrices(
        StockData(
          symbol: 'T',
          prices: _daily(_flat(260, 100)),
          dividends: const DividendContext.incomplete(),
        ),
      );

      expect((r.adjusted, r.block), (null, Week52Block.incomplete));
    });

    test('除權息解釋得了的跳空可用（截止日＝最後一根）；解釋不了的是斷點', () {
      final prices = _daily([..._flat(200, 100), ..._flat(60, 80)]); // −20%

      expect(
        week52AdjustedPrices(
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        ).block,
        Week52Block.discontinuity,
      );

      final r = week52AdjustedPrices(
        StockData(
          symbol: 'T',
          prices: prices,
          dividends: DividendContext.complete([
            DividendPriceEvent(
              exDate: _day(200),
              closeBefore: 100,
              referencePrice: 80,
            ),
          ]),
        ),
      );
      expect(r.block, isNull);
      expect(r.adjusted, hasLength(260));
      expect(r.adjusted!.first.close, closeTo(80, 1e-9));
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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with flat prices (no MA separation)', () {
      final prices = generateConstantPrices(days: 70, basePrice: 100.0);
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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when indicators are null', () {
      final prices = generateConstantPrices(days: 10, basePrice: 100.0);
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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

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
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when indicators are null', () {
      final prices = generateConstantPrices(days: 10, basePrice: 100.0);
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

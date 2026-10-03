import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/extended_market_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';

void main() {
  // ==========================================
  // ForeignShareholdingIncreasingRule
  // ==========================================
  group('ForeignShareholdingIncreasingRule', () {
    const rule = ForeignShareholdingIncreasingRule();

    test('triggers when foreign shareholding increases >= threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          foreignSharesRatio: 30.0,
          foreignSharesRatioChange: 0.8, // >= 0.5
        ),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.foreignShareholdingIncreasing));
      expect(result.score, equals(RuleScores.foreignShareholdingIncreasing));
    });

    test('does not trigger when change is below threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          foreignSharesRatio: 30.0,
          foreignSharesRatioChange: 0.3, // < 0.5
        ),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when marketData is null', () {
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
  });

  // ==========================================
  // ForeignShareholdingDecreasingRule
  // ==========================================
  group('ForeignShareholdingDecreasingRule', () {
    const rule = ForeignShareholdingDecreasingRule();

    test('triggers when foreign shareholding decreases >= threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          foreignSharesRatio: 25.0,
          foreignSharesRatioChange: -0.7, // <= -0.5
        ),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.foreignShareholdingDecreasing));
      expect(result.score, equals(RuleScores.foreignShareholdingDecreasing));
    });

    test('does not trigger when decrease is below threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          foreignSharesRatio: 25.0,
          foreignSharesRatioChange: -0.2, // > -0.5
        ),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when change is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(foreignSharesRatio: 25.0),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // DayTradingHighRule
  // ==========================================
  group('DayTradingHighRule', () {
    const rule = DayTradingHighRule();

    test('triggers when day trading ratio is in high range', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          dayTradingRatio: 60.0,
        ), // 50-70 range
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(
            date: DateTime.now(),
            close: 100.0,
            volume: 15000000, // > 10,000,000 (萬張)
          ),
        ],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.dayTradingHigh));
      expect(result.score, equals(RuleScores.dayTradingHigh));
    });

    // 2026-07-18 實證修正：高當沖不得再貢獻「偏多」分數。
    // 自有資料（production DB 32,097 筆 / 29 個交易日）1D 前瞻報酬：
    // 50-70% bucket excess −0.495%、勝率 37.4% —— 全表最差的一格。
    // 舊 +12 來自 2026-07-18 修掉的 lookahead bias（進場價用訊號日 close
    // 而非隔日 open）：舊慣例下 5D excess +0.120，改正後翻為 −0.229。
    // 規則仍 fire（證據 chip / 風險徽章保留），但分數不得為正。
    test('高當沖不再貢獻偏多分數（實證：50-70% 為 1D 最差 bucket）', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          dayTradingRatio: 55.0,
        ), // 50-70 range
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 15000000),
        ],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      // 規則仍需 fire —— 保留「這檔當沖很高」的資訊價值
      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.dayTradingHigh));
      // 但不得再是正分（偏多）
      expect(result.score, lessThanOrEqualTo(0), reason: '高當沖是投機/波動旗標，非偏多訊號');
      expect(RuleScores.dayTradingHigh, lessThanOrEqualTo(0));
    });

    test('does not trigger when ratio is below high threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 45.0), // < 50
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 15000000),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when ratio is at extreme level', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 75.0), // >= 70
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 15000000),
        ],
        dividends: DividendContext.noEvents,
      );

      // DayTradingHighRule only triggers for [50, 70), extreme is handled by DayTradingExtremeRule
      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when volume is too low', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 60.0),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(
            date: DateTime.now(),
            close: 100.0,
            volume: 5000000, // < 10,000,000 (萬張)
          ),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // DayTradingExtremeRule
  // ==========================================
  group('DayTradingExtremeRule', () {
    const rule = DayTradingExtremeRule();

    test('triggers when day trading ratio is extreme', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 75.0), // >= 70
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(
            date: DateTime.now(),
            close: 100.0,
            volume: 35000000, // > 30,000,000 (3 萬張)
          ),
        ],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.dayTradingExtreme));
      expect(result.score, equals(RuleScores.dayTradingExtreme));
    });

    test('does not trigger below extreme threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 65.0), // < 70
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 35000000),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when volume is too low', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 75.0), // >= 70
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(
            date: DateTime.now(),
            close: 100.0,
            volume: 20000000, // < 30,000,000 (3 萬張)
          ),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // ConcentrationHighRule
  // ==========================================
  group('ConcentrationHighRule', () {
    const rule = ConcentrationHighRule();

    test('triggers when concentration ratio >= threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(concentrationRatio: 75.0), // >= 60
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.concentrationHigh));
      expect(result.score, equals(RuleScores.concentrationHigh));
    });

    test('does not trigger below threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(concentrationRatio: 55.0), // < 60
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when concentration ratio is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('triggers at exact threshold (60%)', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          concentrationRatio:
              InstitutionalParams.concentrationHighThreshold, // 60.0
        ),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.concentrationHigh));
    });
  });

  // ==========================================
  // 邊界/null 測試補充
  // ==========================================

  group('DayTradingHighRule Edge Cases', () {
    const rule = DayTradingHighRule();

    test('returns null when dayTradingRatio is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: null),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 15000000),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('returns null when prices are empty', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 60.0),
      );
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('triggers at exact 50% threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          dayTradingRatio: InstitutionalParams.dayTradingHighThreshold, // 50.0
        ),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 15000000),
        ],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.dayTradingHigh));
    });

    test('returns null when volume is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: 60.0),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: null),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  group('DayTradingExtremeRule Edge Cases', () {
    const rule = DayTradingExtremeRule();

    test('returns null when dayTradingRatio is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(dayTradingRatio: null),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 35000000),
        ],
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('triggers at exact 70% threshold', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        marketData: const MarketDataContext(
          dayTradingRatio:
              InstitutionalParams.dayTradingExtremeThreshold, // 70.0
        ),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [
          createTestPrice(date: DateTime.now(), close: 100.0, volume: 35000000),
        ],
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.dayTradingExtreme));
    });
  });
}

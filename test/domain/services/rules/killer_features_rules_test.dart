import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/insider_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/rules/warning_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';

void main() {
  group('Insider Rules', () {
    group('InsiderSellingStreakRule', () {
      const rule = InsiderSellingStreakRule();

      test('triggers when selling streak >= 3 months', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              hasSellingStreak: true,
              sellingStreakMonths: 3,
              insiderRatio: 25.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.insiderSellingStreak));
        expect(result.score, equals(RuleScores.insiderSellingStreak));
      });

      test('does not trigger when selling streak < 3 months', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              hasSellingStreak: true,
              sellingStreakMonths: 2,
              insiderRatio: 25.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });

      test('does not trigger when no selling streak', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              hasSellingStreak: false,
              sellingStreakMonths: 0,
              insiderRatio: 25.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });

    group('InsiderSignificantBuyingRule', () {
      const rule = InsiderSignificantBuyingRule();

      test('triggers when buying change >= 5%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              hasSignificantBuying: true,
              buyingChange: 6.0,
              insiderRatio: 30.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.insiderSignificantBuying));
        expect(result.score, equals(RuleScores.insiderSignificantBuying));
      });

      test('does not trigger when buying change < 5%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              hasSignificantBuying: true,
              buyingChange: 3.0,
              insiderRatio: 23.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });

      test('does not trigger when buyingChange is null', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              hasSignificantBuying: true,
              buyingChange: null,
              insiderRatio: 25.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });

    group('HighPledgeRatioRule', () {
      const rule = HighPledgeRatioRule();

      test('triggers when pledge ratio >= 70%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              pledgeRatio: 75.0,
              insiderRatio: 20.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.highPledgeRatio));
        expect(result.score, equals(RuleScores.highPledgeRatio));
      });

      test('does not trigger when pledge ratio < 70%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              pledgeRatio: 40.0,
              insiderRatio: 25.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });

      test('does not trigger when pledgeRatio is null', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            insiderData: InsiderDataContext(
              pledgeRatio: null,
              insiderRatio: 25.0,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });
  });

  group('Warning Rules', () {
    group('TradingWarningAttentionRule', () {
      const rule = TradingWarningAttentionRule();

      test('triggers when isAttention is true', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            warningData: WarningDataContext(
              isAttention: true,
              isDisposal: false,
              reasonDescription: '成交量異常',
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.tradingWarningAttention));
        expect(result.score, equals(RuleScores.tradingWarningAttention));
      });

      test('does not trigger when isDisposal is true', () {
        // DISPOSAL 優先於 ATTENTION
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            warningData: WarningDataContext(
              isAttention: true,
              isDisposal: true,
              reasonDescription: '處置股票',
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });

    group('TradingWarningDisposalRule', () {
      const rule = TradingWarningDisposalRule();

      test('triggers when isDisposal is true', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            warningData: WarningDataContext(
              isAttention: false,
              isDisposal: true,
              disposalMeasures: '分盤交易',
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.tradingWarningDisposal));
        expect(result.score, equals(RuleScores.tradingWarningDisposal));
      });

      test('does not trigger when isDisposal is false', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            warningData: WarningDataContext(
              isAttention: true,
              isDisposal: false,
            ),
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });

      // ==========================================
      // 格式化分支補測
      // ==========================================

      test('description includes disposalMeasures when present', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            warningData: WarningDataContext(
              isDisposal: true,
              disposalMeasures: '分盤交易',
            ),
          ),
        );
        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.description, contains('分盤交易'));
      });

      test('description includes disposalEndDate when present', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: MarketDataContext(
            warningData: WarningDataContext(
              isDisposal: true,
              disposalEndDate: DateTime(2026, 3, 15),
            ),
          ),
        );
        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.description, contains('處置期限至'));
        expect(result.description, contains('2026'));
      });

      test('description includes both measures and endDate', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: MarketDataContext(
            warningData: WarningDataContext(
              isDisposal: true,
              disposalMeasures: '分盤交易',
              disposalEndDate: DateTime(2026, 3, 15),
            ),
          ),
        );
        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.description, contains('分盤交易'));
        expect(result.description, contains('處置期限至'));
      });

      test('description is basic when both measures and endDate are null', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            warningData: WarningDataContext(isDisposal: true),
          ),
        );
        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.description, equals('被列入處置股票'));
      });

      test('returns null when warningData is null', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
        );
        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });
  });

  group('Foreign Rules', () {
    group('ForeignConcentrationWarningRule', () {
      const rule = ForeignConcentrationWarningRule();

      test('triggers when foreign ratio >= 60%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(foreignSharesRatio: 65.0),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.foreignConcentrationWarning));
      });

      test('does not trigger when foreign ratio < 60%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(foreignSharesRatio: 50.0),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });

    group('ForeignExodusRule', () {
      const rule = ForeignExodusRule();

      test('triggers when foreign ratio change <= -2%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            foreignSharesRatio: 40.0,
            foreignSharesRatioChange: -2.5,
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.foreignExodus));
        expect(result.score, equals(RuleScores.foreignExodus));
      });

      test('does not trigger when foreign ratio change > -2%', () {
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          marketData: const MarketDataContext(
            foreignSharesRatio: 40.0,
            foreignSharesRatioChange: -1.0,
          ),
        );

        final prices = generateFlatPrices(days: 20, basePrice: 100.0);
        final data = StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNull);
      });
    });
  });
}

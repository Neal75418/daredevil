import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/fundamental_rules.dart';
import 'package:daredevil/domain/services/rules/fundamental_scan_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';
import '../../../helpers/stock_data_builders.dart';

/// 建構站上 MA 且長紅的價格資料
///
/// 60 天盤整在 [basePrice]，最後一天收 [basePrice * 1.05]（+5% > 1.5%）
/// MA60 ≈ basePrice，close > MA60 ✓，changePct > 1.5% ✓
List<DailyPriceEntry> _generatePricesAboveMA({
  required int maPeriod,
  double basePrice = 100.0,
  double lastDayChangePct = 0.05,
}) {
  final days = maPeriod + 5;
  final now = DateTime.now();
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

/// 建構低於 MA 的價格資料（close < MA）
List<DailyPriceEntry> _generatePricesBelowMA({
  required int maPeriod,
  double basePrice = 100.0,
}) {
  final days = maPeriod + 5;
  final now = DateTime.now();
  return List.generate(days, (i) {
    final isLast = i == days - 1;
    // MA 約 100，最後一天 close = 95 < MA
    final close = isLast ? basePrice * 0.95 : basePrice;
    return createTestPrice(
      date: now.subtract(Duration(days: days - i - 1)),
      close: close,
      volume: 1000,
    );
  });
}

void main() {
  // ==========================================
  // RevenueYoYSurgeRule
  // ==========================================
  group('RevenueYoYSurgeRule', () {
    const rule = RevenueYoYSurgeRule();

    test('triggers when yoyGrowth >= threshold with MA60 confirmation', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      final revenue = createTestMonthlyRevenue(
        yoyGrowth: 55.0, // >= 30.0 (revenueYoySurgeThreshold)
      );
      final data = createTestStockData(prices: prices, latestRevenue: revenue);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.revenueYoySurge));
      expect(result.score, equals(RuleScores.revenueYoySurge));
      expect(result.evidence!['yoyGrowth'], equals(55.0));
    });

    test('does not trigger when yoyGrowth is below threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      final revenue = createTestMonthlyRevenue(
        yoyGrowth: 20.0, // < 30.0
      );
      final data = createTestStockData(prices: prices, latestRevenue: revenue);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when price is below MA60', () {
      final prices = _generatePricesBelowMA(maPeriod: 60);
      final revenue = createTestMonthlyRevenue(yoyGrowth: 55.0);
      final data = createTestStockData(prices: prices, latestRevenue: revenue);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when revenue is null', () {
      final prices = _generatePricesAboveMA(maPeriod: 60);
      final data = createTestStockData(prices: prices);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // RevenueYoYDeclineRule
  // ==========================================
  group('RevenueYoYDeclineRule', () {
    const rule = RevenueYoYDeclineRule();

    test('triggers when yoyGrowth <= -20%', () {
      final revenue = createTestMonthlyRevenue(yoyGrowth: -25.0);
      final data = createTestStockData(latestRevenue: revenue);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.revenueYoyDecline));
      expect(result.score, equals(RuleScores.revenueYoyDecline));
    });

    test('does not trigger when decline is insufficient', () {
      final revenue = createTestMonthlyRevenue(yoyGrowth: -10.0);
      final data = createTestStockData(latestRevenue: revenue);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when revenue is null', () {
      final data = createTestStockData();
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // RevenueMomGrowthRule
  // ==========================================
  group('RevenueMomGrowthRule', () {
    const rule = RevenueMomGrowthRule();

    test('triggers with consecutive mom growth and MA20 confirmation', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      // revenueMomConsecutiveMonths = 1, so 1 month of momGrowth >= 10 suffices
      final revenueHistory = generateRevenueHistory(
        months: 3,
        momGrowthValues: [15.0, 12.0, 8.0],
      );
      final data = createTestStockData(
        prices: prices,
        revenueHistory: revenueHistory,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.revenueMomGrowth));
      expect(result.score, equals(RuleScores.revenueMomGrowth));
    });

    test('does not trigger when mom growth is below threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final revenueHistory = generateRevenueHistory(
        months: 3,
        momGrowthValues: [5.0, 3.0, 2.0], // all < 10.0
      );
      final data = createTestStockData(
        prices: prices,
        revenueHistory: revenueHistory,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when price is below MA20', () {
      final prices = _generatePricesBelowMA(maPeriod: 20);
      final revenueHistory = generateRevenueHistory(
        months: 3,
        momGrowthValues: [15.0, 12.0, 8.0],
      );
      final data = createTestStockData(
        prices: prices,
        revenueHistory: revenueHistory,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient history', () {
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
  // HighDividendYieldRule
  // ==========================================
  group('HighDividendYieldRule', () {
    const rule = HighDividendYieldRule();

    test('triggers when dividend yield is in valid range', () {
      final valuation = createTestValuation(
        dividendYield: 7.0, // 5.5 <= 7.0 <= 20
        date: DateTime(2025, 5, 30), // evaluationTime 前 2 天=真的新鮮
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.highDividendYield));
      expect(result.score, equals(RuleScores.highDividendYield));
    });

    test('does not trigger when yield is below threshold', () {
      final valuation = createTestValuation(
        dividendYield: 3.0, // < 5.5
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when yield is abnormally high', () {
      final valuation = createTestValuation(
        dividendYield: 25.0, // > 20.0 (scanDividendYieldMax)
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when data is stale', () {
      final now = DateTime.now();
      final valuation = createTestValuation(
        dividendYield: 7.0,
        date: now.subtract(
          const Duration(days: 10),
        ), // > 7 days (valuationMaxStaleDays)
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: now,
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when valuation is null', () {
      final data = createTestStockData();
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // PEUndervaluedRule
  // ==========================================
  group('PEUndervaluedRule', () {
    const rule = PEUndervaluedRule();

    test('triggers when PE is low with MA20 confirmation', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final valuation = createTestValuation(
        per: 8.0, // 0 < 8 <= 10
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(
        prices: prices,
        latestValuation: valuation,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.peUndervalued));
      expect(result.score, equals(RuleScores.peUndervalued));
    });

    test('does not trigger when PE is above threshold', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final valuation = createTestValuation(
        per: 15.0,
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(
        prices: prices,
        latestValuation: valuation,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when PE is negative', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final valuation = createTestValuation(
        per: -5.0,
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(
        prices: prices,
        latestValuation: valuation,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // PEOvervaluedRule
  // ==========================================
  group('PEOvervaluedRule', () {
    const rule = PEOvervaluedRule();

    test('triggers when PE >= 100 and RSI is overbought', () {
      // Need 14+ days for RSI calculation + RSI > 75
      // Build continuous uptrend to push RSI high
      final now = DateTime.now();
      final prices = List.generate(30, (i) {
        return createTestPrice(
          date: now.subtract(Duration(days: 29 - i)),
          close: 100.0 + (i * 2.0), // Strong uptrend pushes RSI high
          volume: 1000,
        );
      });
      final valuation = createTestValuation(
        per: 120.0, // >= 100
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(
        prices: prices,
        latestValuation: valuation,
      );
      // 提供 RSI > 75（過熱）讓規則觸發
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(rsi: 80),
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.peOvervalued));
      expect(result.score, equals(RuleScores.peOvervalued));
    });

    test('does not trigger when PE is below threshold', () {
      final now = DateTime.now();
      final prices = List.generate(30, (i) {
        return createTestPrice(
          date: now.subtract(Duration(days: 29 - i)),
          close: 100.0 + (i * 2.0),
          volume: 1000,
        );
      });
      final valuation = createTestValuation(
        per: 50.0,
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(
        prices: prices,
        latestValuation: valuation,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when RSI is not overbought', () {
      // Downtrend prices → RSI < 75
      final prices = generateDowntrendPrices(days: 30);
      final valuation = createTestValuation(
        per: 120.0,
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(
        prices: prices,
        latestValuation: valuation,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // PBRUndervaluedRule
  // ==========================================
  group('PBRUndervaluedRule', () {
    const rule = PBRUndervaluedRule();

    test('triggers when PBR is low and positive', () {
      final valuation = createTestValuation(
        pbr: 0.6, // 0 < 0.6 <= 0.8
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.pbrUndervalued));
      expect(result.score, equals(RuleScores.pbrUndervalued));
    });

    test('does not trigger when PBR is above threshold', () {
      final valuation = createTestValuation(
        pbr: 1.5,
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when PBR is zero or negative', () {
      final valuation = createTestValuation(
        pbr: 0.0,
        date: DateTime(2025, 5, 30),
      );
      final data = createTestStockData(latestValuation: valuation);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // RevenueNewHighRule
  // ==========================================
  group('RevenueNewHighRule', () {
    const rule = RevenueNewHighRule();

    test(
      'triggers when current revenue exceeds historical max with MA20 confirmation',
      () {
        final prices = _generatePricesAboveMA(maPeriod: 20);
        final revenue = createTestMonthlyRevenue(
          revenue: 1500000, // current: 150 億
          revenueMonth: 3,
        );
        final data = createTestStockData(
          prices: prices,
          latestRevenue: revenue,
          maxHistoricalRevenue: 1200000, // historical max: 120 億
        );
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
          indicators: indicatorsFromPrices(prices),
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.type, equals(ReasonType.revenueNewHigh));
        expect(result.score, equals(RuleScores.revenueNewHigh));
        expect(result.evidence!['currentRevenue'], equals(1500000));
        expect(result.evidence!['maxHistoricalRevenue'], equals(1200000));
        expect(result.evidence!['surpassPct'], closeTo(25.0, 0.1));
      },
    );

    test('does not trigger when current revenue <= historical max', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final revenue = createTestMonthlyRevenue(revenue: 1000000);
      final data = createTestStockData(
        prices: prices,
        latestRevenue: revenue,
        maxHistoricalRevenue: 1200000, // max > current
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when price is below MA20', () {
      final prices = _generatePricesBelowMA(maPeriod: 20);
      final revenue = createTestMonthlyRevenue(revenue: 1500000);
      final data = createTestStockData(
        prices: prices,
        latestRevenue: revenue,
        maxHistoricalRevenue: 1200000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when maxHistoricalRevenue is null', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final revenue = createTestMonthlyRevenue(revenue: 1500000);
      final data = createTestStockData(
        prices: prices,
        latestRevenue: revenue,
        // maxHistoricalRevenue not set → null
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when latestRevenue is null', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final data = createTestStockData(
        prices: prices,
        maxHistoricalRevenue: 1200000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when maxHistoricalRevenue is zero', () {
      final prices = _generatePricesAboveMA(maPeriod: 20);
      final revenue = createTestMonthlyRevenue(revenue: 1500000);
      final data = createTestStockData(
        prices: prices,
        latestRevenue: revenue,
        maxHistoricalRevenue: 0,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicatorsFromPrices(prices),
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // NewsRule
  // ==========================================
  group('NewsRule', () {
    const rule = NewsRule();

    test('triggers with positive news keywords', () {
      final now = DateTime.now();
      final news = [
        NewsItemEntry(
          id: '1',
          url: 'https://example.com/1',
          title: '公司營收創新高，業績亮眼',
          source: 'Test',
          category: 'EARNINGS',
          publishedAt: now.subtract(const Duration(hours: 1)),
          fetchedAt: now,
        ),
      ];
      final data = createTestStockData(news: news);
      // evaluationTime 錨於同一個 now，避免與 publishedAt 產生負值 age。
      final context = AnalysisContext(
        evaluationTime: now,
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.newsRelated));
      expect((result.evidence!['sentiment'] as int) > 0, isTrue);
    });

    test('triggers with negative news keywords', () {
      final now = DateTime.now();
      final news = [
        NewsItemEntry(
          id: '1',
          url: 'https://example.com/1',
          title: '公司營收衰退，虧損擴大',
          source: 'Test',
          category: 'EARNINGS',
          publishedAt: now.subtract(const Duration(hours: 1)),
          fetchedAt: now,
        ),
      ];
      final data = createTestStockData(news: news);
      // evaluationTime 錨於同一個 now，避免與 publishedAt 產生負值 age。
      final context = AnalysisContext(
        evaluationTime: now,
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect((result!.evidence!['sentiment'] as int) < 0, isTrue);
    });

    test('negation prefix reverses positive keyword', () {
      final now = DateTime.now();
      final news = [
        NewsItemEntry(
          id: '1',
          url: 'https://example.com/1',
          title: '衰退擴產計畫暫緩',
          source: 'Test',
          category: 'COMPANY_EVENT',
          publishedAt: now.subtract(const Duration(hours: 1)),
          fetchedAt: now,
        ),
      ];
      final data = createTestStockData(news: news);
      // evaluationTime 錨於同一個 now，避免與 publishedAt 產生負值 age。
      final context = AnalysisContext(
        evaluationTime: now,
        trendState: TrendState.range,
      );

      final result = rule.evaluate(context, data);

      // '擴產' is positive keyword, but '衰退' prefix negates it → score = -1
      expect(result, isNotNull);
      expect((result!.evidence!['sentiment'] as int) < 0, isTrue);
    });

    test('does not trigger with stale news', () {
      final now = DateTime.now();
      final news = [
        NewsItemEntry(
          id: '1',
          url: 'https://example.com/1',
          title: '公司營收創新高',
          source: 'Test',
          category: 'EARNINGS',
          publishedAt: now.subtract(const Duration(hours: 200)), // > 120 hours
          fetchedAt: now,
        ),
      ];
      final data = createTestStockData(news: news);
      final context = AnalysisContext(
        evaluationTime: now,
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when news is null', () {
      final data = createTestStockData();
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });
}

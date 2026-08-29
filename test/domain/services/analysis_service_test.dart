import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/analysis/analysis_coordinator_service.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  late AnalysisService analysisService;
  late AnalysisCoordinatorService coordinator;

  setUp(() {
    analysisService = AnalysisService();
    coordinator = AnalysisCoordinatorService();
  });

  group('TrendDetectionService', () {
    test('detect uptrend when prices are rising', () {
      final prices = generateUptrendPrices(days: 25);

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.up);
    });

    test('detect downtrend when prices are falling', () {
      final prices = generateDowntrendPrices(days: 25);

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.down);
    });

    test('detect range when prices are flat', () {
      final prices = generateFlatPrices(days: 25, basePrice: 100.0);

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.range);
    });

    test('return range when not enough data', () {
      final prices = generateFlatPrices(days: 3, basePrice: 100.0);

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.range);
    });

    test('detect uptrend with explicit price increase', () {
      final now = DateTime.now();
      final prices = List.generate(25, (i) {
        final price = 100.0 + (i * 0.5); // 100 → 112
        return createTestPrice(
          date: now.subtract(Duration(days: 25 - i - 1)),
          close: price,
        );
      });

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.up);
    });

    test('detect downtrend with explicit price decrease', () {
      final now = DateTime.now();
      final prices = List.generate(25, (i) {
        final price = 112.0 - (i * 0.5); // 112 → 100
        return createTestPrice(
          date: now.subtract(Duration(days: 25 - i - 1)),
          close: price,
        );
      });

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.down);
    });

    test('return range when price change is minimal', () {
      final now = DateTime.now();
      final prices = List.generate(25, (i) {
        final price = 100.0 + (i * 0.02);
        return createTestPrice(
          date: now.subtract(Duration(days: 25 - i - 1)),
          close: price,
        );
      });

      final trend = coordinator.trendService.detectTrendState(prices);

      expect(trend, TrendState.range);
    });
  });

  group('SupportResistanceService', () {
    test('find support and resistance levels', () {
      final now = DateTime.now();
      final prices = <DailyPriceEntry>[];

      for (var i = 0; i < 60; i++) {
        final date = now.subtract(Duration(days: 60 - i - 1));
        double close;
        double high;
        double low;

        if (i < 20) {
          close = 100.0;
          high = 100.5;
          low = 99.5;
        } else if (i < 30) {
          final progress = (i - 20) / 10.0;
          close = 100.0 - 5.0 * (1 - (progress - 0.5).abs() * 2);
          high = close + 0.5;
          low = close - 0.5;
        } else if (i < 45) {
          final progress = (i - 30) / 15.0;
          close = 100.0 + 5.0 * (1 - (progress - 0.5).abs() * 2);
          high = close + 0.5;
          low = close - 0.5;
        } else {
          close = 100.0;
          high = 100.5;
          low = 99.5;
        }

        prices.add(
          DailyPriceEntry(
            symbol: 'TEST',
            date: date,
            open: close - 0.2,
            high: high,
            low: low,
            close: close,
            volume: 1000.0,
          ),
        );
      }

      final (support, resistance) = coordinator.srService.findSupportResistance(
        prices,
      );

      expect(support, isNotNull);
      expect(resistance, isNotNull);
      // 價格在 95~105 間擺盪，支撐/壓力應在合理範圍內
      expect(support!, greaterThan(90.0));
      expect(support, lessThan(105.0));
      expect(resistance!, greaterThan(95.0));
      expect(resistance, lessThan(110.0));
      expect(resistance > support, isTrue);
    });

    test('return nulls when not enough data', () {
      final prices = generateFlatPrices(days: 30, basePrice: 100.0);

      final (support, resistance) = coordinator.srService.findSupportResistance(
        prices,
      );

      expect(support, isNull);
      expect(resistance, isNull);
    });

    test('find 60-day high and low', () {
      final prices = generateSwingPrices(days: 70);

      final (rangeLow, rangeHigh) = coordinator.srService.findRange(prices);

      expect(rangeLow, isNotNull);
      expect(rangeHigh, isNotNull);
      expect(rangeHigh! > rangeLow!, isTrue);
    });

    test('return nulls when empty', () {
      final (rangeLow, rangeHigh) = coordinator.srService.findRange([]);

      expect(rangeLow, isNull);
      expect(rangeHigh, isNull);
    });
  });

  group('ReversalDetectionService', () {
    test('detect weak-to-strong on breakout above range top', () {
      // 45 天：近 20 天量能為前期 2x（通過 1.5x 量能確認），最後一天突破 rangeTop
      final now = DateTime.now();
      final pricesWithBreakout = List.generate(45, (i) {
        final isLast = i == 44;
        return createTestPrice(
          date: now.subtract(Duration(days: 45 - i - 1)),
          close: isLast ? 106.0 : 100.0,
          volume: i >= 25 ? 2000 : 1000,
        );
      });

      final reversal = coordinator.reversalService.detectReversalState(
        pricesWithBreakout,
        trendState: TrendState.down,
        rangeTop: 102.0,
      );

      expect(reversal, ReversalState.weakToStrong);
    });

    test('detect strong-to-weak on breakdown below support', () {
      final now = DateTime.now();
      final pricesWithBreakdown = List.generate(45, (i) {
        final isLast = i == 44;
        return createTestPrice(
          date: now.subtract(Duration(days: 45 - i - 1)),
          close: isLast ? 94.0 : 100.0,
          volume: i >= 25 ? 2000 : 1000,
        );
      });

      final reversal = coordinator.reversalService.detectReversalState(
        pricesWithBreakdown,
        trendState: TrendState.up,
        support: 98.0,
      );

      expect(reversal, ReversalState.strongToWeak);
    });

    test('return none when no reversal detected', () {
      final prices = generateFlatPrices(days: 25, basePrice: 100.0);

      final reversal = coordinator.reversalService.detectReversalState(
        prices,
        trendState: TrendState.range,
      );

      expect(reversal, ReversalState.none);
    });
  });

  group('AnalysisService', () {
    group('analyzeStock', () {
      test('return complete analysis result', () {
        final prices = generateSwingPrices(days: 30);

        final result = analysisService.analyzeStock(prices);

        expect(result, isNotNull);
        expect(result!.trendState, isNotNull);
        expect(result.reversalState, isNotNull);
      });

      test('return null when not enough data', () {
        final prices = generateFlatPrices(days: 3, basePrice: 100.0);

        final result = analysisService.analyzeStock(prices);

        expect(result, isNull);
      });

      test('🚨 恰好 swingWindow 根:不得回傳「未經計算的盤整」(稽核 M4)', () {
        // analyzeStock 的閘門是 `length >= swingWindow`,但它接著把資料
        // 截掉最後一根(避開前視偏差)才餵給 detectTrendState——而後者
        // 自己也要求 `>= swingWindow`。同一個常數、list 短一根,於是
        // 恰好 20 根的股票通過每一道閘門,最後拿到一個**沒算過**的 range。
        //
        // 那個值會落庫成 daily_analysis.trend_state 並渲染成「盤整」,
        // 把「資料不足」講成一個趨勢主張——而 stock_detail_header 的註解
        // 正好在論證這件事不可以發生。
        final justEnough = generateUptrendPrices(
          days: RuleParams.swingWindow + 1,
        );
        expect(
          analysisService.analyzeStock(justEnough)?.trendState,
          TrendState.up,
          reason: '多一根就足以計算,且必須真的算出上升趨勢(證明對照組有效)',
        );

        final oneShort = generateUptrendPrices(days: RuleParams.swingWindow);
        expect(
          analysisService.analyzeStock(oneShort),
          isNull,
          reason: '算不出來要回 null（由 skippedNoAnalysis 計數），不是假裝盤整',
        );
      });
    });

    group('buildContext', () {
      test('build context from analysis result', () {
        const result = AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 95.0,
          resistanceLevel: 105.0,
          rangeTop: 110.0,
          rangeBottom: 90.0,
        );

        final context = analysisService.buildContext(
          result,
          evaluationTime: DateTime(2025, 6, 1),
        );

        expect(context.trendState, TrendState.up);
        expect(context.supportLevel, 95.0);
        expect(context.resistanceLevel, 105.0);
        expect(context.rangeTop, 110.0);
        expect(context.rangeBottom, 90.0);
      });
    });
  });
}

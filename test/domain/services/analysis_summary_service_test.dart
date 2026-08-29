import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';

import '../../helpers/analysis_data_generators.dart';
import '../../helpers/price_data_generators.dart';

// Helper: check if overallParts contain a specific localization key
bool _overallContainsKey(SummaryData data, String key) =>
    data.overallParts.any((ls) => ls.key == key);

void main() {
  const service = AnalysisSummaryService();

  group('AnalysisSummaryService.generate', () {
    test('return neutral when no analysis and no reasons', () {
      final result = service.generate(
        analysis: null,
        reasons: [],
        latestPrice: null,
        priceChange: null,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.sentiment, SummarySentiment.neutral);
      expect(result.keySignals, isEmpty);
      expect(result.riskFactors, isEmpty);
      expect(result.hasConflict, isFalse);
      expect(result.confluenceCount, 0);
      expect(result.overallParts.first.key, 'summary.noSignals');
    });

    test('🚨 不得同時給出「價值投資」與「價值陷阱」(稽核 M9)', () {
      // 兩組匯流模式共用 `{PE_UNDERVALUED, PBR_UNDERVALUED}` 這個
      // signalGroup。detect() 呼叫兩次、消耗集各自獨立時，同一檔股票會拿到
      // 兩個互相矛盾的合成結論，而共用的 PE_UNDERVALUED 又被從多空兩份
      // 原始清單裡剝掉——使用者連底下那個訊號都看不到。
      //
      // 這條釘的是**呼叫順序的接線**：signal_confluence_test 只測得到
      // detect() 本身接不接受 alreadyConsumed，測不到這裡有沒有傳。
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'DOWN', score: 20),
        reasons: [
          createTestReason(reasonType: 'PE_UNDERVALUED', ruleScore: 10),
          createTestReason(
            reasonType: 'HIGH_DIVIDEND_YIELD',
            rank: 2,
            ruleScore: 8,
          ),
          createTestReason(
            reasonType: 'MA_ALIGNMENT_BEARISH',
            rank: 3,
            ruleScore: -15,
          ),
        ],
        latestPrice: null,
        priceChange: -1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      final texts = [
        ...result.keySignals.map((e) => e.key),
        ...result.riskFactors.map((e) => e.key),
        ...result.overallParts.map((e) => e.key),
      ];
      expect(
        texts,
        contains('summary.confluenceValueTrap'),
        reason: '前提:空方的價值陷阱必須成立(否則本測試什麼都沒驗)',
      );
      expect(
        texts,
        isNot(contains('summary.confluenceValueInvestment')),
        reason: '同一檔股票不得同時被判價值投資與價值陷阱',
      );
    });

    test('prepends market-regime context line when marketStage given', () {
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'UP', score: 70),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
        marketStage: MarketStage.bullish,
      );

      // 大盤位階行置頂、對應 key
      expect(result.overallParts.first.key, 'summary.marketBullish');
    });

    test('omits market line when marketStage null or insufficient', () {
      SummaryData gen(MarketStage? stage) => service.generate(
        analysis: createTestAnalysis(trendState: 'UP', score: 70),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
        marketStage: stage,
      );

      for (final r in [gen(null), gen(MarketStage.insufficient)]) {
        expect(_overallContainsKey(r, 'summary.marketBullish'), isFalse);
        expect(_overallContainsKey(r, 'summary.marketNeutral'), isFalse);
        expect(_overallContainsKey(r, 'summary.marketBearish'), isFalse);
      }
    });

    test('return strongBullish when ratio ≥ 0.75 and score ≥ 55', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'TECH_BREAKOUT', rank: 2, ruleScore: 20),
        createTestReason(
          reasonType: 'INSTITUTIONAL_BUY',
          rank: 3,
          ruleScore: 10,
        ),
      ];

      final analysis = createTestAnalysis(trendState: 'UP', score: 70);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 3.5,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // bullRatio = 1.0 ≥ 0.75, score = 70 ≥ 55 → strongBullish
      expect(result.sentiment, SummarySentiment.strongBullish);
    });

    test('return bullish when ratio ≥ 0.6 but below strong threshold', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(
          reasonType: 'INSTITUTIONAL_BUY',
          rank: 2,
          ruleScore: 10,
        ),
        createTestReason(reasonType: 'KD_DEATH_CROSS', rank: 3, ruleScore: -5),
      ];

      final analysis = createTestAnalysis(trendState: 'UP', score: 45);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 2.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // bullRatio = 30/35 ≈ 0.86 ≥ 0.75, but score = 45 < 55 → bullish (not strong)
      expect(result.sentiment, SummarySentiment.bullish);
    });

    test('return bearish when negative signals dominate', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_S2W', ruleScore: -30),
        createTestReason(reasonType: 'TECH_BREAKDOWN', rank: 2, ruleScore: -20),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BEARISH',
          rank: 3,
          ruleScore: -10,
        ),
      ];

      // score=10, not < 10 → bearish (not strongBearish)
      final analysis = createTestAnalysis(trendState: 'DOWN', score: 10);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: -5.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.sentiment, SummarySentiment.bearish);
    });

    test('return strongBearish when ratio ≤ 0.25 and score < 10', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_S2W', ruleScore: -30),
        createTestReason(reasonType: 'TECH_BREAKDOWN', rank: 2, ruleScore: -20),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BEARISH',
          rank: 3,
          ruleScore: -15,
        ),
      ];

      final analysis = createTestAnalysis(trendState: 'DOWN', score: 5);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: -7.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // bullRatio = 0.0 ≤ 0.25, score = 5 < 10 → strongBearish
      expect(result.sentiment, SummarySentiment.strongBearish);
    });
  });

  group('Weighted sentiment', () {
    test(
      'single high-weight positive should outweigh multiple small negatives',
      () {
        final reasons = [
          createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
          createTestReason(
            reasonType: 'DAY_TRADING_HIGH',
            rank: 2,
            ruleScore: -5,
            evidenceJson: '{"ratio": 30}',
          ),
          createTestReason(
            reasonType: 'KD_DEATH_CROSS',
            rank: 3,
            ruleScore: -5,
          ),
        ];

        final analysis = createTestAnalysis(score: 45);

        final result = service.generate(
          analysis: analysis,
          reasons: reasons,
          latestPrice: null,
          priceChange: 2.0,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.short,
        );

        // 35 positive vs 10 negative → bullRatio = 35/45 = 0.78 → bullish
        expect(result.sentiment, SummarySentiment.bullish);
      },
    );
  });

  group('Conflict detection', () {
    test('detect W2S + KD death cross conflict', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_DEATH_CROSS', rank: 2, ruleScore: -10),
      ];

      final analysis = createTestAnalysis(score: 40);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.hasConflict, isTrue);
    });

    test('detect breakout + bearish alignment conflict', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BEARISH',
          rank: 2,
          ruleScore: -10,
        ),
      ];

      final analysis = createTestAnalysis(score: 30);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 2.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.hasConflict, isTrue);
    });

    test('not flag conflict when no contradictory pairs', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 50),
        reasons: reasons,
        latestPrice: null,
        priceChange: 3.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.hasConflict, isFalse);
    });

    test('conflict should raise sentiment threshold toward neutral', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_DEATH_CROSS', rank: 2, ruleScore: -10),
      ];

      // 衝突時門檻提高：bullRatio 需 > 0.65 且 score >= 35
      final analysis = createTestAnalysis(score: 30);

      final result = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // bullRatio = 35/45 ≈ 0.78 > 0.65, 但 score = 30 < 35 → neutral
      expect(result.sentiment, SummarySentiment.neutral);
      expect(result.hasConflict, isTrue);
    });
  });

  group('Confidence calculation', () {
    test('return high confidence with many signals and data', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
        createTestReason(reasonType: 'TECH_BREAKOUT', rank: 3, ruleScore: 20),
        createTestReason(
          reasonType: 'INSTITUTIONAL_BUY',
          rank: 4,
          ruleScore: 10,
        ),
        createTestReason(reasonType: 'VOLUME_SPIKE', rank: 5, ruleScore: 15),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 70),
        reasons: reasons,
        latestPrice: null,
        priceChange: 5.0,
        institutionalHistory: [createTestInstitutional(foreignNet: 5000)],
        revenueHistory: [createTestRevenue(yoyGrowth: 25)],
        latestPER: createTestPER(per: 12),
        horizon: Horizon.short,
      );

      // 5 signals(+2) + confluences(≥1) + no conflict(+1) + 3 data sources(+3) ≥ 5
      expect(result.confidence, AnalysisConfidence.high);
      expect(result.confluenceCount, greaterThan(0));
    });

    test('return low confidence with few signals and no data', () {
      final reasons = [
        createTestReason(reasonType: 'PATTERN_DOJI', ruleScore: 5),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 25),
        reasons: reasons,
        latestPrice: null,
        priceChange: 0.5,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 1 signal(+0) + 0 confluences + no conflict(+1) + 0 data = 1 → low
      expect(result.confidence, AnalysisConfidence.low);
      expect(result.confluenceCount, 0);
    });

    test('return medium confidence with moderate data', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(reasonType: 'VOLUME_SPIKE', rank: 2, ruleScore: 15),
        createTestReason(
          reasonType: 'INSTITUTIONAL_BUY',
          rank: 3,
          ruleScore: 10,
        ),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 50),
        reasons: reasons,
        latestPrice: null,
        priceChange: 3.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 3 signals(+1) + confluence(≥1) + no conflict(+1) + 0 data = 3 → medium
      expect(result.confidence, AnalysisConfidence.medium);
    });
  });

  group('Fundamental bias in sentiment', () {
    test('strong revenue growth should boost positive sentiment', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 15),
        createTestReason(reasonType: 'KD_DEATH_CROSS', rank: 2, ruleScore: -10),
      ];

      // 有基本面：positiveWeight += 5 (yoy>30) + 5 (PE≤10) + 5 (yield≥5.5)
      final resultWith = service.generate(
        analysis: createTestAnalysis(score: 30),
        reasons: reasons,
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [createTestRevenue(yoyGrowth: 40)],
        latestPER: createTestPER(per: 8, dividendYield: 6.0),
        horizon: Horizon.short,
      );

      expect(resultWith.sentiment, SummarySentiment.bullish);
    });

    test('negative revenue should boost bearish weight', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKDOWN', ruleScore: -20),
        createTestReason(reasonType: 'PATTERN_HAMMER', rank: 2, ruleScore: 10),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'DOWN', score: 15),
        reasons: reasons,
        latestPrice: null,
        priceChange: -3.0,
        institutionalHistory: [],
        revenueHistory: [createTestRevenue(yoyGrowth: -25)],
        latestPER: null,
        horizon: Horizon.short,
      );

      // negativeWeight = 20 + 5(fundamental) = 25, positiveWeight = 10
      // bullRatio = 10/35 ≈ 0.29, score=15 < 20 → bearish
      expect(result.sentiment, SummarySentiment.bearish);
    });
  });

  group('Confluence integration in key signals / risk factors', () {
    test('confluence keys should appear first in keySignals', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
        createTestReason(
          reasonType: 'INSTITUTIONAL_BUY',
          rank: 3,
          ruleScore: 10,
        ),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 60),
        reasons: reasons,
        latestPrice: null,
        priceChange: 3.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.keySignals, isNotEmpty);
      expect(result.confluenceCount, greaterThan(0));
      // 匯流 key 在前面，未被消耗的訊號在後面
      expect(result.keySignals.first.key, startsWith('summary.confluence'));
      expect(result.keySignals.length, greaterThanOrEqualTo(2));
    });

    test('bearish confluence keys should appear in riskFactors', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_S2W', ruleScore: -30),
        createTestReason(reasonType: 'KD_DEATH_CROSS', rank: 2, ruleScore: -10),
        createTestReason(
          reasonType: 'INSTITUTIONAL_SELL',
          rank: 3,
          ruleScore: -10,
        ),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'DOWN', score: 10),
        reasons: reasons,
        latestPrice: null,
        priceChange: -4.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.riskFactors, isNotEmpty);
      expect(result.riskFactors.length, greaterThanOrEqualTo(2));
    });

    test('consumed signals should not repeat in remaining list', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 60),
        reasons: reasons,
        latestPrice: null,
        priceChange: 3.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 匯流消耗了 W2S 和 KD_GOLDEN_CROSS，
      // 所以 keySignals 應只有匯流句，不重複列出個別句
      expect(result.keySignals.length, lessThanOrEqualTo(5));
    });
  });

  group('Supporting data', () {
    test('include institutional flow data', () {
      final result = service.generate(
        analysis: createTestAnalysis(),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: null,
        priceChange: 2.0,
        institutionalHistory: [
          createTestInstitutional(
            foreignNet: 5000000,
            investmentTrustNet: 2000000,
          ),
        ],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(result.supportingData, isNotEmpty);
      expect(result.supportingData.first.key, 'summary.institutionalFlow');
    });

    test('use latest entry (last) not oldest (first) for flow data', () {
      final now = DateTime.now();
      final result = service.generate(
        analysis: createTestAnalysis(),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: null,
        priceChange: 2.0,
        institutionalHistory: [
          // oldest entry (index 0) — ascending order
          createTestInstitutional(
            date: now.subtract(const Duration(days: 2)),
            foreignNet: -9000000,
            investmentTrustNet: -3000000,
          ),
          createTestInstitutional(
            date: now.subtract(const Duration(days: 1)),
            foreignNet: -5000000,
            investmentTrustNet: -2000000,
          ),
          // latest entry (last) — should be used for flow display
          createTestInstitutional(
            date: now,
            foreignNet: 8000000,
            investmentTrustNet: 3000000,
          ),
        ],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 法人動向應顯示最新一天（買超），不是最舊的（賣超）
      final flowEntry = result.supportingData
          .where((ls) => ls.key == 'summary.institutionalFlow')
          .first;
      // nestedArgs['foreign'] 應為 netBuy（正數 → buy lots）
      expect(flowEntry.nestedArgs['foreign']?.key, 'summary.netBuy');
    });

    test('detect consecutive buy trend when ≥ 3 days', () {
      final now = DateTime.now();
      final result = service.generate(
        analysis: createTestAnalysis(),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: null,
        priceChange: 2.0,
        institutionalHistory: [
          for (var i = 4; i >= 0; i--)
            createTestInstitutional(
              date: now.subtract(Duration(days: i)),
              foreignNet: 3000000,
              investmentTrustNet: 1000000,
            ),
        ],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      final keys = result.supportingData.map((ls) => ls.key).toSet();
      expect(keys, contains('summary.institutionalBuyTrend'));
    });

    test('include PE and dividend yield in supporting data', () {
      final result = service.generate(
        analysis: createTestAnalysis(),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: null,
        priceChange: 2.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: createTestPER(per: 10, dividendYield: 5.0),
        horizon: Horizon.short,
      );

      expect(result.supportingData, isNotEmpty);
      // PE=10 → peUndervalued, yield=5.0 ≥ 4.0 → highDividendYield
      final keys = result.supportingData.map((ls) => ls.key).toSet();
      expect(keys, contains('summary.peUndervalued'));
      expect(keys, contains('summary.highDividendYield'));
    });
  });

  group('latestPrice code path', () {
    test('produce overallParts with trend key when latestPrice provided', () {
      final now = DateTime.now();
      final latestPrice = createTestPrice(close: 120.5, date: now);

      final result = service.generate(
        analysis: createTestAnalysis(
          trendState: 'UP',
          score: 50,
          supportLevel: 115.0,
          resistanceLevel: 125.0,
        ),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: latestPrice,
        priceChange: 3.5,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 無匯流 → 使用 overallUp trend key
      expect(_overallContainsKey(result, 'summary.overallUp'), isTrue);
      // 有支撐壓力 + close → 使用帶距離版本
      expect(
        _overallContainsKey(result, 'summary.supportResistanceWithDist'),
        isTrue,
      );
      // 有風險報酬比
      expect(_overallContainsKey(result, 'summary.riskReward'), isTrue);
    });

    test('append favorable RR note when upside ≥ 2× downside', () {
      final result = service.generate(
        analysis: createTestAnalysis(
          trendState: 'UP',
          score: 50,
          supportLevel: 115.0,
          resistanceLevel: 125.0,
        ),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: createTestPrice(close: 116.0, date: DateTime.now()),
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );
      // RR = (125-116)/(116-115) = 9 ≥ 2 → favorable
      expect(
        _overallContainsKey(result, 'summary.riskRewardFavorable'),
        isTrue,
      );
      expect(_overallContainsKey(result, 'summary.riskRewardPoor'), isFalse);
    });

    test('append poor RR note when downside > upside', () {
      final result = service.generate(
        analysis: createTestAnalysis(
          trendState: 'UP',
          score: 50,
          supportLevel: 115.0,
          resistanceLevel: 125.0,
        ),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: createTestPrice(close: 124.0, date: DateTime.now()),
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );
      // RR = (125-124)/(124-115) ≈ 0.11 < 1 → poor
      expect(_overallContainsKey(result, 'summary.riskRewardPoor'), isTrue);
      expect(
        _overallContainsKey(result, 'summary.riskRewardFavorable'),
        isFalse,
      );
    });

    test('use confluenceOverall key when confluence exists', () {
      final now = DateTime.now();
      final latestPrice = createTestPrice(close: 105.0, date: now);

      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
      ];

      final result = service.generate(
        analysis: createTestAnalysis(score: 60),
        reasons: reasons,
        latestPrice: latestPrice,
        priceChange: 5.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 有匯流 → 使用 confluenceOverall 格式而非 overallUp/Down/Range
      expect(_overallContainsKey(result, 'summary.confluenceOverall'), isTrue);
      expect(result.confluenceCount, greaterThan(0));
    });

    test('include supportResistance in overallParts', () {
      final now = DateTime.now();
      final latestPrice = createTestPrice(close: 100.0, date: now);

      final result = service.generate(
        analysis: createTestAnalysis(
          trendState: 'RANGE',
          score: 25,
          supportLevel: 95.0,
          resistanceLevel: 110.0,
        ),
        reasons: [createTestReason(reasonType: 'PATTERN_DOJI', ruleScore: 5)],
        latestPrice: latestPrice,
        priceChange: 0.5,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // close=100, support=95, resistance=110 → 使用帶距離版本
      expect(
        _overallContainsKey(result, 'summary.supportResistanceWithDist'),
        isTrue,
      );
      expect(_overallContainsKey(result, 'summary.overallRange'), isTrue);
    });

    test('handle null close in latestPrice gracefully', () {
      final now = DateTime.now();
      final latestPrice = createTestPrice(date: now);

      final result = service.generate(
        analysis: createTestAnalysis(score: 30),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20)],
        latestPrice: latestPrice,
        priceChange: 2.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      // 即使 close 為 null，仍應產生有效的 overallParts
      expect(result.overallParts, isNotEmpty);
      expect(result.sentiment, isNotNull);
    });
  });

  // ==========================================
  // Stage 5c — dual-horizon awareness
  // ==========================================
  //
  // 驗證 `horizon` 參數切換時，service 讀取對應 horizon 的 scoreShort /
  // scoreLong / ruleScoreShort / ruleScoreLong。當 placeholder JSON 為空
  // （scoreShort == scoreLong）時兩個 horizon 產生相同結果；分化時
  // 產生對應 horizon 的判斷。
  group('AnalysisSummaryService dual-horizon awareness', () {
    test('long horizon reads analysis.scoreLong for sentiment grading', () {
      // 短線 score = 10（bearish 等級），長線 score = 70（strongBullish 等級）
      final analysis = DailyAnalysisEntry(
        symbol: 'TEST',
        date: DateTime(2024, 6, 15),
        trendState: 'UP',
        reversalState: 'NONE',
        scoreShort: 10,
        scoreLong: 70,
        computedAt: DateTime(2024, 6, 15, 10, 0),
      );
      final reasons = [
        createTestReasonDual(
          reasonType: 'REVERSAL_W2S',
          ruleScoreShort: 5,
          ruleScoreLong: 35,
        ),
        createTestReasonDual(
          reasonType: 'TECH_BREAKOUT',
          rank: 2,
          ruleScoreShort: 5,
          ruleScoreLong: 20,
        ),
      ];

      final shortResult = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );
      final longResult = service.generate(
        analysis: analysis,
        reasons: reasons,
        latestPrice: null,
        priceChange: 1.0,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.long,
      );

      // 短線 score=10 + 低 ruleScoreShort → 不該升到 strongBullish
      expect(shortResult.sentiment, isNot(SummarySentiment.strongBullish));
      // 長線 score=70 + 高 ruleScoreLong → strongBullish
      expect(longResult.sentiment, SummarySentiment.strongBullish);
    });

    test(
      'long horizon filters key signals by ruleScoreLong (not ruleScoreShort)',
      () {
        // 構造一條 rule：短線負值（應被過濾掉）、長線正值（應出現在 keySignals）
        final reasons = [
          createTestReasonDual(
            reasonType: 'TECH_BREAKOUT',
            ruleScoreShort: -10, // 短線視角下是 risk
            ruleScoreLong: 25, // 長線視角下是 key signal
          ),
        ];
        final analysis = createTestAnalysis(score: 30);

        final shortResult = service.generate(
          analysis: analysis,
          reasons: reasons,
          latestPrice: null,
          priceChange: null,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.short,
        );
        final longResult = service.generate(
          analysis: analysis,
          reasons: reasons,
          latestPrice: null,
          priceChange: null,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.long,
        );

        // 短線視角：TECH_BREAKOUT 是 risk，不該出現在 keySignals
        expect(
          shortResult.keySignals.any((s) => s.key == 'summary.breakout'),
          isFalse,
        );
        expect(
          shortResult.riskFactors.any((s) => s.key == 'summary.breakout'),
          isTrue,
        );

        // 長線視角：TECH_BREAKOUT 是 key signal，不該出現在 risks
        expect(
          longResult.keySignals.any((s) => s.key == 'summary.breakout'),
          isTrue,
        );
        expect(
          longResult.riskFactors.any((s) => s.key == 'summary.breakout'),
          isFalse,
        );
      },
    );

    test(
      'empty placeholder (scoreShort == scoreLong) produces identical result across horizons',
      () {
        // Stage 5c → Stage 4 的關鍵 invariant：當 calibration 是空的時候，
        // 切換 horizon 對 UI 沒有 user-visible 影響。
        final analysis = createTestAnalysis(score: 55);
        final reasons = [
          createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 30),
          createTestReason(
            reasonType: 'KD_GOLDEN_CROSS',
            rank: 2,
            ruleScore: 15,
          ),
        ];

        final shortResult = service.generate(
          analysis: analysis,
          reasons: reasons,
          latestPrice: null,
          priceChange: 1.0,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.short,
        );
        final longResult = service.generate(
          analysis: analysis,
          reasons: reasons,
          latestPrice: null,
          priceChange: 1.0,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.long,
        );

        expect(shortResult.sentiment, longResult.sentiment);
        expect(shortResult.confidence, longResult.confidence);
        expect(
          shortResult.keySignals.map((s) => s.key).toList(),
          longResult.keySignals.map((s) => s.key).toList(),
        );
        expect(
          shortResult.riskFactors.map((s) => s.key).toList(),
          longResult.riskFactors.map((s) => s.key).toList(),
        );
      },
    );
  });
  group('回檔模式 v2 訊號進摘要（2026-07-23 稽核修復）', () {
    // Mode C v2（2026-06-19）的 4 條主訊號與空頭十字星當初未同步擴充
    // 摘要 builders，被 whereType 靜默丟棄——只靠回檔訊號上榜的股票，
    // AI 摘要完全不提其核心訊號。
    SummaryData genWith(String code, double score) => service.generate(
      analysis: createTestAnalysis(trendState: 'UP', score: 20),
      reasons: [createTestReason(reasonType: code, ruleScore: score)],
      latestPrice: null,
      priceChange: 0.5,
      institutionalHistory: [],
      revenueHistory: [],
      latestPER: null,
      horizon: Horizon.short,
    );

    test('四條回檔主訊號各自出現在 keySignals', () {
      const cases = {
        'PULLBACK_TO_MA20': 'summary.pullbackToMa20',
        'PULLBACK_TO_MA10': 'summary.pullbackToMa10',
        'HAMMER_AT_SUPPORT': 'summary.hammerAtSupport',
        'KD_HIGH_PULLBACK': 'summary.kdHighPullback',
      };
      cases.forEach((code, key) {
        final result = genWith(code, 15);
        expect(
          result.keySignals.map((s) => s.key),
          contains(key),
          reason: code,
        );
      });
    });

    test('空頭十字星出現在 riskFactors', () {
      final result = genWith('PATTERN_DOJI_BEARISH', -8);
      expect(
        result.riskFactors.map((s) => s.key),
        contains('summary.patternDojiBearish'),
      );
    });
  });

  group('法人 streak 截斷語意（P1-6）', () {
    // 規則 description 已會說「連買 9 日以上」，摘要若仍說「連買 9 天」
    // 就會同一訊號兩處說法矛盾。此測試釘住兩邊同步。
    SummaryData genStreak(String code, String evidence, double score) =>
        service.generate(
          analysis: createTestAnalysis(trendState: 'UP', score: 20),
          reasons: [
            createTestReason(
              reasonType: code,
              evidenceJson: evidence,
              ruleScore: score,
            ),
          ],
          latestPrice: null,
          priceChange: 0.5,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.short,
        );

    test('🚨 streakTruncated=true 走「N 天以上」文案', () {
      final result = genStreak(
        'INSTITUTIONAL_BUY_STREAK',
        '{"streakDays":9,"streakTruncated":true}',
        15,
      );
      expect(
        result.keySignals.map((s) => s.key),
        contains('summary.institutionalBuyStreakDaysTruncated'),
      );
    });

    test('streakTruncated=false 走原本確切天數文案', () {
      final result = genStreak(
        'INSTITUTIONAL_BUY_STREAK',
        '{"streakDays":5,"streakTruncated":false}',
        15,
      );
      expect(
        result.keySignals.map((s) => s.key),
        contains('summary.institutionalBuyStreakDays'),
      );
    });

    test('賣超 streak 截斷同樣揭露', () {
      final result = genStreak(
        'INSTITUTIONAL_SELL_STREAK',
        '{"streakDays":9,"streakTruncated":true}',
        -15,
      );
      expect(
        result.riskFactors.map((s) => s.key),
        contains('summary.institutionalSellStreakDaysTruncated'),
      );
    });
  });
  // ====================================================================
  // 輔助數據的連買天數不得與關鍵訊號矛盾（2026-07-26 實機發現）
  //
  // 實機截圖：同一張 AI 分析卡上「關鍵訊號」寫「法人連續買超 17 天以上」，
  // 「輔助數據」卻寫「法人連續 7 天買超」——同一件事兩個數字。
  //
  // 根因是兩者用不同窗口：關鍵訊號取自規則 evidence（評分路徑，
  // institutionalStreakLookbackDays=90），輔助數據自行從
  // institutionalHistory 數（個股詳情的顯示窗 institutionalLookbackDays=10）。
  // 放寬評分窗之前兩邊都被截在 ~9 天、看不出來，放寬後就對撞。
  //
  // 不把顯示窗一起放寬：institutionalHistory 也餵籌碼頁的法人表，
  // 9 列變 60 幾列不是想要的。改為讓輔助數據在規則已觸發時不重複陳述——
  // 規則在 ≥4 日觸發、輔助數據在 ≥3 日顯示，讓後者只負責恰好 3 日那格。
  // ====================================================================
  group('輔助數據不得與關鍵訊號的連買天數矛盾', () {
    List<DailyInstitutionalEntry> buyDays(int n) => List.generate(
      n,
      (i) => DailyInstitutionalEntry(
        symbol: 'TEST',
        date: DateTime(2026, 7, 1).add(Duration(days: i)),
        foreignNet: 500000,
        investmentTrustNet: 100000,
      ),
    );

    test('🚨 連續買超規則已觸發時，輔助數據不得再自行陳述天數', () {
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'UP', score: 20),
        reasons: [
          createTestReason(
            reasonType: 'INSTITUTIONAL_BUY_STREAK',
            evidenceJson: '{"streakDays":17,"streakTruncated":true}',
            ruleScore: 15,
          ),
        ],
        latestPrice: null,
        priceChange: 0.5,
        institutionalHistory: buyDays(7),
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(
        result.keySignals.map((s) => s.key),
        contains('summary.institutionalBuyStreakDaysTruncated'),
        reason: '關鍵訊號仍須陳述 17 天以上',
      );
      expect(
        result.supportingData.map((s) => s.key),
        isNot(contains('summary.institutionalBuyTrend')),
        reason: '輔助數據用的是顯示窗（較短），與關鍵訊號並列會自相矛盾',
      );
    });

    test('規則未觸發時輔助數據照常陳述（保留其原有價值）', () {
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'UP', score: 20),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 15)],
        latestPrice: null,
        priceChange: 0.5,
        institutionalHistory: buyDays(3),
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      expect(
        result.supportingData.map((s) => s.key),
        contains('summary.institutionalBuyTrend'),
      );
    });
  });
  // ====================================================================
  // 當日漲跌的方向不得由「趨勢狀態」決定（2026-07-26 實機發現）
  //
  // 實機（1810 和成，2026-07-24）：頁首顯示 ↓ −2.15（−6.99%），AI 摘要
  // 卻寫「目前呈現上升趨勢，收盤價 28.6 元，**漲幅 7.0%**」——同一檔股票
  // 同一天，一個說跌 7%、一個說漲 7%。DB 實證：收 28.60、前收 30.75。
  //
  // 根因兩層：
  //   (1) `priceChange?.abs()` 把正負號剝掉
  //   (2) 「漲幅/跌幅」的用詞來自 `analysis.trendState`（趨勢），不是當日
  //       漲跌的方向。而這兩件事本來就可能不一致——處於上升趨勢的股票
  //       今天當然可以大跌。模板卻強迫它們一致。
  //
  // 修法：句子仍陳述趨勢（那部分是對的），但當日漲跌改為**帶正負號**且
  // 用詞中性，不再宣稱方向。
  // ====================================================================
  group('當日漲跌不得與趨勢用詞綁定', () {
    test('🚨 上升趨勢但當日下跌時，數字必須帶負號', () {
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'UP', score: 20),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 15)],
        latestPrice: DailyPriceEntry(
          symbol: 'TEST',
          date: DateTime(2026, 7, 24),
          close: 28.6,
        ),
        priceChange: -6.99,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      final overall = result.overallParts.firstWhere(
        (p) => p.key == 'summary.overallUp',
      );
      expect(
        overall.namedArgs['change'],
        startsWith('-'),
        reason: '當日跌 6.99% 卻顯示為正數，會被讀成上漲——方向完全相反',
      );
    });

    test('上升趨勢且當日上漲時帶正號', () {
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'UP', score: 20),
        reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 15)],
        latestPrice: DailyPriceEntry(
          symbol: 'TEST',
          date: DateTime(2026, 7, 24),
          close: 30.0,
        ),
        priceChange: 3.5,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );

      final overall = result.overallParts.firstWhere(
        (p) => p.key == 'summary.overallUp',
      );
      expect(overall.namedArgs['change'], startsWith('+'));
    });
  });
  // ====================================================================
  // 輔助數據不得與關鍵訊號／風險提示重複同一句（2026-07-26 實機發現）
  //
  // 實機（1810 和成）：「本益比僅 7.6 倍，估值偏低。」在關鍵訊號與輔助
  // 數據各出現一次，一字不差——同一個 i18n key（summary.peUndervalued）
  // 被 `_buildSupportingData:451` 與規則映射 `:891` 各用一次。
  //
  // 與先前修的「連續買超」不同：那是兩個**不同的 key** 講同一件事、且
  // 數字互相矛盾；這裡是**同一個 key** 出現兩次。前者靠 streakStatedByRule
  // 個別處理，後者需要通用去重——否則每加一條規則就要再補一次特例。
  //
  // 若兩處引數不一致（來源不同：規則 evidence vs latestPER），重複顯示
  // 會從冗餘升級為矛盾。一律保留關鍵訊號那份（已排序、已計分）。
  // ====================================================================
  test('🚨 輔助數據不得重複關鍵訊號已陳述的同一 key', () {
    final result = service.generate(
      analysis: createTestAnalysis(trendState: 'UP', score: 20),
      reasons: [
        createTestReason(
          reasonType: 'PE_UNDERVALUED',
          evidenceJson: '{"pe":7.6}',
          ruleScore: 15,
        ),
      ],
      latestPrice: null,
      priceChange: 0.5,
      institutionalHistory: [],
      revenueHistory: [],
      latestPER: createTestPER(per: 7.6),
      horizon: Horizon.short,
    );

    final keys = result.keySignals.map((s) => s.key).toSet();
    expect(keys, contains('summary.peUndervalued'), reason: '關鍵訊號應保留（已排序、已計分）');
    expect(
      result.supportingData.map((s) => s.key),
      isNot(contains('summary.peUndervalued')),
      reason: '同一句在同一張卡出現兩次是雜訊；引數若不一致更會變成矛盾',
    );
  });

  test('關鍵訊號未提及時輔助數據照常陳述', () {
    final result = service.generate(
      analysis: createTestAnalysis(trendState: 'UP', score: 20),
      reasons: [createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 15)],
      latestPrice: null,
      priceChange: 0.5,
      institutionalHistory: [],
      revenueHistory: [],
      latestPER: createTestPER(per: 7.6),
      horizon: Horizon.short,
    );

    expect(
      result.supportingData.map((s) => s.key),
      contains('summary.peUndervalued'),
      reason: '規則沒觸發時，輔助數據仍是這項資訊的唯一來源',
    );
  });
}

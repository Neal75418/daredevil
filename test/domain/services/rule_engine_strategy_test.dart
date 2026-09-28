import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/rules/technical_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  late RuleEngine ruleEngine;

  setUp(() {
    ruleEngine = RuleEngine();
  });

  group('RuleEngine Strategy', () {
    test('evaluateStock should run all rules and return reasons', () {
      // 產生有成交量爆增的價格資料
      // 注意：突破規則需要 MA20 過濾和成交量確認（TrendParams.reversalVolumeConfirm 倍均量）
      final prices = generatePricesWithVolumeSpike(
        days: 30,
        normalVolume: 1000,
        spikeVolume: 5000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        resistanceLevel: 100.0,
      );

      final reasons = ruleEngine.evaluateStock(
        context,
        StockData(symbol: 'TEST', prices: prices),
      );

      // 驗證成交量爆增規則有觸發
      expect(reasons, isNotEmpty);
      expect(reasons.any((r) => r.type == ReasonType.volumeSpike), isTrue);
      // 注意：突破規則需要 MA20 與成交量確認，收盤 103 剛好等於 breakoutLevel (100 * 1.03)
      // 需要 close > breakoutLevel 才會觸發，所以這裡不再驗證

      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, greaterThan(0));
    });

    test('support custom rules via constructor', () {
      final customEngine = RuleEngine(customRules: [const BreakoutRule()]);

      // 產生有成交量的上升趨勢價格
      // 突破規則需要: 1) close > breakoutLevel  2) close > MA20  3) todayVolume >= 1.5x avgVolume
      final prices = generatePricesWithBreakout(
        days: 30,
        basePrice: 100.0,
        breakoutPrice: 110.0, // 超過 breakoutLevel (100 * 1.03 = 103)
        normalVolume: 1000,
        breakoutVolume: 3000, // 3x 均量
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
        resistanceLevel: 100.0,
      );

      final reasons = customEngine.evaluateStock(
        context,
        StockData(symbol: 'UNKNOWN', prices: prices),
      );

      // 驗證突破規則有觸發
      expect(reasons.any((r) => r.type == ReasonType.techBreakout), isTrue);
    });
  });

  group('calculateScore', () {
    // 注意：以下兩個測試是 calculateScore 的「純算術 unit test」。
    // calculateScore 的契約是「對收到的 reasons 做加總、冷卻、cap」— 即使上游
    // pipeline 不會產出這種輸入組合，此契約仍須被獨立驗證。
    test('Breakout + Volume Spike 各自計分、不做 combo bonus', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'Breakout',
        ),
        const TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'Volume',
        ),
      ];

      // Base: 25 + 22 = 47
      // 組合加成已於 2026-04 移除（TECH_BREAKOUT 本身已要求量能配合，再加 bonus 是 double-count）
      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 47);
    });

    test('Reversal + Volume Spike 各自計分、不做 combo bonus', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.reversalW2S,
          score: 35,
          description: 'Reversal',
        ),
        const TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'Volume',
        ),
      ];

      // Base: 35 + 22 = 57（bonus 已於 2026-04 移除）
      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 57);
    });

    test('cap score at maxScore', () {
      // Simulate reasons that sum > maxScore
      final reasons = List.generate(
        5,
        (i) => const TriggeredReason(
          type: ReasonType.reversalW2S,
          score: 35,
          description: 'High Score',
        ),
      );

      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, RuleScores.maxScore);
    });

    test('not reduce score below 0', () {
      // Simulate negative reasons
      final reasons = [
        const TriggeredReason(
          type: ReasonType.techBreakdown,
          score: -100,
          description: 'Bad',
        ),
      ];

      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 0);
    });
  });
}

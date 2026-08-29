import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/signal_confluence.dart';

import '../../helpers/analysis_data_generators.dart';

void main() {
  const detector = SignalConfluenceDetector();

  group('SignalConfluence.match', () {
    test('match when all groups have at least one hit', () {
      const pattern = SignalConfluence(
        signalGroups: [
          {'A', 'B'},
          {'C', 'D'},
        ],
        summaryKey: 'test.key',
      );

      final result = pattern.match({'A', 'C', 'E'});
      expect(result, isNotNull);
      expect(result, containsAll(['A', 'C']));
    });

    test('return null when a group has no match', () {
      const pattern = SignalConfluence(
        signalGroups: [
          {'A', 'B'},
          {'C', 'D'},
        ],
        summaryKey: 'test.key',
      );

      final result = pattern.match({'A', 'E'}); // 缺少 C or D
      expect(result, isNull);
    });

    test('return all matched types from multiple groups', () {
      const pattern = SignalConfluence(
        signalGroups: [
          {'A', 'B'},
          {'C'},
        ],
        summaryKey: 'test.key',
      );

      // A 和 B 都在 activeTypes 中，C 也在
      final result = pattern.match({'A', 'B', 'C'});
      expect(result, isNotNull);
      expect(result, containsAll(['A', 'B', 'C']));
    });
  });

  group('SignalConfluenceDetector.detect bullish', () {
    test('detect volume_price_breakout pattern', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(reasonType: 'VOLUME_SPIKE', rank: 2, ruleScore: 15),
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('TECH_BREAKOUT'));
      expect(result.consumedTypes, contains('VOLUME_SPIKE'));
      expect(result.summaryKeys, isNotEmpty);
    });

    test('detect bottom_reversal pattern', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('REVERSAL_W2S'));
      expect(result.consumedTypes, contains('KD_GOLDEN_CROSS'));
    });

    test('detect institutional_confirmation pattern', () {
      final reasons = [
        createTestReason(reasonType: 'INSTITUTIONAL_BUY', ruleScore: 10),
        createTestReason(reasonType: 'TECH_BREAKOUT', rank: 2, ruleScore: 20),
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('INSTITUTIONAL_BUY'));
    });

    test('detect fundamental_technical pattern', () {
      final reasons = [
        createTestReason(reasonType: 'REVENUE_YOY_SURGE', ruleScore: 15),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BULLISH',
          rank: 2,
          ruleScore: 10,
        ),
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('REVENUE_YOY_SURGE'));
      expect(result.consumedTypes, contains('MA_ALIGNMENT_BULLISH'));
    });

    test('detect value_investment pattern', () {
      final reasons = [
        createTestReason(reasonType: 'PE_UNDERVALUED', ruleScore: 10),
        createTestReason(
          reasonType: 'HIGH_DIVIDEND_YIELD',
          rank: 2,
          ruleScore: 8,
        ),
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('PE_UNDERVALUED'));
      expect(result.consumedTypes, contains('HIGH_DIVIDEND_YIELD'));
      expect(result.summaryKeys, contains('summary.confluenceValueInvestment'));
    });

    test('detect momentum_breakout pattern', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BULLISH',
          rank: 2,
          ruleScore: 10,
        ),
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('TECH_BREAKOUT'));
      expect(result.consumedTypes, contains('MA_ALIGNMENT_BULLISH'));
      expect(
        result.summaryKeys,
        contains('summary.confluenceMomentumBreakout'),
      );
    });

    test('volume_price_breakout should take priority over momentum_breakout '
        'when TECH_BREAKOUT is consumed', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(reasonType: 'VOLUME_SPIKE', rank: 2, ruleScore: 15),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BULLISH',
          rank: 3,
          ruleScore: 10,
        ),
      ];

      final result = detector.detect(reasons, bullish: true);

      // volume_price_breakout matches first, consuming TECH_BREAKOUT
      expect(result.summaryKeys, contains('summary.confluenceVolumeBreakout'));
      // momentum_breakout cannot match (TECH_BREAKOUT already consumed)
      expect(
        result.summaryKeys,
        isNot(contains('summary.confluenceMomentumBreakout')),
      );
    });

    test('return empty when no bullish confluence found', () {
      final reasons = [
        createTestReason(reasonType: 'VOLUME_SPIKE', ruleScore: 15),
        // 缺少 BREAKOUT 來組成 volume_price_breakout 模式
      ];

      final result = detector.detect(reasons, bullish: true);

      expect(result.matchedCount, 0);
      expect(result.consumedTypes, isEmpty);
      expect(result.summaryKeys, isEmpty);
    });

    test('detect multiple confluences when signals are independent', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
        createTestReason(
          reasonType: 'REVENUE_YOY_SURGE',
          rank: 3,
          ruleScore: 15,
        ),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BULLISH',
          rank: 4,
          ruleScore: 10,
        ),
      ];

      final result = detector.detect(reasons, bullish: true);

      // bottom_reversal (W2S + KD) consumes W2S
      // fundamental_technical needs (REVENUE + W2S/BREAKOUT/MA_BULLISH)
      // → W2S already consumed, but MA_ALIGNMENT_BULLISH still available
      expect(result.matchedCount, greaterThanOrEqualTo(2));
    });

    test('not double-count consumed signals across patterns', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
        createTestReason(
          reasonType: 'REVENUE_YOY_SURGE',
          rank: 3,
          ruleScore: 15,
        ),
        // No MA_ALIGNMENT_BULLISH or TECH_BREAKOUT → fundamental_technical
        // needs W2S (consumed by bottom_reversal) for its second group
      ];

      final result = detector.detect(reasons, bullish: true);

      // bottom_reversal matches (W2S + KD), consuming W2S
      // fundamental_technical needs REVENUE + (W2S/BREAKOUT/MA_BULLISH)
      // W2S is consumed → only 1 pattern should match
      expect(result.matchedCount, 1);
    });
  });

  group('SignalConfluenceDetector.detect bearish', () {
    test('detect top_reversal pattern', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_S2W', ruleScore: -30),
        createTestReason(reasonType: 'KD_DEATH_CROSS', rank: 2, ruleScore: -10),
      ];

      final result = detector.detect(reasons, bullish: false);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('REVERSAL_S2W'));
      expect(result.consumedTypes, contains('KD_DEATH_CROSS'));
    });

    test('detect bearish_breakdown pattern', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKDOWN', ruleScore: -20),
        createTestReason(
          reasonType: 'MA_ALIGNMENT_BEARISH',
          rank: 2,
          ruleScore: -10,
        ),
      ];

      final result = detector.detect(reasons, bullish: false);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('TECH_BREAKDOWN'));
    });

    test('detect value_trap pattern', () {
      final reasons = [
        createTestReason(reasonType: 'PE_UNDERVALUED', ruleScore: 10),
        createTestReason(reasonType: 'REVERSAL_S2W', rank: 2, ruleScore: -30),
      ];

      final result = detector.detect(reasons, bullish: false);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('PE_UNDERVALUED'));
      expect(result.consumedTypes, contains('REVERSAL_S2W'));
    });

    test('detect institutional_exit pattern', () {
      final reasons = [
        createTestReason(reasonType: 'INSTITUTIONAL_SELL', ruleScore: -10),
        createTestReason(reasonType: 'FOREIGN_EXODUS', rank: 2, ruleScore: -15),
      ];

      final result = detector.detect(reasons, bullish: false);

      expect(result.matchedCount, greaterThan(0));
      expect(result.consumedTypes, contains('INSTITUTIONAL_SELL'));
      expect(result.consumedTypes, contains('FOREIGN_EXODUS'));
      expect(
        result.summaryKeys,
        contains('summary.confluenceInstitutionalExit'),
      );
    });

    // ================================================================
    // 多空共用訊號（2026-08-29 領域稽核 M9）
    //
    // `confluenceValueInvestment`（多）與 `confluenceValueTrap`（空）的第一
    // 個 signalGroup 完全相同：`{PE_UNDERVALUED, PBR_UNDERVALUED}`。detect()
    // 被呼叫兩次、消耗集各自獨立，於是同一檔股票可以同時拿到「價值投資」
    // 與「價值陷阱」兩個合成結論；而 analysis_summary_service 會把
    // PE_UNDERVALUED 從多空**兩份**原始清單裡剝掉，使用者只看得到兩個互相
    // 矛盾的結論、看不到底下那個共用訊號。
    //
    // 實測 13 個 stock-day / 7 檔（4763 連續四天:8/14、8/18、8/19、8/20）。
    //
    // **空方勝出**：兩個結論同時成立時，「便宜」是兩邊都知道的事，而陷阱
    // 那條額外告訴你便宜不夠——資訊嚴格較多。做法是先跑空方，把它的
    // consumedTypes 傳進多方那次。
    // ================================================================
    test('🚨 空方消耗過的訊號,多方不得再用來合成結論(稽核 M9)', () {
      final reasons = [
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
      ];

      final bearish = detector.detect(reasons, bullish: false);
      expect(
        bearish.summaryKeys,
        contains('summary.confluenceValueTrap'),
        reason: '前提:空方的價值陷阱必須先成立',
      );
      expect(bearish.consumedTypes, contains('PE_UNDERVALUED'));

      final bullish = detector.detect(
        reasons,
        bullish: true,
        alreadyConsumed: bearish.consumedTypes,
      );
      expect(
        bullish.summaryKeys,
        isNot(contains('summary.confluenceValueInvestment')),
        reason: '同一檔股票不得同時被判「價值投資」與「價值陷阱」',
      );
    });

    test('🚨 不傳 alreadyConsumed 時維持原行為(對照組——證明前提成立)', () {
      // 這條證明上一條測的是**新參數的效果**,不是那組 reasons 本來就
      // 不觸發多方模式。
      final reasons = [
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
      ];
      expect(
        detector.detect(reasons, bullish: true).summaryKeys,
        contains('summary.confluenceValueInvestment'),
      );
    });

    test('alreadyConsumed 不影響無關的模式', () {
      final reasons = [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(reasonType: 'VOLUME_SPIKE', rank: 2, ruleScore: 15),
      ];
      expect(
        detector
            .detect(
              reasons,
              bullish: true,
              alreadyConsumed: const {'PE_UNDERVALUED', 'REVERSAL_S2W'},
            )
            .matchedCount,
        greaterThan(0),
      );
    });

    test('not match bullish patterns when detecting bearish', () {
      final reasons = [
        createTestReason(reasonType: 'REVERSAL_W2S', ruleScore: 35),
        createTestReason(reasonType: 'KD_GOLDEN_CROSS', rank: 2, ruleScore: 10),
      ];

      final result = detector.detect(reasons, bullish: false);

      expect(result.matchedCount, 0);
    });
  });
}

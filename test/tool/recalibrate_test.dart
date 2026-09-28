// Synthetic-data unit tests for tool/recalibrate.dart
//
// Tests the pure-math [Calibrator] class and data models using fabricated
// inputs. No DB or filesystem access. Verifies:
//   1. Proportion z-test (computeTStat) — happy path + degenerate cases
//   2. Linear map normalization (linearMapScore) — boundary behavior
//   3. Single-rule calibrate() — all 3 cut reasons + active branch
//   4. Batch calibrateAll() — normalization uses survivors only
//   5. CalibratedRule.toJson serialization shape

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/recalibrate.dart';

void main() {
  // ==========================================================================
  // computeTStat — proportion z-test
  // ==========================================================================

  group('Calibrator.computeTStat', () {
    // 2026-06-18 formula 修正：variance 用 H0 baseline 算（`p0*(1-p0)/n`），
    // 不再用 sample p 算。Backward compat：未提供 baseline 預設 0.5。
    test('happy path: hit_rate 0.65, n=100 → positive significant t-stat', () {
      final tStat = Calibrator.computeTStat(0.65, 100);
      // (0.65 - 0.5) / sqrt(0.5 × 0.5 / 100) = 0.15 / 0.05 = 3.0
      expect(tStat, closeTo(3.0, 0.01));
    });

    test('hit_rate 0.55, n=30 → t-stat around 0.548 (below 1.5 cut)', () {
      final tStat = Calibrator.computeTStat(0.55, 30);
      // (0.55 - 0.5) / sqrt(0.5 × 0.5 / 30) = 0.05 / 0.0913 ≈ 0.5477
      expect(tStat, closeTo(0.5477, 0.01));
      expect(tStat, lessThan(Calibrator.tStatCutThreshold));
    });

    test('hit_rate exactly 0.5 → t-stat = 0 (null hypothesis)', () {
      expect(Calibrator.computeTStat(0.5, 100), 0.0);
    });

    test('hit_rate 0 → 強烈負 t-stat（不再是 degenerate=0）', () {
      // 修正後：variance 是 baseline 算的，hitRate 0 不會壓 variance 到 0。
      // (0 - 0.5) / sqrt(0.5 × 0.5 / 100) = -0.5 / 0.05 = -10.0
      expect(Calibrator.computeTStat(0.0, 100), closeTo(-10.0, 0.01));
    });

    test('hit_rate 1.0 → 強烈正 t-stat（不再是 degenerate=0）', () {
      // (1.0 - 0.5) / sqrt(0.5 × 0.5 / 100) = 0.5 / 0.05 = 10.0
      expect(Calibrator.computeTStat(1.0, 100), closeTo(10.0, 0.01));
    });

    test('degenerate: n = 0 → 0', () {
      expect(Calibrator.computeTStat(0.6, 0), 0.0);
    });

    test('degenerate: n negative → 0', () {
      expect(Calibrator.computeTStat(0.6, -5), 0.0);
    });

    test('baseline=0.3461 (5D台股實證): hit_rate 0.45 → significant lift', () {
      // 拿 5D 真實 baseline 0.3461，hit_rate 0.45 = +10pp lift
      // (0.45 - 0.3461) / sqrt(0.3461 × 0.6539 / 100)
      // = 0.1039 / sqrt(0.002263) = 0.1039 / 0.04757 ≈ 2.184
      final tStat = Calibrator.computeTStat(0.45, 100, baseline: 0.3461);
      expect(tStat, closeTo(2.184, 0.01));
      expect(tStat, greaterThan(Calibrator.tStatCutThreshold));
    });

    test(
      'baseline regression: 同樣 hit_rate 0.45 對 0.5 baseline 顯示為 negative',
      () {
        // 對比上一個 test：證明 baseline 修正前後 verdict 完全相反。
        // pre-2026-06-18：hit_rate 0.45 vs 0.5 baseline → -1.0 t-stat
        //                 → 看似負面 / 沒 alpha
        // post-2026-06-18：hit_rate 0.45 vs 0.3461 baseline → +2.18 t-stat
        //                  → 真實有 alpha（撈到 cut 過頭的 rule）
        final tStat = Calibrator.computeTStat(0.45, 100);
        expect(tStat, closeTo(-1.0, 0.01));
        expect(tStat, lessThan(Calibrator.tStatCutThreshold));
      },
    );
  });

  // ==========================================================================
  // linearMapScore — min-max normalization to [10, 35]
  // ==========================================================================

  group('Calibrator.linearMapScore', () {
    test('raw == minRaw → score = minScore (10)', () {
      expect(Calibrator.linearMapScore(5.0, 5.0, 20.0), Calibrator.minScore);
    });

    test('raw == maxRaw → score = maxScore (35)', () {
      expect(Calibrator.linearMapScore(20.0, 5.0, 20.0), Calibrator.maxScore);
    });

    test('raw midpoint → score midpoint', () {
      // minRaw=0, maxRaw=10, raw=5 → 50% → score = 10 + 0.5 × 25 = 22.5 → round(22) or (23)
      final score = Calibrator.linearMapScore(5.0, 0.0, 10.0);
      expect(score, anyOf(22, 23));
    });

    test('edge: minRaw == maxRaw → returns midpoint of score range', () {
      // All rules have identical raw weight — can't normalize, fall back to midpoint
      expect(Calibrator.linearMapScore(7.0, 7.0, 7.0), 22); // (10+35)~/2
    });

    test('edge: maxRaw < minRaw → returns midpoint (defensive)', () {
      expect(Calibrator.linearMapScore(5.0, 10.0, 5.0), 22);
    });

    test('out of range: raw > maxRaw → clamped to maxScore', () {
      // raw > maxRaw should not produce score > 35
      expect(Calibrator.linearMapScore(100.0, 0.0, 10.0), Calibrator.maxScore);
    });

    test('out of range: raw < minRaw → clamped to minScore', () {
      expect(Calibrator.linearMapScore(-5.0, 0.0, 10.0), Calibrator.minScore);
    });
  });

  // ==========================================================================
  // calibrate — single-rule full pipeline
  // ==========================================================================

  group('Calibrator.calibrate', () {
    // Test isolation: use normalization range [0, 10] so mid-weights land in middle
    const minRaw = 0.0;
    const maxRaw = 10.0;

    RuleStats stats({
      String ruleId = 'test_rule',
      required double hitRate,
      required double avgReturn,
      required int triggerCount,
    }) {
      return RuleStats(
        ruleId: ruleId,
        hitRate: hitRate,
        avgReturn: avgReturn,
        triggerCount: triggerCount,
      );
    }

    test('active: happy path with passing thresholds', () {
      final result = Calibrator.calibrate(
        stats(hitRate: 0.60, avgReturn: 2.0, triggerCount: 100),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );

      expect(result.active, isTrue);
      expect(result.cutReason, isNull);
      expect(result.samples, 100);
      expect(result.hitRate, 0.60);
      expect(result.avgReturn, 2.0);
      expect(result.score, inInclusiveRange(10, 35));
    });

    test('cut: sample_too_small (n=29, just below threshold)', () {
      final result = Calibrator.calibrate(
        stats(hitRate: 0.80, avgReturn: 5.0, triggerCount: 29),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );

      expect(result.active, isFalse);
      expect(result.cutReason, 'sample_too_small');
      expect(result.score, 0);
    });

    test('cut: sample_too_small (n=0, defensive)', () {
      final result = Calibrator.calibrate(
        stats(hitRate: 0.80, avgReturn: 5.0, triggerCount: 0),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );

      expect(result.active, isFalse);
      expect(result.cutReason, 'sample_too_small');
    });

    test('cut: t_stat_below_threshold', () {
      // hit_rate 0.51 barely above null → z-test ≈ 0.11 with n=30
      final result = Calibrator.calibrate(
        stats(hitRate: 0.51, avgReturn: 2.0, triggerCount: 30),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );

      expect(result.active, isFalse);
      expect(result.cutReason, 't_stat_below_threshold');
      expect(result.tStat, lessThan(Calibrator.tStatCutThreshold));
    });

    test('cut: hit_rate at 0.49 caught by t_stat (negative z when < 0.50)', () {
      // hit_rate 0.49 @ n=500 → z-stat negative → t_stat_below_threshold.
      // t_stat 先於 hit_rate 檢查。hitRateCutThreshold = 0.55：t-stat 過關但
      // hit_rate 仍低於 0.55 時（例如 n=500、hit_rate 0.54，t ≈ 1.79），
      // hit_rate_below_threshold 會觸發；本例 0.49 則 t-stat 為負、先被 t 砍。
      // （本測試未傳 baseline，走預設 0.5。）
      final result = Calibrator.calibrate(
        stats(hitRate: 0.49, avgReturn: 2.0, triggerCount: 500),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );

      expect(result.active, isFalse);
      expect(result.cutReason, 't_stat_below_threshold');
    });

    test('cut order: sample_size checked first', () {
      // All 3 thresholds fail, but sample_size reported first
      final result = Calibrator.calibrate(
        stats(hitRate: 0.40, avgReturn: 0.5, triggerCount: 10),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );
      expect(result.cutReason, 'sample_too_small');
    });

    test('cut order: t_stat checked before hit_rate', () {
      // hit_rate = 0.52 — would fail both t_stat and hit_rate cuts, but
      // t_stat should be reported (checked earlier in cut sequence).
      // Need samples ≥ 30 so we bypass sample check.
      // z = (0.52 - 0.5) / sqrt(0.52 × 0.48 / 50) = 0.02 / 0.0707 ≈ 0.283
      final result = Calibrator.calibrate(
        stats(hitRate: 0.52, avgReturn: 2.0, triggerCount: 50),
        minRaw: minRaw,
        maxRaw: maxRaw,
      );
      expect(result.cutReason, 't_stat_below_threshold');
    });
  });

  // ==========================================================================
  // calibrateAll — batch with survivor-only normalization
  // ==========================================================================

  group('Calibrator.calibrateAll', () {
    test('empty input → empty output', () {
      expect(Calibrator.calibrateAll([]), isEmpty);
    });

    test('all-cut input → all results marked inactive', () {
      // weak_edge: hit_rate 0.49 @ n=500 → negative t-stat → cut
      // tiny: hit_rate 0.70 but samples < 30 → cut as sample_too_small
      final allStats = [
        const RuleStats(
          ruleId: 'weak_edge',
          hitRate: 0.49,
          avgReturn: 1.0,
          triggerCount: 500,
        ),
        const RuleStats(
          ruleId: 'tiny',
          hitRate: 0.70,
          avgReturn: 5.0,
          triggerCount: 10,
        ),
      ];
      final result = Calibrator.calibrateAll(allStats);

      expect(result.length, 2);
      for (final rule in result.values) {
        expect(rule.active, isFalse);
        expect(rule.score, 0);
      }
      expect(result['weak_edge']!.cutReason, 't_stat_below_threshold');
      expect(result['tiny']!.cutReason, 'sample_too_small');
    });

    test(
      'mixed active + cut: normalization uses survivors only, cut rules reported',
      () {
        // cut_hitrate uses hit_rate 0.49 @ n=500 → negative t-stat →
        // t_stat_below_threshold.
        // avg_return is intentionally huge (50) to verify the survivor-only
        // normalization ignores this rule's raw weight even though it would
        // otherwise dominate the max.
        final allStats = [
          // Survivor (strong): highest raw weight
          const RuleStats(
            ruleId: 'strong',
            hitRate: 0.70,
            avgReturn: 5.0,
            triggerCount: 100,
          ),
          // Survivor (medium)
          const RuleStats(
            ruleId: 'medium',
            hitRate: 0.60,
            avgReturn: 3.0,
            triggerCount: 100,
          ),
          // Cut (hit_rate 0.49 → negative t-stat → t_stat_below_threshold)
          const RuleStats(
            ruleId: 'cut_hitrate',
            hitRate: 0.49,
            avgReturn: 50.0,
            triggerCount: 500,
          ),
        ];
        final result = Calibrator.calibrateAll(allStats);

        expect(result.length, 3);
        expect(result['strong']!.active, isTrue);
        expect(result['medium']!.active, isTrue);
        expect(result['cut_hitrate']!.active, isFalse);
        expect(result['cut_hitrate']!.cutReason, 't_stat_below_threshold');

        // 'strong' should have higher score than 'medium' within normalized range
        expect(result['strong']!.score, greaterThan(result['medium']!.score));

        // Both active scores in [10, 35]
        expect(result['strong']!.score, inInclusiveRange(10, 35));
        expect(result['medium']!.score, inInclusiveRange(10, 35));
      },
    );

    test('single survivor → gets midpoint score (no range to normalize)', () {
      final allStats = [
        const RuleStats(
          ruleId: 'lonely',
          hitRate: 0.65,
          avgReturn: 2.0,
          triggerCount: 100,
        ),
      ];
      final result = Calibrator.calibrateAll(allStats);

      expect(result['lonely']!.active, isTrue);
      // With only one survivor, minRaw == maxRaw → midpoint (22)
      expect(result['lonely']!.score, 22);
    });
  });

  // ==========================================================================
  // CalibratedRule.toJson — output schema fidelity
  // ==========================================================================

  group('CalibratedRule.toJson', () {
    test('active rule serializes all required fields without cut_reason', () {
      const stats = RuleStats(
        ruleId: 'test',
        hitRate: 0.60,
        avgReturn: 2.5,
        triggerCount: 100,
      );
      final rule = CalibratedRule.activeRule(
        stats: stats,
        tStat: 2.0,
        score: 20,
      );

      final json = rule.toJson();
      expect(json['score'], 20);
      expect(json['hit_rate'], 0.6);
      expect(json['avg_return'], 2.5);
      expect(json['samples'], 100);
      expect(json['t_stat'], 2.0);
      expect(json['active'], true);
      expect(json.containsKey('cut_reason'), isFalse);
    });

    test('cut rule serializes with cut_reason', () {
      const stats = RuleStats(
        ruleId: 'test',
        hitRate: 0.40,
        avgReturn: 1.0,
        triggerCount: 100,
      );
      final rule = CalibratedRule.cutRule(
        stats: stats,
        tStat: -2.0,
        reason: 'hit_rate_below_threshold',
      );

      final json = rule.toJson();
      expect(json['score'], 0);
      expect(json['active'], false);
      expect(json['cut_reason'], 'hit_rate_below_threshold');
    });

    test('rounding: hit_rate rounded to 4 decimal places', () {
      // hit_rate with many decimals → truncated to 4 in JSON
      const stats = RuleStats(
        ruleId: 'test',
        hitRate: 1 / 3, // 0.333333...
        avgReturn: 1.0,
        triggerCount: 100,
      );
      final rule = CalibratedRule.activeRule(
        stats: stats,
        tStat: 1.0,
        score: 10,
      );
      final json = rule.toJson();
      expect(json['hit_rate'], 0.3333);
    });
  });

  // ==========================================================================
  // rawWeight — sanity check
  // ==========================================================================

  group('Calibrator.rawWeight', () {
    test('formula: hit_rate × avg_return × sqrt(n)', () {
      const stats = RuleStats(
        ruleId: 't',
        hitRate: 0.6,
        avgReturn: 2.5,
        triggerCount: 100,
      );
      // 0.6 × 2.5 × sqrt(100) = 0.6 × 2.5 × 10 = 15.0
      expect(Calibrator.rawWeight(stats), closeTo(15.0, 1e-9));
    });

    test('sqrt(n) scaling dampens large n', () {
      const small = RuleStats(
        ruleId: 's',
        hitRate: 0.6,
        avgReturn: 2.5,
        triggerCount: 4,
      );
      const large = RuleStats(
        ruleId: 'l',
        hitRate: 0.6,
        avgReturn: 2.5,
        triggerCount: 16,
      );
      // small: 0.6 × 2.5 × 2 = 3.0
      // large: 0.6 × 2.5 × 4 = 6.0
      expect(Calibrator.rawWeight(small), closeTo(3.0, 1e-9));
      expect(Calibrator.rawWeight(large), closeTo(6.0, 1e-9));
      // 4× samples → 2× raw weight (sqrt scaling)
      expect(
        Calibrator.rawWeight(large),
        closeTo(2 * Calibrator.rawWeight(small), 1e-9),
      );
    });
  });

  // Unused import prevention — ensure `dart:math` import stays tied to Calibrator math
  test('sanity: dart:math sqrt exists', () {
    expect(sqrt(4), 2);
  });

  // ==========================================================================
  // OTA C1: computeJsonSha256 — content hash for manifest integrity check
  // ==========================================================================

  group('computeJsonSha256', () {
    test('empty string → SHA-256 of empty UTF-8 bytes', () {
      // Known SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      expect(
        computeJsonSha256(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('hello world has a stable known hash', () {
      // Known SHA-256("hello world") = b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
      expect(
        computeJsonSha256('hello world'),
        'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
      );
    });

    test('identical input → identical hash (deterministic)', () {
      const json = '{"schema_version": 1, "rules": {"X": {"score": 25}}}';
      expect(computeJsonSha256(json), computeJsonSha256(json));
    });

    test('one-char difference → completely different hash (avalanche)', () {
      final h1 = computeJsonSha256('{"v": 1}');
      final h2 = computeJsonSha256('{"v": 2}');
      expect(h1, isNot(equals(h2)));
      // Small change should flip at least half the bits on average
      final different = <int>[];
      for (var i = 0; i < h1.length; i++) {
        if (h1[i] != h2[i]) different.add(i);
      }
      expect(
        different.length,
        greaterThan(h1.length ~/ 3),
        reason:
            'SHA-256 avalanche: one-char input change flips most output chars',
      );
    });

    test('output is always 64 lowercase hex characters', () {
      final hash = computeJsonSha256('{"schema_version": 1, "rules": {}}');
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('regression: stable hash for a fixed calibration-shaped JSON', () {
      // Regression guard against library implementation changes. The hash
      // value is whatever `crypto`'s SHA-256 produces today — if the output
      // changes across versions this test flags it loudly.
      final hash = computeJsonSha256('{"rules": {}}');
      expect(hash.length, 64);
      expect(
        hash,
        '29429204d5e59589a7f47576c52a7cc412b77769b7d988de96d22ac40969e240',
      );
    });
  });

  group('HorizonOutput data model', () {
    test('constructor preserves all fields', () {
      const output = HorizonOutput(
        filename: 'assets/rule_scores_calibrated_short_candidate.json',
        jsonStr: '{"rules": {}}',
        sha256Hex:
            '4cac88bbb05d26fc3574b0e1fd4ae56d2a45eeeeb5f5929d61da5ef0fa5cc94f',
        ruleCount: 62,
      );

      expect(
        output.filename,
        'assets/rule_scores_calibrated_short_candidate.json',
      );
      expect(output.jsonStr, '{"rules": {}}');
      expect(output.sha256Hex.length, 64);
      expect(output.ruleCount, 62);
    });
  });
}

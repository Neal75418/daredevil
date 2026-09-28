import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_table.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/calibration_thresholds.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_scores.dart';

/// Helper: 建 happy-path JSON 字串
String _buildJson({
  int schemaVersion = 1,
  String? generatedAt = '2026-04-11T00:00:00.000Z',
  Map<String, Object?>? rules,
  Map<String, Object?> extraRootFields = const {},
}) {
  final buffer = StringBuffer('{');
  buffer.write('"schema_version": $schemaVersion');
  if (generatedAt != null) {
    buffer.write(', "generated_at": "$generatedAt"');
  }
  buffer.write(', "rules": ${_jsonEncode(rules ?? {})}');
  for (final entry in extraRootFields.entries) {
    buffer.write(', "${entry.key}": ${_jsonEncode(entry.value)}');
  }
  buffer.write('}');
  return buffer.toString();
}

String _jsonEncode(Object? value) {
  if (value == null) return 'null';
  if (value is String) return '"$value"';
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return '[${value.map(_jsonEncode).join(',')}]';
  }
  if (value is Map) {
    final entries = value.entries
        .map((e) => '"${e.key}": ${_jsonEncode(e.value)}')
        .join(', ');
    return '{$entries}';
  }
  throw ArgumentError('unsupported type: ${value.runtimeType}');
}

Map<String, Object?> _rule(
  int score, {
  double hitRate = 0.5,
  int samples = 100,
}) {
  return {'score': score, 'hit_rate': hitRate, 'samples': samples};
}

void main() {
  group('CalibratedScoresTable.parseJson [Layer 1: pure parser]', () {
    // ==================================================
    // Happy path (6 cases)
    // ==================================================

    test('1. happy_path_both_horizons_full: 62 rules fully parsed', () {
      final rules = <String, Object?>{
        for (var i = 0; i < 62; i++) 'RULE_$i': _rule(10 + i % 30),
      };
      final json = _buildJson(rules: rules);

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 62);
      expect(table.schemaVersion, 1);
      expect(table.horizon, Horizon.short);
      expect(warnings, isEmpty);
      expect(table.lookup('RULE_0'), 10);
      expect(table.lookup('RULE_30'), 10);
    });

    test('2. empty_rules_returns_empty_table', () {
      final json = _buildJson(rules: {});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(table.schemaVersion, 1);
      expect(warnings, isEmpty);
      expect(table.lookup('ANY_RULE'), isNull);
    });

    test('3. partial_rules_returns_partial_table', () {
      final json = _buildJson(
        rules: {
          'REVERSAL_W2S': _rule(28),
          'TECH_BREAKOUT': _rule(22),
          'VOLUME_SPIKE': _rule(18),
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.long,
      );

      expect(table.ruleCount, 3);
      expect(warnings, isEmpty);
      expect(table.lookup('REVERSAL_W2S'), 28);
      expect(table.lookup('TECH_BREAKOUT'), 22);
      expect(table.lookup('MISSING_RULE'), isNull);
    });

    test('4. schema_version_1_accepted', () {
      final json = _buildJson(schemaVersion: 1, rules: {});
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );
      expect(table.schemaVersion, 1);
      expect(warnings, isEmpty);
    });

    test('5. generatedAt_parsed_correctly', () {
      final json = _buildJson(
        generatedAt: '2026-04-11T12:34:56.789Z',
        rules: {},
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );
      expect(table.generatedAt, isNotNull);
      expect(table.generatedAt!.year, 2026);
      expect(table.generatedAt!.month, 4);
      expect(table.generatedAt!.day, 11);
    });

    test('6. extra_unknown_top_level_fields_ignored', () {
      final json = _buildJson(
        rules: {'REVERSAL_W2S': _rule(28)},
        extraRootFields: {
          '_note': 'This is a placeholder stub',
          'backtest': {'window_days': 504, 'train_ratio': 0.7},
          'horizon': '5d',
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('REVERSAL_W2S'), 28);
      expect(warnings, isEmpty);
    });

    // ==================================================
    // Structural errors (6 cases, scenarios 1-2d)
    // ==================================================

    test('7. malformed_json_returns_empty', () {
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        '{not valid json',
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(table.schemaVersion, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('malformed JSON'));
    });

    test('8. root_not_object_returns_empty', () {
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        '[1, 2, 3]',
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('root must be object'));
    });

    test('9. schema_version_missing_returns_empty', () {
      const json = '{"rules": {}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('schema_version missing'));
    });

    test('10. schema_version_unsupported_returns_empty', () {
      final json = _buildJson(schemaVersion: 2, rules: {});
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('unsupported schema_version: 2'));
    });

    test('11. rules_field_missing_returns_empty', () {
      const json = '{"schema_version": 1}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('rules field missing'));
    });

    test('11b. rules_wrong_type_returns_empty', () {
      const json = '{"schema_version": 1, "rules": "not a map"}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('rules must be object'));
    });

    // ==================================================
    // Calibration drift guard (3 cases)
    //
    // 比對 backtest.success_threshold_pct 與 runtime canonical
    // CalibrationThresholds.successThresholds[Horizon.tradingDays]，
    // drift > 0.01 即拒載。
    // ==================================================

    test('11c. drift_guard_metadata_matches_canonical_accepted', () {
      // short canonical = 1.5
      const json =
          '{"schema_version": 1, '
          '"backtest": {"success_threshold_pct": 1.5}, '
          '"rules": {"REVERSAL_W2S": {"score": 25}}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 1);
      expect(warnings, isEmpty);
      expect(table.lookup('REVERSAL_W2S'), 25);
    });

    test('11d. drift_guard_metadata_mismatch_short_rejected', () {
      // short canonical = 1.5, JSON declares 3.0 → reject
      const json =
          '{"schema_version": 1, '
          '"backtest": {"success_threshold_pct": 3.0}, '
          '"rules": {"REVERSAL_W2S": {"score": 25}}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('success_threshold_pct drift'));
      expect(warnings.first, contains('3.0'));
      expect(warnings.first, contains('1.5'));
    });

    test('11e. drift_guard_missing_backtest_block_passes', () {
      // 沒有 backtest block (test fixture / 早期版本)：silently 跳過 drift
      // check，因為 fixture 對結構嚴格度要求低；real production JSON 一定
      // 含 backtest block。Schema 層級的強檢留給未來 CI guard。
      const json =
          '{"schema_version": 1, '
          '"rules": {"REVERSAL_W2S": {"score": 25}}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 1);
      expect(warnings, isEmpty);
    });

    // ==================================================
    // Drift guard — excess 模式（return_mode 感知）
    //
    // excess JSON 的 success_threshold_pct 是「超額百分點」語意（canonical
    // = CalibrationThresholds.excessSuccessThreshold = 0.0），不得拿絕對
    // 門檻（1.5/8.0）誤判拒載。
    // ==================================================

    test('11f. drift_guard_excess_mode_threshold_0_accepted', () {
      const json =
          '{"schema_version": 1, '
          '"backtest": {"success_threshold_pct": 0.0, "return_mode": "excess"}, '
          '"rules": {"REVERSAL_W2S": {"score": 25}}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 1);
      expect(warnings, isEmpty);
      expect(table.lookup('REVERSAL_W2S'), 25);
    });

    test('11g. drift_guard_excess_mode_drifted_threshold_rejected', () {
      // excess canonical = 0.0，JSON 卻聲明 1.5 → 拒載（門檻語意漂移）
      const json =
          '{"schema_version": 1, '
          '"backtest": {"success_threshold_pct": 1.5, "return_mode": "excess"}, '
          '"rules": {"REVERSAL_W2S": {"score": 25}}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('success_threshold_pct drift'));
    });

    test('11h. drift_guard_absolute_mode_unchanged（return_mode 標註不影響絕對路徑）', () {
      // return_mode: absolute + 正確絕對門檻 → 照常載入
      const json =
          '{"schema_version": 1, '
          '"backtest": {"success_threshold_pct": 1.5, "return_mode": "absolute"}, '
          '"rules": {"REVERSAL_W2S": {"score": 25}}}';
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 1);
      expect(warnings, isEmpty);
    });

    // ==================================================
    // Per-rule content errors (9 cases, scenarios 5a-6b + 7)
    // ==================================================

    test('12. rule_entry_not_object_skipped', () {
      final json = _buildJson(
        rules: {
          'REVERSAL_W2S': 25, // raw int instead of object
          'TECH_BREAKOUT': _rule(22),
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('REVERSAL_W2S'), isNull);
      expect(table.lookup('TECH_BREAKOUT'), 22);
      expect(warnings.length, 1);
      expect(warnings.first, contains('REVERSAL_W2S'));
      expect(warnings.first, contains('entry not object'));
    });

    test('13. rule_score_missing_skipped', () {
      final json = _buildJson(
        rules: {
          'REVERSAL_W2S': {'hit_rate': 0.5, 'samples': 100},
          'TECH_BREAKOUT': _rule(22),
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('REVERSAL_W2S'), isNull);
      expect(table.lookup('TECH_BREAKOUT'), 22);
      expect(warnings.length, 1);
      expect(warnings.first, contains('score field missing'));
    });

    test('14. rule_score_not_numeric_skipped', () {
      final json = _buildJson(
        rules: {
          'REVERSAL_W2S': {'score': 'abc', 'hit_rate': 0.5},
          'TECH_BREAKOUT': _rule(22),
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('REVERSAL_W2S'), isNull);
      expect(table.lookup('TECH_BREAKOUT'), 22);
      expect(warnings.length, 1);
      expect(warnings.first, contains('score not numeric'));
    });

    test('14b. rule_score_fractional_rounded_with_warning', () {
      // JSON `22.7` is parsed as double. Parser should round (not truncate)
      // to avoid the asymmetric `.toInt()` behavior for negatives.
      const json =
          '{"schema_version": 1, "rules": {'
          '"FRAC_POS": {"score": 22.7},'
          '"FRAC_NEG": {"score": -22.7},'
          '"INT_AS_DOUBLE": {"score": 25.0},'
          '"PURE_INT": {"score": 10}'
          '}}';

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      // Round-half-away-from-zero: 22.7 → 23, -22.7 → -23 (symmetric)
      expect(table.lookup('FRAC_POS'), 23);
      expect(table.lookup('FRAC_NEG'), -23);
      // 25.0 equals int 25 so no rounding warning
      expect(table.lookup('INT_AS_DOUBLE'), 25);
      expect(table.lookup('PURE_INT'), 10);

      // Only two fractional entries should produce warnings
      expect(warnings.length, 2);
      expect(warnings.any((w) => w.contains('FRAC_POS')), isTrue);
      expect(warnings.any((w) => w.contains('FRAC_NEG')), isTrue);
      expect(
        warnings.first,
        anyOf(contains('rounded to 23'), contains('rounded to -23')),
      );
    });

    test('15. rule_score_above_max_clamped_to_80', () {
      final json = _buildJson(rules: {'REVERSAL_W2S': _rule(999)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('REVERSAL_W2S'), RuleScores.maxScore);
      expect(warnings.length, 1);
      expect(warnings.first, contains('999'));
      expect(warnings.first, contains('clamped to 80'));
    });

    test('16. rule_score_below_min_clamped_to_-50', () {
      final json = _buildJson(rules: {'TRADING_WARNING_DISPOSAL': _rule(-999)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.long,
      );

      expect(table.lookup('TRADING_WARNING_DISPOSAL'), RuleScores.minScore);
      expect(warnings.length, 1);
      expect(warnings.first, contains('-999'));
      expect(warnings.first, contains('clamped to -50'));
    });

    test('17. rule_score_at_boundary_not_clamped', () {
      final json = _buildJson(
        rules: {
          'REVERSAL_W2S': _rule(RuleScores.maxScore), // 80
          'TRADING_WARNING_DISPOSAL': _rule(RuleScores.minScore), // -50
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('REVERSAL_W2S'), 80);
      expect(table.lookup('TRADING_WARNING_DISPOSAL'), -50);
      expect(warnings, isEmpty);
    });

    test('18. unknown_rule_id_skipped_with_warning_when_whitelist_set', () {
      final json = _buildJson(
        rules: {'REVERSAL_W2S': _rule(28), 'FAKE_UNKNOWN_RULE': _rule(25)},
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        knownRuleIds: {'REVERSAL_W2S', 'TECH_BREAKOUT'},
      );

      expect(table.lookup('REVERSAL_W2S'), 28);
      expect(table.lookup('FAKE_UNKNOWN_RULE'), isNull);
      expect(warnings.length, 1);
      expect(warnings.first, contains('FAKE_UNKNOWN_RULE'));
      expect(warnings.first, contains('unknown ReasonType code'));
    });

    test('18b. null_whitelist_accepts_any_rule_id', () {
      // When knownRuleIds is null (Stage 5a Commit 1 default), scenario 7
      // check is skipped and any rule_id is accepted.
      final json = _buildJson(rules: {'TOTALLY_FAKE_RULE': _rule(25)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('TOTALLY_FAKE_RULE'), 25);
      expect(warnings, isEmpty);
    });

    // ==================================================
    // Mixed scenarios (2 cases)
    // ==================================================

    test('19. mixed_valid_and_invalid_rules', () {
      final json = _buildJson(
        rules: {
          'VALID_1': _rule(20),
          'VALID_2': _rule(15),
          'VALID_3': _rule(30),
          'INVALID_NOT_OBJECT': 99,
          'INVALID_NO_SCORE': {'hit_rate': 0.5},
          'INVALID_SCORE_TYPE': {'score': 'xyz'},
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 3);
      expect(table.lookup('VALID_1'), 20);
      expect(table.lookup('VALID_2'), 15);
      expect(table.lookup('VALID_3'), 30);
      expect(warnings.length, 3);
    });

    test('20. clamp_coexists_with_skip', () {
      final json = _buildJson(
        rules: {
          'VALID_IN_RANGE': _rule(25),
          'CLAMPED_HIGH': _rule(500),
          'CLAMPED_LOW': _rule(-500),
          'SKIPPED_NO_SCORE': {'hit_rate': 0.5},
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('VALID_IN_RANGE'), 25);
      expect(table.lookup('CLAMPED_HIGH'), RuleScores.maxScore);
      expect(table.lookup('CLAMPED_LOW'), RuleScores.minScore);
      expect(table.lookup('SKIPPED_NO_SCORE'), isNull);
      expect(warnings.length, 3); // 2 clamp + 1 skip
    });

    // ==================================================
    // Warning content assertions (2 cases)
    // ==================================================

    test('21. warning_messages_include_rule_id', () {
      final json = _buildJson(
        rules: {
          'MY_SPECIAL_RULE_A': {'hit_rate': 0.5}, // score missing
          'MY_SPECIAL_RULE_B': _rule(999), // clamped
          'MY_SPECIAL_RULE_C': 42, // not object
        },
      );

      final (table: _, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(warnings.length, 3);
      expect(
        warnings.where((w) => w.contains('MY_SPECIAL_RULE_A')),
        hasLength(1),
      );
      expect(
        warnings.where((w) => w.contains('MY_SPECIAL_RULE_B')),
        hasLength(1),
      );
      expect(
        warnings.where((w) => w.contains('MY_SPECIAL_RULE_C')),
        hasLength(1),
      );
    });

    test('22. warning_count_accumulates_correctly', () {
      final rules = <String, Object?>{};
      for (var i = 0; i < 20; i++) {
        rules['BAD_RULE_$i'] = {'hit_rate': 0.5}; // all missing score
      }
      final json = _buildJson(rules: rules);

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.ruleCount, 0);
      expect(warnings.length, 20); // parser does NOT cap; registry does
    });

    // ==================================================
    // Scenario 8: sign-flip warnings (L1)
    // ==================================================

    test('22a. sign_flip_bearish_rule_calibrated_positive_skipped', () {
      // **2026-06-19 contract change**：sign-flip 從「clamp to 0」改成「skip
      // 不寫入 table」，讓 lookup 找不到 → caller 回到 hardcoded fallback。
      // 原本 clamp 到 0 配合 lookup 把 0 視為「有值」會讓 hardcoded 永遠
      // fallback 不了；改成 skip 後 TECH_BREAKDOWN 從 0 → -20（hardcoded），
      // Mode C 跌破支撐重新拿到 -20。
      final json = _buildJson(rules: {'TECH_BREAKDOWN': _rule(22)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'TECH_BREAKDOWN': -20},
      );

      expect(
        table.lookup('TECH_BREAKDOWN'),
        isNull,
        reason: 'sign-flipped rule must be skipped (lookup → null → fallback)',
      );
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('TECH_BREAKDOWN'));
      expect(warnings.first, contains('sign flip'));
      expect(warnings.first, contains('skipped'));
      expect(warnings.first, contains('-20'));
      expect(warnings.first, contains('22'));
    });

    test('22b. sign_flip_bullish_rule_calibrated_negative_skipped', () {
      // 對稱 skip：bullish rule (hardcoded +18) calibrated -5 → skip 不寫入。
      final json = _buildJson(rules: {'PATTERN_HAMMER': _rule(-5)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'PATTERN_HAMMER': 18},
      );

      expect(table.lookup('PATTERN_HAMMER'), isNull);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('sign flip'));
      expect(warnings.first, contains('skipped'));
    });

    test('22c. same_sign_no_warning', () {
      final json = _buildJson(
        rules: {
          'TECH_BREAKOUT': _rule(28), // hardcoded +25, calibrated +28
          'TECH_BREAKDOWN': _rule(-15), // hardcoded -20, calibrated -15
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'TECH_BREAKOUT': 25, 'TECH_BREAKDOWN': -20},
      );

      expect(table.lookup('TECH_BREAKOUT'), 28);
      expect(table.lookup('TECH_BREAKDOWN'), -15);
      expect(warnings, isEmpty);
    });

    test('22d. zero_score_never_flagged_and_returns_null', () {
      // Zero is neutral — 不 flag sign flip。
      //
      // **2026-06-19 contract change**：lookup 對 score=0 也回 null（讓
      // caller fallback 到 hardcoded）。原本 calibrated 0 跟「沒校準」共用
      // 同一個訊號表達會讓 fallback 失效，導致 38 條 cut rule 把 hardcoded
      // 正分全覆蓋成 0。
      //
      // 寫入 table 的內容仍然是 0（schema 不變），但 lookup 把 0 視為 null。
      final json = _buildJson(
        rules: {
          'CUT_RULE': _rule(0), // calibrated 0 — typical cut rule
          'NEUTRAL_RULE': _rule(15),
        },
      );

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'CUT_RULE': -20, 'NEUTRAL_RULE': 0},
      );

      expect(warnings, isEmpty);
      // lookup 對 0 回 null（fallback signal）— 即使 _scores 內部存的是 0。
      expect(table.lookup('CUT_RULE'), isNull);
      expect(table.lookup('NEUTRAL_RULE'), 15);
      // 確認 ruleCount 仍計入 0 entry（schema 沒變）。
      expect(table.ruleCount, 2);
    });

    test('22e. hardcoded_scores_null_skips_check', () {
      // Backwards compat: callers that don't pass hardcodedScores never
      // trigger sign-flip warnings, even on obvious flips.
      final json = _buildJson(rules: {'TECH_BREAKDOWN': _rule(22)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );

      expect(table.lookup('TECH_BREAKDOWN'), 22);
      expect(warnings, isEmpty);
    });

    test('22f. unknown_rule_in_hardcoded_map_not_flagged', () {
      // A rule present in JSON but absent from hardcodedScores map skips
      // the check — avoids false positives for newly added calibrated rules
      // that haven't been registered in RuleScores yet.
      final json = _buildJson(rules: {'NEW_RULE': _rule(25)});

      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'OTHER_RULE': -10},
      );

      expect(table.lookup('NEW_RULE'), 25);
      expect(warnings, isEmpty);
    });
  });

  group('CalibratedScoresRegistry [Layer 2 + Layer 3]', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // C 方案 refactor 2026-06-19：registry 不再直接 import rootBundle，
      // test 顯式注入 loader。
      CalibratedScoresRegistry.instance.assetLoaderOverride =
          rootBundle.loadString;
    });

    tearDown(() {
      CalibratedScoresRegistry.instance.resetForTesting();
    });

    // ==================================================
    // Layer 2: asset smoke tests (2 cases)
    // ==================================================

    test('23. loadFromAssets_short_bundled_metadata_aligned', () async {
      // Bundled `rule_scores_calibrated_short.json` 現為 excess 模式
      // （return_mode: excess、success_threshold_pct 0.0），drift guard 對照
      // excess 的 canonical 放行。Hermetic excess 路徑 coverage 在 11f/11g
      // (inline fixtures)。
      //
      // **2026-06-19 contract change**：lookup 對 calibrated 0 回 null（fallback；
      // 短線負證據歸零的規則除外，回 0）。現行短線資產（2026-09 時為 44 條、
      // 2 條非零）中 REVERSAL_W2S 被 cut 且 avg_return 為正、無負證據，lookup
      // 預期 null（fallback 到 hardcoded +35）。
      await CalibratedScoresRegistry.instance.loadFromAssets();

      // load 成功 → registry 內部已有 table（rule entries 包含 0 entry 仍計入）。
      final result = CalibratedScoresRegistry.instance.lookup(
        Horizon.short,
        'REVERSAL_W2S',
      );
      expect(result, isNull, reason: 'REVERSAL_W2S 被 cut 且無負證據 → fallback');
    });

    test('24. loadFromAssets_long_bundled_metadata_aligned', () async {
      // 同 test 23，長線 JSON metadata 8.0 對齊 canonical。
      //
      // 長線 JSON 唯一 active 的 rule 是 EPS_CONSECUTIVE_GROWTH +22 — 用它
      // 驗證 lookup 正確回 calibrated 值。
      await CalibratedScoresRegistry.instance.loadFromAssets();

      final result = CalibratedScoresRegistry.instance.lookup(
        Horizon.long,
        'EPS_CONSECUTIVE_GROWTH',
      );
      expect(result, 22, reason: '長線唯一 active calibrated rule');
    });

    // ==================================================
    // Layer 3: singleton lifecycle (3 cases)
    // ==================================================

    test('25. lookup_before_load_returns_null', () {
      // resetForTesting ran in tearDown of previous test, so registry is unloaded.
      final result = CalibratedScoresRegistry.instance.lookup(
        Horizon.short,
        'REVERSAL_W2S',
      );
      expect(result, isNull);
    });

    test('26. loadFromAssets_is_idempotent', () async {
      await CalibratedScoresRegistry.instance.loadFromAssets();
      // Second and third calls should be no-ops. We verify by checking that
      // bindForTesting state is not overwritten by a subsequent load.
      CalibratedScoresRegistry.instance.bindForTesting(
        short: const CalibratedScoresTable(
          horizon: Horizon.short,
          schemaVersion: 1,
          generatedAt: null,
          scores: {'FAKE_RULE': 42},
        ),
      );
      // bindForTesting sets _loaded = true. Subsequent loadFromAssets should
      // NOT reload from assets (which would wipe the fake table).
      await CalibratedScoresRegistry.instance.loadFromAssets();
      await CalibratedScoresRegistry.instance.loadFromAssets();

      final result = CalibratedScoresRegistry.instance.lookup(
        Horizon.short,
        'FAKE_RULE',
      );
      expect(
        result,
        42,
        reason: 'idempotent load must not overwrite bound state',
      );
    });

    test(
      '26b. bindForTesting_during_pending_load_is_not_overwritten',
      () async {
        // Race condition regression test:
        // If bindForTesting runs after loadFromAssets yields but before
        // it resolves, the fake table must survive the in-flight load.
        final pending = CalibratedScoresRegistry.instance.loadFromAssets();

        CalibratedScoresRegistry.instance.bindForTesting(
          short: const CalibratedScoresTable(
            horizon: Horizon.short,
            schemaVersion: 1,
            generatedAt: null,
            scores: {'FAKE_RACE': 99},
          ),
        );

        await pending;

        expect(
          CalibratedScoresRegistry.instance.lookup(Horizon.short, 'FAKE_RACE'),
          99,
          reason: 'bindForTesting must win over a pending loadFromAssets',
        );
      },
    );

    test('27. resetForTesting_clears_state', () async {
      CalibratedScoresRegistry.instance.bindForTesting(
        short: const CalibratedScoresTable(
          horizon: Horizon.short,
          schemaVersion: 1,
          generatedAt: null,
          scores: {'REVERSAL_W2S': 28},
        ),
      );
      expect(
        CalibratedScoresRegistry.instance.lookup(Horizon.short, 'REVERSAL_W2S'),
        28,
      );

      CalibratedScoresRegistry.instance.resetForTesting();

      expect(
        CalibratedScoresRegistry.instance.lookup(Horizon.short, 'REVERSAL_W2S'),
        isNull,
      );
    });

    // ==================================================
    // Layer 4: loadWithOverride (OTA C1) — DB cache takes priority
    // ==================================================

    test(
      '28. loadWithOverride_happy_path: both JSONs parse successfully',
      () async {
        final shortJson = _buildJson(rules: {'REVERSAL_W2S': _rule(28)});
        final longJson = _buildJson(rules: {'REVERSAL_W2S': _rule(32)});

        await CalibratedScoresRegistry.instance.loadWithOverride(
          shortJsonOverride: shortJson,
          longJsonOverride: longJson,
        );

        // Override values (not hardcoded RuleScores) should be returned
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.short,
            'REVERSAL_W2S',
          ),
          28,
        );
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.long,
            'REVERSAL_W2S',
          ),
          32,
        );
      },
    );

    test('29. loadWithOverride_both_null: falls back to bundled asset', () async {
      await CalibratedScoresRegistry.instance.loadWithOverride(
        shortJsonOverride: null,
        longJsonOverride: null,
      );

      // Override 都 null → fallback 路徑走到 loadFromAssets 載入 bundled JSON。
      // 用長線唯一 active rule（EPS_CONSECUTIVE_GROWTH +22）驗證 fallback
      // 成功載入 bundled asset。
      final activeLong = CalibratedScoresRegistry.instance.lookup(
        Horizon.long,
        'EPS_CONSECUTIVE_GROWTH',
      );
      expect(activeLong, 22, reason: '長線唯一 active rule 應從 bundled asset 載入');

      // Second call should be no-op (idempotent)
      await CalibratedScoresRegistry.instance.loadWithOverride(
        shortJsonOverride:
            '{"schema_version": 1, "rules": {"X": {"score": 99}}}',
        longJsonOverride:
            '{"schema_version": 1, "rules": {"X": {"score": 99}}}',
      );
      // Should NOT have loaded the new override because _loaded is already true
      expect(
        CalibratedScoresRegistry.instance.lookup(Horizon.short, 'X'),
        isNull,
        reason: 'idempotent — second loadWithOverride must be no-op',
      );
    });

    test(
      '30. loadWithOverride_one_null: falls back to bundled asset',
      () async {
        await CalibratedScoresRegistry.instance.loadWithOverride(
          shortJsonOverride: _buildJson(rules: {'X': _rule(25)}),
          longJsonOverride: null,
        );

        // Because long override was missing, fallback path used assets,
        // which have no rule X. So X should NOT be found.
        expect(
          CalibratedScoresRegistry.instance.lookup(Horizon.short, 'X'),
          isNull,
          reason: 'atomic fallback — neither override should apply',
        );
      },
    );

    test(
      '31. loadWithOverride_malformed_short_json: falls back to assets',
      () async {
        await CalibratedScoresRegistry.instance.loadWithOverride(
          shortJsonOverride: 'not valid json {{{',
          longJsonOverride: _buildJson(rules: {'X': _rule(25)}),
        );

        // Short parse failed → empty table → fall through to asset fallback.
        // Long override was valid but atomic fallback applies to both.
        expect(
          CalibratedScoresRegistry.instance.lookup(Horizon.long, 'X'),
          isNull,
          reason: 'atomic fallback — partial override must not leak through',
        );
      },
    );

    test('32. loadWithOverride_empty_rules: falls back to assets', () async {
      // Valid schema but empty rules → ruleCount == 0 → fallback
      final emptyJson = _buildJson(rules: {});

      await CalibratedScoresRegistry.instance.loadWithOverride(
        shortJsonOverride: emptyJson,
        longJsonOverride: emptyJson,
      );

      // Empty override → fall through to bundled asset。用長線唯一 active
      // rule（EPS_CONSECUTIVE_GROWTH +22）驗證 fallback 成功。
      expect(
        CalibratedScoresRegistry.instance.lookup(
          Horizon.long,
          'EPS_CONSECUTIVE_GROWTH',
        ),
        22,
      );
    });

    test('33. loadWithOverride_idempotent: second call is no-op', () async {
      final json = _buildJson(rules: {'X': _rule(25)});

      await CalibratedScoresRegistry.instance.loadWithOverride(
        shortJsonOverride: json,
        longJsonOverride: json,
      );
      expect(CalibratedScoresRegistry.instance.lookup(Horizon.short, 'X'), 25);

      // Second call with different data should NOT overwrite
      await CalibratedScoresRegistry.instance.loadWithOverride(
        shortJsonOverride: _buildJson(rules: {'X': _rule(15)}),
        longJsonOverride: _buildJson(rules: {'X': _rule(15)}),
      );

      expect(
        CalibratedScoresRegistry.instance.lookup(Horizon.short, 'X'),
        25,
        reason: 'idempotent — second load must not overwrite',
      );
    });
  });

  group('負證據歸零 [2026-07-29 三態 lookup]', () {
    // 校準 JSON 的負證據 cut 條目(仿 production 格式)
    Map<String, Object?> negRule({
      double avg = -1.2,
      double t = -8.0,
      String cutReason = 't_stat_below_threshold',
    }) => {
      'score': 0,
      'hit_rate': 0.42,
      'samples': 50000,
      'avg_return': avg,
      't_stat': t,
      'active': false,
      'cut_reason': cutReason,
    };

    test('負證據 cut(avg<0 且 t≤門檻)在 zeroing 開啟時 lookup 回 0', () {
      final json = _buildJson(rules: {'KD_GOLDEN_CROSS': negRule()});
      final (:table, :warnings) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'KD_GOLDEN_CROSS': 15},
        applyNegativeEvidenceZeroing: true,
      );
      expect(warnings, isEmpty);
      expect(
        table.lookup('KD_GOLDEN_CROSS'),
        0,
        reason: '三態語意:負證據歸零必須生效,不得 fallback 回 hardcoded 正分',
      );
    });

    test('預設(zeroing 關閉)維持 2026-06-19 契約:cut → null fallback', () {
      final json = _buildJson(rules: {'KD_GOLDEN_CROSS': negRule()});
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
      );
      expect(table.lookup('KD_GOLDEN_CROSS'), isNull);
    });

    test('結構 gate 豁免集內的負證據規則 → null fallback(保留 hardcoded)', () {
      final json = _buildJson(rules: {'PULLBACK_TO_MA20': negRule()});
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'PULLBACK_TO_MA20': 15},
        applyNegativeEvidenceZeroing: true,
        structuralExemptions: const {'PULLBACK_TO_MA20'},
      );
      expect(
        table.lookup('PULLBACK_TO_MA20'),
        isNull,
        reason: 'Mode C 的結構定義規則豁免歸零,否則整個回檔觀察 tab 死亡',
      );
    });

    test('hit_rate cut 但 t 為正 → 不歸零(證據偏正,fallback)', () {
      final json = _buildJson(
        rules: {
          'PRICE_SPIKE': negRule(
            avg: 0.22,
            t: 3.5,
            cutReason: 'hit_rate_below_threshold',
          ),
        },
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        applyNegativeEvidenceZeroing: true,
      );
      expect(table.lookup('PRICE_SPIKE'), isNull);
    });

    test('缺 avg_return/t_stat metadata 的 cut → 保守不歸零', () {
      final json = _buildJson(rules: {'CUT_NO_META': _rule(0)});
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        applyNegativeEvidenceZeroing: true,
      );
      expect(table.lookup('CUT_NO_META'), isNull);
    });

    test('邊界:t 恰等於門檻歸零;avg 恰為 0 不歸零', () {
      final json = _buildJson(
        rules: {
          'AT_T_BOUNDARY': negRule(
            t: CalibrationThresholds.negativeEvidenceTStatMax,
          ),
          'AT_AVG_BOUNDARY': negRule(avg: 0.0, t: -8.0),
        },
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'AT_T_BOUNDARY': 15, 'AT_AVG_BOUNDARY': 15},
        applyNegativeEvidenceZeroing: true,
      );
      expect(table.lookup('AT_T_BOUNDARY'), 0);
      expect(table.lookup('AT_AVG_BOUNDARY'), isNull);
    });

    test('active 規則(score>0)不受 zeroing 影響', () {
      final json = _buildJson(
        rules: {
          'WEEK_52_HIGH': {
            'score': 35,
            'hit_rate': 0.4969,
            'samples': 32241,
            'avg_return': 0.6318,
            't_stat': 6.3424,
            'active': true,
          },
        },
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        applyNegativeEvidenceZeroing: true,
      );
      expect(table.lookup('WEEK_52_HIGH'), 35);
    });

    test('zeroedRules snapshot 暴露完整歸零集;empty() 為空集', () {
      final json = _buildJson(
        rules: {'A_NEG': negRule(), 'B_POS_T': negRule(avg: 0.2, t: 3.0)},
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'A_NEG': 15, 'B_POS_T': 15},
        applyNegativeEvidenceZeroing: true,
      );
      expect(table.zeroedSnapshot(), {'A_NEG'});
      expect(
        CalibratedScoresTable.empty(Horizon.short).zeroedSnapshot(),
        isEmpty,
      );
    });
  });

  group('負證據歸零 × 方向 gate(2026-07-29 審查 B2)', () {
    test('空方規則(hardcoded 負分)不歸零——觸發後下跌是命題被證實', () {
      final json = _buildJson(
        rules: {
          'KD_DEATH_CROSS': {
            'score': 0,
            'hit_rate': 0.4453,
            'samples': 18444,
            'avg_return': -0.9724,
            't_stat': -7.8424,
            'active': false,
            'cut_reason': 't_stat_below_threshold',
          },
        },
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'KD_DEATH_CROSS': -12},
        applyNegativeEvidenceZeroing: true,
      );
      expect(
        table.lookup('KD_DEATH_CROSS'),
        isNull,
        reason: '空方規則的 avg<0 是正證據,歸零等於拔掉實證有效的防護',
      );
      expect(table.zeroedSnapshot(), isEmpty);
    });

    test('未提供 hardcodedScores → 方向不明,保守不歸零', () {
      final json = _buildJson(
        rules: {
          'UNKNOWN_DIR': {
            'score': 0,
            'hit_rate': 0.4,
            'samples': 50000,
            'avg_return': -1.2,
            't_stat': -8.0,
            'active': false,
          },
        },
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        applyNegativeEvidenceZeroing: true,
      );
      expect(table.lookup('UNKNOWN_DIR'), isNull);
    });

    test('空方訊號的正「顯示分」不歸零(2026-07-30 WEEK_52_LOW 修正)', () {
      // WEEK_52_LOW 是 neutral 空方訊號,hardcoded +8 是顯示強度分而非
      // 多方宣稱——「hardcoded>0=多方」的判準在它身上漏接:觸發後
      // avg=-0.54(下跌)是預測正確,不是負證據。顯式排除集補上語意。
      final json = _buildJson(
        rules: {
          'WEEK_52_LOW': {
            'score': 0,
            'hit_rate': 0.30,
            'samples': 40000,
            'avg_return': -0.5433,
            't_stat': -5.524,
            'active': false,
            'cut_reason': 't_stat_below_threshold',
          },
        },
      );
      final (:table, warnings: _) = CalibratedScoresTable.parseJson(
        json,
        horizon: Horizon.short,
        hardcodedScores: const {'WEEK_52_LOW': 8},
        applyNegativeEvidenceZeroing: true,
      );
      expect(
        table.lookup('WEEK_52_LOW'),
        isNull,
        reason: '空方訊號觸發後下跌=預測正確,應 fallback 顯示 hardcoded 而非 0',
      );
      expect(table.zeroedSnapshot(), isEmpty);
    });
  });

  group('三態 lookup × isolate 傳輸線(2026-07-29 審查 B1/B3)', () {
    setUp(() => CalibratedScoresRegistry.instance.resetForTesting());
    tearDown(() => CalibratedScoresRegistry.instance.resetForTesting());

    test('snapshotForIsolate 必須攜帶歸零集(斷線=歸零在 production 靜默失效)', () {
      final registry = CalibratedScoresRegistry.instance;
      registry.bindForTesting(
        short: const CalibratedScoresTable(
          horizon: Horizon.short,
          schemaVersion: 1,
          generatedAt: null,
          scores: {'WEEK_52_HIGH': 35},
          zeroedRules: {'KD_GOLDEN_CROSS'},
        ),
      );
      final ctx = registry.snapshotForIsolate();
      expect(
        ctx.lookup(Horizon.short, 'KD_GOLDEN_CROSS'),
        0,
        reason:
            'isolate DTO 沒帶 zeroedShortRules 時,scoring 端會 fallback '
            '回 hardcoded——歸零在 production 完全不生效而測試全綠',
      );
      expect(ctx.lookup(Horizon.short, 'WEEK_52_HIGH'), 35);
    });

    test('registry.isCalibrationBacked:歸零規則不得標校準背書(UI 消費 registry 版)', () {
      final registry = CalibratedScoresRegistry.instance;
      registry.bindForTesting(
        short: const CalibratedScoresTable(
          horizon: Horizon.short,
          schemaVersion: 1,
          generatedAt: null,
          scores: {'WEEK_52_HIGH': 35},
          zeroedRules: {'KD_GOLDEN_CROSS'},
        ),
      );
      expect(registry.isCalibrationBacked('WEEK_52_HIGH'), isTrue);
      expect(
        registry.isCalibrationBacked('KD_GOLDEN_CROSS'),
        isFalse,
        reason: '歸零=校準判死;lookup 回 0(非 null),舊的 != null 判式會誤標背書',
      );
    });
  });

  group('負證據歸零 × 正式資產 [end-to-end]', () {
    setUp(() => CalibratedScoresRegistry.instance.resetForTesting());
    tearDown(() => CalibratedScoresRegistry.instance.resetForTesting());

    test('production short JSON 的歸零集組成符合政策', () async {
      final registry = CalibratedScoresRegistry.instance;
      // File I/O 而非 rootBundle:免 binding、與 CLI loader 同形態
      registry.assetLoaderOverride = (path) => File(path).readAsString();
      await registry.loadFromAssets(
        knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
        hardcodedScores: {for (final r in ReasonType.values) r.code: r.score},
      );

      final zeroed = registry.zeroedShortSnapshot();
      // 決定性負證據的代表(avg<0、|t| 大)必須在集內
      expect(zeroed, contains('KD_GOLDEN_CROSS'));
      expect(zeroed, contains('LOW_VOLUME_ACCUMULATION'));
      expect(zeroed, contains('PATTERN_GAP_UP'));
      // Mode C 結構 gate 豁免——負證據也不歸零
      expect(zeroed, isNot(contains('PULLBACK_TO_MA20')));
      expect(zeroed, isNot(contains('PULLBACK_TO_MA10')));
      expect(zeroed, isNot(contains('HAMMER_AT_SUPPORT')));
      // 正 t 的 hit_rate cut 不歸零(證據偏正)
      expect(zeroed, isNot(contains('PRICE_SPIKE')));
      expect(zeroed, isNot(contains('TECH_BREAKOUT')));
      // active 規則不歸零
      expect(zeroed, isNot(contains('WEEK_52_HIGH')));
      // 空方/防護規則(hardcoded 負分)不歸零——avg<0 是命題被證實(審查 B2)
      expect(zeroed, isNot(contains('KD_DEATH_CROSS')));
      expect(zeroed, isNot(contains('TECH_BREAKDOWN')));
      expect(zeroed, isNot(contains('REVENUE_YOY_DECLINE')));
      // 空方訊號的正「顯示分」也不歸零(2026-07-30):WEEK_52_LOW 的 +8 是
      // neutral 顯示強度,avg<0 是預測正確——顯式排除集承接
      expect(zeroed, isNot(contains('WEEK_52_LOW')));
      // 量級 sanity(2026-07-13 資產:28 負證據 −3 C gate −13 空方 ≈ 12;
      // 重校準後允許漂移但不該歸零全部)
      expect(zeroed.length, inInclusiveRange(6, 25));

      // 三態實效:歸零規則 lookup 回 0、active 回校準值、C gate fallback null
      expect(registry.lookup(Horizon.short, 'KD_GOLDEN_CROSS'), 0);
      expect(registry.lookup(Horizon.short, 'WEEK_52_HIGH'), 35);
      expect(registry.lookup(Horizon.short, 'PULLBACK_TO_MA20'), isNull);
      // long 不套用歸零
      expect(registry.lookup(Horizon.long, 'KD_GOLDEN_CROSS'), isNull);
    });
  });

  group('Horizon enum metadata', () {
    test('short has 5 trading days and 1.5% canonical threshold', () {
      expect(Horizon.short.tradingDays, 5);
      // Success threshold 已搬到 CalibrationThresholds（單一 SSOT），透過
      // tradingDays 當 key 查詢；用 enum 取代 hardcoded key 對齊本 commit
      // 立的 SSOT 慣例。
      expect(
        CalibrationThresholds.successThresholds[Horizon.short.tradingDays],
        1.5,
      );
      expect(
        Horizon.short.assetPath,
        'assets/rule_scores_calibrated_short.json',
      );
    });

    test('long has 60 trading days and 8% canonical threshold', () {
      expect(Horizon.long.tradingDays, 60);
      expect(
        CalibrationThresholds.successThresholds[Horizon.long.tradingDays],
        8.0,
      );
      expect(Horizon.long.assetPath, 'assets/rule_scores_calibrated_long.json');
    });

    test('exactly 2 values (invariant for Stage 5a/5b dual-horizon)', () {
      expect(Horizon.values.length, 2);
    });
  });

  group('registry snapshot → lookup ?? hardcoded [Layer 3.5: end-to-end]', () {
    // 2026-07-23 稽核：原本經 ReasonType.scoreFor extension 測——但 production
    // 評分實際走 snapshotForIsolate() → rule_engine 的 `lookup ?? hardcoded`
    // 路徑，extension 生產零呼叫（假保護）。測試改打正路後 extension 已刪除。
    tearDown(() {
      CalibratedScoresRegistry.instance.resetForTesting();
    });

    int scoreVia(ReasonType rt, Horizon horizon) {
      final ctx = CalibratedScoresRegistry.instance.snapshotForIsolate();
      return ctx.lookup(horizon, rt.code) ?? rt.score;
    }

    test('28. without_registry_load_uses_hardcoded', () {
      expect(
        scoreVia(ReasonType.reversalW2S, Horizon.short),
        RuleScores.reversalW2S,
      );
      expect(
        scoreVia(ReasonType.techBreakout, Horizon.long),
        RuleScores.techBreakout,
      );
    });

    test('29. with_bindForTesting_uses_calibrated', () {
      CalibratedScoresRegistry.instance.bindForTesting(
        short: const CalibratedScoresTable(
          horizon: Horizon.short,
          schemaVersion: 1,
          generatedAt: null,
          scores: {
            'REVERSAL_W2S': 42, // override hardcoded 35
            'TECH_BREAKOUT': 18, // override hardcoded 25
          },
        ),
      );

      expect(scoreVia(ReasonType.reversalW2S, Horizon.short), 42);
      expect(scoreVia(ReasonType.techBreakout, Horizon.short), 18);

      // Long horizon was not bound → fallback to hardcoded
      expect(
        scoreVia(ReasonType.reversalW2S, Horizon.long),
        RuleScores.reversalW2S,
      );
    });

    test('30. unknown_rule_in_fake_table_falls_back', () {
      CalibratedScoresRegistry.instance.bindForTesting(
        short: const CalibratedScoresTable(
          horizon: Horizon.short,
          schemaVersion: 1,
          generatedAt: null,
          scores: {'REVERSAL_W2S': 42},
        ),
      );

      expect(scoreVia(ReasonType.reversalW2S, Horizon.short), 42);
      // TECH_BREAKOUT not in table → fallback
      expect(
        scoreVia(ReasonType.techBreakout, Horizon.short),
        RuleScores.techBreakout,
      );
    });
  });
}

// Drift-prevention guardrail for calibration thresholds.
//
// Three writers stamp the rule_accuracy table (RuleAccuracyService 在 app
// runtime / replay_calibrator + recalibrate.dart 在 Stage 4 tool）。三處
// 都直接讀 `CalibrationThresholds` — 這支 test 鎖住 canonical 值，任何人
// 想偷改某一處會被擋下。
//
// tool/recalibrate.dart 以 `static const x = CalibrationThresholds.x`
// 轉引用這些常數，本測試鎖住值。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibration_thresholds.dart';

void main() {
  group('CalibrationThresholds canonical values', () {
    test('successThresholds match canonical values', () {
      // 5D / 60D 走實證 calibration 校正值（2 年市場資料下的「1σ-above-noise」)。
      // 10D / 20D 走 Stage 2 LEAN plan 原設計值，待後續實證 follow-up。
      // 改動任何值前請先更新 calibration_thresholds.dart docstring。
      expect(CalibrationThresholds.successThresholds[5], equals(1.5));
      expect(CalibrationThresholds.successThresholds[10], equals(5.0));
      expect(CalibrationThresholds.successThresholds[20], equals(8.0));
      expect(CalibrationThresholds.successThresholds[60], equals(8.0));
    });

    test('1D and 3D fall back to defaultSuccessThreshold (no entry)', () {
      // 短線雜訊大，門檻嚴反而測不出真訊號 → 1D / 3D 不列出，走 default。
      expect(CalibrationThresholds.successThresholds.containsKey(1), isFalse);
      expect(CalibrationThresholds.successThresholds.containsKey(3), isFalse);
      expect(CalibrationThresholds.defaultSuccessThreshold, equals(0.0));
    });

    test('cut thresholds match scoring overhaul plan', () {
      // Plan：hit_rate < 55% 砍 / t-stat（帶號）< 1.5 砍 / samples < 30 砍
      expect(CalibrationThresholds.hitRateCutThreshold, equals(0.55));
      expect(CalibrationThresholds.tStatCutThreshold, equals(1.5));
      expect(CalibrationThresholds.sampleSizeCutThreshold, equals(30));
    });
  });
}

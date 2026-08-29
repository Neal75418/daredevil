// Stage 5b Commit 3 — dual-horizon isolate DTO tests
//
// 驗證 [ScoringIsolateInput] / [ScoringIsolateOutput] / [IsolateReasonOutput]
// 在新增 dual-horizon 欄位後的序列化正確性。
import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Map 序列化層已於 2026-08-29 移除(效能稽核 #2,typed 直接跨界)——
  // 原本的 toMap/fromMap roundtrip 保真測試隨層作廢;可跨界性由
  // scoring_watchlist_zero_reason_test 的真 spawn sendability 測試把關。
  // 留下的是與序列化無關的行為契約。
  group('ScoringIsolateInput.calibratedScores', () {
    test('default calibratedScores is empty context', () {
      const input = ScoringIsolateInput(
        candidates: ['2330'],
        pricesMap: {'2330': []},
        newsMap: {'2330': []},
        institutionalMap: {'2330': []},
      );

      // Default 值是 empty — lookup 永遠回 null
      expect(input.calibratedScores.shortScores, isEmpty);
      expect(input.calibratedScores.longScores, isEmpty);
    });

    test('lookup:雙 horizon 各自獨立、未知 rule 回 null', () {
      const ctx = CalibratedScoreContext(
        shortScores: {'TECH_BREAKOUT': 30},
        longScores: {'TECH_BREAKOUT': 10},
      );
      expect(ctx.lookup(Horizon.short, 'TECH_BREAKOUT'), 30);
      expect(ctx.lookup(Horizon.long, 'TECH_BREAKOUT'), 10);
      expect(ctx.lookup(Horizon.short, 'UNKNOWN'), null);
    });
  });

  group('ScoringIsolateOutput dual-horizon fields', () {
    test('different horizons can hold different scores', () {
      const output = ScoringIsolateOutput(
        symbol: '2330',
        scoreShort: 80,
        scoreLong: 20, // 短線很強但長線弱
        turnover: 1000000000,
        trendState: 'UP',
        reversalState: 'NONE',
        reasons: [],
      );
      expect(output.scoreShort, isNot(equals(output.scoreLong)));
      expect(output.scoreShort, 80);
      expect(output.scoreLong, 20);
    });
  });
}

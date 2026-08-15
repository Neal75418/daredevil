// 落庫 reason 與計分 reason 的一致性(2026-08-15 數值稽核第 01 條)
//
// 舊行為:總分由 `mutedShort`(**calibrated** 分數選的 mutex 贏家)算出,
// 但落庫的 topReasons 來自 `mutedForUi`(**hardcoded** 分數選的贏家)。
// 兩者在「calibration 把某條規則歸零」時會選出不同贏家 → 落庫的那份
// 不是實際貢獻分數的那份。
//
// 而三個 mode tab 的分數、排名、門檻全都是對落庫那份做 SUM
// (analysis_dao.getModeStockScores),所以錯的那份才是使用者看到的。
//
// 真實資料實測(2026-08-14,455 檔 universe):69 檔落庫加總 ≠ 總分,
// 最大差 30 分。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/domain/models/triggered_reason.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/scoring_pipeline.dart';

// description 必須唯一——getTopReasons 依它去重(真實規則的描述天然不同)
TriggeredReason r(ReasonType t, int score) => TriggeredReason(
  type: t,
  score: score,
  description: t.code,
  evidence: const {},
);

void main() {
  final engine = RuleEngine();

  test('🚨 落庫的 reason 必須是實際貢獻分數的那份(calibrated 選的贏家)', () {
    // momentum_breakout group:volumeSpike(hardcoded 22)與
    // techBreakout(hardcoded 20)。calibration 把 volumeSpike 歸零 →
    // short 的贏家應是 techBreakout,而非 hardcoded 分數較高的 volumeSpike。
    final calibrated = CalibratedScoreContext(
      shortScores: const {},
      longScores: const {},
      zeroedShortRules: const {'VOLUME_SPIKE'},
    );
    final scored = scoreReasonsDualHorizon(
      ruleEngine: engine,
      reasons: [r(ReasonType.volumeSpike, 22), r(ReasonType.techBreakout, 20)],
      calibratedScores: calibrated,
    );
    expect(scored, isNotNull);
    final persisted = scored!.topReasons.map((x) => x.type).toSet();
    expect(
      persisted,
      contains(ReasonType.techBreakout),
      reason: 'techBreakout 是 calibrated 下的贏家,它才是實際貢獻分數的那條',
    );
    expect(
      persisted,
      isNot(contains(ReasonType.volumeSpike)),
      reason: 'volumeSpike 被 calibration 歸零、對總分零貢獻,不該落庫佔位',
    );
  });

  test('🚨 落庫 reasons 的 calibrated 加總 == scoreShort(invariant)', () {
    final calibrated = CalibratedScoreContext(
      shortScores: const {},
      longScores: const {},
      zeroedShortRules: const {'VOLUME_SPIKE'},
    );
    final scored = scoreReasonsDualHorizon(
      ruleEngine: engine,
      reasons: [
        r(ReasonType.volumeSpike, 22),
        r(ReasonType.techBreakout, 20),
        r(ReasonType.week52High, 15),
      ],
      calibratedScores: calibrated,
    );
    expect(scored, isNotNull);
    final sum = scored!.topReasons.fold<int>(
      0,
      (acc, x) =>
          acc + (calibrated.lookup(Horizon.short, x.type.code) ?? x.score),
    );
    expect(
      sum,
      scored.scoreShort,
      reason: 'mode tab 對落庫做 SUM,不等於總分就是排名建在錯的資料上',
    );
  });

  test('無 calibration 時行為不變(兩條路徑本來就同贏家)', () {
    final scored = scoreReasonsDualHorizon(
      ruleEngine: engine,
      reasons: [r(ReasonType.volumeSpike, 22), r(ReasonType.techBreakout, 20)],
      calibratedScores: CalibratedScoreContext.empty,
    );
    expect(scored, isNotNull);
    expect(
      scored!.topReasons.map((x) => x.type),
      contains(ReasonType.volumeSpike),
      reason: 'hardcoded 下 volumeSpike(22)本來就該贏',
    );
  });
}

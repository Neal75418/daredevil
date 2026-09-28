// score_validate 的 flutter test wrapper（同 run_backfill 設計；`dart run` 亦可）。
// env：CALIBRATION_DB、SCORE_SAMPLE_SIZE。
import 'package:flutter_test/flutter_test.dart';

import '../../tool/score_validate.dart' as sv;

void main() {
  test('score validate', () async {
    final code = await sv.runScoreValidateCli([]);
    expect(code, 0, reason: 'score validate 應正常完成（2=無DB）');
  }, timeout: Timeout.none);
}

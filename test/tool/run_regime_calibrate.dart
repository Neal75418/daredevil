// regime_calibrate 的 flutter test wrapper（同 run_backfill 設計；`dart run` 亦可）。
// env：CALIBRATION_DB、REGIME_SAMPLE_SIZE。
import 'package:flutter_test/flutter_test.dart';

import '../../tool/regime_calibrate.dart' as rc;

void main() {
  test('regime calibrate + 樣本外驗證', () async {
    final code = await rc.runRegimeCalibrateCli([]);
    expect(code, 0, reason: 'regime calibrate 應正常完成（2=無DB）');
  }, timeout: Timeout.none);
}

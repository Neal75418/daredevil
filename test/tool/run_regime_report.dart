// regime_report 的 flutter test wrapper（同 run_backfill 設計；`dart run` 亦可）。
// env：CALIBRATION_DB、REGIME_YEARS、REGIME_SAMPLE_SIZE、REGIME_MIN_UNIVERSE。
import 'package:flutter_test/flutter_test.dart';

import '../../tool/regime_report.dart' as rr;

void main() {
  test('regime report', () async {
    final code = await rr.runRegimeReportCli([]);
    expect(code, 0, reason: 'regime report 應正常完成（2=無DB）');
  }, timeout: Timeout.none);
}

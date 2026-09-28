// 出場條件 gate 的 flutter test wrapper（同 run_replay.dart 設計，該設計源於
// drift_flutter 拆離前；`dart run` 亦可）。
//
// env：CALIBRATION_DB（預設 tool/calibration.db）。NOT a unit test。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/exit_validate.dart' as ev;

void main() {
  test('評分改進 #3: exit validate gate', () async {
    final args = <String>[];
    final db = Platform.environment['CALIBRATION_DB'];
    if (db != null && db.isNotEmpty) {
      args.addAll(['--db', db]);
    }
    final code = await ev.runExitValidateCli(args);
    expect(code, 0, reason: '0=成功；2=無 DB（setup 問題）');
  }, timeout: Timeout.none);
}

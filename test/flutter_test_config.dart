import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/utils/device_time.dart';

import 'helpers/time_shift.dart';

/// 全域測試設定
///
/// Flutter test runner 會自動執行此檔案的 [testExecutable]。
/// 用於初始化 EasyLocalization 並抑制 `Localization key [xxx] not found` 警告，
/// 避免測試輸出被大量無關 warning 淹沒。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // 時間平移：`scripts/test_time_shift.sh N` 把 lib／tool 的「現在」往後撥
  // N 天，找出過了某天才會紅的測試（見 DeviceTime）
  DeviceTime.debugShift = timeShiftFromDefine(
    const String.fromEnvironment('TEST_TIME_SHIFT_DAYS'),
  );
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableLevels = [];

  await testMain();
}

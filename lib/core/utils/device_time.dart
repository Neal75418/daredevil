import 'package:meta/meta.dart';

/// lib／tool／bin 讀「現在」的唯一入口：裝置本地時間（與 `DateTime.now()`
/// 相同）加上測試平移。
///
/// 測試以 `scripts/test_time_shift.sh N` 把時間往後撥 N 天
/// （`test/flutter_test_config.dart` 設定 [debugShift]），找出「過了某天才會
/// 紅」的測試；不要手打 `--dart-define`，key 拼錯等於沒撥。直接讀
/// `DateTime.now()` 的地方撥不到，由 `test/core/device_time_guard_test.dart`
/// 擋下。
///
/// 要台北時間用 `TaiwanTime.now()`（由這裡換算）；能注入時鐘的地方優先用
/// `AppClock`。
///
/// 撥不到的：資料表 `withDefault(currentDateAndTime)` 由 SQLite 填當下時間
/// （例如 `UpdateRun.startedAt`）；`Isolate.run` 等新 isolate 裡 [debugShift]
/// 恆為 0（static 不跨 isolate）；`Process.run` 起的子行程。
abstract final class DeviceTime {
  /// 測試平移；production 恆為 0
  @visibleForTesting
  static Duration debugShift = Duration.zero;

  static DateTime now() => DateTime.now().add(debugShift);
}

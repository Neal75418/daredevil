import 'package:daredevil/core/utils/device_time.dart';

/// `--dart-define=TEST_TIME_SHIFT_DAYS` 的值 → 平移（沒給為 0）。
///
/// 格式錯直接丟 [FormatException]，不當成 0：靜默不平移時全套照樣綠，會被
/// 誤記成「撥了 N 天也沒有時間炸彈」。key 拼錯讀到的是空字串、這裡分辨
/// 不出來，所以撥時間跑全套一律用 `scripts/test_time_shift.sh`，不手打。
Duration timeShiftFromDefine(String raw) =>
    Duration(days: raw.isEmpty ? 0 : int.parse(raw));

/// 撥時間時略過（給 `test(skip: ...)`）；不撥時照常跑。
///
/// 只給「比較的一邊是 SQLite 填的當下時間」的測試用（例如
/// `UpdateRun.startedAt` 的 `withDefault(currentDateAndTime)`）：那邊撥不到，
/// 只要撥時間兩邊就一定不一致——不是時間炸彈。其他撥時間會紅的測試要找出
/// 原因修掉，不能用它略過。`testWidgets` 的 skip 只收 bool，要寫成
/// `skip: skipWhenTimeShifted != null`。
String? get skipWhenTimeShifted => DeviceTime.debugShift == Duration.zero
    ? null
    : 'SQLite 填的當下時間撥不到，撥時間時必然不一致（見 skipWhenTimeShifted）';

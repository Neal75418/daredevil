import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:daredevil/core/utils/device_time.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';

import '../../helpers/time_shift.dart';

void main() {
  late Duration original;
  setUp(() => original = DeviceTime.debugShift);
  tearDown(() => DeviceTime.debugShift = original);

  test(
    '測試的平移等於 --dart-define 的 TEST_TIME_SHIFT_DAYS（flutter_test_config 設定）',
    () {
      expect(
        DeviceTime.debugShift,
        timeShiftFromDefine(
          const String.fromEnvironment('TEST_TIME_SHIFT_DAYS'),
        ),
      );
    },
  );

  group('timeShiftFromDefine', () {
    test('沒給 → 不平移', () {
      expect(timeShiftFromDefine(''), Duration.zero);
    });

    test('天數 → 往後撥那麼多天（負數往前）', () {
      expect(timeShiftFromDefine('90'), const Duration(days: 90));
      expect(timeShiftFromDefine('-30'), const Duration(days: -30));
    });

    // 寫錯時若靜默當成 0，全套會在沒平移的狀態下跑完、被記成「沒有時間炸彈」
    test('格式錯直接丟例外，不當成 0', () {
      expect(() => timeShiftFromDefine('90d'), throwsFormatException);
      expect(() => timeShiftFromDefine('ninety'), throwsFormatException);
    });
  });

  test('now() 是裝置本地時間加上平移', () {
    DeviceTime.debugShift = const Duration(days: 400);
    final before = DateTime.now().add(const Duration(days: 400));
    final shifted = DeviceTime.now();
    final after = DateTime.now().add(const Duration(days: 400));

    expect(shifted.isUtc, isFalse);
    expect(shifted.isBefore(before), isFalse);
    expect(shifted.isAfter(after), isFalse);
  });

  test('TaiwanTime.now() 跟著平移', () {
    TaiwanTime.now(); // 初始化時區資料庫
    final taipei = tz.getLocation('Asia/Taipei');
    DateTime fields(DateTime t) =>
        DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

    DeviceTime.debugShift = const Duration(days: 400);
    final real = fields(tz.TZDateTime.now(taipei));
    final shifted = fields(TaiwanTime.now());

    // 兩次讀時間之間可能跨過一秒
    final diff = shifted.difference(real) - const Duration(days: 400);
    expect(diff.inSeconds, inInclusiveRange(0, 1));
  });
}

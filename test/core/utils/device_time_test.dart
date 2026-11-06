import 'dart:io';

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

  // scripts/test_time_shift.sh 另以環境變數帶同一個天數：腳本傳給 Dart 的
  // define 名稱若被改壞，平移會靜默變 0（全綠卻沒撥）——這條會紅
  test(
    '用腳本撥時間時，指定的天數真的生效',
    skip: _expectedShiftDays == null
        ? '只在用 scripts/test_time_shift.sh 跑時檢查'
        : null,
    () {
      expect(
        DeviceTime.debugShift,
        Duration(days: int.parse(_expectedShiftDays!)),
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

  group('skipWhenTimeShifted', () {
    // 永遠略過的話，用它的測試在平常的 CI 也不跑，守的行為就沒人守了
    test('沒撥時間 → 不略過', () {
      DeviceTime.debugShift = Duration.zero;
      expect(skipWhenTimeShifted, isNull);
    });

    test('撥了時間 → 略過並說明理由', () {
      DeviceTime.debugShift = const Duration(days: 30);
      expect(skipWhenTimeShifted, contains('SQLite'));
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

final _expectedShiftDays = Platform.environment['EXPECT_TIME_SHIFT_DAYS'];

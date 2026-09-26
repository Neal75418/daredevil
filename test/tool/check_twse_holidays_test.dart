import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_twse_holidays.dart';

void main() {
  group('twseClosedWeekdays', () {
    test('只取平日休市；「開始／最後交易日」是交易日、週末不列', () {
      final closed = twseClosedWeekdays([
        ['2026-01-01', '中華民國開國紀念日', ''], // 週四
        ['2026-01-02', '國曆新年開始交易日', ''], // 週五，有交易
        ['2026-02-11', '農曆春節前最後交易日', ''], // 週三，有交易
        ['2026-02-12', '市場無交易，僅辦理結算交割作業', ''], // 週四
        ['2026-02-28', '和平紀念日', ''], // 週六
      ]);
      expect(closed, {DateTime.utc(2026, 1, 1), DateTime.utc(2026, 2, 12)});
    });
  });

  // queryYear 參數會被 API 忽略、一律回今年——曾讓工具查不到尚未到來的年份
  test('以 date=<年>0101 指定年份', () {
    final uri = twseHolidayUri(2027);
    expect(uri.queryParameters['date'], '20270101');
    expect(uri.queryParameters.containsKey('queryYear'), isFalse);
  });

  group('diffHolidays', () {
    test('分別列出程式漏掉與多列的日期', () {
      final diff = diffHolidays(
        code: {DateTime.utc(2027, 2, 11), DateTime.utc(2027, 1, 1)},
        twse: {DateTime.utc(2027, 1, 1), DateTime.utc(2027, 2, 4)},
      );
      expect(diff.missingInCode, [DateTime.utc(2027, 2, 4)]);
      expect(diff.extraInCode, [DateTime.utc(2027, 2, 11)]);
    });

    test('一致時兩邊都空', () {
      final diff = diffHolidays(
        code: {DateTime.utc(2027, 1, 1)},
        twse: {DateTime.utc(2027, 1, 1)},
      );
      expect(diff.missingInCode, isEmpty);
      expect(diff.extraInCode, isEmpty);
    });
  });
}

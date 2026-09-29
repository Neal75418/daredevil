import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/calendar_month.dart';

void main() {
  group('CalendarMonth', () {
    test('tryParse 只接受 YYYY-MM', () {
      expect(CalendarMonth.tryParse('2026-09'), const CalendarMonth(2026, 9));
      for (final bad in [
        '2026-9',
        '2026-13',
        '2026-00',
        '202609',
        '2026-09-01',
        ' 2026-09',
        '2026-09 ',
        '',
      ]) {
        expect(CalendarMonth.tryParse(bad), isNull, reason: bad);
      }
    });

    test('toString 與 tryParse 互為反函式', () {
      expect(const CalendarMonth(2021, 1).toString(), '2021-01');
      expect(CalendarMonth.tryParse('2021-01').toString(), '2021-01');
    });

    test('previous 與 addMonths 跨年正確', () {
      expect(
        const CalendarMonth(2026, 1).previous,
        const CalendarMonth(2025, 12),
      );
      expect(
        const CalendarMonth(2026, 9).addMonths(-12),
        const CalendarMonth(2025, 9),
      );
      expect(
        const CalendarMonth(2026, 9).addMonths(4),
        const CalendarMonth(2027, 1),
      );
      expect(
        const CalendarMonth(2026, 9).addMonths(-69),
        const CalendarMonth(2020, 12),
      );
    });

    test('firstDay／lastDay 為當地午夜，含閏年二月', () {
      expect(const CalendarMonth(2026, 9).firstDay, DateTime(2026, 9, 1));
      expect(const CalendarMonth(2024, 2).lastDay, DateTime(2024, 2, 29));
      expect(const CalendarMonth(2025, 2).lastDay, DateTime(2025, 2, 28));
      expect(const CalendarMonth(2026, 12).lastDay, DateTime(2026, 12, 31));
    });

    test('of 取本地年月（忽略時刻）', () {
      expect(
        CalendarMonth.of(DateTime(2026, 9, 30, 23, 59)),
        const CalendarMonth(2026, 9),
      );
    });

    test('descending 含頭尾、由新到舊；from 晚於 to 回空清單', () {
      expect(
        CalendarMonth.descending(
          from: const CalendarMonth(2025, 11),
          to: const CalendarMonth(2026, 2),
        ),
        const [
          CalendarMonth(2026, 2),
          CalendarMonth(2026, 1),
          CalendarMonth(2025, 12),
          CalendarMonth(2025, 11),
        ],
      );
      expect(
        CalendarMonth.descending(
          from: const CalendarMonth(2026, 3),
          to: const CalendarMonth(2026, 2),
        ),
        isEmpty,
      );
    });

    test('同年不同月、同月不同年都不相等', () {
      expect(const CalendarMonth(2026, 9), isNot(const CalendarMonth(2026, 8)));
      expect(const CalendarMonth(2026, 9), isNot(const CalendarMonth(2025, 9)));
    });

    test('相等、雜湊與比較', () {
      expect({
        const CalendarMonth(2026, 9),
        CalendarMonth.of(DateTime(2026, 9, 5)),
      }, hasLength(1));
      expect(
        const CalendarMonth(2025, 12).compareTo(const CalendarMonth(2026, 1)),
        lessThan(0),
      );
      expect(
        const CalendarMonth(2025, 12).isBefore(const CalendarMonth(2026, 1)),
        isTrue,
      );
      expect(
        const CalendarMonth(2026, 1).isBefore(const CalendarMonth(2026, 1)),
        isFalse,
      );
      expect(
        const CalendarMonth(2026, 2).isAfter(const CalendarMonth(2026, 1)),
        isTrue,
      );
    });

    test('月份超出 1–12 時建構就擋下', () {
      expect(() => CalendarMonth(2026, 13), throwsA(isA<AssertionError>()));
    });
  });
}

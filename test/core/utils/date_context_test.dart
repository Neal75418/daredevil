import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';

void main() {
  group('DateContext', () {
    group('factory constructors', () {
      test('DateContext.now() creates context with today at midnight', () {
        // 使用台灣時區比對，避免 CI 伺服器（UTC）與台灣（UTC+8）
        // 在 00:00–08:00 UTC 期間因日期不同而 flaky
        final beforeTaiwan = TaiwanTime.today();
        final ctx = DateContext.now();
        final afterTaiwan = TaiwanTime.today();

        expect(
          ctx.today == beforeTaiwan || ctx.today == afterTaiwan,
          isTrue,
          reason: 'ctx.today should equal Taiwan today (at midnight)',
        );
        expect(ctx.today.hour, equals(0));
        expect(ctx.today.minute, equals(0));
        expect(ctx.today.second, equals(0));
      });

      test(
        'DateContext.now() creates historyStart 5 days before by default',
        () {
          final ctx = DateContext.now();

          final expectedHistoryStart = ctx.today.subtract(
            const Duration(days: 5),
          );
          expect(ctx.historyStart, equals(expectedHistoryStart));
        },
      );

      test('DateContext.now() accepts custom historyDays', () {
        final ctx = DateContext.now(historyDays: 10);

        final expectedHistoryStart = ctx.today.subtract(
          const Duration(days: 10),
        );
        expect(ctx.historyStart, equals(expectedHistoryStart));
      });

      test('DateContext.forDate() normalizes given date to midnight', () {
        final date = DateTime(2024, 6, 15, 14, 30, 45);
        final ctx = DateContext.forDate(date);

        expect(ctx.today, equals(DateTime(2024, 6, 15)));
        expect(ctx.today.hour, equals(0));
      });

      test('DateContext.forDate() sets historyStart correctly', () {
        final date = DateTime(2024, 6, 15);
        final ctx = DateContext.forDate(date, historyDays: 7);

        expect(ctx.historyStart, equals(DateTime(2024, 6, 8)));
      });

      test(
        'DateContext.withLookback() creates context with custom lookback',
        () {
          final ctx = DateContext.withLookback(30);

          final expectedHistoryStart = ctx.today.subtract(
            const Duration(days: 30),
          );
          expect(ctx.historyStart, equals(expectedHistoryStart));
        },
      );
    });

    group('normalize', () {
      test('normalizes datetime to midnight', () {
        final date = DateTime(2024, 3, 15, 10, 30, 45, 123, 456);
        final normalized = DateContext.normalize(date);

        expect(normalized.year, equals(2024));
        expect(normalized.month, equals(3));
        expect(normalized.day, equals(15));
        expect(normalized.hour, equals(0));
        expect(normalized.minute, equals(0));
        expect(normalized.second, equals(0));
        expect(normalized.millisecond, equals(0));
        expect(normalized.microsecond, equals(0));
      });

      test('normalizing already normalized date returns same value', () {
        final date = DateTime(2024, 3, 15);
        final normalized = DateContext.normalize(date);

        expect(normalized, equals(date));
      });
    });

    group('isSameDay', () {
      test('returns true for same day different times', () {
        final a = DateTime(2024, 3, 15, 10, 30);
        final b = DateTime(2024, 3, 15, 22, 45);

        expect(DateContext.isSameDay(a, b), isTrue);
      });

      test('returns false for different days', () {
        final a = DateTime(2024, 3, 15);
        final b = DateTime(2024, 3, 16);

        expect(DateContext.isSameDay(a, b), isFalse);
      });

      test('returns false for different months same day number', () {
        final a = DateTime(2024, 3, 15);
        final b = DateTime(2024, 4, 15);

        expect(DateContext.isSameDay(a, b), isFalse);
      });

      test('returns false for different years same month and day', () {
        final a = DateTime(2024, 3, 15);
        final b = DateTime(2025, 3, 15);

        expect(DateContext.isSameDay(a, b), isFalse);
      });
    });

    group('isBeforeOrEqual', () {
      test('returns true when a is before b', () {
        final a = DateTime(2024, 3, 10);
        final b = DateTime(2024, 3, 15);

        expect(DateContext.isBeforeOrEqual(a, b), isTrue);
      });

      test('returns true when a equals b (same day)', () {
        final a = DateTime(2024, 3, 15, 10, 30);
        final b = DateTime(2024, 3, 15, 22, 45);

        expect(DateContext.isBeforeOrEqual(a, b), isTrue);
      });

      test('returns false when a is after b', () {
        final a = DateTime(2024, 3, 20);
        final b = DateTime(2024, 3, 15);

        expect(DateContext.isBeforeOrEqual(a, b), isFalse);
      });
    });

    group('formatYmd', () {
      test('formats date as YYYY-MM-DD', () {
        final date = DateTime(2024, 3, 15);
        expect(DateContext.formatYmd(date), equals('2024-03-15'));
      });

      test('pads single digit month with zero', () {
        final date = DateTime(2024, 1, 15);
        expect(DateContext.formatYmd(date), equals('2024-01-15'));
      });

      test('pads single digit day with zero', () {
        final date = DateTime(2024, 12, 5);
        expect(DateContext.formatYmd(date), equals('2024-12-05'));
      });

      test('handles year with less than 4 digits', () {
        final date = DateTime(999, 1, 1);
        expect(DateContext.formatYmd(date), equals('999-01-01'));
      });
    });
  });
}

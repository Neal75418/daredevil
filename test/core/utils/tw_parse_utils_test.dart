import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/tw_parse_utils.dart';

void main() {
  group('TwParseUtils', () {
    group('parseFormattedDouble', () {
      test('parses integer string', () {
        expect(TwParseUtils.parseFormattedDouble('1234'), 1234.0);
      });

      test('parses decimal string', () {
        expect(TwParseUtils.parseFormattedDouble('123.45'), 123.45);
      });

      test('parses comma-formatted string', () {
        expect(TwParseUtils.parseFormattedDouble('1,234,567'), 1234567.0);
      });

      test('parses comma-formatted decimal', () {
        expect(TwParseUtils.parseFormattedDouble('1,234.56'), 1234.56);
      });

      test('parses negative number', () {
        expect(TwParseUtils.parseFormattedDouble('-100.5'), -100.5);
      });

      test('returns null for null', () {
        expect(TwParseUtils.parseFormattedDouble(null), isNull);
      });

      test('returns null for empty string', () {
        expect(TwParseUtils.parseFormattedDouble(''), isNull);
      });

      test('returns null for "--"', () {
        expect(TwParseUtils.parseFormattedDouble('--'), isNull);
      });

      test('returns null for "X"', () {
        expect(TwParseUtils.parseFormattedDouble('X'), isNull);
      });

      test('returns null for "---"', () {
        expect(TwParseUtils.parseFormattedDouble('---'), isNull);
      });

      test('handles whitespace', () {
        expect(TwParseUtils.parseFormattedDouble('  100  '), 100.0);
      });

      test('parses integer value directly', () {
        expect(TwParseUtils.parseFormattedDouble(42), 42.0);
      });

      test('parses double value directly', () {
        expect(TwParseUtils.parseFormattedDouble(3.14), 3.14);
      });
    });

    group('parsePrice(2026-07-30 零價 sentinel)', () {
      // TWSE 端點對「無成交」的表達不一致:MI_INDEX 用 '--'、
      // STOCK_DAY_ALL(CSV/JSON)用 '0.00'。台股價格下限 0.01,0 不可能
      // 是真值——一律視為無價(null),否則 0 會污染 52 週窗與漲跌計算
      // (實例:1472 於 2026-07-30 全日僅零股成交,close 0 → 顯示 -100%)。
      test('正常價格照常解析', () {
        expect(TwParseUtils.parsePrice('89.00'), 89.0);
        expect(TwParseUtils.parsePrice('2,205.00'), 2205.0);
      });

      test('0 與 0.00 視為無價 → null', () {
        expect(TwParseUtils.parsePrice('0.00'), isNull);
        expect(TwParseUtils.parsePrice('0'), isNull);
        expect(TwParseUtils.parsePrice(0), isNull);
        expect(TwParseUtils.parsePrice(0.0), isNull);
      });

      test('沿用 parseFormattedDouble 的無值記號', () {
        expect(TwParseUtils.parsePrice('--'), isNull);
        expect(TwParseUtils.parsePrice('X'), isNull);
        expect(TwParseUtils.parsePrice(null), isNull);
        expect(TwParseUtils.parsePrice(''), isNull);
      });
    });

    group('parseAdDate', () {
      test('parses valid YYYYMMDD date', () {
        final result = TwParseUtils.parseAdDate('20260121');

        expect(result.year, 2026);
        expect(result.month, 1);
        expect(result.day, 21);
      });

      test('parses end of month date', () {
        final result = TwParseUtils.parseAdDate('20251231');

        expect(result.year, 2025);
        expect(result.month, 12);
        expect(result.day, 31);
      });

      test('returns today for invalid length', () {
        final before = DateTime.now();
        final result = TwParseUtils.parseAdDate('2026');
        final after = DateTime.now();

        // 防止午夜跨日：result 應在 before ~ after 的日期範圍內
        expect(result.year, before.year);
        expect(result.day == before.day || result.day == after.day, isTrue);
      });

      test('returns today for empty string', () {
        final before = DateTime.now();
        final result = TwParseUtils.parseAdDate('');

        expect(result.year, before.year);
      });

      test('rejects implausibly early year (e.g. 0000-12-18 junk)', () {
        // 曾因 API 髒資料寫入 0000-12-18 等錯誤年份，現應回退到今日
        final before = DateTime.now();
        final result = TwParseUtils.parseAdDate('00001218');

        expect(result.year, before.year);
        expect(result.year, isNot(0));
      });

      test('rejects out-of-range month', () {
        final before = DateTime.now();
        final result = TwParseUtils.parseAdDate('20261318'); // month 13

        expect(result.year, before.year);
      });

      test('rejects normalized invalid day (e.g. 02/30)', () {
        // 2/30 會被 DateTime 正規化為 3/2，視為無效 → 回退今日
        final before = DateTime.now();
        final result = TwParseUtils.parseAdDate('20260230');

        expect(result.year, before.year);
        expect(result.month, isNot(3));
      });
    });

    group('parseSlashRocDate', () {
      test('parses valid ROC date "114/01/24"', () {
        final result = TwParseUtils.parseSlashRocDate('114/01/24');

        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 1);
        expect(result.day, 24);
      });

      test('parses ROC year 115', () {
        final result = TwParseUtils.parseSlashRocDate('115/06/15');

        expect(result, isNotNull);
        expect(result!.year, 2026);
        expect(result.month, 6);
        expect(result.day, 15);
      });

      test('returns null for invalid format', () {
        expect(TwParseUtils.parseSlashRocDate('2025-01-24'), isNull);
      });

      test('returns null for invalid month', () {
        expect(TwParseUtils.parseSlashRocDate('114/13/01'), isNull);
      });

      test('returns null for invalid day (Feb 30)', () {
        expect(TwParseUtils.parseSlashRocDate('114/02/30'), isNull);
      });

      test('returns null for zero month', () {
        expect(TwParseUtils.parseSlashRocDate('114/00/01'), isNull);
      });

      test('returns null for non-numeric parts', () {
        expect(TwParseUtils.parseSlashRocDate('abc/01/01'), isNull);
      });
    });

    group('parseCompactRocDate', () {
      test('parses valid compact ROC date "1140124"', () {
        final result = TwParseUtils.parseCompactRocDate('1140124');

        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 1);
        expect(result.day, 24);
      });

      test('parses "1150615"', () {
        final result = TwParseUtils.parseCompactRocDate('1150615');

        expect(result, isNotNull);
        expect(result!.year, 2026);
        expect(result.month, 6);
        expect(result.day, 15);
      });

      test('returns null for null', () {
        expect(TwParseUtils.parseCompactRocDate(null), isNull);
      });

      test('returns null for too short string', () {
        expect(TwParseUtils.parseCompactRocDate('11401'), isNull);
      });

      test('returns null for invalid date (Feb 30)', () {
        expect(TwParseUtils.parseCompactRocDate('1140230'), isNull);
      });

      test('returns null for invalid month', () {
        expect(TwParseUtils.parseCompactRocDate('1141301'), isNull);
      });
    });

    group('toRocDateString', () {
      test('converts AD to ROC format', () {
        final result = TwParseUtils.toRocDateString(DateTime(2025, 1, 24));

        expect(result, '114/01/24');
      });

      test('converts year 2026', () {
        final result = TwParseUtils.toRocDateString(DateTime(2026, 12, 31));

        expect(result, '115/12/31');
      });

      test('pads single-digit month and day', () {
        final result = TwParseUtils.toRocDateString(DateTime(2025, 3, 5));

        expect(result, '114/03/05');
      });
    });

    group('formatDateYmd', () {
      test('formats date as YYYY-MM-DD', () {
        expect(TwParseUtils.formatDateYmd(DateTime(2025, 6, 15)), '2025-06-15');
      });

      test('pads single digits', () {
        expect(TwParseUtils.formatDateYmd(DateTime(2025, 1, 5)), '2025-01-05');
      });
    });

    group('formatDateCompact', () {
      test('formats date as YYYYMMDD', () {
        expect(
          TwParseUtils.formatDateCompact(DateTime(2025, 6, 15)),
          '20250615',
        );
      });

      test('pads single digits', () {
        expect(
          TwParseUtils.formatDateCompact(DateTime(2025, 1, 5)),
          '20250105',
        );
      });
    });

    group('round-trip conversions', () {
      test('parseSlashRocDate → toRocDateString preserves date', () {
        const rocStr = '114/06/15';
        final parsed = TwParseUtils.parseSlashRocDate(rocStr);
        final formatted = TwParseUtils.toRocDateString(parsed!);

        expect(formatted, rocStr);
      });

      test('parseAdDate → formatDateCompact preserves date', () {
        const adStr = '20250615';
        final parsed = TwParseUtils.parseAdDate(adStr);
        final formatted = TwParseUtils.formatDateCompact(parsed);

        expect(formatted, adStr);
      });
    });
  });

  group('parseFormattedInt(2026-08-15 稽核:19 處土製解析只有 2 處 trim)', () {
    test('千分位、空白、哨兵一併處理', () {
      expect(TwParseUtils.parseFormattedInt('1,234'), 1234);
      expect(TwParseUtils.parseFormattedInt(' 5,678 '), 5678);
      expect(TwParseUtils.parseFormattedInt('--'), isNull);
      expect(TwParseUtils.parseFormattedInt('X'), isNull);
      expect(TwParseUtils.parseFormattedInt('---'), isNull);
      expect(TwParseUtils.parseFormattedInt(''), isNull);
      expect(TwParseUtils.parseFormattedInt(null), isNull);
    });

    test('🚨 帶空白的數字:土製版會 parse 失敗落 0,canonical 正確解析', () {
      // 這是下沉的實質價值——19 處中 17 處沒 trim
      expect(TwParseUtils.parseFormattedInt(' 1,000'), 1000);
      expect(TwParseUtils.parseFormattedDouble('  12.5  '), 12.5);
    });

    test('0 仍是合法值(不與缺值混淆)', () {
      expect(TwParseUtils.parseFormattedInt('0'), 0);
      expect(TwParseUtils.parseFormattedDouble('0.00'), 0.0);
    });
  });
}

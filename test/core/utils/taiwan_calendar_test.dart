import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/taiwan_calendar.dart';

void main() {
  group('TaiwanCalendar.isTradingDay', () {
    test('平日交易日為 true、週末為 false', () {
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 7, 13)), isTrue); // 週一
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 7, 11)), isFalse); // 週六
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 7, 12)), isFalse); // 週日
    });

    test('2025 年新增國定假日休市（教師節/光復節補假、行憲紀念日）', () {
      // 漏掉這三天曾讓 HistoricalPriceSyncer phase 0 把它們當缺漏日
      // 反覆抓到空回應（TWSE 官方無資料）觸發斷路器
      expect(TaiwanCalendar.isTradingDay(DateTime(2025, 9, 29)), isFalse);
      expect(TaiwanCalendar.isTradingDay(DateTime(2025, 10, 24)), isFalse);
      expect(TaiwanCalendar.isTradingDay(DateTime(2025, 12, 25)), isFalse);
    });

    test('2026-07-10 颱風停市（TWSE 證實 20260710 無交易資料）', () {
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 7, 10)), isFalse);
    });

    test('2026 年版新增國定假日休市', () {
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 9, 28)), isFalse);
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 10, 26)), isFalse);
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 12, 25)), isFalse);
    });

    test('既有假日維持休市（迴歸）', () {
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 2, 16)), isFalse); // 春節
      expect(TaiwanCalendar.isTradingDay(DateTime(2026, 6, 19)), isFalse); // 端午
      expect(TaiwanCalendar.isTradingDay(DateTime(2025, 10, 6)), isFalse); // 中秋
    });
  });

  // 2024-01～2026-09 以證交所每日成交資訊（FMTQIK）逐月比對實際交易日
  // （2026-09-26）：2024、2025 共錯 13 天，2026 一致
  group('2024～2025 依證交所實際交易日修正', () {
    test('春節前「市場無交易、僅結算交割」日休市', () {
      for (final d in [
        DateTime(2024, 2, 6),
        DateTime(2024, 2, 7),
        DateTime(2025, 1, 23),
        DateTime(2025, 1, 24),
      ]) {
        expect(TaiwanCalendar.isTradingDay(d), isFalse, reason: '$d');
      }
    });

    test('2024 颱風停市（凱米、山陀兒、康芮）', () {
      for (final d in [
        DateTime(2024, 7, 24),
        DateTime(2024, 7, 25),
        DateTime(2024, 10, 2),
        DateTime(2024, 10, 3),
        DateTime(2024, 10, 31),
      ]) {
        expect(TaiwanCalendar.isTradingDay(d), isFalse, reason: '$d');
      }
    });

    // 2025-10-07 被誤列為休市，缺漏偵測因此永遠不回補那天
    test('2025 誤列為休市、實際有交易的日子', () {
      for (final d in [
        DateTime(2025, 2, 3),
        DateTime(2025, 2, 4),
        DateTime(2025, 6, 2),
        DateTime(2025, 10, 7),
      ]) {
        expect(TaiwanCalendar.isTradingDay(d), isTrue, reason: '$d');
      }
    });
  });

  // 116 年（2027）依人事行政總處辦公日曆表（行政院 2026-05-21 核定，官方 Excel 逐格解析）。
  // 原本依萬年曆推估的清單錯了 10 天：漏 8 天、多列 2 天。證交所春節前
  // 另休的「無交易、僅結算交割」日要等證交所公告（見 sourceOf）。
  group('2027 依政府官方行事曆', () {
    test('平日放假日 17 天全部休市', () {
      for (final (m, d) in [
        (1, 1),
        (2, 4),
        (2, 5),
        (2, 8),
        (2, 9),
        (2, 10),
        (3, 1),
        (4, 5),
        (4, 6),
        (4, 30),
        (6, 9),
        (9, 15),
        (9, 28),
        (10, 11),
        (10, 25),
        (12, 24),
        (12, 31),
      ]) {
        expect(
          TaiwanCalendar.isTradingDay(DateTime(2027, m, d)),
          isFalse,
          reason: '2027-$m-$d',
        );
      }
    });

    test('原本多列的 2/11、10/15 要開盤', () {
      expect(TaiwanCalendar.isTradingDay(DateTime(2027, 2, 11)), isTrue);
      expect(TaiwanCalendar.isTradingDay(DateTime(2027, 10, 15)), isTrue);
    });
  });

  group('資料來源與到期提醒', () {
    test('各年份的資料來源', () {
      expect(TaiwanCalendar.sourceOf(2026), CalendarSource.twse);
      expect(TaiwanCalendar.sourceOf(2027), CalendarSource.government);
      expect(TaiwanCalendar.sourceOf(2028), isNull);
    });

    test('11 月底前、今年已是證交所確認版 → 不提醒', () {
      expect(TaiwanCalendar.coverageNotice(DateTime(2026, 11, 30, 23)), isNull);
    });

    test('12 月起下一年還不是證交所確認版 → 提醒', () {
      expect(
        TaiwanCalendar.coverageNotice(DateTime(2026, 12, 1)),
        allOf(contains('2027'), contains('證交所')),
      );
    });

    test('今年本身還不是證交所確認版 → 整年提醒', () {
      expect(
        TaiwanCalendar.coverageNotice(DateTime(2027, 3, 1)),
        contains('2027'),
      );
    });

    test('今年超出日曆涵蓋範圍 → 提醒', () {
      expect(
        TaiwanCalendar.coverageNotice(DateTime(2028, 1, 3)),
        contains('2028'),
      );
    });
  });
}

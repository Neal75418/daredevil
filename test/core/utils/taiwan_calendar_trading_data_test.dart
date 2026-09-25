import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/taiwan_calendar.dart';

/// 今日頁的「資料落後」提示要以交易日判斷：週一早上看到上週五的資料、
/// 中秋＋教師節連假後看到節前的資料，都不是過期。
void main() {
  group('expectedLatestTradingDataDate — 此刻應已有的最新收盤資料日', () {
    DateTime expected(DateTime now) =>
        TaiwanCalendar.expectedLatestTradingDataDate(now);

    test('交易日收盤資料就緒後 → 當天', () {
      expect(expected(DateTime(2026, 9, 17, 17)), DateTime(2026, 9, 17));
    });

    test('就緒時間邊界：16:00 整算當天、15:59 還不算', () {
      expect(expected(DateTime(2026, 9, 17, 16)), DateTime(2026, 9, 17));
      expect(expected(DateTime(2026, 9, 17, 15, 59)), DateTime(2026, 9, 16));
    });

    test('交易日盤中／就緒前 → 前一個交易日', () {
      expect(expected(DateTime(2026, 9, 17, 10)), DateTime(2026, 9, 16));
    });

    test('週末 → 週五', () {
      expect(expected(DateTime(2026, 9, 19, 12)), DateTime(2026, 9, 18));
    });

    test('週一早上 → 上週五', () {
      expect(expected(DateTime(2026, 9, 21, 9)), DateTime(2026, 9, 18));
    });

    test('休市日晚上（中秋 9/25）→ 前一個交易日', () {
      expect(expected(DateTime(2026, 9, 25, 20)), DateTime(2026, 9, 24));
    });

    test('連假後早上（9/25 中秋、9/28 教師節）→ 節前最後交易日', () {
      expect(expected(DateTime(2026, 9, 29, 9)), DateTime(2026, 9, 24));
    });
  });

  group('tradingDaysBehind — 資料落後幾個交易日', () {
    int behind(DateTime data, DateTime now) =>
        TaiwanCalendar.tradingDaysBehind(data, now);

    test('週一早上看上週五資料 → 0（週末不算落後）', () {
      expect(behind(DateTime(2026, 9, 18), DateTime(2026, 9, 21, 9)), 0);
    });

    test('週一收盤就緒後仍是上週五資料 → 1', () {
      expect(behind(DateTime(2026, 9, 18), DateTime(2026, 9, 21, 17)), 1);
    });

    test('🚨 連假後早上看節前資料 → 0（連假不算落後）', () {
      expect(behind(DateTime(2026, 9, 24), DateTime(2026, 9, 29, 9)), 0);
    });

    test('一整週沒更新 → 4', () {
      expect(behind(DateTime(2026, 9, 14), DateTime(2026, 9, 18, 17)), 4);
    });

    test('資料比預期還新（盤中已有當天資料）→ 0，不為負', () {
      expect(behind(DateTime(2026, 9, 17), DateTime(2026, 9, 17, 10)), 0);
    });

    test('資料日帶時間部分也不會多算', () {
      expect(
        behind(DateTime(2026, 9, 17, 8, 30), DateTime(2026, 9, 17, 17)),
        0,
      );
    });
  });
}

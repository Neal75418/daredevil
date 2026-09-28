import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/screens/comparison/utils/comparison_calculator.dart';

void main() {
  final defaultDate = DateTime(2026, 2, 13);

  DailyPriceEntry price(double close, {int daysAgo = 0}) => DailyPriceEntry(
    symbol: '2330',
    date: defaultDate.subtract(Duration(days: daysAgo)),
    open: close,
    high: close,
    low: close,
    close: close,
    volume: 50000,
  );

  group('calculatePriceReturn（帶正負號漲跌幅）', () {
    test('上漲帶 +', () {
      final r = ComparisonCalculator.calculatePriceReturn(
        [price(500, daysAgo: 1), price(550)],
        5,
        Brightness.light,
      );
      expect(r.display, '+10.0%');
    });

    test('平盤（0%）不帶 + 且配色中性（null）', () {
      final r = ComparisonCalculator.calculatePriceReturn(
        [price(600, daysAgo: 1), price(600)],
        5,
        Brightness.light,
      );
      expect(r.display, '0.0%', reason: '平盤不得帶 +');
      expect(r.color, isNull, reason: '平盤不著漲跌方向色');
    });

    test('微負值捨入歸零 → 0.0%（非 -0.0%）且配色中性', () {
      // (100.02 / 100 - 1) * 100 = 0.02% → 取一位小數捨入為 0.0%
      final r = ComparisonCalculator.calculatePriceReturn(
        [price(100, daysAgo: 1), price(100.02)],
        5,
        Brightness.light,
      );
      expect(r.display, '0.0%');
      expect(r.color, isNull);
    });
  });

  group('aggregateInstitutionalNet（帶正負號張數）', () {
    DailyInstitutionalEntry entry() => DailyInstitutionalEntry(
      symbol: '2330',
      date: defaultDate,
      foreignNet: 0,
      investmentTrustNet: 0,
      dealerNet: 0,
    );

    test('平盤（合計捨入為 0 張）不帶 + 且配色中性（null）', () {
      // total 300 股 → /1000 四捨五入為 0 張
      final r = ComparisonCalculator.aggregateInstitutionalNet(
        [entry()],
        (e) => 300.0,
        Brightness.light,
      );
      expect(r.display, '0', reason: '0 張不得帶 +');
      expect(r.color, isNull, reason: '0 張不著漲跌方向色');
    });
  });

  group('法人近 5 日取樣（與輸入順序無關）', () {
    // DAO 依日期升冪回傳，查詢窗約 10 個日曆日、通常含 6~8 個交易日；
    // 取「前 5 筆」會拿到最舊的 5 天而不是最近 5 天。
    List<DailyInstitutionalEntry> sevenDaysAscending() => [
      for (var i = 6; i >= 0; i--)
        DailyInstitutionalEntry(
          symbol: '2330',
          date: defaultDate.subtract(Duration(days: i)),
          // 越新的日子金額越大，最近 5 天 = 3000..7000 股
          foreignNet: (7 - i) * 1000.0,
          investmentTrustNet: 0,
          dealerNet: 0,
        ),
    ];

    test('aggregateInstitutionalNet 加總最近 5 天，不是最舊 5 天', () {
      final r = ComparisonCalculator.aggregateInstitutionalNet(
        sevenDaysAscending(),
        (e) => e.foreignNet ?? 0,
        Brightness.light,
      );
      // 3000+4000+5000+6000+7000 = 25000 股；最舊 5 天會是 15000
      expect(r.numeric, 25000);
    });

    test('輸入順序反過來結果相同', () {
      final r = ComparisonCalculator.aggregateInstitutionalNet(
        sevenDaysAscending().reversed.toList(),
        (e) => e.foreignNet ?? 0,
        Brightness.light,
      );
      expect(r.numeric, 25000);
    });

    test('foreignNetRadarScore 以最近 5 天外資淨買換算 0~100', () {
      // 25000 股 / 5000 萬股滿分範圍 × 50 + 50
      final score = ComparisonCalculator.foreignNetRadarScore(
        sevenDaysAscending(),
      );
      expect(score, closeTo(25000 / 50000000 * 50 + 50, 1e-9));
    });

    test('foreignNetRadarScore 無資料回中性 50', () {
      expect(ComparisonCalculator.foreignNetRadarScore(null), 50);
      expect(ComparisonCalculator.foreignNetRadarScore(const []), 50);
    });
  });
}

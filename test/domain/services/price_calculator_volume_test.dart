// calculateAverageVolume 特徵化+minValidDays 擴充(2026-08-15 審計)
//
// 背景:此 helper 此前零測試、rules 層 6 處各自 inline 重寫。接線前先
// 釘住行為;minValidDays 是為 volume_rules 兩站點(要求近 20 日至少
// N 個有效交易日)而加,預設 1 = 舊行為不變。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/price_calculator.dart';

DailyPriceEntry entry(int day, double? volume) => DailyPriceEntry(
  symbol: '2330',
  date: DateTime(2026, 1, 1).add(Duration(days: day)),
  open: 100,
  high: 101,
  low: 99,
  close: 100,
  volume: volume,
  priceChange: 0,
);

void main() {
  group('calculateAverageVolume 特徵化', () {
    test('skipLast 排除今日;取 days 日平均', () {
      final prices = [for (var i = 0; i < 6; i++) entry(i, (i + 1) * 100.0)];
      // volumes: 100..600,今日=600;skipLast 取 500,400,300,200,100
      expect(
        PriceCalculator.calculateAverageVolume(prices, days: 5, skipLast: true),
        closeTo(300, 0.001),
      );
    });

    test('filterZero 過濾停牌日(0 量);null 量視為 0 一併被濾', () {
      final prices = [
        entry(0, 200),
        entry(1, 0),
        entry(2, null),
        entry(3, 400),
        entry(4, 999), // 今日,skipLast 排除
      ];
      expect(
        PriceCalculator.calculateAverageVolume(
          prices,
          days: 4,
          skipLast: true,
          filterZero: true,
        ),
        closeTo(300, 0.001),
      );
    });

    test('資料短於 days 時退化為可用天數的均量(不回 null)', () {
      final prices = [entry(0, 100), entry(1, 300)];
      expect(
        PriceCalculator.calculateAverageVolume(prices, days: 5),
        closeTo(200, 0.001),
      );
    });

    test('全空/全被濾 → null', () {
      expect(PriceCalculator.calculateAverageVolume(const []), isNull);
      expect(
        PriceCalculator.calculateAverageVolume([
          entry(0, 0),
          entry(1, 0),
        ], filterZero: true),
        isNull,
      );
    });
  });

  group('minValidDays(volume_rules 站點需求)', () {
    test('🚨 有效日數 < minValidDays → null', () {
      final prices = [
        entry(0, 100),
        entry(1, 0),
        entry(2, 0),
        entry(3, 200),
        entry(4, 999), // 今日
      ];
      // skipLast+filterZero 後有效日只有 2(100,200)< 3 → null
      expect(
        PriceCalculator.calculateAverageVolume(
          prices,
          days: 4,
          skipLast: true,
          filterZero: true,
          minValidDays: 3,
        ),
        isNull,
      );
    });

    test('有效日數 >= minValidDays → 正常回均量;預設 1 = 舊行為', () {
      final prices = [entry(0, 100), entry(1, 0), entry(2, 200), entry(3, 999)];
      expect(
        PriceCalculator.calculateAverageVolume(
          prices,
          days: 3,
          skipLast: true,
          filterZero: true,
          minValidDays: 2,
        ),
        closeTo(150, 0.001),
      );
    });
  });
}

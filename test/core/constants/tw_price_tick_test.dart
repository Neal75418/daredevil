import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/tw_price_tick.dart';

/// 台股（上市、上櫃普通股）升降單位與漲跌停價
void main() {
  test('升降單位依價格區間', () {
    expect(TwPriceTick.tickFor(9.99), 0.01);
    expect(TwPriceTick.tickFor(10), 0.05);
    expect(TwPriceTick.tickFor(49.95), 0.05);
    expect(TwPriceTick.tickFor(50), 0.1);
    expect(TwPriceTick.tickFor(99.9), 0.1);
    expect(TwPriceTick.tickFor(100), 0.5);
    expect(TwPriceTick.tickFor(499.5), 0.5);
    expect(TwPriceTick.tickFor(500), 1);
    expect(TwPriceTick.tickFor(999), 1);
    expect(TwPriceTick.tickFor(1000), 5);
  });

  test('漲停價＝平盤價 × 1.1 往下取到升降單位', () {
    // 盟立 2464：8/3 平盤 134.5 收 147.5、8/4 平盤 147.5 收 162 都是漲停
    expect(TwPriceTick.limitPrices(134.5).up, 147.5);
    expect(TwPriceTick.limitPrices(147.5).up, 162);
    expect(TwPriceTick.limitPrices(95).up, 104.5);
    expect(TwPriceTick.limitPrices(9.5).up, 10.45);
    expect(TwPriceTick.limitPrices(40).up, 44);
    // 91 × 1.1＝100.1 跨進 0.5 的區間 → 100
    expect(TwPriceTick.limitPrices(91).up, 100);
  });

  test('跌停價＝平盤價 × 0.9 往上取到升降單位', () {
    // 11/20 南亞 1303 平盤 228.5 收 206、奇鋐 3017 平盤 2445 收 2205
    expect(TwPriceTick.limitPrices(228.5).down, 206);
    expect(TwPriceTick.limitPrices(2445).down, 2205);
    expect(TwPriceTick.limitPrices(40).down, 36);
    // 111 × 0.9＝99.9 本身是合法價位；111.5 × 0.9＝100.35 落在 0.5 的區間
    expect(TwPriceTick.limitPrices(111).down, 99.9);
    expect(TwPriceTick.limitPrices(111.5).down, 100.5);
  });
}

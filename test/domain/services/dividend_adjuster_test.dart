// 除權息還原（DividendAdjuster）：日期 d 的開高低收乘上所有
// d < 除權息日 ≤ asOf 事件的因子（除權息參考價 ÷ 除權息前收盤）
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_adjuster.dart';

DailyPriceEntry _bar(DateTime date, double close) => DailyPriceEntry(
  symbol: 'T',
  date: date,
  open: close,
  high: close + 1,
  low: close - 1,
  close: close,
  volume: 1000,
  priceChange: 0.5,
);

DividendPriceEvent _event(DateTime exDate, double close, double reference) =>
    DividendPriceEvent(
      exDate: exDate,
      closeBefore: close,
      referencePrice: reference,
    );

void main() {
  final d14 = DateTime(2026, 9, 14);
  final d15 = DateTime(2026, 9, 15);
  final d16 = DateTime(2026, 9, 16);
  final d17 = DateTime(2026, 9, 17);

  group('交易所實例：除權息前一天的收盤還原後等於除權息參考價', () {
    // 前收盤就是除權息前一天的收盤，因子＝參考價 ÷ 前收盤
    for (final (name, close, reference) in [
      ('純現金 2330 2026-09-16', 2385.0, 2377.99),
      ('配股 6669 2026-09-02（每千股 1,982.8 股）', 7800.0, 2614.99),
      ('只有現金增資 3149 2026-07-17', 93.5, 86.68),
    ]) {
      test(name, () {
        final prices = [
          _bar(d14, close),
          _bar(d15, close),
          _bar(d16, reference),
        ];

        final adjusted = DividendAdjuster.adjust(prices, [
          _event(d16, close, reference),
        ], asOf: d16);

        expect(adjusted[0].close, closeTo(reference, 1e-9));
        expect(adjusted[1].close, closeTo(reference, 1e-9));
        expect(adjusted[2].close, reference, reason: '除權息當天已是除權息後，不調整');
      });
    }
  });

  test('多次除權息：較舊的日子乘上之後每一次的因子', () {
    final prices = [_bar(d14, 100), _bar(d15, 90), _bar(d16, 81)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d15, 100, 90),
      _event(d16, 90, 81),
    ], asOf: d16);

    expect(adjusted[0].close, closeTo(81, 1e-9));
    expect(adjusted[1].close, closeTo(81, 1e-9));
    expect(adjusted[2].close, 81);
  });

  test('開高低收都調整；成交量、漲跌價差、代號與日期不動；缺值維持 null', () {
    final prices = [
      DailyPriceEntry(
        symbol: 'T',
        date: d14,
        high: 110,
        close: 100,
        volume: 5000,
        priceChange: 2,
      ),
      _bar(d15, 90),
    ];

    final p = DividendAdjuster.adjust(prices, [
      _event(d15, 100, 90),
    ], asOf: d15).first;

    expect(p.open, isNull);
    expect(p.high, closeTo(99, 1e-9));
    expect(p.low, isNull);
    expect(p.close, closeTo(90, 1e-9));
    expect(
      (p.symbol, p.date, p.volume, p.priceChange),
      ('T', d14, 5000.0, 2.0),
    );
  });

  test('🚨 評分日之後的事件不套用（換日回退不得前視）', () {
    final prices = [_bar(d14, 100), _bar(d15, 100)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d16, 100, 90),
    ], asOf: d15);

    expect(adjusted, same(prices));
  });

  test('除權息日帶時刻：以日期比較（評分日當天的事件照套、除權息當天不調整）', () {
    final prices = [_bar(d15, 100), _bar(d16, 90)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(DateTime(2026, 9, 16, 8), 100, 90),
    ], asOf: d16);

    expect(adjusted[0].close, closeTo(90, 1e-9));
    expect(adjusted[1].close, 90);
  });

  test('因子大於 1（認購價高於市價的現金增資）：較舊的價格往上調', () {
    final prices = [_bar(d14, 50), _bar(d15, 52.5)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d15, 50, 52.5),
    ], asOf: d15);

    expect(adjusted[0].close, closeTo(52.5, 1e-9));
  });

  test('停牌期間除權息：停牌前的價格照樣還原，停牌列維持 null', () {
    final prices = [
      _bar(d14, 100),
      DailyPriceEntry(symbol: 'T', date: d15),
      _bar(d17, 90),
    ];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d16, 100, 90),
    ], asOf: d17);

    expect(adjusted[0].close, closeTo(90, 1e-9));
    expect(adjusted[1].close, isNull);
    expect(adjusted[2].close, 90);
  });

  test('不受任何事件影響的日子沿用原物件；沒有要套用的事件時回傳原序列', () {
    final prices = [_bar(d14, 100), _bar(d15, 90), _bar(d16, 90)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d15, 100, 90),
    ], asOf: d16);

    expect(adjusted[1], same(prices[1]));
    expect(adjusted[2], same(prices[2]));
    expect(DividendAdjuster.adjust(prices, const [], asOf: d16), same(prices));
  });
}

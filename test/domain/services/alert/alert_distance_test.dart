import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/alert/alert_distance.dart';

/// 價位提醒距現價多遠(2026-10-06,路線圖第 2 項)。
void main() {
  test('目標在現價之下 → 負值:股價再跌多少 % 才觸發', () {
    expect(AlertDistance.percent(target: 98, price: 100), closeTo(-2.0, 1e-9));
  });

  test('目標在現價之上 → 正值:股價再漲多少 % 才觸發', () {
    expect(AlertDistance.percent(target: 105, price: 100), closeTo(5.0, 1e-9));
  });

  test('🚨 以現價為分母(股價要動多少),不是以目標價', () {
    // 目標 90、現價 100:股價要跌 10%;若以目標為分母會變成 11.1%
    expect(AlertDistance.percent(target: 90, price: 100), closeTo(-10.0, 1e-9));
  });

  test('沒有現價或現價不合理 → null', () {
    expect(AlertDistance.percent(target: 98, price: null), isNull);
    expect(AlertDistance.percent(target: 98, price: 0), isNull);
  });

  test('已達到:向上型現價 ≥ 目標、向下型現價 ≤ 目標', () {
    expect(
      AlertDistance.isReached(upward: true, target: 105, price: 105),
      isTrue,
    );
    expect(
      AlertDistance.isReached(upward: true, target: 105, price: 104.9),
      isFalse,
    );
    expect(
      AlertDistance.isReached(upward: false, target: 98, price: 98),
      isTrue,
    );
    expect(
      AlertDistance.isReached(upward: false, target: 98, price: 98.1),
      isFalse,
    );
  });
}

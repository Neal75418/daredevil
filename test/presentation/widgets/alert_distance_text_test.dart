import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/widgets/alert_distance_text.dart';

PriceAlertEntry _alert({
  String type = 'BELOW',
  double target = 98,
  bool active = true,
  DateTime? triggeredAt,
}) => PriceAlertEntry(
  id: 1,
  symbol: '2330',
  alertType: type,
  targetValue: target,
  isActive: active,
  triggeredAt: triggeredAt,
  createdAt: DateTime(2026, 10, 6),
);

/// 價位提醒的距離文字(2026-10-06,路線圖第 2 項)。
void main() {
  test('快捷鈕:一位小數帶正負號;已越過或沒有現價 → null', () {
    expect(
      AlertDistanceText.percent(upward: false, target: 98, price: 100),
      '-2.0%',
    );
    expect(
      AlertDistanceText.percent(upward: true, target: 105, price: 100),
      '+5.0%',
    );
    expect(
      AlertDistanceText.percent(upward: false, target: 98, price: 97),
      isNull,
    );
    expect(
      AlertDistanceText.percent(upward: false, target: 98, price: null),
      isNull,
    );
  });

  test('🚨 已掛提醒:啟用中、未觸發的價位型才顯示;已越過顯示「已達到」', () {
    expect(
      AlertDistanceText.forAlert(_alert(), 100),
      'alert.distanceFromPrice',
    );
    expect(AlertDistanceText.forAlert(_alert(), 97), 'alert.reached');
    expect(
      AlertDistanceText.forAlert(_alert(type: 'ABOVE', target: 105), 100),
      'alert.distanceFromPrice',
    );
  });

  test('🚨 不是價位型、已停用、已觸發、沒有現價 → 不顯示', () {
    expect(AlertDistanceText.forAlert(_alert(type: 'CHANGE_PCT'), 100), isNull);
    expect(
      AlertDistanceText.forAlert(_alert(type: 'RSI_OVERSOLD'), 100),
      isNull,
    );
    expect(AlertDistanceText.forAlert(_alert(active: false), 100), isNull);
    expect(
      AlertDistanceText.forAlert(
        _alert(triggeredAt: DateTime(2026, 10, 6, 10)),
        100,
      ),
      isNull,
    );
    expect(AlertDistanceText.forAlert(_alert(), null), isNull);
  });
}

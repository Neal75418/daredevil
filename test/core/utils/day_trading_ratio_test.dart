import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/day_trading_ratio.dart';

void main() {
  test('一般情況：當沖股數 ÷ 成交量 × 100', () {
    expect(computeDayTradingRatio(tradeVolume: 250, totalVolume: 1000), 25.0);
  });

  test('超過上限夾到 dayTradingMaxValidRatio', () {
    expect(
      computeDayTradingRatio(tradeVolume: 3000, totalVolume: 1000),
      DataFreshness.dayTradingMaxValidRatio,
    );
  });

  test('分母缺失或為 0 → null（由呼叫端決定寫 0、保留或跳過）', () {
    expect(computeDayTradingRatio(tradeVolume: 10, totalVolume: null), isNull);
    expect(computeDayTradingRatio(tradeVolume: 10, totalVolume: 0), isNull);
    expect(computeDayTradingRatio(tradeVolume: null, totalVolume: 100), isNull);
  });

  test('負值夾到 0', () {
    expect(computeDayTradingRatio(tradeVolume: -5, totalVolume: 100), 0.0);
  });
}

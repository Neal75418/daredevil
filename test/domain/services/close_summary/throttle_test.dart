import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/close_summary/throttle.dart';

import 'close_summary_fixtures.dart';

/// 每天加 1 的上升序列（不會收破 5 日門檻），再把 [dips] 指定的位置壓到 50
List<double> _risingWithDips(int length, Set<int> dips) => [
  for (var i = 0; i < length; i++) dips.contains(i) ? 50.0 : 100.0 + i,
];

void main() {
  group('readThrottle 狀態', () {
    test('收盤低於前 4 日平均 → 空手', () {
      final reading = readThrottle(taiexFrom([...repeat(100, 20), 99]))!;
      expect(reading.state, ThrottleState.flat);
      expect(reading.threshold, 100);
    });

    test('守住門檻但收在月線下 → 小量', () {
      // 門檻＝90；月線＝(15×110＋4×90＋95)/20＝105.25
      final reading = readThrottle(
        taiexFrom([...repeat(110, 16), ...repeat(90, 4), 95]),
      )!;
      expect(reading.state, ThrottleState.reduced);
      expect(reading.ma20, 105.25);
      expect(reading.close, 95);
    });

    test('收盤等於門檻與月線 → 全開，不算收破', () {
      final reading = readThrottle(taiexFrom(repeat(100, 21)))!;
      expect(reading.state, ThrottleState.full);
      expect(reading.lastBreakDate, isNull);
    });

    test('少於 21 筆 → null', () {
      expect(readThrottle(taiexFrom(repeat(100, 20))), isNull);
    });
  });

  group('最近一次收破 5 日門檻', () {
    test('收破兩次時取較近的一次', () {
      // 30 筆：第 −10 根與第 −3 根各收破一次
      final rows = taiexFrom(_risingWithDips(30, {19, 26}));
      final reading = readThrottle(rows)!;
      expect(reading.lastBreakDate, rows[26].date);
      expect(reading.tradingDaysSinceBreak, 3);
    });

    test('資料日當天收破 → 資料日、0 天', () {
      final rows = taiexFrom(_risingWithDips(30, {29}));
      final reading = readThrottle(rows)!;
      expect(reading.lastBreakDate, rows[29].date);
      expect(reading.tradingDaysSinceBreak, 0);
    });

    test('第 5 筆（第一個有門檻可比的）收破也查得到', () {
      final rows = taiexFrom(_risingWithDips(30, {4}));
      final reading = readThrottle(rows)!;
      expect(reading.lastBreakDate, rows[4].date);
      expect(reading.tradingDaysSinceBreak, 25);
    });

    test('整段都沒收破 → null，並回報查了幾個交易日', () {
      final reading = readThrottle(taiexFrom(_risingWithDips(30, {})))!;
      expect(reading.lastBreakDate, isNull);
      expect(reading.tradingDaysSinceBreak, isNull);
      // 前 4 筆沒有門檻可比，查得到的是第 5 筆起的 26 天
      expect(reading.lookbackTradingDays, 26);
    });
  });
}

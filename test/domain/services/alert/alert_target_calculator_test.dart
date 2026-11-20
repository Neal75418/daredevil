import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/alert/alert_target_calculator.dart';

/// 提醒觸發價計算(2026-08-07)。
///
/// 契約:app 只負責「把價位算好」,使用者點哪個由他自己決定。
/// 守門價採 **2.0×ATR(20)**——2026-08-07 回測定案的 k 值(見 v3.3 §4.1):
/// 固定 % 的停損落在飆股單日噪音內,被洗率 55.9%;2.0×ATR 降到 18.9%。
void main() {
  /// 造 n 根日線:收盤等距上升,每日高低差固定 range
  List<Ohlc> bars(
    int n, {
    double start = 100,
    double step = 1,
    double range = 4,
  }) {
    return [
      for (var i = 0; i < n; i++)
        Ohlc(
          high: start + i * step + range / 2,
          low: start + i * step - range / 2,
          close: start + i * step,
        ),
    ];
  }

  group('均線類觸發價', () {
    test('跌破 5MA/10MA/20MA:價位=該均線,方向向下', () {
      final t = AlertTargetCalculator.compute(bars(30));
      // 收盤 100,101,...129;5MA=(125..129)/5=127
      expect(t[AlertKind.breakBelowMa5]!.price, closeTo(127, 1e-9));
      expect(t[AlertKind.breakBelowMa5]!.isUpward, isFalse);
      expect(t[AlertKind.breakBelowMa10]!.price, closeTo(124.5, 1e-9));
      expect(t[AlertKind.breakBelowMa20]!.price, closeTo(119.5, 1e-9));
      expect(t[AlertKind.breakBelowMa20]!.isUpward, isFalse);
    });

    test('突破月線:同樣是 20MA 但方向向上(回榜資格訊號)', () {
      final t = AlertTargetCalculator.compute(bars(30));
      expect(t[AlertKind.breakAboveMa20]!.price, closeTo(119.5, 1e-9));
      expect(t[AlertKind.breakAboveMa20]!.isUpward, isTrue);
    });
  });

  test('突破 20 日高=結構 C 觸發線,取近 20 根的最高價、向上', () {
    final t = AlertTargetCalculator.compute(bars(30));
    // 近 20 根(index 10..29)最高 = 129+2 = 131
    expect(t[AlertKind.breakAbove20DayHigh]!.price, closeTo(131, 1e-9));
    expect(t[AlertKind.breakAbove20DayHigh]!.isUpward, isTrue);
  });

  test('🚨 守門價 = 最新收盤 − 2.0×ATR(20),向下(v3.3 §4.1 的 k)', () {
    final b = bars(30, range: 4); // 每日 TR 固定 4(高低差)…含前收缺口後仍為 4~5
    final t = AlertTargetCalculator.compute(b);
    final gate = t[AlertKind.stopGate]!;
    expect(gate.isUpward, isFalse);
    // 此 fixture 每根 TR 恆為 4(高低差 4、缺口 1)→ ATR(20)=4.0 精確。
    // **必須斷言精確值**:2026-08-08 變異測試證明,原本的 3.5~5.5 區間
    // 容忍 k∈[1.75,2.75],把 k 從回測定案的 2.0 改成 2.5 測試照樣全綠
    // ——那等於這條「k=2.0」的守門完全沒有守。
    expect(gate.price, closeTo(129 - 2.0 * 4.0, 1e-9));
  });

  test('資料不足 20 根 → 只給算得出來的,不硬湊', () {
    final t = AlertTargetCalculator.compute(bars(8));
    expect(t.containsKey(AlertKind.breakBelowMa5), isTrue);
    expect(t.containsKey(AlertKind.breakBelowMa10), isFalse);
    expect(t.containsKey(AlertKind.breakBelowMa20), isFalse);
    expect(t.containsKey(AlertKind.stopGate), isFalse);
  });

  test('空資料 → 空 map,不拋例外', () {
    expect(AlertTargetCalculator.compute(const []), isEmpty);
  });

  test('方向對應既有警示系統的 alertType(不自建判定邏輯)', () {
    final t = AlertTargetCalculator.compute(bars(30));
    expect(t[AlertKind.breakBelowMa10]!.alertTypeValue, 'BELOW');
    expect(t[AlertKind.breakAboveMa20]!.alertTypeValue, 'ABOVE');
    expect(t[AlertKind.stopGate]!.alertTypeValue, 'BELOW');
  });

  test('🚨 順序契約:最後一筆必須是最新——反了會用到最舊的幾根算均線', () {
    // 2026-08-07 實機 bug:priceHistory 是升冪(最舊在前),接線處卻多
    // reversed 一次 → 5MA 用最舊 5 根算,緯創現價 183.5 卻顯示 122.8、
    // 「20 日高」128.0 低於現價(數學上不可能)。此測試鎖住方向。
    final ascending = bars(30); // close 100..129,最後一筆最新
    final t = AlertTargetCalculator.compute(ascending);
    final latestClose = ascending.last.close; // 129

    expect(
      t[AlertKind.breakBelowMa5]!.price,
      greaterThan(latestClose - 5),
      reason: '5MA 應貼近最新價,不是幾十元外的舊價',
    );
    expect(
      t[AlertKind.breakAbove20DayHigh]!.price,
      greaterThanOrEqualTo(latestClose),
      reason: '20 日高不可能低於最新收盤',
    );
    expect(t[AlertKind.stopGate]!.price, lessThan(latestClose));
    expect(
      t[AlertKind.stopGate]!.price,
      greaterThan(latestClose * 0.7),
      reason: '守門價應在最新價下方合理範圍,不是舊價區',
    );
  });

  test('simpleAtr:最後 period 根 True Range(含跳空)的簡單平均', () {
    // 22 根:第 1 根高低差 80、在窗外(第 0 根只提供它的前收);
    // 第 2..21 根(窗內 20 根)預設高低 101/99、收 100 → TR 2,
    // 第 10 根跳空上漲(前收 100、高 112、低 108、收 110)→ TR=最高−前收=12,
    // 第 11 根跳空下跌(前收 110、高 96、低 94、收 95)→ TR=前收−最低=16。
    final input = <Ohlc>[
      const Ohlc(high: 101, low: 99, close: 100),
      const Ohlc(high: 140, low: 60, close: 100),
      for (var i = 2; i <= 21; i++)
        switch (i) {
          10 => const Ohlc(high: 112, low: 108, close: 110),
          11 => const Ohlc(high: 96, low: 94, close: 95),
          12 => const Ohlc(high: 101, low: 99, close: 100), // 前收 95:TR=6
          _ => const Ohlc(high: 101, low: 99, close: 100),
        },
    ];
    // 窗內 20 根:17 根 TR 2、加 12、16、6 → (34+12+16+6)/20 = 3.4
    expect(AlertTargetCalculator.simpleAtr(input, 20), closeTo(3.4, 1e-4));
    expect(
      AlertTargetCalculator.simpleAtr(input.sublist(0, 20), 20),
      isNull,
      reason: '要 period + 1 根才有前一根收盤',
    );
  });
}

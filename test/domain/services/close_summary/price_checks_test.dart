import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/close_summary/price_checks.dart';

import 'close_summary_fixtures.dart';

/// 前 20 根由 100 每根加 1 到 119，第 21 根是 [last]
List<double> _risingThen(double last) => [
  for (var i = 0; i < 20; i++) 100.0 + i,
  last,
];

void main() {
  group('checkStrongList', () {
    test('20 日漲幅恰好 15% 不算通過，超過才算', () {
      final exact = checkStrongList(barsFrom([100, ...repeat(100, 19), 115]));
      expect(exact.ret20, CheckOutcome.fail);

      final above = checkStrongList(
        barsFrom([100, ...repeat(100, 19), 115.01]),
      );
      expect(above.ret20, CheckOutcome.pass);
    });

    test('近 20 根有一根漲停才通過；漲停在第 21 根不算', () {
      // 第 21 根（資料日）漲 10%
      final inWindow = checkStrongList(barsFrom([...repeat(100, 20), 110]));
      expect(inWindow.limitUpIn20, CheckOutcome.pass);

      // 漲停在第 2 根，是資料日往回數的第 21 根
      final outOfWindow = checkStrongList(
        barsFrom([100, 110, ...repeat(110, 20)]),
      );
      expect(outOfWindow.limitUpIn20, CheckOutcome.fail);
    });

    test('收在升降單位算出的漲停價也算漲停（只漲 9.665%）', () {
      // 平盤 134.5 的漲停價是 147.5
      final check = checkStrongList(barsFrom([...repeat(134.5, 20), 147.5]));
      expect(check.limitUpIn20, CheckOutcome.pass);
    });

    test('ETF（00 開頭）的升降單位不同，退回用漲跌幅推算', () {
      final check = checkStrongList(
        barsFrom([...repeat(134.5, 20), 147.5], symbol: '0050'),
      );
      expect(check.limitUpIn20, CheckOutcome.fail);
    });

    test('20 日均量恰好 3,000,000 股不算通過', () {
      final volumes = {for (var i = 0; i < 21; i++) i: 3000000.0};
      final exact = checkStrongList(
        barsFrom(repeat(100, 21), volumes: volumes),
      );
      expect(exact.avgVolume20, CheckOutcome.fail);

      final above = checkStrongList(
        barsFrom(
          repeat(100, 21),
          volumes: {for (var i = 0; i < 21; i++) i: 3000001.0},
        ),
      );
      expect(above.avgVolume20, CheckOutcome.pass);
    });

    test('20 日均量只算最後 20 根', () {
      // 第 2 根（往回第 20 根）1 億股、之後都 0：20 根平均 5,000,000
      final lastTwenty = checkStrongList(
        barsFrom(
          repeat(100, 21),
          volumes: {1: 100000000, for (var i = 2; i < 21; i++) i: 0},
        ),
      );
      expect(lastTwenty.avgVolume20, CheckOutcome.pass);

      // 第 1 根（往回第 21 根）1 億股不算進來
      final outside = checkStrongList(
        barsFrom(
          repeat(100, 21),
          volumes: {0: 100000000, for (var i = 1; i < 21; i++) i: 3000000},
        ),
      );
      expect(outside.avgVolume20, CheckOutcome.fail);
    });

    test('20 根裡有一天沒有成交量 → 均量資料不足', () {
      final check = checkStrongList(
        barsFrom(repeat(100, 21), nullVolumes: {10}),
      );
      expect(check.avgVolume20, CheckOutcome.insufficient);
    });

    test('收盤等於 20 日均線不算站上', () {
      final check = checkStrongList(barsFrom(repeat(100, 21)));
      expect(check.aboveMa20, CheckOutcome.fail);
    });

    // 21 根：100 → 漲停 → 一路到 120；收在月線上
    final strongCloses = [
      100.0,
      110.0,
      for (var i = 0; i < 18; i++) 110.0 + i * 0.5,
      120.0,
    ];

    test('四條件都過才 allPassed，passed 數通過的條數', () {
      final check = checkStrongList(barsFrom(strongCloses));
      expect(check.ret20, CheckOutcome.pass);
      expect(check.limitUpIn20, CheckOutcome.pass);
      expect(check.avgVolume20, CheckOutcome.pass);
      expect(check.aboveMa20, CheckOutcome.pass);
      expect(check.passed, 4);
      expect(check.allPassed, isTrue);
    });

    test('只過 3 條 → passed 3、不算 allPassed', () {
      final check = checkStrongList(
        barsFrom(
          strongCloses,
          volumes: {for (var i = 0; i < 21; i++) i: 3000000.0},
        ),
      );
      expect(check.avgVolume20, CheckOutcome.fail);
      expect(check.passed, 3);
      expect(check.allPassed, isFalse);
    });

    test('少於 21 根：四條件都是資料不足，不計入通過數', () {
      final check = checkStrongList(barsFrom(repeat(100, 20)));
      expect(check.ret20, CheckOutcome.insufficient);
      expect(check.limitUpIn20, CheckOutcome.insufficient);
      expect(check.avgVolume20, CheckOutcome.insufficient);
      expect(check.aboveMa20, CheckOutcome.insufficient);
      expect(check.passed, 0);
      expect(check.allPassed, isFalse);
    });
  });

  group('maSideStreak', () {
    test('最後 3 根都收在各自的 20 日均線下 → −3', () {
      expect(maSideStreak(barsFrom([...repeat(100, 20), 90, 90, 90])), -3);
    });

    test('最後一根剛站上 → 1', () {
      expect(maSideStreak(barsFrom([...repeat(100, 20), 90, 90, 110])), 1);
    });

    test('最後一根恰好等於 20 日均線算在上方', () {
      // 資料日 100：最後 20 根＝17×102＋83＋83＋100，平均恰好 100
      expect(maSideStreak(barsFrom([...repeat(102, 21), 83, 83, 100])), 1);
    });

    test('不足 20 根 → 0', () {
      expect(maSideStreak(barsFrom(repeat(100, 19))), 0);
    });
  });

  group('crossedBelowMa', () {
    test('前一日等於均線、資料日收在均線下 → true', () {
      expect(crossedBelowMa(barsFrom([...repeat(100, 20), 90])), isTrue);
    });

    test('兩日都在均線下 → false', () {
      expect(crossedBelowMa(barsFrom([...repeat(100, 20), 90, 90])), isFalse);
    });
  });

  group('structureC', () {
    final highs = {for (var i = 0; i < 20; i++) i: 105.0};

    test('收盤高於之前 20 根的最高價 → true', () {
      expect(
        structureC(barsFrom([...repeat(100, 20), 106], highs: highs)),
        isTrue,
      );
    });

    test('只高於之前的最高收盤、沒高於最高價 → false', () {
      expect(
        structureC(barsFrom([...repeat(100, 20), 104], highs: highs)),
        isFalse,
      );
    });

    test('收盤等於之前的最高價 → false', () {
      expect(
        structureC(barsFrom([...repeat(100, 20), 105], highs: highs)),
        isFalse,
      );
    });

    test('往回第 20 根的最高價也算在內', () {
      // 只有資料日之前第 20 根最高價 105
      expect(
        structureC(barsFrom([...repeat(100, 20), 104], highs: {0: 105})),
        isFalse,
      );
    });
  });

  group('structureBSupport', () {
    test('碰到 5 日線並守住 → 5', () {
      // 5MA 118、10MA 115.5；最低 119 ≤ 118 × 1.015
      final bars = barsFrom(_risingThen(120), lows: {20: 119});
      expect(structureBSupport(bars), 5);
    });

    test('同時碰到 5 日線與 10 日線 → 取較短的 5', () {
      final bars = barsFrom(_risingThen(120), lows: {20: 115});
      expect(structureBSupport(bars), 5);
    });

    test('沒守住 5 日線、但碰到並守住 10 日線 → 10', () {
      // 收 116.62：5MA 117.324，收盤約為 5MA × 0.994；10MA 115.162
      final bars = barsFrom(_risingThen(116.62), lows: {20: 115.5});
      expect(structureBSupport(bars), 10);
    });

    test('碰到 5 日線支撐但收盤不在 10 日線上 → null', () {
      // 收 112：5MA 110.4、10MA 120.2
      final bars = barsFrom(
        [...repeat(100, 11), ...repeat(130, 5), ...repeat(110, 4), 112],
        lows: {20: 110},
      );
      expect(structureBSupport(bars), isNull);
    });

    test('收盤等於 10 日線 → null', () {
      // 5MA、10MA、收盤都是 110
      final bars = barsFrom([...repeat(100, 11), ...repeat(110, 10)]);
      expect(structureBSupport(bars), isNull);
    });

    test('20 日漲幅不大於 0 → null', () {
      final falling = _risingThen(120)..[0] = 125;
      expect(structureBSupport(barsFrom(falling, lows: {20: 119})), isNull);

      final flat = _risingThen(120)..[0] = 120;
      expect(structureBSupport(barsFrom(flat, lows: {20: 119})), isNull);
    });
  });

  group('checkEntryPrerequisites', () {
    test('60 日漲幅為 0 → 會動不通過', () {
      final check = checkEntryPrerequisites(
        barsFrom(repeat(100, 61)),
        revenueYoy3m: 50,
      );
      expect(check.moving, CheckOutcome.fail);
    });

    test('乖離恰好 15% 不通過、略低於 15% 通過，並回報乖離', () {
      // 最後 20 根＝19×377＋437：20 日均線 380，乖離 57/380＝15%
      final exact = checkEntryPrerequisites(
        barsFrom([...repeat(300, 41), ...repeat(377, 19), 437]),
        revenueYoy3m: 50,
      );
      expect(exact.bias, CheckOutcome.fail);
      expect(exact.biasPct, 15.0);

      final below = checkEntryPrerequisites(
        barsFrom([...repeat(300, 41), ...repeat(377, 19), 436.9]),
        revenueYoy3m: 50,
      );
      expect(below.bias, CheckOutcome.pass);
    });

    test('營收年增 3 月均：沒有資料是資料不足、恰好 30% 不通過', () {
      final bars = barsFrom(repeat(100, 61));
      expect(
        checkEntryPrerequisites(bars, revenueYoy3m: null).revenue,
        CheckOutcome.insufficient,
      );
      expect(
        checkEntryPrerequisites(bars, revenueYoy3m: 30).revenue,
        CheckOutcome.fail,
      );
      expect(
        checkEntryPrerequisites(bars, revenueYoy3m: 30.01).revenue,
        CheckOutcome.pass,
      );
    });

    test('資料日成交量恰好 3,000,000 股不通過；沒有成交量是資料不足', () {
      final check = checkEntryPrerequisites(
        barsFrom(repeat(100, 61), volumes: {60: 3000000}),
        revenueYoy3m: 50,
      );
      expect(check.dayVolume, CheckOutcome.fail);

      final missing = checkEntryPrerequisites(
        barsFrom(repeat(100, 61), nullVolumes: {60}),
        revenueYoy3m: 50,
      );
      expect(missing.dayVolume, CheckOutcome.insufficient);
    });

    test('少於 61 根 → 會動是資料不足', () {
      final check = checkEntryPrerequisites(
        barsFrom(repeat(100, 60)),
        revenueYoy3m: 50,
      );
      expect(check.moving, CheckOutcome.insufficient);
      expect(check.allPassed, isFalse);
    });

    test('四項都過 → allPassed', () {
      // 60 日漲幅 > 0、乖離小、營收 50%、量 5,000,000
      final check = checkEntryPrerequisites(
        barsFrom([...repeat(90, 41), ...repeat(100, 20)]),
        revenueYoy3m: 50,
      );
      expect(check.moving, CheckOutcome.pass);
      expect(check.bias, CheckOutcome.pass);
      expect(check.revenue, CheckOutcome.pass);
      expect(check.dayVolume, CheckOutcome.pass);
      expect(check.allPassed, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/close_summary/chip_checks.dart';

import 'close_summary_fixtures.dart';

/// 5 根日線，每天成交量 5,000,000 股（1% 是 50,000 股）
final _bars = barsFrom(repeat(100, 5));

({double foreign, double trust}) _d(double foreign, double trust) =>
    (foreign: foreign, trust: trust);

void main() {
  group('籌碼章', () {
    test('外資最近 3 天每天買超都達成交量 1%（含恰好 1%）→ 外資成立', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, 0),
          _d(60000, 0),
          _d(50000, 0),
          _d(70000, 0),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealedBy, ChipParty.foreign);
      expect(check.sealed, isTrue);
    });

    test('其中一天只有 0.99% → 不成立', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, 0),
          _d(60000, 0),
          _d(49500, 0),
          _d(70000, 0),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealedBy, isNull);
      expect(check.sealed, isFalse);
    });

    test('3 天裡有一天沒有該股的法人列 → 那天算 0，不成立', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, 0),
          _d(60000, 0),
          null,
          _d(70000, 0),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealed, isFalse);
    });

    test('外資、投信都成立 → 取外資', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, 0),
          _d(60000, 60000),
          _d(60000, 60000),
          _d(60000, 60000),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealedBy, ChipParty.foreign);
    });

    test('不足 3 根價格 → 不成立', () {
      final check = checkChip(
        institutional: instFrom([_d(900000, 0), _d(900000, 0)]),
        bars: barsFrom(repeat(100, 2)),
        institutionalReady: true,
      )!;
      expect(check.sealed, isFalse);
    });

    test('法人列的時間不是午夜也對得上價格日', () {
      final rows = [
        for (final row in instFrom(List.filled(5, _d(60000, 0))))
          row.copyWith(date: row.date.add(const Duration(hours: 8))),
      ];
      final check = checkChip(
        institutional: rows,
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealedBy, ChipParty.foreign);
      expect(check.foreignStreak, 5);
    });

    test('投信成立、外資沒成立 → 投信', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, 0),
          _d(0, 60000),
          _d(0, 60000),
          _d(0, 60000),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealedBy, ChipParty.trust);
    });
  });

  group('對做', () {
    test('外資成立，投信某天賣掉外資 3 天買的量 → 對做；少 1 股 → 不算', () {
      List<({double foreign, double trust})?> days(double trustSell) => [
        _d(0, 0),
        _d(0, 0),
        _d(60000, 0),
        _d(60000, -trustSell),
        _d(60000, 0),
      ];

      final opposed = checkChip(
        institutional: instFrom(days(180000)),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(opposed.sealedBy, ChipParty.foreign);
      expect(opposed.opposed, isTrue);

      final notOpposed = checkChip(
        institutional: instFrom(days(179999)),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(notOpposed.opposed, isFalse);
    });

    test('投信成立，看的是外資的賣超', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, 0),
          _d(-300000, 60000),
          _d(0, 60000),
          _d(0, 60000),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.sealedBy, ChipParty.trust);
      expect(check.opposed, isTrue);
    });

    test('籌碼章前一天的賣超不算（只看那 3 天）', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(0, -999999),
          _d(60000, 0),
          _d(60000, 0),
          _d(60000, 0),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.opposed, isFalse);
    });
  });

  group('連買連賣天數與當日張數', () {
    test('外資連買 4 天 → 4；投信連賣 3 天 → −3，不受 1% 下限影響', () {
      final check = checkChip(
        institutional: instFrom([
          _d(0, 0),
          _d(1, 0),
          _d(1, -1),
          _d(1, -1),
          _d(1, -1),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.foreignStreak, 4);
      expect(check.trustStreak, -3);
      expect(check.foreignNetShares, 1);
      expect(check.trustNetShares, -1);
    });

    test('資料日買賣超為 0 → 天數 0', () {
      final check = checkChip(
        institutional: instFrom([
          _d(1, 1),
          _d(1, 1),
          _d(1, 1),
          _d(1, 1),
          _d(0, 0),
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.foreignStreak, 0);
      expect(check.trustStreak, 0);
    });
  });

  group('法人資料未到', () {
    test('市場的法人還沒寫入 → null', () {
      expect(
        checkChip(
          institutional: instFrom(List.filled(5, _d(60000, 0))),
          bars: _bars,
          institutionalReady: false,
        ),
        isNull,
      );
    });

    test('市場已到、但資料日沒有該股的列 → 當日 0、不成立', () {
      final check = checkChip(
        institutional: instFrom([
          _d(60000, 0),
          _d(60000, 0),
          _d(60000, 0),
          _d(60000, 0),
          null,
        ]),
        bars: _bars,
        institutionalReady: true,
      )!;
      expect(check.foreignNetShares, 0);
      expect(check.foreignStreak, 0);
      expect(check.sealed, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/transaction_types.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/close_summary/holding_checks.dart';

import 'close_summary_fixtures.dart';

/// 進場日（第 20 個交易日）以前 21 根：收盤 100、高低 102／98（TR 4），
/// 之後接 [after] 的收盤，[afterHighs] 指定進場後第幾根的最高價（從 1 起）
List<({double close, double? high, double? low})> _series(
  List<double> after, {
  Map<int, double> afterHighs = const {},
}) => [
  for (var i = 0; i < 21; i++) (close: 100.0, high: 102.0, low: 98.0),
  for (var i = 0; i < after.length; i++)
    (close: after[i], high: afterHighs[i + 1], low: null),
];

void main() {
  final buyOnEntry = [txOn(20, TransactionTypes.buy, 1000)];
  final position = positionOf(quantity: 1000, avgCost: 100);

  List<double> closesOf(List<({double close, double? high, double? low})> s) =>
      [for (final b in s) b.close];

  HoldingCheck? checkWith(
    List<({double close, double? high, double? low})> s, {
    List<PortfolioTransactionEntry> txs = const [],
  }) {
    final bars = barsFrom(
      closesOf(s),
      highs: {for (var i = 0; i < s.length; i++) i: ?s[i].high},
      lows: {for (var i = 0; i < s.length; i++) i: ?s[i].low},
    );
    return checkHolding(
      position: position,
      transactions: txs.isEmpty ? buyOnEntry : txs,
      bars: bars,
    );
  }

  test('成本守門價＝成本 − 2 × 進場日的 ATR(20)，之後 ATR 變大也不動', () {
    // 進場後波動變大（高低 110／90）
    final s = [
      ..._series([]),
      for (var i = 0; i < 3; i++) (close: 100.0, high: 110.0, low: 90.0),
    ];
    final check = checkWith(s)!;
    expect(check.stopPrice, 92);
    expect(check.oneR, 8);
    expect(check.entryDate, tradingDay(20));
  });

  group('時間（8 日未達 +1R）', () {
    test('進場後第 5 天收盤到 +1R → 解除', () {
      final check = checkWith(_series([101, 102, 103, 104, 108, 100, 100]))!;
      expect(check.timeStop, TimeStopState.lifted);
    });

    test('8 天內最高價到過 109、收盤最高 107.99 → 第 8 天到期', () {
      final check = checkWith(
        _series(
          [101, 102, 107.99, 103, 100, 100, 100, 100],
          afterHighs: {3: 109},
        ),
      )!;
      expect(check.tradingDaysHeld, 8);
      expect(check.timeStop, TimeStopState.expired);
    });

    test('第 7 天還沒到 +1R → 進行中', () {
      final check = checkWith(_series([101, 102, 103, 104, 105, 106, 107]))!;
      expect(check.tradingDaysHeld, 7);
      expect(check.timeStop, TimeStopState.running);
    });

    test('進場當天 → 第 0 天', () {
      expect(checkWith(_series([]))!.tradingDaysHeld, 0);
    });

    test('只看進場後 8 天：第 8 天收盤到 +1R 仍解除', () {
      final check = checkWith(
        _series([101, 101, 101, 101, 101, 101, 101, 108]),
      )!;
      expect(check.timeStop, TimeStopState.lifted);
    });

    test('8 天都沒到、第 9 天才到 +1R → 仍是到期', () {
      final check = checkWith(
        _series([101, 101, 101, 101, 101, 101, 101, 101, 110]),
      )!;
      expect(check.timeStop, TimeStopState.expired);
    });
  });

  test('進場日晚於資料日（盤後資料還沒寫入）→ 守門價、1R、時間都是 null', () {
    final check = checkHolding(
      position: position,
      transactions: [txOn(26, TransactionTypes.buy, 1000)],
      bars: barsFrom(repeat(100, 25)),
    )!;
    expect(check.stopPrice, isNull);
    expect(check.oneR, isNull);
    expect(check.timeStop, isNull);
    expect(check.tradingDaysHeld, 0);
  });

  test('進場日早於讀到的第一根 → 持有天數 null（數不出來）', () {
    final check = checkHolding(
      position: position,
      transactions: [txOn(0, TransactionTypes.buy, 1000)],
      bars: barsFrom(repeat(100, 10), startDay: 5),
    )!;
    expect(check.tradingDaysHeld, isNull);
    expect(check.stopPrice, isNull);
    expect(check.timeStop, isNull);
  });

  group('進場日', () {
    test('賣光後又買回 → 取最後一次歸零之後第一筆買進', () {
      final txs = [
        txOn(0, TransactionTypes.buy, 1000),
        txOn(4, TransactionTypes.sell, 1000),
        txOn(9, TransactionTypes.buy, 500),
        txOn(11, TransactionTypes.buy, 500),
      ];
      expect(holdingEntryDate(txs), tradingDay(9));

      final check = checkHolding(
        position: position,
        transactions: txs,
        bars: barsFrom(repeat(100, 16)),
      )!;
      expect(check.entryDate, tradingDay(9));
    });

    test('連股票股利一起賣光後又買回 → 取賣光後第一筆買進', () {
      final txs = [
        txOn(0, TransactionTypes.buy, 1000),
        txOn(3, TransactionTypes.dividendStock, 50),
        txOn(5, TransactionTypes.sell, 1050),
        txOn(7, TransactionTypes.buy, 30),
        txOn(9, TransactionTypes.buy, 1000),
      ];
      expect(holdingEntryDate(txs), tradingDay(7));
    });

    test('買進的股數賣光、只剩配股股數 → null（成本為 0，沒有守門價可言）', () {
      final txs = [
        txOn(0, TransactionTypes.buy, 1000),
        txOn(3, TransactionTypes.dividendStock, 50),
        txOn(5, TransactionTypes.sell, 1000),
      ];
      expect(holdingEntryDate(txs), isNull);
    });

    test('交易順序亂掉也照日期與建立時間排序', () {
      // 照輸入順序算會得到第 0 天；排序後是 0 買、4 賣光、9 買 → 第 9 天
      final txs = [
        txOn(9, TransactionTypes.buy, 500),
        txOn(4, TransactionTypes.sell, 1000),
        txOn(0, TransactionTypes.buy, 1000),
      ];
      expect(holdingEntryDate(txs), tradingDay(9));
    });

    test('同一天先賣光再買回 → 照建立時間排序，取當天那筆買進', () {
      final day5 = tradingDay(5);
      final txs = [
        txOn(
          5,
          TransactionTypes.buy,
          500,
          createdAt: day5.add(const Duration(hours: 10)),
        ),
        txOn(
          5,
          TransactionTypes.sell,
          1000,
          createdAt: day5.add(const Duration(hours: 9)),
        ),
        txOn(0, TransactionTypes.buy, 1000),
      ];
      expect(holdingEntryDate(txs), day5);
    });

    test('只有股利、沒有買進 → null', () {
      final txs = [txOn(3, TransactionTypes.dividendCash, 500)];
      expect(holdingEntryDate(txs), isNull);
      expect(
        checkHolding(
          position: position,
          transactions: txs,
          bars: barsFrom(repeat(100, 16)),
        ),
        isNull,
      );
    });
  });

  test('進場日之前不足 21 根 → 守門價、1R、時間都是 null，天數與損益照算', () {
    final check = checkHolding(
      position: position,
      transactions: [txOn(10, TransactionTypes.buy, 1000)],
      bars: barsFrom([...repeat(100, 11), 101, 102, 103]),
    )!;
    expect(check.stopPrice, isNull);
    expect(check.oneR, isNull);
    expect(check.timeStop, isNull);
    expect(check.stopBroken, isFalse);
    expect(check.tradingDaysHeld, 3);
    expect(check.unrealizedPnl, 3000);
  });

  test('資料日收盤低於成本守門價才算收破', () {
    expect(checkWith(_series([95, 91.99]))!.stopBroken, isTrue);
    expect(checkWith(_series([95, 92]))!.stopBroken, isFalse);
  });

  test('損益：120 股、成本 525、收盤 530 → 600 元、約 0.952%', () {
    final check = checkHolding(
      position: positionOf(quantity: 120, avgCost: 525),
      transactions: [txOn(0, TransactionTypes.buy, 120, price: 525)],
      bars: barsFrom([525, 530]),
    )!;
    expect(check.unrealizedPnl, closeTo(600, 1e-9));
    expect(check.unrealizedPct, closeTo(0.952381, 1e-6));
    expect(check.quantity, 120);
    expect(check.avgCost, 525);
  });
}

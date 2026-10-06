import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/domain/services/live_quote/today_pnl.dart';

/// 今日損益(以昨收計)(2026-10-06,spec §7「今日損益」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final afterClose = DateTime(2026, 10, 6, 14, 10);

  MergedPrice live(
    double price, {
    double prev = 100,
    DateTime? now,
    bool closing = false,
    String time = '10:14:50',
  }) => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 5), close: prev),
    live: LiveQuoteEntry(
      symbol: 'A',
      date: DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: prev,
      quoteTime: time,
      isClosingQuote: closing,
    ),
    now: now ?? morning,
  );

  MergedPrice official(double close, double? change, {DateTime? date}) =>
      LiveQuoteMerge.merge(
        official: OfficialPrice(
          date: date ?? DateTime(2026, 10, 6),
          close: close,
          priceChange: change,
        ),
        live: null,
        now: afterClose,
      );

  MergedPrice yesterdayOnly() => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 5), close: 100),
    live: null,
    now: morning,
  );

  test('🚨 盤中:各持股股數 ×(即時價 − MIS 昨收)之和', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: live(102)),
      (quantity: 500, merged: live(98)),
    ], phase: MarketPhase.open)!;
    expect(r.amount, closeTo(1000 * 2 + 500 * -2, 1e-9));
    expect(r.missingCount, 0);
    expect(r.includesNonClosing, isFalse);
  });

  test('🚨 沒有今天價格的持股不當 0、不默默略過:計數「無報價未計入」', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: live(102)),
      (quantity: 300, merged: yesterdayOnly()),
    ], phase: MarketPhase.open)!;
    expect(r.amount, closeTo(2000, 1e-9));
    expect(r.missingCount, 1);
  });

  test('全部沒有今天價格 → 金額 0、計數全部(仍顯示,讓人知道沒算到)', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: yesterdayOnly()),
    ], phase: MarketPhase.open)!;
    expect(r.amount, 0);
    expect(r.missingCount, 1);
  });

  test('🚨 盤後資料寫入後:昨收 = 收盤 − 交易所價差(除權息日即為參考價)', () {
    // 除息 3 元:前一日收 103、參考價 100、今日收 101,價差 +1
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: official(101, 1)),
    ], phase: MarketPhase.afterClose)!;
    expect(r.amount, closeTo(1000, 1e-9), reason: '不可用 103 當昨收而少掉股利');
  });

  test('正式資料沒有價差(推不回昨收)→ 計數無報價', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: official(101, null)),
    ], phase: MarketPhase.afterClose)!;
    expect(r.missingCount, 1);
  });

  test('🚨 收盤後有持股用非收盤報價 → 標「含未收盤報價」;都是收盤報價則不標', () {
    final withNonClosing = TodayPnlRule.compute([
      (
        quantity: 1,
        merged: live(101, now: afterClose, closing: true, time: '13:30:00'),
      ),
      (quantity: 1, merged: live(99, now: afterClose, time: '13:29:40')),
    ], phase: MarketPhase.afterClose)!;
    expect(withNonClosing.includesNonClosing, isTrue);

    final allClosing = TodayPnlRule.compute([
      (
        quantity: 1,
        merged: live(101, now: afterClose, closing: true, time: '13:30:00'),
      ),
    ], phase: MarketPhase.afterClose)!;
    expect(allClosing.includesNonClosing, isFalse);
  });

  test('🚨 非交易日、盤前不顯示', () {
    final holdings = [(quantity: 1000.0, merged: live(102))];
    expect(TodayPnlRule.compute(holdings, phase: MarketPhase.closed), isNull);
    expect(TodayPnlRule.compute(holdings, phase: MarketPhase.preOpen), isNull);
  });

  test('已平倉(股數 0)不計;沒有在倉持股 → 不顯示', () {
    expect(
      TodayPnlRule.compute([
        (quantity: 0, merged: yesterdayOnly()),
      ], phase: MarketPhase.open),
      isNull,
    );
    final r = TodayPnlRule.compute([
      (quantity: 0, merged: yesterdayOnly()),
      (quantity: 10, merged: live(101)),
    ], phase: MarketPhase.open)!;
    expect(r.missingCount, 0);
    expect(r.amount, closeTo(10, 1e-9));
  });

  test('🚨 只有昨天的正式資料(含交易所價差)→ 仍算無報價,不把昨天的漲跌當今天', () {
    final stale = LiveQuoteMerge.merge(
      official: OfficialPrice(
        date: DateTime(2026, 10, 5),
        close: 100,
        priceChange: 3,
      ),
      live: null,
      now: morning,
    );
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: stale),
    ], phase: MarketPhase.open)!;
    expect(r.amount, 0);
    expect(r.missingCount, 1);
  });
}

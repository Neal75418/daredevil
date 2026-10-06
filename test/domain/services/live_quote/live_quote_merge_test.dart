import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';

/// 顯示合併規則(2026-10-06,spec §5):以「該畫面原本要顯示的那筆資料」
/// 為基準——它是今天且有收盤價就用它,否則用今天的即時報價,都沒有就維持
/// 原本的資料。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15, 40);
  final afterClose = DateTime(2026, 10, 6, 14, 10);

  LiveQuoteEntry live({
    DateTime? date,
    double price = 101,
    bool closing = false,
    String time = '10:15:30',
  }) => LiveQuoteEntry(
    symbol: 'A',
    date: date ?? DateTime(2026, 10, 6),
    price: price,
    displaySource: LiveDisplaySource.trade,
    previousClose: 100,
    quoteTime: time,
    isClosingQuote: closing,
  );

  OfficialPrice official(DateTime? date, double? close, {double? change}) =>
      OfficialPrice(date: date, close: close, priceChange: change);

  test('🚨 原本的資料是今天且有收盤價 → 正式資料,不看即時', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 6), 98, change: -2),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.official);
    expect(m.price, 98);
    expect(m.previousClose, 100, reason: '收盤 − priceChange');
    expect(m.label, isNull);
  });

  test('🚨 原本的資料是昨天 + 今天的即時 → 即時,盤中標報價時間', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100, change: 1),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.live);
    expect(m.price, 101);
    expect(m.previousClose, 100, reason: 'MIS 昨收 y');
    expect(m.label, LiveQuoteLabel.quoteTime);
    expect(m.quoteTime, '10:15:30');
  });

  test('🚨 部分寫入:日期是今天但收盤價為 null → 不算正式資料', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 6), null),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.live);
  });

  test('過期指數(呼叫端把日期傳 null)→ 不算正式資料', () {
    final m = LiveQuoteMerge.merge(
      official: official(null, 100),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.live);
  });

  test('🚨 即時報價日期不是今天 → 不用,維持原本的資料', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100, change: 1),
      live: live(date: DateTime(2026, 10, 5)),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.fallback);
    expect(m.price, 100);
    expect(m.previousClose, 99);
  });

  test('🚨 跨日:App 開著過夜,隔天盤前不把昨天的收盤標成今日收盤', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100),
      live: live(closing: true),
      now: DateTime(2026, 10, 7, 8, 30),
    );
    expect(m.kind, MergedPriceKind.fallback);
    expect(m.label, isNull);
  });

  test('🚨 收盤後三種標示:收盤報價、非收盤報價;盤中為報價時間', () {
    LiveQuoteLabel? label(bool closing, DateTime now) => LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100),
      live: live(closing: closing, time: closing ? '13:30:00' : '13:29:40'),
      now: now,
    ).label;
    expect(label(true, afterClose), LiveQuoteLabel.closingPending);
    expect(label(false, afterClose), LiveQuoteLabel.lastQuote);
    expect(label(false, morning), LiveQuoteLabel.quoteTime);
  });

  test('priceChange 為 null → previousClose 交給呼叫端(null)', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 6), 105),
      live: null,
      now: afterClose,
    );
    expect(m.kind, MergedPriceKind.official);
    expect(m.previousClose, isNull);
  });

  test('都沒有 → 原本的資料(可能是 null)', () {
    final m = LiveQuoteMerge.merge(official: null, live: null, now: morning);
    expect(m.kind, MergedPriceKind.fallback);
    expect(m.price, isNull);
    expect(m.live, isNull);
  });

  test('MergedPrice.changePercent:以 previousClose 計;沒有昨收為 null', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100),
      live: live(price: 102),
      now: morning,
    );
    expect(m.changePercent, closeTo(2.0, 1e-9));
    final none = LiveQuoteMerge.merge(official: null, live: null, now: morning);
    expect(none.changePercent, isNull);
  });

  test('OfficialPrice 值相等(讓 provider 的 select 不因新實例而重算)', () {
    expect(
      official(DateTime(2026, 10, 5), 100, change: 1),
      official(DateTime(2026, 10, 5), 100, change: 1),
    );
    expect(
      official(DateTime(2026, 10, 5), 100, change: 1),
      isNot(official(DateTime(2026, 10, 5), 100, change: 2)),
    );
  });
}

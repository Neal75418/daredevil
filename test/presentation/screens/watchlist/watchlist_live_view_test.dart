import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_live_view.dart';

/// 自選列的即時顯示結果(2026-10-06,spec §7 自選清單)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final row = WatchlistItemData(
    symbol: 'A',
    market: 'TWSE',
    latestClose: 100,
    priceChange: 1,
    priceDate: DateTime(2026, 10, 5),
    priceChangeAmount: 1,
    recentPrices: const [97, 98, 99, 100],
  );

  LiveQuoteEntry entry({bool locked = false, int? flashId}) => LiveQuoteEntry(
    symbol: 'A',
    date: DateTime(2026, 10, 6),
    price: locked ? 110 : 103,
    displaySource: locked ? LiveDisplaySource.locked : LiveDisplaySource.trade,
    previousClose: 100,
    quoteTime: '10:14:50',
    isClosingQuote: false,
    limitUp: 110,
    limitDown: 90,
    isLimitUpLocked: locked,
    flash: flashId == null ? null : LiveQuoteFlash(id: flashId, up: true),
  );

  test('🚨 用即時:價格、以 MIS 昨收算的漲跌幅、走勢小圖接上即時價、帶漲跌停價與閃色', () {
    final v = WatchlistLiveView.of(
      item: row,
      merged: row.mergedWith(entry(flashId: 3), morning),
      flashEnabled: true,
    );
    expect(v.price, 103);
    expect(v.changePercent, closeTo(3.0, 1e-9));
    expect(v.recentPrices, [97, 98, 99, 100, 103]);
    expect(v.card!.limitUp, 110);
    expect(v.card!.flash!.id, 3);
    expect(v.card!.flashEnabled, isTrue);
  });

  test('🚨 鎖漲停 → 帶鎖住旗標', () {
    final v = WatchlistLiveView.of(
      item: row,
      merged: row.mergedWith(entry(locked: true), morning),
      flashEnabled: false,
    );
    expect(v.card!.limitUpLocked, isTrue);
    expect(v.card!.flashEnabled, isFalse);
  });

  test('🚨 畫面已有今天正式資料 → 走勢小圖不重複接、不帶即時欄位', () {
    final today = WatchlistItemData(
      symbol: 'A',
      market: 'TWSE',
      latestClose: 101,
      priceChange: 1,
      priceDate: DateTime(2026, 10, 6),
      priceChangeAmount: 1,
      recentPrices: const [99, 100, 101],
    );
    final v = WatchlistLiveView.of(
      item: today,
      merged: today.mergedWith(entry(), morning),
      flashEnabled: true,
    );
    expect(v.price, 101);
    expect(v.changePercent, 1);
    expect(v.recentPrices, [99, 100, 101]);
    expect(v.card, isNull);
  });

  test('沒有即時但有例外標示 → 只帶標示', () {
    final v = WatchlistLiveView.of(
      item: row,
      merged: row.mergedWith(null, morning),
      flashEnabled: true,
      caption: 'liveQuote.cardPaused',
    );
    expect(v.price, 100);
    expect(v.card!.caption, 'liveQuote.cardPaused');
    expect(v.card!.limitUp, isNull);
  });
}

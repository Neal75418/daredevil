import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 跟著 fakeAsync 經過的時間走
class _AsyncClock implements AppClock {
  _AsyncClock(this.t0, this.async);
  final DateTime t0;
  final FakeAsync async;
  @override
  DateTime now() => t0.add(async.elapsed);
}

class _SeededWatchlist extends WatchlistNotifier {
  _SeededWatchlist(this.seed);
  final WatchlistState seed;

  @override
  WatchlistState build() {
    super.build();
    return seed;
  }
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;

  @override
  LiveQuoteState build() => initial;

  void emit(LiveQuoteState s) => state = s;
}

/// 自選的合併後價格與排序(2026-10-06,spec §5、§7「自選清單排序」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);

  WatchlistItemData item(
    String symbol, {
    double close = 100,
    double pct = 1,
    DateTime? date,
  }) => WatchlistItemData(
    symbol: symbol,
    market: 'TWSE',
    latestClose: close,
    priceChange: pct,
    priceDate: date ?? DateTime(2026, 10, 5),
    priceChangeAmount: close - close / (1 + pct / 100),
  );

  LiveQuoteEntry entry(String symbol, double price, {double prev = 100}) =>
      LiveQuoteEntry(
        symbol: symbol,
        date: DateTime(2026, 10, 6),
        price: price,
        displaySource: LiveDisplaySource.trade,
        previousClose: prev,
        quoteTime: '10:14:50',
        isClosingQuote: false,
      );

  ({ProviderContainer c, _FixedCenter center}) setup(
    WatchlistState seed,
    LiveQuoteState live,
  ) {
    final center = _FixedCenter(live);
    final c = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(morning)),
        watchlistProvider.overrideWith(() => _SeededWatchlist(seed)),
        liveQuoteCenterProvider.overrideWith(() => center),
      ],
    );
    addTearDown(c.dispose);
    return (c: c, center: center);
  }

  test('🚨 正式資料是昨天、有今天的即時 → 用即時價與以 MIS 昨收算的漲跌幅', () {
    final s = setup(
      WatchlistState(items: [item('A')]),
      LiveQuoteState(entries: {'A': entry('A', 105)}),
    );
    final m = s.c.read(watchlistLivePriceProvider('A'))!;
    expect(m.kind, MergedPriceKind.live);
    expect(m.price, 105);
    final row = s.c.read(watchlistProvider).itemOf('A')!;
    expect(row.changePercentWith(m), closeTo(5.0, 1e-9));
  });

  test('正式資料是今天 → 不看即時,漲跌幅沿用盤後', () {
    final s = setup(
      WatchlistState(
        items: [item('A', close: 101, pct: 1, date: DateTime(2026, 10, 6))],
      ),
      LiveQuoteState(entries: {'A': entry('A', 105)}),
    );
    final m = s.c.read(watchlistLivePriceProvider('A'))!;
    expect(m.kind, MergedPriceKind.official);
    expect(m.price, 101);
    expect(s.c.read(watchlistProvider).itemOf('A')!.changePercentWith(m), 1);
  });

  test('不在自選 → null', () {
    final s = setup(WatchlistState(), const LiveQuoteState());
    expect(s.c.read(watchlistLivePriceProvider('X')), isNull);
  });

  test('🚨 依漲跌幅排序用合併後的漲跌幅(與卡片顯示一致)', () {
    final s = setup(
      WatchlistState(items: [item('A', pct: 3), item('B', pct: 1)]),
      LiveQuoteState(
        entries: {'A': entry('A', 99), 'B': entry('B', 104)},
      ), // A 即時 -1%、B 即時 +4%
    );
    s.c.read(watchlistProvider.notifier).setSort(WatchlistSort.priceChangeDesc);
    expect(
      [for (final i in s.c.read(watchlistProvider).items) i.symbol],
      ['B', 'A'],
    );
  });

  test('🚨 resortWithLive:依漲跌幅排序時用最新即時重排;其他排序不動', () {
    final s = setup(
      WatchlistState(
        items: [item('A', pct: 3), item('B', pct: 1)],
        sort: WatchlistSort.priceChangeDesc,
      ),
      const LiveQuoteState(),
    );
    final notifier = s.c.read(watchlistProvider.notifier);
    s.c.read(liveQuoteCenterProvider); // 先建好報價中心才能推送新狀態
    s.center.emit(
      LiveQuoteState(entries: {'A': entry('A', 99), 'B': entry('B', 104)}),
    );
    notifier.resortWithLive();
    expect(
      [for (final i in s.c.read(watchlistProvider).items) i.symbol],
      ['B', 'A'],
    );

    final other = setup(
      WatchlistState(
        items: [item('A', pct: 3), item('B', pct: 1)],
        sort: WatchlistSort.addedDesc,
      ),
      LiveQuoteState(entries: {'A': entry('A', 99), 'B': entry('B', 104)}),
    );
    final before = other.c.read(watchlistProvider);
    other.c.read(watchlistProvider.notifier).resortWithLive();
    expect(
      other.c.read(watchlistProvider),
      same(before),
      reason: '非漲跌幅排序不發新狀態(否則每輪都重建整個清單)',
    );
  });

  test('copyWith(改分組)保留價格日期與價差', () {
    final row = item('A').copyWith(groupId: 3, groupName: 'G');
    expect(row.priceDate, DateTime(2026, 10, 5));
    expect(row.priceChangeAmount, isNotNull);
  });

  test('邊界時刻:開盤、收盤、午夜', () {
    expect(
      LiveQuoteBoundary.nextBoundary(DateTime(2026, 10, 6, 8, 59, 59)),
      DateTime(2026, 10, 6, 9),
    );
    expect(
      LiveQuoteBoundary.nextBoundary(DateTime(2026, 10, 6, 9)),
      DateTime(2026, 10, 6, 13, 30),
    );
    expect(
      LiveQuoteBoundary.nextBoundary(DateTime(2026, 10, 6, 13, 30)),
      DateTime(2026, 10, 7),
    );
  });

  test('🚨 跨過 13:30 而資料沒變 → 合併結果照樣重算(卡片改標最後報價)', () {
    fakeAsync((async) {
      final c = ProviderContainer(
        overrides: [
          appClockProvider.overrideWithValue(
            _AsyncClock(DateTime(2026, 10, 6, 13, 29, 58), async),
          ),
          watchlistProvider.overrideWith(
            () => _SeededWatchlist(WatchlistState(items: [item('A')])),
          ),
          liveQuoteCenterProvider.overrideWith(
            () => _FixedCenter(LiveQuoteState(entries: {'A': entry('A', 101)})),
          ),
        ],
      );
      final sub = c.listen(watchlistLivePriceProvider('A'), (_, _) {});
      expect(sub.read()!.label, LiveQuoteLabel.quoteTime);

      async.elapse(const Duration(seconds: 3));
      expect(sub.read()!.label, LiveQuoteLabel.lastQuote);
      sub.close();
      c.dispose();
    });
  });
}

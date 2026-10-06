import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings([this.initial = const SettingsState()]);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _FixedMarket extends MarketOverviewNotifier {
  _FixedMarket(this.initial);
  final MarketOverviewState initial;
  @override
  MarketOverviewState build() => initial;
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;
  @override
  LiveQuoteState build() => initial;
}

/// 大盤指數的即時顯示(2026-10-06,spec §5、§7「今日頁大盤列、大盤總覽頁」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final yesterday = DateTime(2026, 10, 5);
  final today = DateTime(2026, 10, 6);

  TwseMarketIndex index(String name, DateTime date, {double close = 20000}) =>
      TwseMarketIndex(
        date: date,
        name: name,
        close: close,
        change: 100,
        changePercent: 0.5,
      );

  LiveQuoteEntry quote(String symbol, double price, {int? flashId}) =>
      LiveQuoteEntry(
        symbol: symbol,
        date: today,
        price: price,
        displaySource: LiveDisplaySource.trade,
        previousClose: 20000,
        quoteTime: '10:14:55',
        isClosingQuote: false,
        flash: flashId == null ? null : LiveQuoteFlash(id: flashId, up: true),
      );

  ProviderContainer container(
    MarketOverviewState market,
    LiveQuoteState live, {
    SettingsState settings = const SettingsState(),
  }) {
    final c = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(morning)),
        marketOverviewProvider.overrideWith(() => _FixedMarket(market)),
        liveQuoteCenterProvider.overrideWith(() => _FixedCenter(live)),
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('indexSymbolOf:上市 t00、上櫃 o00', () {
    expect(LiveQuoteParams.indexSymbolOf(MarketCode.twse), 't00');
    expect(LiveQuoteParams.indexSymbolOf(MarketCode.tpex), 'o00');
  });

  test('🚨 盤後資料是昨天、有今天的即時 → 顯示即時點數,漲跌以 MIS 昨收算', () {
    final c = container(
      MarketOverviewState(indices: [index(MarketIndexNames.taiex, yesterday)]),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!;
    expect(shown.isLive, isTrue);
    expect(shown.index.name, MarketIndexNames.taiex);
    expect(shown.index.close, 20200);
    expect(shown.index.change, closeTo(200, 1e-9));
    expect(shown.index.changePercent, closeTo(1.0, 1e-9));
    expect(shown.index.date, today);
    expect(shown.statusText, 'liveQuote.quoteTime');
  });

  test('盤後資料是今天 → 用盤後那一筆,不標狀態', () {
    final official = index(MarketIndexNames.taiex, today);
    final c = container(
      MarketOverviewState(indices: [official]),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    final indices = c.read(marketLiveIndicesProvider);
    final shown = indices.byMarket[MarketCode.twse]!;
    expect(shown.isLive, isFalse);
    expect(shown.index, same(official));
    expect(shown.statusText, isNull);
    expect(indices.anyLive, isFalse);
  });

  test('🚨 備援值(非即時)即使日期是今天也不算正式資料 → 有即時就用即時', () {
    final stale = index(MarketIndexNames.taiex, today);
    final c = container(
      MarketOverviewState(
        indices: [stale],
        indexStaleNames: {MarketIndexNames.taiex},
      ),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    expect(
      c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!.isLive,
      isTrue,
    );
  });

  test('沒有盤後資料、有即時 → 名稱用預設的上櫃指數名稱', () {
    final c = container(
      const MarketOverviewState(),
      LiveQuoteState(entries: {'o00': quote('o00', 300)}),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.tpex]!;
    expect(shown.index.name, MarketIndexNames.tpexIndex);
    expect(shown.isLive, isTrue);
  });

  test('沒有盤後也沒有即時 → 不顯示該指數', () {
    final c = container(const MarketOverviewState(), const LiveQuoteState());
    expect(c.read(marketLiveIndicesProvider).byMarket, isEmpty);
  });

  test('閃色事件帶到顯示資料;設定頁關閉價格閃色 → flashEnabled false', () {
    final c = container(
      MarketOverviewState(indices: [index(MarketIndexNames.taiex, yesterday)]),
      LiveQuoteState(entries: {'t00': quote('t00', 20200, flashId: 7)}),
      settings: const SettingsState(priceFlash: false),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!;
    expect(shown.flash!.id, 7);
    expect(shown.flashEnabled, isFalse);
  });

  test('🚨 登記兩個指數;「已有今天正式資料」只在日期是今天且不是備援值時成立', () {
    MarketOverviewState state(DateTime date, {bool stale = false}) =>
        MarketOverviewState(
          indices: [
            index(MarketIndexNames.taiex, date),
            index(MarketIndexNames.tpexIndex, date, close: 300),
          ],
          indexStaleNames: stale ? {MarketIndexNames.taiex} : const {},
        );

    expect(marketIndexRegistrations(state(today), morning), const [
      LiveQuoteRegistration(
        symbol: 't00',
        market: MarketCode.twse,
        hasOfficialToday: true,
      ),
      LiveQuoteRegistration(
        symbol: 'o00',
        market: MarketCode.tpex,
        hasOfficialToday: true,
      ),
    ]);
    expect(
      marketIndexRegistrations(
        state(today, stale: true),
        morning,
      ).first.hasOfficialToday,
      isFalse,
    );
    expect(
      marketIndexRegistrations(
        state(yesterday),
        morning,
      ).first.hasOfficialToday,
      isFalse,
    );
    expect(
      marketIndexRegistrations(
        const MarketOverviewState(),
        morning,
      ).map((r) => r.hasOfficialToday),
      [false, false],
    );
  });

  test('🚨 漲跌以 MIS 昨收為基準,不是盤後那一筆的收盤(盤後資料可能更舊)', () {
    final c = container(
      MarketOverviewState(
        indices: [
          index(MarketIndexNames.taiex, DateTime(2026, 10, 2), close: 19800),
        ],
      ),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!;
    expect(shown.index.change, closeTo(200, 1e-9));
    expect(shown.index.changePercent, closeTo(1.0, 1e-9));
  });

  test('🚨 用盤後正式資料的指數:報價中心暫停時也不標暫停(那個數字不是即時的)', () {
    final c = container(
      MarketOverviewState(indices: [index(MarketIndexNames.taiex, today)]),
      LiveQuoteState(stalled: true, entries: {'t00': quote('t00', 20200)}),
    );
    expect(
      c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!.statusText,
      isNull,
    );
  });
}

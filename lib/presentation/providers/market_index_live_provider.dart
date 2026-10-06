import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';

/// 大盤列、大盤總覽頁 Hero 卡要顯示的一個指數
@immutable
class MarketIndexLive {
  const MarketIndexLive({
    required this.index,
    required this.isLive,
    this.flash,
    this.flashEnabled = true,
    this.statusText,
  });

  /// 要顯示的指數:用即時報價時以即時點數與 MIS 昨收組成,否則是盤後那一筆
  final TwseMarketIndex index;

  /// 用即時報價(此時不掛「非即時」)
  final bool isLive;
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 這個指數自己的報價狀態(已翻譯);用盤後正式資料時為 null
  final String? statusText;

  /// 依合併結果組出要顯示的指數;沒有盤後資料也沒有即時時回 null
  static MarketIndexLive? of({
    required String market,
    required TwseMarketIndex? official,
    required MergedPrice merged,
    required LiveQuoteState center,
    required bool flashEnabled,
  }) {
    final statusText = merged.kind == MergedPriceKind.official
        ? null
        : LiveQuoteStatusRule.header(
            state: center,
            merged: [merged],
            intradayTime: merged.quoteTime,
          )?.text();
    final live = merged.live;
    final price = merged.price;
    final previous = merged.previousClose;
    if (merged.kind == MergedPriceKind.live &&
        live != null &&
        price != null &&
        previous != null) {
      return MarketIndexLive(
        index: TwseMarketIndex(
          date: live.date,
          name: official?.name ?? heroIndexName(market),
          close: price,
          change: price - previous,
          changePercent: merged.changePercent ?? 0,
        ),
        isLive: true,
        flash: live.flash,
        flashEnabled: flashEnabled,
        statusText: statusText,
      );
    }
    if (official == null) return null;
    return MarketIndexLive(
      index: official,
      isLive: false,
      flashEnabled: flashEnabled,
      statusText: statusText,
    );
  }
}

/// 大盤列與 Hero 卡的兩個指數
@immutable
class MarketLiveIndices {
  const MarketLiveIndices({this.byMarket = const {}, this.statusText});

  /// 市場別(`MarketCode.twse`／`MarketCode.tpex`)→ 要顯示的指數
  final Map<String, MarketIndexLive> byMarket;

  /// 兩個指數合起來的報價狀態(大盤列用,已翻譯);都用正式資料時為 null
  final String? statusText;

  /// 有任一指數用即時報價(此時情緒、漲跌家數仍是盤後,要標日期)
  bool get anyLive => byMarket.values.any((i) => i.isLive);
}

/// 盤後的正式資料:該指數的日期;備援值(非即時)的日期傳 null,不算今天
OfficialPrice? _officialOf(MarketOverviewState s, String market) {
  final index = heroIndexOf(s, market);
  if (index == null) return null;
  return OfficialPrice(
    date: s.indexStaleNames.contains(index.name) ? null : index.date,
    close: index.close,
    priceChange: index.change,
  );
}

/// 大盤指數要顯示的點數(依合併規則;正式資料 = `MarketOverviewState` 的該
/// 指數,日期是今天且不是備援值)。判讀文字不走這裡(spec §7)
final marketIndexLivePriceProvider = Provider.autoDispose
    .family<MergedPrice, String>((ref, market) {
      ref.watch(liveQuoteBoundaryProvider);
      final official = ref.watch(
        marketOverviewProvider.select((s) => _officialOf(s, market)),
      );
      final live = ref.watch(
        liveQuoteCenterProvider.select(
          (s) => s.entries[LiveQuoteParams.indexSymbolOf(market)],
        ),
      );
      return LiveQuoteMerge.merge(
        official: official,
        live: live,
        now: ref.read(appClockProvider).now(),
      );
    });

/// 大盤列與 Hero 卡共用:兩個指數要顯示的值與狀態
final marketLiveIndicesProvider = Provider.autoDispose<MarketLiveIndices>((
  ref,
) {
  final center = ref.watch(liveQuoteCenterProvider);
  final flashEnabled = ref.watch(settingsProvider.select((s) => s.priceFlash));
  final byMarket = <String, MarketIndexLive>{};
  final merged = <MergedPrice>[];
  for (final market in const [MarketCode.twse, MarketCode.tpex]) {
    final m = ref.watch(marketIndexLivePriceProvider(market));
    merged.add(m);
    final item = MarketIndexLive.of(
      market: market,
      official: ref.watch(
        marketOverviewProvider.select((s) => heroIndexOf(s, market)),
      ),
      merged: m,
      center: center,
      flashEnabled: flashEnabled,
    );
    if (item != null) byMarket[market] = item;
  }
  final allOfficial = merged.every((m) => m.kind == MergedPriceKind.official);
  return MarketLiveIndices(
    byMarket: byMarket,
    statusText: allOfficial
        ? null
        : LiveQuoteStatusRule.header(
            state: center,
            merged: merged,
            intradayTime: null,
          )?.text(),
  );
});

/// 大盤列與大盤總覽頁登記的兩個指數;「已有今天正式資料」= 該指數日期是
/// 今天且不是備援值(收盤後據此決定要不要抓收盤報價)
List<LiveQuoteRegistration> marketIndexRegistrations(
  MarketOverviewState state,
  DateTime now,
) => [
  for (final market in const [MarketCode.twse, MarketCode.tpex])
    _indexRegistration(state, market, now),
];

LiveQuoteRegistration _indexRegistration(
  MarketOverviewState state,
  String market,
  DateTime now,
) {
  final date = _officialOf(state, market)?.date;
  return LiveQuoteRegistration(
    symbol: LiveQuoteParams.indexSymbolOf(market),
    market: market,
    hasOfficialToday: date != null && DateContext.isSameDay(date, now),
  );
}

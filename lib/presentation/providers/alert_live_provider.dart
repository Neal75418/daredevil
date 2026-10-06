import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 全域提醒頁某一檔的現價(依合併規則;正式資料 = 該檔最新一筆)。只用來
/// 顯示距現價多少,不影響提醒的觸發(2026-10-06,路線圖第 2 項)
final alertLivePriceProvider = Provider.autoDispose.family<MergedPrice, String>(
  (ref, symbol) {
    ref.watch(liveQuoteBoundaryProvider);
    final official = ref.watch(
      priceAlertProvider.select((s) {
        final p = s.latestPrices[symbol];
        return OfficialPrice(
          date: p?.date,
          close: p?.close,
          priceChange: p?.priceChange,
        );
      }),
    );
    final live = ref.watch(
      liveQuoteCenterProvider.select((s) => s.entries[symbol]),
    );
    return LiveQuoteMerge.merge(
      official: official,
      live: live,
      now: ref.read(appClockProvider).now(),
    );
  },
);

/// 要顯示距現價的股票:有啟用中、還沒觸發的價位提醒(突破／跌破),主檔查得到
/// 且知道市場別
List<String> alertWatchedSymbols(PriceAlertState state) => [
  for (final symbol in {
    for (final a in state.alerts)
      if (a.isActive &&
          a.triggeredAt == null &&
          (a.alertType == AlertType.above.value ||
              a.alertType == AlertType.below.value))
        a.symbol,
  })
    if (state.stockMarkets.containsKey(symbol) &&
        !state.unmonitorableSymbols.contains(symbol))
      symbol,
];

/// 全域提醒頁向報價中心登記的股票;「已有今天正式資料」看最新一筆的日期
List<LiveQuoteRegistration> alertRegistrations(
  PriceAlertState state,
  DateTime now,
) => [
  for (final symbol in alertWatchedSymbols(state))
    LiveQuoteRegistration(
      symbol: symbol,
      market: state.stockMarkets[symbol]!,
      hasOfficialToday: switch (state.latestPrices[symbol]?.date) {
        final date? => DateContext.isSameDay(date, now),
        null => false,
      },
    ),
];

/// 全域提醒頁頂端的報價狀態(只看登記的那些股票;已翻譯)
final alertsLiveHeaderProvider = Provider.autoDispose<String?>((ref) {
  // 接成字串再比較:清單沒有值相等,直接 select 清單會每次都判定成有變動
  final symbols = ref.watch(
    priceAlertProvider.select((s) => alertWatchedSymbols(s).join(',')),
  );
  if (symbols.isEmpty) return null;
  final center = ref.watch(liveQuoteCenterProvider);
  return LiveQuoteStatusRule.header(
    state: center,
    merged: [
      for (final symbol in symbols.split(','))
        ref.watch(alertLivePriceProvider(symbol)),
    ],
    intradayTime: null,
  )?.text();
});

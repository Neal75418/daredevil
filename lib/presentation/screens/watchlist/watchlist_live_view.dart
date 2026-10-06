import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/stock_card_live.dart';

/// 自選列要顯示的即時結果(依合併規則算出;見 `watchlistLivePriceProvider`)
@immutable
class WatchlistLiveView {
  const WatchlistLiveView({
    required this.price,
    required this.changePercent,
    required this.recentPrices,
    this.card,
  });

  /// [caption] 由呼叫端翻譯好傳入(本函式不碰 i18n)
  factory WatchlistLiveView.of({
    required WatchlistItemData item,
    required MergedPrice merged,
    required bool flashEnabled,
    String? caption,
  }) {
    final live = merged.kind == MergedPriceKind.live ? merged.live : null;
    final price = merged.price;
    return WatchlistLiveView(
      price: price,
      changePercent: item.changePercentWith(merged),
      // 走勢小圖最後一點接上即時價;畫面已有今天正式資料時不重複接
      recentPrices: live != null && price != null
          ? [...item.recentPrices, price]
          : item.recentPrices,
      card: live == null && caption == null
          ? null
          : StockCardLive(
              limitUp: live?.limitUp,
              limitDown: live?.limitDown,
              limitUpLocked: live?.isLimitUpLocked ?? false,
              limitDownLocked: live?.isLimitDownLocked ?? false,
              flash: live?.flash,
              flashEnabled: flashEnabled,
              caption: caption,
            ),
    );
  }

  final double? price;
  final double? changePercent;
  final List<double> recentPrices;
  final StockCardLive? card;
}

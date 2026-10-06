import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/market_session.dart';

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 盤中即時報價跟「現在」有關的判斷(是不是今天的正式資料、盤中或收盤後
/// 的標示)只在資料變動時重算;App 開著、資料沒變而跨過午夜／開盤／收盤時
/// 會過期(例如整天停在自選頁,隔天收盤後不去抓收盤報價)。這個 provider 在
/// 每個邊界換一次值,讓依賴它的地方重算。
final liveQuoteBoundaryProvider =
    NotifierProvider.autoDispose<LiveQuoteBoundary, DateTime>(
      LiveQuoteBoundary.new,
    );

class LiveQuoteBoundary extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    final now = ref.watch(appClockProvider).now();
    _schedule(now);
    return now;
  }

  void _schedule(DateTime now) {
    _timer?.cancel();
    // 多 1 毫秒:計時器略早觸發時,重算用的「現在」才不會還在邊界前
    _timer = Timer(
      nextBoundary(now).difference(now) + const Duration(milliseconds: 1),
      () {
        final t = ref.read(appClockProvider).now();
        state = t;
        _schedule(t);
      },
    );
  }

  /// [now] 之後的下一個邊界:開盤、收盤、午夜
  @visibleForTesting
  static DateTime nextBoundary(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    for (final minutes in const [
      MarketSession.openMinutes,
      MarketSession.closeMinutes,
    ]) {
      final boundary = day.add(Duration(minutes: minutes));
      if (boundary.isAfter(now)) return boundary;
    }
    return DateTime(now.year, now.month, now.day + 1);
  }
}

/// 自選某一檔要顯示的價格(依合併規則)。卡片、長按預覽、排序共用同一個
/// 結果,避免同一個數字兩個來源。不在自選清單裡回 null。
final watchlistLivePriceProvider = Provider.autoDispose
    .family<MergedPrice?, String>((ref, symbol) {
      ref.watch(liveQuoteBoundaryProvider);
      final item = ref.watch(watchlistProvider.select((s) => s.itemOf(symbol)));
      if (item == null) return null;
      final live = ref.watch(
        liveQuoteCenterProvider.select((s) => s.entries[symbol]),
      );
      return item.mergedWith(live, ref.read(appClockProvider).now());
    });

/// 自選頁首的即時報價狀態(見 [LiveQuoteStatusRule.header])
final watchlistLiveHeaderProvider = Provider.autoDispose<LiveHeaderStatus?>((
  ref,
) {
  ref.watch(liveQuoteBoundaryProvider);
  final items = ref.watch(watchlistProvider.select((s) => s.items));
  final center = ref.watch(liveQuoteCenterProvider);
  final now = ref.read(appClockProvider).now();
  return LiveQuoteStatusRule.header(
    state: center,
    merged: [
      for (final item in items)
        item.mergedWith(center.entries[item.symbol], now),
    ],
    intradayTime: center.latestQuoteTime,
  );
});

/// 個股頁要顯示的價格(依合併規則;正式資料 = 對齊法人日期的那一筆)。上方
/// 區塊與背景漸層共用同一個結果
final stockDetailLivePriceProvider = Provider.autoDispose
    .family<MergedPrice, String>((ref, symbol) {
      ref.watch(liveQuoteBoundaryProvider);
      final official = ref.watch(
        stockDetailProvider(symbol).select((s) {
          final p = s.price.latestPrice;
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
    });

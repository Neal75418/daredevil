import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/domain/services/live_quote/today_pnl.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 持股某一檔要顯示的價格(依合併規則;正式資料 = 該檔最新一筆)。持股列、
/// 總覽、持股詳情共用同一個結果。不在持股裡回 null
final portfolioLivePriceProvider = Provider.autoDispose
    .family<MergedPrice?, String>((ref, symbol) {
      ref.watch(liveQuoteBoundaryProvider);
      final official = ref.watch(
        portfolioProvider.select((s) {
          final p = s.positionOf(symbol);
          return p == null
              ? null
              : OfficialPrice(
                  date: p.priceDate,
                  close: p.currentPrice,
                  priceChange: p.priceChangeAmount,
                );
        }),
      );
      if (official == null) return null;
      final live = ref.watch(
        liveQuoteCenterProvider.select((s) => s.entries[symbol]),
      );
      return LiveQuoteMerge.merge(
        official: official,
        live: live,
        now: ref.read(appClockProvider).now(),
      );
    });

/// 投資組合的即時總覽
@immutable
class PortfolioLive {
  const PortfolioLive({
    required this.positions,
    required this.summary,
    this.todayPnl,
    this.status,
  });

  /// 持股(現價換成合併後的價格,順序同 `PortfolioState.positions`)
  final List<PortfolioPositionData> positions;

  /// 以 [positions] 計算的總市值、總損益等(同 `PortfolioState.summary` 的算法)
  final PortfolioSummary summary;

  /// 今日損益(以昨收計);非交易日、盤前為 null
  final TodayPnl? todayPnl;

  /// 持倉標題列的報價狀態(已翻譯);沒有為 null
  final String? status;
}

/// 投資組合的即時總覽。績效、配置、股利不走這裡,維持盤後(spec §7)
final portfolioLiveProvider = Provider.autoDispose<PortfolioLive>((ref) {
  ref.watch(liveQuoteBoundaryProvider);
  final positions = ref.watch(portfolioProvider.select((s) => s.positions));
  final center = ref.watch(liveQuoteCenterProvider);
  final now = ref.read(appClockProvider).now();
  final merged = <String, MergedPrice>{
    for (final p in positions)
      p.symbol: ?ref.watch(portfolioLivePriceProvider(p.symbol)),
  };
  final livePositions = [
    for (final p in positions)
      if (merged[p.symbol] case final m?) p.copyWithPrice(m.price) else p,
  ];
  return PortfolioLive(
    positions: livePositions,
    summary: PortfolioState(positions: livePositions).summary,
    todayPnl: TodayPnlRule.compute([
      for (final p in positions)
        if (merged[p.symbol] case final m?) (quantity: p.quantity, merged: m),
    ], phase: LiveQuoteSchedule.phaseAt(now)),
    status: LiveQuoteStatusRule.header(
      state: center,
      merged: merged.values,
      intradayTime: null,
    )?.text(),
  );
});

/// 投資組合與持股詳情登記的股票:在倉、有市場別;「已有今天正式資料」看
/// 價格日期是不是今天
List<LiveQuoteRegistration> portfolioRegistrations(
  Iterable<PortfolioPositionData> positions,
  DateTime now,
) => [
  for (final p in positions)
    if (p.quantity > 0)
      if (p.market case final market?)
        LiveQuoteRegistration(
          symbol: p.symbol,
          market: market,
          hasOfficialToday:
              p.priceDate != null && DateContext.isSameDay(p.priceDate!, now),
        ),
];

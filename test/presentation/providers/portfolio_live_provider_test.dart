import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_live_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _SeededPortfolio extends PortfolioNotifier {
  _SeededPortfolio(this.seed);
  final PortfolioState seed;
  @override
  PortfolioState build() => seed;
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;
  @override
  LiveQuoteState build() => initial;
}

/// 投資組合的合併後價格與即時總覽(2026-10-06,spec §5、§7「投資組合」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);

  PortfolioPositionData position(
    String symbol, {
    double quantity = 1000,
    double avgCost = 500,
    double? price = 600,
    DateTime? date,
    double? change = 6,
    String? market = MarketCode.twse,
  }) => PortfolioPositionData(
    symbol: symbol,
    market: market,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: 0,
    totalDividendReceived: 0,
    currentPrice: price,
    priceDate: date ?? DateTime(2026, 10, 5),
    priceChangeAmount: change,
  );

  LiveQuoteEntry quote(String symbol, double price, {double prev = 600}) =>
      LiveQuoteEntry(
        symbol: symbol,
        date: DateTime(2026, 10, 6),
        price: price,
        displaySource: LiveDisplaySource.trade,
        previousClose: prev,
        quoteTime: '10:14:50',
        isClosingQuote: false,
      );

  ProviderContainer container(
    List<PortfolioPositionData> positions,
    LiveQuoteState live, {
    DateTime? now,
  }) {
    final c = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(now ?? morning)),
        portfolioProvider.overrideWith(
          () => _SeededPortfolio(PortfolioState(positions: positions)),
        ),
        liveQuoteCenterProvider.overrideWith(() => _FixedCenter(live)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('🚨 正式資料是昨天、有今天的即時 → 每檔用即時價', () {
    final c = container([
      position('2330'),
    ], LiveQuoteState(entries: {'2330': quote('2330', 612)}));
    final m = c.read(portfolioLivePriceProvider('2330'))!;
    expect(m.kind, MergedPriceKind.live);
    expect(m.price, 612);
    expect(c.read(portfolioLivePriceProvider('9999')), isNull);
  });

  test('🚨 即時總覽:總市值、未實現損益用即時價;今日損益以昨收計', () {
    final c = container(
      [
        position('2330'),
        position('2317', quantity: 2000, avgCost: 100, price: 120, change: 1),
      ],
      LiveQuoteState(
        entries: {
          '2330': quote('2330', 612),
          '2317': quote('2317', 118, prev: 120),
        },
      ),
    );
    final live = c.read(portfolioLiveProvider);
    expect(
      live.summary.totalMarketValue,
      closeTo(1000 * 612 + 2000 * 118, 1e-6),
    );
    expect(
      live.summary.totalUnrealizedPnl,
      closeTo(1000 * 112 + 2000 * 18, 1e-6),
    );
    expect(live.todayPnl!.amount, closeTo(1000 * 12 + 2000 * -2, 1e-6));
    expect(live.todayPnl!.missingCount, 0);
    expect(live.positions.first.currentPrice, 612);
  });

  test('🚨 有一檔沒有今天的價格 → 總市值照用原本資料(不當 0);今日損益計數未計入', () {
    final c = container([
      position('2330'),
      position('6488', quantity: 100, avgCost: 400, price: 420, change: 5),
    ], LiveQuoteState(entries: {'2330': quote('2330', 612)}));
    final live = c.read(portfolioLiveProvider);
    expect(
      live.summary.totalMarketValue,
      closeTo(1000 * 612 + 100 * 420, 1e-6),
    );
    expect(live.todayPnl!.missingCount, 1);
    expect(live.todayPnl!.amount, closeTo(12000, 1e-6));
  });

  test('非交易日 → 不顯示今日損益', () {
    final c = container(
      [position('2330')],
      const LiveQuoteState(),
      now: DateTime(2026, 10, 10, 11), // 國慶日
    );
    expect(c.read(portfolioLiveProvider).todayPnl, isNull);
  });

  test('盤中有即時 → 狀態為報價時間;全部用正式資料 → 沒有狀態', () {
    final live = container([
      position('2330'),
    ], LiveQuoteState(entries: {'2330': quote('2330', 612)}));
    expect(live.read(portfolioLiveProvider).status, 'liveQuote.quoteTime');

    final official = container(
      [position('2330', date: DateTime(2026, 10, 6))],
      const LiveQuoteState(),
      now: DateTime(2026, 10, 6, 15),
    );
    expect(official.read(portfolioLiveProvider).status, isNull);
  });

  test('🚨 登記在倉持股(有市場別);「已有今天正式資料」看價格日期', () {
    final regs = portfolioRegistrations([
      position('2330', date: DateTime(2026, 10, 6)),
      position('2317'),
      position('1101', quantity: 0),
      position('9999', market: null),
    ], morning);
    expect(regs, const [
      LiveQuoteRegistration(
        symbol: '2330',
        market: MarketCode.twse,
        hasOfficialToday: true,
      ),
      LiveQuoteRegistration(symbol: '2317', market: MarketCode.twse),
    ]);
  });

  test('🚨 全部持股都是今天的正式資料 → 標題列不顯示狀態(即使最近一輪「尚無報價」)', () {
    final c = container(
      [position('2330', date: DateTime(2026, 10, 6))],
      const LiveQuoteState(latestResponseHadToday: false),
      now: DateTime(2026, 10, 6, 16),
    );
    expect(c.read(portfolioLiveProvider).status, isNull);
  });
}

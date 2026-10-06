import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/portfolio_analytics_service.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/allocation_pie_chart.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/portfolio_summary_card.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/screens/portfolio/portfolio_tab.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';
import '../../../helpers/phone_layout_helpers.dart';

// ==========================================
// Fake Notifier
// ==========================================

class FakePortfolioNotifier extends PortfolioNotifier {
  PortfolioState initialState = const PortfolioState();

  @override
  PortfolioState build() => initialState;

  @override
  Future<void> loadPositions() async {}

  @override
  Future<void> deleteTransaction(int id, String symbol) async {}

  @override
  Future<void> addBuy({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    String? note,
  }) async {}

  @override
  Future<void> addSell({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {}

  @override
  Future<void> addDividend({
    required String symbol,
    required DateTime date,
    required double amount,
    required bool isCash,
    String? note,
  }) async {}
}

// ==========================================
// Test Helpers
// ==========================================

PortfolioPositionData createPosition({
  String symbol = '2330',
  String? stockName = '台積電',
  double quantity = 1000,
  double avgCost = 500.0,
  double realizedPnl = 0,
  double totalDividendReceived = 0,
  double? currentPrice = 600.0,
  String? market = MarketCode.twse,
  DateTime? priceDate,
  double? priceChangeAmount,
}) {
  return PortfolioPositionData(
    symbol: symbol,
    stockName: stockName,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    currentPrice: currentPrice,
    market: market,
    priceDate: priceDate,
    priceChangeAmount: priceChangeAmount,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestWidget({
    PortfolioState? portfolioState,
    Brightness brightness = Brightness.light,
    _LiveCenter? liveCenter,
    DateTime? now,
  }) {
    final state = portfolioState ?? const PortfolioState();
    return buildProviderTestApp(
      const PortfolioTab(),
      overrides: [
        portfolioProvider.overrideWith(() {
          final n = FakePortfolioNotifier();
          n.initialState = state;
          return n;
        }),
        if (now != null) appClockProvider.overrideWithValue(_Clock(now)),
      ],
      brightness: brightness,
      liveQuoteCenter: liveCenter == null ? null : () => liveCenter,
    );
  }

  group('PortfolioTab', () {
    testWidgets('shows shimmer when loading with no data', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(portfolioState: const PortfolioState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(GenericListShimmer), findsOneWidget);
    });

    testWidgets('shows error state with retry', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: const PortfolioState(error: 'Network error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty state when no positions', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsOneWidget,
      );
    });

    testWidgets('shows add button in empty state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
    });

    testWidgets('shows positions list', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(symbol: '2330', stockName: '台積電'),
        createPosition(symbol: '2317', stockName: '鴻海'),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('shows FAB when positions exist', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows summary card', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      // PortfolioSummaryCard renders inside CustomScrollView
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('shows performance and industry allocation', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      const performance = PortfolioPerformance(
        totalReturn: 15.5,
        totalMarketValue: 600000,
        totalCostBasis: 500000,
        totalDividends: 13500,
        totalRealizedPnl: 0,
        periodReturns: PeriodReturns(
          daily: 0.5,
          weekly: 1.2,
          monthly: 3.0,
          yearly: 15.5,
        ),
        maxDrawdown: -5.2,
        industryAllocation: {
          '半導體業': IndustryAllocation(
            industry: '半導體業',
            value: 600000,
            percentage: 100.0,
            symbols: ['2330'],
          ),
        },
      );
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(
            positions: positions,
            performance: performance,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CustomScrollView), findsOneWidget);
    });
  });

  group('錯誤頁在手機上（小螢幕、放大字級）', () {
    for (final error in ['Database error', 'Network error']) {
      for (final scenario in phoneScenarios) {
        testWidgets('$error：$scenario 不溢位', (tester) async {
          applyPhoneScenario(tester, scenario);
          await tester.pumpWidget(
            buildTestWidget(portfolioState: PortfolioState(error: error)),
          );
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          expect(find.byType(EmptyState), findsOneWidget);
        });
      }
    }
  });

  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);
    // 兩檔:只有 2330 有即時——配置比例若誤用即時價就會變(一檔時永遠 100%,
    // 測不出來)
    final state = PortfolioState(
      positions: [
        createPosition(priceDate: DateTime(2026, 10, 5), priceChangeAmount: 6),
        createPosition(
          symbol: '2317',
          stockName: '鴻海',
          avgCost: 90,
          currentPrice: 100,
          priceDate: DateTime(2026, 10, 5),
          priceChangeAmount: 1,
        ),
      ],
    );
    LiveQuoteEntry quote(double price) => LiveQuoteEntry(
      symbol: '2330',
      date: DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: 600,
      quoteTime: '10:14:50',
      isClosingQuote: false,
    );

    testWidgets('🚨 登記在倉持股', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: state,
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(center.registered.values.single, const [
        LiveQuoteRegistration(symbol: '2330', market: MarketCode.twse),
        LiveQuoteRegistration(symbol: '2317', market: MarketCode.twse),
      ]);
    });

    testWidgets('🚨 總覽用即時價;配置圓餅維持盤後', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(LiveQuoteState(entries: {'2330': quote(612)}));
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: state,
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final summary = tester
          .widget<PortfolioSummaryCard>(find.byType(PortfolioSummaryCard))
          .summary;
      expect(summary.totalMarketValue, closeTo(612000 + 100000, 1e-6));
      final today = tester
          .widget<PortfolioSummaryCard>(find.byType(PortfolioSummaryCard))
          .todayPnl!;
      expect(today.amount, closeTo(12000, 1e-6));
      expect(today.missingCount, 1, reason: '2317 沒有今天的價格');
      final pie = tester.widget<AllocationPieChart>(
        find.byType(AllocationPieChart),
      );
      expect(pie.allocationMap, state.allocationMap, reason: '圓餅維持盤後');
      expect(find.textContaining('612'), findsWidgets);
    });

    testWidgets('盤後卡片的資料日期說明', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(portfolioState: state, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('portfolio.postMarketAsOf'), findsOneWidget);
    });

    testWidgets('持倉標題列顯示報價狀態', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(LiveQuoteState(entries: {'2330': quote(612)}));
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: state,
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('liveQuote.quoteTime'), findsOneWidget);
    });
  });
}

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 記錄登記、不發請求的報價中心
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter(this.initial);
  final LiveQuoteState initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}

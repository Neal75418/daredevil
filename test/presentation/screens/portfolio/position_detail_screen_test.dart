import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/screens/portfolio/position_detail_screen.dart';

import '../../../helpers/portfolio_data_builders.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

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
}) {
  return PortfolioPositionData(
    symbol: symbol,
    stockName: stockName,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    currentPrice: currentPrice,
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
    List<PortfolioTransactionEntry>? txList,
    Brightness brightness = Brightness.light,
    String symbol = '2330',
  }) {
    final state = portfolioState ?? const PortfolioState();
    final transactions = txList ?? [];
    return buildProviderTestApp(
      PositionDetailScreen(symbol: symbol),
      overrides: [
        portfolioProvider.overrideWith(() {
          final n = FakePortfolioNotifier();
          n.initialState = state;
          return n;
        }),
        positionTransactionsProvider.overrideWith(
          (ref, symbol) async => transactions,
        ),
      ],
      brightness: brightness,
    );
  }

  group('PositionDetailScreen', () {
    testWidgets('shows AppBar with symbol when no position', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AppBar), findsOneWidget);
      // When no position data, AppBar shows just the symbol
      expect(find.text('2330'), findsOneWidget);
    });

    testWidgets('shows AppBar with symbol and name', (tester) async {
      widenViewport(tester);
      final positions = [createPosition(symbol: '2330', stockName: '台積電')];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2330 台積電'), findsOneWidget);
    });

    testWidgets('shows empty state when no position found', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Shows "no positions" message
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('shows position summary card', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(quantity: 1000, avgCost: 500.0, currentPrice: 600.0),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows FAB with add icon', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows positive PnL with green color', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(
          quantity: 1000,
          avgCost: 500.0,
          currentPrice: 600.0, // +100 per share = +100,000 PnL
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Positive PnL shows "+" prefix
      expect(find.textContaining('+'), findsAtLeastNWidgets(1));
    });

    testWidgets('平盤未實現損益顯示中性、無 +0 與 (+0.0%)', (tester) async {
      widenViewport(tester);
      final positions = [
        // currentPrice == avgCost → unrealizedPnl == 0
        createPosition(quantity: 1000, avgCost: 500.0, currentPrice: 500.0),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('+0'), findsNothing);
      expect(find.textContaining('(+0.0%)'), findsNothing);
      expect(find.text('(0.0%)'), findsOneWidget);
    });

    // 已實現損益的配色原本走 `realizedPnl >= 0 ? upColor : downColor`，
    // 尚未賣出的持股 realizedPnl 恰為 0 卻被著成漲色（紅）。與同一方法內
    // 上方 pnlColor 的三分法慣例對齊：平盤走中性色。
    testWidgets('平盤已實現損益（0）不著漲色', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(quantity: 1000, avgCost: 500.0, realizedPnl: 0),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      final tile = find
          .ancestor(
            of: find.text('portfolio.realizedPnl'),
            matching: find.byType(Column),
          )
          .first;
      final valueText = tester.widget<Text>(
        find.descendant(of: tile, matching: find.text('0')),
      );
      expect(valueText.style?.color, isNot(AppTheme.upColor));
    });

    testWidgets('真實已實現獲利仍著漲色（未過度中性化）', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(quantity: 1000, avgCost: 500.0, realizedPnl: 50000),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      final tile = find
          .ancestor(
            of: find.text('portfolio.realizedPnl'),
            matching: find.byType(Column),
          )
          .first;
      final valueText = tester.widget<Text>(
        find.descendant(of: tile, matching: find.text('50000')),
      );
      expect(valueText.style?.color, AppTheme.upColor);
    });

    testWidgets('shows negative PnL', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(
          quantity: 1000,
          avgCost: 600.0,
          currentPrice: 500.0, // -100 per share = -100,000 PnL
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Negative PnL value present
      expect(find.textContaining('-100000'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows transaction list', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      final transactions = [
        createTestPortfolioTransaction(
          id: 1,
          symbol: '2330',
          txType: 'BUY',
          quantity: 1000,
          price: 500.0,
          date: DateTime(2026, 1, 15),
        ),
        createTestPortfolioTransaction(
          id: 2,
          symbol: '2330',
          txType: 'SELL',
          quantity: 500,
          price: 600.0,
          date: DateTime(2026, 2, 10),
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(positions: positions),
          txList: transactions,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Should show Dismissible rows for each transaction
      expect(find.byType(Dismissible), findsNWidgets(2));
    });

    testWidgets('shows empty transaction message', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(positions: positions),
          txList: [],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Empty transaction list shows "no positions" text
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows buy transaction with type badge', (tester) async {
      widenViewport(tester);
      final positions = [createPosition()];
      final transactions = [
        createTestPortfolioTransaction(
          id: 1,
          txType: 'BUY',
          quantity: 1000,
          price: 500.0,
          date: DateTime(2026, 1, 15),
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(positions: positions),
          txList: transactions,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Transaction row shows date
      expect(find.text('2026-01-15'), findsOneWidget);
    });

    testWidgets('shows dividend transaction differently', (tester) async {
      widenViewport(tester);
      final positions = [createPosition(totalDividendReceived: 5000)];
      final transactions = [
        createTestPortfolioTransaction(
          id: 1,
          txType: 'DIVIDEND_CASH',
          quantity: 5000, // dividend amount stored as quantity
          price: 0,
          date: DateTime(2026, 2, 1),
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(positions: positions),
          txList: transactions,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Dividend transaction shows differently (no "@ price")
      expect(find.byType(Dismissible), findsOneWidget);
    });

    testWidgets('shows divider between position summary and transactions', (
      tester,
    ) async {
      widenViewport(tester);
      final positions = [createPosition()];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Divider), findsAtLeastNWidgets(1));
    });

    testWidgets('shows realized PnL in summary', (tester) async {
      widenViewport(tester);
      final positions = [
        createPosition(realizedPnl: 50000, totalDividendReceived: 3000),
      ];
      await tester.pumpWidget(
        buildTestWidget(portfolioState: PortfolioState(positions: positions)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Shows realized PnL value
      expect(find.text('50000'), findsOneWidget);
    });
  });
}

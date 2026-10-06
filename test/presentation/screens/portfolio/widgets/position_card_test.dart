import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/position_card.dart';

import '../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  PortfolioPositionData createPosition({
    String symbol = '2330',
    String? stockName = '台積電',
    double quantity = 1000,
    double avgCost = 500.0,
    double realizedPnl = 0,
    double totalDividendReceived = 0,
    double? currentPrice = 580.0,
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

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(3000, 2400);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('PositionCard', () {
    testWidgets('displays symbol and stock name', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PositionCard(position: createPosition(), onTap: () {})),
      );

      expect(find.text('2330'), findsOneWidget);
      expect(find.text('台積電'), findsOneWidget);
    });

    testWidgets('displays chevron_right icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(PositionCard(position: createPosition(), onTap: () {})),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      widenViewport(tester);
      bool tapped = false;
      await tester.pumpWidget(
        buildTestApp(
          PositionCard(position: createPosition(), onTap: () => tapped = true),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('handles null stockName gracefully', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PositionCard(position: createPosition(stockName: null), onTap: () {}),
        ),
      );

      expect(find.text('2330'), findsOneWidget);
      expect(find.byType(PositionCard), findsOneWidget);
    });

    testWidgets('平盤未實現損益顯示中性、無 +0 與 (+0.0%)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PositionCard(
            // currentPrice == avgCost → unrealizedPnl == 0
            position: createPosition(avgCost: 500.0, currentPrice: 500.0),
            onTap: () {},
          ),
        ),
      );

      expect(find.textContaining('(+0.0%)'), findsNothing);
      expect(find.text('(0.0%)'), findsOneWidget);
      final pnl = tester.widget<Text>(find.text('0'));
      expect(pnl.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    });

    testWidgets('handles null currentPrice', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          PositionCard(
            position: createPosition(currentPrice: null),
            onTap: () {},
          ),
        ),
      );

      expect(find.byType(PositionCard), findsOneWidget);
    });
  });

  group('盤中即時報價', () {
    PortfolioPositionData p() => const PortfolioPositionData(
      symbol: '2330',
      stockName: '台積電',
      quantity: 1000,
      avgCost: 500,
      realizedPnl: 0,
      totalDividendReceived: 0,
      currentPrice: 612,
    );

    testWidgets('例外標示顯示在卡片上', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          PositionCard(
            position: p(),
            live: const PositionCardLive(caption: 'liveQuote.cardPaused'),
            onTap: () {},
          ),
        ),
      );
      expect(find.text('liveQuote.cardPaused'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 現價閃色最濃時 $brightness:對卡片實際底色 ≥ 4.5', (tester) async {
        Widget card(int id) => buildTestApp(
          PositionCard(
            position: p(),
            live: PositionCardLive(flash: LiveQuoteFlash(id: id, up: false)),
            onTap: () {},
          ),
          brightness: brightness,
        );
        await tester.pumpWidget(card(1));
        await tester.pumpWidget(card(2));
        await tester.pump();

        final tint =
            (tester
                        .widget<DecoratedBox>(find.byKey(PriceFlash.tintKey))
                        .decoration
                    as BoxDecoration)
                .color!;
        final cardColor = Theme.of(
          tester.element(find.byKey(PriceFlash.tintKey)),
        ).colorScheme.surfaceContainerLow;
        final text = tester
            .widget<RichText>(
              find.descendant(
                of: find.byKey(PriceFlash.tintKey),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .color!;
        expect(
          ColorContrast.ratio(
            text,
            ColorContrast.compositeOver(
              tint.withValues(alpha: 1),
              cardColor,
              tint.a,
            ),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });

      testWidgets('🚨 例外標示灰字 $brightness:對卡片實際底色 ≥ 4.5', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            PositionCard(
              position: p(),
              live: const PositionCardLive(caption: 'liveQuote.cardPaused'),
              onTap: () {},
            ),
            brightness: brightness,
          ),
        );
        final text = tester
            .widget<Text>(find.text('liveQuote.cardPaused'))
            .style!
            .color!;
        final cardColor = Theme.of(
          tester.element(find.text('liveQuote.cardPaused')),
        ).colorScheme.surfaceContainerLow;
        expect(ColorContrast.ratio(text, cardColor), greaterThanOrEqualTo(4.5));
      });
    }
  });
}

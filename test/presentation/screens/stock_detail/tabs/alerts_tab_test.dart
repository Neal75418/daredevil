import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/alert_quick_set.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/alerts_tab.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

import '../../../../helpers/provider_test_helpers.dart';
import '../../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeStockDetailNotifier extends StockDetailNotifier {
  FakeStockDetailNotifier(super.symbol);

  StockDetailState initialState = const StockDetailState();

  @override
  StockDetailState build() => initialState;

  @override
  Future<void> loadInsiderData() async {}

  @override
  Future<void> loadData() async {}
}

class FakePriceAlertNotifier extends PriceAlertNotifier {
  PriceAlertState initialState = const PriceAlertState();

  @override
  PriceAlertState build() => initialState;

  @override
  Future<void> loadAlerts() async {}

  @override
  Future<void> deleteAlert(int id) async {}

  @override
  Future<void> toggleAlert(int id, bool isActive) async {}

  @override
  Future<bool> createAlert({
    required String symbol,
    required AlertType alertType,
    required double targetValue,
    String? note,
  }) async {
    return true;
  }
}

// ==========================================
// Test Helpers
// ==========================================

PriceAlertEntry createAlert({
  int id = 1,
  String symbol = '2330',
  String alertType = 'ABOVE',
  double targetValue = 900.0,
  bool isActive = true,
  String? note,
}) {
  return PriceAlertEntry(
    id: id,
    symbol: symbol,
    alertType: alertType,
    targetValue: targetValue,
    isActive: isActive,
    note: note,
    createdAt: DateTime(2026, 2, 13),
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
    StockDetailState? stockState,
    PriceAlertState? alertState,
    Brightness brightness = Brightness.light,
    _FixedCenter? liveCenter,
    DateTime? now,
  }) {
    final stock = stockState ?? const StockDetailState();
    final alert = alertState ?? const PriceAlertState();
    return buildProviderTestApp(
      const AlertsTab(symbol: '2330'),
      overrides: [
        stockDetailProvider.overrideWith2((symbol) {
          final n = FakeStockDetailNotifier(symbol);
          n.initialState = stock;
          return n;
        }),
        priceAlertProvider.overrideWith(() {
          final n = FakePriceAlertNotifier();
          n.initialState = alert;
          return n;
        }),
        if (now != null) appClockProvider.overrideWithValue(_Clock(now)),
      ],
      brightness: brightness,
      liveQuoteCenter: liveCenter == null ? null : () => liveCenter,
    );
  }

  group('AlertsTab', () {
    testWidgets('shows loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(alertState: const PriceAlertState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no alerts', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    });

    testWidgets('shows section header with bell icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SectionHeader), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    });

    testWidgets('shows current price card when price available', (
      tester,
    ) async {
      widenViewport(tester);
      final stockState = const StockDetailState().copyWith(
        latestPrice: DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 2, 13),
          close: 850.0,
          volume: 50000,
        ),
      );
      await tester.pumpWidget(buildTestWidget(stockState: stockState));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.monetization_on), findsOneWidget);
      expect(find.textContaining('850.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('hides current price card when no price', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.monetization_on), findsNothing);
    });

    testWidgets('shows alert card with description', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'ABOVE', targetValue: 900.0)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Card), findsAtLeastNWidgets(1));
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('shows switch for toggling alert', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert()];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('shows note when present', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(note: 'Buy signal')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Buy signal'), findsOneWidget);
    });

    testWidgets('shows multiple alert cards', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, alertType: 'ABOVE', targetValue: 900.0),
        createAlert(id: 2, alertType: 'BELOW', targetValue: 700.0),
        createAlert(id: 3, alertType: 'CHANGE_PCT', targetValue: 5.0),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.byType(Switch), findsNWidgets(3));
    });

    testWidgets('shows correct icon for above alert type', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'ABOVE')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      // 2026-08-16:above/below 改用「穿越門檻線」的中性圖示——趨勢箭頭
      // (trending_*) 是股價趨勢專用,兩者共用視覺語言會讓同一檔股票在
      // 自選股頁與警示頁顯示相反方向(實機:仁寶漲停卻是綠色下箭頭)。
      expect(find.byIcon(Icons.vertical_align_top), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.trending_up), findsNothing);
    });

    testWidgets('shows correct icon for below alert type', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'BELOW')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.vertical_align_bottom), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.trending_down), findsNothing);
    });

    testWidgets('filters alerts by symbol', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, symbol: '2330', alertType: 'ABOVE'),
        createAlert(id: 2, symbol: '2317', alertType: 'BELOW'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Only 1 alert card — the one for 2330
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert()];
      await tester.pumpWidget(
        buildTestWidget(
          alertState: PriceAlertState(alerts: alerts),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AlertsTab), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('shows percent icon for changePct alert', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'CHANGE_PCT', targetValue: 5.0)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.percent), findsAtLeastNWidgets(1));
    });

    testWidgets('shows bar_chart icon for volumeSpike alert', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(alertType: 'VOLUME_SPIKE', targetValue: 200.0),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.bar_chart), findsAtLeastNWidgets(1));
    });

    testWidgets('inactive alert shows switch off', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(isActive: false)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
    });

    testWidgets('active alert shows switch on', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(isActive: true)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('alert card is wrapped in Dismissible', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert()];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Dismissible), findsOneWidget);
    });

    testWidgets('shows add alert icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
    });

    testWidgets('shows multiple icon types for mixed alerts', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, alertType: 'ABOVE'),
        createAlert(id: 2, alertType: 'BELOW'),
        createAlert(id: 3, alertType: 'CHANGE_PCT', targetValue: 3.0),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.byIcon(Icons.vertical_align_top), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.vertical_align_bottom), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.percent), findsAtLeastNWidgets(1));
    });

    testWidgets('hides note subtitle when note is null', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(note: null)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      final listTile = tester.widget<ListTile>(find.byType(ListTile));
      expect(listTile.subtitle, isNull);
    });
  });

  group('距現價多少(2026-10-06,路線圖第 2 項)', () {
    final morning = DateTime(2026, 10, 6, 10, 15);
    // 30 根日線(5MA 等快捷鈕才算得出來);最後一筆 10/5 收 880
    final history = [
      for (var i = 0; i < 30; i++)
        DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 8, 25).add(Duration(days: i)),
          open: 870,
          high: 885,
          low: 865,
          close: i == 29 ? 880 : 870,
          volume: 1000,
        ),
    ];
    final stockState = StockDetailState(
      price: StockPriceState(
        latestPrice: DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 10, 5),
          close: 880,
          priceChange: -5,
        ),
        priceHistory: history,
      ),
    );
    _FixedCenter live(double price) => _FixedCenter(
      LiveQuoteState(
        entries: {
          '2330': LiveQuoteEntry(
            symbol: '2330',
            date: DateTime(2026, 10, 6),
            price: price,
            displaySource: LiveDisplaySource.trade,
            previousClose: 880,
            quoteTime: '10:14:50',
            isClosingQuote: false,
          ),
        },
      ),
    );

    testWidgets('🚨 現價與距離用即時價(個股頁已在抓這一檔,不多發請求)', (tester) async {
      widenViewport(tester);
      // 跌破 885:盤後收 880 已越過,即時 890 還沒——用了即時才會顯示距離
      await tester.pumpWidget(
        buildTestWidget(
          stockState: stockState,
          alertState: PriceAlertState(
            alerts: [createAlert(alertType: 'BELOW', targetValue: 885)],
          ),
          liveCenter: live(890),
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('890.00'), findsWidgets);
      expect(find.text('alert.distanceFromPrice'), findsOneWidget);
      expect(find.text('alert.reached'), findsNothing);
    });

    testWidgets('現價已越過目標 → 已達到', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: stockState,
          alertState: PriceAlertState(
            alerts: [createAlert(alertType: 'BELOW', targetValue: 885)],
          ),
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('alert.reached'), findsOneWidget);
    });

    testWidgets('🚨 盤中有即時價 → 快捷鈕不顯示「以昨收判斷」;沒有才顯示', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: stockState,
          liveCenter: live(890),
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(AlertQuickSet.staleWarningKey), findsNothing);
    });

    testWidgets('盤中沒有今天的價格 → 顯示「以昨收判斷」', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(stockState: stockState, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(AlertQuickSet.staleWarningKey), findsOneWidget);
    });

    testWidgets('🚨 新增提醒面板的「目前價格」跟著即時價更新(與頁首同一個數字)', (tester) async {
      widenViewport(tester);
      final center = live(890);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: stockState,
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('alert.create').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      center.emit(
        LiveQuoteState(
          entries: {
            '2330': LiveQuoteEntry(
              symbol: '2330',
              date: DateTime(2026, 10, 6),
              price: 895,
              displaySource: LiveDisplaySource.trade,
              previousClose: 880,
              quoteTime: '10:15:05',
              isClosingQuote: false,
            ),
          },
        ),
      );
      await tester.pump();
      expect(find.textContaining('890.00'), findsNothing);
      expect(
        find.textContaining('895.00'),
        findsNWidgets(2),
        reason: '分頁現價卡＋面板',
      );
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 距離灰字 $brightness:對卡片實際底色 ≥ 4.5', (tester) async {
        widenViewport(tester);
        await tester.pumpWidget(
          buildTestWidget(
            stockState: stockState,
            alertState: PriceAlertState(
              alerts: [createAlert(alertType: 'BELOW', targetValue: 885)],
            ),
            liveCenter: live(890),
            now: morning,
            brightness: brightness,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final finder = find.text('alert.distanceFromPrice');
        final color = tester.widget<Text>(finder).style!.color!;
        final card = tester.widget<Material>(
          find.ancestor(of: finder, matching: find.byType(Material)).first,
        );
        expect(
          ColorContrast.ratio(color, card.color!),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) {}

  @override
  void unregister(Object owner) {}

  @override
  void setAppVisible(bool visible) {}

  void emit(LiveQuoteState s) => state = s;
}

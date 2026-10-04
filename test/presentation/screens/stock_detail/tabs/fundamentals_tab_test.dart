import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/data/models/finmind/per.dart';
import 'package:daredevil/data/models/finmind/revenue.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_tab.dart';
import 'package:daredevil/presentation/widgets/metric_card.dart';
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
  Future<void> loadFundamentals() async {}

  @override
  Future<void> loadData() async {}
}

class FakeSettingsNotifier extends SettingsNotifier {
  SettingsState initialState = const SettingsState();

  @override
  SettingsState build() => initialState;

  @override
  void setThemeMode(ThemeMode mode) {}

  @override
  void setShowROCYear(bool value) {}

  @override
  void setShowWarningBadges(bool value) {}

  @override
  void setInsiderNotifications(bool value) {}

  @override
  void setDisposalUrgentAlerts(bool value) {}

  @override
  void setLimitAlerts(bool value) {}

  @override
  void setCacheDurationMinutes(int minutes) {}

  @override
  void setAutoUpdateEnabled(bool value) {}
}

// ==========================================
// Tests
// ==========================================

void main() {
  DividendSummary summary({
    DividendYearStatus status = DividendYearStatus.paid,
    TrailingYield trailing = const TrailingYieldNone(),
  }) => DividendSummary(
    displayEnd: DateTime(2026, 10, 2),
    parValueTen: true,
    current: DividendYearRow(year: 2026, status: status, cash: 1),
    pastYears: [
      for (var y = 2025; y >= 2021; y--)
        DividendYearRow(year: y, status: status, cash: 1),
    ],
    average: null,
    trailingYield: trailing,
  );

  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestWidget({
    StockDetailState? stockState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
    String symbol = '2330',
  }) {
    final stock = stockState ?? const StockDetailState();
    final settings = settingsState ?? const SettingsState();
    return buildProviderTestApp(
      FundamentalsTab(symbol: symbol),
      overrides: [
        stockDetailProvider.overrideWith2((symbol) {
          final n = FakeStockDetailNotifier(symbol);
          n.initialState = stock;
          return n;
        }),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = settings;
          return n;
        }),
      ],
      brightness: brightness,
    );
  }

  group('FundamentalsTab', () {
    testWidgets('shows three metric cards with icons', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(MetricCard), findsNWidgets(3));
      // P/E icon, P/B icon, Yield icon
      expect(find.byIcon(Icons.analytics), findsOneWidget);
      expect(find.byIcon(Icons.account_balance), findsOneWidget);
      expect(find.byIcon(Icons.percent), findsAtLeastNWidgets(1));
    });

    testWidgets('shows dash for empty PER values', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // No latestPER → all show "-"
      expect(find.text('-'), findsAtLeastNWidgets(3));
    });

    testWidgets('shows revenue section header', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SectionHeader), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.trending_up), findsAtLeastNWidgets(1));
    });

    testWidgets('shows EPS section header', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.bar_chart), findsAtLeastNWidgets(1));
    });

    testWidgets('shows dividend section header', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.payments), findsOneWidget);
    });

    testWidgets('shows loading state for fundamentals', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        isLoadingFundamentals: true,
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      // Loading state shows progress indicators
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });

    testWidgets('shows PER values when data is present', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        latestPER: const FinMindPER(
          stockId: '2330',
          date: '2026-02-20',
          per: 18.5,
          pbr: 4.32,
          dividendYield: 2.15,
        ),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('18.5'), findsOneWidget);
      expect(find.text('4.32'), findsOneWidget);
      expect(find.text('2.15%'), findsOneWidget);
    });

    testWidgets('shows revenue table when data exists', (tester) async {
      widenViewport(tester);
      final revenues = [
        FinMindRevenue(
          stockId: '2330',
          date: '2026-01-10',
          revenue: 250000000,
          revenueMonth: 1,
          revenueYear: 2026,
        ),
      ];
      final state = const StockDetailState().copyWith(revenueHistory: revenues);
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FundamentalsTab), findsOneWidget);
      // Revenue table is rendered (not the empty/loading state)
      expect(find.byType(SectionHeader), findsAtLeastNWidgets(3));
    });

    // 既有缺陷（Task 9 修復）：P/E `#3498DB`、殖利率 `AppTheme.dividendColor`
    // (`#A78BFA`) 對淺色主題 surfaceContainerLow 對比不足（純色背景分別
    // 2.9912:1／2.5817:1，疊色後 2.7080:1／2.3730:1，皆低於 MetricCard 圖示
    // 3.0:1 門檻）；P/B `#9B59B6` 則是深色主題疊色後對 surfaceContainerLow
    // 僅 2.8907:1 不足（`ColorContrast` 精算，brief 表格未列出的第三個
    // 缺陷）。三者皆應改用 CategoryColors.chartPaletteFor(brightness) 取色，
    // 與 insider_tab.dart 的既有做法一致。
    testWidgets('metric card accent colors use chartPalette (dark theme)', (
      tester,
    ) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        latestPER: const FinMindPER(
          stockId: '2330',
          date: '2026-02-20',
          per: 18.5,
          pbr: 4.32,
          dividendYield: 2.15,
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: state, brightness: Brightness.dark),
      );
      await tester.pump(const Duration(seconds: 1));

      final cards = tester
          .widgetList<MetricCard>(find.byType(MetricCard))
          .toList();
      expect(cards, hasLength(3));
      final palette = CategoryColors.chartPaletteFor(Brightness.dark);
      expect(cards[0].accentColor, palette[0], reason: 'P/E 應取藍 500');
      expect(cards[1].accentColor, palette[1], reason: 'P/B 應取橘 500');
      expect(cards[2].accentColor, palette[2], reason: '殖利率應取紫 500');
    });

    testWidgets('metric card accent colors use chartPalette (light theme)', (
      tester,
    ) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        latestPER: const FinMindPER(
          stockId: '2330',
          date: '2026-02-20',
          per: 18.5,
          pbr: 4.32,
          dividendYield: 2.15,
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: state, brightness: Brightness.light),
      );
      await tester.pump(const Duration(seconds: 1));

      final cards = tester
          .widgetList<MetricCard>(find.byType(MetricCard))
          .toList();
      expect(cards, hasLength(3));
      final palette = CategoryColors.chartPaletteFor(Brightness.light);
      expect(cards[0].accentColor, palette[0], reason: 'P/E 應取藍 600');
      expect(cards[1].accentColor, palette[1], reason: 'P/B 應取橘 600');
      expect(cards[2].accentColor, palette[2], reason: '殖利率應取紫 600');
    });

    testWidgets('股利摘要已載入：顯示股利表', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        dividendSummary: summary(),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(DividendSummaryTable), findsOneWidget);
    });

    testWidgets('🚨 全部建置中：顯示「股利資料建置中」、不畫表', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        dividendSummary: summary(status: DividendYearStatus.building),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('stockDetail.dividendBuilding'), findsOneWidget);
      expect(find.byType(DividendSummaryTable), findsNothing);
    });

    testWidgets('股利讀取失敗（沒有摘要、有錯誤）：顯示暫無法取得', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        fundamentalsError: '部分基本面資料暫無法取得（股利）',
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('stockDetail.dividendUnavailable'), findsOneWidget);
      expect(find.byType(DividendSummaryTable), findsNothing);
    });

    testWidgets('ETF：殖利率卡顯示近一年殖利率', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        dividendSummary: summary(trailing: const TrailingYieldValue(0.0209)),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: state, symbol: '0050'),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2.09%'), findsOneWidget);
      expect(find.text('stockDetail.trailingYieldLabel'), findsOneWidget);
      expect(find.text('stockDetail.yieldLabel'), findsNothing);
    });

    testWidgets('ETF：近一年無配息', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState().copyWith(
            dividendSummary: summary(trailing: const TrailingYieldNone()),
          ),
          symbol: '0050',
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('stockDetail.trailingYieldNone'), findsOneWidget);
    });

    // 同一個測試內重 pump 新的 override 不會重建已建立的 notifier，所以分開
    testWidgets('ETF：近一年殖利率建置中', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState().copyWith(
            dividendSummary: summary(trailing: const TrailingYieldBuilding()),
          ),
          symbol: '0050',
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('stockDetail.dividendStatusBuilding'), findsOneWidget);
    });

    testWidgets('一般股票：殖利率卡照舊用官方估值、不看近一年殖利率', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        latestPER: const FinMindPER(
          stockId: '2330',
          date: '2026-02-20',
          per: 18.5,
          pbr: 4.32,
          dividendYield: 2.15,
        ),
        dividendSummary: summary(trailing: const TrailingYieldValue(0.05)),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2.15%'), findsOneWidget);
      expect(find.text('5.00%'), findsNothing);
      expect(find.text('stockDetail.yieldLabel'), findsOneWidget);
    });
  });
}

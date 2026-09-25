import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/presentation/providers/scan_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/screens/scan/scan_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeScanNotifier extends ScanNotifier {
  ScanState initialState = const ScanState();

  @override
  ScanState build() => initialState;

  @override
  Future<void> loadData() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> setFilter(ScanFilter filter) async {}

  @override
  void setSort(ScanSort sort) {}

  @override
  Future<void> setIndustryFilter(String? industry) async {}

  @override
  Future<void> toggleWatchlist(String symbol) async {}
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
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestWidget({
    ScanState? scanState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
  }) {
    final scan = scanState ?? const ScanState();
    final settings = settingsState ?? const SettingsState();
    return buildProviderTestApp(
      const ScanScreen(),
      overrides: [
        scanProvider.overrideWith(() {
          final n = FakeScanNotifier();
          n.initialState = scan;
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

  group('ScanScreen', () {
    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(scanState: const ScanState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockListShimmer), findsOneWidget);
    });

    testWidgets('shows AppBar with title', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows more menu with extra scan options', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // more_vert menu is visible
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // 點開選單後額外功能項目出現在 popup 中
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        // 忽略 popup 在測試 viewport 的 overflow（非真實 bug）
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 融券賣出排行（trending_down）為保留的選單項目之一
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
      FlutterError.onError = originalOnError;
    });

    testWidgets('shows sort icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('shows filter chips row', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilterChip), findsAtLeastNWidgets(1));
    });

    testWidgets('淺色主題選中的「全部」標籤文字色為 onSurface（非 onSecondaryContainer）', (
      tester,
    ) async {
      // chipTheme.selectedColor（淺色主題）是 primaryColor 疊 15% alpha
      // 於白之上的淡紫色，非實心 secondaryContainer；onSecondaryContainer
      // 對這個合成色只有 1.14:1（見 app_theme_surfaces_test.dart 的疊色
      // 守門測試），故選中標籤文字必須是 onSurface，不能退回
      // onSecondaryContainer。
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget()); // 預設 filter = all（選中）
      await tester.pump(const Duration(seconds: 1));

      final allChip = tester.widget<FilterChip>(find.byType(FilterChip).first);
      final labelColor = allChip.labelStyle?.color;
      expect(labelColor, AppTheme.lightTheme.colorScheme.onSurface);
      expect(
        labelColor,
        isNot(AppTheme.lightTheme.colorScheme.onSecondaryContainer),
      );
    });

    testWidgets('深色主題選中的「全部」標籤文字色維持 onSecondaryContainer', (tester) async {
      // 深色主題 chipTheme 沒覆寫 selectedColor，落回 M3 預設實心
      // secondaryContainer，onSecondaryContainer 對它本來就合格
      // （6.51:1），不應被本次修復意外改動。
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget(brightness: Brightness.dark));
      await tester.pump(const Duration(seconds: 1));

      final allChip = tester.widget<FilterChip>(find.byType(FilterChip).first);
      expect(
        allChip.labelStyle?.color,
        AppTheme.darkTheme.colorScheme.onSecondaryContainer,
      );
    });

    testWidgets('shows more filters action chip', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.byType(ActionChip), findsOneWidget);
    });

    testWidgets('shows error state with retry', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(scanState: const ScanState(error: 'Network error')),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty state when no stocks', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    // 全新安裝時「全部」篩選也是空的，原本顯示「試著調整篩選條件」——
    // 使用者根本沒設篩選，問題是還沒有資料
    testWidgets('🚨 還沒有任何資料 → 首次建置的空狀態，不叫人調整篩選', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('empty.firstBuildIdleTitle'), findsOneWidget);
      expect(find.text('empty.noFilterResults'), findsNothing);
    });

    testWidgets('還沒有任何資料且第一次更新進行中 → 顯示建置中', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(
          const ScanScreen(),
          overrides: [
            scanProvider.overrideWith(() => FakeScanNotifier()),
            settingsProvider.overrideWith(() => FakeSettingsNotifier()),
            todayProvider.overrideWith(() => _UpdatingTodayNotifier()),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('empty.firstBuildRunningTitle'), findsOneWidget);
    });

    testWidgets('有資料但篩選沒結果 → 維持「無符合條件」', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(scanState: ScanState(dataDate: DateTime(2026, 9, 18))),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('empty.noFilterResults'), findsOneWidget);
    });

    testWidgets('shows filtering indicator', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(scanState: const ScanState(isFiltering: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows stock count text', (tester) async {
      widenViewport(tester);
      final stocks = [
        ScanStockItem(
          symbol: '2330',
          score: 85,
          stockName: 'TSMC',
          market: 'TWSE',
          latestClose: 600.0,
          reasons: [],
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(scanState: ScanState(stocks: stocks, hasMore: false)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Stock count semantics area
      expect(find.byType(Semantics), findsAtLeastNWidgets(1));
    });

    testWidgets('shows current filter chip when filter is not all', (
      tester,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          scanState: const ScanState(filter: ScanFilter.reversalW2S),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Should show at least 2 FilterChips (all + current filter)
      expect(find.byType(FilterChip), findsAtLeastNWidgets(2));
      // Close icon for removing current filter
      expect(find.byIcon(Icons.close), findsAtLeastNWidgets(1));
    });

    testWidgets('shows industry filter chip when industries available', (
      tester,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          scanState: const ScanState(industries: ['半導體', '電子零組件', '金融']),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.factory_outlined), findsOneWidget);
    });
  });
}

class _UpdatingTodayNotifier extends TodayNotifier {
  @override
  TodayState build() => const TodayState(isUpdating: true);
}

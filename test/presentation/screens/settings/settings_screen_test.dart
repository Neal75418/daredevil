import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/screens/settings/settings_screen.dart';

/// 共享測試 DB（避免 Drift multiple-database warning）
final _testDb = AppDatabase.forTesting();

// ==========================================
// Test Asset Loader — returns empty map so .tr() returns the key itself
// ==========================================

class _EmptyAssetLoader extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

// ==========================================
// Fake Notifier
// ==========================================

class FakeSettingsNotifier extends SettingsNotifier {
  SettingsState initialState = const SettingsState();

  @override
  SettingsState build() => initialState;

  @override
  void setThemeMode(ThemeMode mode) {}

  @override
  void setLocale(AppLocale locale) {}

  @override
  void setShowWarningBadges(bool value) {}

  @override
  void setInsiderNotifications(bool value) {}

  @override
  void setDisposalUrgentAlerts(bool value) {}

  @override
  void setLimitAlerts(bool value) {}

  @override
  void setShowROCYear(bool value) {}

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
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestWidget({
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
  }) {
    final s = settingsState ?? const SettingsState();
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(_testDb),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = s;
          return n;
        }),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'TW'),
        assetLoader: _EmptyAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: brightness == Brightness.light
                ? AppTheme.lightTheme
                : AppTheme.darkTheme,
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      ),
    );
  }

  group('SettingsScreen', () {
    testWidgets('renders all settings sections', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SettingsScreen), findsOneWidget);

      // Theme icon (system by default)
      expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);

      // Language icon
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);

      // Warning badges icon
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      // About icon
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

      // Version icon
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('「關於」含免責聲明全文與資料來源顯名', (tester) async {
      // 政府資料開放授權條款要求顯名，未顯名視為自始未取得授權
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      // 設定頁有持續動畫，pumpAndSettle 會逾時；推進到對話框轉場結束即可
      await tester.pump(const Duration(seconds: 1));

      for (final key in [
        'disclaimer.point1',
        'disclaimer.point4',
        'settings.dataSourcesTitle',
        'settings.dataSources',
      ]) {
        expect(find.text(key), findsOneWidget, reason: key);
      }
    });

    testWidgets('shows warning badges switch as enabled', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(
        buildTestWidget(
          settingsState: const SettingsState(showWarningBadges: true),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.isNotEmpty, isTrue);
      expect(switches.first.value, isTrue);
    });

    testWidgets('shows version info', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // PackageInfo 在測試環境未初始化，version tile 存在但 trailing 為空
      expect(find.text('settings.version'), findsOneWidget);
    });

    testWidgets('shows cache duration setting', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(
        buildTestWidget(
          settingsState: const SettingsState(cacheDurationMinutes: 30),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.cached_rounded), findsOneWidget);
    });

    testWidgets('shows back button', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows ROC year switch', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    });

    testWidgets('shows dark theme icon when dark mode selected', (
      tester,
    ) async {
      widenViewport(tester);

      await tester.pumpWidget(
        buildTestWidget(
          settingsState: const SettingsState(themeMode: ThemeMode.dark),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    });
  });
}

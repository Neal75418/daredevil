/// Golden test: SettingsScreen
///
/// 驗證設定畫面在 light/dark 模式下的視覺一致性。
@Tags(['golden'])
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/screens/settings/settings_screen.dart';

import '../../../helpers/widget_test_helpers.dart';

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
  void setPriceFlash(bool value) {}

  @override
  void setCacheDurationMinutes(int minutes) {}

  @override
  void setAutoUpdateEnabled(bool value) {}
}

class _EmptyAssetLoader extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

// ==========================================
// Helpers
// ==========================================

void widenViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget buildTestWidget({
  SettingsState? settingsState,
  Brightness brightness = Brightness.light,
}) {
  final s = settingsState ?? const SettingsState();
  final db = AppDatabase.forTesting();
  addTearDown(() => db.close());
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
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

// ==========================================
// Golden Tests
// ==========================================

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('SettingsScreen Golden', () {
    testWidgets('light mode', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_screen_light.png'),
      );
    });

    testWidgets('dark mode', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget(brightness: Brightness.dark));
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_screen_dark.png'),
      );
    });
  });
}

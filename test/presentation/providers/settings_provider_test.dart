import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/presentation/providers/settings_provider.dart';

// ==========================================
// Tests
// ==========================================

void main() {
  // ==========================================
  // AppLocale
  // ==========================================

  group('AppLocale', () {
    test('toLocale creates correct Locale for zhTW', () {
      final locale = AppLocale.zhTW.toLocale();
      expect(locale.languageCode, 'zh');
      expect(locale.countryCode, 'TW');
    });

    test('toLocale creates correct Locale for en', () {
      final locale = AppLocale.en.toLocale();
      expect(locale.languageCode, 'en');
      expect(locale.countryCode, isNull);
    });

    test('fromString parses valid names', () {
      expect(AppLocale.fromString('zhTW'), AppLocale.zhTW);
      expect(AppLocale.fromString('en'), AppLocale.en);
    });

    test('fromString defaults to zhTW for null', () {
      expect(AppLocale.fromString(null), AppLocale.zhTW);
    });

    test('fromString defaults to zhTW for unknown', () {
      expect(AppLocale.fromString('unknown'), AppLocale.zhTW);
    });

    test('displayName returns readable names', () {
      expect(AppLocale.zhTW.displayName, '繁體中文');
      expect(AppLocale.en.displayName, 'English');
    });
  });

  // ==========================================
  // SettingsState
  // ==========================================

  group('SettingsState', () {
    test('has correct default values', () {
      const state = SettingsState();

      expect(state.themeMode, ThemeMode.system);
      expect(state.locale, AppLocale.zhTW);
      expect(state.showWarningBadges, isTrue);
      expect(state.insiderNotifications, isTrue);
      expect(state.disposalUrgentAlerts, isTrue);
      expect(state.limitAlerts, isTrue);
      expect(state.showROCYear, isTrue);
      expect(state.cacheDurationMinutes, 30);
      expect(state.autoUpdateEnabled, isFalse);
    });

    test('copyWith preserves unset values', () {
      const state = SettingsState(
        themeMode: ThemeMode.dark,
        locale: AppLocale.en,
        showWarningBadges: false,
      );

      final copied = state.copyWith();
      expect(copied.themeMode, ThemeMode.dark);
      expect(copied.locale, AppLocale.en);
      expect(copied.showWarningBadges, isFalse);
    });

    test('copyWith updates individual fields', () {
      const state = SettingsState();
      final updated = state.copyWith(
        themeMode: ThemeMode.dark,
        cacheDurationMinutes: 60,
        autoUpdateEnabled: true,
      );

      expect(updated.themeMode, ThemeMode.dark);
      expect(updated.cacheDurationMinutes, 60);
      expect(updated.autoUpdateEnabled, isTrue);
      // Unchanged
      expect(updated.locale, AppLocale.zhTW);
    });
  });

  // ==========================================
  // SettingsNotifier
  // ==========================================

  group('SettingsNotifier', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has default values', () {
      final state = container.read(settingsProvider);
      expect(state.themeMode, ThemeMode.system);
      expect(state.locale, AppLocale.zhTW);
    });

    test('loads settings from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode': ThemeMode.dark.index,
        'settings_locale': 'en',
        'settings_show_warning_badges': false,
        'settings_cache_duration_minutes': 60,
      });

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);

      // Force provider to build and load
      container2.read(settingsProvider);

      // Wait for async _loadSettings to complete
      await Future<void>.delayed(Duration.zero);

      final state = container2.read(settingsProvider);
      expect(state.themeMode, ThemeMode.dark);
      expect(state.locale, AppLocale.en);
      expect(state.showWarningBadges, isFalse);
      expect(state.cacheDurationMinutes, 60);
    });

    test('setThemeMode changes theme', () async {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setThemeMode(ThemeMode.dark);

      final state = container.read(settingsProvider);
      expect(state.themeMode, ThemeMode.dark);
    });

    test('setLocale changes locale', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setLocale(AppLocale.en);

      final state = container.read(settingsProvider);
      expect(state.locale, AppLocale.en);
    });

    test('setShowWarningBadges changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setShowWarningBadges(false);

      expect(container.read(settingsProvider).showWarningBadges, isFalse);
    });

    test('setInsiderNotifications changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setInsiderNotifications(false);

      expect(container.read(settingsProvider).insiderNotifications, isFalse);
    });

    test('setDisposalUrgentAlerts changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setDisposalUrgentAlerts(false);

      expect(container.read(settingsProvider).disposalUrgentAlerts, isFalse);
    });

    test('setLimitAlerts changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setLimitAlerts(false);

      expect(container.read(settingsProvider).limitAlerts, isFalse);
    });

    test('setShowROCYear changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setShowROCYear(false);

      expect(container.read(settingsProvider).showROCYear, isFalse);
    });

    test('setCacheDurationMinutes changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setCacheDurationMinutes(120);

      expect(container.read(settingsProvider).cacheDurationMinutes, 120);
    });

    test('setAutoUpdateEnabled changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setAutoUpdateEnabled(true);

      expect(container.read(settingsProvider).autoUpdateEnabled, isTrue);
    });
  });

  // ==========================================
  // Derived Providers
  // ==========================================

  group('Derived providers', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('themeModeProvider returns current theme', () {
      final themeMode = container.read(themeModeProvider);
      expect(themeMode, ThemeMode.system);
    });

    test('cacheDurationProvider returns cache minutes', () {
      final duration = container.read(cacheDurationProvider);
      expect(duration, 30);
    });
  });
}

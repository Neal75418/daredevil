import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/utils/logger.dart';

// ==================================================
// 設定鍵值
// ==================================================

const _keyThemeMode = 'settings_theme_mode';
const _keyLocale = 'settings_locale';
const _keyShowWarningBadges = 'settings_show_warning_badges';
const _keyInsiderNotifications = 'settings_insider_notifications';
const _keyDisposalUrgentAlerts = 'settings_disposal_urgent_alerts';
const _keyLimitAlerts = 'settings_limit_alerts';
const _keyShowROCYear = 'settings_show_roc_year';
const _keyCacheDurationMinutes = 'settings_cache_duration_minutes';
const _keyAutoUpdateEnabled = 'settings_auto_update_enabled';

// ==================================================
// 設定狀態
// ==================================================

/// 支援的語系
enum AppLocale {
  zhTW('zh', 'TW', '繁體中文'),
  en('en', null, 'English');

  const AppLocale(this.languageCode, this.countryCode, this.displayName);

  final String languageCode;
  final String? countryCode;
  final String displayName;

  Locale toLocale() => Locale(languageCode, countryCode);

  static AppLocale fromString(String? value) {
    if (value == null) return AppLocale.zhTW;
    return AppLocale.values.firstWhere(
      (l) => l.name == value,
      orElse: () => AppLocale.zhTW,
    );
  }
}

/// 設定狀態
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.locale = AppLocale.zhTW,
    this.showWarningBadges = true,
    this.insiderNotifications = true,
    this.disposalUrgentAlerts = true,
    this.limitAlerts = true,
    this.showROCYear = true,
    this.cacheDurationMinutes = 30,
    this.autoUpdateEnabled = false,
  });

  final ThemeMode themeMode;
  final AppLocale locale;

  /// 在自選股顯示警示標記（注意/處置/高質押）
  final bool showWarningBadges;

  /// 當自選股董監持股有重大變化時發送通知
  final bool insiderNotifications;

  /// 當自選股被列入處置股時發送緊急通知
  final bool disposalUrgentAlerts;

  /// 當自選股觸及漲跌停時顯示標記
  final bool limitAlerts;

  /// 財報頁面使用民國年顯示
  final bool showROCYear;

  /// API 快取存活時間（分鐘）
  final int cacheDurationMinutes;

  /// 是否啟用每日自動背景更新
  final bool autoUpdateEnabled;

  SettingsState copyWith({
    ThemeMode? themeMode,
    AppLocale? locale,
    bool? showWarningBadges,
    bool? insiderNotifications,
    bool? disposalUrgentAlerts,
    bool? limitAlerts,
    bool? showROCYear,
    int? cacheDurationMinutes,
    bool? autoUpdateEnabled,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      showWarningBadges: showWarningBadges ?? this.showWarningBadges,
      insiderNotifications: insiderNotifications ?? this.insiderNotifications,
      disposalUrgentAlerts: disposalUrgentAlerts ?? this.disposalUrgentAlerts,
      limitAlerts: limitAlerts ?? this.limitAlerts,
      showROCYear: showROCYear ?? this.showROCYear,
      cacheDurationMinutes: cacheDurationMinutes ?? this.cacheDurationMinutes,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
    );
  }
}

// ==================================================
// 設定 Notifier
// ==================================================

/// 設定狀態管理器（含持久化）
class SettingsNotifier extends Notifier<SettingsState> {
  /// 用於序列化儲存操作的互斥鎖
  /// 確保多個設定變更不會同時寫入造成競態條件
  Future<void>? _saveLock;

  @override
  SettingsState build() {
    _loadSettings();
    return const SettingsState();
  }

  /// 從 SharedPreferences 載入設定
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final themeModeIndex = prefs.getInt(_keyThemeMode);
      final localeString = prefs.getString(_keyLocale);

      final themeMode =
          themeModeIndex != null && themeModeIndex < ThemeMode.values.length
          ? ThemeMode.values[themeModeIndex]
          : ThemeMode.system;

      final locale = AppLocale.fromString(localeString);

      // 進階功能設定（預設開啟）
      final showWarningBadges = prefs.getBool(_keyShowWarningBadges) ?? true;
      final insiderNotifications =
          prefs.getBool(_keyInsiderNotifications) ?? true;
      final disposalUrgentAlerts =
          prefs.getBool(_keyDisposalUrgentAlerts) ?? true;
      final limitAlerts = prefs.getBool(_keyLimitAlerts) ?? true;
      final showROCYear = prefs.getBool(_keyShowROCYear) ?? true;
      final cacheDurationMinutes = prefs.getInt(_keyCacheDurationMinutes) ?? 30;
      final autoUpdateEnabled = prefs.getBool(_keyAutoUpdateEnabled) ?? false;

      state = SettingsState(
        themeMode: themeMode,
        locale: locale,
        showWarningBadges: showWarningBadges,
        insiderNotifications: insiderNotifications,
        disposalUrgentAlerts: disposalUrgentAlerts,
        limitAlerts: limitAlerts,
        showROCYear: showROCYear,
        cacheDurationMinutes: cacheDurationMinutes,
        autoUpdateEnabled: autoUpdateEnabled,
      );

      AppLogger.debug(
        'SettingsNotifier',
        '設定已載入: 主題=$themeMode, 語言=${locale.displayName}',
      );
    } catch (e) {
      AppLogger.warning('SettingsNotifier', '載入設定失敗', e);
    }
  }

  /// 儲存設定至 SharedPreferences
  ///
  /// 使用互斥鎖確保多個設定變更不會同時寫入。
  /// 每次儲存都會等待前一次儲存完成後再執行。
  Future<void> _saveSettings() async {
    // 等待前一次儲存完成
    final previousSave = _saveLock;
    if (previousSave != null) {
      await previousSave;
    }

    // 捕獲當前狀態快照（避免在 await 期間狀態被修改）
    final snapshot = state;

    // 建立新的儲存操作並捕獲引用
    final currentSave = _performSave(snapshot);
    _saveLock = currentSave;

    try {
      await currentSave;
    } finally {
      // 只有當前鎖仍是我們建立的鎖時才清除
      // 使用 identical 比較物件參照，避免 _saveLock == _saveLock 永遠為 true 的錯誤
      if (identical(_saveLock, currentSave)) {
        _saveLock = null;
      }
    }
  }

  /// 實際執行儲存操作
  Future<void> _performSave(SettingsState snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyThemeMode, snapshot.themeMode.index);
      await prefs.setString(_keyLocale, snapshot.locale.name);
      await prefs.setBool(_keyShowWarningBadges, snapshot.showWarningBadges);
      await prefs.setBool(
        _keyInsiderNotifications,
        snapshot.insiderNotifications,
      );
      await prefs.setBool(
        _keyDisposalUrgentAlerts,
        snapshot.disposalUrgentAlerts,
      );
      await prefs.setBool(_keyLimitAlerts, snapshot.limitAlerts);
      await prefs.setBool(_keyShowROCYear, snapshot.showROCYear);
      await prefs.setInt(
        _keyCacheDurationMinutes,
        snapshot.cacheDurationMinutes,
      );
      await prefs.setBool(_keyAutoUpdateEnabled, snapshot.autoUpdateEnabled);
    } catch (e) {
      AppLogger.warning('SettingsNotifier', '儲存設定失敗', e);
    }
  }

  /// 設定主題模式
  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '主題已變更: $mode');
  }

  /// 設定語系
  void setLocale(AppLocale locale) {
    state = state.copyWith(locale: locale);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '語言已變更: ${locale.displayName}');
  }

  /// 設定是否顯示警示標記
  void setShowWarningBadges(bool value) {
    state = state.copyWith(showWarningBadges: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '警示標記顯示: $value');
  }

  /// 設定董監持股通知
  void setInsiderNotifications(bool value) {
    state = state.copyWith(insiderNotifications: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '董監持股通知: $value');
  }

  /// 設定處置股票緊急警報
  void setDisposalUrgentAlerts(bool value) {
    state = state.copyWith(disposalUrgentAlerts: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '處置股票緊急警報: $value');
  }

  /// 設定漲跌停提示
  void setLimitAlerts(bool value) {
    state = state.copyWith(limitAlerts: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '漲跌停提示: $value');
  }

  /// 設定民國年顯示
  void setShowROCYear(bool value) {
    state = state.copyWith(showROCYear: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '民國年顯示: $value');
  }

  /// 設定快取時間（分鐘）
  void setCacheDurationMinutes(int minutes) {
    state = state.copyWith(cacheDurationMinutes: minutes);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '快取時間: $minutes 分鐘');
  }

  /// 設定是否啟用自動更新
  void setAutoUpdateEnabled(bool value) {
    state = state.copyWith(autoUpdateEnabled: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '自動更新: $value');
  }
}

// ==================================================
// Provider
// ==================================================

/// 設定 Provider
final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// 主題模式 Provider（便捷存取）
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});

/// 快取時間 Provider（便捷存取）
final cacheDurationProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).cacheDurationMinutes;
});

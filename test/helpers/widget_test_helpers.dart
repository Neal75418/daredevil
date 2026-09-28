import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/theme/app_theme.dart';

/// 建立測試用的 MaterialApp 包裝
///
/// 使用 production 主題（AppTheme），確保測試環境與實際 app 一致。
///
/// [locale] 未指定時語系為 Flutter 預設 en_US——依語系分級的數字格式
/// （`Localizations.localeOf(context)`）會走英文路徑；要驗中文版面或輸出
/// 時傳 `Locale('zh', 'TW')`。
Widget buildTestApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale? locale,
}) {
  return MaterialApp(
    theme: brightness == Brightness.light
        ? AppTheme.lightTheme
        : AppTheme.darkTheme,
    locale: locale,
    supportedLocales: locale == null
        ? const [Locale('en', 'US')]
        : const [Locale('zh', 'TW'), Locale('en')],
    localizationsDelegates: locale == null
        ? null
        : GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: child),
  );
}

/// 初始化 EasyLocalization 測試環境
///
/// 抑制 `Localization key [xxx] not found` 警告，
/// 適用於不需要實際翻譯值的結構性測試（如 SummaryLocalizer）。
///
/// 用法：在 `setUpAll()` 中呼叫：
/// ```dart
/// setUpAll(() async {
///   await setupTestLocalization();
/// });
/// ```
Future<void> setupTestLocalization() async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableLevels = [];
}

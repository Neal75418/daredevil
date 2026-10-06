import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:flutter_riverpod/misc.dart';

/// 測試用共享 in-memory DB（整個 test process 只建立一次）
///
/// 避免每個 testWidgets 都 new 一個 AppDatabase，
/// 消除 Drift 的 "multiple database" runtime warning。
///
/// WARNING: 此 DB 跨所有測試共用 — 每個 widget test 必須 override
/// 所有可能寫入 DB 的 provider，否則會造成跨測試汙染。
final _testDb = AppDatabase.forTesting();

/// 建立需要 Riverpod Provider 的測試用 MaterialApp 包裝
///
/// 適用於依賴 Provider 的 Widget 測試（如 Screen 子元件）。
/// [overrides] 傳入 mock provider override 列表。
/// 預設覆寫 [databaseProvider] 為共享 in-memory DB。
///
/// 報價中心預設為 [InertLiveQuoteCenter];要即時資料時傳 `liveQuoteCenter:`,
/// 不要放進 [overrides](會重複 override)。
///
/// [zhTranslations] 為 true 時載入真實 zh-TW 翻譯（`.tr()` 回中文而非
/// key），語系為 zh_TW。版面寬度相關的斷言要用它：key 字串通常比中文長，
/// 會造成假性水平溢位。需先 `await setupTestLocalization()`，pump 後翻譯
/// 才載入完成。⚠️ 翻譯寫入全域 `Localization.instance` 且不會還原，同檔
/// 之後依賴 key 字串的測試會被污染——用到它的測試放在獨立檔案（每個測試
/// 檔各自一個 isolate）。
Widget buildProviderTestApp(
  Widget child, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  GoRouter? router,
  bool zhTranslations = false,
  LiveQuoteCenter Function()? liveQuoteCenter,
}) {
  if (zhTranslations) {
    return EasyLocalization(
      supportedLocales: const [Locale('zh', 'TW')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh', 'TW'),
      startLocale: const Locale('zh', 'TW'),
      saveLocale: false,
      assetLoader: _ZhTwAssetLoader(),
      child: Builder(
        builder: (context) => _buildProviderApp(
          child,
          overrides: overrides,
          brightness: brightness,
          router: router,
          liveQuoteCenter: liveQuoteCenter,
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
        ),
      ),
    );
  }
  return _buildProviderApp(
    child,
    overrides: overrides,
    brightness: brightness,
    router: router,
    liveQuoteCenter: liveQuoteCenter,
  );
}

class _ZhTwAssetLoader extends AssetLoader {
  static final _zhTw =
      json.decode(File('assets/translations/zh-TW.json').readAsStringSync())
          as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => _zhTw;
}

Widget _buildProviderApp(
  Widget child, {
  required List<Override> overrides,
  required Brightness brightness,
  required GoRouter? router,
  required LiveQuoteCenter Function()? liveQuoteCenter,
  Locale? locale,
  Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
}) {
  final theme = brightness == Brightness.light
      ? AppTheme.lightTheme
      : AppTheme.darkTheme;
  final supportedLocales = locale == null
      ? const [Locale('en', 'US')]
      : [locale];
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(_testDb),
      liveQuoteCenterProvider.overrideWith(
        liveQuoteCenter ?? InertLiveQuoteCenter.new,
      ),
      ...overrides,
    ],
    // Riverpod 3 預設對失敗的 FutureProvider 自動重試（指數退避，最多
    // 10 次、單次延遲上看 6.4s，總計可達 ~38s）。Widget 測試需要錯誤狀態
    // 立即、確定性地呈現，故關閉重試——與正式環境的 ProviderScope（main.dart）
    // 各自獨立，不影響正式行為。
    retry: (_, _) => null,
    // 需要驗證 context.push 等導頁時傳入 [router]（此時 [child] 不使用，
    // 由 router 的路由決定畫面）
    child: router == null
        ? MaterialApp(
            theme: theme,
            locale: locale,
            supportedLocales: supportedLocales,
            localizationsDelegates: localizationsDelegates,
            home: Scaffold(body: child),
          )
        : MaterialApp.router(
            theme: theme,
            locale: locale,
            supportedLocales: supportedLocales,
            localizationsDelegates: localizationsDelegates,
            routerConfig: router,
          ),
  );
}

/// 不發請求、不登記的報價中心(預設用它):畫面測試不可隨執行時間是否在
/// 盤中而不同。需要即時資料的測試用 [buildProviderTestApp] 的
/// `liveQuoteCenter:` 傳入假的報價中心。
class InertLiveQuoteCenter extends LiveQuoteCenter {
  @override
  LiveQuoteState build() => const LiveQuoteState();

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) {}

  @override
  void unregister(Object owner) {}

  @override
  void setAppVisible(bool visible) {}
}

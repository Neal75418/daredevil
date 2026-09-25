import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
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
Widget buildProviderTestApp(
  Widget child, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  GoRouter? router,
}) {
  final theme = brightness == Brightness.light
      ? AppTheme.lightTheme
      : AppTheme.darkTheme;
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(_testDb), ...overrides],
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
            home: Scaffold(body: child),
          )
        : MaterialApp.router(theme: theme, routerConfig: router),
  );
}

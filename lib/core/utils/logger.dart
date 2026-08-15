/// 日誌等級，用於過濾輸出
enum LogLevel { debug, info, warning, error }

/// Sentry breadcrumb 投遞函式 — 不直接依賴 sentry_flutter 型別讓 logger.dart
/// 維持純 Dart。Flutter app 在 startup 透過 [AppLogger.setSentryDelegates]
/// 注入 closure，內部把參數轉成 `Breadcrumb` + `SentryLevel`。CLI 路徑不
/// 注入，所有 Sentry 呼叫成為 null-safe no-op。
typedef SentryBreadcrumbFn =
    void Function(
      String message,
      String? category,
      String level, // 'debug' | 'info' | 'warning' | 'error'
      Map<String, dynamic>? data,
    );

/// Sentry exception 上報函式 — 跟 [SentryBreadcrumbFn] 同樣的去耦設計。
typedef SentryCaptureFn =
    void Function(
      Object error,
      StackTrace? stackTrace,
      String tag,
      String message,
    );

/// 結構化日誌工具，確保應用程式日誌格式一致
///
/// 使用範例：
/// ```dart
/// AppLogger.debug('PriceRepo', '取得 2330 價格資料');
/// AppLogger.info('UpdateService', '更新完成');
/// AppLogger.warning('StockDetail', '無 $symbol 的法人資料');
/// AppLogger.error('Network', 'API 請求失敗', e, stackTrace);
/// ```
///
/// Sentry 整合（C 方案 refactor 2026-06-19）：
/// - Flutter app 在 `main.dart` 透過 [setSentryDelegates] 注入 closures，
///   把 logger 呼叫橋接到 `Sentry.addBreadcrumb` / `Sentry.captureException`
/// - CLI 路徑（`tool/`）不注入，logger 呼叫 Sentry 段變成 no-op
/// - 過去 logger 直接 `import 'package:sentry_flutter'` 把 dart:ui 拉進整套
///   type graph，導致純 Dart CLI 無法 dart run
abstract final class AppLogger {
  /// 最低輸出等級
  static const LogLevel _minLevel = LogLevel.debug;

  /// Sentry breadcrumb delegate — 由 main.dart 注入；CLI 不注入時為 null
  static SentryBreadcrumbFn? _sentryBreadcrumb;

  /// Sentry capture delegate — 由 main.dart 注入；CLI 不注入時為 null
  static SentryCaptureFn? _sentryCapture;

  /// 由 Flutter app 在 startup 呼叫一次，注入 Sentry bridging closures。
  /// CLI 環境不需呼叫；所有 Sentry 段自動 no-op。
  /// CLI 強制輸出開關。app 不得設定(release 應維持靜默);
  /// `tool/` 下的 CLI 在 main 開頭設 true,讓錯誤進得了 launchd 日誌。
  static bool forceOutput = false;

  static void setSentryDelegates({
    SentryBreadcrumbFn? breadcrumb,
    SentryCaptureFn? capture,
  }) {
    _sentryBreadcrumb = breadcrumb;
    _sentryCapture = capture;
  }

  /// 記錄 debug 訊息
  static void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  /// 記錄 info 訊息
  static void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// 記錄 warning 訊息，可附帶例外與堆疊追蹤
  ///
  /// 同時加入 Sentry breadcrumb（若已注入 delegate）。
  static void warning(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _log(LogLevel.warning, tag, message, error, stackTrace);

    _sentryBreadcrumb?.call(
      '[$tag] $message',
      tag,
      'warning',
      error != null ? {'error': error.toString()} : null,
    );
  }

  /// 記錄 error 訊息，可附帶例外與堆疊追蹤
  ///
  /// 同時上報至 Sentry（若已注入 delegate）。
  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _log(LogLevel.error, tag, message, error, stackTrace);

    if (error != null) {
      _sentryCapture?.call(error, stackTrace, tag, message);
    }
  }

  static void _log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    // 低於最低等級的日誌不輸出
    if (level.index < _minLevel.index) return;

    // 僅在 debug 模式輸出日誌（release build assert 不執行 → 留 release=false）
    var isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    // [forceOutput] 讓 CLI 繞過 assert gate——實測 `dart run`(launchd 兩支
    // CLI 的執行方式)下 assert **未啟用**,否則這 600+ 個呼叫點在生產環境
    // 輸出零位元組(2026-08-15 稽核;本專案有靜默斷 13 天的前科)。
    if (!isDebug && !forceOutput) return;

    final prefix = switch (level) {
      LogLevel.debug => '[D]',
      LogLevel.info => '[I]',
      LogLevel.warning => '[W]',
      LogLevel.error => '[E]',
    };

    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final logMessage = '$timestamp $prefix [$tag] $message';

    // 純 Dart `print` — debug build 行為等同 `debugPrint`（不 throttle 但
    // 順序保證）。CLI 寫進 launchd stdout file。
    // ignore: avoid_print
    print(logMessage);

    if (error != null) {
      // ignore: avoid_print
      print('$timestamp $prefix [$tag] Error: $error');
    }

    if (stackTrace != null) {
      // ignore: avoid_print
      print('$timestamp $prefix [$tag] StackTrace:\n$stackTrace');
    }
  }
}

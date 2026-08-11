import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/utils/desktop_scroll_behavior.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:daredevil/app/router.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/app/background_update_service.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/services/notification_service.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/presentation/providers/intraday_monitor_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await EasyLocalization.ensureInitialized();

  // C 方案 refactor 2026-06-19：CalibratedScoresRegistry 已純 Dart 化，
  // 不直接 import flutter/services。Flutter app startup 注入
  // rootBundle.loadString 當 asset loader；CLI 走 File.readAsString。
  CalibratedScoresRegistry.instance.assetLoaderOverride = rootBundle.loadString;

  // 設定通知點擊導航 — 必須在 initialize() 之前，避免 init 期間若 plugin
  // dispatch 到 _onNotificationTapped，callback 還是 null 而 silently 丟掉
  // payload。callback 是 plugin singleton 上的 property，在 init 前先 assign
  // 不影響 init 流程；init 內部註冊 onDidReceiveNotificationResponse 時
  // 屬性已就位。
  NotificationService.instance.onTapCallback = (symbol) {
    router.push(AppRoutes.stockDetail(symbol));
  };

  // Initialize notification service (權限請求延遲到使用者啟用通知時)
  await NotificationService.instance.initialize();

  // 初始化背景更新服務
  await BackgroundUpdateService.instance.initialize();

  // 建立 Container 以在 runApp 前初始化 Provider
  final appVersion = await _loadAppVersion();
  final container = ProviderContainer(
    overrides: [currentAppVersionProvider.overrideWithValue(appVersion)],
  );

  // B-lite cold-start auto-update（review 2026-06-18）：macOS dev 機沒有
  // workmanager 路徑，使用者開 app 時自動跑 update 是最務實的累積 calibration
  // forward data 方法。預設關閉（給測試），production startup 顯式打開。
  // 6h gate + 交易日 + isUpdating 三層 short-circuit 在 TodayNotifier 內處理。
  TodayNotifier.autoColdStartUpdateEnabled = true;

  // 從安全儲存載入 FinMind API Token
  await _initializeFinMindToken(container);

  // 讀回上一輪的 API 配額計數與 cooldown。**必須 await**：tracker 建構與
  // checkBudget 都是同步的，fire-and-forget 會讓早期呼叫看到空狀態。
  // 不做的話重啟即歸零，而 FinMind 伺服器端的 hourly 額度不會忘記——
  // 2026-07-27 實測重啟後本地計數 42/600、伺服器直接回 402。
  final budgetRestore = await container
      .read(apiBudgetTrackerProvider)
      .restore();
  if (budgetRestore.restoredCalls > 0 ||
      budgetRestore.cooldownVendors.isNotEmpty) {
    AppLogger.info(
      'ApiBudgetTracker',
      '配額狀態已還原: ${budgetRestore.restoredCalls} 次呼叫在窗內'
          '${budgetRestore.cooldownVendors.isEmpty ? "" : "，cooldown 中: "
                    '${budgetRestore.cooldownVendors.map((v) => v.name).join(",")}'}',
    );
  }

  // 檢查是否已完成引導流程
  await initOnboardingStatus();

  // 快取預熱（非阻塞）
  container
      .read(cacheWarmupServiceProvider)
      .warmup()
      .then((_) {
        AppLogger.info('Main', '快取預熱完成');
      })
      .catchError((error) {
        AppLogger.warning('Main', '快取預熱失敗（不影響使用）', error);
      });

  // Sentry DSN 由 --dart-define=SENTRY_DSN=xxx 編譯時注入
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = sentryDsn;
      options.environment = kDebugMode ? 'development' : 'production';
      options.sendDefaultPii = false;
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
    }, appRunner: () => _runApp(container));
  } else {
    await _runApp(container);
  }

  // C 方案 refactor 2026-06-19：logger.dart 已純 Dart 化，不再直接 import
  // sentry_flutter。Flutter app startup 注入 Sentry bridging closures；
  // CLI 路徑（tool/）不注入，Sentry 段成 no-op。
  AppLogger.setSentryDelegates(
    breadcrumb: (message, category, level, data) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: category,
          level: switch (level) {
            'debug' => SentryLevel.debug,
            'info' => SentryLevel.info,
            'warning' => SentryLevel.warning,
            'error' => SentryLevel.error,
            _ => SentryLevel.info,
          },
          data: data,
        ),
      );
    },
    capture: (error, stackTrace, tag, message) {
      Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('logger.tag', tag);
          scope.setContexts('logger', {'message': message, 'tag': tag});
        },
      );
    },
  );
}

Future<void> _runApp(ProviderContainer container) async {
  // Stage 5a + OTA: 載入 calibrated scores JSON（放在 Sentry init 之後，
  // 讓 asset 載入錯誤能被 Sentry 捕獲上報）。
  //
  // 載入優先順序（design doc §3.2 fallback chain）：
  //   1. AppSettings DB cache（last successful OTA fetch）
  //   2. Bundled asset（最後一次 release 時 commit 進 repo 的 JSON）
  //   3. Empty table → hardcoded RuleScores
  //
  // loadWithOverride 會在 DB cache 有效時直接使用，否則自動 fall through
  // 到 loadFromAssets（原 Stage 5a 路徑）。
  final db = container.read(databaseProvider);
  final cached = await db.getCachedCalibration();
  await CalibratedScoresRegistry.instance.loadWithOverride(
    shortJsonOverride: cached.shortJson,
    longJsonOverride: cached.longJson,
    knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
    hardcodedScores: {for (final r in ReasonType.values) r.code: r.score},
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh', 'TW'),
      child: UncontrolledProviderScope(
        container: container,
        child: const DaredevilApp(),
      ),
    ),
  );

  // OTA calibration check — fire-and-forget（design doc §2 Q7 = A）
  //
  // 在 runApp 之後呼叫，不阻塞 UI。24h gate 在 CalibrationUpdater 內部
  // 處理，大部分 cold start 不會實際打網路。新 JSON 寫入 AppSettings
  // 但不 invalidate provider（Q5 = B, deferred swap），下次 cold start
  // 才會走 Tier 1 DB cache 路徑讀到新版本。
  unawaited(
    container
        .read(calibrationUpdaterProvider)
        .checkAndUpdate()
        .then((result) {
          AppLogger.info(
            'CalibrationUpdater',
            'OTA check: ${result.describe()}',
          );
        })
        .catchError((Object error) {
          // CalibrationUpdater.checkAndUpdate 內部已全 try/catch，這裡
          // 是最外層保底，理論上不會觸發。
          AppLogger.warning(
            'CalibrationUpdater',
            'OTA check outer error',
            error,
          );
        }),
  );
}

/// 取得當前 app version 字串，注入 [currentAppVersionProvider]
///
/// PackageInfo 取不到時 fallback `'0.0.0-fallback'`：所有 manifest 的
/// `minimum_app_version` 都會把這個值判定為不足，OTA gate 保守拒推
/// （與其風險「未知版本下載未知 calibration」相比，這側更安全）。
/// 用 `-fallback` 後綴讓 ELK / Sentry breadcrumb 能分辨「真版本不足」
/// vs 「PackageInfo 壞掉」。
Future<String> _loadAppVersion() async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } catch (e) {
    AppLogger.warning('Main', 'PackageInfo 取得 app version 失敗，OTA 將保守拒推', e);
    return '0.0.0-fallback';
  }
}

/// 從安全儲存載入 FinMind API Token 並設定至 Client
Future<void> _initializeFinMindToken(ProviderContainer container) async {
  try {
    final settingsRepo = container.read(settingsRepositoryProvider);
    final token = await settingsRepo.getFinMindToken();
    if (token != null && token.isNotEmpty) {
      container.read(finMindClientProvider).token = token;
    }
  } catch (e) {
    // Token 載入為選用，失敗不影響啟動
    AppLogger.warning('Main', '載入 FinMind Token 失敗', e);
  }
}

class DaredevilApp extends ConsumerStatefulWidget {
  const DaredevilApp({super.key});

  @override
  ConsumerState<DaredevilApp> createState() => _DaredevilAppState();
}

class _DaredevilAppState extends ConsumerState<DaredevilApp>
    with WidgetsBindingObserver {
  DateTime? _lastPausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 盤中提醒輪詢:僅前景執行(iOS/macOS 不保證背景常駐,見 provider 註解)
    ref.read(intradayMonitorProvider.notifier).start();
  }

  @override
  void dispose() {
    // ⚠️ 不要在這裡 ref.read:Riverpod 3.x 會拋 StateError,而且因為它是
    // 第一行,removeObserver 與 super.dispose() 都不會執行 → 死掉的 State
    // 繼續掛在生命週期觀察者上(2026-08-08 二次審查實測)。計時器的釋放
    // 由 provider 的 ref.onDispose 負責,本來就涵蓋。
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
      ref.read(intradayMonitorProvider.notifier).stop();
      // 配額狀態落盤(2026-08-01 複審):tracker 每 10 次呼叫才自動存,
      // 退背景/被殺前 flush 掉尾端記帳——遺失=低估=放行更多=402 方向
      unawaited(
        ref.read(apiBudgetTrackerProvider).flush().catchError((Object e) {
          AppLogger.warning('ApiBudgetTracker', 'paused flush 失敗', e);
        }),
      );
    } else if (state == AppLifecycleState.resumed && _lastPausedAt != null) {
      final elapsed = DateTime.now().difference(_lastPausedAt!);
      if (elapsed.inMinutes >= DataFreshness.appStaleThresholdMinutes) {
        AppLogger.info('Lifecycle', '離開 ${elapsed.inMinutes} 分鐘，重新載入資料');
        ref.read(todayProvider.notifier).loadData();
      }
      _lastPausedAt = null;
      ref.read(intradayMonitorProvider.notifier).start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Daredevil',
      onGenerateTitle: (context) => 'app.name'.tr(),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      routerConfig: router,
      // 🚨 桌面的預設 dragDevices **不含 mouse**,橫向卡列在 macOS 上完全
      // 拖不動(2026-08-11 實機:族群排行「轉向」的卡片超出寬度但滑不到)。
      // 全專案有 8 處 `scrollDirection: Axis.horizontal`,而先前只有
      // `upcoming_events_section` 自己包了一層 ScrollConfiguration ——
      // 修一處等於留七個同樣的坑。設在這裡一次涵蓋全部。
      scrollBehavior: const DesktopDragScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'dart:io';

import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/logger.dart';

/// 本地通知服務
class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// singleton 是否已初始化。
  ///
  /// 診斷用(2026-08-08):這與 `NotificationNotifier.state.isInitialized`
  /// 是**兩個不同的旗標**——前者在 main() 啟動時就設好,後者只有
  /// today_provider 在每日更新後才會設。混為一談會讓人以為服務沒起來,
  /// 實際上只是 provider 狀態沒同步。
  bool get isInitialized => _isInitialized;

  /// 通知點擊回呼 — 由 app 層設定，接收 stock symbol 作為 payload
  void Function(String symbol)? onTapCallback;

  /// 初始化通知服務
  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS / macOS: 三個 request*Permission flag 設 true 會在 initialize()
    // 立即觸發 OS 權限 prompt。我們希望首次 prompt 由 user 主動啟用 alert 時
    // 才觸發（經 NotificationNotifier.ensurePermission → requestPermissions），
    // 所以 init 階段全部 false，只跑 channel / timezone / handler 註冊。
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const macOSSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macOSSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;

    AppLogger.debug('NotificationService', '服務已初始化');
  }

  /// 檢查是否已取得通知權限（不會請求權限）
  ///
  /// 🔴 2026-08-08 二次審查:macOS **不能**用 `IOSFlutterLocalNotifications
  /// Plugin` 解析——flutter_local_notifications 只在 `TargetPlatform.iOS`
  /// 註冊它,macOS 註冊的是 `MacOSFlutterLocalNotificationsPlugin`。原本
  /// 兩者共用 iOS 分支,於是 macOS 恆得 null → 恆回 false → 依賴權限的
  /// 功能(盤中提醒守門)在主力平台整個死掉且無聲。
  Future<bool> hasPermission() async {
    if (Platform.isMacOS) {
      final macPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      // 🚨 `?? false` 會把「plugin 解析不到」壓成「使用者拒絕」,兩者
      // 症狀 100% 相同(2026-08-08 三次審查 H-4)。這正是先前 macOS 誤用
      // iOS plugin 那個 bug 之所以要花一整天、做完八項證偽才定位的機制。
      // 下次升 Flutter 或 plugin 導致註冊名改變時,這幾行要能自己指認。
      if (macPlugin == null) {
        AppLogger.error(
          'NotificationService',
          'MacOSFlutterLocalNotificationsPlugin 解析不到——這不是「沒權限」,'
              '是 plugin 未註冊(Flutter/plugin 版本或平台判定變更)',
          StateError('macOS notification plugin unresolved'),
        );
        return false;
      }
      final result = await macPlugin.checkPermissions();
      if (result == null) {
        AppLogger.error(
          'NotificationService',
          'checkPermissions 回 null(非 denied)——plugin 行為改變',
          StateError('checkPermissions returned null'),
        );
        return false;
      }
      return result.isEnabled;
    }

    if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      // checkPermissions 只檢查不請求
      final result = await iosPlugin?.checkPermissions();
      return result?.isEnabled ?? false;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final result = await androidPlugin?.areNotificationsEnabled();
      return result ?? false;
    }

    return true;
  }

  /// 請求通知權限（iOS/macOS/Android）
  ///
  /// macOS 走 `MacOSFlutterLocalNotificationsPlugin`,理由同 [hasPermission]。
  ///
  /// 🔴 **macOS 上這條路徑已知失效(2026-08-08 實機定案,原因未明)**。
  /// 系統在 App 行程內就回絕,連通知服務都沒接觸到:
  /// ```
  /// 請求前 authorizationStatus = 1 (denied)   ← 從未請求過卻已是 denied
  /// error = UNErrorDomain Code=1 "Notifications are not allowed for this application"
  /// ```
  /// 證據取得方式:暫時改插件原生碼把 `{ (granted, _) in` 丟掉的 error
  /// 寫出來——**沒有那一步就只看得到一個沒有理由的 false**(0–4ms 回覆、
  /// 不跳窗、`usernoted` 零日誌,全是 `.denied` 的標準行為)。
  ///
  /// 已逐一證偽:插件解析失敗、權限參數全 false 觸發原生早退、使用者曾
  /// 按拒絕(系統 65 個 app 紀錄裡查無此 app)、簽章無效(正式 Apple
  /// Development 憑證且 `--verify --deep --strict` 通過)、同 bundle ID
  /// 的殘留註冊(清掉 1 個 macOS + 2 個 iOS 模擬器死註冊)、`usernoted`
  /// 記憶體快取(重啟)、執行位置不受信任(複製到 `/Applications` 重測)。
  ///
  /// **影響有限**:macOS 的盤中提醒由 launchd CLI
  /// (`tool/intraday_alert_check.dart`)以原生 `osascript` 發送,已驗證可用,
  /// 且無論 App 開著與否都會執行。GUI 這條是冗餘的第二條路。iOS 不受影響。
  ///
  /// ⚠️ **更正(2026-08-08 三次審查)**:本註解原本斷言「提醒不會被燒掉」,
  /// 那句話當時**只對盤中輪詢成立**——收盤路徑(`today_provider`)當時
  /// 沒有這道守門,會先認領再發現通知發不出去,提醒兩條路徑都撿不到。
  /// 該守門與「通知失敗釋放認領」(`releaseAlertClaim`)已於同日補上,
  /// 但這個錯誤結論值得留著:**它差點讓下一個人直接跳過不修**。
  Future<bool> requestPermissions() async {
    if (Platform.isMacOS) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    }

    if (Platform.isIOS) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final result = await androidPlugin?.requestNotificationsPermission();
      return result ?? false;
    }

    return true;
  }

  /// 顯示價格提醒通知
  Future<void> showPriceAlert({
    required int id,
    required String symbol,
    required String title,
    required String body,
    String? payload,
  }) async {
    // ignore: prefer_const_constructors - AndroidNotificationDetails is not const
    final androidDetails = AndroidNotificationDetails(
      'price_alerts',
      'Price Alerts',
      channelDescription: 'Notifications for stock price alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: AppTheme.notificationColor,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload ?? symbol,
    );
  }

  /// 顯示一般通知
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'general',
      'General',
      channelDescription: 'General app notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  /// 顯示緊急警報通知（處置股票專用）
  ///
  /// 使用 Importance.max 確保用戶立即注意到。
  Future<void> showUrgentAlert({
    required int id,
    required String symbol,
    required String title,
    required String body,
    String? payload,
  }) async {
    // ignore: prefer_const_constructors - AndroidNotificationDetails is not const
    final androidDetails = AndroidNotificationDetails(
      'urgent_alerts',
      'Urgent Alerts',
      channelDescription: 'Urgent notifications for disposal stocks',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFE53935), // 紅色警示
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true, // 全螢幕通知
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical, // iOS 緊急通知
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload ?? symbol,
    );
  }

  /// 處理通知點擊事件
  ///
  /// payload 包含股票代號，導航由應用程式的導航系統處理。
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    AppLogger.debug('NotificationService', '通知被點擊: $payload');
    if (payload != null && payload.isNotEmpty) {
      onTapCallback?.call(payload);
    }
  }

  /// 釋放通知服務資源
  ///
  /// 取消所有待發送通知並重置初始化狀態。
  /// 應在應用程式關閉時呼叫。
  Future<void> dispose() async {
    if (!_isInitialized) return;

    try {
      await _notifications.cancelAll();
    } finally {
      _isInitialized = false;
      AppLogger.debug('NotificationService', '服務已釋放');
    }
  }
}

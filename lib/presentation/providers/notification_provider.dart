import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/core/services/notification_service.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';

/// 通知狀態
class NotificationState {
  const NotificationState({
    this.isInitialized = false,
    this.hasPermission = false,
    this.error,
  });

  final bool isInitialized;
  final bool hasPermission;
  final String? error;

  // Sentinel：區分「未傳入」與「傳入 null」

  NotificationState copyWith({
    bool? isInitialized,
    bool? hasPermission,
    Object? error = sentinel,
  }) {
    return NotificationState(
      isInitialized: isInitialized ?? this.isInitialized,
      hasPermission: hasPermission ?? this.hasPermission,
      error: identical(error, sentinel)
          ? this.error
          : (error is String? ? error : error.toString()),
    );
  }
}

/// 通知管理器
class NotificationNotifier extends Notifier<NotificationState> {
  final _service = NotificationService.instance;

  @override
  NotificationState build() {
    // WARNING: _service is a singleton (NotificationService.instance).
    // Disposing it here is safe only because this provider is NOT autoDispose,
    // so it is created once and lives for the app's lifetime. If the provider
    // were ever changed to autoDispose, recreating it would call dispose() on
    // the shared singleton, leaving other references in a broken state.
    ref.onDispose(() {
      unawaited(_service.dispose());
    });
    return const NotificationState();
  }

  /// 初始化通知服務
  ///
  /// 注意：不會自動請求權限，權限會在使用者建立提醒時請求。
  /// Service 初始化與權限檢查分離處理，確保 hasPermission 失敗不影響 isInitialized 狀態。
  Future<void> initialize() async {
    try {
      await _service.initialize();
      state = state.copyWith(isInitialized: true);

      // 權限檢查為非關鍵操作，失敗不影響服務可用性
      try {
        final hasPermission = await _service.hasPermission();
        state = state.copyWith(hasPermission: hasPermission);
      } catch (e) {
        AppLogger.warning('NotificationNotifier', '權限檢查失敗（非關鍵）', e);
      }
    } catch (e) {
      AppLogger.warning('NotificationNotifier', '初始化通知服務失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
    }
  }

  /// 確保已取得通知權限
  ///
  /// 在建立提醒前呼叫，若尚未取得權限會請求使用者授權
  Future<bool> ensurePermission() async {
    if (state.hasPermission) return true;
    return requestPermissions();
  }

  /// 請求通知權限
  Future<bool> requestPermissions() async {
    try {
      final hasPermission = await _service.requestPermissions();
      state = state.copyWith(hasPermission: hasPermission);
      return hasPermission;
    } catch (e) {
      AppLogger.warning('NotificationNotifier', '請求通知權限失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
      return false;
    }
  }

  /// 顯示價格提醒通知
  ///
  /// 根據使用者設定決定是否發送：
  /// - 處置/注意股票警示受 `disposalUrgentAlerts` 設定控制
  /// - 董監持股相關警示受 `insiderNotifications` 設定控制
  Future<bool> showPriceAlertNotification(
    PriceAlertEntry alert, {
    double? currentPrice,
  }) async {
    // 🚨 回傳 bool 而非 void(2026-08-08 四次審查 C-1):這三個 return
    // 是**靜默**的,不丟例外。呼叫端原本靠 try/catch 做補償,於是補償對
    // 真正的失效模式(無權限、設定關掉)一次都不會啟動——一個不會觸發
    // 的補償機制,比沒有更糟,因為它讓人以為已經處理了。
    if (!state.isInitialized || !state.hasPermission) return false;

    final alertType = AlertType.fromValue(alert.alertType);
    final settings = ref.read(settingsProvider);

    // 尊重使用者設定：處置/注意股票警示
    if ((alertType == AlertType.tradingDisposal ||
            alertType == AlertType.tradingWarning) &&
        !settings.disposalUrgentAlerts) {
      return false;
    }

    // 尊重使用者設定：董監持股相關警示
    if ((alertType == AlertType.insiderSelling ||
            alertType == AlertType.insiderBuying ||
            alertType == AlertType.highPledgeRatio) &&
        !settings.insiderNotifications) {
      return false;
    }

    final title = getAlertTitle(alert.symbol, alertType);
    final body = getAlertBody(alert, alertType, currentPrice);

    // 處置股票使用緊急通知（Importance.max）
    if (alertType == AlertType.tradingDisposal) {
      await _service.showUrgentAlert(
        id: alert.id,
        symbol: alert.symbol,
        title: title,
        body: body,
        payload: alert.symbol,
      );
    } else {
      await _service.showPriceAlert(
        id: alert.id,
        symbol: alert.symbol,
        title: title,
        body: body,
        payload: alert.symbol,
      );
    }
    return true;
  }

  /// 顯示更新完成通知
  Future<void> showUpdateCompleteNotification({
    required int alertsTriggered,
  }) async {
    if (!state.isInitialized || !state.hasPermission) return;

    final String body;
    if (alertsTriggered > 0) {
      body = 'notification.updateWithAlerts'.tr(
        namedArgs: {'alerts': alertsTriggered.toString()},
      );
    } else {
      body = 'notification.updateNoAlerts'.tr();
    }

    await _service.showNotification(
      id: 0,
      title: 'notification.updateComplete'.tr(),
      body: body,
    );
  }

  @visibleForTesting
  static String getAlertTitle(String symbol, AlertType alertType) {
    return switch (alertType) {
      AlertType.above => 'notification.priceAboveTarget'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.below => 'notification.priceBelowTarget'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.changePct => 'notification.priceChangeTarget'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.volumeSpike || AlertType.volumeAbove =>
        'notification.volumeAlertTitle'.tr(namedArgs: {'symbol': symbol}),
      AlertType.rsiOverbought => 'notification.rsiOverboughtTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.rsiOversold => 'notification.rsiOversoldTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.kdGoldenCross => 'notification.kdGoldenCrossTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.kdDeathCross => 'notification.kdDeathCrossTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.breakResistance => 'notification.breakResistanceTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.breakSupport => 'notification.breakSupportTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.week52High => 'notification.week52HighTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.week52Low => 'notification.week52LowTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.crossAboveMa => 'notification.crossAboveMaTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.crossBelowMa => 'notification.crossBelowMaTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.revenueYoySurge => 'notification.revenueYoySurgeTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.highDividendYield => 'notification.highDividendYieldTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.peUndervalued => 'notification.peUndervaluedTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.tradingWarning => 'notification.tradingWarningTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.tradingDisposal => 'notification.tradingDisposalTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.insiderSelling => 'notification.insiderSellingTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.insiderBuying => 'notification.insiderBuyingTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
      AlertType.highPledgeRatio => 'notification.highPledgeRatioTitle'.tr(
        namedArgs: {'symbol': symbol},
      ),
    };
  }

  @visibleForTesting
  static String getAlertBody(
    PriceAlertEntry alert,
    AlertType alertType,
    double? currentPrice,
  ) {
    final priceText = currentPrice != null
        ? 'notification.currentPriceSuffix'.tr(
            namedArgs: {'price': currentPrice.toStringAsFixed(2)},
          )
        : '';

    final baseBody = switch (alertType) {
      AlertType.above => 'notification.aboveBody'.tr(
        namedArgs: {'price': alert.targetValue.toStringAsFixed(2)},
      ),
      AlertType.below => 'notification.belowBody'.tr(
        namedArgs: {'price': alert.targetValue.toStringAsFixed(2)},
      ),
      AlertType.changePct => 'notification.changeBody'.tr(
        namedArgs: {'percent': alert.targetValue.toStringAsFixed(1)},
      ),
      // 爆量的倍數是固定門檻、不存在 targetValue（見 AlertParams）
      AlertType.volumeSpike => 'notification.volumeSpikeBody'.tr(
        namedArgs: {
          'value': AlertParams.volumeSpikeMultiplier.toStringAsFixed(0),
        },
      ),
      AlertType.volumeAbove => 'notification.volumeAboveBody'.tr(
        namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
      ),
      AlertType.rsiOverbought => 'notification.rsiOverboughtBody'.tr(
        namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
      ),
      AlertType.rsiOversold => 'notification.rsiOversoldBody'.tr(
        namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
      ),
      AlertType.kdGoldenCross => 'notification.kdGoldenCrossBody'.tr(),
      AlertType.kdDeathCross => 'notification.kdDeathCrossBody'.tr(),
      AlertType.breakResistance => 'notification.breakResistanceBody'.tr(
        namedArgs: {'price': alert.targetValue.toStringAsFixed(2)},
      ),
      AlertType.breakSupport => 'notification.breakSupportBody'.tr(
        namedArgs: {'price': alert.targetValue.toStringAsFixed(2)},
      ),
      AlertType.week52High => 'notification.week52HighBody'.tr(),
      AlertType.week52Low => 'notification.week52LowBody'.tr(),
      AlertType.crossAboveMa => 'notification.crossAboveMaBody'.tr(
        namedArgs: {'days': alert.targetValue.toInt().toString()},
      ),
      AlertType.crossBelowMa => 'notification.crossBelowMaBody'.tr(
        namedArgs: {'days': alert.targetValue.toInt().toString()},
      ),
      AlertType.revenueYoySurge => 'notification.revenueYoySurgeBody'.tr(
        namedArgs: {'percent': alert.targetValue.toStringAsFixed(1)},
      ),
      AlertType.highDividendYield => 'notification.highDividendYieldBody'.tr(
        namedArgs: {'percent': alert.targetValue.toStringAsFixed(1)},
      ),
      AlertType.peUndervalued => 'notification.peUndervaluedBody'.tr(
        namedArgs: {'value': alert.targetValue.toStringAsFixed(1)},
      ),
      AlertType.tradingWarning => 'notification.tradingWarningBody'.tr(),
      AlertType.tradingDisposal => 'notification.tradingDisposalBody'.tr(),
      AlertType.insiderSelling => 'notification.insiderSellingBody'.tr(),
      AlertType.insiderBuying => 'notification.insiderBuyingBody'.tr(),
      AlertType.highPledgeRatio => 'notification.highPledgeRatioBody'.tr(),
    };

    return '$baseBody$priceText';
  }
}

/// 通知 Provider
final notificationProvider =
    NotifierProvider<NotificationNotifier, NotificationState>(
      NotificationNotifier.new,
    );

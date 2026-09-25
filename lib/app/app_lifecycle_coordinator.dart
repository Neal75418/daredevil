import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import 'package:daredevil/app/foreground_reload_policy.dart';
import 'package:daredevil/core/constants/data_freshness.dart';

/// App 生命週期的副作用：回前景重載、配額落盤、盤中輪詢啟停。
///
/// 從 main 的 State 抽出來是為了能測：這段曾在 macOS 上兩度失效——回前景
/// 不重載、配額從不落盤——兩者都只綁 `paused`，而 macOS 不會進 `paused`
/// （失焦是 `inactive`、最小化是 `hidden`）。
class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    required Duration staleAfter,
    required this.reload,
    required this.flushBudget,
    required this.stopIntraday,
    required this.startIntraday,
  }) : _reloadPolicy = ForegroundReloadPolicy(staleAfter: staleAfter);

  final VoidCallback reload;
  final Future<void> Function() flushBudget;
  final VoidCallback stopIntraday;
  final VoidCallback startIntraday;
  final ForegroundReloadPolicy _reloadPolicy;

  /// 盤中輪詢是否因 paused 停過（只有停過才在 resumed 重啟：macOS 失焦、
  /// 手機拉通知列回來都不重啟，免得每次都多一輪 tick）
  bool _intradayStopped = false;

  void onStateChanged(AppLifecycleState state, DateTime now) {
    if (_reloadPolicy.onStateChanged(state, now)) reload();

    // 配額落盤：tracker 每 10 次呼叫才自動存，退背景／被殺前要 flush 掉
    // 尾端記帳（遺失＝低估用量＝放行更多）。hidden 涵蓋 macOS 最小化；
    // 手機 hidden → paused 各 flush 一次，寫偏好設定成本可忽略。
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(flushBudget());
    }

    // 盤中輪詢只綁 paused：macOS 視窗只是失焦時 app 仍在前景，
    // 盤中提醒本就該繼續
    if (state == AppLifecycleState.paused) {
      stopIntraday();
      _intradayStopped = true;
    } else if (state == AppLifecycleState.resumed && _intradayStopped) {
      _intradayStopped = false;
      startIntraday();
    }
  }

  /// 桌面結束 App（macOS Cmd+Q）。engine 會等這裡回覆才真的結束，
  /// 所以落盤能在退出前完成。
  Future<AppExitResponse> onExitRequested() async {
    await flushBudget().timeout(
      const Duration(seconds: DataFreshness.exitFlushTimeoutSec),
      onTimeout: () {},
    );
    return AppExitResponse.exit;
  }
}

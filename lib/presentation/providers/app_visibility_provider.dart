import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/app/app_lifecycle_coordinator.dart';

/// App 是否在前景（resumed／inactive 可見，hidden／paused 不可見）。
///
/// 初值讀 [WidgetsBinding] 目前的生命週期；之後由 `main.dart` 的生命週期回呼
/// [AppVisibility.set]。不在 `initState` 寫入：widget 樹建構期間寫 provider
/// state 會被 Riverpod 擋下（同值也擋）。
final appVisibilityProvider = NotifierProvider<AppVisibility, bool>(
  AppVisibility.new,
);

class AppVisibility extends Notifier<bool> {
  /// 還沒有生命週期狀態（剛啟動）時當成可見
  @override
  bool build() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || AppLifecycleCoordinator.isVisible(lifecycle);
  }

  /// 同值直接返回：寫 state 時 Riverpod 會先檢查是否在 build 期間（同值也會
  /// 檢查），同值時不寫 state 才不受影響。
  void set(bool visible) {
    if (state == visible) return;
    state = visible;
  }
}

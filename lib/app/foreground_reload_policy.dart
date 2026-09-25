import 'package:flutter/widgets.dart';

/// 回到前景時要不要重新載入資料（離開超過 [staleAfter] 才重載）。
///
/// 🚨 離開時間不可只在 `paused` 記：Flutter 的 `paused` 只有 iOS／Android
/// 會進入。macOS 失焦是 `inactive`、最小化是 `hidden`——只看 `paused` 的話，
/// 視窗長開時 launchd 已在背景更新 DB，回到視窗卻從不重載。
/// 因此一離開 `resumed` 就記下**最早**的離開時間（手機的
/// inactive → hidden → paused 不會把它往後推）。
class ForegroundReloadPolicy {
  ForegroundReloadPolicy({required this.staleAfter});

  final Duration staleAfter;
  DateTime? _leftAt;

  /// 回傳 true 表示此刻（回到 `resumed`）應重新載入。
  bool onStateChanged(AppLifecycleState state, DateTime now) {
    if (state == AppLifecycleState.resumed) {
      final leftAt = _leftAt;
      _leftAt = null;
      return leftAt != null && now.difference(leftAt) >= staleAfter;
    }
    _leftAt ??= now;
    return false;
  }
}

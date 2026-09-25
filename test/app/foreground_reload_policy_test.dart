import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/app/foreground_reload_policy.dart';

/// 原本只在 `paused` 記離開時間，但 `paused` 只有 iOS／Android 會進入
/// （Flutter SDK：AppLifecycleState.paused「only entered on iOS and Android」）。
/// macOS 失焦是 inactive、最小化是 hidden → 視窗長開時 launchd 已更新 DB，
/// 回到視窗卻從不重載，今日頁與資料落後提示停在舊狀態。
void main() {
  const staleAfter = Duration(minutes: 30);
  final t0 = DateTime(2026, 9, 25, 9);

  late ForegroundReloadPolicy policy;
  setUp(() => policy = ForegroundReloadPolicy(staleAfter: staleAfter));

  bool at(AppLifecycleState s, Duration offset) =>
      policy.onStateChanged(s, t0.add(offset));

  test('🚨 macOS：失焦（inactive）超過門檻後回來 → 重載', () {
    expect(at(AppLifecycleState.inactive, Duration.zero), isFalse);
    expect(at(AppLifecycleState.resumed, const Duration(minutes: 31)), isTrue);
  });

  test('🚨 macOS：失焦 → 最小化 → 還原，以最早離開時間計算', () {
    at(AppLifecycleState.inactive, Duration.zero);
    at(AppLifecycleState.hidden, const Duration(minutes: 20));
    at(AppLifecycleState.inactive, const Duration(minutes: 29));
    expect(at(AppLifecycleState.resumed, const Duration(minutes: 31)), isTrue);
  });

  test('手機：inactive → hidden → paused → 回來超過門檻 → 重載', () {
    at(AppLifecycleState.inactive, Duration.zero);
    at(AppLifecycleState.hidden, Duration.zero);
    at(AppLifecycleState.paused, Duration.zero);
    expect(at(AppLifecycleState.resumed, const Duration(minutes: 45)), isTrue);
  });

  test('短暫離開（拉下通知列、切去看一下）→ 不重載', () {
    at(AppLifecycleState.inactive, Duration.zero);
    expect(at(AppLifecycleState.resumed, const Duration(minutes: 5)), isFalse);
  });

  test('剛好達到門檻 → 重載', () {
    at(AppLifecycleState.inactive, Duration.zero);
    expect(at(AppLifecycleState.resumed, staleAfter), isTrue);
  });

  test('沒離開過就收到 resumed → 不重載', () {
    expect(at(AppLifecycleState.resumed, const Duration(hours: 5)), isFalse);
  });

  test('重載後歸零：下一次 resumed 不會重複觸發', () {
    at(AppLifecycleState.inactive, Duration.zero);
    expect(at(AppLifecycleState.resumed, const Duration(minutes: 31)), isTrue);
    expect(at(AppLifecycleState.resumed, const Duration(minutes: 90)), isFalse);
  });
}

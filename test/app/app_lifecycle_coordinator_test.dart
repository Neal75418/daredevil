import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:fake_async/fake_async.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/app/app_lifecycle_coordinator.dart';

/// App 生命週期的副作用集中在這裡測：這段曾在 macOS 上兩度失效——
/// 回前景不重載、配額從不落盤（兩者都只綁 paused，而 macOS 不會進 paused）。
void main() {
  final t0 = DateTime(2026, 9, 25, 9);
  late List<String> calls;
  late AppLifecycleCoordinator c;

  setUp(() {
    calls = [];
    c = AppLifecycleCoordinator(
      staleAfter: const Duration(minutes: 30),
      reload: () => calls.add('reload'),
      flushBudget: () async => calls.add('flush'),
      stopIntraday: () => calls.add('stop'),
      startIntraday: () => calls.add('start'),
    );
  });

  void go(AppLifecycleState s, [Duration after = Duration.zero]) =>
      c.onStateChanged(s, t0.add(after));

  group('macOS（沒有 paused）', () {
    test('🚨 失焦超過門檻後回來 → 重載', () {
      go(AppLifecycleState.inactive);
      go(AppLifecycleState.resumed, const Duration(minutes: 31));
      expect(calls, contains('reload'));
    });

    test('🚨 最小化 → 落盤', () {
      go(AppLifecycleState.inactive);
      go(AppLifecycleState.hidden);
      expect(calls, contains('flush'));
    });

    test('只是失焦（仍可見）→ 不落盤、不停盤中輪詢', () {
      go(AppLifecycleState.inactive);
      expect(calls, isEmpty);
    });

    test('🚨 Cmd+Q → 等落盤完成才回覆可以結束', () async {
      final gate = Completer<void>();
      c = AppLifecycleCoordinator(
        staleAfter: const Duration(minutes: 30),
        reload: () {},
        flushBudget: () => gate.future,
        stopIntraday: () {},
        startIntraday: () {},
      );
      var replied = false;
      final pending = c.onExitRequested().then((r) {
        replied = true;
        return r;
      });
      await pumpEventQueue();
      expect(replied, isFalse, reason: '落盤還沒完成就回覆＝engine 直接結束');

      gate.complete();
      expect(await pending, AppExitResponse.exit);
    });

    test('落盤卡住時不能讓 Cmd+Q 永遠沒反應（逾時後照樣結束）', () {
      fakeAsync((async) {
        c = AppLifecycleCoordinator(
          staleAfter: const Duration(minutes: 30),
          reload: () {},
          flushBudget: () => Completer<void>().future,
          stopIntraday: () {},
          startIntraday: () {},
        );
        AppExitResponse? response;
        c.onExitRequested().then((r) => response = r);
        async.elapse(const Duration(seconds: 1));
        expect(response, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(response, AppExitResponse.exit);
      });
    });
  });

  group('手機', () {
    test('退背景 → 落盤並停盤中輪詢；回來重新啟動', () {
      go(AppLifecycleState.inactive);
      go(AppLifecycleState.hidden);
      go(AppLifecycleState.paused);
      expect(calls, containsAll(['flush', 'stop']));

      calls.clear();
      go(AppLifecycleState.resumed, const Duration(minutes: 5));
      expect(calls, ['start'], reason: '未滿門檻不重載，但輪詢要恢復');
    });

    test('拉下通知列又收回（inactive↔resumed）→ 不重啟盤中輪詢', () {
      go(AppLifecycleState.inactive);
      go(AppLifecycleState.resumed, const Duration(minutes: 1));
      expect(calls, isEmpty);
    });

    test('退背景超過門檻回來 → 重載且重啟輪詢', () {
      go(AppLifecycleState.paused);
      calls.clear();
      go(AppLifecycleState.resumed, const Duration(minutes: 45));
      expect(calls, containsAll(['reload', 'start']));
    });
  });
}

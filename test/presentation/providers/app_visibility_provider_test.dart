import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/app_visibility_provider.dart';

void main() {
  testWidgets('沒有生命週期狀態時當成可見', (tester) async {
    expect(tester.binding.lifecycleState, isNull);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appVisibilityProvider), isTrue);
  });

  // testWidgets：結束時 binding 會重設生命週期，hidden 不會漏到下一條測試
  testWidgets('初值跟著 WidgetsBinding 的生命週期', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final hidden = ProviderContainer();
    addTearDown(hidden.dispose);
    expect(hidden.read(appVisibilityProvider), isFalse);

    for (final (state, visible) in const [
      (AppLifecycleState.resumed, true),
      // macOS 視窗失焦但看得到
      (AppLifecycleState.inactive, true),
      (AppLifecycleState.paused, false),
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appVisibilityProvider), visible, reason: '$state');
    }
  });

  testWidgets('set 後改變並通知', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <bool>[];
    container.listen(appVisibilityProvider, (_, next) => seen.add(next));

    container.read(appVisibilityProvider.notifier).set(false);
    container.read(appVisibilityProvider.notifier).set(false);
    container.read(appVisibilityProvider.notifier).set(true);

    expect(seen, [false, true]);
  });
}

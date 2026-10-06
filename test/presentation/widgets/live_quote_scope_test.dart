import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';

/// 週六:報價中心照常登記、計時,但不會發請求
class _SaturdayClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 3, 10);
}

/// 畫面登記與可見性(2026-10-06,spec §4)。
///
/// 用真的 go_router 與真的報價中心:套件升級改了 TickerMode 行為會先紅;
/// 報價中心若在 build 期間寫 state,Riverpod 會在這裡拋錯。
void main() {
  late ProviderContainer container;
  late GoRouter router;

  Set<String> registered() => container
      .read(liveQuoteCenterProvider.notifier)
      .registeredMarkets
      .keys
      .toSet();

  setUp(() {
    container = ProviderContainer(
      overrides: [appClockProvider.overrideWithValue(_SaturdayClock())],
    );
    router = GoRouter(
      initialLocation: '/watchlist',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/watchlist',
                  builder: (_, _) => const LiveQuoteScope(
                    registrations: [
                      LiveQuoteRegistration(
                        symbol: '2330',
                        market: MarketCode.twse,
                      ),
                    ],
                    child: Text('watchlist'),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/news', builder: (_, _) => const Text('news')),
              ],
            ),
          ],
        ),
        // 個股頁在 shell 外(同 lib/app/router.dart)
        GoRoute(
          path: '/stock',
          builder: (_, _) => const Scaffold(body: Text('stock')),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    container.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 拆掉整棵樹:scope dispose → 取消登記 → 報價中心停拍
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('🚨 切到別的分頁 → 取消登記;切回來 → 重新登記', (tester) async {
    await pumpApp(tester);
    expect(registered(), {'2330'});

    router.go('/news');
    await tester.pumpAndSettle();
    expect(registered(), isEmpty);

    router.go('/watchlist');
    await tester.pumpAndSettle();
    expect(registered(), {'2330'});
    await unmount(tester);
  });

  testWidgets('🚨 推入不透明頁面(個股頁)→ 底下的頁面取消登記;返回 → 重新登記', (tester) async {
    await pumpApp(tester);
    router.push('/stock');
    await tester.pumpAndSettle();
    expect(find.text('stock'), findsOneWidget);
    expect(registered(), isEmpty);

    router.pop();
    await tester.pumpAndSettle();
    expect(registered(), {'2330'});
    await unmount(tester);
  });

  testWidgets('開底部面板 → 底下的畫面維持登記', (tester) async {
    await pumpApp(tester);
    showModalBottomSheet<void>(
      context: tester.element(find.text('watchlist')),
      builder: (_) => const Text('sheet'),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(registered(), {'2330'});
    await unmount(tester);
  });

  testWidgets('離開畫面(dispose)→ 取消登記', (tester) async {
    await pumpApp(tester);
    await unmount(tester);
    expect(registered(), isEmpty);
  });

  testWidgets('清單改變 → 以新清單重新登記', (tester) async {
    Widget scope(List<String> symbols) => UncontrolledProviderScope(
      container: container,
      child: LiveQuoteScope(
        registrations: [
          for (final s in symbols)
            LiveQuoteRegistration(symbol: s, market: MarketCode.twse),
        ],
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(scope(['2330']));
    expect(registered(), {'2330'});
    await tester.pumpWidget(scope(['2330', '2317']));
    expect(registered(), {'2330', '2317'});
    await unmount(tester);
  });
}

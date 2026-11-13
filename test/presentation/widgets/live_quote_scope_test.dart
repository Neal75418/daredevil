import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';

/// 週六:報價中心照常登記、計時,但不會發請求
class _SaturdayClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 3, 10);
}

/// 測試用的代號清單(`LiveQuoteScope.listen` 的來源由它衍生)
class _Symbols extends Notifier<List<String>> {
  @override
  List<String> build() => const ['2330'];

  void set(List<String> next) => state = next;
}

/// 測試用的登記清單(直接當 `LiveQuoteScope.listen` 的來源)
class _Registrations extends Notifier<List<LiveQuoteRegistration>> {
  @override
  List<LiveQuoteRegistration> build() => _registrationsOf(const ['2330']);

  void set(List<String> symbols) => state = _registrationsOf(symbols);
}

List<LiveQuoteRegistration> _registrationsOf(List<String> symbols) => [
  for (final s in symbols)
    LiveQuoteRegistration(symbol: s, market: MarketCode.twse),
];

class _FnClock implements AppClock {
  _FnClock(this._now);
  final DateTime Function() _now;

  @override
  DateTime now() => _now();
}

/// 每個請求都有回應、但沒有任何報價(收盤後算一次「不是收盤報價」的嘗試,
/// 一分鐘後重抓);[requests] 記每個請求的代號
class _NotClosingClient extends IntradayQuoteClient {
  _NotClosingClient(this.requests) : super(dio: Dio(), logBatchErrors: false);
  final List<List<String>> requests;

  @override
  Future<QuoteBatchReport> fetchQuotesDetailed(
    Map<String, String> markets,
  ) async {
    requests.add(markets.keys.toList());
    return QuoteBatchReport(
      quotes: const {},
      errors: const [],
      respondedSymbols: markets.keys.toSet(),
      failedSymbols: const <String>{},
    );
  }
}

/// 記下每一次 `register` 收到的代號(其餘照真的報價中心)
class _RecordingCenter extends LiveQuoteCenter {
  _RecordingCenter(this.calls);
  final List<List<String>> calls;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) {
    calls.add([for (final r in entries) r.symbol]);
    super.register(owner, entries);
  }
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

  testWidgets('🚨 固定清單:內容沒變的重建也重新登記(登記日跟著畫面最近一次重建)→ 隔天畫面以'
      '「已有今天正式資料」重建之後,收盤後不再替它抓', (tester) async {
    // 週二 14:01(收盤後)登記;每秒一拍,時鐘跟著 pump 前進
    var now = DateTime(2026, 10, 6, 14, 1);
    final requests = <List<String>>[];
    final live = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_FnClock(() => now)),
        liveQuoteClientProvider.overrideWithValue(_NotClosingClient(requests)),
      ],
    );
    addTearDown(live.dispose);
    Future<void> elapse(Duration d) async {
      for (var i = 0; i < d.inSeconds; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    // 每次都是新的 widget 與新的清單物件,內容相同
    Widget scope() => UncontrolledProviderScope(
      container: live,
      child: LiveQuoteScope(
        registrations: [
          for (final symbol in ['2330'])
            LiveQuoteRegistration(
              symbol: symbol,
              market: MarketCode.twse,
              hasOfficialToday: true,
            ),
        ],
        child: const SizedBox(),
      ),
    );

    await tester.pumpWidget(scope());
    await elapse(const Duration(seconds: 10));
    expect(requests, isEmpty, reason: '前提:登記當天已有正式資料,收盤後不抓');

    // 隔天(週三)13:31,畫面一直沒有重建:前一天登記的「已有」不算數
    now = DateTime(2026, 10, 7, 13, 31);
    await elapse(const Duration(seconds: 10));
    expect(requests, hasLength(1), reason: '前提:登記日不是今天,照樣替它抓');

    // 畫面重建,這時已有今天的正式資料:清單內容與前一天那份相同
    await tester.pumpWidget(scope());
    await elapse(const Duration(minutes: 3));
    expect(requests, hasLength(1), reason: '重建過的「已有今天正式資料」算數,不再重抓');
    expect(
      live.read(liveQuoteCenterProvider.notifier).registeredMarkets.keys,
      ['2330'],
      reason: '不再抓是因為登記日更新了,不是因為沒登記',
    );
    await tester.pumpWidget(const SizedBox());
  });

  group('listen:清單由 provider 給,不靠畫面重畫', () {
    /// 衍生的清單來源:由 [symbols] 算出,[builds] 記重算次數
    ({
      NotifierProvider<_Symbols, List<String>> symbols,
      Provider<List<LiveQuoteRegistration>> source,
      int Function() builds,
    })
    derivedSource() {
      var builds = 0;
      final symbols = NotifierProvider<_Symbols, List<String>>(_Symbols.new);
      final source = Provider.autoDispose<List<LiveQuoteRegistration>>((ref) {
        builds++;
        return _registrationsOf(ref.watch(symbols));
      });
      return (symbols: symbols, source: source, builds: () => builds);
    }

    /// 衍生的 provider 由 ProviderScope 以 `Timer(Duration.zero)` 排程重算;
    /// 不帶時間的 `pump()` 不前進時間、計時器不會跑
    Future<void> letProvidersRecompute(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 1));

    testWidgets('🚨 清單一變就登記新的,不必 pump', (tester) async {
      final source =
          NotifierProvider<_Registrations, List<LiveQuoteRegistration>>(
            _Registrations.new,
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LiveQuoteScope.listen(source: source, child: const SizedBox()),
        ),
      );
      expect(registered(), {'2330'});

      container.read(source.notifier).set(['2330', '2317']);
      expect(registered(), {'2330', '2317'});
      await unmount(tester);
    });

    testWidgets('🚨 App 看不見、畫面停止排程:衍生的清單變了照樣登記', (tester) async {
      final (:symbols, :source, builds: _) = derivedSource();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LiveQuoteScope.listen(source: source, child: const SizedBox()),
        ),
      );
      expect(registered(), {'2330'});

      void setLifecycle(AppLifecycleState state) =>
          tester.binding.handleAppLifecycleStateChanged(state);
      addTearDown(() => setLifecycle(AppLifecycleState.resumed));
      setLifecycle(AppLifecycleState.hidden);
      await tester.pump(); // 切到 hidden 之前已經排好的那一幀
      expect(tester.binding.framesEnabled, isFalse, reason: '前提:看不見時不畫幀');

      container.read(symbols.notifier).set(['2317']);
      await letProvidersRecompute(tester);
      expect(registered(), {'2317'});

      // 回到可見才拆得掉樹(看不見時不畫幀)
      setLifecycle(AppLifecycleState.resumed);
      await unmount(tester);
    });

    /// `/list`(讀主題、每次重建都新建一個 `LiveQuoteScope.listen`)與不透明
    /// 的 `/stock`;[themeMode] 切換時底下的頁面跟著重建
    Future<({GoRouter router, int Function() listBuilds})> pumpCoverable(
      WidgetTester tester,
      Provider<List<LiveQuoteRegistration>> source,
      ValueNotifier<ThemeMode> themeMode,
    ) async {
      var listBuilds = 0;
      final router = GoRouter(
        initialLocation: '/list',
        routes: [
          GoRoute(
            path: '/list',
            builder: (context, _) {
              listBuilds++;
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: LiveQuoteScope.listen(
                  source: source,
                  child: const Text('list'),
                ),
              );
            },
          ),
          GoRoute(
            path: '/stock',
            builder: (_, _) => const Scaffold(body: Text('stock')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ValueListenableBuilder(
            valueListenable: themeMode,
            builder: (_, mode, _) => MaterialApp.router(
              routerConfig: router,
              themeMode: mode,
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (router: router, listBuilds: () => listBuilds);
    }

    testWidgets('🚨 被不透明頁面蓋住 → 取消登記、清單來源不重算(期間清單變兩次、頁面重建);'
        '回來 → 以現值重新登記,之後照樣跟著換', (tester) async {
      final (:symbols, :source, :builds) = derivedSource();
      final themeMode = ValueNotifier(ThemeMode.light);
      addTearDown(themeMode.dispose);
      final (:router, :listBuilds) = await pumpCoverable(
        tester,
        source,
        themeMode,
      );
      expect(registered(), {'2330'});

      router.push('/stock');
      await tester.pumpAndSettle();
      expect(find.text('stock'), findsOneWidget);
      expect(registered(), isEmpty);
      final sourceBuildsWhenCovered = builds();
      final listBuildsWhenCovered = listBuilds();

      // 蓋住期間:清單依賴的資料變兩次,切兩次深色模式(底下的頁面每次都重建、
      // 新建一個 LiveQuoteScope.listen)
      container.read(symbols.notifier).set(['2317']);
      themeMode.value = ThemeMode.dark;
      await tester.pumpAndSettle();
      container.read(symbols.notifier).set(['2317', '2454']);
      themeMode.value = ThemeMode.light;
      await tester.pumpAndSettle();
      expect(
        listBuilds(),
        greaterThanOrEqualTo(listBuildsWhenCovered + 2),
        reason: '前提:蓋住期間底下的頁面至少重建兩次',
      );
      expect(registered(), isEmpty, reason: '蓋住期間不登記');
      expect(builds(), sourceBuildsWhenCovered, reason: '蓋住期間清單來源不重算');

      router.pop();
      await tester.pumpAndSettle();
      expect(registered(), {'2317', '2454'}, reason: '以現值重新登記');

      container.read(symbols.notifier).set(['3008']);
      await letProvidersRecompute(tester);
      expect(registered(), {'3008'}, reason: '回來之後清單變了照樣跟著換');
      await unmount(tester);
    });

    testWidgets('🚨 蓋住期間清單沒變:回來照樣重新登記', (tester) async {
      final (symbols: _, :source, builds: _) = derivedSource();
      final themeMode = ValueNotifier(ThemeMode.light);
      addTearDown(themeMode.dispose);
      final (:router, listBuilds: _) = await pumpCoverable(
        tester,
        source,
        themeMode,
      );
      router.push('/stock');
      await tester.pumpAndSettle();
      expect(registered(), isEmpty);

      router.pop();
      await tester.pumpAndSettle();
      expect(registered(), {'2330'});
      await unmount(tester);
    });

    testWidgets('🚨 TickerMode 關閉期間又收到一次相依變動(搬到樹上別處)→ 仍不登記;'
        '打開後清單變了照樣跟著換', (tester) async {
      final (:symbols, :source, builds: _) = derivedSource();
      final key = GlobalKey();
      Widget tree({required bool enabled, required bool moved}) {
        final scope = KeyedSubtree(
          key: key,
          child: LiveQuoteScope.listen(source: source, child: const SizedBox()),
        );
        return UncontrolledProviderScope(
          container: container,
          child: TickerMode(
            enabled: enabled,
            child: moved
                ? Padding(padding: EdgeInsets.zero, child: scope)
                : scope,
          ),
        );
      }

      await tester.pumpWidget(tree(enabled: true, moved: false));
      expect(registered(), {'2330'});
      await tester.pumpWidget(tree(enabled: false, moved: false));
      expect(registered(), isEmpty);
      // 同一個 State 搬到別的位置:TickerMode 沒變,但會再收到一次相依變動
      await tester.pumpWidget(tree(enabled: false, moved: true));
      expect(registered(), isEmpty);

      await tester.pumpWidget(tree(enabled: true, moved: true));
      expect(registered(), {'2330'});
      container.read(symbols.notifier).set(['2317']);
      await letProvidersRecompute(tester);
      expect(registered(), {'2317'});
      await unmount(tester);
    });

    testWidgets('🚨 看得見時又收到一次相依變動(搬到樹上別處)→ 不重複訂閱:'
        '清單變一次只登記一次', (tester) async {
      final registerCalls = <List<String>>[];
      final counting = ProviderContainer(
        overrides: [
          appClockProvider.overrideWithValue(_SaturdayClock()),
          liveQuoteCenterProvider.overrideWith(
            () => _RecordingCenter(registerCalls),
          ),
        ],
      );
      addTearDown(counting.dispose);
      final (:symbols, :source, builds: _) = derivedSource();
      final key = GlobalKey();
      Widget tree({required bool moved}) {
        final scope = KeyedSubtree(
          key: key,
          child: LiveQuoteScope.listen(source: source, child: const SizedBox()),
        );
        return UncontrolledProviderScope(
          container: counting,
          child: TickerMode(
            enabled: true,
            child: moved
                ? Padding(padding: EdgeInsets.zero, child: scope)
                : scope,
          ),
        );
      }

      await tester.pumpWidget(tree(moved: false));
      await tester.pumpWidget(tree(moved: true));
      expect(
        registerCalls,
        hasLength(greaterThan(1)),
        reason: '前提:搬動後又同步過(重建與相依變動各同步一次)',
      );

      registerCalls.clear();
      counting.read(symbols.notifier).set(['2317']);
      await letProvidersRecompute(tester);
      expect(registerCalls, [
        ['2317'],
      ]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('換了清單來源 → 改聽新的,舊的變動不再理會', (tester) async {
      final a = derivedSource();
      final b = derivedSource();
      Widget scope(Provider<List<LiveQuoteRegistration>> source) =>
          UncontrolledProviderScope(
            container: container,
            child: LiveQuoteScope.listen(
              source: source,
              child: const SizedBox(),
            ),
          );
      await tester.pumpWidget(scope(a.source));
      container.read(b.symbols.notifier).set(['2317']);
      await tester.pumpWidget(scope(b.source));
      expect(registered(), {'2317'});

      container.read(a.symbols.notifier).set(['9999']);
      await letProvidersRecompute(tester);
      expect(registered(), {'2317'}, reason: '舊的來源不再理會');
      container.read(b.symbols.notifier).set(['3008']);
      await letProvidersRecompute(tester);
      expect(registered(), {'3008'});
      await unmount(tester);
    });
  });
}

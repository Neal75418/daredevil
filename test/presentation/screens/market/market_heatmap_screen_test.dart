import 'package:easy_localization/easy_localization.dart' show EasyLocalization;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/app_visibility_provider.dart';
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/screens/market/market_heatmap_screen.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_legend.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_view.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class _FakeHeatmap extends MarketHeatmapNotifier {
  _FakeHeatmap(this._initial);
  final MarketHeatmapState _initial;
  int reloads = 0;
  final visible = <bool>[];

  @override
  MarketHeatmapState build() => _initial;

  @override
  Future<void> reload() async => reloads++;

  @override
  void setVisible(bool visible) => this.visible.add(visible);
}

class _FakeOverview extends MarketOverviewNotifier {
  _FakeOverview(this._initial);
  final MarketOverviewState _initial;

  @override
  MarketOverviewState build() => _initial;

  @override
  Future<void> loadData() async {}
}

HeatmapTile _tile(
  String symbol,
  String name,
  double cap,
  double pct, {
  bool mine = false,
  String? industry = '半導體業',
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  industry: industry,
  close: 100,
  marketCap: cap,
  change: TileChangeValue(pct),
  isMine: mine,
);

HeatmapTile _hollowTile(
  String symbol,
  String name,
  double cap, {
  String? industry = '半導體業',
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  industry: industry,
  close: 100,
  marketCap: cap,
  change: const TileChangeHollow(HollowReason.noChangeData),
  isMine: false,
);

/// 上市六檔（市值降冪）
HeatmapMarketData _twse({int excluded = 0}) => HeatmapMarketData(
  market: MarketCode.twse,
  dataDate: DateTime(2026, 10, 7),
  capCoverage: 0.74,
  excludedForShares: excluded,
  tiles: [
    _tile('9901', '測試甲', 8e11, 1.8),
    _tile('9911', '測試丁', 5e11, -0.4, industry: '其他電子零組件業'),
    _tile('9902', '測試乙', 2e11, 1.8),
    _hollowTile('9931', '測試航運', 2e11, industry: '航運業'),
    _tile('9912', '測試平', 1e11, 0, industry: '其他電子零組件業'),
    // 四捨五入到 0.00% 的漲跌：顏色是平盤，描述也要唸平盤
    _tile('9913', '測試微', 1e11, 0.004, industry: '其他電子零組件業'),
  ],
);

final _tpex = HeatmapMarketData(
  market: MarketCode.tpex,
  dataDate: DateTime(2026, 10, 6),
  capCoverage: 0.52,
  excludedForShares: 0,
  tiles: [_tile('9951', '測試戊', 1e11, -2, industry: '生技醫療業')],
);

MarketHeatmapState _loaded(Map<String, HeatmapMarketData> markets) =>
    MarketHeatmapState(isLoading: false, markets: markets);

/// provider 第一次讀取兩個市場都失敗時的狀態（error 只在這種時候設）
MarketHeatmapState _bothFailed() => MarketHeatmapState(
  isLoading: false,
  error: Exception('boom'),
  failedMarkets: const {MarketCode.twse, MarketCode.tpex},
);

final _overview = MarketOverviewState(
  indices: [
    TwseMarketIndex(
      date: DateTime(2026, 10, 7),
      name: MarketIndexNames.taiex,
      close: 22150.3,
      change: -61.2,
      changePercent: -0.28,
    ),
    TwseMarketIndex(
      date: DateTime(2026, 10, 6),
      name: MarketIndexNames.tpexIndex,
      close: 245.6,
      change: 0.25,
      changePercent: 0.1,
    ),
  ],
);

class _Clock implements AppClock {
  _Clock(this.value);
  DateTime value;

  @override
  DateTime now() => value;
}

/// 正式資料的測試用的時刻：資料日（10/6、10/7）的隔天開盤前，不需要即時
final _preOpen = DateTime(2026, 10, 8, 8);

List<Override> _overrides(
  _FakeHeatmap fake, {
  MarketOverviewState? overview,
  MarketLiveIndices live = const MarketLiveIndices(),
}) => [
  marketHeatmapProvider.overrideWith(() => fake),
  marketOverviewProvider.overrideWith(
    () => _FakeOverview(overview ?? _overview),
  ),
  marketLiveIndicesProvider.overrideWithValue(live),
  appClockProvider.overrideWithValue(_Clock(_preOpen)),
];

Finder get _painterFinder => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is HeatmapPainter,
);

HeatmapPainter _painterOf(WidgetTester tester) =>
    tester.widget<CustomPaint>(_painterFinder).painter! as HeatmapPainter;

Offset _tileCenter(WidgetTester tester, String symbol) {
  final tile = _painterOf(
    tester,
  ).layout.firstWhere((t) => t.tile.symbol == symbol);
  final b = tile.paint;
  return tester.getTopLeft(find.byType(HeatmapView)) +
      Offset(b.left + b.width / 2, b.top + b.height / 2);
}

void main() {
  setUpAll(() async => setupTestLocalization());

  void viewport(WidgetTester tester, {Size size = const Size(1200, 900)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<_FakeHeatmap> pump(
    WidgetTester tester,
    MarketHeatmapState state, {
    MarketOverviewState? overview,
    MarketLiveIndices live = const MarketLiveIndices(),
    Brightness brightness = Brightness.light,
    bool settle = true,
  }) async {
    viewport(tester);
    final fake = _FakeHeatmap(state);
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: _overrides(fake, overview: overview, live: live),
        zhTranslations: true,
        brightness: brightness,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return fake;
  }

  /// 首頁 `/`（一個按鈕推入熱力圖）、熱力圖、個股頁、另一個不透明頁
  GoRouter testRouter({String initial = '/'}) {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(AppRoutes.marketHeatmap),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.marketHeatmap,
          builder: (_, _) => const MarketHeatmapScreen(),
        ),
        GoRoute(
          path: AppRoutes.stockDetailTemplate,
          builder: (_, state) =>
              Scaffold(body: Text('stock ${state.pathParameters['symbol']}')),
        ),
        GoRoute(
          path: '/other',
          builder: (_, _) => const Scaffold(body: Text('other')),
        ),
      ],
    );
    addTearDown(router.dispose);
    return router;
  }

  Future<_FakeHeatmap> pumpRouter(
    WidgetTester tester,
    GoRouter router,
    MarketHeatmapState state, {
    Size size = const Size(1200, 900),
  }) async {
    viewport(tester, size: size);
    final fake = _FakeHeatmap(state);
    await tester.pumpWidget(
      buildProviderTestApp(
        const SizedBox(),
        overrides: _overrides(fake),
        router: router,
        zhTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  group('狀態', () {
    // 證交所約 14:00 公布今天收盤 → 指數是今天；格子要等每日更新。右側「M/D 收盤」
    // 是格子的日期，指數要另外說明。比較的是格子自己的日期（各市場分開定案）
    testWidgets('🚨 指數比格子新 → 標「指數為 M/D 收盤」；同一天的市場不標', (tester) async {
      final newer = _overview.copyWith(
        indices: [
          for (final i in _overview.indices)
            i.name == MarketIndexNames.taiex
                ? TwseMarketIndex(
                    date: DateTime(2026, 10, 8),
                    name: i.name,
                    close: i.close,
                    change: i.change,
                    changePercent: i.changePercent,
                  )
                : i,
        ],
      );
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse(), MarketCode.tpex: _tpex}),
        overview: newer,
      );
      expect(find.text('指數為 10/8 收盤'), findsOneWidget);

      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.textContaining('指數為'), findsNothing);
    });

    testWidgets('兩個市場日期不同時頁首跟著切換', (tester) async {
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse(), MarketCode.tpex: _tpex}),
      );
      expect(find.text('10/7 收盤'), findsOneWidget);
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.text('10/6 收盤'), findsOneWidget);
      expect(find.text('10/7 收盤'), findsNothing);
    });

    testWidgets('只有一個市場有資料，另一個顯示空狀態', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      expect(find.byType(HeatmapView), findsOneWidget);
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.byType(HeatmapView), findsNothing);
      expect(find.text('完成第一次資料更新後就會顯示'), findsOneWidget);
    });

    testWidgets('第一次讀取失敗顯示錯誤卡片、重試呼叫 reload', (tester) async {
      final fake = await pump(tester, _bothFailed());
      expect(find.text('熱力圖資料讀取失敗'), findsOneWidget);
      expect(find.text('完成第一次資料更新後就會顯示'), findsNothing);
      await tester.tap(find.text('重試'));
      expect(fake.reloads, 1);
    });

    testWidgets('單一市場第一次讀取失敗時顯示錯誤卡片，不是空狀態', (tester) async {
      await pump(
        tester,
        MarketHeatmapState(
          isLoading: false,
          markets: {MarketCode.twse: _twse()},
          failedMarkets: const {MarketCode.tpex},
        ),
      );
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.text('熱力圖資料讀取失敗'), findsOneWidget);
      expect(find.text('完成第一次資料更新後就會顯示'), findsNothing);
    });

    testWidgets('有資料但上一次讀取失敗：照常畫舊資料', (tester) async {
      await pump(
        tester,
        MarketHeatmapState(
          isLoading: false,
          markets: {MarketCode.twse: _twse()},
          failedMarkets: const {MarketCode.twse},
        ),
      );
      expect(find.byType(HeatmapView), findsOneWidget);
      expect(find.text('熱力圖資料讀取失敗'), findsNothing);
    });

    testWidgets('沒有任何資料顯示空狀態文案', (tester) async {
      await pump(tester, const MarketHeatmapState(isLoading: false));
      expect(find.text('完成第一次資料更新後就會顯示'), findsOneWidget);
      expect(find.byType(HeatmapView), findsNothing);
    });

    testWidgets('第一次讀取中顯示載入中', (tester) async {
      await pump(tester, const MarketHeatmapState(), settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('完成第一次資料更新後就會顯示'), findsNothing);
    });

    testWidgets('頁尾只在有缺股數時顯示', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse(excluded: 3)}));
      expect(find.text('3 檔缺股數或股數不一致，未列入'), findsOneWidget);
    });

    testWidgets('沒有缺股數時沒有頁尾', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      expect(find.textContaining('未列入'), findsNothing);
    });
  });

  group('圖例', () {
    List<Color> expectedScale(Brightness b) => [
      for (var step = 6; step >= 1; step--)
        HeatmapColors.fill(step: step, up: false, brightness: b),
      HeatmapColors.flat(b),
      for (var step = 1; step <= 6; step++)
        HeatmapColors.fill(step: step, up: true, brightness: b),
    ];

    List<Color> shownScale(WidgetTester tester) => [
      for (var i = 0; i < 13; i++)
        tester.widget<ColoredBox>(find.byKey(HeatmapLegend.swatchKey(i))).color,
    ];

    testWidgets('13 格色階與四項說明；切換主題後色塊換成該主題色表', (tester) async {
      viewport(tester);
      final fake = _FakeHeatmap(_loaded({MarketCode.twse: _twse()}));
      Widget app(Brightness b) => buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: _overrides(fake),
        zhTranslations: true,
        brightness: b,
      );
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      expect(shownScale(tester), expectedScale(Brightness.light));
      expect(find.text('跌 ≥ 9.5%'), findsOneWidget);
      expect(find.text('漲 ≥ 9.5%'), findsOneWidget);
      // 跌在綠色那端（左）、漲在紅色那端（右）
      expect(
        tester.getTopLeft(find.text('跌 ≥ 9.5%')).dx,
        lessThan(tester.getTopLeft(find.byKey(HeatmapLegend.swatchKey(0))).dx),
      );
      expect(
        tester.getTopLeft(find.text('漲 ≥ 9.5%')).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(HeatmapLegend.swatchKey(12))).dx,
        ),
      );
      expect(find.text('雙線框＝自選或持股'), findsOneWidget);
      expect(find.text('空心＝沒有今日漲跌'), findsOneWidget);
      expect(find.text('市值前 6 檔・占上市市值 74%'), findsOneWidget);

      await tester.pumpWidget(app(Brightness.dark));
      await tester.pumpAndSettle();
      expect(shownScale(tester), expectedScale(Brightness.dark));
    });

    testWidgets('寬畫面時圖例排成一行', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      final tops = {
        for (final text in [
          '跌 ≥ 9.5%',
          '漲 ≥ 9.5%',
          '雙線框＝自選或持股',
          '空心＝沒有今日漲跌',
          '市值前 6 檔・占上市市值 74%',
        ])
          tester.getTopLeft(find.text(text).first).dy,
      };
      expect(tops, hasLength(1));
    });

    testWidgets('🚨 切到上櫃：市場名稱、檔數與百分比跟著換', (tester) async {
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse(), MarketCode.tpex: _tpex}),
      );
      expect(find.text('市值前 6 檔・占上市市值 74%'), findsOneWidget);
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.text('市值前 1 檔・占上櫃市值 52%'), findsOneWidget);
      expect(find.textContaining('占上市市值'), findsNothing);
    });

    testWidgets('🚨 可畫的只有 3 檔、全部都畫：寫 3 檔、100%', (tester) async {
      await pump(
        tester,
        _loaded({
          MarketCode.twse: HeatmapMarketData(
            market: MarketCode.twse,
            dataDate: DateTime(2026, 10, 7),
            capCoverage: 1,
            excludedForShares: 0,
            tiles: [
              _tile('9901', '測試甲', 3e11, 1),
              _tile('9902', '測試乙', 2e11, 1),
              _tile('9903', '測試丙', 1e11, 1),
            ],
          ),
        }),
      );
      expect(find.text('市值前 3 檔・占上市市值 100%'), findsOneWidget);
    });

    testWidgets('🚨 還有沒畫的就不寫 100%：覆蓋率 99.6% 寫 99%', (tester) async {
      await pump(
        tester,
        _loaded({
          MarketCode.twse: HeatmapMarketData(
            market: MarketCode.twse,
            dataDate: DateTime(2026, 10, 7),
            capCoverage: 0.996,
            excludedForShares: 0,
            tiles: [_tile('9901', '測試甲', 3e11, 1)],
          ),
        }),
      );
      expect(find.text('市值前 1 檔・占上市市值 99%'), findsOneWidget);
    });

    testWidgets('標題列只有上市／上櫃切換，沒有別的動作按鈕', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.actions!.whereType<SegmentedButton<String>>(), hasLength(1));
      expect(find.byType(PopupMenuButton<Object>), findsNothing);
      expect(find.text('大盤熱力圖'), findsOneWidget);
    });
  });

  group('指數', () {
    final staleOverview = MarketOverviewState(
      indices: _overview.indices,
      indexStaleNames: const {MarketIndexNames.taiex},
    );

    testWidgets('指數非即時時標示，與大盤總覽一致', (tester) async {
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse()}),
        overview: staleOverview,
        live: MarketLiveIndices(
          byMarket: {
            MarketCode.twse: MarketIndexLive(
              index: _overview.indices.first,
              isLive: false,
            ),
          },
        ),
      );
      expect(find.textContaining('加權'), findsWidgets);
      expect(find.textContaining('22,150.30'), findsOneWidget);
      expect(find.textContaining('-0.28%'), findsOneWidget);
      expect(find.textContaining('非即時(10/7)'), findsOneWidget);
    });

    testWidgets('即時報價時不標非即時、顯示即時點數', (tester) async {
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse()}),
        overview: staleOverview,
        live: MarketLiveIndices(
          byMarket: {
            MarketCode.twse: MarketIndexLive(
              index: TwseMarketIndex(
                date: DateTime(2026, 10, 8),
                name: MarketIndexNames.taiex,
                close: 22300,
                change: 149.7,
                changePercent: 0.68,
              ),
              isLive: true,
              statusText: '盤中 10:14:55',
            ),
          },
        ),
      );
      expect(find.textContaining('22,300.00'), findsOneWidget);
      expect(find.textContaining('+0.68%'), findsOneWidget);
      expect(find.textContaining('非即時'), findsNothing);
      expect(find.text('盤中 10:14:55'), findsOneWidget);
    });

    testWidgets('沒有即時報價時用大盤總覽的官方值；不是備援值就不標非即時', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      expect(find.textContaining('22,150.30'), findsOneWidget);
      expect(find.textContaining('非即時'), findsNothing);
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.textContaining('245.60'), findsOneWidget);
      expect(find.textContaining('櫃買'), findsWidgets);
    });

    testWidgets('即時報價的閃色事件與設定接到點數', (tester) async {
      const flash = LiveQuoteFlash(id: 7, up: true);
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse()}),
        live: MarketLiveIndices(
          byMarket: {
            MarketCode.twse: MarketIndexLive(
              index: _overview.indices.first,
              isLive: true,
              flash: flash,
              flashEnabled: false,
            ),
          },
        ),
      );
      final priceFlash = tester.widget<PriceFlash>(find.byType(PriceFlash));
      expect(priceFlash.flash, flash);
      expect(priceFlash.enabled, isFalse);
    });

    testWidgets('指數兩者都沒有時顯示暫無資料', (tester) async {
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse()}),
        overview: const MarketOverviewState(),
      );
      expect(find.textContaining('暫無資料'), findsOneWidget);
    });
  });

  group('無障礙描述', () {
    testWidgets('🚨 每一格唸股名與漲跌；空心唸原因；四捨五入到 0.00% 的唸平盤', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      expect(find.semantics.byLabel('測試甲，上漲 1.80%'), findsOneWidget);
      expect(find.semantics.byLabel('測試丁，下跌 0.40%'), findsOneWidget);
      expect(find.semantics.byLabel('測試平，平盤 0.00%'), findsOneWidget);
      expect(find.semantics.byLabel('測試微，平盤 0.00%'), findsOneWidget);
      expect(find.semantics.byLabel('測試航運，無漲跌資料'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('英文：無障礙描述與提示用英文句型', (tester) async {
    viewport(tester);
    final handle = tester.ensureSemantics();
    final fake = _FakeHeatmap(_loaded({MarketCode.twse: _twse()}));
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: _overrides(fake),
        enTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('測試甲, up 1.80%'), findsOneWidget);
    expect(find.semantics.byLabel('測試航運: No change data'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(_tileCenter(tester, '9931'));
    await tester.pump();
    expect(find.text('Change: No change data'), findsOneWidget);
    await mouse.moveTo(_tileCenter(tester, '9901'));
    await tester.pump();
    expect(find.text('Price: 100.00'), findsOneWidget);
    expect(find.text('Change: +1.80%'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('🚨 同一頁換語系：交給 painter 的 labels 換成新語系的，描述改用新語系的句型', (
    tester,
  ) async {
    viewport(tester);
    final handle = tester.ensureSemantics();
    final fake = _FakeHeatmap(_loaded({MarketCode.twse: _twse()}));
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: _overrides(fake),
        switchableTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(MarketHeatmapScreen));
    final before = _painterOf(tester).labels;
    expect(before.locale, const Locale('zh', 'TW'));
    expect(find.semantics.byLabel('測試甲，上漲 1.80%'), findsOneWidget);

    await EasyLocalization.of(
      tester.element(find.byType(MarketHeatmapScreen)),
    )!.setLocale(const Locale('en', 'US'));
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(MarketHeatmapScreen)),
      same(state),
      reason: '前提：還是同一頁（State 沒有重建）',
    );
    final after = _painterOf(tester).labels;
    expect(after.locale, const Locale('en', 'US'));
    expect(after, isNot(before), reason: '與換語系前的不相等，painter 才重建描述');
    expect(find.semantics.byLabel('測試甲, up 1.80%'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('重建時沿用同一份 labels（painter 不因此重畫）', (tester) async {
    final fake = await pump(tester, _loaded({MarketCode.twse: _twse()}));
    final before = _painterOf(tester).labels;
    fake.state = _loaded({MarketCode.twse: _twse(excluded: 1)});
    await tester.pumpAndSettle();
    expect(identical(_painterOf(tester).labels, before), isTrue);
  });

  testWidgets('不需要即時時只登記目前市場的指數，切換市場跟著換', (tester) async {
    viewport(tester);
    final center = _LiveCenter();
    final fake = _FakeHeatmap(
      _loaded({MarketCode.twse: _twse(), MarketCode.tpex: _tpex}),
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: _overrides(fake),
        zhTranslations: true,
        liveQuoteCenter: () => center,
      ),
    );
    await tester.pumpAndSettle();
    expect(center.symbols, {LiveQuoteParams.indexSymbolOf(MarketCode.twse)});
    await tester.tap(find.text('上櫃'));
    await tester.pumpAndSettle();
    expect(center.symbols, {LiveQuoteParams.indexSymbolOf(MarketCode.tpex)});
  });

  testWidgets('點格子進個股頁', (tester) async {
    final router = testRouter(initial: AppRoutes.marketHeatmap);
    await pumpRouter(tester, router, _loaded({MarketCode.twse: _twse()}));
    await tester.tapAt(_tileCenter(tester, '9901'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/stock/9901');
    expect(find.text('stock 9901'), findsOneWidget);
  });

  group('可見性', () {
    testWidgets('被不透明頁蓋住時 setVisible(false)、返回後 true', (tester) async {
      final router = testRouter(initial: AppRoutes.marketHeatmap);
      final fake = await pumpRouter(
        tester,
        router,
        _loaded({MarketCode.twse: _twse()}),
      );
      expect(fake.visible.last, isTrue);
      router.push('/other');
      await tester.pumpAndSettle();
      expect(fake.visible.last, isFalse);
      router.pop();
      await tester.pumpAndSettle();
      expect(fake.visible.last, isTrue);
    });

    testWidgets('App 切到背景時 setVisible(false)、回來 true', (tester) async {
      final fake = await pump(tester, _loaded({MarketCode.twse: _twse()}));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MarketHeatmapScreen)),
      );
      container.read(appVisibilityProvider.notifier).set(false);
      await tester.pump();
      expect(fake.visible.last, isFalse);
      container.read(appVisibilityProvider.notifier).set(true);
      await tester.pump();
      expect(fake.visible.last, isTrue);
    });

    for (final (desc, state, settle) in [
      ('空狀態', const MarketHeatmapState(isLoading: false), true),
      ('錯誤卡片', _bothFailed(), true),
      ('載入中', const MarketHeatmapState(), false),
    ]) {
      testWidgets('$desc也會 setVisible(true)', (tester) async {
        final fake = await pump(tester, state, settle: settle);
        expect(fake.visible, [true]);
      });
    }

    testWidgets('切到沒資料的市場不會 setVisible(false)', (tester) async {
      final fake = await pump(tester, _loaded({MarketCode.twse: _twse()}));
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(find.text('完成第一次資料更新後就會顯示'), findsOneWidget);
      expect(fake.visible, isNot(contains(false)));
    });

    testWidgets('離開頁面時 setVisible(false) 不拋錯', (tester) async {
      final router = testRouter();
      final fake = await pumpRouter(
        tester,
        router,
        _loaded({MarketCode.twse: _twse()}),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(fake.visible.last, isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('open'), findsOneWidget);
      expect(fake.visible.last, isFalse);
    });
  });

  group('即時', () {
    final friday = DateTime(2026, 11, 6);
    DateTime monday(int h, int m, [int s = 0]) =>
        DateTime(2026, 11, 9, h, m, s);
    final today = DateTime(2026, 11, 9);

    /// 上市五檔、上櫃三檔（市值降冪），資料日上週五
    HeatmapMarketData twse() => HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: friday,
      capCoverage: 0.74,
      excludedForShares: 0,
      tiles: [
        _tile('9901', '測試甲', 8e11, -0.8),
        _tile('9911', '測試丁', 5e11, -0.4, industry: '其他電子零組件業'),
        _tile('9902', '測試乙', 2e11, -0.8),
        _tile('9931', '測試航運', 2e11, 0.5, industry: '航運業'),
        _tile('9912', '測試平', 1e11, 0, industry: '其他電子零組件業'),
      ],
    );

    HeatmapMarketData tpex() => HeatmapMarketData(
      market: MarketCode.tpex,
      dataDate: friday,
      capCoverage: 0.52,
      excludedForShares: 0,
      tiles: [
        _tile('9951', '測試戊', 3e11, -2, industry: '生技醫療業'),
        _tile('9952', '測試己', 1e11, -2, industry: '生技醫療業'),
        _tile('9961', '測試庚', 1e11, 1, industry: '觀光餐旅業'),
      ],
    );

    /// 上市 30 檔（收盤後的進度用），市值降冪。虛構代號以英文字母開頭
    HeatmapMarketData twse30() => HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: friday,
      capCoverage: 0.74,
      excludedForShares: 0,
      tiles: [
        for (var i = 0; i < 30; i++)
          _tile('Z${i.toString().padLeft(2, '0')}', '測$i', (100 - i) * 1e9, 1),
      ],
    );

    final overviewFriday = MarketOverviewState(
      indices: [
        TwseMarketIndex(
          date: friday,
          name: MarketIndexNames.taiex,
          close: 22150.3,
          change: -61.2,
          changePercent: -0.28,
        ),
        TwseMarketIndex(
          date: friday,
          name: MarketIndexNames.tpexIndex,
          close: 245.6,
          change: 0.25,
          changePercent: 0.1,
        ),
      ],
    );

    /// 昨收 100 的報價（成交價 [price]）
    LiveQuoteEntry quote(String symbol, double price, {bool closing = false}) =>
        LiveQuoteEntry(
          symbol: symbol,
          date: today,
          price: price,
          displaySource: LiveDisplaySource.trade,
          previousClose: 100,
          quoteTime: closing ? '13:30:00' : '10:30:00',
          isClosingQuote: closing,
          rowTime: closing ? '13:30:00' : '10:30:05',
        );

    /// 指數自己的報價狀態：與熱力圖的狀態行分得出來
    final indexLive = MarketLiveIndices(
      byMarket: {
        MarketCode.twse: MarketIndexLive(
          index: overviewFriday.indices.first,
          isLive: false,
          statusText: '指數自己的狀態',
        ),
      },
    );

    /// [live] 為 null 時用真的指數 provider（指數的狀態由報價中心算出）
    Future<({_LiveCenter center, _Clock clock, ProviderContainer container})>
    pumpLive(
      WidgetTester tester, {
      required DateTime at,
      Map<String, HeatmapMarketData>? markets,
      LiveQuoteState state = const LiveQuoteState(),
      MarketOverviewState? overview,
      MarketLiveIndices? live,
      GoRouter? router,
      bool english = false,
    }) async {
      viewport(tester);
      final clock = _Clock(at);
      final center = _LiveCenter(state);
      final fake = _FakeHeatmap(
        _loaded(markets ?? {MarketCode.twse: twse(), MarketCode.tpex: tpex()}),
      );
      await tester.pumpWidget(
        buildProviderTestApp(
          router == null ? const MarketHeatmapScreen() : const SizedBox(),
          overrides: [
            marketHeatmapProvider.overrideWith(() => fake),
            marketOverviewProvider.overrideWith(
              () => _FakeOverview(overview ?? overviewFriday),
            ),
            appClockProvider.overrideWithValue(clock),
            if (live != null)
              marketLiveIndicesProvider.overrideWithValue(live)
            else
              settingsProvider.overrideWith(_FakeSettings.new),
          ],
          router: router,
          zhTranslations: !english,
          enTranslations: english,
          liveQuoteCenter: () => center,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      return (center: center, clock: clock, container: container);
    }

    Text statusLine(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(MarketHeatmapScreen.statusLineKey));

    HeatmapTile tileOf(WidgetTester tester, String symbol) => _painterOf(
      tester,
    ).layout.firstWhere((t) => t.tile.symbol == symbol).tile;

    /// 畫面拿到的資料的即時模式
    HeatmapLiveMode? liveModeOf(WidgetTester tester) =>
        tester.widget<HeatmapView>(find.byType(HeatmapView)).data.liveMode;

    testWidgets('盤中登記目前市場的指數＋熱力圖的個股；切到上櫃換成上櫃的，不含另一個市場的指數', (tester) async {
      final page = await pumpLive(
        tester,
        at: monday(10, 30),
        live: const MarketLiveIndices(),
      );
      final twseView = page.container.read(heatmapLiveProvider);
      expect(twseView.mode, HeatmapLiveMode.intraday, reason: '前提');
      expect(twseView.stockRegistrations, hasLength(5), reason: '前提');
      expect(page.center.registered.values.single, [
        LiveQuoteRegistration(
          symbol: LiveQuoteParams.indexSymbolOf(MarketCode.twse),
          market: MarketCode.twse,
        ),
        ...twseView.stockRegistrations,
      ]);

      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      final tpexView = page.container.read(heatmapLiveProvider);
      expect(tpexView.stockRegistrations.map((r) => r.symbol), [
        '9951',
        '9952',
        '9961',
      ]);
      expect(page.center.registered.values.single, [
        LiveQuoteRegistration(
          symbol: LiveQuoteParams.indexSymbolOf(MarketCode.tpex),
          market: MarketCode.tpex,
        ),
        ...tpexView.stockRegistrations,
      ]);
      expect(
        page.center.symbols,
        isNot(contains(LiveQuoteParams.indexSymbolOf(MarketCode.twse))),
      );
    });

    testWidgets('🚨 登記的清單就是 heatmapRegistrationsProvider 的值；App 看不見、畫面停止排程後，'
        '拿到收盤報價的移出 → 登記跟著換', (tester) async {
      final page = await pumpLive(
        tester,
        at: monday(13, 40),
        markets: {MarketCode.twse: twse30()},
        live: const MarketLiveIndices(),
      );
      final first = page.container.read(heatmapRegistrationsProvider);
      expect(first, hasLength(1 + 30), reason: '前提：指數＋還沒有收盤報價的 30 檔');
      expect(page.center.registered.values.single, first);

      void setLifecycle(AppLifecycleState state) =>
          tester.binding.handleAppLifecycleStateChanged(state);
      addTearDown(() => setLifecycle(AppLifecycleState.resumed));
      setLifecycle(AppLifecycleState.hidden);
      await tester.pump(); // 切到 hidden 之前已經排好的那一幀
      expect(tester.binding.framesEnabled, isFalse, reason: '前提：看不見時不畫幀');

      // 前 10 檔拿到收盤報價 → 熱力圖只登記剩下的 20 檔
      final got = [for (final r in first.skip(1).take(10)) r.symbol];
      page.center.publish(
        LiveQuoteState(
          entries: {for (final s in got) s: quote(s, 101, closing: true)},
          latestResponseHadToday: true,
        ),
      );
      // 不帶時間的 pump() 不前進時間，provider 排程重算用的計時器不會跑
      await tester.pump(const Duration(milliseconds: 1));
      final next = page.center.registered.values.single;
      expect(
        {for (final r in next) r.symbol}.intersection(got.toSet()),
        isEmpty,
        reason: '已有收盤報價的不再登記',
      );
      expect(next, hasLength(1 + 20));
      expect(next, page.container.read(heatmapRegistrationsProvider));

      // 回到可見才拆得掉樹（看不見時不畫幀）
      setLifecycle(AppLifecycleState.resumed);
      await tester.pump();
    });

    testWidgets('盤中：狀態行顯示報價狀態（最多兩行、省略號）；指數列不顯示自己的狀態、右側不寫「M/D 收盤」', (
      tester,
    ) async {
      await pumpLive(
        tester,
        at: monday(10, 30),
        state: LiveQuoteState(
          entries: {'9901': quote('9901', 101.83)},
          fetchedAt: {'9901': monday(10, 30)},
          latestResponseHadToday: true,
        ),
        live: indexLive,
      );
      expect(statusLine(tester).data, '報價時間 10:30:05');
      expect(statusLine(tester).maxLines, 2);
      expect(statusLine(tester).overflow, TextOverflow.ellipsis);
      expect(find.text('指數自己的狀態'), findsNothing);
      expect(find.text('11/6 收盤'), findsNothing);
      expect(liveModeOf(tester), HeatmapLiveMode.intraday);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('🚨 盤中狀態行還沒有內容時先佔一行：第一輪報價回來、狀態行出現時，'
          '圖區的位置與大小不變（格子不重排；系統字級 $scale）', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final page = await pumpLive(
          tester,
          at: monday(10, 30),
          live: indexLive,
        );
        expect(
          find.byKey(MarketHeatmapScreen.statusLineKey),
          findsNothing,
          reason: '前提：還沒有狀態',
        );
        final waiting = tester.getRect(find.byType(HeatmapView));

        page.center.publish(
          LiveQuoteState(
            entries: {'9901': quote('9901', 101.83)},
            fetchedAt: {'9901': monday(10, 30)},
            latestResponseHadToday: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          statusLine(tester).data,
          '報價時間 10:30:05',
          reason: '前提：狀態行出現（一行）',
        );
        expect(tester.getRect(find.byType(HeatmapView)), waiting);

        // 切到上櫃：上櫃的檔還沒有報價，狀態行又沒有內容；圖區不動
        await tester.tap(find.text('上櫃'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(MarketHeatmapScreen.statusLineKey),
          findsNothing,
          reason: '前提：上櫃還沒有狀態',
        );
        expect(tester.getRect(find.byType(HeatmapView)), waiting);
      });
    }

    testWidgets('不在即時時段、沒有狀態：不留空行（圖區比即時時段還沒有狀態時高）', (tester) async {
      await pumpLive(
        tester,
        at: monday(8, 30),
        live: const MarketLiveIndices(),
      );
      expect(
        find.byKey(MarketHeatmapScreen.statusLineKey),
        findsNothing,
        reason: '前提：開盤前沒有狀態',
      );
      final idle = tester.getRect(find.byType(HeatmapView));

      await pumpLive(tester, at: monday(10, 30), live: indexLive);
      expect(
        find.byKey(MarketHeatmapScreen.statusLineKey),
        findsNothing,
        reason: '前提：盤中還沒有狀態',
      );
      final waiting = tester.getRect(find.byType(HeatmapView));
      expect(idle.bottom, waiting.bottom, reason: '前提：圖區的底部相同');
      expect(idle.top, lessThan(waiting.top));
    });

    testWidgets('盤中中心還沒有任何狀態：不顯示狀態行（指數的狀態也不顯示）', (tester) async {
      await pumpLive(tester, at: monday(9, 0, 5), live: indexLive);
      expect(find.byKey(MarketHeatmapScreen.statusLineKey), findsNothing);
      expect(find.text('指數自己的狀態'), findsNothing);
      expect(find.text('11/6 收盤'), findsNothing);
    });

    testWidgets('收盤後：「今日收盤 3／30 檔・待盤後更新」；指數已是今天也不寫「指數為 M/D 收盤」', (
      tester,
    ) async {
      await pumpLive(
        tester,
        at: monday(13, 40),
        markets: {MarketCode.twse: twse30()},
        state: LiveQuoteState(
          entries: {
            for (final s in ['Z00', 'Z01', 'Z10'])
              s: quote(s, 101, closing: true),
          },
          latestResponseHadToday: true,
        ),
        overview: MarketOverviewState(
          indices: [
            TwseMarketIndex(
              date: today,
              name: MarketIndexNames.taiex,
              close: 22300,
              change: 149.7,
              changePercent: 0.68,
            ),
          ],
        ),
        live: const MarketLiveIndices(),
      );
      expect(statusLine(tester).data, '今日收盤 3／30 檔・待盤後更新');
      expect(find.textContaining('指數為'), findsNothing);
      expect(find.text('11/6 收盤'), findsNothing);
    });

    for (final (locale, english, expected) in [
      ('zh-TW', false, '今日收盤 3／30 檔・2 檔收盤沒撮合・待盤後更新'),
      (
        'en',
        true,
        "Today's close 3/30 · 2 no closing match · after-hours data pending",
      ),
    ]) {
      testWidgets('🚨 收盤後有收盤沒撮合的檔（$locale）：進度另寫檔數', (tester) async {
        await pumpLive(
          tester,
          at: monday(13, 40),
          markets: {MarketCode.twse: twse30()},
          state: LiveQuoteState(
            entries: {
              for (final s in ['Z00', 'Z01', 'Z10'])
                s: quote(s, 101, closing: true),
            },
            latestResponseHadToday: true,
            // Z01 放棄後又拿到收盤報價：算已收盤
            closingGivenUpAt: {
              for (final s in ['Z01', 'Z02', 'Z29']) s: monday(13, 35),
            },
          ),
          live: const MarketLiveIndices(),
          english: english,
        );
        expect(statusLine(tester).data, expected);
        expect(statusLine(tester).maxLines, 2);
        expect(statusLine(tester).overflow, TextOverflow.ellipsis);
      });
    }

    testWidgets('收盤後限流＋收盤沒撮合：限流文字在前、進度在後', (tester) async {
      await pumpLive(
        tester,
        at: monday(13, 40),
        markets: {MarketCode.twse: twse30()},
        state: LiveQuoteState(
          entries: {
            for (final s in ['Z00', 'Z01', 'Z10'])
              s: quote(s, 101, closing: true),
          },
          rateLimitedUntil: monday(13, 41),
          latestResponseHadToday: true,
          closingGivenUpAt: {
            for (final s in ['Z02', 'Z29']) s: monday(13, 35),
          },
        ),
        live: const MarketLiveIndices(),
      );
      expect(
        statusLine(tester).data,
        '報價暫停（證交所限流，13:41 再試）・今日收盤 3／30 檔・2 檔收盤沒撮合・待盤後更新',
      );
    });

    testWidgets('收盤後限流：限流文字在前、進度在後', (tester) async {
      await pumpLive(
        tester,
        at: monday(13, 40),
        markets: {MarketCode.twse: twse30()},
        state: LiveQuoteState(
          entries: {
            for (final s in ['Z00', 'Z01', 'Z10'])
              s: quote(s, 101, closing: true),
          },
          rateLimitedUntil: monday(13, 41),
          latestResponseHadToday: true,
        ),
        live: const MarketLiveIndices(),
      );
      expect(statusLine(tester).data, '報價暫停（證交所限流，13:41 再試）・今日收盤 3／30 檔・待盤後更新');
    });

    for (final (desc, at) in [
      ('盤中', monday(10, 30)),
      ('收盤後', monday(13, 40)),
    ]) {
      testWidgets('停市日退回（$desc）：「證交所今天尚無報價」只出現一次、沒有進度、保留右側「M/D 收盤」', (
        tester,
      ) async {
        final page = await pumpLive(
          tester,
          at: at,
          state: const LiveQuoteState(latestResponseHadToday: false),
        );
        // 前提：指數自己的狀態也是「證交所今天尚無報價」（不 override 掉）
        expect(
          page.container
              .read(marketLiveIndicesProvider)
              .byMarket[MarketCode.twse]
              ?.statusText,
          '證交所今天尚無報價',
        );
        expect(page.container.read(heatmapLiveProvider).mode, isNotNull);
        expect(find.text('證交所今天尚無報價'), findsOneWidget);
        expect(statusLine(tester).data, '證交所今天尚無報價');
        expect(find.textContaining('今日收盤'), findsNothing);
        expect(find.text('11/6 收盤'), findsOneWidget);
        expect(liveModeOf(tester), isNull);
      });
    }

    testWidgets('停市日退回、總覽已有今天的指數（14:00 後）：不寫「指數為 M/D 收盤」', (tester) async {
      await pumpLive(
        tester,
        at: monday(14, 30),
        state: const LiveQuoteState(latestResponseHadToday: false),
        overview: MarketOverviewState(
          indices: [
            TwseMarketIndex(
              date: today,
              name: MarketIndexNames.taiex,
              close: 22300,
              change: 149.7,
              changePercent: 0.68,
            ),
          ],
        ),
      );
      expect(statusLine(tester).data, '證交所今天尚無報價');
      expect(find.textContaining('指數為'), findsNothing);
      expect(find.text('11/6 收盤'), findsOneWidget);
    });

    testWidgets('不需要即時（開盤前）：沒有狀態行、右側有「M/D 收盤」', (tester) async {
      await pumpLive(
        tester,
        at: monday(8, 30),
        state: const LiveQuoteState(latestResponseHadToday: false),
        live: const MarketLiveIndices(),
      );
      expect(find.byKey(MarketHeatmapScreen.statusLineKey), findsNothing);
      expect(find.text('11/6 收盤'), findsOneWidget);
      expect(liveModeOf(tester), isNull);
    });

    testWidgets('不需要即時時指數列顯示指數自己的狀態', (tester) async {
      await pumpLive(tester, at: monday(8, 30), live: indexLive);
      expect(statusLine(tester).data, '指數自己的狀態');
      expect(find.text('11/6 收盤'), findsOneWidget);
    });

    testWidgets('跨過 13:30：資料的模式跟著換，盤中上色的格子改成尚未取得收盤報價、'
        '拿到收盤報價的上色', (tester) async {
      final page = await pumpLive(
        tester,
        at: monday(13, 29),
        state: LiveQuoteState(
          entries: {'9901': quote('9901', 101)},
          fetchedAt: {'9901': monday(13, 29)},
          latestResponseHadToday: true,
        ),
        live: const MarketLiveIndices(),
      );
      final before = _painterOf(tester);
      expect(liveModeOf(tester), HeatmapLiveMode.intraday);
      expect(tileOf(tester, '9901').change, const TileChangeValue(1));

      page.clock.value = monday(13, 31);
      page.center.publish(
        LiveQuoteState(
          entries: {
            '9901': quote('9901', 101),
            '9911': quote('9911', 102, closing: true),
          },
          fetchedAt: {'9901': monday(13, 29), '9911': monday(13, 31)},
          latestResponseHadToday: true,
        ),
      );
      page.container.invalidate(liveQuoteBoundaryProvider);
      await tester.pump();
      final after = _painterOf(tester);
      expect(liveModeOf(tester), HeatmapLiveMode.afterClose);
      expect(after.shouldRepaint(before), isTrue);
      expect(
        tileOf(tester, '9901').change,
        const TileChangeHollow(HollowReason.noClosingQuote),
      );
      expect(tileOf(tester, '9911').change, const TileChangeValue(2));
    });

    testWidgets('離開熱力圖再回來：仍在原市場，格子先維持離開前的顏色', (tester) async {
      final router = testRouter(initial: AppRoutes.marketHeatmap);
      final page = await pumpLive(
        tester,
        at: monday(10, 30),
        live: const MarketLiveIndices(),
        router: router,
      );
      // 用上櫃：預設是上市，選取被重設時看得出來
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();

      page.clock.value = monday(10, 30, 15);
      page.center.publish(
        LiveQuoteState(
          entries: {'9951': quote('9951', 103)},
          fetchedAt: {'9951': monday(10, 30, 15)},
          latestResponseHadToday: true,
        ),
      );
      await tester.pump();
      expect(tileOf(tester, '9951').change, const TileChangeValue(3));

      // 推一個不透明頁面；期間報價中心照常發布，沒有 9951 的新報價
      page.clock.value = monday(10, 31);
      router.push('/other');
      await tester.pumpAndSettle();
      expect(find.text('other'), findsOneWidget);
      page.clock.value = monday(10, 31, 15);
      page.center.publish(
        LiveQuoteState(
          entries: {'9951': quote('9951', 103), '9952': quote('9952', 99)},
          fetchedAt: {'9951': monday(10, 30, 15), '9952': monday(10, 31, 15)},
          latestResponseHadToday: true,
        ),
      );
      await tester.pump();

      page.clock.value = monday(10, 31, 30);
      router.pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            )
            .selected,
        {MarketCode.tpex},
      );
      expect(tileOf(tester, '9951').change, const TileChangeValue(3));

      // 回來後報價中心再發布一次、還沒重抓 9951：仍是離開前的顏色（開始登記
      // 的時刻沒有因為頁面被蓋住而重記）
      page.clock.value = monday(10, 31, 40);
      page.center.publish(
        LiveQuoteState(
          entries: {'9951': quote('9951', 103), '9952': quote('9952', 98)},
          fetchedAt: {'9951': monday(10, 30, 15), '9952': monday(10, 31, 40)},
          latestResponseHadToday: true,
        ),
      );
      await tester.pump();
      expect(tileOf(tester, '9952').change, const TileChangeValue(-2));
      expect(tileOf(tester, '9951').change, const TileChangeValue(3));
    });
  });
}

/// 記錄登記、不發請求的報價中心；[publish] 換狀態（模擬一輪報價回來）
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter([this._initial = const LiveQuoteState()]);
  final LiveQuoteState _initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => _initial;

  void publish(LiveQuoteState next) => state = next;

  /// 所有畫面登記的代號
  Set<String> get symbols => {
    for (final entries in registered.values)
      for (final r in entries) r.symbol,
  };

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}

class _FakeSettings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
}

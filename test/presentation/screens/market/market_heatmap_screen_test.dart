import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/app_visibility_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
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

HeatmapTile _tile(String symbol, String name, double cap, double pct) =>
    HeatmapTile(
      symbol: symbol,
      name: name,
      close: 100,
      marketCap: cap,
      change: TileChangeValue(pct),
      isMine: false,
    );

HeatmapTile _hollowTile(String symbol, String name, double cap) => HeatmapTile(
  symbol: symbol,
  name: name,
  close: 100,
  marketCap: cap,
  change: const TileChangeHollow(HollowReason.noChangeData),
  isMine: false,
);

HeatmapIndustry _industry(String? name, List<HeatmapTile> tiles, double? pct) =>
    HeatmapIndustry(
      name: name,
      marketCap: tiles.fold(0.0, (s, t) => s + t.marketCap),
      weightedChangePercent: pct,
      tiles: tiles,
    );

/// 產業刻意不照市值排列：選單要自己排
HeatmapMarketData _twse({int excluded = 0, bool withShipping = true}) =>
    HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: DateTime(2026, 10, 7),
      excludedForShares: excluded,
      industries: [
        if (withShipping)
          _industry('航運業', [_hollowTile('9931', '測試航運', 2e11)], null),
        _industry('半導體業', [
          _tile('9901', '測試甲', 8e11, 1.8),
          _tile('9902', '測試乙', 2e11, 1.8),
        ], 1.8),
        _industry('其他電子零組件業', [
          _tile('9911', '測試丁', 5e11, -0.4),
          _tile('9912', '測試平', 1e11, 0),
          // 四捨五入到 0.00% 的漲跌：顏色是平盤，描述也要唸平盤
          _tile('9913', '測試微', 1e11, 0.004),
        ], -0.4),
      ],
    );

final _tpex = HeatmapMarketData(
  market: MarketCode.tpex,
  dataDate: DateTime(2026, 10, 6),
  excludedForShares: 0,
  industries: [
    _industry('生技醫療業', [_tile('9951', '測試戊', 1e11, -2)], -2),
  ],
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
];

Finder get _painterFinder => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is HeatmapPainter,
);

HeatmapPainter _painterOf(WidgetTester tester) =>
    tester.widget<CustomPaint>(_painterFinder).painter! as HeatmapPainter;

Offset _tileCenter(WidgetTester tester, String symbol) {
  final tile = _painterOf(
    tester,
  ).layout.expand((l) => l.tiles).firstWhere((t) => t.tile.symbol == symbol);
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

  Future<void> openIndustryMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('產業'));
    await tester.pumpAndSettle();
  }

  group('狀態', () {
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
      expect(find.text('產業漲跌為市值加權'), findsOneWidget);

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
          '產業漲跌為市值加權',
        ])
          tester.getTopLeft(find.text(text).first).dy,
      };
      expect(tops, hasLength(1));
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

  group('放大', () {
    List<String?> menuTexts(WidgetTester tester) => [
      for (final item in tester.widgetList<PopupMenuItem<Object>>(
        find.byWidgetPredicate((w) => w is PopupMenuItem<Object>),
      ))
        (item.child! as Text).data,
    ];

    testWidgets('產業選單依市值排序並帶漲跌；選了就放大、標題換成「← 全市場」', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      expect(find.text('大盤熱力圖'), findsOneWidget);
      await openIndustryMenu(tester);
      expect(menuTexts(tester), [
        '全市場',
        '半導體業 +1.80%',
        '其他電子零組件業 -0.40%',
        '航運業 —',
      ]);
      await tester.tap(find.text('其他電子零組件業 -0.40%'));
      await tester.pumpAndSettle();
      final painter = _painterOf(tester);
      expect(painter.zoomed, isTrue);
      expect(painter.layout.map((l) => l.industry.name), ['其他電子零組件業']);
      expect(find.text('← 全市場'), findsOneWidget);
      expect(find.text('大盤熱力圖'), findsNothing);

      await openIndustryMenu(tester);
      await tester.tap(find.text('全市場').last);
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
      expect(find.text('大盤熱力圖'), findsOneWidget);
    });

    testWidgets('點產業標題放大、點「← 全市場」回來', (tester) async {
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      final header = _painterOf(
        tester,
      ).layout.firstWhere((l) => l.industry.name == '半導體業').header!;
      await tester.tapAt(
        tester.getTopLeft(find.byType(HeatmapView)) +
            Offset(
              header.left + header.width / 2,
              header.top + header.height / 2,
            ),
      );
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isTrue);
      await tester.tap(find.text('← 全市場'));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
    });

    testWidgets('窄螢幕放大狀態點得到「← 全市場」', (tester) async {
      final router = testRouter();
      await pumpRouter(
        tester,
        router,
        _loaded({MarketCode.twse: _twse()}),
        size: const Size(360, 800),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await openIndustryMenu(tester);
      await tester.tap(find.text('其他電子零組件業 -0.40%'));
      await tester.pumpAndSettle();
      final back = find.widgetWithText(TextButton, '← 全市場');
      expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
    });

    testWidgets('英文窄螢幕放大狀態：「← All industries」一行、在標題列內、點得到', (tester) async {
      viewport(tester, size: const Size(360, 800));
      final router = testRouter();
      final fake = _FakeHeatmap(_loaded({MarketCode.twse: _twse()}));
      await tester.pumpWidget(
        buildProviderTestApp(
          const SizedBox(),
          overrides: _overrides(fake),
          router: router,
          enTranslations: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Industry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('半導體業 +1.80%'));
      await tester.pumpAndSettle();
      final back = find.widgetWithText(TextButton, '← All industries');
      expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
      final label = tester.getRect(find.text('← All industries'));
      final appBar = tester.getRect(find.byType(AppBar));
      // 一行：高度不超過一行字（測試字型行高＝字級）
      final style = tester.widget<Text>(find.text('← All industries'));
      expect(style.maxLines, 1);
      expect(label.top, greaterThanOrEqualTo(appBar.top));
      expect(label.bottom, lessThanOrEqualTo(appBar.bottom));
      expect(label.height, lessThanOrEqualTo(24));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
    });

    testWidgets('切換市場清掉放大', (tester) async {
      await pump(
        tester,
        _loaded({MarketCode.twse: _twse(), MarketCode.tpex: _tpex}),
      );
      await openIndustryMenu(tester);
      await tester.tap(find.text('半導體業 +1.80%'));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isTrue);
      await tester.tap(find.text('上櫃'));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
      await tester.tap(find.text('上市'));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
      expect(find.text('大盤熱力圖'), findsOneWidget);
    });

    testWidgets('放大中的產業在重讀後消失時回到全市場', (tester) async {
      final fake = await pump(tester, _loaded({MarketCode.twse: _twse()}));
      await openIndustryMenu(tester);
      await tester.tap(find.text('航運業 —'));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isTrue);
      fake.state = _loaded({MarketCode.twse: _twse(withShipping: false)});
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
      expect(_painterOf(tester).layout, hasLength(2));
      expect(find.text('大盤熱力圖'), findsOneWidget);

      // 之後又出現：維持全市場，不自己放大回去
      fake.state = _loaded({MarketCode.twse: _twse()});
      await tester.pumpAndSettle();
      expect(_painterOf(tester).zoomed, isFalse);
      expect(_painterOf(tester).layout, hasLength(3));
    });

    testWidgets('產業選單市值相同時依產業名排序', (tester) async {
      await pump(
        tester,
        _loaded({
          MarketCode.twse: HeatmapMarketData(
            market: MarketCode.twse,
            dataDate: DateTime(2026, 10, 7),
            excludedForShares: 0,
            industries: [
              _industry('甲業', [_tile('9971', '測試甲甲', 1e11, 1)], 1),
              _industry('乙業', [_tile('9972', '測試乙乙', 1e11, 1)], 1),
            ],
          ),
        }),
      );
      await openIndustryMenu(tester);
      // 字串比較：乙（U+4E59）在甲（U+7532）之前
      expect(menuTexts(tester), ['全市場', '乙業 +1.00%', '甲業 +1.00%']);
    });
  });

  group('無障礙描述', () {
    testWidgets('全市場唸產業、放大後唸格子', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _loaded({MarketCode.twse: _twse()}));
      expect(find.semantics.byLabel('半導體業，市值加權上漲 1.80%，共 2 檔'), findsOneWidget);
      expect(
        find.semantics.byLabel('其他電子零組件業，市值加權下跌 0.40%，共 3 檔'),
        findsOneWidget,
      );
      expect(find.semantics.byLabel('航運業，無漲跌資料，共 1 檔'), findsOneWidget);

      await openIndustryMenu(tester);
      await tester.tap(find.text('其他電子零組件業 -0.40%'));
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('測試丁，下跌 0.40%'), findsOneWidget);
      expect(find.semantics.byLabel('測試平，平盤 0.00%'), findsOneWidget);
      expect(find.semantics.byLabel('測試微，平盤 0.00%'), findsOneWidget);

      await openIndustryMenu(tester);
      await tester.tap(find.text('航運業 —'));
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('測試航運，無漲跌資料'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('產業別空白時寫「未分類」', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _loaded({
          MarketCode.twse: HeatmapMarketData(
            market: MarketCode.twse,
            dataDate: DateTime(2026, 10, 7),
            excludedForShares: 0,
            industries: [
              _industry(null, [_tile('9961', '測試己', 1e11, 0.5)], 0.5),
            ],
          ),
        }),
      );
      expect(find.semantics.byLabel('未分類，市值加權上漲 0.50%，共 1 檔'), findsOneWidget);
      expect(_painterOf(tester).labels.uncategorized, '未分類');
      await openIndustryMenu(tester);
      expect(find.text('未分類 +0.50%'), findsOneWidget);
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
    expect(
      find.semantics.byLabel('半導體業, cap-weighted up 1.80%, 2 stocks'),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel('航運業, no change data, 1 stocks'),
      findsOneWidget,
    );

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

    await tester.tap(find.byTooltip('Industry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('航運業 —'));
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('測試航運: No change data'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('重建時沿用同一份 labels（painter 不因此重畫）', (tester) async {
    final fake = await pump(tester, _loaded({MarketCode.twse: _twse()}));
    final before = _painterOf(tester).labels;
    fake.state = _loaded({MarketCode.twse: _twse(excluded: 1)});
    await tester.pumpAndSettle();
    expect(identical(_painterOf(tester).labels, before), isTrue);
  });

  testWidgets('登記兩個指數的即時報價', (tester) async {
    viewport(tester);
    final center = _LiveCenter();
    final fake = _FakeHeatmap(_loaded({MarketCode.twse: _twse()}));
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: _overrides(fake),
        zhTranslations: true,
        liveQuoteCenter: () => center,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      {
        for (final entries in center.registered.values)
          for (final r in entries) r.symbol,
      },
      {'t00', 'o00'},
    );
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
}

/// 記錄登記、不發請求的報價中心
class _LiveCenter extends LiveQuoteCenter {
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => const LiveQuoteState();

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}

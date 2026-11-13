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
import 'package:daredevil/domain/services/heatmap/heatmap_grouping.dart';
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
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  close: 100,
  marketCap: cap,
  baseCap: cap * 100 / (100 + pct),
  change: TileChangeValue(pct),
  isMine: mine,
);

HeatmapTile _hollowTile(String symbol, String name, double cap) => HeatmapTile(
  symbol: symbol,
  name: name,
  close: 100,
  marketCap: cap,
  baseCap: 0,
  change: const TileChangeHollow(HollowReason.noChangeData),
  isMine: false,
);

HeatmapIndustry _industry(
  String? name,
  List<HeatmapTile> tiles,
  double? pct, {
  double? coverage,
}) => HeatmapIndustry(
  name: name,
  marketCap: tiles.fold(0.0, (s, t) => s + t.marketCap),
  weightedChangePercent: pct,
  tiles: tiles,
  liveCoverage: coverage,
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

/// 大、中產業加兩個放不下標題列的小產業（其中一檔自選）：小產業合成一塊
/// （只有一個大產業時，合併塊會被擠成點不到的細條）
HeatmapMarketData _withSmallIndustries() => HeatmapMarketData(
  market: MarketCode.twse,
  dataDate: DateTime(2026, 10, 7),
  excludedForShares: 0,
  industries: [
    _industry('大業', [_tile('9901', '測試甲', 1e12, 1)], 1),
    _industry('中甲業', [_tile('9911', '測試乙', 3e11, 1)], 1),
    _industry('中乙業', [_tile('9921', '測試丙', 2e11, 1)], 1),
    _industry('中丙業', [_tile('9931', '測試丁', 1e11, 1)], 1),
    _industry('小甲業', [_tile('9961', '測試己', 5e9, 1, mine: true)], 1),
    _industry('小乙業', [_tile('9971', '測試庚', 5e9, 1)], 1),
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
      expect(find.text('雙線框＝含自選或持股'), findsOneWidget);
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
          '雙線框＝含自選或持股',
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

    HeatmapMarketData folded(List<HeatmapTile> tiles) => HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: DateTime(2026, 10, 7),
      excludedForShares: 0,
      industries: [_industry('測試業', tiles, 1)],
    );

    testWidgets('放大後合併塊的描述寫檔數、加權漲跌與漲跌家數', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _loaded({
          // 一檔大的、四檔中型、40 檔太小（只有大的加合併塊時，合併塊會被
          // 擠成細長條）
          MarketCode.twse: folded([
            _tile('9901', '測試甲', 1e12, 1),
            for (var i = 0; i < 4; i++) _tile('${9902 + i}', '中$i', 1e11, 1),
            for (var i = 0; i < 40; i++) _tile('${9940 + i}', '小$i', 1e9, 1),
          ]),
        }),
      );
      await openIndustryMenu(tester);
      await tester.tap(find.text('測試業 +1.00%'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('其他 40 檔，市值加權上漲 1.00%，漲 40、跌 0、平 0'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('合併塊有空心成員時，描述補上沒有今日漲跌的檔數', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _loaded({
          MarketCode.twse: folded([
            _tile('9901', '測試甲', 1e12, 1),
            for (var i = 0; i < 4; i++) _tile('${9902 + i}', '中$i', 1e11, 1),
            for (var i = 0; i < 40; i++) _tile('${9940 + i}', '小$i', 1e9, 1),
            _hollowTile('9939', '小空', 1e9),
          ]),
        }),
      );
      await openIndustryMenu(tester);
      await tester.tap(find.text('測試業 +1.00%'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('其他 41 檔，市值加權上漲 1.00%，漲 40、跌 0、平 0、沒有今日漲跌 1'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('合併塊有自選或持股時，描述補上含幾檔', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _loaded({
          MarketCode.twse: folded([
            _tile('9901', '測試甲', 1e12, 1),
            for (var i = 0; i < 4; i++) _tile('${9902 + i}', '中$i', 1e11, 1),
            for (var i = 0; i < 40; i++)
              _tile('${9940 + i}', '小$i', 1e9, 1, mine: i < 2),
          ]),
        }),
      );
      await openIndustryMenu(tester);
      await tester.tap(find.text('測試業 +1.00%'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('其他 40 檔，市值加權上漲 1.00%，漲 40、跌 0、平 0，含自選或持股 2 檔'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('小產業合併塊的描述寫產業數、檔數、加權漲跌、家數與含幾檔自選', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _loaded({MarketCode.twse: _withSmallIndustries()}));
      expect(
        find.semantics.byLabel(
          '其他 2 個產業，共 2 檔，市值加權上漲 1.00%，漲 2、跌 0、平 0，含自選或持股 1 檔',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('小產業合併塊全是空心時，描述寫個股檔數（不是產業數）', (tester) async {
      final handle = tester.ensureSemantics();
      final data = _withSmallIndustries();
      await pump(
        tester,
        _loaded({
          MarketCode.twse: HeatmapMarketData(
            market: data.market,
            dataDate: data.dataDate,
            excludedForShares: 0,
            industries: [
              ...data.industries.take(4),
              _industry('小甲業', [
                _hollowTile('9961', '測試己', 2.5e9),
                _hollowTile('9962', '測試辛', 2.5e9),
              ], null),
              _industry('小乙業', [
                _hollowTile('9971', '測試庚', 2.5e9),
                _hollowTile('9972', '測試壬', 2.5e9),
              ], null),
            ],
          ),
        }),
      );
      expect(find.semantics.byLabel('其他 2 個產業，無漲跌資料，共 4 檔'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('整個產業都合併時，描述用產業名稱', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _loaded({
          MarketCode.twse: folded([
            for (var i = 0; i < 1000; i++) _tile('${i + 1000}', '小$i', 1, 1),
          ]),
        }),
      );
      await openIndustryMenu(tester);
      await tester.tap(find.text('測試業 +1.00%'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('測試業，市值加權上漲 1.00%，漲 1000、跌 0、平 0'),
        findsOneWidget,
      );
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
      find.semantics.byLabel('航運業: No change data, 1 stocks'),
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

  testWidgets('點「其他 N 檔」拉出成員清單，點一檔進個股頁', (tester) async {
    final router = testRouter(initial: AppRoutes.marketHeatmap);
    await pumpRouter(
      tester,
      router,
      _loaded({
        MarketCode.twse: HeatmapMarketData(
          market: MarketCode.twse,
          dataDate: DateTime(2026, 10, 7),
          excludedForShares: 0,
          industries: [
            _industry('測試業', [
              _tile('9901', '測試甲', 1e12, 1),
              for (var i = 0; i < 4; i++) _tile('${9902 + i}', '中$i', 1e11, 1),
              // 「小0」漲最多：清單依漲跌幅排序，它排第一列
              for (var i = 0; i < 40; i++)
                _tile('${9940 + i}', '小$i', 1e9, i == 0 ? 9.9 : 1),
            ], 1),
          ],
        ),
      }),
    );
    final other = _painterOf(tester).layout.single.other!;
    expect(other.members, hasLength(40), reason: '前提：40 檔被合併');
    final p = other.paint;
    await tester.tapAt(
      tester.getTopLeft(find.byType(HeatmapView)) +
          Offset(p.left + p.width / 2, p.top + p.height / 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('測試業 · 其他 40 檔'), findsOneWidget);
    await tester.tap(find.text('小0'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/stock/9940');
  });

  testWidgets('點「其他 N 個產業」拉出產業清單，點一個放大該產業', (tester) async {
    await pump(tester, _loaded({MarketCode.twse: _withSmallIndustries()}));
    final group = _painterOf(tester).smallIndustries!;
    expect(group.members, hasLength(2), reason: '前提：兩個小產業合併');
    expect(group.interactive, isTrue, reason: '前提：點得到');
    final p = group.paint;
    await tester.tapAt(
      tester.getTopLeft(find.byType(HeatmapView)) +
          Offset(p.left + p.width / 2, p.top + p.height / 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('其他 2 個產業'), findsOneWidget);
    await tester.tap(find.text('小乙業'));
    await tester.pumpAndSettle();
    expect(find.text('其他 2 個產業'), findsNothing, reason: '清單收起');
    expect(_painterOf(tester).zoomed, isTrue);
    expect(_painterOf(tester).layout.single.industry.key, '小乙業');
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

    /// 上市三個產業、上櫃兩個產業，資料日上週五
    HeatmapMarketData twse() => HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: friday,
      excludedForShares: 0,
      industries: [
        _industry('半導體業', [
          _tile('9901', '測試甲', 8e11, -0.8),
          _tile('9902', '測試乙', 2e11, -0.8),
        ], -0.8),
        _industry('其他電子零組件業', [
          _tile('9911', '測試丁', 5e11, -0.4),
          _tile('9912', '測試平', 1e11, 0),
        ], -0.33),
        _industry('航運業', [_tile('9931', '測試航運', 2e11, 0.5)], 0.5),
      ],
    );

    HeatmapMarketData tpex() => HeatmapMarketData(
      market: MarketCode.tpex,
      dataDate: friday,
      excludedForShares: 0,
      industries: [
        _industry('生技醫療業', [
          _tile('9951', '測試戊', 3e11, -2),
          _tile('9952', '測試己', 1e11, -2),
        ], -2),
        _industry('觀光餐旅業', [_tile('9961', '測試庚', 1e11, 1)], 1),
      ],
    );

    /// 上市 120 檔（收盤後的進度用；檔數超過 99xx，虛構代號以英文字母開頭）
    HeatmapMarketData twse120() => HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: friday,
      excludedForShares: 0,
      industries: [
        for (var g = 0; g < 3; g++)
          _industry('測試$g業', [
            for (var i = 0; i < 40; i++)
              _tile('Z$g${i.toString().padLeft(2, '0')}', '測$g$i', 1e9, 1),
          ], 1),
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

    HeatmapTile tileOf(WidgetTester tester, String symbol) => _painterOf(tester)
        .layout
        .expand((l) => l.tiles)
        .firstWhere((t) => t.tile.symbol == symbol)
        .tile;

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
      expect(_painterOf(tester).liveMode, HeatmapLiveMode.intraday);
    });

    testWidgets('盤中中心還沒有任何狀態：不顯示狀態行（指數的狀態也不顯示）', (tester) async {
      await pumpLive(tester, at: monday(9, 0, 5), live: indexLive);
      expect(find.byKey(MarketHeatmapScreen.statusLineKey), findsNothing);
      expect(find.text('指數自己的狀態'), findsNothing);
      expect(find.text('11/6 收盤'), findsNothing);
    });

    testWidgets('收盤後：「今日收盤 3／120 檔・待盤後更新」；指數已是今天也不寫「指數為 M/D 收盤」', (
      tester,
    ) async {
      await pumpLive(
        tester,
        at: monday(13, 40),
        markets: {MarketCode.twse: twse120()},
        state: LiveQuoteState(
          entries: {
            for (final s in ['Z000', 'Z001', 'Z100'])
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
      expect(statusLine(tester).data, '今日收盤 3／120 檔・待盤後更新');
      expect(find.textContaining('指數為'), findsNothing);
      expect(find.text('11/6 收盤'), findsNothing);
    });

    for (final (locale, english, expected) in [
      ('zh-TW', false, '今日收盤 3／120 檔・2 檔收盤沒撮合・待盤後更新'),
      (
        'en',
        true,
        "Today's close 3/120 · 2 no closing match · after-hours data pending",
      ),
    ]) {
      testWidgets('🚨 收盤後有收盤沒撮合的檔（$locale）：進度另寫檔數', (tester) async {
        await pumpLive(
          tester,
          at: monday(13, 40),
          markets: {MarketCode.twse: twse120()},
          state: LiveQuoteState(
            entries: {
              for (final s in ['Z000', 'Z001', 'Z100'])
                s: quote(s, 101, closing: true),
            },
            latestResponseHadToday: true,
            // Z001 放棄後又拿到收盤報價：算已收盤
            closingGivenUpAt: {
              for (final s in ['Z001', 'Z002', 'Z239']) s: monday(13, 35),
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
        markets: {MarketCode.twse: twse120()},
        state: LiveQuoteState(
          entries: {
            for (final s in ['Z000', 'Z001', 'Z100'])
              s: quote(s, 101, closing: true),
          },
          rateLimitedUntil: monday(13, 41),
          latestResponseHadToday: true,
          closingGivenUpAt: {
            for (final s in ['Z002', 'Z239']) s: monday(13, 35),
          },
        ),
        live: const MarketLiveIndices(),
      );
      expect(
        statusLine(tester).data,
        '報價暫停（證交所限流，13:41 再試）・今日收盤 3／120 檔・2 檔收盤沒撮合・待盤後更新',
      );
    });

    testWidgets('收盤後限流：限流文字在前、進度在後', (tester) async {
      await pumpLive(
        tester,
        at: monday(13, 40),
        markets: {MarketCode.twse: twse120()},
        state: LiveQuoteState(
          entries: {
            for (final s in ['Z000', 'Z001', 'Z100'])
              s: quote(s, 101, closing: true),
          },
          rateLimitedUntil: monday(13, 41),
          latestResponseHadToday: true,
        ),
        live: const MarketLiveIndices(),
      );
      expect(
        statusLine(tester).data,
        '報價暫停（證交所限流，13:41 再試）・今日收盤 3／120 檔・待盤後更新',
      );
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
        expect(_painterOf(tester).liveMode, isNull);
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
      expect(_painterOf(tester).liveMode, isNull);
    });

    testWidgets('不需要即時時指數列顯示指數自己的狀態', (tester) async {
      await pumpLive(tester, at: monday(8, 30), live: indexLive);
      expect(statusLine(tester).data, '指數自己的狀態');
      expect(find.text('11/6 收盤'), findsOneWidget);
    });

    testWidgets('跨過 13:30：painter 的模式跟著換，標題與描述改成「收盤」、沒有值的產業寫「未收盤」', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
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
      expect(before.liveMode, HeatmapLiveMode.intraday);
      expect(before.labels.coverageSuffix(0.8, before.liveMode!), '・即時 80%');
      expect(
        find.semantics.byLabel('半導體業，市值加權上漲 1.00%，共 2 檔，即時部分占 80%'),
        findsOneWidget,
      );

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
      expect(after.liveMode, HeatmapLiveMode.afterClose);
      expect(after.shouldRepaint(before), isTrue);
      expect(after.labels.coverageSuffix(0.8, after.liveMode!), '・收盤 80%');
      expect(
        after.labels.noChangeLabel(after.liveMode!, allNoClosingMatch: false),
        '未收盤',
      );
      expect(
        after.labels.noChangeLabel(after.liveMode!, allNoClosingMatch: true),
        '收盤沒撮合',
      );
      expect(find.semantics.byLabel('半導體業，未收盤，共 2 檔'), findsOneWidget);
      expect(
        find.semantics.byLabel('其他電子零組件業，市值加權上漲 2.00%，共 2 檔，已收盤部分占 83%'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('離開熱力圖再回來：仍在原市場與放大，格子先維持離開前的顏色', (tester) async {
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
      await openIndustryMenu(tester);
      await tester.tap(find.text('生技醫療業 未即時'));
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
      final painter = _painterOf(tester);
      expect(painter.zoomed, isTrue);
      expect(painter.layout.single.industry.key, '生技醫療業');
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

    group('畫面上的即時比例（固定的即時資料）', () {
      /// 盤中：半導體業 +1.83%（即時 96%）、其他電子零組件業 −0.40%（即時
      /// 0.4%）、航運業全部未即時
      HeatmapMarketData liveData() => HeatmapMarketData(
        market: MarketCode.twse,
        dataDate: friday,
        excludedForShares: 0,
        liveMode: HeatmapLiveMode.intraday,
        industries: [
          _industry(
            '半導體業',
            [_tile('9901', '測試甲', 8e11, 1.83), _tile('9902', '測試乙', 2e11, 0)],
            1.83,
            coverage: 0.96,
          ),
          _industry(
            '其他電子零組件業',
            [_tile('9911', '測試丁', 5e11, -0.4)],
            -0.4,
            coverage: 0.004,
          ),
          _industry(
            '航運業',
            [_hollowTile('9931', '測試航運', 2e11)],
            null,
            coverage: 0,
          ),
        ],
      );

      Future<ProviderContainer> pumpFixed(
        WidgetTester tester,
        HeatmapMarketData data,
      ) async {
        viewport(tester);
        final fake = _FakeHeatmap(_loaded({MarketCode.twse: data}));
        await tester.pumpWidget(
          buildProviderTestApp(
            const MarketHeatmapScreen(),
            overrides: [
              ..._overrides(fake),
              heatmapLiveProvider.overrideWith(
                () => _FixedLive(
                  HeatmapLiveView(data: data, mode: data.liveMode),
                ),
              ),
            ],
            zhTranslations: true,
          ),
        );
        await tester.pumpAndSettle();
        return ProviderScope.containerOf(
          tester.element(find.byType(MarketHeatmapScreen)),
        );
      }

      List<String?> menuTexts(WidgetTester tester) => [
        for (final item in tester.widgetList<PopupMenuItem<Object>>(
          find.byWidgetPredicate((w) => w is PopupMenuItem<Object>),
        ))
          (item.child! as Text).data,
      ];

      testWidgets('產業選單：漲跌接即時比例（0.4% 寫 1%）；全部未即時寫「未即時」', (tester) async {
        await pumpFixed(tester, liveData());
        await openIndustryMenu(tester);
        expect(menuTexts(tester), [
          '全市場',
          '半導體業 +1.83%・即時 96%',
          '其他電子零組件業 -0.40%・即時 1%',
          '航運業 未即時',
        ]);
      });

      testWidgets('無障礙：產業描述接即時比例子句（不念「・」）；未即時的產業說「未即時」', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpFixed(tester, liveData());
        expect(
          find.semantics.byLabel('半導體業，市值加權上漲 1.83%，共 2 檔，即時部分占 96%'),
          findsOneWidget,
        );
        expect(
          find.semantics.byLabel('其他電子零組件業，市值加權下跌 0.40%，共 1 檔，即時部分占 1%'),
          findsOneWidget,
        );
        expect(find.semantics.byLabel('航運業，未即時，共 1 檔'), findsOneWidget);
        handle.dispose();
      });

      /// 一檔大的、四檔中型、40 檔被合併（[hollow] 檔另外空心）
      HeatmapMarketData folded({required bool allHollow}) => HeatmapMarketData(
        market: MarketCode.twse,
        dataDate: friday,
        excludedForShares: 0,
        liveMode: HeatmapLiveMode.intraday,
        industries: [
          _industry(
            '測試業',
            [
              _tile('9901', '測試甲', 1e12, 1),
              for (var i = 0; i < 4; i++) _tile('${9902 + i}', '中$i', 1e11, 1),
              for (var i = 0; i < 40; i++)
                allHollow
                    ? _hollowTile('${9940 + i}', '小$i', 1e9)
                    : _tile('${9940 + i}', '小$i', 1e9, 1),
              if (!allHollow) _hollowTile('9939', '小空', 1e9),
            ],
            1,
            coverage: 0.9,
          ),
        ],
      );

      testWidgets('無障礙：合併塊寫「沒有今日漲跌 N」並接即時比例', (tester) async {
        final handle = tester.ensureSemantics();
        final container = await pumpFixed(tester, folded(allHollow: false));
        container.read(heatmapSelectionProvider.notifier).zoomTo('測試業');
        await tester.pumpAndSettle();
        // 40 檔有值、1 檔空心，市值相同：即時 40/41 ≈ 98%
        expect(
          find.semantics.byLabel(
            '其他 41 檔，市值加權上漲 1.00%，漲 40、跌 0、平 0、沒有今日漲跌 1，即時部分占 98%',
          ),
          findsOneWidget,
        );
        handle.dispose();
      });

      testWidgets('無障礙：盤中整塊空心的合併塊說「未即時」', (tester) async {
        final handle = tester.ensureSemantics();
        final container = await pumpFixed(tester, folded(allHollow: true));
        container.read(heatmapSelectionProvider.notifier).zoomTo('測試業');
        await tester.pumpAndSettle();
        expect(find.semantics.byLabel('其他 40 檔，未即時，共 40 檔'), findsOneWidget);
        handle.dispose();
      });

      group('收盤後區塊每一格都是收盤沒撮合', () {
        HeatmapTile unmatched(String symbol, String name, double cap) =>
            HeatmapTile(
              symbol: symbol,
              name: name,
              close: 100,
              marketCap: cap,
              baseCap: 0,
              change: const TileChangeHollow(HollowReason.noClosingMatch),
              isMine: false,
            );

        HeatmapTile waiting(String symbol, String name, double cap) =>
            HeatmapTile(
              symbol: symbol,
              name: name,
              close: 100,
              marketCap: cap,
              baseCap: 0,
              change: const TileChangeHollow(HollowReason.noClosingQuote),
              isMine: false,
            );

        HeatmapIndustry block(String name, List<HeatmapTile> tiles) =>
            HeatmapIndustry(
              name: name,
              marketCap: tiles.fold(0.0, (s, t) => s + t.marketCap),
              weightedChangePercent: null,
              tiles: tiles,
              liveCoverage: 0,
              allNoClosingMatch: heatmapAllNoClosingMatch(tiles),
            );

        /// 航運業全部收盤沒撮合；觀光餐旅業混一檔尚未取得收盤報價
        HeatmapMarketData afterCloseData() => HeatmapMarketData(
          market: MarketCode.twse,
          dataDate: friday,
          excludedForShares: 0,
          liveMode: HeatmapLiveMode.afterClose,
          industries: [
            _industry('半導體業', [_tile('9901', '測試甲', 8e11, 1)], 1, coverage: 1),
            block('航運業', [
              unmatched('9931', '測試航運', 2e11),
              unmatched('9932', '測試航運乙', 1e11),
            ]),
            block('觀光餐旅業', [
              unmatched('9961', '測試庚', 1e11),
              waiting('9962', '測試辛', 1e11),
            ]),
          ],
        );

        testWidgets('產業選單：全部沒撮合寫「收盤沒撮合」，混一檔未收盤的寫「未收盤」', (tester) async {
          await pumpFixed(tester, afterCloseData());
          await openIndustryMenu(tester);
          expect(menuTexts(tester), [
            '全市場',
            '半導體業 +1.00%・收盤 100%',
            '航運業 收盤沒撮合',
            '觀光餐旅業 未收盤',
          ]);
        });

        testWidgets('無障礙：產業描述', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpFixed(tester, afterCloseData());
          expect(find.semantics.byLabel('航運業，收盤沒撮合，共 2 檔'), findsOneWidget);
          expect(find.semantics.byLabel('觀光餐旅業，未收盤，共 2 檔'), findsOneWidget);
          handle.dispose();
        });

        testWidgets('無障礙：合併塊全部沒撮合說「收盤沒撮合」；格子說原因', (tester) async {
          final handle = tester.ensureSemantics();
          final container = await pumpFixed(
            tester,
            HeatmapMarketData(
              market: MarketCode.twse,
              dataDate: friday,
              excludedForShares: 0,
              liveMode: HeatmapLiveMode.afterClose,
              industries: [
                block('測試業', [
                  unmatched('9901', '測試甲', 1e12),
                  for (var i = 0; i < 4; i++)
                    unmatched('${9902 + i}', '中$i', 1e11),
                  for (var i = 0; i < 40; i++)
                    unmatched('${9940 + i}', '小$i', 1e9),
                ]),
              ],
            ),
          );
          container.read(heatmapSelectionProvider.notifier).zoomTo('測試業');
          await tester.pumpAndSettle();
          expect(
            find.semantics.byLabel('其他 40 檔，收盤沒撮合，共 40 檔'),
            findsOneWidget,
          );
          expect(find.semantics.byLabel('測試甲，收盤沒撮合'), findsOneWidget);
          handle.dispose();
        });

        testWidgets('無障礙：小產業合併塊全部沒撮合說「收盤沒撮合」', (tester) async {
          final handle = tester.ensureSemantics();
          final small = _withSmallIndustries();
          await pumpFixed(
            tester,
            HeatmapMarketData(
              market: small.market,
              dataDate: friday,
              excludedForShares: 0,
              liveMode: HeatmapLiveMode.afterClose,
              industries: [
                for (final i in small.industries)
                  block(i.name!, [
                    for (final t in i.tiles)
                      unmatched(t.symbol, t.name, t.marketCap),
                  ]),
              ],
            ),
          );
          final group = _painterOf(tester).smallIndustries!;
          expect(group.allNoClosingMatch, isTrue, reason: '前提');
          expect(
            find.semantics.byLabel(
              '其他 ${group.members.length} 個產業，收盤沒撮合，'
              '共 ${group.stockCount} 檔',
            ),
            findsOneWidget,
          );
          handle.dispose();
        });
      });

      testWidgets('無障礙：小產業合併塊寫「沒有今日漲跌 N」並接即時比例', (tester) async {
        final handle = tester.ensureSemantics();
        final small = _withSmallIndustries();
        await pumpFixed(
          tester,
          HeatmapMarketData(
            market: small.market,
            dataDate: friday,
            excludedForShares: 0,
            liveMode: HeatmapLiveMode.intraday,
            industries: [
              ...small.industries.take(5),
              _industry(
                '小乙業',
                [_hollowTile('9971', '測試庚', 5e9)],
                null,
                coverage: 0,
              ),
            ],
          ),
        );
        // 兩檔市值相同、一檔即時：即時 50%
        expect(
          find.semantics.byLabel(
            '其他 2 個產業，共 2 檔，市值加權上漲 1.00%，漲 1、跌 0、平 0、'
            '沒有今日漲跌 1，即時部分占 50%，含自選或持股 1 檔',
          ),
          findsOneWidget,
        );
        handle.dispose();
      });

      testWidgets('點「其他 N 個產業」拉出的清單用當下的模式寫比例', (tester) async {
        final small = _withSmallIndustries();
        await pumpFixed(
          tester,
          HeatmapMarketData(
            market: small.market,
            dataDate: friday,
            excludedForShares: 0,
            liveMode: HeatmapLiveMode.afterClose,
            industries: [
              for (final i in small.industries)
                _industry(
                  i.name,
                  i.tiles,
                  i.weightedChangePercent,
                  coverage: 1,
                ),
            ],
          ),
        );
        final p = _painterOf(tester).smallIndustries!.paint;
        await tester.tapAt(
          tester.getTopLeft(find.byType(HeatmapView)) +
              Offset(p.left + p.width / 2, p.top + p.height / 2),
        );
        await tester.pumpAndSettle();
        expect(find.text('市值加權 +1.00%・收盤 100%'), findsOneWidget);
        expect(find.text('+1.00%・收盤 100%'), findsNWidgets(2));
      });

      testWidgets('點「其他 N 檔」拉出的清單用當下的模式寫比例', (tester) async {
        final container = await pumpFixed(tester, folded(allHollow: false));
        container.read(heatmapSelectionProvider.notifier).zoomTo('測試業');
        await tester.pumpAndSettle();
        final other = _painterOf(tester).layout.single.other!;
        final p = other.paint;
        await tester.tapAt(
          tester.getTopLeft(find.byType(HeatmapView)) +
              Offset(p.left + p.width / 2, p.top + p.height / 2),
        );
        await tester.pumpAndSettle();
        expect(find.text('市值加權 +1.00%・即時 98%'), findsOneWidget);
        expect(find.text('漲 40、跌 0、平 0、空心 1'), findsOneWidget);
      });
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

/// 固定的熱力圖即時檢視（只驗畫面怎麼寫，不經過即時套色）
class _FixedLive extends HeatmapLiveNotifier {
  _FixedLive(this.view);
  final HeatmapLiveView view;

  @override
  HeatmapLiveView build() => view;
}

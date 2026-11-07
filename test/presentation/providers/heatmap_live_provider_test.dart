import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

class _FixedHeatmap extends MarketHeatmapNotifier {
  _FixedHeatmap(this.initial);
  final MarketHeatmapState initial;
  @override
  MarketHeatmapState build() => initial;
  void replace(MarketHeatmapState next) => state = next;
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;
  @override
  LiveQuoteState build() => initial;
  void replace(LiveQuoteState next) => state = next;
}

final _friday = DateTime(2026, 11, 6);
final _monday = DateTime(2026, 11, 9);

DateTime _mon(int h, int m, [int s = 0]) => DateTime(2026, 11, 9, h, m, s);

DateTime _tue(int h, int m, [int s = 0]) => DateTime(2026, 11, 10, h, m, s);

const _semi = '半導體業';

/// 半導體業的成員；9950 市值最小，不在全市場前 69 檔、放大後才登記
const _semiMembers = {'9901', '9902', '9903', '9950'};

/// 虛構代號 99NN
String _sym(int i) => '99${i.toString().padLeft(2, '0')}';

/// 市值依代號遞減，9950 最小
double _capOf(int i) => i == 50 ? 0.5e6 : (100 - i) * 1e6;

/// 上市全市場市值前 69 檔：9900～9949、9951～9969
final _top69 = [
  for (var i = 0; i < 50; i++) _sym(i),
  for (var i = 51; i < 70; i++) _sym(i),
];

/// 正式資料的一格：收盤 100、漲跌 −0.8%
HeatmapTile _tile(String symbol, double cap) => HeatmapTile(
  symbol: symbol,
  name: '測試$symbol',
  close: 100,
  marketCap: cap,
  baseCap: cap * 100 / 99.2,
  change: const TileChangeValue(-0.8),
  isMine: false,
);

HeatmapIndustry _industry(String name, List<HeatmapTile> tiles) {
  final sorted = [...tiles]
    ..sort((a, b) {
      final byCap = b.marketCap.compareTo(a.marketCap);
      return byCap != 0 ? byCap : a.symbol.compareTo(b.symbol);
    });
  return HeatmapIndustry(
    name: name,
    marketCap: sorted.fold(0.0, (a, t) => a + t.marketCap),
    weightedChangePercent: -0.8,
    tiles: sorted,
  );
}

/// 上市：9900～9979 共 80 檔，分「測試業」與半導體業
HeatmapMarketData _twse({DateTime? dataDate}) {
  final tiles = [for (var i = 0; i < 80; i++) _tile(_sym(i), _capOf(i))];
  return HeatmapMarketData(
    market: MarketCode.twse,
    dataDate: dataDate ?? _friday,
    industries: [
      _industry('測試業', [
        for (final t in tiles)
          if (!_semiMembers.contains(t.symbol)) t,
      ]),
      _industry(_semi, [
        for (final t in tiles)
          if (_semiMembers.contains(t.symbol)) t,
      ]),
    ],
    excludedForShares: 0,
  );
}

/// 上櫃：9980～9989 共 10 檔
HeatmapMarketData _tpex({DateTime? dataDate}) => HeatmapMarketData(
  market: MarketCode.tpex,
  dataDate: dataDate ?? _friday,
  industries: [
    _industry('測試丙業', [
      for (var i = 80; i < 90; i++) _tile(_sym(i), _capOf(i)),
    ]),
  ],
  excludedForShares: 0,
);

/// 成交價 103、昨收 100（上色時漲 3%）
LiveQuoteEntry _quote(
  String symbol, {
  DateTime? date,
  bool closing = false,
  String time = '10:04:50',
}) => LiveQuoteEntry(
  symbol: symbol,
  date: date ?? _monday,
  price: 103,
  displaySource: LiveDisplaySource.trade,
  previousClose: 100,
  quoteTime: time,
  isClosingQuote: closing,
);

LiveQuoteState _state({
  Map<String, LiveQuoteEntry> entries = const {},
  Map<String, DateTime> fetchedAt = const {},
  bool? hadToday = true,
  bool stalled = false,
  DateTime? rateLimitedUntil,
  DateTime? lastRespondedAt,
  String? quoteTime,
}) => LiveQuoteState(
  entries: entries,
  fetchedAt: fetchedAt,
  stalled: stalled,
  rateLimitedUntil: rateLimitedUntil,
  lastRespondedAt: lastRespondedAt,
  latestResponseHadToday: hadToday,
  latestQuoteTime: quoteTime,
);

/// 開著的熱力圖頁：listener 讓 autoDispose 的 provider 一直活著，每個動作
/// 先撥時鐘再改狀態、立即讀出重算的結果
class _Page {
  _Page({
    required DateTime at,
    Map<String, HeatmapMarketData>? markets,
    LiveQuoteState center = const LiveQuoteState(),
  }) : clock = _Clock(at) {
    container = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(clock),
        marketHeatmapProvider.overrideWith(
          () => _FixedHeatmap(
            MarketHeatmapState(
              isLoading: false,
              markets:
                  markets ??
                  {MarketCode.twse: _twse(), MarketCode.tpex: _tpex()},
            ),
          ),
        ),
        liveQuoteCenterProvider.overrideWith(() => _FixedCenter(center)),
      ],
    );
    addTearDown(container.dispose);
    _sub = container.listen(heatmapLiveProvider, (_, _) => notified++);
  }

  final _Clock clock;
  late final ProviderContainer container;
  late final ProviderSubscription<HeatmapLiveView> _sub;
  int notified = 0;

  HeatmapLiveView get view => _sub.read();

  HeatmapLiveView publish(DateTime at, LiveQuoteState state) {
    clock.value = at;
    (container.read(liveQuoteCenterProvider.notifier) as _FixedCenter).replace(
      state,
    );
    return view;
  }

  HeatmapLiveView replaceMarkets(
    DateTime at,
    Map<String, HeatmapMarketData> markets,
  ) {
    clock.value = at;
    (container.read(marketHeatmapProvider.notifier) as _FixedHeatmap).replace(
      MarketHeatmapState(isLoading: false, markets: markets),
    );
    return view;
  }

  HeatmapLiveView zoomTo(DateTime at, String key) {
    clock.value = at;
    container.read(heatmapSelectionProvider.notifier).zoomTo(key);
    return view;
  }

  HeatmapLiveView clearZoom(DateTime at) {
    clock.value = at;
    container.read(heatmapSelectionProvider.notifier).clearZoom();
    return view;
  }

  HeatmapLiveView selectMarket(DateTime at, String market) {
    clock.value = at;
    container.read(heatmapSelectionProvider.notifier).selectMarket(market);
    return view;
  }

  /// 跨過開盤、收盤或午夜：邊界 provider 換值
  HeatmapLiveView crossBoundary(DateTime at) {
    clock.value = at;
    container.invalidate(liveQuoteBoundaryProvider);
    return view;
  }
}

TileChange _changeOf(HeatmapLiveView view, String symbol) => view
    .data!
    .industries
    .expand((i) => i.tiles)
    .firstWhere((t) => t.symbol == symbol)
    .change;

final _colored = isA<TileChangeValue>().having(
  (c) => c.percent,
  'percent',
  closeTo(3, 1e-9),
);

Matcher _hollow(HollowReason reason) =>
    isA<TileChangeHollow>().having((c) => c.reason, 'reason', reason);

List<String> _symbolsOf(HeatmapLiveView view) => [
  for (final r in view.stockRegistrations) r.symbol,
];

void main() {
  group('heatmapSelectionProvider', () {
    test('開頁是上市、全市場；換市場清掉放大；放大與取消放大不換市場', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(heatmapSelectionProvider, (_, _) {});
      final notifier = c.read(heatmapSelectionProvider.notifier);

      expect(sub.read(), (market: MarketCode.twse, zoom: null));
      notifier.zoomTo(_semi);
      expect(sub.read(), (market: MarketCode.twse, zoom: _semi));
      notifier.selectMarket(MarketCode.tpex);
      expect(sub.read(), (market: MarketCode.tpex, zoom: null));
      // 未分類的 key 是空字串，仍是放大
      notifier.zoomTo('');
      expect(sub.read(), (market: MarketCode.tpex, zoom: ''));
      notifier.clearZoom();
      expect(sub.read(), (market: MarketCode.tpex, zoom: null));
    });
  });

  group('模式與登記', () {
    test('週一 10:30、資料日上週五 → 盤中，登記全市場市值前 69 檔，'
        '都沒有今天的正式資料、市場別照目前市場', () {
      final page = _Page(at: _mon(10, 30));
      final view = page.view;

      expect(view.mode, HeatmapLiveMode.intraday);
      expect(view.data!.liveMode, HeatmapLiveMode.intraday);
      expect(view.stockRegistrations, hasLength(HeatmapParams.liveTileLimit));
      expect(_symbolsOf(view), _top69);
      expect(
        view.stockRegistrations.every(
          (r) => r.market == MarketCode.twse && !r.hasOfficialToday,
        ),
        isTrue,
      );
      expect(view.quoteStatus, isNull);
      expect(view.closing, isNull);

      final tpex = page.selectMarket(_mon(10, 31), MarketCode.tpex);
      expect(_symbolsOf(tpex), [for (var i = 80; i < 90; i++) _sym(i)]);
      expect(
        tpex.stockRegistrations.every(
          (r) => r.market == MarketCode.tpex && !r.hasOfficialToday,
        ),
        isTrue,
      );
    });

    test('這個市場沒有正式資料 → 什麼都沒有', () {
      final page = _Page(
        at: _mon(10, 30),
        markets: const {},
        center: _state(entries: {'9901': _quote('9901')}),
      );
      expect(page.view, const HeatmapLiveView());
    });

    test('盤後資料在頁面開著時寫入（資料日變今天）→ 不需要即時：沒有登記，'
        'data 是新的正式資料', () {
      final page = _Page(
        at: _mon(13, 35),
        center: _state(entries: {'9900': _quote('9900', closing: true)}),
      );
      expect(page.view.mode, HeatmapLiveMode.afterClose);

      final written = _twse(dataDate: _monday);
      final view = page.replaceMarkets(_mon(14, 30), {
        MarketCode.twse: written,
        MarketCode.tpex: _tpex(),
      });
      expect(view.mode, isNull);
      expect(view.stockRegistrations, isEmpty);
      expect(view.quoteStatus, isNull);
      expect(view.closing, isNull);
      expect(view.data, same(written));
    });
  });

  group('開始登記的時刻', () {
    test('開頁 10:00：10:05 抓到的上色；09:40（開頁前別的畫面抓的）未即時', () {
      final page = _Page(
        at: _mon(10, 0),
        center: _state(
          entries: {'9902': _quote('9902')},
          fetchedAt: {'9902': _mon(9, 40)},
        ),
      );
      expect(_changeOf(page.view, '9902'), _hollow(HollowReason.notLive));
      // 沒有一檔是這頁登記之後抓的：沒有即時數字可描述
      expect(page.view.quoteStatus, isNull);

      final view = page.publish(
        _mon(10, 5),
        _state(
          entries: {'9901': _quote('9901'), '9902': _quote('9902')},
          fetchedAt: {'9901': _mon(10, 5), '9902': _mon(9, 40)},
          quoteTime: '10:04:58',
        ),
      );
      expect(_changeOf(view, '9901'), _colored);
      expect(_changeOf(view, '9902'), _hollow(HollowReason.notLive));
    });

    test('全市場 → 放大半導體業 → 取消放大：一直在清單裡的 9901 全程上色；'
        '放大時才進清單的 9950 未即時', () {
      final page = _Page(at: _mon(10, 0));
      final center = _state(
        entries: {'9901': _quote('9901'), '9950': _quote('9950')},
        fetchedAt: {'9901': _mon(10, 5), '9950': _mon(9, 40)},
      );
      final whole = page.publish(_mon(10, 5), center);
      expect(_changeOf(whole, '9901'), _colored);
      expect(_changeOf(whole, '9950'), _hollow(HollowReason.notLive));

      final zoomed = page.zoomTo(_mon(10, 6), _semi);
      expect(_symbolsOf(zoomed), ['9901', '9902', '9903', '9950']);
      expect(_changeOf(zoomed, '9901'), _colored);
      expect(_changeOf(zoomed, '9950'), _hollow(HollowReason.notLive));

      final back = page.clearZoom(_mon(10, 7));
      expect(_symbolsOf(back), _top69);
      expect(_changeOf(back, '9901'), _colored);
      expect(_changeOf(back, '9950'), _hollow(HollowReason.notLive));
    });

    test('離開清單就移除：9960 放大期間被別的畫面抓到，取消放大後未即時，'
        '直到抓到的時刻不早於重新進清單的時刻', () {
      final page = _Page(at: _mon(10, 0));
      expect(_symbolsOf(page.view), contains('9960'));

      expect(
        _symbolsOf(page.zoomTo(_mon(10, 10), _semi)),
        isNot(contains('9960')),
      );
      page.publish(
        _mon(10, 12),
        _state(
          entries: {'9960': _quote('9960')},
          fetchedAt: {'9960': _mon(10, 12)},
        ),
      );

      final back = page.clearZoom(_mon(10, 15));
      expect(_changeOf(back, '9960'), _hollow(HollowReason.notLive));

      // 相等也算這頁登記之後抓的
      final fetched = page.publish(
        _mon(10, 15),
        _state(
          entries: {'9960': _quote('9960')},
          fetchedAt: {'9960': _mon(10, 15)},
        ),
      );
      expect(_changeOf(fetched, '9960'), _colored);
    });

    test('切到不需要即時的市場再切回：回來的檔重新記開始登記的時刻，切走期間別的畫面抓的不算', () {
      final page = _Page(
        at: _mon(10, 0),
        markets: {
          MarketCode.twse: _twse(),
          MarketCode.tpex: _tpex(dataDate: _monday),
        },
      );
      expect(_symbolsOf(page.view), contains('9901'));

      final tpex = page.selectMarket(_mon(10, 1), MarketCode.tpex);
      expect(tpex.mode, isNull);
      expect(tpex.stockRegistrations, isEmpty);

      page.publish(
        _mon(10, 2),
        _state(
          entries: {'9901': _quote('9901')},
          fetchedAt: {'9901': _mon(10, 2)},
        ),
      );
      final back = page.selectMarket(_mon(10, 3), MarketCode.twse);
      expect(_changeOf(back, '9901'), _hollow(HollowReason.notLive));
    });

    test('換日：開始登記的時刻整個清空，隔天以當天重新進清單的時刻為準', () {
      final page = _Page(at: _mon(10, 0));
      final monday = page.publish(
        _mon(10, 5),
        _state(
          entries: {'9901': _quote('9901')},
          fetchedAt: {'9901': _mon(10, 5)},
        ),
      );
      expect(_changeOf(monday, '9901'), _colored);

      // 頁面被蓋住過夜，隔天回來第一次重算；9901 是別的畫面 09:05 抓的
      final tuesday = page.publish(
        _tue(9, 10),
        _state(
          entries: {'9901': _quote('9901', date: DateTime(2026, 11, 10))},
          fetchedAt: {'9901': _tue(9, 5)},
        ),
      );
      expect(tuesday.mode, HeatmapLiveMode.intraday);
      expect(_changeOf(tuesday, '9901'), _hollow(HollowReason.notLive));

      final next = page.publish(
        _tue(9, 10, 15),
        _state(
          entries: {'9901': _quote('9901', date: DateTime(2026, 11, 10))},
          fetchedAt: {'9901': _tue(9, 10, 15)},
        ),
      );
      expect(_changeOf(next, '9901'), _colored);
    });
  });

  group('盤中狀態', () {
    test('盤中狀態是報價中心的頁首規則；網路暫停 → pausedNetwork，'
        '已上色的格子維持', () {
      final page = _Page(at: _mon(10, 0));
      final live = page.publish(
        _mon(10, 5),
        _state(
          entries: {'9901': _quote('9901')},
          fetchedAt: {'9901': _mon(10, 5)},
          lastRespondedAt: _mon(10, 5),
          quoteTime: '10:04:58',
        ),
      );
      expect(
        live.quoteStatus,
        const LiveHeaderStatus(LiveHeaderKind.quoteTime, '10:04:58'),
      );
      expect(_changeOf(live, '9901'), _colored);

      final stalled = page.publish(
        _mon(10, 7),
        _state(
          entries: {'9901': _quote('9901')},
          fetchedAt: {'9901': _mon(10, 5)},
          lastRespondedAt: _mon(10, 5),
          quoteTime: '10:04:58',
          stalled: true,
        ),
      );
      expect(
        stalled.quoteStatus,
        const LiveHeaderStatus(LiveHeaderKind.pausedNetwork, '10:05:00'),
      );
      expect(_changeOf(stalled, '9901'), _colored);
    });

    test('盤中跨過 13:30：盤中最後一筆不是收盤報價 → noClosingQuote', () {
      final page = _Page(at: _mon(13, 29));
      final open = page.publish(
        _mon(13, 29, 30),
        _state(
          entries: {'9901': _quote('9901', time: '13:29:25')},
          fetchedAt: {'9901': _mon(13, 29, 30)},
        ),
      );
      expect(_changeOf(open, '9901'), _colored);

      final closed = page.crossBoundary(_mon(13, 30));
      expect(closed.mode, HeatmapLiveMode.afterClose);
      expect(closed.data!.liveMode, HeatmapLiveMode.afterClose);
      expect(_changeOf(closed, '9901'), _hollow(HollowReason.noClosingQuote));
    });
  });

  group('收盤後', () {
    test('13:35：登記還沒拿到收盤報價的前 69 檔；進度是整張圖的檔數與今天'
        '有收盤報價的檔數，放大不變', () {
      final page = _Page(
        at: _mon(13, 35),
        center: _state(
          entries: {
            '9900': _quote('9900', closing: true),
            '9901': _quote('9901', closing: true),
            '9902': _quote('9902', closing: true),
            // 不在圖上（指數）
            't00': _quote('t00', closing: true),
            // 今天但不是收盤報價
            '9903': _quote('9903', time: '13:29:58'),
            // 收盤報價但不是今天的
            '9904': _quote('9904', date: _friday, closing: true),
          },
        ),
      );
      final view = page.view;
      expect(view.mode, HeatmapLiveMode.afterClose);
      expect(view.data!.liveMode, HeatmapLiveMode.afterClose);
      expect(_symbolsOf(view), [
        for (var i = 3; i < 50; i++) _sym(i),
        for (var i = 51; i < 73; i++) _sym(i),
      ]);
      expect(view.closing, (done: 3, total: 80));
      expect(_changeOf(view, '9900'), _colored);
      expect(_changeOf(view, '9903'), _hollow(HollowReason.noClosingQuote));

      final zoomed = page.zoomTo(_mon(13, 36), _semi);
      expect(zoomed.closing, (done: 3, total: 80));
      expect(_symbolsOf(zoomed), _symbolsOf(view));
    });

    test('13:35：狀態只保留報價暫停（限流、網路），沒有暫停為 null', () {
      final entries = {
        '9900': _quote('9900', closing: true),
        // 這頁登記之後抓到、不是收盤報價：頁首規則會說「最後報價」
        '9903': _quote('9903', time: '13:29:58'),
      };
      final fetchedAt = {'9903': _mon(13, 36)};
      final page = _Page(at: _mon(13, 35));

      final limited = page.publish(
        _mon(13, 36),
        _state(
          entries: entries,
          fetchedAt: fetchedAt,
          rateLimitedUntil: _mon(13, 40),
        ),
      );
      expect(
        limited.quoteStatus,
        const LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, '13:40'),
      );

      final stalled = page.publish(
        _mon(13, 37),
        _state(
          entries: entries,
          fetchedAt: fetchedAt,
          stalled: true,
          lastRespondedAt: _mon(13, 36),
        ),
      );
      expect(
        stalled.quoteStatus,
        const LiveHeaderStatus(LiveHeaderKind.pausedNetwork, '13:36:00'),
      );

      final quiet = page.publish(
        _mon(13, 38),
        _state(entries: entries, fetchedAt: fetchedAt),
      );
      expect(quiet.quoteStatus, isNull);
      expect(quiet.closing, (done: 1, total: 80));
    });
  });

  group('停市日退回', () {
    /// 證交所只回前一天的報價；圖外的指數有今天的報價也不算
    LiveQuoteState typhoon({
      DateTime? rateLimitedUntil,
      bool stalled = false,
      DateTime? lastRespondedAt,
    }) => _state(
      entries: {
        '9901': _quote('9901', date: _friday),
        '9960': _quote('9960', date: _friday, closing: true),
        't00': _quote('t00'),
      },
      hadToday: false,
      rateLimitedUntil: rateLimitedUntil,
      stalled: stalled,
      lastRespondedAt: lastRespondedAt,
    );

    for (final (label, at, mode) in [
      ('盤中', _mon(10, 30), HeatmapLiveMode.intraday),
      ('收盤後', _mon(13, 35), HeatmapLiveMode.afterClose),
    ]) {
      test('$label：整個市場都沒有今天的報價 → 正式資料、證交所今天尚無報價；'
          '照常登記、沒有進度', () {
        final view = _Page(at: at, center: typhoon()).view;
        expect(view.mode, mode);
        expect(view.data, _twse());
        expect(view.data!.liveMode, isNull);
        expect(
          view.quoteStatus,
          const LiveHeaderStatus(LiveHeaderKind.noQuotesToday),
        );
        expect(_symbolsOf(view), _top69);
        expect(view.closing, isNull);
      });

      test('$label：退回期間報價暫停時用暫停的狀態', () {
        final page = _Page(
          at: at,
          center: typhoon(rateLimitedUntil: at.add(const Duration(minutes: 5))),
        );
        expect(page.view.quoteStatus?.kind, LiveHeaderKind.pausedRateLimit);
        expect(page.view.data!.liveMode, isNull);

        final stalled = page.publish(
          at.add(const Duration(minutes: 1)),
          typhoon(stalled: true, lastRespondedAt: at),
        );
        expect(stalled.quoteStatus?.kind, LiveHeaderKind.pausedNetwork);
        expect(stalled.data!.liveMode, isNull);
      });
    }

    test('不誤退回：收盤後最近一輪沒有今天的報價、但圖上已有今天的收盤 → '
        '照常套色；放大到沒有收盤報價的產業也一樣', () {
      final page = _Page(
        at: _mon(13, 35),
        center: _state(
          entries: {'9900': _quote('9900', closing: true)},
          hadToday: false,
        ),
      );
      final view = page.view;
      expect(view.data!.liveMode, HeatmapLiveMode.afterClose);
      expect(view.closing, (done: 1, total: 80));
      expect(view.quoteStatus, isNull);

      final zoomed = page.zoomTo(_mon(13, 36), _semi);
      expect(zoomed.data!.liveMode, HeatmapLiveMode.afterClose);
      expect(zoomed.closing, (done: 1, total: 80));
      expect(zoomed.quoteStatus, isNull);
    });

    test('不誤退回：盤中放大到沒有今天報價的產業，圖上別處有 → 照常套色、'
        '不說證交所今天尚無報價', () {
      final page = _Page(
        at: _mon(10, 30),
        center: _state(
          entries: {'9960': _quote('9960')},
          fetchedAt: {'9960': _mon(10, 30)},
          hadToday: false,
        ),
      );
      final zoomed = page.zoomTo(_mon(10, 31), _semi);
      expect(zoomed.data!.liveMode, HeatmapLiveMode.intraday);
      // 頁首規則在 latestResponseHadToday 為 false、登記的幾檔都沒有報價時
      // 會說「證交所今天尚無報價」；這裡沒有退回，代表圖上某處（9960）有今天
      // 的報價，那句話是錯的，所以頁首不顯示
      expect(zoomed.quoteStatus, isNull);
    });

    test('開盤頭幾秒退回，第一筆今天的報價一到就離開', () {
      final page = _Page(
        at: _mon(9, 0, 5),
        center: _state(
          entries: {'9901': _quote('9901', date: _friday)},
          hadToday: false,
        ),
      );
      expect(page.view.mode, HeatmapLiveMode.intraday);
      expect(page.view.data!.liveMode, isNull);
      expect(page.view.quoteStatus?.kind, LiveHeaderKind.noQuotesToday);

      final view = page.publish(
        _mon(9, 0, 20),
        _state(
          entries: {'9901': _quote('9901', time: '09:00:15')},
          fetchedAt: {'9901': _mon(9, 0, 20)},
          quoteTime: '09:00:15',
        ),
      );
      expect(view.data!.liveMode, HeatmapLiveMode.intraday);
      expect(_changeOf(view, '9901'), _colored);
      expect(
        view.quoteStatus,
        const LiveHeaderStatus(LiveHeaderKind.quoteTime, '09:00:15'),
      );
    });
  });

  group('相等與沿用', () {
    test('報價中心換了新的狀態物件、內容相同 → 檢視相等、data 是同一個物件、'
        '不通知畫面', () {
      final page = _Page(at: _mon(10, 0));
      LiveQuoteState center() => _state(
        entries: {'9901': _quote('9901')},
        fetchedAt: {'9901': _mon(10, 5)},
        quoteTime: '10:04:58',
      );
      final before = page.publish(_mon(10, 5), center());
      final notified = page.notified;
      // listener 有接上：內容變了會通知，下面「不通知」才有意義
      expect(notified, greaterThan(0));

      final after = page.publish(_mon(10, 5, 10), center());
      expect(after, before);
      expect(after.hashCode, before.hashCode);
      expect(after.data, same(before.data));
      expect(page.notified, notified);
    });

    test('HeatmapLiveView：五個欄位任一不同就不相等；登記清單比內容', () {
      final data = _tpex();
      const registration = LiveQuoteRegistration(
        symbol: '9980',
        market: MarketCode.tpex,
      );
      HeatmapLiveView view({
        HeatmapMarketData? data,
        HeatmapLiveMode? mode = HeatmapLiveMode.afterClose,
        List<LiveQuoteRegistration> registrations = const [registration],
        LiveHeaderStatus? status = const LiveHeaderStatus(
          LiveHeaderKind.pausedNetwork,
        ),
        ({int done, int total})? closing = (done: 1, total: 10),
      }) => HeatmapLiveView(
        data: data,
        mode: mode,
        stockRegistrations: registrations,
        quoteStatus: status,
        closing: closing,
      );

      final base = view(data: data);
      final equal = view(
        data: _tpex(),
        registrations: [
          const LiveQuoteRegistration(symbol: '9980', market: MarketCode.tpex),
        ],
      );
      expect(equal, base);
      expect(equal.hashCode, base.hashCode);

      expect(view(data: _twse()), isNot(base));
      expect(view(data: data, mode: HeatmapLiveMode.intraday), isNot(base));
      expect(view(data: data, registrations: const []), isNot(base));
      expect(view(data: data, status: null), isNot(base));
      expect(view(data: data, closing: (done: 2, total: 10)), isNot(base));
    });
  });
}

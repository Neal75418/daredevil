import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_live.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

final _today = DateTime(2026, 11, 9);
final _officialDate = DateTime(2026, 11, 6);

/// 正式資料的一格：收盤 100、市值 100,000（股數 1,000）、漲跌 −0.8%
HeatmapTile _tile(
  String symbol, {
  double cap = 100000,
  TileChange change = const TileChangeValue(-0.8),
  bool mine = false,
}) => HeatmapTile(
  symbol: symbol,
  name: '測試$symbol',
  close: 100,
  marketCap: cap,
  baseCap: change is TileChangeValue ? cap * 100 / (100 + change.percent) : 0,
  change: change,
  isMine: mine,
);

HeatmapMarketData _official(List<HeatmapTile> tiles, {int excluded = 0}) =>
    HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: _officialDate,
      industries: [
        HeatmapIndustry(
          name: '測試業',
          marketCap: tiles.fold(0.0, (a, t) => a + t.marketCap),
          weightedChangePercent: -0.8,
          tiles: tiles,
        ),
      ],
      excludedForShares: excluded,
    );

LiveQuoteEntry _entry(
  String symbol, {
  double price = 103,
  double y = 100,
  DateTime? date,
  LiveDisplaySource source = LiveDisplaySource.trade,
  bool closing = false,
}) => LiveQuoteEntry(
  symbol: symbol,
  date: date ?? _today,
  price: price,
  displaySource: source,
  previousClose: y,
  quoteTime: '10:00:00',
  isClosingQuote: closing,
);

/// 預設：[entries] 的每一檔都登記、都在 [fresh]
HeatmapMarketData _overlay(
  HeatmapMarketData official,
  Map<String, LiveQuoteEntry> entries, {
  HeatmapLiveMode mode = HeatmapLiveMode.intraday,
  Map<String, LiveSymbolStatus> status = const {},
  Set<String>? registered,
  Set<String>? fresh,
}) => overlayHeatmapLive(
  official,
  mode: mode,
  entries: entries,
  symbolStatus: status,
  registered: registered ?? entries.keys.toSet(),
  fresh: fresh ?? entries.keys.toSet(),
  today: _today,
);

HeatmapTile _only(HeatmapMarketData data) =>
    data.industries.single.tiles.single;

HeatmapTile _tileOf(HeatmapMarketData data, String symbol) =>
    data.industries.single.tiles.firstWhere((t) => t.symbol == symbol);

TileChange _changeOf(HeatmapMarketData data, [String symbol = '9901']) =>
    _tileOf(data, symbol).change;

double _percentOf(HeatmapMarketData data, [String symbol = '9901']) {
  final change = _changeOf(data, symbol);
  expect(change, isA<TileChangeValue>());
  return (change as TileChangeValue).percent;
}

/// 虛構代號 99NN（NN 是兩位數序號，0～99）
String _sym(int i) => '99${i.toString().padLeft(2, '0')}';

/// 一個產業：格子照正式資料的順序（市值降冪、同值代號升冪）排好
HeatmapIndustry _industry(String? name, List<HeatmapTile> tiles) {
  final sorted = [...tiles]
    ..sort((a, b) {
      final byCap = b.marketCap.compareTo(a.marketCap);
      return byCap != 0 ? byCap : a.symbol.compareTo(b.symbol);
    });
  return HeatmapIndustry(
    name: name,
    marketCap: sorted.fold(0.0, (a, t) => a + t.marketCap),
    weightedChangePercent: null,
    tiles: sorted,
  );
}

HeatmapMarketData _market(List<HeatmapIndustry> industries) =>
    HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: _officialDate,
      industries: industries,
      excludedForShares: 0,
    );

/// 登記清單的上限：兩批 MIS 請求扣掉一個指數
const _limit = 69;

List<String> _symbols(
  HeatmapMarketData official, {
  HeatmapLiveMode mode = HeatmapLiveMode.intraday,
  String? zoom,
  Map<String, LiveQuoteEntry> entries = const {},
}) => heatmapLiveSymbols(
  official,
  mode: mode,
  zoomIndustryKey: zoom,
  entries: entries,
  today: _today,
);

/// 以代號查市值
Map<String, double> _capsOf(HeatmapMarketData market) => {
  for (final i in market.industries)
    for (final t in i.tiles) t.symbol: t.marketCap,
};

/// 市值是 [from]、[from] − 1、…、[to]（單位千元）的降冪序列
List<double> _capsDescending(int from, int to) => [
  for (var c = from; c >= to; c--) c * 1000.0,
];

void main() {
  group('盤中', () {
    test('在 fresh 且有成交：用即時價與 y 算漲跌，顯示價換成即時價', () {
      final data = _overlay(_official([_tile('9901')]), {
        '9901': _entry('9901'),
      });
      final tile = _only(data);
      expect(_percentOf(data), closeTo(3, 1e-9));
      expect(tile.close, 103);
      expect(tile.marketCap, 100000);
      expect(tile.baseCap, closeTo(100000, 1e-9));
    });

    test('y 是參考價（除權息日）：以 y 為基準，平盤市值跟著 y', () {
      final data = _overlay(_official([_tile('9901')]), {
        '9901': _entry('9901', price: 99.75, y: 95),
      });
      expect(_percentOf(data), closeTo(5, 1e-9));
      expect(_only(data).baseCap, closeTo(95000, 1e-9));
    });

    test('不改名稱、代號、自選標記', () {
      final data = _overlay(_official([_tile('9901', mine: true)]), {
        '9901': _entry('9901'),
      });
      final tile = _only(data);
      expect(tile.symbol, '9901');
      expect(tile.name, '測試9901');
      expect(tile.isMine, isTrue);
    });

    group('登記了但不在 fresh', () {
      HeatmapMarketData run(LiveSymbolStatus? status) => _overlay(
        _official([_tile('9901')]),
        // 中心有今天的成交報價也不用：fresh（登記之後拿到過）才算
        {'9901': _entry('9901')},
        registered: {'9901'},
        fresh: {},
        status: {'9901': ?status},
      );

      test('逐檔狀態是 noQuote：無報價', () {
        expect(
          _changeOf(run(LiveSymbolStatus.noQuote)),
          const TileChangeHollow(HollowReason.noQuote),
        );
      });

      test('沒有狀態、batchFailed、ok：盤中未即時，附正式資料的漲跌', () {
        for (final status in [
          null,
          LiveSymbolStatus.batchFailed,
          LiveSymbolStatus.ok,
        ]) {
          expect(
            _changeOf(run(status)),
            TileChangeHollow(
              HollowReason.notLive,
              previous: (percent: -0.8, date: _officialDate),
            ),
            reason: '狀態 $status',
          );
        }
      });

      test('格子不套即時價：顯示價與平盤市值是空心的樣子', () {
        final tile = _only(run(LiveSymbolStatus.noQuote));
        expect(tile.close, 100);
        expect(tile.baseCap, 0);
      });
    });

    test('在 fresh 但報價中心沒有這一檔：照逐檔狀態判斷', () {
      final data = _overlay(
        _official([_tile('9901'), _tile('9902')]),
        {},
        registered: {'9901', '9902'},
        fresh: {'9901', '9902'},
        status: {'9901': LiveSymbolStatus.noQuote},
      );
      expect(_changeOf(data), const TileChangeHollow(HollowReason.noQuote));
      expect(
        _changeOf(data, '9902'),
        TileChangeHollow(
          HollowReason.notLive,
          previous: (percent: -0.8, date: _officialDate),
        ),
      );
    });

    group('沒登記', () {
      test('中心有今天的報價也不用：盤中未即時，附正式資料的漲跌與日期', () {
        final data = _overlay(
          _official([_tile('9901')]),
          {'9901': _entry('9901')},
          registered: {},
          fresh: {'9901'},
        );
        expect(
          _changeOf(data),
          TileChangeHollow(
            HollowReason.notLive,
            previous: (percent: -0.8, date: DateTime(2026, 11, 6)),
          ),
        );
        final tile = _only(data);
        expect(tile.close, 100);
        expect(tile.baseCap, 0);
      });

      test('正式資料是空心：不附漲跌', () {
        final data = _overlay(
          _official([
            _tile(
              '9901',
              change: const TileChangeHollow(HollowReason.noChangeData),
            ),
          ]),
          {},
          registered: {},
          fresh: {},
        );
        expect(_changeOf(data), const TileChangeHollow(HollowReason.notLive));
        expect((_changeOf(data) as TileChangeHollow).previous, isNull);
      });
    });

    group('在 fresh 但報價不能上色', () {
      test('只有試撮或五檔價：尚無成交', () {
        final data = _overlay(_official([_tile('9901')]), {
          '9901': _entry('9901', source: LiveDisplaySource.trialOrBook),
        });
        expect(_changeOf(data), const TileChangeHollow(HollowReason.noTrade));
        expect(_only(data).baseCap, 0);
      });

      test('漲跌停鎖住照常上色', () {
        final data = _overlay(_official([_tile('9901')]), {
          '9901': _entry('9901', price: 110, source: LiveDisplaySource.locked),
        });
        expect(_percentOf(data), closeTo(10, 1e-9));
        expect(_only(data).close, 110);
      });

      test('最後一筆成交（lastTrade）照常上色', () {
        final data = _overlay(_official([_tile('9901')]), {
          '9901': _entry('9901', source: LiveDisplaySource.lastTrade),
        });
        expect(_percentOf(data), closeTo(3, 1e-9));
      });

      test('報價日期是前一天：盤中未即時（附正式資料的漲跌）', () {
        final data = _overlay(_official([_tile('9901')]), {
          '9901': _entry('9901', date: DateTime(2026, 11, 6)),
        });
        expect(
          _changeOf(data),
          TileChangeHollow(
            HollowReason.notLive,
            previous: (percent: -0.8, date: _officialDate),
          ),
        );
      });

      test('報價日期比對只看年月日、不看時分', () {
        final data = _overlay(_official([_tile('9901')]), {
          '9901': _entry('9901', date: DateTime(2026, 11, 9, 9, 30)),
        });
        expect(_percentOf(data), closeTo(3, 1e-9));
      });

      test('前一天的試撮報價：以日期為先，是盤中未即時而不是尚無成交', () {
        final data = _overlay(_official([_tile('9901')]), {
          '9901': _entry(
            '9901',
            date: DateTime(2026, 11, 6),
            source: LiveDisplaySource.trialOrBook,
          ),
        });
        expect(_changeOf(data), isA<TileChangeHollow>());
        expect(
          (_changeOf(data) as TileChangeHollow).reason,
          HollowReason.notLive,
        );
      });

      test('y 是 0、負數、NaN、∞：無漲跌資料，不退回資料庫收盤', () {
        for (final y in [0.0, -1.0, double.nan, double.infinity]) {
          final data = _overlay(_official([_tile('9901')]), {
            '9901': _entry('9901', y: y),
          });
          expect(
            _changeOf(data),
            const TileChangeHollow(HollowReason.noChangeData),
            reason: 'y = $y',
          );
          expect(_only(data).baseCap, 0, reason: 'y = $y');
        }
      });

      test('即時價是 0、負數、NaN、∞：無漲跌資料', () {
        for (final price in [0.0, -5.0, double.nan, double.infinity]) {
          final data = _overlay(_official([_tile('9901')]), {
            '9901': _entry('9901', price: price),
          });
          expect(
            _changeOf(data),
            const TileChangeHollow(HollowReason.noChangeData),
            reason: 'price = $price',
          );
        }
      });

      test('正式資料的收盤或市值不是正數，算不出可信的平盤市值：無漲跌資料', () {
        HeatmapTile broken({required double close, required double cap}) =>
            HeatmapTile(
              symbol: '9901',
              name: '測試9901',
              close: close,
              marketCap: cap,
              baseCap: 0,
              change: const TileChangeHollow(HollowReason.noChangeData),
              isMine: false,
            );
        // 收盤與昨收都是負數時平盤市值是正的，只有昨收檢查擋得下
        for (final (close, cap, y) in [
          (0.0, 100000.0, 100.0),
          (-100.0, 100000.0, 100.0),
          (-100.0, 100000.0, -100.0),
          (100.0, 0.0, 100.0),
        ]) {
          final data = _overlay(_official([broken(close: close, cap: cap)]), {
            '9901': _entry('9901', y: y),
          });
          expect(
            _changeOf(data),
            const TileChangeHollow(HollowReason.noChangeData),
            reason: '收盤 $close、市值 $cap、y $y',
          );
        }
      });
    });
  });

  group('收盤後', () {
    HeatmapMarketData run({
      required LiveQuoteEntry? entry,
      Set<String> registered = const {},
      Set<String> fresh = const {},
      Map<String, LiveSymbolStatus> status = const {},
    }) => _overlay(
      _official([_tile('9901')]),
      {'9901': ?entry},
      mode: HeatmapLiveMode.afterClose,
      registered: registered,
      fresh: fresh,
      status: status,
    );

    test('今天的收盤報價：不論登記與 fresh 都上色', () {
      for (final (registered, fresh) in [
        (<String>{}, <String>{}),
        ({'9901'}, <String>{}),
        (<String>{}, {'9901'}),
        ({'9901'}, {'9901'}),
      ]) {
        final data = run(
          entry: _entry('9901', price: 102, closing: true),
          registered: registered,
          fresh: fresh,
        );
        expect(
          _percentOf(data),
          closeTo(2, 1e-9),
          reason: '登記 $registered、fresh $fresh',
        );
        expect(_only(data).close, 102);
        expect(_only(data).baseCap, closeTo(100000, 1e-9));
      }
    });

    test('不是收盤報價：尚未取得收盤報價（登記了也一樣）', () {
      final data = run(
        entry: _entry('9901'),
        registered: {'9901'},
        fresh: {'9901'},
      );
      expect(
        _changeOf(data),
        const TileChangeHollow(HollowReason.noClosingQuote),
      );
      expect(_only(data).baseCap, 0);
    });

    test('中心沒有這一檔：尚未取得收盤報價', () {
      expect(
        _changeOf(run(entry: null, registered: {'9901'})),
        const TileChangeHollow(HollowReason.noClosingQuote),
      );
    });

    test('逐檔狀態 noQuote 也是尚未取得收盤報價，不是無報價', () {
      expect(
        _changeOf(
          run(
            entry: null,
            registered: {'9901'},
            status: {'9901': LiveSymbolStatus.noQuote},
          ),
        ),
        const TileChangeHollow(HollowReason.noClosingQuote),
      );
    });

    test('收盤報價但不是今天的：尚未取得收盤報價', () {
      final data = run(
        entry: _entry('9901', date: DateTime(2026, 11, 6), closing: true),
      );
      expect(
        _changeOf(data),
        const TileChangeHollow(HollowReason.noClosingQuote),
      );
    });

    test('收盤報價的 y 不可用：無漲跌資料', () {
      final data = run(entry: _entry('9901', y: 0, closing: true));
      expect(
        _changeOf(data),
        const TileChangeHollow(HollowReason.noChangeData),
      );
    });

    test('收盤報價的顯示來源是最後一筆成交：照常上色', () {
      final data = run(
        entry: _entry(
          '9901',
          source: LiveDisplaySource.lastTrade,
          closing: true,
        ),
      );
      expect(_percentOf(data), closeTo(3, 1e-9));
    });
  });

  group('產業與整體', () {
    HeatmapMarketData twoTiles({
      required Map<String, LiveQuoteEntry> entries,
      HeatmapLiveMode mode = HeatmapLiveMode.intraday,
      Set<String>? registered,
      Set<String>? fresh,
    }) => _overlay(
      _official([_tile('9901', cap: 100), _tile('9902', cap: 100)]),
      entries,
      mode: mode,
      registered: registered,
      fresh: fresh,
    );

    test('只用已即時的成員算加權漲跌，coverage 是已即時的市值占比', () {
      final data = twoTiles(
        entries: {'9901': _entry('9901', price: 102)},
        registered: {'9901'},
      );
      final industry = data.industries.single;
      expect(industry.weightedChangePercent, closeTo(2, 1e-9));
      expect(industry.liveCoverage, 0.5);
    });

    test('權重是即時平盤市值（股數 × y），不是市值', () {
      final data = _overlay(
        _official([
          // 股數 1、y 100、+10%：平盤市值 100
          _tile('9901', cap: 100),
          // 股數 10、y 50、0%：平盤市值 500
          _tile('9902', cap: 1000),
        ]),
        {
          '9901': _entry('9901', price: 110),
          '9902': _entry('9902', price: 50, y: 50),
        },
      );
      final industry = data.industries.single;
      expect(_tileOf(data, '9902').baseCap, closeTo(500, 1e-9));
      // (100 × 10 + 500 × 0) ÷ 600；用市值當權重會得 0.909
      expect(industry.weightedChangePercent, closeTo(10 / 6, 1e-9));
      expect(industry.liveCoverage, 1.0);
    });

    test('全部未即時：沒有加權漲跌，coverage 0', () {
      final data = twoTiles(entries: {}, registered: {}, fresh: {});
      final industry = data.industries.single;
      expect(industry.weightedChangePercent, isNull);
      expect(industry.liveCoverage, 0);
    });

    test('收盤後也算 coverage（已取得收盤報價的比例）', () {
      final data = twoTiles(
        mode: HeatmapLiveMode.afterClose,
        entries: {'9901': _entry('9901', price: 101, closing: true)},
      );
      final industry = data.industries.single;
      expect(industry.weightedChangePercent, closeTo(1, 1e-9));
      expect(industry.liveCoverage, 0.5);
    });

    test('liveMode 帶入結果', () {
      for (final mode in HeatmapLiveMode.values) {
        final data = _overlay(
          _official([_tile('9901')]),
          {},
          mode: mode,
          registered: {},
          fresh: {},
        );
        expect(data.liveMode, mode);
      }
    });

    test('市場、資料日、頁尾檔數、產業與格子順序、市值都與正式資料相同', () {
      final official = HeatmapMarketData(
        market: MarketCode.tpex,
        dataDate: _officialDate,
        industries: [
          HeatmapIndustry(
            name: '甲業',
            marketCap: 700,
            weightedChangePercent: 1,
            tiles: [_tile('9903', cap: 400), _tile('9901', cap: 300)],
          ),
          HeatmapIndustry(
            name: null,
            marketCap: 200,
            weightedChangePercent: null,
            tiles: [
              _tile(
                '9902',
                cap: 200,
                change: const TileChangeHollow(HollowReason.noChangeData),
              ),
            ],
          ),
        ],
        excludedForShares: 3,
      );
      final data = _overlay(
        official,
        {'9903': _entry('9903'), '9901': _entry('9901', price: 90)},
        registered: {'9903', '9901'},
        fresh: {'9903'},
      );
      expect(data.market, MarketCode.tpex);
      expect(data.dataDate, _officialDate);
      expect(data.excludedForShares, 3);
      expect(data.industries.map((i) => i.name), ['甲業', null]);
      expect(data.industries.map((i) => i.marketCap), [700, 200]);
      expect(
        [
          for (final i in data.industries)
            for (final t in i.tiles) (t.symbol, t.marketCap),
        ],
        [('9903', 400), ('9901', 300), ('9902', 200)],
      );
    });

    test('不改動傳入的正式資料', () {
      final official = _official([_tile('9901')]);
      final before = _official([_tile('9901')]);
      _overlay(official, {'9901': _entry('9901')});
      expect(official, before);
    });
  });

  group('heatmapLiveModeAt', () {
    final now = DateTime(2026, 11, 9, 10, 30);

    HeatmapLiveMode? modeAt(
      MarketPhase phase, {
      DateTime? dataDate,
      DateTime? at,
    }) => heatmapLiveModeAt(
      phase: phase,
      dataDate: dataDate ?? _officialDate,
      now: at ?? now,
    );

    test('盤中、資料日是前一個交易日：盤中', () {
      expect(modeAt(MarketPhase.open), HeatmapLiveMode.intraday);
    });

    test('收盤後、資料日是前一個交易日：收盤後', () {
      expect(modeAt(MarketPhase.afterClose), HeatmapLiveMode.afterClose);
    });

    test('盤中、資料日已是今天：null（該市場已有今天的正式資料）', () {
      expect(modeAt(MarketPhase.open, dataDate: _today), isNull);
    });

    test('收盤後、資料日已是今天：null', () {
      expect(modeAt(MarketPhase.afterClose, dataDate: _today), isNull);
    });

    test('開盤前、休市日：null', () {
      expect(modeAt(MarketPhase.preOpen), isNull);
      expect(modeAt(MarketPhase.closed), isNull);
    });

    test('資料日與 now 只比年月日、不看時分', () {
      final late = DateTime(2026, 11, 9, 13, 35);
      expect(
        modeAt(
          MarketPhase.afterClose,
          dataDate: DateTime(2026, 11, 9, 0, 0),
          at: late,
        ),
        isNull,
      );
      expect(
        modeAt(
          MarketPhase.afterClose,
          dataDate: DateTime(2026, 11, 8, 23, 59),
          at: late,
        ),
        HeatmapLiveMode.afterClose,
      );
    });

    test('開著頁面跨過 9:00：由 null 變盤中', () {
      final before = DateTime(2026, 11, 9, 8, 59, 59);
      final after = DateTime(2026, 11, 9, 9, 0);
      expect(LiveQuoteSchedule.phaseAt(before), MarketPhase.preOpen);
      expect(LiveQuoteSchedule.phaseAt(after), MarketPhase.open);
      expect(
        heatmapLiveModeAt(
          phase: LiveQuoteSchedule.phaseAt(before),
          dataDate: _officialDate,
          now: before,
        ),
        isNull,
      );
      expect(
        heatmapLiveModeAt(
          phase: LiveQuoteSchedule.phaseAt(after),
          dataDate: _officialDate,
          now: after,
        ),
        HeatmapLiveMode.intraday,
      );
    });

    test('開著頁面跨過 13:30：由盤中變收盤後', () {
      final before = DateTime(2026, 11, 9, 13, 29);
      final after = DateTime(2026, 11, 9, 13, 35);
      expect(LiveQuoteSchedule.phaseAt(before), MarketPhase.open);
      expect(LiveQuoteSchedule.phaseAt(after), MarketPhase.afterClose);
      expect(
        heatmapLiveModeAt(
          phase: LiveQuoteSchedule.phaseAt(before),
          dataDate: _officialDate,
          now: before,
        ),
        HeatmapLiveMode.intraday,
      );
      expect(
        heatmapLiveModeAt(
          phase: LiveQuoteSchedule.phaseAt(after),
          dataDate: _officialDate,
          now: after,
        ),
        HeatmapLiveMode.afterClose,
      );
    });

    test('收盤後開著頁面跨午夜到下一個交易日：由收盤後變 null', () {
      final evening = DateTime(2026, 11, 9, 23, 59);
      final nextMorning = DateTime(2026, 11, 10, 0, 1);
      expect(LiveQuoteSchedule.phaseAt(evening), MarketPhase.afterClose);
      expect(LiveQuoteSchedule.phaseAt(nextMorning), MarketPhase.preOpen);
      expect(
        heatmapLiveModeAt(
          phase: LiveQuoteSchedule.phaseAt(evening),
          dataDate: _officialDate,
          now: evening,
        ),
        HeatmapLiveMode.afterClose,
      );
      expect(
        heatmapLiveModeAt(
          phase: LiveQuoteSchedule.phaseAt(nextMorning),
          dataDate: _officialDate,
          now: nextMorning,
        ),
        isNull,
      );
    });
  });

  group('heatmapLiveSymbols', () {
    test('登記上限加一個指數剛好是兩批 MIS 請求', () {
      expect(1 + HeatmapParams.liveTileLimit, 2 * ApiEndpoints.misBatchSize);
      expect(HeatmapParams.liveTileLimit, _limit);
    });

    test('沒有產業或產業沒有格子：空清單', () {
      for (final mode in HeatmapLiveMode.values) {
        expect(_symbols(_market([]), mode: mode), isEmpty);
        expect(_symbols(_market([_industry('甲業', [])]), mode: mode), isEmpty);
      }
    });

    group('盤中全市場', () {
      test('三個產業共 100 檔：全市場市值前 69，市值降冪', () {
        final groups = <List<HeatmapTile>>[[], [], []];
        for (var i = 0; i < 100; i++) {
          // 37 與 100 互質：市值是 1000～100000 的一個排列，且分散在三個產業
          groups[i % 3].add(_tile(_sym(i), cap: ((i * 37) % 100 + 1) * 1000.0));
        }
        final market = _market([
          _industry('甲業', groups[0]),
          _industry('乙業', groups[1]),
          _industry(null, groups[2]),
        ]);
        final symbols = _symbols(market);
        final caps = _capsOf(market);
        expect(symbols, hasLength(_limit));
        expect(symbols.toSet(), hasLength(_limit));
        expect([
          for (final s in symbols) caps[s],
        ], _capsDescending(100, 100 - _limit + 1));
      });

      test('市值相同：跨產業依代號升冪', () {
        final market = _market([
          _industry('甲業', [_tile('9905', cap: 500), _tile('9901', cap: 500)]),
          _industry('乙業', [_tile('9903', cap: 500), _tile('9902', cap: 700)]),
        ]);
        expect(_symbols(market), ['9902', '9901', '9903', '9905']);
      });

      test('市值相同的格子跨過上限：留下代號小的', () {
        final market = _market([
          _industry('甲業', [
            for (var i = 0; i < 70; i += 2) _tile(_sym(i), cap: 500),
          ]),
          _industry('乙業', [
            for (var i = 1; i < 70; i += 2) _tile(_sym(i), cap: 500),
          ]),
        ]);
        expect(_symbols(market), [for (var i = 0; i < _limit; i++) _sym(i)]);
      });

      test('不到 69 檔：全部', () {
        final market = _market([
          _industry('甲業', [
            for (var i = 0; i < 30; i++) _tile(_sym(i), cap: 1000.0 + i),
          ]),
          _industry('乙業', [
            for (var i = 30; i < 50; i++) _tile(_sym(i), cap: 1000.0 + i),
          ]),
        ]);
        final symbols = _symbols(market);
        expect(symbols, hasLength(50));
        expect(symbols.first, _sym(49));
        expect(symbols.last, _sym(0));
      });

      test('不看報價中心裡的報價（收盤報價也不排除）', () {
        final market = _market([
          _industry('甲業', [
            for (var i = 0; i < 80; i++) _tile(_sym(i), cap: (1000 - i) * 1.0),
          ]),
        ]);
        final entries = {
          for (var i = 0; i < 80; i++) _sym(i): _entry(_sym(i), closing: true),
        };
        expect(_symbols(market, entries: entries), [
          for (var i = 0; i < _limit; i++) _sym(i),
        ]);
      });
    });

    group('盤中放大', () {
      // 甲業 80 檔（市值 1000～80000 的排列）、乙業 10 檔（市值遠大於甲業）
      final market = _market([
        _industry('甲業', [
          for (var i = 0; i < 80; i++)
            _tile(_sym(i), cap: ((i * 37) % 80 + 1) * 1000.0),
        ]),
        _industry('乙業', [
          for (var i = 0; i < 10; i++)
            _tile(_sym(80 + i), cap: (200 + i) * 1000.0),
        ]),
      ]);
      final caps = _capsOf(market);
      final b = {for (var i = 80; i < 90; i++) _sym(i)};

      test('80 檔的產業：該產業的前 69，不被別的產業的大格子擠掉', () {
        final symbols = _symbols(market, zoom: '甲業');
        expect(symbols, hasLength(_limit));
        expect(symbols.toSet().intersection(b), isEmpty);
        expect([
          for (final s in symbols) caps[s],
        ], _capsDescending(80, 80 - _limit + 1));
      });

      test('10 檔的產業：10 檔，市值降冪', () {
        final symbols = _symbols(market, zoom: '乙業');
        expect(symbols.toSet(), b);
        expect([for (final s in symbols) caps[s]], _capsDescending(209, 200));
      });

      test('放大的產業不存在（重讀後消失）：視同全市場', () {
        final whole = _symbols(market);
        expect(_symbols(market, zoom: '消失業'), whole);
        // 全市場是乙業 10 檔加甲業前 59 檔
        expect(
          [for (final s in whole) caps[s]],
          [..._capsDescending(209, 200), ..._capsDescending(80, 22)],
        );
      });

      test('未分類的產業用空字串識別', () {
        final uncategorized = _market([
          _industry('甲業', [_tile('9901', cap: 900), _tile('9902', cap: 800)]),
          _industry(null, [_tile('9903', cap: 100), _tile('9904', cap: 300)]),
        ]);
        expect(_symbols(uncategorized, zoom: ''), ['9904', '9903']);
        expect(_symbols(uncategorized), ['9901', '9902', '9904', '9903']);
      });
    });

    group('收盤後', () {
      // 兩個產業共 80 檔，市值依序號降冪：序號就是市值名次
      final market = _market([
        _industry('甲業', [
          for (var i = 0; i < 80; i += 2) _tile(_sym(i), cap: (1000 - i) * 1.0),
        ]),
        _industry('乙業', [
          for (var i = 1; i < 80; i += 2) _tile(_sym(i), cap: (1000 - i) * 1.0),
        ]),
      ]);

      Map<String, LiveQuoteEntry> closingToday(Iterable<int> indexes) => {
        for (final i in indexes) _sym(i): _entry(_sym(i), closing: true),
      };

      test('前 69 大裡 5 檔已有今天的收盤報價：由第 70～74 名補上', () {
        const acquired = {0, 10, 20, 30, 68};
        final symbols = _symbols(
          market,
          mode: HeatmapLiveMode.afterClose,
          entries: closingToday(acquired),
        );
        expect(symbols, [
          for (var i = 0; i < 74; i++)
            if (!acquired.contains(i)) _sym(i),
        ]);
        expect(symbols, hasLength(_limit));
      });

      test('沒有任何收盤報價：市值前 69', () {
        expect(_symbols(market, mode: HeatmapLiveMode.afterClose), [
          for (var i = 0; i < _limit; i++) _sym(i),
        ]);
      });

      test('放大與否結果相同（含放大的產業已不存在）', () {
        const acquired = {0, 1, 2};
        final entries = closingToday(acquired);
        final expected = _symbols(
          market,
          mode: HeatmapLiveMode.afterClose,
          entries: entries,
        );
        for (final zoom in ['甲業', '乙業', '消失業']) {
          expect(
            _symbols(
              market,
              mode: HeatmapLiveMode.afterClose,
              zoom: zoom,
              entries: entries,
            ),
            expected,
            reason: '放大 $zoom',
          );
        }
        expect(expected, [for (var i = 3; i < 72; i++) _sym(i)]);
      });

      test('前一天的收盤報價、不是收盤報價的、別檔的報價都不算已取得', () {
        final small = _market([
          _industry('甲業', [
            for (var i = 0; i < 10; i++) _tile(_sym(i), cap: (1000 - i) * 1.0),
          ]),
        ]);
        final symbols = _symbols(
          small,
          mode: HeatmapLiveMode.afterClose,
          entries: {
            // 前一天的收盤報價
            '9900': _entry('9900', date: DateTime(2026, 11, 6), closing: true),
            // 今天但不是收盤報價
            '9901': _entry('9901'),
            // 今天的收盤報價，日期帶時分也算同一天
            '9902': _entry(
              '9902',
              date: DateTime(2026, 11, 9, 13, 30),
              closing: true,
            ),
            // 不在這張圖上的股票
            '9999': _entry('9999', closing: true),
          },
        );
        expect(symbols, [
          for (var i = 0; i < 10; i++)
            if (i != 2) _sym(i),
        ]);
      });

      test('整個市場不到 69 檔：全部（扣掉已取得的）', () {
        final small = _market([
          _industry('甲業', [
            for (var i = 0; i < 50; i++) _tile(_sym(i), cap: (1000 - i) * 1.0),
          ]),
        ]);
        expect(_symbols(small, mode: HeatmapLiveMode.afterClose), [
          for (var i = 0; i < 50; i++) _sym(i),
        ]);
        expect(
          _symbols(
            small,
            mode: HeatmapLiveMode.afterClose,
            entries: closingToday([4, 7]),
          ),
          [
            for (var i = 0; i < 50; i++)
              if (i != 4 && i != 7) _sym(i),
          ],
        );
      });

      test('市值相同：跨產業依代號升冪', () {
        final tied = _market([
          _industry('甲業', [_tile('9905', cap: 500), _tile('9901', cap: 500)]),
          _industry('乙業', [_tile('9903', cap: 500), _tile('9902', cap: 700)]),
        ]);
        expect(
          _symbols(
            tied,
            mode: HeatmapLiveMode.afterClose,
            entries: closingToday([]),
          ),
          ['9902', '9901', '9903', '9905'],
        );
      });
    });
  });
}

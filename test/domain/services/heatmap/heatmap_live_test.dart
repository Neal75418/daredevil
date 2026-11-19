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
  String? industry,
}) => HeatmapTile(
  symbol: symbol,
  name: '測試$symbol',
  industry: industry,
  close: 100,
  marketCap: cap,
  change: change,
  isMine: mine,
);

HeatmapMarketData _official(List<HeatmapTile> tiles, {int excluded = 0}) =>
    HeatmapMarketData(
      market: MarketCode.twse,
      dataDate: _officialDate,
      tiles: tiles,
      capCoverage: 1,
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

/// 預設：[entries] 的每一檔都登記、都在 [fresh]；報價中心沒有放棄任何一檔
HeatmapMarketData _overlay(
  HeatmapMarketData official,
  Map<String, LiveQuoteEntry> entries, {
  HeatmapLiveMode mode = HeatmapLiveMode.intraday,
  Map<String, LiveSymbolStatus> status = const {},
  Set<String>? registered,
  Set<String>? fresh,
  Set<String> givenUp = const {},
}) => overlayHeatmapLive(
  official,
  mode: mode,
  entries: entries,
  symbolStatus: status,
  registered: registered ?? entries.keys.toSet(),
  fresh: fresh ?? entries.keys.toSet(),
  closingGivenUp: givenUp,
  today: _today,
);

HeatmapTile _only(HeatmapMarketData data) => data.tiles.single;

HeatmapTile _tileOf(HeatmapMarketData data, String symbol) =>
    data.tiles.firstWhere((t) => t.symbol == symbol);

TileChange _changeOf(HeatmapMarketData data, [String symbol = '9901']) =>
    _tileOf(data, symbol).change;

double _percentOf(HeatmapMarketData data, [String symbol = '9901']) {
  final change = _changeOf(data, symbol);
  expect(change, isA<TileChangeValue>());
  return (change as TileChangeValue).percent;
}

/// 虛構代號 99NN（NN 是兩位數序號，0～99）
String _sym(int i) => '99${i.toString().padLeft(2, '0')}';

/// 正式資料：格子照市值降冪、同值代號升冪排好（與 `buildHeatmapMarket` 的輸出相同）
HeatmapMarketData _market(List<HeatmapTile> tiles) {
  final sorted = [...tiles]
    ..sort((a, b) {
      final byCap = b.marketCap.compareTo(a.marketCap);
      return byCap != 0 ? byCap : a.symbol.compareTo(b.symbol);
    });
  return HeatmapMarketData(
    market: MarketCode.twse,
    dataDate: _officialDate,
    tiles: sorted,
    capCoverage: 1,
    excludedForShares: 0,
  );
}

/// 登記清單的上限：兩批 MIS 請求扣掉一個指數
const _limit = 69;

List<String> _symbols(
  HeatmapMarketData official, {
  HeatmapLiveMode mode = HeatmapLiveMode.intraday,
  Map<String, LiveQuoteEntry> entries = const {},
  Set<String> givenUp = const {},
}) => heatmapLiveSymbols(
  official,
  mode: mode,
  entries: entries,
  closingGivenUp: givenUp,
  today: _today,
);

/// 市值依序號降冪的 [count] 檔：序號就是市值名次
HeatmapMarketData _ranked(int count) => _market([
  for (var i = 0; i < count; i++) _tile(_sym(i), cap: (1000 - i) * 1.0),
]);

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
    });

    test('y 是參考價（除權息日）：以 y 為基準', () {
      final data = _overlay(_official([_tile('9901')]), {
        '9901': _entry('9901', price: 99.75, y: 95),
      });
      expect(_percentOf(data), closeTo(5, 1e-9));
    });

    test('🚨 不改名稱、代號、產業別、自選標記（上色與空心的格子都一樣）', () {
      final data = _overlay(
        _official([
          _tile('9901', mine: true, industry: '半導體業'),
          _tile('9902', mine: true, industry: '航運業'),
        ]),
        {'9901': _entry('9901')},
        registered: {'9901', '9902'},
      );
      final colored = _tileOf(data, '9901');
      expect(colored.change, isA<TileChangeValue>());
      expect(colored.symbol, '9901');
      expect(colored.name, '測試9901');
      expect(colored.industry, '半導體業');
      expect(colored.isMine, isTrue);
      final hollow = _tileOf(data, '9902');
      expect(hollow.change, isA<TileChangeHollow>());
      expect(hollow.name, '測試9902');
      expect(hollow.industry, '航運業');
      expect(hollow.isMine, isTrue);
    });

    group('登記了但不在 fresh', () {
      HeatmapMarketData run(LiveSymbolStatus? status) => _overlay(
        _official([_tile('9901')]),
        // 中心有今天的成交報價也不用：fresh（登記前後拿到過）才算
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

      test('格子不套即時價：顯示價是正式資料的收盤', () {
        expect(_only(run(LiveSymbolStatus.noQuote)).close, 100);
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
              industry: null,
              close: close,
              marketCap: cap,
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
      Set<String> givenUp = const {},
    }) => _overlay(
      _official([_tile('9901')]),
      {'9901': ?entry},
      mode: HeatmapLiveMode.afterClose,
      registered: registered,
      fresh: fresh,
      status: status,
      givenUp: givenUp,
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

    group('報價中心已放棄（closingGivenUp）', () {
      test('🚨 已放棄、沒有收盤報價：收盤沒撮合（不附正式資料的漲跌）', () {
        for (final entry in [null, _entry('9901')]) {
          final data = run(entry: entry, givenUp: {'9901'});
          expect(
            _changeOf(data),
            const TileChangeHollow(HollowReason.noClosingMatch),
            reason: '$entry',
          );
          expect(_only(data).close, 100, reason: '顯示價維持正式資料');
        }
      });

      test('沒放棄：尚未取得收盤報價', () {
        final data = run(entry: _entry('9901'), givenUp: {'9902'});
        expect(
          _changeOf(data),
          const TileChangeHollow(HollowReason.noClosingQuote),
        );
      });

      test('🚨 有今天的收盤報價即使在集合裡也上色（收盤報價先於放棄）', () {
        final data = run(
          entry: _entry('9901', price: 102, closing: true),
          givenUp: {'9901'},
        );
        expect(_percentOf(data), closeTo(2, 1e-9));
      });

      test('前一天的收盤報價不算：收盤沒撮合', () {
        final data = run(
          entry: _entry('9901', date: DateTime(2026, 11, 6), closing: true),
          givenUp: {'9901'},
        );
        expect(
          _changeOf(data),
          const TileChangeHollow(HollowReason.noClosingMatch),
        );
      });

      test('🚨 盤中不看它：登記且 fresh 的照常上色、沒登記的照常未即時', () {
        final official = _official([_tile('9901'), _tile('9902')]);
        final data = _overlay(
          official,
          {'9901': _entry('9901')},
          registered: {'9901'},
          fresh: {'9901'},
          givenUp: {'9901', '9902'},
        );
        expect(_percentOf(data, '9901'), closeTo(3, 1e-9));
        expect(
          _changeOf(data, '9902'),
          isA<TileChangeHollow>().having(
            (c) => c.reason,
            'reason',
            HollowReason.notLive,
          ),
        );
      });
    });
  });

  group('整體', () {
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

    test('🚨 市場、資料日、頁尾檔數、覆蓋率、格子順序、市值都與正式資料相同', () {
      final official = HeatmapMarketData(
        market: MarketCode.tpex,
        dataDate: _officialDate,
        tiles: [
          _tile('9903', cap: 400),
          _tile('9901', cap: 300),
          _tile(
            '9902',
            cap: 200,
            change: const TileChangeHollow(HollowReason.noChangeData),
          ),
        ],
        capCoverage: 0.52,
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
      expect(data.capCoverage, 0.52);
      expect(
        [for (final t in data.tiles) (t.symbol, t.marketCap)],
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

    test('沒有格子：空清單', () {
      for (final mode in HeatmapLiveMode.values) {
        expect(_symbols(_market([]), mode: mode), isEmpty);
      }
    });

    Map<String, LiveQuoteEntry> closingToday(Iterable<int> indexes) => {
      for (final i in indexes) _sym(i): _entry(_sym(i), closing: true),
    };

    group('盤中', () {
      test('圖上的檔全部登記，照正式資料的順序', () {
        expect(_symbols(_ranked(30)), [for (var i = 0; i < 30; i++) _sym(i)]);
      });

      test('🚨 照 tiles 的順序（市值），不是代號順序', () {
        final market = _market([
          _tile('9903', cap: 300),
          _tile('9901', cap: 200),
          _tile('9902', cap: 100),
        ]);
        for (final mode in HeatmapLiveMode.values) {
          expect(_symbols(market, mode: mode), ['9903', '9901', '9902']);
        }
      });

      test('🚨 超過登記上限時只登記前 69 檔', () {
        expect(_symbols(_ranked(80)), [
          for (var i = 0; i < _limit; i++) _sym(i),
        ]);
      });

      test('不看報價中心裡的報價（收盤報價也不排除）', () {
        expect(
          _symbols(
            _ranked(30),
            entries: closingToday([for (var i = 0; i < 30; i++) i]),
          ),
          [for (var i = 0; i < 30; i++) _sym(i)],
        );
      });

      test('🚨 不看 closingGivenUp（今天放棄的照常登記）', () {
        expect(
          _symbols(
            _ranked(30),
            givenUp: {for (var i = 0; i < 10; i++) _sym(i)},
          ),
          [for (var i = 0; i < 30; i++) _sym(i)],
        );
      });
    });

    group('收盤後', () {
      final market = _ranked(30);

      test('沒有任何收盤報價：圖上全部', () {
        expect(_symbols(market, mode: HeatmapLiveMode.afterClose), [
          for (var i = 0; i < 30; i++) _sym(i),
        ]);
      });

      test('已有今天收盤報價的移出', () {
        const acquired = {0, 10, 29};
        expect(
          _symbols(
            market,
            mode: HeatmapLiveMode.afterClose,
            entries: closingToday(acquired),
          ),
          [
            for (var i = 0; i < 30; i++)
              if (!acquired.contains(i)) _sym(i),
          ],
        );
      });

      test('前一天的收盤報價、不是收盤報價的、別檔的報價都不算已取得', () {
        final symbols = _symbols(
          _ranked(10),
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

      test('🚨 報價中心已放棄的移出；與已取得的一起扣掉', () {
        const givenUp = {1, 5, 29};
        expect(
          _symbols(
            market,
            mode: HeatmapLiveMode.afterClose,
            entries: closingToday([0, 2]),
            givenUp: {for (final i in givenUp) _sym(i)},
          ),
          [
            for (var i = 0; i < 30; i++)
              if (!givenUp.contains(i) && i != 0 && i != 2) _sym(i),
          ],
        );
      });

      test('全部都放棄或已取得：空清單', () {
        expect(
          _symbols(
            market,
            mode: HeatmapLiveMode.afterClose,
            entries: closingToday([for (var i = 0; i < 30; i += 2) i]),
            givenUp: {for (var i = 1; i < 30; i += 2) _sym(i)},
          ),
          isEmpty,
        );
      });

      test('🚨 超過登記上限：扣掉已取得與放棄的之後取前 69 檔', () {
        const acquired = {0, 10, 20};
        const givenUp = {30, 68};
        final symbols = _symbols(
          _ranked(80),
          mode: HeatmapLiveMode.afterClose,
          entries: closingToday(acquired),
          givenUp: {for (final i in givenUp) _sym(i)},
        );
        expect(symbols, [
          for (var i = 0; i < 74; i++)
            if (!acquired.contains(i) && !givenUp.contains(i)) _sym(i),
        ]);
        expect(symbols, hasLength(_limit));
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_grouping.dart';

final _d1001 = DateTime(2026, 10, 1);
final _d1015 = DateTime(2026, 10, 15);

/// 沒傳 foreign 時用預設的 1000 股（明確傳 null 表示沒有外資持股股數）
const _defaultForeign = Object();

HeatmapStockInput _stock(
  String symbol, {
  String? industry = '測試業',
  double close = 100,
  double? priceChange = 1,
  Object? foreign = _defaultForeign,
  HeatmapShares? insider,
}) => HeatmapStockInput(
  symbol: symbol,
  name: '測試$symbol',
  industry: industry,
  close: close,
  priceChange: priceChange,
  foreign: identical(foreign, _defaultForeign)
      ? (shares: 1000, date: _d1001)
      : _asShares(foreign),
  insider: insider,
);

/// 經過 Object? 參數的記錄字面值，整數股數會推論成 int
HeatmapShares? _asShares(Object? value) {
  final v = value as ({num shares, DateTime date})?;
  return v == null ? null : (shares: v.shares.toDouble(), date: v.date);
}

HeatmapMarketData _build(
  List<HeatmapStockInput> stocks, {
  String market = MarketCode.twse,
  Set<String> mine = const {},
}) => buildHeatmapMarket(
  HeatmapMarketInput(
    market: market,
    dataDate: DateTime(2026, 10, 6),
    stocks: stocks,
    mine: mine,
  ),
);

List<String> _symbols(HeatmapMarketData data) => [
  for (final t in data.tiles) t.symbol,
];

/// 虛構代號 99NN（NN 是兩位數序號）
String _sym(int i) => '99${i.toString().padLeft(2, '0')}';

void main() {
  group('resolveHeatmapShares', () {
    test('上市只用外資持股', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.twse,
          foreign: null,
          insider: (shares: 1000, date: _d1001),
        ),
        const SharesMissing(),
      );
    });

    test('上櫃取較新的一筆', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 1000, date: _d1001),
          insider: (shares: 1050, date: _d1015),
        ),
        const SharesOk(1050),
      );
    });

    test('上櫃同日用外資持股', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 1000, date: _d1001),
          insider: (shares: 1050, date: _d1001),
        ),
        const SharesOk(1000),
      );
    });

    test('上櫃相差恰 10% 仍可用、超過才不畫', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 900, date: _d1001),
          insider: (shares: 1000, date: _d1001),
        ),
        const SharesOk(900),
      );
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 1000, date: _d1001),
          insider: (shares: 1120, date: _d1015),
        ),
        const SharesInconsistent(),
      );
    });

    test('上櫃外資較新時用外資', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 1000, date: _d1015),
          insider: (shares: 1050, date: _d1001),
        ),
        const SharesOk(1000),
      );
    });

    test('上市股數 ≤ 0、負數、NaN、∞ 視同沒有', () {
      for (final v in [0.0, -1000.0, double.nan, double.infinity]) {
        expect(
          resolveHeatmapShares(
            market: MarketCode.twse,
            foreign: (shares: v, date: _d1001),
          ),
          const SharesMissing(),
          reason: '$v',
        );
      }
    });

    test('上櫃只有一個來源就用它', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: null,
          insider: (shares: 1050, date: _d1015),
        ),
        const SharesOk(1050),
      );
    });

    test('股數 ≤ 0 視同沒有', () {
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 0, date: _d1001),
          insider: null,
        ),
        const SharesMissing(),
      );
      // 一邊 ≤ 0 時不拿它來比 10%，直接用另一邊
      expect(
        resolveHeatmapShares(
          market: MarketCode.tpex,
          foreign: (shares: 0, date: _d1015),
          insider: (shares: 1000, date: _d1001),
        ),
        const SharesOk(1000),
      );
    });
  });

  group('heatmapChangePercent', () {
    test('漲跌幅＝漲跌／(收盤−漲跌)', () {
      expect(heatmapChangePercent(close: 105, priceChange: 5), 5.0);
      expect(
        heatmapChangePercent(close: 95, priceChange: -5),
        closeTo(-5, 1e-9),
      );
    });

    test('輸入都是有限值、計算溢位時回 null', () {
      // priceChange × 100 溢位成 ∞：只有最後的有限值檢查擋得住
      expect(heatmapChangePercent(close: 2e307, priceChange: 1e307), isNull);
    });

    test('漲跌空值與分母 ≤ 0 回 null', () {
      expect(heatmapChangePercent(close: 5, priceChange: null), isNull);
      expect(heatmapChangePercent(close: 5, priceChange: 5), isNull);
      expect(heatmapChangePercent(close: 5, priceChange: 6), isNull);
    });

    test('非有限值回 null', () {
      expect(
        heatmapChangePercent(
          close: double.infinity,
          priceChange: double.infinity,
        ),
        isNull,
      );
      expect(heatmapChangePercent(close: double.nan, priceChange: 1), isNull);
      expect(
        heatmapChangePercent(close: 100, priceChange: double.infinity),
        isNull,
      );
      expect(
        heatmapChangePercent(close: double.infinity, priceChange: 1),
        isNull,
      );
      // 輸入是 ∞：開頭的輸入檢查擋下
      expect(
        heatmapChangePercent(close: 1, priceChange: double.negativeInfinity),
        isNull,
      );
    });
  });

  group('buildHeatmapMarket', () {
    test('排除 ETF、上櫃ETF、存託憑證，且不計入頁尾', () {
      final data = _build([
        _stock('9901'),
        // 被排除的沒有股數：若先判股數才排除產業，頁尾會多算
        _stock('9902', industry: 'ETF', foreign: null),
        _stock('9903', industry: '上櫃ETF', foreign: null),
        _stock('9904', industry: '存託憑證', foreign: null),
      ]);
      expect(data.excludedForShares, 0);
      expect(_symbols(data), ['9901']);
    });

    test('缺股數與股數不一致計入頁尾、不畫', () {
      final data = _build(market: MarketCode.tpex, [
        _stock('9901'),
        _stock('9902', foreign: null),
        _stock(
          '9903',
          foreign: (shares: 1000, date: _d1001),
          insider: (shares: 1120, date: _d1015),
        ),
      ]);
      expect(data.excludedForShares, 2);
      expect(_symbols(data), ['9901']);
    });

    test('🚨 先排除再取市值前 30 檔', () {
      final data = _build([
        // 市值隨序號遞增：前 30 大是序號 34～5
        for (var i = 0; i < 35; i++)
          _stock(_sym(i), foreign: (shares: 1000 + i, date: _d1001)),
        // 市值比它們都大、但不畫的：先取前 30 才排除的話會占掉名額
        _stock('0050', industry: 'ETF', foreign: (shares: 1e9, date: _d1001)),
        _stock('9105', industry: '存託憑證', foreign: (shares: 1e9, date: _d1001)),
        _stock('9998', foreign: null),
      ]);
      expect(HeatmapParams.topTileCount, 30, reason: '前提：下面的名次照 30 檔寫');
      expect(_symbols(data), [for (var i = 34; i >= 5; i--) _sym(i)]);
      expect(data.excludedForShares, 1);
    });

    test('🚨 覆蓋率＝圖上的市值 ÷ 全部可畫股票的市值（不畫的不算）', () {
      final data = _build([
        for (var i = 0; i < 35; i++) _stock(_sym(i)),
        _stock('0050', industry: 'ETF', foreign: (shares: 1e9, date: _d1001)),
      ]);
      expect(data.tiles, hasLength(30));
      expect(data.capCoverage, closeTo(30 / 35, 1e-12));
    });

    test('不足 30 檔：全部都畫，覆蓋率恰為 1.0', () {
      final data = _build([
        _stock('9901', close: 0.1),
        _stock('9902', close: 0.2),
        _stock('9903', close: 0.3),
      ]);
      expect(_symbols(data), ['9903', '9902', '9901']);
      expect(data.capCoverage, 1.0);
    });

    test('漲跌空值畫空心', () {
      final data = _build([_stock('9901', priceChange: null)]);
      expect(
        data.tiles.single.change,
        const TileChangeHollow(HollowReason.noChangeData),
      );
    });

    test('市值溢位的股票計入頁尾', () {
      final data = _build([
        _stock('9901'),
        _stock('9902', close: 1e10, foreign: (shares: 1e300, date: _d1001)),
      ]);
      expect(_symbols(data), ['9901']);
      expect(data.excludedForShares, 1);
    });

    test('新股首日大漲照常上色', () {
      final data = _build([_stock('9901', close: 22.393, priceChange: 12.393)]);
      final change = data.tiles.single.change;
      expect(change, isA<TileChangeValue>());
      expect((change as TileChangeValue).percent, closeTo(123.93, 1e-6));
    });

    test('grouping 不先四捨五入', () {
      final data = _build([_stock('9901', close: 3.07, priceChange: 0.07)]);
      final change = data.tiles.single.change;
      expect((change as TileChangeValue).percent, closeTo(2.3333, 1e-4));
      expect(change.percent, isNot(HeatmapParams.roundPercent(change.percent)));
    });

    test('收盤 ≤ 0 略過且不計頁尾', () {
      // 略過的沒有股數：若先判股數才略過，頁尾會多算
      final data = _build([
        _stock('9901'),
        _stock('9902', close: 0, foreign: null),
        _stock('9903', close: double.infinity, foreign: null),
        _stock('9904', close: double.nan, foreign: null),
      ]);
      expect(_symbols(data), ['9901']);
      expect(data.excludedForShares, 0);
    });

    test('股數不是有限數計入頁尾', () {
      final data = _build([
        _stock('9901'),
        _stock('9902', foreign: (shares: double.infinity, date: _d1001)),
      ]);
      expect(_symbols(data), ['9901']);
      expect(data.excludedForShares, 1);
    });

    test('上櫃股數 ≤ 0 的股票計入頁尾', () {
      final data = _build(market: MarketCode.tpex, [
        _stock('9901'),
        _stock('9902', foreign: (shares: 0, date: _d1001)),
      ]);
      expect(_symbols(data), ['9901']);
      expect(data.excludedForShares, 1);
    });

    test('公司行動空窗照用董監股數', () {
      // 照 5904 面額 10 元改 1 元的數值：董監表已是新股數，價格仍是舊價
      final data = _build(market: MarketCode.tpex, [
        _stock(
          '9904',
          close: 720,
          foreign: null,
          insider: (shares: 1064438260, date: DateTime(2026, 7, 15)),
        ),
      ]);
      expect(data.tiles.single.marketCap, 720 * 1064438260);
    });

    test('自選或持股標記', () {
      final data = _build([_stock('9901'), _stock('9902')], mine: {'9901'});
      expect(
        {for (final t in data.tiles) t.symbol: t.isMine},
        {'9901': true, '9902': false},
      );
    });

    test('排序穩定：市值降冪，同值依代號；不看產業', () {
      final stocks = [
        _stock('9903', industry: 'B業'),
        _stock('9902', industry: 'A業'),
        _stock('9901', industry: 'A業'),
        _stock('9904', industry: 'B業'),
        _stock('9905', industry: 'C業', foreign: (shares: 5000, date: _d1001)),
      ];
      final data = _build(stocks);
      expect(_symbols(data), ['9905', '9901', '9902', '9903', '9904']);
      expect(_build(stocks), data);
    });

    test('🚨 每格帶產業別；空字串與 null 都是 null（未分類）', () {
      final data = _build([
        _stock('9901', industry: '半導體業'),
        _stock('9902', industry: ''),
        _stock('9903', industry: null),
      ]);
      expect(
        {for (final t in data.tiles) t.symbol: t.industry},
        {'9901': '半導體業', '9902': null, '9903': null},
      );
    });

    test('0 檔', () {
      final data = _build([]);
      expect(data.tiles, isEmpty);
      expect(data.capCoverage, 0);
      expect(data.excludedForShares, 0);
    });
  });

  group('heatmapTopTiles', () {
    HeatmapTile tile(String symbol, double cap) => HeatmapTile(
      symbol: symbol,
      name: symbol,
      industry: null,
      close: 100,
      marketCap: cap,
      change: const TileChangeHollow(HollowReason.noChangeData),
      isMine: false,
    );
    List<String> symbols(List<HeatmapTile> tiles) => [
      for (final t in tiles) t.symbol,
    ];

    test('🚨 市值由大到小取前 count 檔；同值依代號由小到大', () {
      // D 排在 B 前面傳入：筆數少時排序是穩定的，照代號順序傳入的話不比
      // 代號也會得到同樣的結果
      final result = heatmapTopTiles([
        tile('A', 50),
        tile('D', 30),
        tile('B', 30),
        tile('C', 20),
      ], count: 3);
      expect(symbols(result.tiles), ['A', 'B', 'D']);
    });

    test('🚨 不足 count 檔時全部回傳，覆蓋率恰為 1.0', () {
      // 市值不是整數、由小到大傳入：取到的與全部的若用不同順序加總，比例
      // 會差一個位元，畫面就把 100% 寫成 99%
      final result = heatmapTopTiles([
        tile('A', 0.1),
        tile('B', 0.2),
        tile('C', 0.3),
      ], count: 30);
      expect(symbols(result.tiles), ['C', 'B', 'A']);
      expect(result.coverage, 1.0);
    });

    test('覆蓋率＝取到的市值 ÷ 全部市值', () {
      final result = heatmapTopTiles([
        tile('A', 60),
        tile('B', 30),
        tile('C', 10),
      ], count: 2);
      expect(symbols(result.tiles), ['A', 'B']);
      expect(result.coverage, closeTo(0.9, 1e-12));
    });

    test('沒有任何一檔，或全部市值不是有限正數：空清單、覆蓋率 0', () {
      for (final all in [
        const <HeatmapTile>[],
        [tile('A', 0)],
        [tile('A', double.infinity), tile('B', 1)],
      ]) {
        final result = heatmapTopTiles(all, count: 30);
        expect(result.tiles, isEmpty, reason: '$all');
        expect(result.coverage, 0, reason: '$all');
      }
    });
  });
}

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
  for (final i in data.industries)
    for (final t in i.tiles) t.symbol,
];

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
      expect(data.industries.map((i) => i.name), ['測試業']);
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

    test('漲跌空值畫空心', () {
      final data = _build([_stock('9901', priceChange: null)]);
      expect(
        data.industries.single.tiles.single.change,
        const TileChangeHollow(HollowReason.noChangeData),
      );
    });

    test('格子帶平盤市值：股數 × (收盤 − 漲跌)；漲跌空值為 0', () {
      final data = _build([
        _stock(
          '9901',
          close: 110,
          priceChange: 10,
          foreign: (shares: 1000, date: _d1001),
        ),
        _stock('9902', priceChange: null),
      ]);
      final tiles = {for (final t in data.industries.single.tiles) t.symbol: t};
      expect(tiles['9901']!.baseCap, closeTo(100000, 1e-9));
      expect(tiles['9902']!.baseCap, 0);
    });

    test('產業漲跌以平盤市值加權、空心成員不計', () {
      final data = _build([
        // 平盤市值 300（平盤價 100 × 3 股）、+2%，今天市值 306
        _stock(
          '9901',
          close: 102,
          priceChange: 2,
          foreign: (shares: 3, date: _d1001),
        ),
        // 平盤市值 100、−2%，今天市值 98
        _stock(
          '9902',
          close: 98,
          priceChange: -2,
          foreign: (shares: 1, date: _d1001),
        ),
        // 今天市值 600、空心
        _stock(
          '9903',
          close: 100,
          priceChange: null,
          foreign: (shares: 6, date: _d1001),
        ),
      ]);
      final industry = data.industries.single;
      // (300 × 2 + 100 × −2) ÷ (300 + 100)
      expect(industry.weightedChangePercent, closeTo(1.0, 1e-9));
      expect(industry.marketCap, closeTo(1004, 1e-9));
      // 格子依今天市值降冪（依收盤排會是 9901、9903、9902）
      expect(industry.tiles.map((t) => t.symbol), ['9903', '9901', '9902']);
    });

    test('平盤價與漲跌幅都不對稱時，加權用平盤市值', () {
      final data = _build([
        // 平盤 50 × 6 股＝300、+10%
        _stock(
          '9901',
          close: 55,
          priceChange: 5,
          foreign: (shares: 6, date: _d1001),
        ),
        // 平盤 200 × 0.5 股＝100、−4%
        _stock(
          '9902',
          close: 192,
          priceChange: -8,
          foreign: (shares: 0.5, date: _d1001),
        ),
      ]);
      // (300 × 10 + 100 × −4) ÷ 400
      expect(data.industries.single.weightedChangePercent, closeTo(6.5, 1e-9));
    });

    test('跌幅極接近 −100% 的壞資料不讓產業漲跌變成 NaN', () {
      final data = _build([
        _stock('9901', close: 1e-20, priceChange: -1),
        _stock('9902', close: 102, priceChange: 2),
      ]);
      // (1000 × −100 + 100000 × 2) ÷ (1000 + 100000)
      expect(
        data.industries.single.weightedChangePercent,
        closeTo(100 / 101, 1e-9),
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

    test('平盤市值溢位時產業漲跌為 null，不是 NaN', () {
      // 收盤 1、漲跌 −1e300：漲跌幅約 −100%（有限），平盤市值 1e10 × 1e300 溢位
      final data = _build([
        _stock(
          '9901',
          close: 1,
          priceChange: -1e300,
          foreign: (shares: 1e10, date: _d1001),
        ),
      ]);
      expect(data.industries.single.weightedChangePercent, isNull);
    });

    test('平盤市值相同、漲跌相反的產業加權漲跌為 0', () {
      final data = _build([
        _stock(
          '9901',
          close: 110,
          priceChange: 10,
          foreign: (shares: 1, date: _d1001),
        ),
        _stock(
          '9902',
          close: 90,
          priceChange: -10,
          foreign: (shares: 1, date: _d1001),
        ),
      ]);
      expect(data.industries.single.weightedChangePercent, closeTo(0, 1e-9));
    });

    test('全部空心的產業沒有加權漲跌', () {
      final data = _build([
        _stock('9901', priceChange: null),
        _stock('9902', priceChange: null),
      ]);
      expect(data.industries.single.weightedChangePercent, isNull);
    });

    test('新股首日大漲照常上色', () {
      final data = _build([_stock('9901', close: 22.393, priceChange: 12.393)]);
      final change = data.industries.single.tiles.single.change;
      expect(change, isA<TileChangeValue>());
      expect((change as TileChangeValue).percent, closeTo(123.93, 1e-6));
    });

    test('grouping 不先四捨五入', () {
      final data = _build([_stock('9901', close: 3.07, priceChange: 0.07)]);
      final change = data.industries.single.tiles.single.change;
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
      expect(data.industries.single.tiles.single.marketCap, 720 * 1064438260);
    });

    test('自選或持股標記', () {
      final data = _build([_stock('9901'), _stock('9902')], mine: {'9901'});
      final tiles = {
        for (final t in data.industries.single.tiles) t.symbol: t.isMine,
      };
      expect(tiles, {'9901': true, '9902': false});
    });

    test('排序穩定：市值降冪，同值時產業依名稱、格子依代號', () {
      final stocks = [
        _stock('9903', industry: 'B業'),
        _stock('9902', industry: 'A業'),
        _stock('9901', industry: 'A業'),
        _stock('9904', industry: 'B業'),
        _stock('9905', industry: 'C業', foreign: (shares: 5000, date: _d1001)),
      ];
      final data = _build(stocks);
      expect(data.industries.map((i) => i.name), ['C業', 'A業', 'B業']);
      expect(data.industries[1].tiles.map((t) => t.symbol), ['9901', '9902']);
      expect(_build(stocks), data);
    });

    test('產業別空白歸未分類', () {
      final data = _build([
        _stock('9901', industry: ''),
        _stock('9902', industry: null),
      ]);
      final industry = data.industries.single;
      expect(industry.name, isNull);
      expect(industry.key, '');
      expect(industry.tiles, hasLength(2));
    });

    test('0 檔', () {
      final data = _build([]);
      expect(data.industries, isEmpty);
      expect(data.excludedForShares, 0);
    });
  });

  group('heatmapWeightedChange', () {
    HeatmapTile tile(
      String symbol, {
      required double baseCap,
      required TileChange change,
    }) => HeatmapTile(
      symbol: symbol,
      name: symbol,
      close: 100,
      marketCap: 1000,
      baseCap: baseCap,
      change: change,
      isMine: false,
    );

    test('平盤市值相同、各 ±10% 加權後為 0', () {
      final weighted = heatmapWeightedChange([
        tile('9901', baseCap: 1000, change: const TileChangeValue(10)),
        tile('9902', baseCap: 1000, change: const TileChangeValue(-10)),
      ]);
      expect(weighted, closeTo(0, 1e-12));
    });

    test('權重是平盤市值，不是格子的市值', () {
      // 兩格市值相同（1000），平盤市值 300 與 100
      final weighted = heatmapWeightedChange([
        tile('9901', baseCap: 300, change: const TileChangeValue(2)),
        tile('9902', baseCap: 100, change: const TileChangeValue(-2)),
      ]);
      expect(weighted, closeTo(1.0, 1e-12));
    });

    test('只有空心、或沒有格子：null', () {
      expect(
        heatmapWeightedChange([
          tile(
            '9901',
            baseCap: 0,
            change: const TileChangeHollow(HollowReason.noChangeData),
          ),
        ]),
        isNull,
      );
      expect(heatmapWeightedChange(const []), isNull);
    });

    test('平盤市值 0 的有值格子不參與', () {
      final weighted = heatmapWeightedChange([
        tile('9901', baseCap: 0, change: const TileChangeValue(50)),
        tile('9902', baseCap: 100, change: const TileChangeValue(2)),
      ]);
      expect(weighted, closeTo(2, 1e-12));
      // 只剩平盤市值 0 的有值格子：分母 0
      expect(
        heatmapWeightedChange([
          tile('9901', baseCap: 0, change: const TileChangeValue(50)),
        ]),
        isNull,
      );
    });

    test('平盤市值是負數或 NaN 的有值格子不參與', () {
      for (final bad in [-100.0, double.nan]) {
        final weighted = heatmapWeightedChange([
          tile('9901', baseCap: bad, change: const TileChangeValue(50)),
          tile('9902', baseCap: 100, change: const TileChangeValue(2)),
        ]);
        expect(weighted, closeTo(2, 1e-12), reason: 'baseCap = $bad');
      }
    });

    test('空心格子即使帶平盤市值也不參與', () {
      final weighted = heatmapWeightedChange([
        tile(
          '9901',
          baseCap: 900,
          change: const TileChangeHollow(HollowReason.noChangeData),
        ),
        tile('9902', baseCap: 100, change: const TileChangeValue(3)),
      ]);
      expect(weighted, closeTo(3, 1e-12));
    });

    test('結果不是有限數：null', () {
      expect(
        heatmapWeightedChange([
          tile('9901', baseCap: 1e300, change: const TileChangeValue(1e300)),
        ]),
        isNull,
      );
      expect(
        heatmapWeightedChange([
          tile(
            '9901',
            baseCap: double.infinity,
            change: const TileChangeValue(1),
          ),
        ]),
        isNull,
      );
    });
  });

  group('heatmapValueCoverage', () {
    HeatmapTile tile(double cap, TileChange change) => HeatmapTile(
      symbol: '9901',
      name: '測試',
      close: 100,
      marketCap: cap,
      baseCap: 0,
      change: change,
      isMine: false,
    );
    const hollow = TileChangeHollow(HollowReason.noChangeData);

    test('有漲跌值的市值占全部市值的比例', () {
      expect(
        heatmapValueCoverage([
          tile(300, const TileChangeValue(1)),
          tile(100, hollow),
        ]),
        0.75,
      );
    });

    test('全部有值時恰為 1.0（含無法精確表示的市值）', () {
      expect(
        heatmapValueCoverage([
          for (final cap in [0.1, 0.2, 0.3, 1e15 + 0.1, 7.7])
            tile(cap, const TileChangeValue(0)),
        ]),
        1.0,
      );
    });

    test('全部空心：0；沒有格子或總市值 ≤ 0：0', () {
      expect(heatmapValueCoverage([tile(100, hollow)]), 0);
      expect(heatmapValueCoverage(const []), 0);
      expect(heatmapValueCoverage([tile(0, const TileChangeValue(1))]), 0);
    });

    test('總市值溢位時回 0，不是 NaN', () {
      expect(
        heatmapValueCoverage([
          tile(1e308, const TileChangeValue(1)),
          tile(1e308, const TileChangeValue(1)),
        ]),
        0,
      );
    });
  });

  group('heatmapAllNoClosingMatch', () {
    HeatmapTile tile(TileChange change) => HeatmapTile(
      symbol: '9901',
      name: '測試',
      close: 100,
      marketCap: 100,
      baseCap: 0,
      change: change,
      isMine: false,
    );
    const unmatched = TileChangeHollow(HollowReason.noClosingMatch);

    test('每一格都是收盤沒撮合：true', () {
      expect(heatmapAllNoClosingMatch([tile(unmatched)]), isTrue);
      expect(
        heatmapAllNoClosingMatch([tile(unmatched), tile(unmatched)]),
        isTrue,
      );
    });

    test('混一格別的空心原因或有值：false', () {
      for (final change in [
        for (final reason in HollowReason.values)
          if (reason != HollowReason.noClosingMatch) TileChangeHollow(reason),
        const TileChangeValue(1),
      ]) {
        expect(
          heatmapAllNoClosingMatch([tile(unmatched), tile(change)]),
          isFalse,
          reason: '$change',
        );
      }
    });

    test('🚨 沒有格子：false', () {
      expect(heatmapAllNoClosingMatch(const []), isFalse);
    });
  });
}

import 'dart:convert';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_grouping.dart';

/// 熱力圖 × 報價中心整合測試的共用資料:上市規模的虛構市場(圖上只畫市值最大的
/// 幾檔),與證交所即時報價收盤後的假回應。

/// 上市規模
const heatmapFixtureStockCount = 1078;

/// 正式資料的日期(週五);測試的「今天」是下一個交易日 2026-11-09(週一)
final heatmapFixtureDataDate = DateTime(2026, 11, 6);

/// 市值第 [rank] 大(0 起算)的虛構代號。代號順序與市值順序刻意不同
/// (397 與 1,078 互質,乘上去取餘數是一對一)
String heatmapFixtureSymbolAt(int rank) =>
    'Z${((rank * 397) % heatmapFixtureStockCount + 1).toString().padLeft(4, '0')}';

/// 整個市場,市值由大到小
final heatmapFixtureByCap = [
  for (var r = 0; r < heatmapFixtureStockCount; r++) heatmapFixtureSymbolAt(r),
];

/// 圖上的檔:市值最大的 [HeatmapParams.topTileCount] 檔,由大到小
final heatmapFixtureTiles = heatmapFixtureByCap
    .take(HeatmapParams.topTileCount)
    .toList();

/// 圖上收盤那一盤沒撮合的 3 檔:市值名次 3、13、23
Set<String> heatmapFixtureUnmatched3() => {
  for (final rank in [3, 13, 23]) heatmapFixtureByCap[rank],
};

/// 正式資料:整個市場 1,078 檔(收盤 100、漲跌 −0.8;市值依名次遞減)經
/// `buildHeatmapMarket`,圖上是市值最大的那幾檔
HeatmapMarketData heatmapFixtureTwse() => buildHeatmapMarket(
  HeatmapMarketInput(
    market: MarketCode.twse,
    dataDate: heatmapFixtureDataDate,
    stocks: [
      for (var r = 0; r < heatmapFixtureStockCount; r++)
        HeatmapStockInput(
          symbol: heatmapFixtureByCap[r],
          name: '虛構${heatmapFixtureByCap[r]}',
          industry: '虛構產業${r % 8}',
          close: 100,
          priceChange: -0.8,
          foreign: (
            shares: (heatmapFixtureStockCount - r) * 1e7,
            date: heatmapFixtureDataDate,
          ),
        ),
    ],
    mine: const {},
  ),
);

/// 收盤後證交所的回應:每檔都回收盤報價(13:30:00 的成交 101,昨收 100);
/// [noTrade] 整天沒成交,回一列沒有成交價、試撮價與五檔的(解析時整列丟掉);
/// [unmatched] 收盤那一盤沒撮合,回 13:30:00 的列但沒有成交價、只有五檔
/// (代號數字是 5 的倍數的另帶試撮價)
String heatmapFixtureClosingResponse(
  List<String> symbols,
  DateTime now, {
  Set<String> noTrade = const {},
  Set<String> unmatched = const {},
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return jsonEncode({
    'rtcode': '0000',
    'msgArray': [
      for (final s in symbols)
        {
          'c': s,
          'z': noTrade.contains(s) || unmatched.contains(s) ? '-' : '101.0000',
          'pz': unmatched.contains(s) && int.parse(s.substring(1)) % 5 == 0
              ? '100.5000'
              : '-',
          'y': '100.0000',
          'd': '${now.year}${two(now.month)}${two(now.day)}',
          't': '13:30:00',
          'b': unmatched.contains(s) ? '100.0000_' : '-',
          'a': unmatched.contains(s) ? '101.0000_' : '-',
        },
    ],
  });
}

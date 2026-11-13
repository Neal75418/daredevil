import 'dart:convert';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/heatmap.dart';

/// 熱力圖收盤後滾動登記的共用測試資料:上市規模的虛構市場,與證交所即時報價
/// 收盤後的假回應。

/// 上市規模
const heatmapFixtureStockCount = 1078;

/// 正式資料的日期(週五);測試的「今天」是下一個交易日 2026-11-09(週一)
final heatmapFixtureDataDate = DateTime(2026, 11, 6);

/// 市值第 [rank] 大(0 起算)的虛構代號。代號順序與市值順序刻意不同
/// (397 與 1,078 互質,乘上去取餘數是一對一)
String heatmapFixtureSymbolAt(int rank) =>
    'Z${((rank * 397) % heatmapFixtureStockCount + 1).toString().padLeft(4, '0')}';

/// 市值由大到小
final heatmapFixtureByCap = [
  for (var r = 0; r < heatmapFixtureStockCount; r++) heatmapFixtureSymbolAt(r),
];

/// 收盤那一盤沒撮合的 100 檔:市值名次 3、13、…、993,散在市值各處,
/// 市值前 69 檔裡有 7 檔
Set<String> heatmapFixtureUnmatched100() => {
  for (var k = 0; k < 100; k++) heatmapFixtureByCap[3 + 10 * k],
};

/// 正式資料:收盤 100、漲跌 −0.8%;市值依名次遞減,名次輪流分到 8 個產業
HeatmapMarketData heatmapFixtureTwse() {
  const industryCount = 8;
  final members = [for (var k = 0; k < industryCount; k++) <HeatmapTile>[]];
  for (var r = 0; r < heatmapFixtureStockCount; r++) {
    final cap = (heatmapFixtureStockCount - r) * 1e9;
    members[r % industryCount].add(
      HeatmapTile(
        symbol: heatmapFixtureByCap[r],
        name: '虛構${heatmapFixtureByCap[r]}',
        close: 100,
        marketCap: cap,
        baseCap: cap * 100 / 99.2,
        change: const TileChangeValue(-0.8),
        isMine: false,
      ),
    );
  }
  final industries = [
    for (var k = 0; k < industryCount; k++)
      HeatmapIndustry(
        name: '虛構產業$k',
        marketCap: members[k].fold(0.0, (a, t) => a + t.marketCap),
        weightedChangePercent: -0.8,
        tiles: members[k],
      ),
  ]..sort((a, b) => b.marketCap.compareTo(a.marketCap));
  return HeatmapMarketData(
    market: MarketCode.twse,
    dataDate: heatmapFixtureDataDate,
    industries: industries,
    excludedForShares: 0,
  );
}

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

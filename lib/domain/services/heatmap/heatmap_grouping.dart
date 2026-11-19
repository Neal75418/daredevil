import 'dart:math' as math;

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/heatmap.dart';

/// 決定一檔股票用哪一個已發行股數。
///
/// - 股數 ≤ 0 或不是有限數（NaN、∞）視同沒有。
/// - 上市只用外資持股（每天、全市場）。
/// - 上櫃：兩個來源都有且相差超過 [HeatmapParams.shareMismatchRatio]
///   （以較大的一方為分母）→ 不一致；否則取日期較新的，同日取外資持股。
SharesResolution resolveHeatmapShares({
  required String market,
  HeatmapShares? foreign,
  HeatmapShares? insider,
}) {
  assert(
    market == MarketCode.twse || market == MarketCode.tpex,
    '未知的市場別 $market',
  );
  HeatmapShares? usable(HeatmapShares? s) =>
      s != null && s.shares > 0 && s.shares.isFinite ? s : null;
  final f = usable(foreign);
  if (market != MarketCode.tpex) {
    return f == null ? const SharesMissing() : SharesOk(f.shares);
  }
  final i = usable(insider);
  if (f != null && i != null) {
    final larger = math.max(f.shares, i.shares);
    if ((f.shares - i.shares).abs() / larger >
        HeatmapParams.shareMismatchRatio) {
      return const SharesInconsistent();
    }
    return SharesOk(i.date.isAfter(f.date) ? i.shares : f.shares);
  }
  final only = f ?? i;
  return only == null ? const SharesMissing() : SharesOk(only.shares);
}

/// 漲跌幅（%）＝漲跌 ÷（收盤 − 漲跌），與大盤統計同一公式。
///
/// 漲跌是空值、分母 ≤ 0、或收盤、漲跌、結果任何一個不是有限數時回 null
/// （畫空心）。不退回前一筆收盤：除權息日會把股息算成跌幅。
double? heatmapChangePercent({
  required double close,
  required double? priceChange,
}) {
  if (priceChange == null || !close.isFinite || !priceChange.isFinite) {
    return null;
  }
  final denominator = close - priceChange;
  if (!(denominator > 0)) return null;
  final percent = priceChange * 100 / denominator;
  return percent.isFinite ? percent : null;
}

/// 把一個市場的股票算成圖上的格子：先照排除規則篩掉不畫的，再取市值最大的
/// [HeatmapParams.topTileCount] 檔。「圖上最多幾檔」只在這裡決定，之後各層
/// 照 [HeatmapMarketData.tiles] 給的全部處理。
///
/// 頂層函式、輸入輸出都是純資料：計算太慢時可直接交給 `Isolate.run`。
HeatmapMarketData buildHeatmapMarket(HeatmapMarketInput input) {
  var excludedForShares = 0;
  final drawable = <HeatmapTile>[];
  for (final s in input.stocks) {
    if (HeatmapParams.isExcludedIndustry(s.industry)) continue;
    // 沒有可用收盤價（≤ 0、NaN、∞）視同不在圖上，不計頁尾
    if (!(s.close > 0) || !s.close.isFinite) continue;
    final shares = resolveHeatmapShares(
      market: input.market,
      foreign: s.foreign,
      insider: s.insider,
    );
    // 股數有問題（缺、不一致、或荒謬到市值溢位）：不畫，計入頁尾
    if (shares is! SharesOk) {
      excludedForShares++;
      continue;
    }
    final marketCap = s.close * shares.shares;
    if (!marketCap.isFinite) {
      excludedForShares++;
      continue;
    }
    final percent = heatmapChangePercent(
      close: s.close,
      priceChange: s.priceChange,
    );
    drawable.add(
      HeatmapTile(
        symbol: s.symbol,
        name: s.name,
        industry: (s.industry?.isEmpty ?? true) ? null : s.industry,
        close: s.close,
        marketCap: marketCap,
        change: percent == null
            ? const TileChangeHollow(HollowReason.noChangeData)
            : TileChangeValue(percent),
        isMine: input.mine.contains(s.symbol),
      ),
    );
  }

  final top = heatmapTopTiles(drawable, count: HeatmapParams.topTileCount);
  return HeatmapMarketData(
    market: input.market,
    dataDate: input.dataDate,
    tiles: top.tiles,
    capCoverage: top.coverage,
    excludedForShares: excludedForShares,
  );
}

/// 市值最大的 [count] 檔（[count] ≥ 0；市值降冪、同值依代號升冪），與它們的
/// 市值合計占 [all] 全部市值的比例（0～1）。
///
/// 兩個合計在同一個迴圈、同樣順序累加：全部都取時兩者逐位相同，比例恰為
/// 1.0。全部市值不是有限正數時回空清單與 0。
({List<HeatmapTile> tiles, double coverage}) heatmapTopTiles(
  Iterable<HeatmapTile> all, {
  required int count,
}) {
  assert(count >= 0, '檔數不能是負數，得到 $count');
  final sorted = all.toList()
    ..sort(_byCapThen((t) => t.marketCap, (t) => t.symbol));
  var taken = 0.0;
  var total = 0.0;
  for (var i = 0; i < sorted.length; i++) {
    final cap = sorted[i].marketCap;
    total += cap;
    if (i < count) taken += cap;
  }
  if (!(total > 0) || !total.isFinite) return (tiles: const [], coverage: 0);
  return (
    tiles: List.unmodifiable(sorted.take(count)),
    coverage: taken / total,
  );
}

/// 市值降冪、同值依 [key] 升冪
int Function(T, T) _byCapThen<T>(
  double Function(T) cap,
  String Function(T) key,
) => (a, b) {
  final byCap = cap(b).compareTo(cap(a));
  return byCap != 0 ? byCap : key(a).compareTo(key(b));
};

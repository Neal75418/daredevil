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

/// 把一個市場的股票分成產業區塊與格子。
///
/// 頂層函式、輸入輸出都是純資料：計算太慢時可直接交給 `Isolate.run`。
HeatmapMarketData buildHeatmapMarket(HeatmapMarketInput input) {
  var excludedForShares = 0;
  final byIndustry = <String?, List<HeatmapTile>>{};
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
    final priceChange = s.priceChange;
    final percent = heatmapChangePercent(
      close: s.close,
      priceChange: priceChange,
    );
    final industry = (s.industry?.isEmpty ?? true) ? null : s.industry;
    (byIndustry[industry] ??= []).add(
      HeatmapTile(
        symbol: s.symbol,
        name: s.name,
        close: s.close,
        marketCap: marketCap,
        // percent 非 null 時 priceChange 非 null、收盤 − 漲跌是正數（溢位由
        // 加權結果的 isFinite 擋下）。直接相乘、不從漲跌幅反推，極端輸入下
        // 才不會除以 0
        baseCap: percent == null || priceChange == null
            ? 0.0
            : shares.shares * (s.close - priceChange),
        change: percent == null
            ? const TileChangeHollow(HollowReason.noChangeData)
            : TileChangeValue(percent),
        isMine: input.mine.contains(s.symbol),
      ),
    );
  }

  final industries = [
    for (final MapEntry(key: name, value: tiles) in byIndustry.entries)
      _industry(name, tiles),
  ]..sort(_byCapThen((i) => i.marketCap, (i) => i.key));

  return HeatmapMarketData(
    market: input.market,
    dataDate: input.dataDate,
    industries: List.unmodifiable(industries),
    excludedForShares: excludedForShares,
  );
}

/// 以平盤市值（[HeatmapTile.baseCap]）加權的漲跌幅（%）：
/// Σ(平盤市值 × 漲跌幅) ÷ Σ 平盤市值。
///
/// 平盤市值是股數 × 平盤價，加權後等於這批股票總市值相對平盤的變化率，才近似
/// 它們對指數的影響；用今天的市值加權會偏向漲的成員（兩檔平盤市值相同、各
/// ±10% 會算出 +1%）。空心與平盤市值 ≤ 0 的格子不計；分母 ≤ 0 或結果不是
/// 有限數時回 null。
double? heatmapWeightedChange(Iterable<HeatmapTile> tiles) {
  var sum = 0.0;
  var base = 0.0;
  for (final t in tiles) {
    final change = t.change;
    if (change is! TileChangeValue || !(t.baseCap > 0)) continue;
    sum += t.baseCap * change.percent;
    base += t.baseCap;
  }
  if (!(base > 0)) return null;
  final weighted = sum / base;
  return weighted.isFinite ? weighted : null;
}

/// 有漲跌值的格子市值占全部市值的比例（0～1）。
///
/// 兩個合計在同一個迴圈、同樣順序累加：全部有值時兩者逐位相同，比例恰為
/// 1.0。全部市值 ≤ 0 或不是有限數時回 0。
double heatmapValueCoverage(Iterable<HeatmapTile> tiles) {
  var valued = 0.0;
  var total = 0.0;
  for (final t in tiles) {
    total += t.marketCap;
    if (t.change is TileChangeValue) valued += t.marketCap;
  }
  if (!(total > 0) || !total.isFinite) return 0;
  return valued / total;
}

/// 每一格都是收盤沒撮合（[HollowReason.noClosingMatch]）；沒有格子時為 false。
///
/// 產業、合併塊、小產業合併塊在算 [heatmapValueCoverage] 的同一處算出並存成
/// 欄位，畫面只讀欄位：區塊沒有漲跌值時據此改寫「收盤沒撮合」。
bool heatmapAllNoClosingMatch(Iterable<HeatmapTile> tiles) =>
    tiles.isNotEmpty &&
    tiles.every(
      (t) => switch (t.change) {
        TileChangeHollow(reason: HollowReason.noClosingMatch) => true,
        _ => false,
      },
    );

HeatmapIndustry _industry(String? name, List<HeatmapTile> tiles) {
  tiles.sort(_byCapThen((t) => t.marketCap, (t) => t.symbol));
  return HeatmapIndustry(
    name: name,
    marketCap: tiles.fold(0.0, (a, t) => a + t.marketCap),
    weightedChangePercent: heatmapWeightedChange(tiles),
    tiles: List.unmodifiable(tiles),
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

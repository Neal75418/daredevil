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
  final byIndustry = <String?, List<_Member>>{};
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
    (byIndustry[industry] ??= []).add((
      // percent 非 null 時 priceChange 非 null、收盤 − 漲跌是正數（溢位由
      // 加權結果的 isFinite 擋下）
      baseCap: percent == null || priceChange == null
          ? 0.0
          : shares.shares * (s.close - priceChange),
      tile: HeatmapTile(
        symbol: s.symbol,
        name: s.name,
        close: s.close,
        marketCap: marketCap,
        change: percent == null
            ? const TileChangeHollow(HollowReason.noChangeData)
            : TileChangeValue(percent),
        isMine: input.mine.contains(s.symbol),
      ),
    ));
  }

  final industries = [
    for (final MapEntry(key: name, value: members) in byIndustry.entries)
      _industry(name, members),
  ]..sort(_byCapThen((i) => i.marketCap, (i) => i.key));

  return HeatmapMarketData(
    market: input.market,
    dataDate: input.dataDate,
    industries: List.unmodifiable(industries),
    excludedForShares: excludedForShares,
  );
}

/// 一格與它的平盤市值（股數 × 平盤價；空心為 0，不參與加權）
typedef _Member = ({HeatmapTile tile, double baseCap});

/// 產業漲跌以「平盤市值」（股數 × (收盤 − 漲跌)）加權：等於產業總市值相對
/// 平盤的變化率，才近似這個產業對指數的影響；用今天的市值加權會偏向漲的
/// 成員（兩檔平盤市值相同、各 ±10% 會算出 +1%）。直接相乘、不從漲跌幅反推，
/// 極端輸入下才不會除以 0。
HeatmapIndustry _industry(String? name, List<_Member> members) {
  members.sort(_byCapThen((m) => m.tile.marketCap, (m) => m.tile.symbol));
  var cap = 0.0;
  var weightedSum = 0.0;
  var weightedBase = 0.0;
  for (final m in members) {
    cap += m.tile.marketCap;
    final change = m.tile.change;
    if (change is TileChangeValue) {
      weightedSum += m.baseCap * change.percent;
      weightedBase += m.baseCap;
    }
  }
  final weighted = weightedBase > 0 ? weightedSum / weightedBase : null;
  return HeatmapIndustry(
    name: name,
    marketCap: cap,
    weightedChangePercent: weighted != null && weighted.isFinite
        ? weighted
        : null,
    tiles: List.unmodifiable([for (final m in members) m.tile]),
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

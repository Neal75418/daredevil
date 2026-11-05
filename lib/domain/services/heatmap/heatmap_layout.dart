import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/domain/models/heatmap.dart';

/// 矩形（邏輯像素），不依賴 `dart:ui`
typedef HeatmapBox = ({double left, double top, double width, double height});

/// 一格的位置
@immutable
class HeatmapTileLayout {
  const HeatmapTileLayout({
    required this.tile,
    required this.bounds,
    required this.paint,
    required this.interactive,
  });

  final HeatmapTile tile;

  /// 切間隔前的矩形：同一產業內面積與市值成比例（各產業扣掉標題列與間隔
  /// 的比例不同，跨產業不成比例）
  final HeatmapBox bounds;

  /// 內縮 [HeatmapParams.tileGap] 一半後實際畫的矩形
  final HeatmapBox paint;

  /// [paint] 短邊 ≥ [HeatmapParams.minInteractiveSide]：太小的格子照畫但不回應
  /// 點擊與滑鼠
  final bool interactive;

  @override
  bool operator ==(Object other) =>
      other is HeatmapTileLayout &&
      other.tile == tile &&
      other.bounds == bounds &&
      other.paint == paint &&
      other.interactive == interactive;

  @override
  int get hashCode => Object.hash(tile, bounds, paint, interactive);
}

/// 漲跌家數（方向照四捨五入到 2 位後的漲跌幅，與顏色同一階）
typedef HeatmapBreadth = ({int up, int down, int flat, int hollow});

/// 合併的小格子：產業內預期面積太小（點不到、寫不下字）的個股合成一塊
@immutable
class HeatmapOtherLayout {
  const HeatmapOtherLayout({
    required this.members,
    required this.bounds,
    required this.paint,
    required this.interactive,
    required this.wholeIndustry,
    required this.marketCap,
    required this.weightedChangePercent,
    required this.breadth,
  });

  /// 被合併的個股（市值降冪）
  final List<HeatmapTile> members;
  final HeatmapBox bounds;
  final HeatmapBox paint;
  final bool interactive;

  /// 整個產業都被合併（沒有個別格子）：畫面寫產業名稱，不寫「其他」
  final bool wholeIndustry;

  /// 成員市值合計（面積照它算）
  final double marketCap;

  /// 成員以平盤市值加權的漲跌幅；成員全是空心或結果不是有限數時為 null。
  /// 整個產業都合併時是產業的 [HeatmapIndustry.weightedChangePercent]
  final double? weightedChangePercent;
  final HeatmapBreadth breadth;

  /// 成員中自選或持股的檔數（> 0 時合併塊畫自選框）
  int get mineCount => members.where((t) => t.isMine).length;

  @override
  bool operator ==(Object other) =>
      other is HeatmapOtherLayout &&
      const ListEquality<HeatmapTile>().equals(other.members, members) &&
      other.bounds == bounds &&
      other.paint == paint &&
      other.interactive == interactive &&
      other.wholeIndustry == wholeIndustry &&
      other.marketCap == marketCap &&
      other.weightedChangePercent == weightedChangePercent &&
      other.breadth == breadth;

  @override
  int get hashCode => Object.hash(
    const ListEquality<HeatmapTile>().hash(members),
    bounds,
    paint,
    interactive,
    wholeIndustry,
    marketCap,
    weightedChangePercent,
    breadth,
  );
}

/// 一個產業區塊的位置
@immutable
class HeatmapIndustryLayout {
  const HeatmapIndustryLayout({
    required this.industry,
    required this.bounds,
    required this.header,
    required this.tiles,
    this.other,
  });

  final HeatmapIndustry industry;

  /// 切間隔前的矩形：面積與產業市值成比例
  final HeatmapBox bounds;

  /// 標題列；區塊太小時為 null（格子從頂端開始）
  final HeatmapBox? header;

  /// 個別畫出的格子（不含被合併的）
  final List<HeatmapTileLayout> tiles;

  /// 合併的小格子；沒有要合併的（或只有一檔太小）時為 null
  final HeatmapOtherLayout? other;

  @override
  bool operator ==(Object other) =>
      other is HeatmapIndustryLayout &&
      other.industry == industry &&
      other.bounds == bounds &&
      other.header == header &&
      const ListEquality<HeatmapTileLayout>().equals(other.tiles, tiles) &&
      other.other == this.other;

  @override
  int get hashCode => Object.hash(
    industry,
    bounds,
    header,
    const ListEquality<HeatmapTileLayout>().hash(tiles),
    other,
  );
}

/// 合併的小產業：全市場圖上預期面積放不下標題列的產業合成一塊（見
/// [layoutHeatmapMarket]）
@immutable
class HeatmapIndustryGroupLayout {
  const HeatmapIndustryGroupLayout({
    required this.members,
    required this.bounds,
    required this.paint,
    required this.interactive,
    required this.marketCap,
    required this.weightedChangePercent,
    required this.breadth,
  });

  /// 被合併的產業（與輸入同序，市值降冪）
  final List<HeatmapIndustry> members;

  /// 切間隔前的矩形：面積與成員市值合計成比例
  final HeatmapBox bounds;

  /// 內縮半個產業間隔後實際畫的矩形
  final HeatmapBox paint;
  final bool interactive;

  /// 成員市值合計
  final double marketCap;

  /// 成員的個股以平盤市值加權的漲跌幅；全是空心或結果不是有限數時為 null
  final double? weightedChangePercent;

  /// 成員所有個股的漲跌家數
  final HeatmapBreadth breadth;

  /// 成員的個股檔數
  int get stockCount => members.fold(0, (a, i) => a + i.tiles.length);

  /// 成員中自選或持股的檔數（> 0 時合併塊畫自選框）
  int get mineCount =>
      members.fold(0, (a, i) => a + i.tiles.where((t) => t.isMine).length);

  @override
  bool operator ==(Object other) =>
      other is HeatmapIndustryGroupLayout &&
      const ListEquality<HeatmapIndustry>().equals(other.members, members) &&
      other.bounds == bounds &&
      other.paint == paint &&
      other.interactive == interactive &&
      other.marketCap == marketCap &&
      other.weightedChangePercent == weightedChangePercent &&
      other.breadth == breadth;

  @override
  int get hashCode => Object.hash(
    const ListEquality<HeatmapIndustry>().hash(members),
    bounds,
    paint,
    interactive,
    marketCap,
    weightedChangePercent,
    breadth,
  );
}

/// 全市場圖的佈局：各產業區塊，加上合併的小產業（沒有要合併的時為 null）
@immutable
class HeatmapMarketLayout {
  const HeatmapMarketLayout({required this.industries, this.smallIndustries});

  static const empty = HeatmapMarketLayout(industries: []);

  final List<HeatmapIndustryLayout> industries;
  final HeatmapIndustryGroupLayout? smallIndustries;
}

/// 全市場圖：預期面積（市值占比 × 圖區面積）小於
/// 「[HeatmapParams.industryFoldMinSide]² × [HeatmapParams.foldAspectAllowance]」
/// 的產業合成一塊，其餘照 [layoutHeatmap]。只有一個產業太小、或每個產業都
/// 太小時不合併。放大單一產業時用 [layoutHeatmap]。
HeatmapMarketLayout layoutHeatmapMarket(
  List<HeatmapIndustry> industries, {
  required double width,
  required double height,
}) {
  HeatmapMarketLayout plain() => HeatmapMarketLayout(
    industries: layoutHeatmap(industries, width: width, height: height),
  );
  final area = width * height;
  final total = industries.fold(0.0, (a, i) => a + i.marketCap);
  if (!(width > 0) ||
      !(height > 0) ||
      !area.isFinite ||
      !(total > 0) ||
      !total.isFinite) {
    return plain();
  }
  const minArea =
      HeatmapParams.industryFoldMinSide *
      HeatmapParams.industryFoldMinSide *
      HeatmapParams.foldAspectAllowance;
  bool tooSmall(HeatmapIndustry i) => i.marketCap / total * area < minArea;
  final small = [
    for (final i in industries)
      if (tooSmall(i)) i,
  ];
  final kept = [
    for (final i in industries)
      if (!tooSmall(i)) i,
  ];
  if (small.length < 2 || kept.isEmpty) return plain();
  // 合併塊照市值排進降冪序列，與產業區塊一起切
  final groupCap = small.fold(0.0, (a, i) => a + i.marketCap);
  final firstSmaller = kept.indexWhere((i) => i.marketCap < groupCap);
  final at = firstSmaller < 0 ? kept.length : firstSmaller;
  final boxes = [
    ...squarify([for (final i in kept) i.marketCap]..insert(at, groupCap), (
      left: 0,
      top: 0,
      width: width,
      height: height,
    )),
  ];
  final groupBox = boxes.removeAt(at);
  final groupPaint = _inset(groupBox, HeatmapParams.industryGap / 2);
  final tiles = [for (final i in small) ...i.tiles];
  return HeatmapMarketLayout(
    industries: List.unmodifiable([
      for (var k = 0; k < kept.length; k++) _layoutIndustry(kept[k], boxes[k]),
    ]),
    smallIndustries: HeatmapIndustryGroupLayout(
      members: List.unmodifiable(small),
      bounds: groupBox,
      paint: groupPaint,
      interactive:
          math.min(groupPaint.width, groupPaint.height) >=
          HeatmapParams.minInteractiveSide,
      marketCap: groupCap,
      weightedChangePercent: _weightedChange(tiles),
      breadth: _breadth(tiles),
    ),
  );
}

/// 兩層 squarified 佈局：先依產業市值切產業區塊，再在區塊內（扣掉標題列）依
/// 個股市值切格子。圖區 ≤ 0 或面積不是有限數（父層高度無上限、溢位）、沒有
/// 產業、或總市值不是有限正數時回空。
List<HeatmapIndustryLayout> layoutHeatmap(
  List<HeatmapIndustry> industries, {
  required double width,
  required double height,
}) {
  if (!(width > 0) ||
      !(height > 0) ||
      !(width * height).isFinite ||
      industries.isEmpty) {
    return const [];
  }
  final total = industries.fold(0.0, (a, i) => a + i.marketCap);
  if (!(total > 0) || !total.isFinite) return const [];
  final boxes = squarify(
    [for (final i in industries) i.marketCap],
    (left: 0, top: 0, width: width, height: height),
  );
  return List.unmodifiable([
    for (var k = 0; k < industries.length; k++)
      _layoutIndustry(industries[k], boxes[k]),
  ]);
}

HeatmapIndustryLayout _layoutIndustry(
  HeatmapIndustry industry,
  HeatmapBox bounds,
) {
  final inner = _inset(bounds, HeatmapParams.industryGap / 2);
  final hasHeader =
      inner.width >= HeatmapParams.industryHeaderMinWidth &&
      inner.height >= HeatmapParams.industryHeaderMinHeight;
  const headerHeight = HeatmapParams.industryHeaderHeight;
  final HeatmapBox? header = hasHeader
      ? (
          left: inner.left,
          top: inner.top,
          width: inner.width,
          height: headerHeight,
        )
      : null;
  final HeatmapBox content = hasHeader
      ? (
          left: inner.left,
          top: inner.top + headerHeight,
          width: inner.width,
          height: inner.height - headerHeight,
        )
      : inner;
  final tiles = industry.tiles;
  final total = tiles.fold(0.0, (a, t) => a + t.marketCap);
  final contentArea = content.width * content.height;
  const minArea =
      HeatmapParams.foldMinSide *
      HeatmapParams.foldMinSide *
      HeatmapParams.foldAspectAllowance;
  final canFold = total > 0 && total.isFinite && contentArea.isFinite;
  // 自選或持股照樣合併：留成小格子寫不下名稱、認不出是哪一檔，改由合併塊的
  // 自選框與清單標示
  bool tooSmall(HeatmapTile t) =>
      canFold && t.marketCap / total * contentArea < minArea;
  final folded = [
    for (final t in tiles)
      if (tooSmall(t)) t,
  ];
  if (folded.length < 2) {
    final boxes = squarify([for (final t in tiles) t.marketCap], content);
    return HeatmapIndustryLayout(
      industry: industry,
      bounds: bounds,
      header: header,
      tiles: List.unmodifiable([
        for (var k = 0; k < tiles.length; k++) _layoutTile(tiles[k], boxes[k]),
      ]),
    );
  }
  final kept = [
    for (final t in tiles)
      if (!tooSmall(t)) t,
  ];
  // 合併塊照市值排進降冪序列，與個別格子一起切
  final otherCap = folded.fold(0.0, (a, t) => a + t.marketCap);
  final firstSmaller = kept.indexWhere((t) => t.marketCap < otherCap);
  final at = firstSmaller < 0 ? kept.length : firstSmaller;
  final boxes = [
    ...squarify(
      [for (final t in kept) t.marketCap]..insert(at, otherCap),
      content,
    ),
  ];
  final otherBox = boxes.removeAt(at);
  final otherPaint = _inset(otherBox, HeatmapParams.tileGap / 2);
  return HeatmapIndustryLayout(
    industry: industry,
    bounds: bounds,
    header: header,
    tiles: List.unmodifiable([
      for (var k = 0; k < kept.length; k++) _layoutTile(kept[k], boxes[k]),
    ]),
    other: HeatmapOtherLayout(
      members: List.unmodifiable(folded),
      bounds: otherBox,
      paint: otherPaint,
      interactive:
          math.min(otherPaint.width, otherPaint.height) >=
          HeatmapParams.minInteractiveSide,
      wholeIndustry: kept.isEmpty,
      marketCap: otherCap,
      // 整個產業都合併時直接用產業的值：與標題列寫的是同一個數，不會因兩種
      // 算法的捨入差 0.01
      weightedChangePercent: kept.isEmpty
          ? industry.weightedChangePercent
          : _weightedChange(folded),
      breadth: _breadth(folded),
    ),
  );
}

/// 以平盤市值加權的漲跌幅（與產業漲跌同一算法；產業那邊直接用股數 ×
/// （收盤 − 漲跌），這裡從格子已有的市值與漲跌幅反推，盤中市值基準不同時要改）。平盤市值＝市值 ÷
/// (1 + 漲跌幅 / 100)：市值是股數 × 收盤，漲跌幅＝漲跌 ÷（收盤 − 漲跌），
/// 所以等於股數 ×（收盤 − 漲跌）。
double? _weightedChange(List<HeatmapTile> tiles) {
  var sum = 0.0;
  var base = 0.0;
  for (final t in tiles) {
    final change = t.change;
    if (change is! TileChangeValue) continue;
    final b = t.marketCap * 100 / (100 + change.percent);
    // 極端資料下（漲跌幅 −100%）算不出平盤市值：跳過這一檔，不讓整塊變空心
    // （成員乘積溢位時整塊結果不是有限數，仍回 null）
    if (!b.isFinite || !(b > 0)) continue;
    sum += b * change.percent;
    base += b;
  }
  if (!(base > 0)) return null;
  final weighted = sum / base;
  return weighted.isFinite ? weighted : null;
}

HeatmapBreadth _breadth(List<HeatmapTile> tiles) {
  var up = 0;
  var down = 0;
  var flat = 0;
  var hollow = 0;
  for (final t in tiles) {
    switch (t.change) {
      case TileChangeHollow():
        hollow++;
      case TileChangeValue(:final percent):
        final rounded = HeatmapParams.roundPercent(percent);
        if (rounded > 0) {
          up++;
        } else if (rounded < 0) {
          down++;
        } else {
          flat++;
        }
    }
  }
  return (up: up, down: down, flat: flat, hollow: hollow);
}

HeatmapTileLayout _layoutTile(HeatmapTile tile, HeatmapBox bounds) {
  final paint = _inset(bounds, HeatmapParams.tileGap / 2);
  return HeatmapTileLayout(
    tile: tile,
    bounds: bounds,
    paint: paint,
    interactive:
        math.min(paint.width, paint.height) >= HeatmapParams.minInteractiveSide,
  );
}

/// 四邊各內縮 [d]；哪一邊不夠縮，那一邊的長度就是 0（置中）
HeatmapBox _inset(HeatmapBox b, double d) => (
  left: b.left + math.min(d, b.width / 2),
  top: b.top + math.min(d, b.height / 2),
  width: math.max(0.0, b.width - 2 * d),
  height: math.max(0.0, b.height - 2 * d),
);

/// Bruls、Huizing、van Wijk 的 squarified treemap：沿剩餘區域的短邊排一列，
/// 加入下一個值會讓該列最差長寬比變大時就換列。
///
/// [values] 應已降冪；回傳與 [values] 同順序、面積與值成比例的矩形，鋪滿
/// [area]（最後一列與每列最後一格吃滿剩下的長度，浮點誤差不留縫）。總和
/// 不是有限正數、[area] 沒有面積、或面積 ÷ 總和不是有限數時，全部回 [area] 左上角的 0 大小矩形。
List<HeatmapBox> squarify(List<double> values, HeatmapBox area) {
  final n = values.length;
  if (n == 0) return const [];
  final HeatmapBox empty = (
    left: area.left,
    top: area.top,
    width: 0,
    height: 0,
  );
  final total = values.fold(0.0, (a, v) => a + math.max(0.0, v));
  if (!(total > 0) ||
      !total.isFinite ||
      !(area.width > 0) ||
      !(area.height > 0)) {
    return List.filled(n, empty);
  }
  final scale = area.width * area.height / total;
  if (!scale.isFinite) return List.filled(n, empty);
  final areas = [for (final v in values) math.max(0.0, v) * scale];
  final result = List<HeatmapBox>.filled(n, empty);

  var rect = area;
  var i = 0;
  while (i < n) {
    final side = math.min(rect.width, rect.height);
    if (!(side > 0)) {
      final HeatmapBox corner = (
        left: rect.left,
        top: rect.top,
        width: 0,
        height: 0,
      );
      for (var k = i; k < n; k++) {
        result[k] = corner;
      }
      break;
    }
    var end = i + 1;
    var rowSum = areas[i];
    var worst = _worstRatio(areas, i, end, rowSum, side);
    while (end < n) {
      final nextSum = rowSum + areas[end];
      final nextWorst = _worstRatio(areas, i, end + 1, nextSum, side);
      if (nextWorst > worst) break;
      rowSum = nextSum;
      worst = nextWorst;
      end++;
    }
    final lastRow = end == n;
    if (rect.width >= rect.height) {
      // 短邊是高：這一列是貼左邊的一欄
      final colWidth = lastRow
          ? rect.width
          : math.min(rect.width, rowSum / rect.height);
      var y = rect.top;
      for (var k = i; k < end; k++) {
        final h = k == end - 1
            ? rect.top + rect.height - y
            : (rowSum > 0 ? areas[k] / rowSum * rect.height : 0.0);
        result[k] = (left: rect.left, top: y, width: colWidth, height: h);
        y += h;
      }
      rect = (
        left: rect.left + colWidth,
        top: rect.top,
        width: rect.width - colWidth,
        height: rect.height,
      );
    } else {
      // 短邊是寬：這一列是貼上邊的一排
      final rowHeight = lastRow
          ? rect.height
          : math.min(rect.height, rowSum / rect.width);
      var x = rect.left;
      for (var k = i; k < end; k++) {
        final w = k == end - 1
            ? rect.left + rect.width - x
            : (rowSum > 0 ? areas[k] / rowSum * rect.width : 0.0);
        result[k] = (left: x, top: rect.top, width: w, height: rowHeight);
        x += w;
      }
      rect = (
        left: rect.left,
        top: rect.top + rowHeight,
        width: rect.width,
        height: rect.height - rowHeight,
      );
    }
    i = end;
  }
  return result;
}

/// 索引 [from, to) 這一列沿長度 [side] 排開時，最差的長寬比
double _worstRatio(
  List<double> areas,
  int from,
  int to,
  double sum,
  double side,
) {
  if (!(sum > 0)) return double.infinity;
  final s2 = sum * sum;
  final w2 = side * side;
  var worst = 0.0;
  for (var k = from; k < to; k++) {
    final a = areas[k];
    if (!(a > 0)) return double.infinity;
    worst = math.max(worst, math.max(w2 * a / s2, s2 / (w2 * a)));
  }
  return worst;
}

/// 點擊或滑鼠位置對應的格子；只回可互動的格子，間隔與標題列回 null
HeatmapTileLayout? tileAt(
  List<HeatmapIndustryLayout> layout,
  double x,
  double y,
) {
  for (final industry in layout) {
    if (!_contains(industry.bounds, x, y)) continue;
    for (final t in industry.tiles) {
      if (t.interactive && _contains(t.paint, x, y)) return t;
    }
    return null;
  }
  return null;
}

/// 點擊或滑鼠位置對應的合併塊（只回可互動的）
({HeatmapIndustryLayout industry, HeatmapOtherLayout other})? otherAt(
  List<HeatmapIndustryLayout> layout,
  double x,
  double y,
) {
  for (final industry in layout) {
    if (!_contains(industry.bounds, x, y)) continue;
    final other = industry.other;
    if (other != null && other.interactive && _contains(other.paint, x, y)) {
      return (industry: industry, other: other);
    }
    return null;
  }
  return null;
}

/// 點擊或滑鼠位置對應的小產業合併塊（只回可互動的）
HeatmapIndustryGroupLayout? smallIndustriesAt(
  HeatmapMarketLayout layout,
  double x,
  double y,
) {
  final group = layout.smallIndustries;
  if (group == null || !group.interactive) return null;
  return _contains(group.paint, x, y) ? group : null;
}

/// 點擊位置對應的產業標題列
HeatmapIndustryLayout? industryHeaderAt(
  List<HeatmapIndustryLayout> layout,
  double x,
  double y,
) {
  for (final industry in layout) {
    final header = industry.header;
    if (header != null && _contains(header, x, y)) return industry;
  }
  return null;
}

bool _contains(HeatmapBox b, double x, double y) =>
    x >= b.left && x < b.left + b.width && y >= b.top && y < b.top + b.height;

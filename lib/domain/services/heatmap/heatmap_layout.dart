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

/// 一個產業區塊的位置
@immutable
class HeatmapIndustryLayout {
  const HeatmapIndustryLayout({
    required this.industry,
    required this.bounds,
    required this.header,
    required this.tiles,
  });

  final HeatmapIndustry industry;

  /// 切間隔前的矩形：面積與產業市值成比例
  final HeatmapBox bounds;

  /// 標題列；區塊太小時為 null（格子從頂端開始）
  final HeatmapBox? header;
  final List<HeatmapTileLayout> tiles;

  @override
  bool operator ==(Object other) =>
      other is HeatmapIndustryLayout &&
      other.industry == industry &&
      other.bounds == bounds &&
      other.header == header &&
      const ListEquality<HeatmapTileLayout>().equals(other.tiles, tiles);

  @override
  int get hashCode => Object.hash(
    industry,
    bounds,
    header,
    const ListEquality<HeatmapTileLayout>().hash(tiles),
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
  final tileBoxes = squarify([
    for (final t in industry.tiles) t.marketCap,
  ], content);
  return HeatmapIndustryLayout(
    industry: industry,
    bounds: bounds,
    header: header,
    tiles: List.unmodifiable([
      for (var k = 0; k < industry.tiles.length; k++)
        _layoutTile(industry.tiles[k], tileBoxes[k]),
    ]),
  );
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

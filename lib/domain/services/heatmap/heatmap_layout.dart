import 'dart:math' as math;

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

  /// 切間隔前的矩形：面積與市值成比例
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

/// squarified 佈局：格子依市值直接切滿整個圖區。[tiles] 應已依市值降冪。
/// 圖區 ≤ 0 或面積不是有限數（父層高度無上限、溢位）、沒有格子、或總市值
/// 不是有限正數時回空。
List<HeatmapTileLayout> layoutHeatmapTiles(
  List<HeatmapTile> tiles, {
  required double width,
  required double height,
}) {
  if (!(width > 0) ||
      !(height > 0) ||
      !(width * height).isFinite ||
      tiles.isEmpty) {
    return const [];
  }
  final total = tiles.fold(0.0, (a, t) => a + t.marketCap);
  if (!(total > 0) || !total.isFinite) return const [];
  final boxes = squarify(
    [for (final t in tiles) t.marketCap],
    (left: 0, top: 0, width: width, height: height),
  );
  return List.unmodifiable([
    for (var k = 0; k < tiles.length; k++) _layoutTile(tiles[k], boxes[k]),
  ]);
}

/// 點擊或滑鼠位置對應的格子；只回可互動的格子，間隔回 null
HeatmapTileLayout? heatmapTileAt(
  List<HeatmapTileLayout> layout,
  double x,
  double y,
) {
  for (final tile in layout) {
    if (tile.interactive && _contains(tile.paint, x, y)) return tile;
  }
  return null;
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

bool _contains(HeatmapBox b, double x, double y) =>
    x >= b.left && x < b.left + b.width && y >= b.top && y < b.top + b.height;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';

HeatmapTile _tile(String symbol, double cap) => HeatmapTile(
  symbol: symbol,
  name: symbol,
  industry: null,
  close: 100,
  marketCap: cap,
  change: const TileChangeValue(1),
  isMine: false,
);

double _area(HeatmapBox b) => b.width * b.height;

double _overlap(HeatmapBox a, HeatmapBox b) {
  final w =
      math.min(a.left + a.width, b.left + b.width) - math.max(a.left, b.left);
  final h =
      math.min(a.top + a.height, b.top + b.height) - math.max(a.top, b.top);
  return w > 0 && h > 0 ? w * h : 0;
}

void _expectInside(HeatmapBox inner, HeatmapBox outer, String reason) {
  const eps = 1e-9;
  expect(inner.left, greaterThanOrEqualTo(outer.left - eps), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top - eps), reason: reason);
  expect(
    inner.left + inner.width,
    lessThanOrEqualTo(outer.left + outer.width + eps),
    reason: reason,
  );
  expect(
    inner.top + inner.height,
    lessThanOrEqualTo(outer.top + outer.height + eps),
    reason: reason,
  );
}

void main() {
  test('squarify 回傳順序與輸入相同、面積成比例', () {
    final boxes = squarify(
      [5, 3, 2],
      (left: 0, top: 0, width: 100, height: 100),
    );
    expect(boxes.map(_area).toList(), [
      closeTo(5000, 1e-6),
      closeTo(3000, 1e-6),
      closeTo(2000, 1e-6),
    ]);
  });

  test('squarify 面積 ÷ 總和不是有限數時回 0 大小矩形，不產生 NaN', () {
    const HeatmapBox zero = (left: 0, top: 0, width: 0, height: 0);
    expect(squarify([1, 1], (left: 0, top: 0, width: 1e200, height: 1e200)), [
      zero,
      zero,
    ]);
  });

  test('squarify 長寬比：10 個等值在正方形中最差 ≤ 3', () {
    final boxes = squarify(List.filled(10, 1.0), (
      left: 0,
      top: 0,
      width: 100,
      height: 100,
    ));
    final worst = boxes
        .map((b) => math.max(b.width / b.height, b.height / b.width))
        .reduce(math.max);
    expect(worst, lessThanOrEqualTo(3));
  });

  group('layoutHeatmapTiles', () {
    test('圖區沒有面積、不是有限數、或沒有格子：空清單', () {
      final tiles = [_tile('A', 6), _tile('B', 3)];
      expect(layoutHeatmapTiles(tiles, width: 0, height: 50), isEmpty);
      expect(layoutHeatmapTiles(tiles, width: 100, height: 0), isEmpty);
      expect(
        layoutHeatmapTiles(tiles, width: 100, height: double.infinity),
        isEmpty,
      );
      expect(layoutHeatmapTiles(const [], width: 100, height: 50), isEmpty);
    });

    test('總市值不是有限正數：空清單', () {
      for (final tiles in [
        [_tile('A', 0)],
        [_tile('A', double.infinity)],
      ]) {
        expect(
          layoutHeatmapTiles(tiles, width: 100, height: 50),
          isEmpty,
          reason: '${tiles.single.marketCap}',
        );
      }
    });

    test('🚨 圖區極小時 30 檔照樣排、不丟例外', () {
      final tiles = [
        for (var i = 0; i < 30; i++)
          _tile('T${i.toString().padLeft(2, '0')}', 30.0 - i),
      ];
      final layout = layoutHeatmapTiles(tiles, width: 3, height: 2);
      expect(layout, hasLength(30));
      expect([for (final l in layout) l.interactive], everyElement(isFalse));
    });

    test('🚨 面積與市值成比例、鋪滿圖區、互不重疊', () {
      final layout = layoutHeatmapTiles(
        [_tile('A', 6), _tile('B', 3), _tile('C', 1)],
        width: 100,
        height: 50,
      );
      expect([for (final l in layout) l.tile.symbol], ['A', 'B', 'C']);
      // 面積、合計、不重疊在寬高對調時都不會變：另外確認每格都在圖區內
      for (final l in layout) {
        _expectInside(l.bounds, (
          left: 0,
          top: 0,
          width: 100,
          height: 50,
        ), l.tile.symbol);
      }
      expect(_area(layout[0].bounds), closeTo(3000, 1e-6));
      expect(_area(layout[1].bounds), closeTo(1500, 1e-6));
      expect(_area(layout[2].bounds), closeTo(500, 1e-6));
      expect(
        layout.fold(0.0, (a, l) => a + _area(l.bounds)),
        closeTo(5000, 1e-6),
      );
      for (var i = 0; i < layout.length; i++) {
        for (var j = i + 1; j < layout.length; j++) {
          expect(_overlap(layout[i].bounds, layout[j].bounds), 0);
        }
      }
    });

    test('🚨 實際畫的矩形四邊各內縮半個格子間隔；短邊太小的不互動', () {
      final layout = layoutHeatmapTiles(
        [_tile('A', 9990), _tile('B', 10)],
        width: 100,
        height: 50,
      );
      const d = HeatmapParams.tileGap / 2;
      final a = layout[0];
      expect(a.paint.left, closeTo(a.bounds.left + d, 1e-9));
      expect(a.paint.top, closeTo(a.bounds.top + d, 1e-9));
      expect(a.paint.width, closeTo(a.bounds.width - 2 * d, 1e-9));
      expect(a.paint.height, closeTo(a.bounds.height - 2 * d, 1e-9));
      expect(a.interactive, isTrue);
      expect(layout[1].interactive, isFalse);
    });

    test('極端比例：一檔占 55%、其餘 29 檔均分，每格都在圖區內、面積成比例', () {
      final tiles = [
        _tile('BIG', 55 * 29.0),
        for (var i = 0; i < 29; i++)
          _tile('S${i.toString().padLeft(2, '0')}', 45.0),
      ];
      final layout = layoutHeatmapTiles(tiles, width: 800, height: 500);
      final total = tiles.fold(0.0, (a, t) => a + t.marketCap);
      expect(layout, hasLength(30));
      for (final l in layout) {
        _expectInside(l.bounds, (
          left: 0,
          top: 0,
          width: 800,
          height: 500,
        ), l.tile.symbol);
        expect(
          _area(l.bounds),
          closeTo(l.tile.marketCap / total * 800 * 500, 1e-6),
          reason: l.tile.symbol,
        );
      }
    });

    test('🚨 interactive 看實際畫的矩形短邊，門檻含等號', () {
      const side = HeatmapParams.minInteractiveSide + HeatmapParams.tileGap;
      final atThreshold = layoutHeatmapTiles(
        [_tile('A', 1)],
        width: side,
        height: 50,
      ).single;
      expect(
        atThreshold.paint.width,
        closeTo(HeatmapParams.minInteractiveSide, 1e-9),
      );
      expect(atThreshold.interactive, isTrue);
      final below = layoutHeatmapTiles(
        [_tile('A', 1)],
        width: side - 0.01,
        height: 50,
      ).single;
      expect(below.interactive, isFalse);
    });
  });

  group('heatmapTileAt', () {
    // A 60%、B 38.5%、C 1.5%：C 是一條畫得出來、但短邊不到
    // minInteractiveSide 的細長格子
    List<HeatmapTileLayout> build() => layoutHeatmapTiles(
      [_tile('A', 6000), _tile('B', 3850), _tile('C', 150)],
      width: 100,
      height: 50,
    );
    (double, double) center(HeatmapBox b) =>
        (b.left + b.width / 2, b.top + b.height / 2);

    test('點在格子裡回那一格', () {
      final layout = build();
      for (final tile in layout.take(2)) {
        final (x, y) = center(tile.paint);
        expect(heatmapTileAt(layout, x, y), same(tile));
      }
    });

    test('🚨 點在格子間隔上回 null', () {
      final layout = build();
      final a = layout[0];
      // 在 A 切間隔前的矩形裡、實際畫的矩形外
      final x = a.bounds.left + a.bounds.width - HeatmapParams.tileGap / 4;
      expect(heatmapTileAt(layout, x, center(a.bounds).$2), isNull);
    });

    test('🚨 點在不互動的格子上回 null', () {
      final layout = build();
      final c = layout[2];
      expect(c.interactive, isFalse, reason: '前提：C 的短邊太小');
      expect(
        c.paint.width > 0 && c.paint.height > 0,
        isTrue,
        reason: '前提：C 畫得出來，點得到它的範圍',
      );
      final (x, y) = center(c.paint);
      expect(heatmapTileAt(layout, x, y), isNull);
    });
  });
}

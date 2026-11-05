import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';

HeatmapTile _tile(String symbol, double cap) => HeatmapTile(
  symbol: symbol,
  name: symbol,
  close: 100,
  marketCap: cap,
  change: const TileChangeValue(1),
  isMine: false,
);

/// [caps] 需已降冪（與分組計算的輸出相同）
HeatmapIndustry _industry(String name, List<double> caps) => HeatmapIndustry(
  name: name,
  marketCap: caps.fold(0.0, (a, c) => a + c),
  weightedChangePercent: 1,
  tiles: [for (var i = 0; i < caps.length; i++) _tile('$name$i', caps[i])],
);

double _area(HeatmapBox b) => b.width * b.height;

double _overlap(HeatmapBox a, HeatmapBox b) {
  final w =
      math.min(a.left + a.width, b.left + b.width) - math.max(a.left, b.left);
  final h =
      math.min(a.top + a.height, b.top + b.height) - math.max(a.top, b.top);
  return w > 0 && h > 0 ? w * h : 0;
}

/// 產業內縮後扣掉標題列的格子區
HeatmapBox _content(HeatmapIndustryLayout l) {
  const d = HeatmapParams.industryGap / 2;
  final b = l.bounds;
  final inner = (
    left: b.left + math.min(d, b.width / 2),
    top: b.top + math.min(d, b.height / 2),
    width: math.max(0.0, b.width - 2 * d),
    height: math.max(0.0, b.height - 2 * d),
  );
  final h = l.header;
  return h == null
      ? inner
      : (
          left: inner.left,
          top: inner.top + h.height,
          width: inner.width,
          height: inner.height - h.height,
        );
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

/// 比例、鋪滿、不重疊、在範圍內，並且每個輸入的產業與格子都畫出來、順序不變
void _expectValidLayout(
  List<HeatmapIndustry> industries,
  List<HeatmapIndustryLayout> layout,
  double width,
  double height,
) {
  // 每個產業、每一格都要畫出來（總市值從輸入算，少畫一個也會紅）
  expect(
    layout.map((l) => l.industry.key).toList(),
    industries.map((i) => i.key).toList(),
  );
  for (var k = 0; k < layout.length; k++) {
    expect(
      layout[k].tiles.map((t) => t.tile.symbol).toList(),
      industries[k].tiles.map((t) => t.symbol).toList(),
    );
  }
  final total = industries.fold(0.0, (a, i) => a + i.marketCap);
  final HeatmapBox area = (left: 0, top: 0, width: width, height: height);
  // 產業層：面積與市值成比例、在圖區內、鋪滿
  var industryArea = 0.0;
  for (final l in layout) {
    industryArea += _area(l.bounds);
    _expectInside(l.bounds, area, '產業 ${l.industry.key}');
    expect(
      _area(l.bounds) / (width * height),
      closeTo(l.industry.marketCap / total, 1e-6),
      reason: '產業 ${l.industry.key}',
    );
    // 格子層：對產業內容區成比例、在內容區內、鋪滿
    final content = _content(l);
    var tileArea = 0.0;
    for (final t in l.tiles) {
      tileArea += _area(t.bounds);
      _expectInside(t.bounds, content, '格子 ${t.tile.symbol}');
      expect(
        _area(t.bounds) / _area(content),
        closeTo(t.tile.marketCap / l.industry.marketCap, 1e-6),
        reason: '格子 ${t.tile.symbol}',
      );
    }
    expect(tileArea, closeTo(_area(content), _area(content) * 1e-9 + 1e-9));
  }
  expect(industryArea, closeTo(width * height, width * height * 1e-9));
  // 不重疊
  final all = [for (final l in layout) ...l.tiles.map((t) => t.bounds)];
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      expect(_overlap(all[i], all[j]), lessThan(1e-6));
    }
  }
  for (var i = 0; i < layout.length; i++) {
    for (var j = i + 1; j < layout.length; j++) {
      expect(_overlap(layout[i].bounds, layout[j].bounds), lessThan(1e-6));
    }
  }
}

void main() {
  final mixed = [
    _industry('A', [300, 200, 100]),
    _industry('B', [250, 150]),
    _industry('C', [80, 60, 40, 20]),
  ];

  test('面積與市值成比例、矩形不重疊、鋪滿圖區', () {
    _expectValidLayout(
      mixed,
      layoutHeatmap(mixed, width: 800, height: 500),
      800,
      500,
    );
  });

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

  test('0 檔回空；單產業單格時格子＝產業內容區', () {
    expect(layoutHeatmap([], width: 800, height: 500), isEmpty);
    final layout = layoutHeatmap(
      [
        _industry('A', [100]),
      ],
      width: 300,
      height: 200,
    );
    final l = layout.single;
    final content = _content(l);
    final tile = l.tiles.single.bounds;
    expect(tile.left, closeTo(content.left, 1e-9));
    expect(tile.top, closeTo(content.top, 1e-9));
    expect(tile.width, closeTo(content.width, 1e-9));
    expect(tile.height, closeTo(content.height, 1e-9));
  });

  test('極端比例：一檔占 41%、其餘 200 檔均分', () {
    // 產業依市值降冪（分組計算的輸出形狀）
    final industries = [
      _industry('B', List.filled(200, 59 / 200)),
      _industry('A', [41]),
    ];
    _expectValidLayout(
      industries,
      layoutHeatmap(industries, width: 1200, height: 700),
      1200,
      700,
    );
  });

  test('同樣輸入同樣輸出', () {
    expect(
      layoutHeatmap(mixed, width: 800, height: 500),
      layoutHeatmap(mixed, width: 800, height: 500),
    );
  });

  test('圖區為 0 或極小：不拋錯，極小時格子都不可互動', () {
    expect(layoutHeatmap(mixed, width: 0, height: 500), isEmpty);
    expect(layoutHeatmap(mixed, width: 800, height: -1), isEmpty);
    expect(layoutHeatmap(mixed, width: 800, height: 0), isEmpty);
    // 父層高度無上限、或寬×高溢位：不產生 NaN／∞ 矩形
    expect(layoutHeatmap(mixed, width: 800, height: double.infinity), isEmpty);
    expect(layoutHeatmap(mixed, width: 1e200, height: 1e200), isEmpty);
    final layout = layoutHeatmap(
      [_industry('A', List.filled(40, 1.0))],
      width: 10,
      height: 10,
    );
    final tiles = layout.single.tiles;
    expect(tiles, hasLength(40));
    expect(tiles.where((t) => t.interactive), isEmpty);
  });

  test('總市值溢位回空', () {
    expect(
      layoutHeatmap(
        [
          _industry('A', [1e308]),
          _industry('B', [1e308]),
        ],
        width: 800,
        height: 500,
      ),
      isEmpty,
    );
  });

  test('小產業不畫標題列，格子從頂端開始；夠大時頂端切出標題列', () {
    const d = HeatmapParams.industryGap / 2;
    // 內縮後寬比門檻少 1
    final small = layoutHeatmap(
      [
        _industry('A', [100, 50]),
      ],
      width: HeatmapParams.industryHeaderMinWidth - 1 + 2 * d,
      height: 200,
    ).single;
    expect(small.header, isNull);
    final topOfTiles = small.tiles.map((t) => t.bounds.top).reduce(math.min);
    expect(topOfTiles, closeTo(d, 1e-9));

    final big = layoutHeatmap(
      [
        _industry('A', [100, 50]),
      ],
      width: 300,
      height: 200,
    ).single;
    expect(big.header, (left: d, top: d, width: 300 - 2 * d, height: 16.0));
    final topOfBig = big.tiles.map((t) => t.bounds.top).reduce(math.min);
    expect(topOfBig, closeTo(d + 16, 1e-9));
  });

  test('標題列門檻含等號：內縮後剛好等於寬高門檻就畫標題列', () {
    const d = HeatmapParams.industryGap / 2;
    final exact = layoutHeatmap(
      [
        _industry('A', [1]),
      ],
      width: HeatmapParams.industryHeaderMinWidth + 2 * d,
      height: HeatmapParams.industryHeaderMinHeight + 2 * d,
    ).single;
    expect(exact.header, isNotNull);
  });

  test('interactive 看繪製區（paint）短邊，門檻含等號', () {
    const d = HeatmapParams.industryGap / 2;
    // 單產業單格、沒有標題列：格子＝內縮 d 後的區域，paint 再各縮 0.5
    HeatmapTileLayout only(double width) => layoutHeatmap(
      [
        _industry('A', [1]),
      ],
      width: width,
      height: 50,
    ).single.tiles.single;
    // bounds 短邊 5、paint 短邊剛好 4 → 可互動
    expect(only(5 + 2 * d).interactive, isTrue);
    // bounds 短邊 4.5（≥ 4）、paint 短邊 3.5 → 不可互動
    expect(only(4.5 + 2 * d).interactive, isFalse);
  });

  test('高度不夠的產業也不畫標題列', () {
    // 內縮後高 39 < 40、寬 298 夠
    final flat = layoutHeatmap(
      [
        _industry('A', [100, 50]),
      ],
      width: 300,
      height: 41,
    ).single;
    expect(flat.header, isNull);
  });

  test('tileAt 只回可互動的格子；間隔與標題列回 null', () {
    final layout = layoutHeatmap(
      [
        _industry('A', [1000, 1e-6]),
      ],
      width: 300,
      height: 200,
    );
    final tiles = layout.single.tiles;
    final big = tiles.firstWhere((t) => t.tile.symbol == 'A0');
    final tiny = tiles.firstWhere((t) => t.tile.symbol == 'A1');
    expect(tiny.interactive, isFalse);

    final b = big.bounds;
    expect(
      tileAt(layout, b.left + b.width / 2, b.top + b.height / 2)?.tile.symbol,
      'A0',
    );
    final t = tiny.bounds;
    expect(tileAt(layout, t.left + t.width / 2, t.top + t.height / 2), isNull);
    // 格子邊緣在 bounds 內、paint 外（間隔）
    expect(tileAt(layout, b.left + 0.25, b.top + b.height / 2), isNull);
    // 標題列
    final h = layout.single.header!;
    expect(tileAt(layout, h.left + 10, h.top + h.height / 2), isNull);
  });

  test('tileAt 對繪製區不為空、但不可互動的格子回 null', () {
    // 繪製區 3×10：點得中矩形，但短邊 < minInteractiveSide
    HeatmapIndustryLayout layoutWith({required bool interactive}) =>
        HeatmapIndustryLayout(
          industry: _industry('A', [1]),
          bounds: (left: 0, top: 0, width: 100, height: 100),
          header: null,
          tiles: [
            HeatmapTileLayout(
              tile: _tile('A0', 1),
              bounds: (left: 9.5, top: 9.5, width: 4, height: 11),
              paint: (left: 10, top: 10, width: 3, height: 10),
              interactive: interactive,
            ),
          ],
        );
    expect(tileAt([layoutWith(interactive: false)], 11, 15), isNull);
    expect(tileAt([layoutWith(interactive: true)], 11, 15)?.tile.symbol, 'A0');
  });

  test('industryHeaderAt：標題列回該產業，格子區回 null', () {
    final layout = layoutHeatmap(mixed, width: 800, height: 500);
    final withHeader = layout.firstWhere((l) => l.header != null);
    final h = withHeader.header!;
    expect(
      industryHeaderAt(layout, h.left + 5, h.top + h.height / 2)?.industry.key,
      withHeader.industry.key,
    );
    final tile = withHeader.tiles.first.paint;
    expect(
      industryHeaderAt(
        layout,
        tile.left + tile.width / 2,
        tile.top + tile.height / 2,
      ),
      isNull,
    );
  });
}

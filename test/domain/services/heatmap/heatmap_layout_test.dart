import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';

/// 平盤市值：市值 ÷ (1 + 漲跌幅 / 100)；空心為 0
double _baseCapOf(double cap, TileChange change) => switch (change) {
  TileChangeValue(:final percent) => cap * 100 / (100 + percent),
  TileChangeHollow() => 0,
};

HeatmapTile _tile(String symbol, double cap) => HeatmapTile(
  symbol: symbol,
  name: symbol,
  close: 100,
  marketCap: cap,
  baseCap: _baseCapOf(cap, const TileChangeValue(1)),
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

  test('圖區為 0 或極小：不拋錯；極小時整個產業合成一塊', () {
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
    expect(layout.single.tiles, isEmpty);
    expect(layout.single.other!.members, hasLength(40));
    expect(layout.single.other!.wholeIndustry, isTrue);
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

  group('太小的個股合併成「其他」', () {
    const minArea =
        HeatmapParams.foldMinSide *
        HeatmapParams.foldMinSide *
        HeatmapParams.foldAspectAllowance;

    HeatmapTile tile(
      String symbol,
      double cap, {
      TileChange change = const TileChangeValue(1),
      double? baseCap,
      bool mine = false,
    }) => HeatmapTile(
      symbol: symbol,
      name: symbol,
      close: 100,
      marketCap: cap,
      baseCap: baseCap ?? _baseCapOf(cap, change),
      change: change,
      isMine: mine,
    );

    HeatmapIndustry industry(String name, List<HeatmapTile> tiles) =>
        HeatmapIndustry(
          name: name,
          marketCap: tiles.fold(0.0, (a, t) => a + t.marketCap),
          weightedChangePercent: 1,
          tiles: tiles,
        );

    HeatmapIndustryLayout only(List<HeatmapTile> tiles) =>
        layoutHeatmap([industry('A', tiles)], width: 400, height: 300).single;

    test('預期面積太小的個股合成一塊，面積＝它們市值的占比', () {
      final l = only([
        tile('A0', 1000),
        for (var i = 0; i < 30; i++) tile('S$i', 1),
      ]);
      expect(l.tiles.map((t) => t.tile.symbol), ['A0']);
      final other = l.other!;
      expect(other.members, hasLength(30));
      expect(other.wholeIndustry, isFalse);
      expect(other.marketCap, 30);
      expect(
        _area(other.bounds),
        closeTo(_area(_content(l)) * 30 / 1030, 1e-6),
      );
      // 合併塊與格子不重疊、一起鋪滿內容區
      expect(_overlap(other.bounds, l.tiles.single.bounds), closeTo(0, 1e-9));
      expect(
        _area(other.bounds) + _area(l.tiles.single.bounds),
        closeTo(_area(_content(l)), 1e-6),
      );
    });

    test('門檻含等號：預期面積剛好等於門檻不合併、略小就合併', () {
      // 364×340：內縮後 360×336、扣標題列 16 → 格子區 360×320 = 115,200；
      // 占比 1/100 的預期面積剛好是 1,152（浮點數也剛好）
      HeatmapIndustryLayout at(List<double> caps) => layoutHeatmap(
        [
          industry('A', [
            for (var i = 0; i < caps.length; i++) tile('A$i', caps[i]),
          ]),
        ],
        width: 364,
        height: 340,
      ).single;
      final exact = at([98, 1, 1]);
      expect(_area(_content(exact)), 115200, reason: '前提：格子區面積');
      expect(1 / 100 * 115200, minArea, reason: '前提：浮點數剛好等於門檻');
      expect(exact.other, isNull);
      expect(at([98.02, 0.99, 0.99]).other!.members, hasLength(2));
    });

    test('只有一檔太小時不合併', () {
      final l = only([tile('A0', 1000), tile('S0', 1)]);
      expect(l.other, isNull);
      expect(l.tiles, hasLength(2));
    });

    test('自選或持股照樣合併，合併塊數得出含幾檔', () {
      // 太小的自選格子寫不下名稱、認不出是哪一檔：一起合併，由合併塊標示
      final l = only([
        tile('A0', 1000, mine: true),
        for (var i = 0; i < 30; i++) tile('S$i', 1, mine: i < 2),
      ]);
      expect(l.other!.members, hasLength(30));
      expect(l.tiles.map((t) => t.tile.symbol), ['A0'], reason: '夠大的照舊單獨畫');
      expect(l.other!.mineCount, 2);
      final none = only([
        tile('A0', 1000),
        for (var i = 0; i < 30; i++) tile('S$i', 1),
      ]);
      expect(none.other!.mineCount, 0);
    });

    test('整個產業都太小：只有一塊、標成整個產業', () {
      final layout = layoutHeatmap(
        [
          industry('A', [tile('A0', 1e6)]),
          industry('B', [for (var i = 0; i < 5; i++) tile('B$i', 1)]),
        ],
        width: 400,
        height: 300,
      );
      final b = layout.firstWhere((l) => l.industry.key == 'B');
      expect(b.tiles, isEmpty);
      expect(b.other!.wholeIndustry, isTrue);
      expect(b.other!.members, hasLength(5));
    });

    test('整個產業都合併時，漲跌直接用產業的值（與標題列同一個數）', () {
      // 產業的值刻意與成員反推的值（+1）不同，才分得出用的是哪一個
      final layout = layoutHeatmap(
        [
          industry('A', [tile('A0', 1e6)]),
          HeatmapIndustry(
            name: 'B',
            marketCap: 5,
            weightedChangePercent: 1.23,
            tiles: [for (var i = 0; i < 5; i++) tile('B$i', 1)],
          ),
        ],
        width: 400,
        height: 300,
      );
      final b = layout.firstWhere((l) => l.industry.key == 'B');
      expect(b.other!.wholeIndustry, isTrue, reason: '前提：整個產業合併');
      expect(b.other!.weightedChangePercent, 1.23);
    });

    test('合併塊的漲跌以平盤市值加權、家數照四捨五入後的方向', () {
      final l = only([
        tile('A0', 1e6),
        // 平盤市值各 100：+10% 與 −10% 加權後 0
        tile('S0', 110, change: const TileChangeValue(10)),
        tile('S1', 90, change: const TileChangeValue(-10)),
        tile('S2', 0.0001, change: const TileChangeValue(0.004)),
        tile(
          'S3',
          0.0001,
          change: const TileChangeHollow(HollowReason.noChangeData),
        ),
      ]);
      final other = l.other!;
      expect(other.weightedChangePercent, closeTo(0, 1e-6));
      expect(other.breadth, (up: 1, down: 1, flat: 1, hollow: 1));
    });

    test('平盤市值 0 的有值成員不參與，其他成員照常加權', () {
      final l = only([
        tile('A0', 1e6),
        tile('S0', 1, change: const TileChangeValue(-100), baseCap: 0),
        tile('S1', 1, change: const TileChangeValue(2)),
      ]);
      expect(l.other!.weightedChangePercent, closeTo(2, 1e-9));
    });

    test('合併塊的漲跌用格子帶的平盤市值，不從市值與漲跌幅反推', () {
      // 兩檔市值 1,000、平盤市值 1,000、+5% 與 −5%：加權後 0。從市值反推平盤
      // 市值（1,000 ÷ 1.05、1,000 ÷ 0.95）會得到約 −0.25%
      final l = only([
        tile('A0', 1e6),
        tile('S0', 1000, change: const TileChangeValue(5), baseCap: 1000),
        tile('S1', 1000, change: const TileChangeValue(-5), baseCap: 1000),
      ]);
      expect(l.other!.weightedChangePercent, closeTo(0, 1e-12));
    });

    test('合併塊的 coverage：有漲跌值的成員市值占成員市值合計', () {
      const hollow = TileChangeHollow(HollowReason.noChangeData);
      final l = only([
        tile('A0', 1e6),
        tile('S0', 300),
        tile('S1', 100, change: hollow),
      ]);
      expect(l.other!.members.map((t) => t.symbol), ['S0', 'S1']);
      expect(l.other!.coverage, 0.75);
    });

    test('合併的成員全是空心：沒有加權漲跌', () {
      const hollow = TileChangeHollow(HollowReason.noChangeData);
      final l = only([
        tile('A0', 1e6),
        tile('S0', 1, change: hollow),
        tile('S1', 1, change: hollow),
      ]);
      expect(l.other!.weightedChangePercent, isNull);
    });

    test('其他塊：coverage 納入 ==／hashCode', () {
      final other = only([
        tile('A0', 1e6),
        tile('S0', 300),
        tile('S1', 100),
      ]).other!;
      HeatmapOtherLayout withCoverage(double coverage) => HeatmapOtherLayout(
        members: other.members,
        bounds: other.bounds,
        paint: other.paint,
        interactive: other.interactive,
        wholeIndustry: other.wholeIndustry,
        marketCap: other.marketCap,
        weightedChangePercent: other.weightedChangePercent,
        breadth: other.breadth,
        coverage: coverage,
      );
      expect(other.coverage, 1.0, reason: '前提：成員都有值');
      expect(withCoverage(1.0), other);
      expect(withCoverage(1.0).hashCode, other.hashCode);
      expect(withCoverage(0.5), isNot(other));
      expect(withCoverage(0.5).hashCode, isNot(other.hashCode));
    });

    test('otherAt：點在合併塊上回該產業與合併塊；格子上回 null', () {
      final layout = [
        only([tile('A0', 1000), for (var i = 0; i < 30; i++) tile('S$i', 1)]),
      ];
      final other = layout.single.other!;
      expect(other.interactive, isTrue);
      final p = other.paint;
      final hit = otherAt(layout, p.left + p.width / 2, p.top + p.height / 2);
      expect(hit?.other, other);
      expect(hit?.industry, layout.single);
      final t = layout.single.tiles.single.paint;
      expect(
        otherAt(layout, t.left + t.width / 2, t.top + t.height / 2),
        isNull,
      );
    });

    test('otherAt：合併塊被擠成細條、不可互動時回 null', () {
      // 只有一檔大的加合併塊：合併塊只占約 0.4%，排成不到 4px 寬的細條
      final layout = [
        only([tile('A0', 1e12), for (var i = 0; i < 40; i++) tile('S$i', 1e8)]),
      ];
      final other = layout.single.other!;
      expect(other.interactive, isFalse);
      final p = other.paint;
      expect(p.width * p.height, greaterThan(0), reason: '前提：有面積');
      expect(
        otherAt(layout, p.left + p.width / 2, p.top + p.height / 2),
        isNull,
      );
    });
  });

  group('小產業合成一塊（全市場）', () {
    const minArea =
        HeatmapParams.industryFoldMinSide *
        HeatmapParams.industryFoldMinSide *
        HeatmapParams.foldAspectAllowance;

    HeatmapTile stock(
      String symbol,
      double cap, {
      TileChange change = const TileChangeValue(1),
      double? baseCap,
      bool mine = false,
    }) => HeatmapTile(
      symbol: symbol,
      name: symbol,
      close: 100,
      marketCap: cap,
      baseCap: baseCap ?? _baseCapOf(cap, change),
      change: change,
      isMine: mine,
    );

    HeatmapIndustry ind(String name, List<HeatmapTile> tiles) =>
        HeatmapIndustry(
          name: name,
          marketCap: tiles.fold(0.0, (a, t) => a + t.marketCap),
          weightedChangePercent: 1,
          tiles: tiles,
        );

    HeatmapIndustry one(String name, double cap) =>
        ind(name, [stock('${name}0', cap)]);

    test('預期面積放不下標題列的產業合成一塊，面積＝它們市值的占比', () {
      // 400×300＝120,000：B 占 7%（8,400）留著；S 各占 1%（1,200）合併
      final l = layoutHeatmapMarket(
        [
          one('A', 900),
          one('B', 70),
          one('S1', 10),
          one('S2', 10),
          one('S3', 10),
        ],
        width: 400,
        height: 300,
      );
      expect(l.industries.map((i) => i.industry.key), ['A', 'B']);
      final g = l.smallIndustries!;
      expect(g.members.map((i) => i.key), ['S1', 'S2', 'S3']);
      expect(g.marketCap, 30);
      expect(_area(g.bounds), closeTo(120000 * 30 / 1000, 1e-6));
      // 與產業區塊不重疊、一起鋪滿圖區
      for (final i in l.industries) {
        expect(_overlap(g.bounds, i.bounds), closeTo(0, 1e-9));
      }
      expect(
        l.industries.fold(0.0, (a, i) => a + _area(i.bounds)) + _area(g.bounds),
        closeTo(120000, 1e-6),
      );
      // 畫的範圍與產業區塊一樣內縮半個產業間隔
      const d = HeatmapParams.industryGap / 2;
      expect(g.paint, (
        left: g.bounds.left + d,
        top: g.bounds.top + d,
        width: g.bounds.width - 2 * d,
        height: g.bounds.height - 2 * d,
      ));
      expect(g.interactive, isTrue);
    });

    test('門檻含等號：預期面積剛好等於門檻不合併、略小就合併', () {
      // 880×440＝387,200：占比 1/100 的預期面積剛好是 3,872（浮點數也剛好）
      HeatmapMarketLayout at(List<double> caps) => layoutHeatmapMarket(
        [for (var i = 0; i < caps.length; i++) one('I$i', caps[i])],
        width: 880,
        height: 440,
      );
      expect(1 / 100 * (880 * 440), minArea, reason: '前提：浮點數剛好等於門檻');
      expect(at([98, 1, 1]).smallIndustries, isNull);
      expect(at([98.02, 0.99, 0.99]).smallIndustries!.members, hasLength(2));
    });

    test('只有一個產業太小時不合併', () {
      final l = layoutHeatmapMarket(
        [one('A', 900), one('B', 90), one('S', 10)],
        width: 400,
        height: 300,
      );
      expect(l.smallIndustries, isNull);
      expect(l.industries.map((i) => i.industry.key), ['A', 'B', 'S']);
    });

    test('每個產業都太小時不合併（沒有別的產業可以並排）', () {
      // 50×50＝2,500，連整張圖都小於門檻
      final l = layoutHeatmapMarket(
        [one('A', 60), one('B', 40)],
        width: 50,
        height: 50,
      );
      expect(l.smallIndustries, isNull);
      expect(l.industries, hasLength(2));
    });

    test('沒有要合併的時候，產業佈局與 layoutHeatmap 相同', () {
      final industries = [one('A', 600), one('B', 400)];
      expect(
        layoutHeatmapMarket(industries, width: 400, height: 300).industries,
        layoutHeatmap(industries, width: 400, height: 300),
      );
    });

    test('合併塊的漲跌：成員的個股以平盤市值加權；家數、檔數、自選檔數', () {
      const hollow = TileChangeHollow(HollowReason.noChangeData);
      final l = layoutHeatmapMarket(
        [
          one('A', 1e6),
          // 平盤市值各 100：+10% 與 −10% 加權後 0
          ind('S1', [
            stock('S1a', 110, change: const TileChangeValue(10), mine: true),
            stock('S1b', 0.0001, change: hollow),
          ]),
          ind('S2', [
            stock('S2a', 90, change: const TileChangeValue(-10)),
            stock('S2b', 0.0001, change: const TileChangeValue(0.004)),
          ]),
        ],
        width: 400,
        height: 300,
      );
      final g = l.smallIndustries!;
      expect(g.weightedChangePercent, closeTo(0, 1e-6));
      expect(g.breadth, (up: 1, down: 1, flat: 1, hollow: 1));
      expect(g.stockCount, 4);
      expect(g.mineCount, 1);
    });

    test('合併塊的 coverage：成員所有個股中有漲跌值的市值占比', () {
      const hollow = TileChangeHollow(HollowReason.noChangeData);
      final l = layoutHeatmapMarket(
        [
          one('A', 1e6),
          ind('S1', [stock('S1a', 300), stock('S1b', 100, change: hollow)]),
          ind('S2', [stock('S2a', 200), stock('S2b', 200, change: hollow)]),
        ],
        width: 400,
        height: 300,
      );
      // (300 + 200) ÷ (300 + 100 + 200 + 200)
      expect(l.smallIndustries!.coverage, 0.625);
    });

    test('小產業合併塊：coverage 納入 ==／hashCode', () {
      final g = layoutHeatmapMarket(
        [one('A', 1e6), one('S1', 10), one('S2', 10)],
        width: 400,
        height: 300,
      ).smallIndustries!;
      HeatmapIndustryGroupLayout withCoverage(double coverage) =>
          HeatmapIndustryGroupLayout(
            members: g.members,
            bounds: g.bounds,
            paint: g.paint,
            interactive: g.interactive,
            marketCap: g.marketCap,
            weightedChangePercent: g.weightedChangePercent,
            breadth: g.breadth,
            coverage: coverage,
          );
      expect(g.coverage, 1.0, reason: '前提：成員都有值');
      expect(withCoverage(1.0), g);
      expect(withCoverage(1.0).hashCode, g.hashCode);
      expect(withCoverage(0.5), isNot(g));
      expect(withCoverage(0.5).hashCode, isNot(g.hashCode));
    });

    test('合併塊照市值排進降冪序列（比它小的產業排在它後面）', () {
      // 合併塊 80 比 B 的 50 大：切的順序是 850、80、50
      final m = layoutHeatmapMarket(
        [
          one('A', 850),
          one('B', 50),
          one('S1', 30),
          one('S2', 25),
          one('S3', 25),
        ],
        width: 400,
        height: 300,
      );
      expect(m.smallIndustries!.members.map((i) => i.key), ['S1', 'S2', 'S3']);
      final boxes = squarify(
        [850, 80, 50],
        (left: 0, top: 0, width: 400, height: 300),
      );
      expect(m.smallIndustries!.bounds, boxes[1]);
      expect(m.industries.map((i) => i.bounds), [boxes[0], boxes[2]]);
    });

    test('smallIndustriesAt：合併塊被擠成細條、不可互動時回 null', () {
      // 一個很大的產業加合併塊：合併塊只占約 1.5%，排成約 6px 寬的細條（內縮
      // 半個產業間隔後約 2px）
      final l = layoutHeatmapMarket(
        [one('A', 1e6), one('S1', 7500), one('S2', 7500)],
        width: 400,
        height: 300,
      );
      final g = l.smallIndustries!;
      expect(g.interactive, isFalse);
      final p = g.paint;
      expect(p.width * p.height, greaterThan(0), reason: '前提：有面積');
      expect(
        smallIndustriesAt(l, p.left + p.width / 2, p.top + p.height / 2),
        isNull,
      );
    });

    test('smallIndustriesAt：點在合併塊上回它；產業上回 null', () {
      final l = layoutHeatmapMarket(
        [one('A', 900), one('B', 70), one('S1', 15), one('S2', 15)],
        width: 400,
        height: 300,
      );
      final p = l.smallIndustries!.paint;
      expect(
        smallIndustriesAt(l, p.left + p.width / 2, p.top + p.height / 2),
        l.smallIndustries,
      );
      final a = l.industries.first.bounds;
      expect(
        smallIndustriesAt(l, a.left + a.width / 2, a.top + a.height / 2),
        isNull,
      );
    });
  });
}

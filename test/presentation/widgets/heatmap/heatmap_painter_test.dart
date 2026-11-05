import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';

HeatmapTile _tile(
  String symbol,
  double cap,
  TileChange change, {
  String? name,
  bool isMine = false,
}) => HeatmapTile(
  symbol: symbol,
  name: name ?? '測試$symbol',
  close: 100,
  marketCap: cap,
  change: change,
  isMine: isMine,
);

final _industries = [
  HeatmapIndustry(
    name: 'A',
    marketCap: 300,
    weightedChangePercent: 1,
    tiles: [
      _tile('9901', 200, const TileChangeValue(1)),
      _tile('9902', 100, const TileChangeHollow(HollowReason.noChangeData)),
    ],
  ),
  HeatmapIndustry(
    name: 'B',
    marketCap: 100,
    weightedChangePercent: -1,
    tiles: [_tile('9911', 100, const TileChangeValue(-1))],
  ),
];

String _industryLabel(HeatmapIndustryLayout l) => 'industry:${l.industry.key}';
String _tileLabel(HeatmapTileLayout t) => 'tile:${t.tile.symbol}';
String _otherLabel(int count) => 'other:$count';
String _wholeLabel(int count) => 'all:$count';
String _otherSemantics(HeatmapIndustryLayout l, HeatmapOtherLayout o) =>
    'other:${l.industry.key}:${o.members.length}';
String _groupLabel(int count) => 'group:$count';
String _groupSemantics(HeatmapIndustryGroupLayout g) =>
    'group:${g.members.length}';

const _labels = HeatmapPaintLabels(
  uncategorized: '未分類',
  industrySemantics: _industryLabel,
  tileSemantics: _tileLabel,
  otherLabel: _otherLabel,
  otherShortLabel: 'oth',
  wholeLabel: _wholeLabel,
  otherSemantics: _otherSemantics,
  groupLabel: _groupLabel,
  groupShortLabel: 'grp',
  groupSemantics: _groupSemantics,
);

void _ignore(String _) {}
void _ignoreOther(HeatmapIndustryLayout _, HeatmapOtherLayout _) {}
void _ignoreGroup(HeatmapIndustryGroupLayout _) {}

HeatmapPainter _painter(
  List<HeatmapIndustryLayout> layout, {
  Brightness brightness = Brightness.light,
  bool zoomed = false,
  HeatmapPaintLabels? labels,
  ValueChanged<String> onIndustryTap = _ignore,
  ValueChanged<String> onTileTap = _ignore,
  HeatmapOtherTap onOtherTap = _ignoreOther,
  HeatmapIndustryGroupLayout? smallIndustries,
  ValueChanged<HeatmapIndustryGroupLayout> onSmallIndustriesTap = _ignoreGroup,
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) => HeatmapPainter(
  layout: layout,
  smallIndustries: smallIndustries,
  onSmallIndustriesTap: onSmallIndustriesTap,
  brightness: brightness,
  zoomed: zoomed,
  labels: labels ?? _labels,
  onIndustryTap: onIndustryTap,
  onTileTap: onTileTap,
  onOtherTap: onOtherTap,
  fontFamily: fontFamily,
  fontFamilyFallback: fontFamilyFallback,
);

/// 單一格子、沒有產業標題的佈局（直接指定格子大小，畫布呼叫只來自這一格）
List<HeatmapIndustryLayout> _oneTile(HeatmapTile tile, Rect r) {
  final box = (left: r.left, top: r.top, width: r.width, height: r.height);
  return [
    HeatmapIndustryLayout(
      industry: HeatmapIndustry(
        name: 'A',
        marketCap: tile.marketCap,
        weightedChangePercent: 1,
        tiles: [tile],
      ),
      bounds: box,
      header: null,
      tiles: [
        HeatmapTileLayout(
          tile: tile,
          bounds: box,
          paint: box,
          interactive: true,
        ),
      ],
    ),
  ];
}

void Function(Canvas) _paintFn(List<HeatmapIndustryLayout> layout) =>
    (canvas) => _painter(layout).paint(canvas, const Size(400, 300));

List<String> _semanticLabels(HeatmapPainter p) => [
  for (final node in p.semanticsBuilder(const Size(400, 300)))
    node.properties.label!,
];

void main() {
  final layout = layoutHeatmap(_industries, width: 400, height: 300);

  group('shouldRepaint', () {
    test('同樣佈局與主題不要求重畫', () {
      expect(_painter(layout).shouldRepaint(_painter(layout)), isFalse);
    });

    test('主題改變要重畫', () {
      expect(
        _painter(
          layout,
          brightness: Brightness.dark,
        ).shouldRepaint(_painter(layout)),
        isTrue,
      );
    });

    test('放大狀態改變要重畫', () {
      expect(
        _painter(layout, zoomed: true).shouldRepaint(_painter(layout)),
        isTrue,
      );
    });

    test('佈局換成另一個物件要重畫', () {
      final other = layoutHeatmap(_industries, width: 400, height: 300);
      expect(_painter(other).shouldRepaint(_painter(layout)), isTrue);
    });

    test('字族改變要重畫；備援字族內容相同不重畫', () {
      expect(
        _painter(layout, fontFamily: 'A').shouldRepaint(_painter(layout)),
        isTrue,
      );
      expect(
        _painter(
          layout,
          fontFamilyFallback: ['B'],
        ).shouldRepaint(_painter(layout, fontFamilyFallback: ['C'])),
        isTrue,
      );
      expect(
        _painter(
          layout,
          fontFamilyFallback: ['B'],
        ).shouldRepaint(_painter(layout, fontFamilyFallback: ['B'])),
        isFalse,
      );
    });

    test('labels 改變要重畫', () {
      const other = HeatmapPaintLabels(
        uncategorized: 'Uncategorized',
        industrySemantics: _industryLabel,
        tileSemantics: _tileLabel,
        otherLabel: _otherLabel,
        otherShortLabel: 'oth',
        wholeLabel: _wholeLabel,
        otherSemantics: _otherSemantics,
        groupLabel: _groupLabel,
        groupShortLabel: 'grp',
        groupSemantics: _groupSemantics,
      );
      expect(
        _painter(layout, labels: other).shouldRepaint(_painter(layout)),
        isTrue,
      );
    });
  });

  test('labels 換了描述函式也要重畫', () {
    String otherIndustryLabel(HeatmapIndustryLayout l) => 'x';
    final other = HeatmapPaintLabels(
      uncategorized: '未分類',
      industrySemantics: otherIndustryLabel,
      tileSemantics: _tileLabel,
      otherLabel: _otherLabel,
      otherShortLabel: 'oth',
      wholeLabel: _wholeLabel,
      otherSemantics: _otherSemantics,
      groupLabel: _groupLabel,
      groupShortLabel: 'grp',
      groupSemantics: _groupSemantics,
    );
    expect(
      _painter(layout, labels: other).shouldRepaint(_painter(layout)),
      isTrue,
    );
  });

  group('shouldRebuildSemantics', () {
    void other(String _) {}

    test('同樣的佈局與回呼不重建', () {
      expect(
        _painter(layout).shouldRebuildSemantics(_painter(layout)),
        isFalse,
      );
    });

    test('產業回呼換了要重建（不要求重畫）', () {
      final next = _painter(layout, onIndustryTap: other);
      expect(next.shouldRepaint(_painter(layout)), isFalse);
      expect(next.shouldRebuildSemantics(_painter(layout)), isTrue);
    });

    test('合併塊回呼換了要重建', () {
      void other(HeatmapIndustryLayout _, HeatmapOtherLayout _) {}
      expect(
        _painter(
          layout,
          onOtherTap: other,
        ).shouldRebuildSemantics(_painter(layout)),
        isTrue,
      );
    });

    test('格子回呼換了要重建', () {
      expect(
        _painter(
          layout,
          onTileTap: other,
        ).shouldRebuildSemantics(_painter(layout)),
        isTrue,
      );
    });

    test('需要重畫時也重建', () {
      expect(
        _painter(
          layout,
          brightness: Brightness.dark,
        ).shouldRebuildSemantics(_painter(layout)),
        isTrue,
      );
    });
  });

  test('無障礙節點的點擊動作帶產業 key／代號', () {
    String? industry;
    String? tile;
    final nodes = _painter(
      layout,
      onIndustryTap: (k) => industry = k,
    ).semanticsBuilder(const Size(400, 300));
    nodes[1].properties.onTap!();
    expect(industry, 'B');

    final zoomedLayout = layoutHeatmap(
      [_industries.first],
      width: 400,
      height: 300,
    );
    final tileNodes = _painter(
      zoomedLayout,
      zoomed: true,
      onTileTap: (s) => tile = s,
    ).semanticsBuilder(const Size(400, 300));
    tileNodes[1].properties.onTap!();
    expect(tile, '9902');
  });

  test('未放大時無障礙節點＝產業數；放大時＝可互動格子數', () {
    expect(_semanticLabels(_painter(layout)), ['industry:A', 'industry:B']);
    final zoomedLayout = layoutHeatmap(
      [_industries.first],
      width: 400,
      height: 300,
    );
    expect(_semanticLabels(_painter(zoomedLayout, zoomed: true)), [
      'tile:9901',
      'tile:9902',
    ]);
  });

  test('放大時不給非互動格子無障礙節點', () {
    final tinyLayout = layoutHeatmap(
      [
        HeatmapIndustry(
          name: 'A',
          marketCap: 1000.000001,
          weightedChangePercent: 1,
          tiles: [
            _tile('9901', 1000, const TileChangeValue(1)),
            _tile('9902', 0.000001, const TileChangeValue(1)),
          ],
        ),
      ],
      width: 400,
      height: 300,
    );
    expect(_semanticLabels(_painter(tinyLayout, zoomed: true)), ['tile:9901']);
  });

  group('畫布', () {
    const r = Rect.fromLTWH(10, 10, 100, 60);

    test('自選格子：先填色、再畫外黑框、最後畫內白框', () {
      const change = TileChangeValue(1);
      final fill = heatmapTileStyle(change, Brightness.light).fill!;
      final fn = _paintFn(
        _oneTile(_tile('9901', 100, change, isMine: true), r),
      );
      expect(
        fn,
        paints
          ..rect(rect: r, color: fill, style: PaintingStyle.fill)
          ..rect(
            rect: r.deflate(0.5),
            color: HeatmapColors.mineOuter,
            style: PaintingStyle.stroke,
          )
          ..rect(
            rect: r.deflate(1.5),
            color: HeatmapColors.mineInner,
            style: PaintingStyle.stroke,
          ),
      );
      expect(fn, paintsExactlyCountTimes(#drawRect, 3));
    });

    test('空心格子只畫邊框、不填色', () {
      final fn = _paintFn(
        _oneTile(
          _tile('9902', 100, const TileChangeHollow(HollowReason.noChangeData)),
          r,
        ),
      );
      expect(
        fn,
        paints..rect(
          rect: r.deflate(0.5),
          color: HeatmapColors.hollowBorder(Brightness.light),
          style: PaintingStyle.stroke,
        ),
      );
      expect(fn, paintsExactlyCountTimes(#drawRect, 1));
    });

    // 測試字型每字 11×11、行高 11；左右各留 2：「測試9901」「+1.00%」都是 66 寬，
    // 最短可接受的名稱「測試…」33 寬
    const value = TileChangeValue(1);
    const hollow = TileChangeHollow(HollowReason.noChangeData);
    for (final (desc, change, name, width, height, count) in [
      ('有漲跌、夠大：名稱＋漲跌幅', value, null, 100.0, 60.0, 2),
      ('有漲跌、只放得下一行：只寫名稱', value, null, 100.0, 20.0, 1),
      ('有漲跌、漲跌幅寫不下：只寫名稱（縮短）', value, null, 50.0, 60.0, 1),
      ('有漲跌、連兩個字＋…都放不下：不寫', value, null, 30.0, 60.0, 0),
      ('有漲跌、一行都放不下：不寫', value, null, 100.0, 10.0, 0),
      ('兩個字的名稱不必縮：照寫', value, '測試', 30.0, 60.0, 1),
      ('左右留白要扣：寬 35（可用 31）放不下「測試…」33', value, null, 35.0, 60.0, 0),
      ('空心、夠大：只寫名稱', hollow, null, 100.0, 60.0, 1),
      ('空心、一行都放不下：不寫', hollow, null, 100.0, 10.0, 0),
      ('空心、連兩個字＋…都放不下：不寫', hollow, null, 30.0, 60.0, 0),
    ]) {
      test('文字：$desc', () {
        final fn = _paintFn(
          _oneTile(
            _tile('9901', 100, change, name: name),
            Rect.fromLTWH(0, 0, width, height),
          ),
        );
        expect(fn, paintsExactlyCountTimes(#drawParagraph, count));
      });
    }

    test('大格子的名稱與漲跌幅都放大（置中位置照放大後的字寬算）', () {
      // 400×300：字級 22，「測試9901」「+1.00%」都是 6 字 × 22 = 132 寬，
      // 置中於 (400 − 132) / 2 = 134
      bool centered(Offset o) => (o.dx - 134).abs() < 0.01;
      expect(
        _paintFn(
          _oneTile(
            _tile('9901', 100, value),
            const Rect.fromLTWH(0, 0, 400, 300),
          ),
        ),
        paints
          ..paragraph(offset: predicate<Offset>(centered))
          ..paragraph(offset: predicate<Offset>(centered)),
      );
    });

    test('縮短的名稱不超出格子', () {
      final fn = _paintFn(
        _oneTile(_tile('9901', 100, value), const Rect.fromLTWH(0, 0, 50, 60)),
      );
      expect(
        fn,
        paints..paragraph(offset: predicate<Offset>((o) => o.dx >= 0)),
      );
    });

    // 產業標題：「半導體業」44 寬、「 -1.06%」77 寬、「半導…」33 寬；左右各留 2
    List<HeatmapIndustryLayout> header(double width, double? pct) => [
      HeatmapIndustryLayout(
        industry: HeatmapIndustry(
          name: '半導體業',
          marketCap: 1,
          weightedChangePercent: pct,
          tiles: const [],
        ),
        bounds: (left: 0, top: 0, width: width, height: 100),
        header: (left: 0, top: 0, width: width, height: 16),
        tiles: const [],
      ),
    ];
    test('產業標題縮短名稱時，漲跌幅緊接在「半導…」後面、完整落在標題列內', () {
      // 寬 120：名稱可用 116 − 77 = 39，縮成「半導…」33 寬；漲跌幅從 2 + 33 起
      expect(
        _paintFn(header(120, -1.06)),
        paints
          ..paragraph()
          ..paragraph(
            offset: predicate<Offset>((o) => (o.dx - 35).abs() < 0.01),
          ),
      );
    });

    for (final (desc, width, pct, count) in [
      ('放得下：名稱與漲跌幅', 200.0, -1.06, 2),
      ('放不下：縮名稱、漲跌幅完整', 120.0, -1.06, 2),
      ('連兩個字＋…＋漲跌幅都放不下：只寫名稱', 100.0, -1.06, 1),
      ('沒有漲跌：只寫名稱', 200.0, null, 1),
      ('左右留白要扣：寬 37（可用 33）放得下「半導…」', 37.0, null, 1),
      ('左右留白要扣：寬 36（可用 32）什麼都不寫', 36.0, null, 0),
    ]) {
      test('產業標題：$desc', () {
        expect(
          _paintFn(header(width, pct)),
          paintsExactlyCountTimes(#drawParagraph, count),
        );
      });
    }
  });

  group('合併塊', () {
    HeatmapBox box(Rect r) =>
        (left: r.left, top: r.top, width: r.width, height: r.height);

    HeatmapOtherLayout other(
      Rect r, {
      double? pct = 1,
      bool whole = false,
      int count = 3,
      int mine = 0,
    }) => HeatmapOtherLayout(
      members: [
        for (var i = 0; i < count; i++)
          _tile('${9950 + i}', 1, const TileChangeValue(1), isMine: i < mine),
      ],
      bounds: box(r),
      paint: box(r),
      interactive: true,
      wholeIndustry: whole,
      marketCap: count.toDouble(),
      weightedChangePercent: pct,
      breadth: (up: count, down: 0, flat: 0, hollow: 0),
    );

    List<HeatmapIndustryLayout> withOther(
      HeatmapOtherLayout o, {
      HeatmapBox? header,
    }) => [
      HeatmapIndustryLayout(
        industry: const HeatmapIndustry(
          name: '甲業',
          marketCap: 3,
          weightedChangePercent: 1,
          tiles: [],
        ),
        bounds: o.bounds,
        header: header,
        tiles: const [],
        other: o,
      ),
    ];

    test('照加權漲跌填色，寫「其他 N 檔」與漲跌幅', () {
      const r = Rect.fromLTWH(0, 0, 200, 100);
      final fill = heatmapTileStyle(
        const TileChangeValue(1),
        Brightness.light,
      ).fill!;
      final fn = _paintFn(withOther(other(r)));
      expect(fn, paints..rect(rect: r, color: fill));
      expect(fn, paintsExactlyCountTimes(#drawParagraph, 2));
    });

    test('成員有自選或持股：整塊加自選框（與格子同樣的雙線）', () {
      const r = Rect.fromLTWH(0, 0, 200, 100);
      final fill = heatmapTileStyle(
        const TileChangeValue(1),
        Brightness.light,
      ).fill!;
      final fn = _paintFn(withOther(other(r, mine: 1)));
      expect(
        fn,
        paints
          ..rect(rect: r, color: fill, style: PaintingStyle.fill)
          ..rect(
            rect: r.deflate(0.5),
            color: HeatmapColors.mineOuter,
            style: PaintingStyle.stroke,
          )
          ..rect(
            rect: r.deflate(1.5),
            color: HeatmapColors.mineInner,
            style: PaintingStyle.stroke,
          ),
      );
      expect(fn, paintsExactlyCountTimes(#drawRect, 3));
      expect(
        _paintFn(withOther(other(r))),
        paintsExactlyCountTimes(#drawRect, 1),
        reason: '沒有自選或持股不畫框',
      );
    });

    test('成員全是空心：只畫邊框、只寫標籤', () {
      const r = Rect.fromLTWH(0, 0, 200, 100);
      final fn = _paintFn(withOther(other(r, pct: null)));
      expect(
        fn,
        paints..rect(
          rect: r.deflate(0.5),
          color: HeatmapColors.hollowBorder(Brightness.light),
          style: PaintingStyle.stroke,
        ),
      );
      expect(fn, paintsExactlyCountTimes(#drawRect, 1));
      expect(fn, paintsExactlyCountTimes(#drawParagraph, 1));
    });

    test('「其他 N 檔」放不下時退成短標籤「其他」（不縮短成看不懂的字）', () {
      // 「other:3」7 字 × 11 = 77、「oth」33，可用寬 56；漲跌幅 66 寫不下
      expect(
        _paintFn(withOther(other(const Rect.fromLTWH(0, 0, 60, 60)))),
        paintsExactlyCountTimes(#drawParagraph, 1),
      );
    });

    test('連「其他」都放不下：不寫（不只寫一個數字）', () {
      // 可用寬 32 < 「oth」33；漲跌幅也寫不下
      expect(
        _paintFn(withOther(other(const Rect.fromLTWH(0, 0, 36, 60)))),
        paintsExactlyCountTimes(#drawParagraph, 0),
      );
    });

    test('部分合併：短標籤也放不下時，漲跌幅放得下也不單獨寫', () {
      final labels = HeatmapPaintLabels(
        uncategorized: '未分類',
        industrySemantics: _industryLabel,
        tileSemantics: _tileLabel,
        otherLabel: (count) => 'x' * 30,
        otherShortLabel: 'y' * 30,
        wholeLabel: _wholeLabel,
        otherSemantics: _otherSemantics,
        groupLabel: _groupLabel,
        groupShortLabel: 'grp',
        groupSemantics: _groupSemantics,
      );
      expect(
        (Canvas canvas) => _painter(
          withOther(other(const Rect.fromLTWH(0, 0, 200, 100))),
          labels: labels,
        ).paint(canvas, const Size(400, 300)),
        paintsExactlyCountTimes(#drawParagraph, 0),
      );
    });

    test('整個產業合成一塊、有標題列：漲跌幅也放不下就不寫', () {
      // 40 寬（可用 36）：「+1.00%」66 寫不下；標題列只寫得下「甲業」一段
      expect(
        _paintFn(
          withOther(
            other(const Rect.fromLTWH(0, 16, 40, 100), whole: true),
            header: (left: 0, top: 0, width: 40, height: 16),
          ),
        ),
        paintsExactlyCountTimes(#drawParagraph, 1),
      );
    });

    test('整個產業合成一塊、有標題列：「共 N 檔」放不下時只寫漲跌幅', () {
      final labels = HeatmapPaintLabels(
        uncategorized: '未分類',
        industrySemantics: _industryLabel,
        tileSemantics: _tileLabel,
        otherLabel: _otherLabel,
        otherShortLabel: 'oth',
        wholeLabel: (count) => 'x' * 30,
        otherSemantics: _otherSemantics,
        groupLabel: _groupLabel,
        groupShortLabel: 'grp',
        groupSemantics: _groupSemantics,
      );
      // 標題列 200 寬：「甲業」＋「 +1.00%」兩段；合併塊只寫漲跌幅一段
      expect(
        (Canvas canvas) => _painter(
          withOther(
            other(const Rect.fromLTWH(0, 16, 200, 100), whole: true),
            header: (left: 0, top: 0, width: 200, height: 16),
          ),
          labels: labels,
        ).paint(canvas, const Size(400, 300)),
        paintsExactlyCountTimes(#drawParagraph, 3),
      );
    });

    ({List<String> calls, HeatmapPaintLabels labels}) spyLabels() {
      final calls = <String>[];
      return (
        calls: calls,
        labels: HeatmapPaintLabels(
          uncategorized: '未分類',
          industrySemantics: _industryLabel,
          tileSemantics: _tileLabel,
          otherLabel: (count) {
            calls.add('other');
            return 'other:$count';
          },
          otherShortLabel: 'oth',
          wholeLabel: (count) {
            calls.add('whole');
            return 'all:$count';
          },
          otherSemantics: _otherSemantics,
          groupLabel: _groupLabel,
          groupShortLabel: 'grp',
          groupSemantics: _groupSemantics,
        ),
      );
    }

    test('整個產業都合併、沒有標題列：寫產業名稱', () {
      final spy = spyLabels();
      final layout = withOther(
        other(const Rect.fromLTWH(0, 0, 200, 100), whole: true),
      );
      expect(
        (Canvas canvas) => _painter(
          layout,
          labels: spy.labels,
        ).paint(canvas, const Size(400, 300)),
        paintsExactlyCountTimes(#drawParagraph, 2),
      );
      expect(spy.calls, isEmpty);
    });

    test('整個產業都合併、有標題列：寫「共 N 檔」，不重複產業名稱', () {
      final spy = spyLabels();
      final layout = withOther(
        other(const Rect.fromLTWH(0, 16, 200, 100), whole: true),
        header: (left: 0, top: 0, width: 200, height: 16),
      );
      expect(
        (Canvas canvas) => _painter(
          layout,
          labels: spy.labels,
        ).paint(canvas, const Size(400, 300)),
        // 標題列 2 段（名稱、漲跌幅）＋合併塊 2 行
        paintsExactlyCountTimes(#drawParagraph, 4),
      );
      expect(spy.calls, ['whole']);
    });

    test('放大時合併塊有無障礙節點，點擊交給合併塊的回呼；未放大時沒有', () {
      (HeatmapIndustryLayout, HeatmapOtherLayout)? tapped;
      final layout = withOther(other(const Rect.fromLTWH(0, 0, 200, 100)));
      final nodes = _painter(
        layout,
        zoomed: true,
        onOtherTap: (industry, other) => tapped = (industry, other),
      ).semanticsBuilder(const Size(400, 300));
      expect([for (final n in nodes) n.properties.label], ['other:甲業:3']);
      nodes.single.properties.onTap!();
      expect(tapped?.$1, layout.single);
      expect(tapped?.$2, layout.single.other);
      expect(_semanticLabels(_painter(layout)), ['industry:甲業']);
    });
  });

  group('小產業合併塊', () {
    HeatmapBox box(Rect r) =>
        (left: r.left, top: r.top, width: r.width, height: r.height);

    HeatmapIndustryGroupLayout group(
      Rect r, {
      double? pct = 1,
      int mine = 0,
      bool interactive = true,
    }) => HeatmapIndustryGroupLayout(
      members: [
        for (var i = 0; i < 3; i++)
          HeatmapIndustry(
            name: 'S$i',
            marketCap: 1,
            weightedChangePercent: pct,
            tiles: [
              _tile(
                '${9960 + i}',
                1,
                const TileChangeValue(1),
                isMine: i < mine,
              ),
            ],
          ),
      ],
      bounds: box(r),
      paint: box(r),
      interactive: interactive,
      marketCap: 3,
      weightedChangePercent: pct,
      breadth: (up: 3, down: 0, flat: 0, hollow: 0),
    );

    void Function(Canvas) paintGroup(HeatmapIndustryGroupLayout g) =>
        (canvas) => _painter(
          const [],
          smallIndustries: g,
        ).paint(canvas, const Size(400, 300));

    test('照加權漲跌填色，寫「其他 N 個產業」與漲跌幅', () {
      const r = Rect.fromLTWH(0, 0, 200, 100);
      final fill = heatmapTileStyle(
        const TileChangeValue(1),
        Brightness.light,
      ).fill!;
      final fn = paintGroup(group(r));
      expect(fn, paints..rect(rect: r, color: fill));
      expect(fn, paintsExactlyCountTimes(#drawRect, 1));
      expect(fn, paintsExactlyCountTimes(#drawParagraph, 2));
    });

    test('成員全是空心：只畫邊框', () {
      const r = Rect.fromLTWH(0, 0, 200, 100);
      expect(
        paintGroup(group(r, pct: null)),
        paints..rect(
          rect: r.deflate(0.5),
          color: HeatmapColors.hollowBorder(Brightness.light),
          style: PaintingStyle.stroke,
        ),
      );
    });

    test('「其他 N 個產業」寫不下退成「其他產業」，再寫不下不寫', () {
      // 「group:3」7 字 × 11 = 77、「grp」33；60 寬可用 56、36 寬可用 32
      expect(
        paintGroup(group(const Rect.fromLTWH(0, 0, 60, 60))),
        paintsExactlyCountTimes(#drawParagraph, 1),
      );
      expect(
        paintGroup(group(const Rect.fromLTWH(0, 0, 36, 60))),
        paintsExactlyCountTimes(#drawParagraph, 0),
      );
    });

    test('成員有自選或持股：整塊加自選框', () {
      const r = Rect.fromLTWH(0, 0, 200, 100);
      expect(
        paintGroup(group(r, mine: 1)),
        paints
          ..rect(rect: r, style: PaintingStyle.fill)
          ..rect(
            rect: r.deflate(0.5),
            color: HeatmapColors.mineOuter,
            style: PaintingStyle.stroke,
          )
          ..rect(
            rect: r.deflate(1.5),
            color: HeatmapColors.mineInner,
            style: PaintingStyle.stroke,
          ),
      );
    });

    test('全市場時有無障礙節點，點它交給回呼；不可互動時沒有', () {
      final g = group(const Rect.fromLTWH(0, 200, 200, 100));
      HeatmapIndustryGroupLayout? tapped;
      final nodes = _painter(
        layout,
        smallIndustries: g,
        onSmallIndustriesTap: (x) => tapped = x,
      ).semanticsBuilder(const Size(400, 300));
      expect(nodes.map((n) => n.properties.label), [
        'industry:A',
        'industry:B',
        'group:3',
      ]);
      nodes.last.properties.onTap!();
      expect(tapped, g);
      expect(
        _semanticLabels(
          _painter(
            layout,
            smallIndustries: group(
              const Rect.fromLTWH(0, 200, 200, 2),
              interactive: false,
            ),
          ),
        ),
        ['industry:A', 'industry:B'],
      );
    });

    test('合併塊換了要重畫；回呼換了要重建無障礙節點', () {
      final g = group(const Rect.fromLTWH(0, 200, 200, 100));
      expect(
        _painter(layout, smallIndustries: g).shouldRepaint(_painter(layout)),
        isTrue,
      );
      void other(HeatmapIndustryGroupLayout _) {}
      final next = _painter(layout, onSmallIndustriesTap: other);
      expect(next.shouldRepaint(_painter(layout)), isFalse);
      expect(next.shouldRebuildSemantics(_painter(layout)), isTrue);
    });

    test('labels 換了合併塊的標籤也要重畫', () {
      const other = HeatmapPaintLabels(
        uncategorized: '未分類',
        industrySemantics: _industryLabel,
        tileSemantics: _tileLabel,
        otherLabel: _otherLabel,
        otherShortLabel: 'oth',
        wholeLabel: _wholeLabel,
        otherSemantics: _otherSemantics,
        groupLabel: _groupLabel,
        groupShortLabel: 'x',
        groupSemantics: _groupSemantics,
      );
      expect(other == _labels, isFalse);
      String g2(int c) => 'g2';
      final other2 = HeatmapPaintLabels(
        uncategorized: '未分類',
        industrySemantics: _industryLabel,
        tileSemantics: _tileLabel,
        otherLabel: _otherLabel,
        otherShortLabel: 'oth',
        wholeLabel: _wholeLabel,
        otherSemantics: _otherSemantics,
        groupLabel: g2,
        groupShortLabel: 'grp',
        groupSemantics: _groupSemantics,
      );
      expect(other2 == _labels, isFalse);
      String s2(HeatmapIndustryGroupLayout g) => 's2';
      final other3 = HeatmapPaintLabels(
        uncategorized: '未分類',
        industrySemantics: _industryLabel,
        tileSemantics: _tileLabel,
        otherLabel: _otherLabel,
        otherShortLabel: 'oth',
        wholeLabel: _wholeLabel,
        otherSemantics: _otherSemantics,
        groupLabel: _groupLabel,
        groupShortLabel: 'grp',
        groupSemantics: s2,
      );
      expect(other3 == _labels, isFalse);
    });
  });

  group('heatmapFitName（每字寬 10，「*」寬 3）', () {
    double measure(String text) =>
        text.runes.fold(0.0, (w, r) => w + (r == 0x2A ? 3 : 10));
    for (final (desc, name, maxWidth, expected) in [
      ('放得下就寫全名', '半導體業', 40.0, '半導體業'),
      ('放不下：取最長的前 N 個字＋…', '電腦及週邊', 45.0, '電腦及…'),
      ('最少兩個字＋…', '半導體業', 30.0, '半導…'),
      ('連兩個字＋…都放不下：不寫', '半導體業', 29.0, null),
      ('兩個字的名稱放不下就不寫（不縮成一個字）', '測試', 19.0, null),
      ('含窄字元時全名比兩個字＋…窄：照寫全名', '測試*', 23.0, '測試*'),
      ('「…」前不留連字號：「測試-…」放得下也寫「測試…」', '測試-KY', 40.0, '測試…'),
      ('去掉連字號後不到兩個字的候選不用（不寫「測-…」）', '測-KY', 30.0, null),
    ]) {
      test(desc, () {
        expect(heatmapFitName(name, maxWidth, measure), expected);
      });
    }
  });

  group('heatmapHeaderLayout（每字寬 10）', () {
    double measure(String text) => text.length * 10.0;
    for (final (desc, name, percent, maxWidth, expected) in [
      ('放得下', '半導體業', '-1.06%', 110.0, (name: '半導體業', showPercent: true)),
      ('放不下：名稱讓出空間', '半導體業', '-1.06%', 105.0, (name: '半導…', showPercent: true)),
      (
        '連兩個字＋…都放不下：不寫漲跌幅',
        '半導體業',
        '-1.06%',
        99.0,
        (name: '半導體業', showPercent: false),
      ),
      ('兩個字的名稱不必縮', '航運', '+0.10%', 90.0, (name: '航運', showPercent: true)),
      ('沒有漲跌：名稱照樣可縮', '半導體業', null, 30.0, (name: '半導…', showPercent: false)),
      ('什麼都放不下', '半導體業', null, 25.0, (name: null, showPercent: false)),
    ]) {
      test(desc, () {
        expect(
          heatmapHeaderLayout(
            name: name,
            percent: percent,
            maxWidth: maxWidth,
            measure: measure,
          ),
          expected,
        );
      });
    }
  });

  group('heatmapTileLines', () {
    for (final (desc, nameFits, percent, width, height, expected) in [
      ('兩行放得下', true, 66.0, 96.0, 22.0, (name: true, percent: true)),
      ('高度只放得下一行：只寫名稱', true, 66.0, 96.0, 21.0, (name: true, percent: false)),
      ('漲跌幅寫不下：只寫名稱', true, 66.0, 65.0, 60.0, (name: true, percent: false)),
      ('名稱放不下：不寫', false, 20.0, 96.0, 60.0, (name: false, percent: false)),
      ('一行都放不下：不寫', true, 66.0, 96.0, 10.0, (name: false, percent: false)),
      ('空心：只寫名稱', true, null, 96.0, 60.0, (name: true, percent: false)),
    ]) {
      test(desc, () {
        expect(
          heatmapTileLines(
            nameFits: nameFits,
            percentWidth: percent,
            lineHeight: 11,
            width: width,
            height: height,
          ),
          expected,
        );
      });
    }
  });

  group('heatmapTileFontSize：格子越大字越大，11～22', () {
    for (final (desc, width, height, expected) in [
      ('小格子維持 11', 60.0, 40.0, 11.0),
      ('寬除以 8、高除以 5 取小', 120.0, 80.0, 15.0),
      ('高度限制', 100.0, 60.0, 12.0),
      ('扁長格子看高度', 200.0, 60.0, 12.0),
      ('大格子封頂 22', 830.0, 650.0, 22.0),
    ]) {
      test(desc, () {
        expect(heatmapTileFontSize(width, height), expected);
      });
    }
  });

  test('最窄的標題列放得下「兩個字＋…」', () {
    final p = TextPainter(
      text: const TextSpan(
        text: '測試…',
        style: TextStyle(fontSize: HeatmapParams.labelFontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(p.dispose);
    expect(
      HeatmapParams.industryHeaderMinWidth - 2 * HeatmapParams.textPadding,
      greaterThanOrEqualTo(p.width),
    );
  });

  test('畫完後建立的 TextPainter 全部 dispose（含標題列與寫不下的名稱）', () {
    var created = 0;
    var disposed = 0;
    void listener(ObjectEvent e) {
      if (e.object is! TextPainter) return;
      if (e is ObjectCreated) created++;
      if (e is ObjectDisposed) disposed++;
    }

    FlutterMemoryAllocations.instance.addListener(listener);
    addTearDown(
      () => FlutterMemoryAllocations.instance.removeListener(listener),
    );
    final withNarrowName = [
      ...layout,
      ..._oneTile(
        _tile('9921', 100, const TileChangeValue(1), name: '測試測試測試測試'),
        const Rect.fromLTWH(0, 0, 80, 60),
      ),
    ];
    expect(layout.every((l) => l.header != null), isTrue, reason: '前提：有標題列');
    final recorder = ui.PictureRecorder();
    _painter(withNarrowName).paint(Canvas(recorder), const Size(400, 300));
    recorder.endRecording().dispose();
    expect(created, greaterThan(0));
    expect(disposed, created);
  });

  test('無障礙節點標成按鈕', () {
    expect(
      _painter(layout)
          .semanticsBuilder(const Size(400, 300))
          .every((n) => n.properties.button ?? false),
      isTrue,
    );
    final zoomedLayout = layoutHeatmap(
      [_industries.first],
      width: 400,
      height: 300,
    );
    expect(
      _painter(zoomedLayout, zoomed: true)
          .semanticsBuilder(const Size(400, 300))
          .every((n) => n.properties.button ?? false),
      isTrue,
    );
  });

  group('格子樣式', () {
    for (final b in Brightness.values) {
      test(b.name, () {
        final hollow = heatmapTileStyle(
          const TileChangeHollow(HollowReason.noChangeData),
          b,
        );
        expect(hollow.fill, isNull);
        expect(hollow.border, HeatmapColors.hollowBorder(b));
        expect(hollow.text, HeatmapColors.hollowText(b));

        final flat = heatmapTileStyle(const TileChangeValue(0), b);
        expect(flat.fill, HeatmapColors.flat(b));
        expect(flat.border, isNull);
        expect(flat.text, HeatmapColors.textOn(HeatmapColors.flat(b)));

        final up = heatmapTileStyle(const TileChangeValue(2), b);
        expect(up.fill, HeatmapColors.fill(step: 3, up: true, brightness: b));

        final down = heatmapTileStyle(const TileChangeValue(-9.5), b);
        expect(
          down.fill,
          HeatmapColors.fill(step: 6, up: false, brightness: b),
        );
        expect(down.text, HeatmapColors.textOn(down.fill!));
      });
    }
  });

  test('formatHeatmapPercent', () {
    expect(formatHeatmapPercent(1.834), '+1.83%');
    expect(formatHeatmapPercent(-0.4), '-0.40%');
    expect(formatHeatmapPercent(0), '0.00%');
    expect(formatHeatmapPercent(9.499999999999998), '+9.50%');
    expect(formatHeatmapPercent(0.004), '0.00%');
    expect(formatHeatmapPercent(-0.004), '0.00%');
  });

  test('formatHeatmapCap：中文以億、其他語系以十億為單位', () {
    expect(formatHeatmapCap(123450000000, const Locale('zh', 'TW')), '1,234.5');
    expect(formatHeatmapCap(123440000000, const Locale('en')), '123.4');
    expect(formatHeatmapCap(1234500000000, const Locale('en')), '1,234.5');
  });
}

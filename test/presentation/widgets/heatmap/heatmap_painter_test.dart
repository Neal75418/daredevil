import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  double close = 100,
}) => HeatmapTile(
  symbol: symbol,
  name: name ?? '測試$symbol',
  industry: null,
  close: close,
  marketCap: cap,
  change: change,
  isMine: isMine,
);

final _tiles = [
  _tile('9901', 200, const TileChangeValue(1)),
  _tile('9902', 100, const TileChangeHollow(HollowReason.noChangeData)),
  _tile('9911', 100, const TileChangeValue(-1)),
];

String _tileLabel(HeatmapTileLayout t) => 'tile:${t.tile.symbol}';

const _zh = Locale('zh', 'TW');

const _labels = HeatmapPaintLabels(locale: _zh, tileSemantics: _tileLabel);

void _ignore(String _) {}

HeatmapPainter _painter(
  List<HeatmapTileLayout> layout, {
  Brightness brightness = Brightness.light,
  HeatmapPaintLabels? labels,
  ValueChanged<String> onTileTap = _ignore,
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) => HeatmapPainter(
  layout: layout,
  brightness: brightness,
  labels: labels ?? _labels,
  onTileTap: onTileTap,
  fontFamily: fontFamily,
  fontFamilyFallback: fontFamilyFallback,
);

/// 單一格子的佈局（直接指定格子大小，畫布呼叫只來自這一格）
List<HeatmapTileLayout> _oneTile(HeatmapTile tile, Rect r) {
  final box = (left: r.left, top: r.top, width: r.width, height: r.height);
  return [
    HeatmapTileLayout(tile: tile, bounds: box, paint: box, interactive: true),
  ];
}

void Function(Canvas) _paintFn(List<HeatmapTileLayout> layout) =>
    (canvas) => _painter(layout).paint(canvas, const Size(400, 300));

List<String> _semanticLabels(HeatmapPainter p) => [
  for (final node in p.semanticsBuilder(const Size(400, 300)))
    node.properties.label!,
];

/// 畫出來的每段文字的寬度與位置，照畫的順序
List<({double width, Offset at})> _paragraphs(List<HeatmapTileLayout> layout) {
  final canvas = _ParagraphCanvas();
  _painter(layout).paint(canvas, const Size(400, 300));
  return canvas.drawn;
}

List<double> _paragraphWidths(List<HeatmapTileLayout> layout) => [
  for (final p in _paragraphs(layout)) p.width,
];

void main() {
  final layout = layoutHeatmapTiles(_tiles, width: 400, height: 300);

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

    test('佈局換成另一個物件要重畫', () {
      final other = layoutHeatmapTiles(_tiles, width: 400, height: 300);
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

    test('只換描述函式不要求重畫（圖上的字不來自它）', () {
      String otherLabel(HeatmapTileLayout t) => 'x';
      expect(
        _painter(
          layout,
          labels: HeatmapPaintLabels(locale: _zh, tileSemantics: otherLabel),
        ).shouldRepaint(_painter(layout)),
        isFalse,
      );
    });
  });

  group('shouldRebuildSemantics', () {
    void other(String _) {}

    test('同樣的佈局與回呼不重建', () {
      expect(
        _painter(layout).shouldRebuildSemantics(_painter(layout)),
        isFalse,
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

    test('🚨 描述函式換了要重建', () {
      String otherLabel(HeatmapTileLayout t) => 'x';
      expect(
        _painter(
          layout,
          labels: HeatmapPaintLabels(locale: _zh, tileSemantics: otherLabel),
        ).shouldRebuildSemantics(_painter(layout)),
        isTrue,
      );
    });

    test('🚨 語系換了要重建（同一個描述函式）；不要求重畫', () {
      const english = HeatmapPaintLabels(
        locale: Locale('en', 'US'),
        tileSemantics: _tileLabel,
      );
      final next = _painter(layout, labels: english);
      expect(next.shouldRebuildSemantics(_painter(layout)), isTrue);
      expect(next.shouldRepaint(_painter(layout)), isFalse);
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

  test('🚨 每個可互動的格子一個無障礙節點，標成按鈕，點了帶代號', () {
    String? tapped;
    final p = _painter(layout, onTileTap: (s) => tapped = s);
    expect(_semanticLabels(p), ['tile:9901', 'tile:9902', 'tile:9911']);
    final nodes = p.semanticsBuilder(const Size(400, 300));
    expect(nodes.every((n) => n.properties.button ?? false), isTrue);
    nodes[1].properties.onTap!();
    expect(tapped, '9902');
  });

  test('🚨 不互動的格子沒有無障礙節點', () {
    final tiny = layoutHeatmapTiles(
      [
        _tile('9901', 1000, const TileChangeValue(1)),
        _tile('9902', 0.000001, const TileChangeValue(1)),
      ],
      width: 400,
      height: 300,
    );
    expect([for (final l in tiny) l.interactive], [true, false], reason: '前提');
    expect(_semanticLabels(_painter(tiny)), ['tile:9901']);
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

    // 測試字型每個字都是字級見方；小格子字級 11、左右各留 2：「測試9901」
    // 「100.00」「+1.00%」都是 66 寬，最短可接受的名稱「測試…」33 寬
    const value = TileChangeValue(1);
    const hollow = TileChangeHollow(HollowReason.noChangeData);
    for (final (desc, change, name, width, height, count) in [
      ('有漲跌、夠大：股名＋價格＋漲跌幅', value, null, 100.0, 60.0, 3),
      ('有漲跌、只放得下兩行：少一行', value, null, 100.0, 30.0, 2),
      ('有漲跌、只放得下一行：只寫股名', value, null, 100.0, 20.0, 1),
      ('有漲跌、價格與漲跌幅都寫不下：只寫股名（縮短）', value, null, 50.0, 60.0, 1),
      ('有漲跌、連兩個字＋…都放不下：不寫', value, null, 30.0, 60.0, 0),
      ('有漲跌、一行都放不下：不寫', value, null, 100.0, 10.0, 0),
      ('兩個字的名稱不必縮：照寫', value, '測試', 30.0, 60.0, 1),
      ('左右留白要扣：寬 35（可用 31）放不下「測試…」33', value, null, 35.0, 60.0, 0),
      ('空心、夠大：只寫股名', hollow, null, 100.0, 60.0, 1),
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

    group('畫的是哪幾行（股名 2 字、價格 7 字、漲跌幅 6 字，字數不同才分得出來）', () {
      HeatmapTile tile({TileChange change = value, double close = 3955}) =>
          _tile('9901', 100, change, name: '測試', close: close);

      test('🚨 三行由上到下是股名、價格、漲跌幅，各自水平置中、整塊垂直置中', () {
        // 100×60：字級 12、行高 12；三行共 36，從 y = 12 開始
        final drawn = _paragraphs(
          _oneTile(tile(), const Rect.fromLTWH(0, 0, 100, 60)),
        );
        expect([for (final p in drawn) p.width], [24.0, 84.0, 72.0]);
        for (final (i, p) in drawn.indexed) {
          expect(p.at.dx, closeTo((100 - p.width) / 2, 1e-6), reason: '第 $i 行');
          expect(p.at.dy, closeTo(12.0 + 12 * i, 1e-6), reason: '第 $i 行');
        }
      });

      test('🚨 只放得下兩行：股名與漲跌幅，不是股名與價格', () {
        // 100×30：字級 11，三行要 33
        expect(
          _paragraphWidths(
            _oneTile(tile(), const Rect.fromLTWH(0, 0, 100, 30)),
          ),
          [22.0, 66.0],
        );
      });

      test('🚨 價格比格子寬：只寫股名與漲跌幅', () {
        // 80×60：字級 11、可用寬 76，價格 77 寫不下、漲跌幅 66 寫得下
        expect(
          _paragraphWidths(_oneTile(tile(), const Rect.fromLTWH(0, 0, 80, 60))),
          [22.0, 66.0],
        );
      });

      test('🚨 空心格子只寫股名，不寫價格', () {
        expect(
          _paragraphWidths(
            _oneTile(tile(change: hollow), const Rect.fromLTWH(0, 0, 100, 60)),
          ),
          [24.0],
        );
      });

      test('價格是這一格的顯示價，小數 2 位', () {
        // 53.4 → 「53.40」5 字
        expect(
          _paragraphWidths(
            _oneTile(tile(close: 53.4), const Rect.fromLTWH(0, 0, 100, 60)),
          ),
          [24.0, 60.0, 72.0],
        );
      });
    });

    test('大格子的字放大（置中位置照放大後的字寬算）', () {
      // 400×300：字級 22，「測試9901」「100.00」「+1.00%」都是 6 字 × 22 = 132 寬，
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

  group('heatmapTileLines', () {
    for (final (desc, nameFits, percent, width, height, expected) in [
      (
        '兩行放得下',
        true,
        66.0,
        96.0,
        22.0,
        (name: true, price: false, percent: true),
      ),
      (
        '高度只放得下一行：只寫名稱',
        true,
        66.0,
        96.0,
        21.0,
        (name: true, price: false, percent: false),
      ),
      (
        '漲跌幅寫不下：只寫名稱',
        true,
        66.0,
        65.0,
        60.0,
        (name: true, price: false, percent: false),
      ),
      (
        '名稱放不下：不寫',
        false,
        20.0,
        96.0,
        60.0,
        (name: false, price: false, percent: false),
      ),
      (
        '一行都放不下：不寫',
        true,
        66.0,
        96.0,
        10.0,
        (name: false, price: false, percent: false),
      ),
      (
        '空心：只寫名稱',
        true,
        null,
        96.0,
        60.0,
        (name: true, price: false, percent: false),
      ),
    ]) {
      test(desc, () {
        expect(
          heatmapTileLines(
            nameFits: nameFits,
            priceWidth: null,
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

  group('heatmapTileLines：價格那一行', () {
    for (final (desc, height, priceWidth, percentWidth, expected) in [
      ('三行放得下', 30.0, 40.0, 50.0, (name: true, price: true, percent: true)),
      (
        '🚨 高度只夠兩行：先省價格',
        29.0,
        40.0,
        50.0,
        (name: true, price: false, percent: true),
      ),
      (
        '價格太寬：不寫價格',
        30.0,
        120.0,
        50.0,
        (name: true, price: false, percent: true),
      ),
      (
        '🚨 沒有要寫價格（priceWidth 是 null）：三行放得下也只寫兩行',
        30.0,
        null,
        50.0,
        (name: true, price: false, percent: true),
      ),
      (
        '🚨 空心（沒有漲跌幅）：不寫價格',
        30.0,
        40.0,
        null,
        (name: true, price: false, percent: false),
      ),
    ]) {
      test(desc, () {
        expect(
          heatmapTileLines(
            nameFits: true,
            priceWidth: priceWidth,
            percentWidth: percentWidth,
            lineHeight: 10,
            width: 100,
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

  test('畫完後建立的 TextPainter 全部 dispose（含寫不下、縮短的名稱）', () {
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
    final recorder = ui.PictureRecorder();
    _painter(withNarrowName).paint(Canvas(recorder), const Size(400, 300));
    recorder.endRecording().dispose();
    expect(created, greaterThan(0));
    expect(disposed, created);
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

  test('formatHeatmapPrice：小數 2 位', () {
    expect(formatHeatmapPrice(3955), '3955.00');
    expect(formatHeatmapPrice(53.4), '53.40');
  });
}

/// 畫的當下記下每段文字的寬度與位置（畫完 TextPainter 就 dispose，事後讀不到）
class _ParagraphCanvas extends TestRecordingCanvas {
  final drawn = <({double width, Offset at})>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      drawn.add((width: paragraph.longestLine, at: offset));
}

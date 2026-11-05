import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:intl/intl.dart' show NumberFormat;

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';

/// 一格的顏色：空心時 [fill] 為 null、只畫 [border]
typedef HeatmapTileStyle = ({Color? fill, Color? border, Color text});

/// 格子的填色、空心邊框與文字色（自選框另取 [HeatmapColors.mineOuter]／
/// [HeatmapColors.mineInner]）
HeatmapTileStyle heatmapTileStyle(TileChange change, Brightness brightness) {
  switch (change) {
    case TileChangeHollow():
      return (
        fill: null,
        border: HeatmapColors.hollowBorder(brightness),
        text: HeatmapColors.hollowText(brightness),
      );
    case TileChangeValue(:final percent):
      final step = HeatmapParams.stepOf(percent);
      final fill = step == 0
          ? HeatmapColors.flat(brightness)
          : HeatmapColors.fill(
              step: step,
              up: percent > 0,
              brightness: brightness,
            );
      return (fill: fill, border: null, text: HeatmapColors.textOn(fill));
  }
}

/// 漲跌幅文字：小數 2 位、正值加 `+`。數值與正負號都取
/// [HeatmapParams.roundPercent]（分階用的同一個值），看到的數字與顏色才會
/// 同一階。
String formatHeatmapPercent(double percent) {
  final rounded = HeatmapParams.roundPercent(percent);
  if (rounded == 0) return '0.00%';
  final digits = rounded.abs().toStringAsFixed(2);
  return rounded > 0 ? '+$digits%' : '-$digits%';
}

/// 名稱在 [maxWidth] 內最多寫成什麼：放得下就寫全名；放不下就取最長的
/// 「前 N 個字＋…」（N ≥ 2，再少就認不出是哪一檔或哪個產業；「…」前不留
/// 連字號與空白，例如「XX-KY」縮成「XX…」）；都放不下回 null。
///
/// 自己截、畫量過的字串，不交給文字引擎的 ellipsis：引擎截斷時需要的寬度和
/// 單獨量出來的不同，實機會多砍一個字。
final _trailingJoiner = RegExp(r'[-\s]+$');

@visibleForTesting
String? heatmapFitName(
  String name,
  double maxWidth,
  double Function(String text) measure,
) {
  if (measure(name) <= maxWidth) return name;
  final chars = name.characters.toList();
  for (var n = chars.length - 1; n >= 2; n--) {
    final prefix = chars.take(n).join().replaceFirst(_trailingJoiner, '');
    if (prefix.characters.length < 2) continue;
    final candidate = '$prefix…';
    if (measure(candidate) <= maxWidth) return candidate;
  }
  return null;
}

/// 產業標題怎麼寫（[measure] 量文字寬度）：放得下就寫「名稱 漲跌幅」；放不下
/// 先縮名稱（見 [heatmapFitName]），漲跌幅保持完整；名稱縮到兩個字＋…還放不下
/// 就只寫名稱。被截斷的數字比不寫更糟（「-0.…」可能被讀成任何值）。
/// [name] 為 null 表示什麼都放不下。
@visibleForTesting
({String? name, bool showPercent}) heatmapHeaderLayout({
  required String name,
  required String? percent,
  required double maxWidth,
  required double Function(String text) measure,
}) {
  if (percent != null) {
    final room = maxWidth - measure(' $percent');
    final fitted = heatmapFitName(name, room, measure);
    if (fitted != null) return (name: fitted, showPercent: true);
  }
  return (name: heatmapFitName(name, maxWidth, measure), showPercent: false);
}

/// 格子寫哪幾行：名稱優先（顏色已經表示漲跌大小，名稱是顏色給不了的資訊），
/// 名稱放不下（見 [heatmapFitName]）就不寫；第二行放得下、漲跌幅也完整放得下，
/// 才加漲跌幅。空心格子傳 [percentWidth] null，只寫名稱。
@visibleForTesting
({bool name, bool percent}) heatmapTileLines({
  required bool nameFits,
  required double? percentWidth,
  required double lineHeight,
  required double width,
  required double height,
}) {
  if (!nameFits || lineHeight > height) return (name: false, percent: false);
  final percentFits =
      percentWidth != null && percentWidth <= width && 2 * lineHeight <= height;
  return (name: true, percent: percentFits);
}

/// 格子的字級：格子越大字越大（大格子是市值最大、最多人看的股票）
@visibleForTesting
double heatmapTileFontSize(double width, double height) => math
    .min(
      width / HeatmapParams.tileFontWidthRatio,
      height / HeatmapParams.tileFontHeightRatio,
    )
    .clamp(HeatmapParams.labelFontSize, HeatmapParams.tileFontSizeMax);

/// 市值數字：`zh` 開頭的語系以億、其他語系以十億為單位，小數 1 位、千分位
String formatHeatmapCap(double marketCap, Locale locale) {
  final unit = locale.languageCode == 'zh' ? 1e8 : 1e9;
  return NumberFormat('#,##0.0', 'en_US').format(marketCap / unit);
}

/// 畫在圖上與無障礙描述用的文字（由頁面依語系組好傳入；兩個函式以
/// identity 比較，頁面要保存同一個實例，painter 才不會一直重畫）
@immutable
class HeatmapPaintLabels {
  const HeatmapPaintLabels({
    required this.uncategorized,
    required this.industrySemantics,
    required this.tileSemantics,
  });

  /// 產業別為空時的產業名稱
  final String uncategorized;
  final String Function(HeatmapIndustryLayout industry) industrySemantics;
  final String Function(HeatmapTileLayout tile) tileSemantics;

  @override
  bool operator ==(Object other) =>
      other is HeatmapPaintLabels &&
      other.uncategorized == uncategorized &&
      identical(other.industrySemantics, industrySemantics) &&
      identical(other.tileSemantics, tileSemantics);

  @override
  int get hashCode => Object.hash(
    uncategorized,
    identityHashCode(industrySemantics),
    identityHashCode(tileSemantics),
  );
}

/// 一次畫完全部格子（上千個 widget 太重）。
///
/// 無障礙分層：全市場只描述產業；放大到單一產業時才描述每個可互動格子
/// （上千段描述讓螢幕閱讀器無法使用）。
class HeatmapPainter extends CustomPainter {
  HeatmapPainter({
    required this.layout,
    required this.brightness,
    required this.zoomed,
    required this.labels,
    required this.onIndustryTap,
    required this.onTileTap,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final List<HeatmapIndustryLayout> layout;
  final Brightness brightness;
  final bool zoomed;
  final HeatmapPaintLabels labels;

  /// 無障礙節點的點擊動作（螢幕閱讀器啟用產業節點放大、啟用格子進個股頁）。
  /// 傳穩定的實例（例如 State 的方法），語意才不會每次都重建。
  final ValueChanged<String> onIndustryTap;
  final ValueChanged<String> onTileTap;

  /// 圖上文字的字族，由畫面依 App 主題傳入（只取字族，字級與顏色由 painter
  /// 決定）；null 用引擎預設字型
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    for (final industry in layout) {
      final header = industry.header;
      if (header != null) _paintHeader(canvas, industry, header);
      for (final tile in industry.tiles) {
        _paintTile(canvas, tile);
      }
    }
  }

  void _paintHeader(
    Canvas canvas,
    HeatmapIndustryLayout industry,
    HeatmapBox header,
  ) {
    final rect = _rect(header);
    canvas.drawRect(
      rect,
      Paint()..color = HeatmapColors.pageBackground(brightness),
    );
    final name = industry.industry.name ?? labels.uncategorized;
    final change = industry.industry.weightedChangePercent;
    final percent = change == null ? null : formatHeatmapPercent(change);
    final color = HeatmapColors.headerText(brightness);
    // 同一次繪製裡同一個字串只排版一次：量過的直接拿來畫
    final painters = <String, TextPainter>{};
    TextPainter make(String text) => painters[text] ??= _text(text, color);

    try {
      final layout = heatmapHeaderLayout(
        name: name,
        percent: percent,
        maxWidth: rect.width - 2 * HeatmapParams.textPadding,
        measure: (text) => make(text).width,
      );
      final shown = layout.name;
      if (shown == null) return;
      final namePainter = make(shown);
      final x = rect.left + HeatmapParams.textPadding;
      namePainter.paint(
        canvas,
        Offset(x, rect.top + (rect.height - namePainter.height) / 2),
      );
      if (layout.showPercent) {
        final percentPainter = make(' $percent');
        percentPainter.paint(
          canvas,
          Offset(
            x + namePainter.width,
            rect.top + (rect.height - percentPainter.height) / 2,
          ),
        );
      }
    } finally {
      for (final p in painters.values) {
        p.dispose();
      }
    }
  }

  void _paintTile(Canvas canvas, HeatmapTileLayout tile) {
    final rect = _rect(tile.paint);
    if (rect.width <= 0 || rect.height <= 0) return;
    final style = heatmapTileStyle(tile.tile.change, brightness);
    final fill = style.fill;
    if (fill != null) {
      canvas.drawRect(rect, Paint()..color = fill);
    } else {
      _stroke(canvas, rect, style.border!);
    }
    if (tile.tile.isMine) {
      _stroke(canvas, rect, HeatmapColors.mineOuter);
      _stroke(canvas, rect.deflate(1), HeatmapColors.mineInner);
    }
    _paintTileText(canvas, tile, rect, style.text);
  }

  /// 格子文字：名稱優先，第二行放得下才加漲跌幅（見 [heatmapTileLines]）；
  /// 字級隨格子大小（見 [heatmapTileFontSize]）。
  void _paintTileText(
    Canvas canvas,
    HeatmapTileLayout tile,
    Rect rect,
    Color color,
  ) {
    if (rect.width < HeatmapParams.tileTextMinWidth ||
        rect.height < HeatmapParams.tileTextMinHeight) {
      return;
    }
    final fontSize = heatmapTileFontSize(rect.width, rect.height);
    final maxWidth = rect.width - 2 * HeatmapParams.textPadding;
    final change = tile.tile.change;
    final painters = <String, TextPainter>{};
    TextPainter make(String text) =>
        painters[text] ??= _text(text, color, fontSize: fontSize);

    try {
      final name = heatmapFitName(
        tile.tile.name,
        maxWidth,
        (text) => make(text).width,
      );
      final namePainter = name == null ? null : make(name);
      final percent = change is TileChangeValue
          ? make(formatHeatmapPercent(change.percent))
          : null;
      final pick = heatmapTileLines(
        nameFits: namePainter != null,
        percentWidth: percent?.width,
        lineHeight: namePainter?.height ?? double.infinity,
        width: maxWidth,
        height: rect.height,
      );
      if (!pick.name) return;
      final lines = [namePainter!, if (pick.percent) percent!];
      final total = lines.fold(0.0, (h, p) => h + p.height);
      var y = rect.top + (rect.height - total) / 2;
      for (final line in lines) {
        line.paint(
          canvas,
          Offset(rect.left + (rect.width - line.width) / 2, y),
        );
        y += line.height;
      }
    } finally {
      for (final p in painters.values) {
        p.dispose();
      }
    }
  }

  void _stroke(Canvas canvas, Rect rect, Color color) {
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  /// 單行文字（寬度＝實際字寬；要縮短的字串由呼叫端先決定好）
  TextPainter _text(
    String text,
    Color color, {
    double fontSize = HeatmapParams.labelFontSize,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  static Rect _rect(HeatmapBox b) =>
      Rect.fromLTWH(b.left, b.top, b.width, b.height);

  @override
  bool shouldRepaint(HeatmapPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.brightness != brightness ||
      oldDelegate.zoomed != zoomed ||
      oldDelegate.labels != labels ||
      oldDelegate.fontFamily != fontFamily ||
      !listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback);

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    if (!zoomed) {
      return [
        for (final industry in layout)
          CustomPainterSemantics(
            rect: _rect(industry.bounds),
            properties: SemanticsProperties(
              label: labels.industrySemantics(industry),
              textDirection: TextDirection.ltr,
              button: true,
              onTap: () => onIndustryTap(industry.industry.key),
            ),
          ),
      ];
    }
    return [
      for (final industry in layout)
        for (final tile in industry.tiles)
          if (tile.interactive)
            CustomPainterSemantics(
              rect: _rect(tile.paint),
              properties: SemanticsProperties(
                label: labels.tileSemantics(tile),
                textDirection: TextDirection.ltr,
                button: true,
                onTap: () => onTileTap(tile.tile.symbol),
              ),
            ),
    ];
  };

  @override
  bool shouldRebuildSemantics(HeatmapPainter oldDelegate) =>
      shouldRepaint(oldDelegate) ||
      oldDelegate.onIndustryTap != onIndustryTap ||
      oldDelegate.onTileTap != onTileTap;
}

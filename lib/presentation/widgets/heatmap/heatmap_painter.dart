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
/// 「前 N 個字＋…」（N ≥ 2，再少就認不出是哪一檔；「…」前不留
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

/// 格子寫哪幾行：名稱優先（顏色已經表示漲跌大小，名稱是顏色給不了的資訊），
/// 名稱放不下（見 [heatmapFitName]）就不寫；第二行放得下、漲跌幅也完整放得下，
/// 才加漲跌幅。空心格子傳 [percentWidth] null，只寫名稱。
///
/// 價格（[priceWidth]，沒有要寫時傳 null）排在名稱與漲跌幅中間，最先省：
/// 有漲跌幅、三行放得下、價格也完整放得下才寫。
@visibleForTesting
({bool name, bool price, bool percent}) heatmapTileLines({
  required bool nameFits,
  required double? priceWidth,
  required double? percentWidth,
  required double lineHeight,
  required double width,
  required double height,
}) {
  if (!nameFits || lineHeight > height) {
    return (name: false, price: false, percent: false);
  }
  final percentFits =
      percentWidth != null && percentWidth <= width && 2 * lineHeight <= height;
  final priceFits =
      percentFits &&
      priceWidth != null &&
      priceWidth <= width &&
      3 * lineHeight <= height;
  return (name: true, price: priceFits, percent: percentFits);
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

/// 格子上的價格：小數 2 位（與提示相同）
String formatHeatmapPrice(double price) => price.toStringAsFixed(2);

/// 無障礙描述怎麼產生（由頁面傳入）。[locale] 是描述文字的語系：同一個
/// [tileSemantics] 在不同語系產生不同的文字，語系換了語意要重建。函式以
/// identity 比較，傳穩定的函式，painter 才不會一直重建語意
@immutable
class HeatmapPaintLabels {
  const HeatmapPaintLabels({required this.locale, required this.tileSemantics});

  final Locale locale;
  final String Function(HeatmapTileLayout tile) tileSemantics;

  @override
  bool operator ==(Object other) =>
      other is HeatmapPaintLabels &&
      other.locale == locale &&
      identical(other.tileSemantics, tileSemantics);

  @override
  int get hashCode => Object.hash(locale, identityHashCode(tileSemantics));
}

/// 一次畫完全部格子；每個可互動的格子一個無障礙節點。
class HeatmapPainter extends CustomPainter {
  HeatmapPainter({
    required this.layout,
    required this.brightness,
    required this.labels,
    required this.onTileTap,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final List<HeatmapTileLayout> layout;
  final Brightness brightness;
  final HeatmapPaintLabels labels;

  /// 無障礙節點的點擊動作（螢幕閱讀器啟用格子進個股頁）。傳穩定的實例
  /// （例如 State 的方法），語意才不會每次都重建。
  final ValueChanged<String> onTileTap;

  /// 圖上文字的字族，由畫面依 App 主題傳入（只取字族，字級與顏色由 painter
  /// 決定）；null 用引擎預設字型
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    for (final tile in layout) {
      _paintTile(canvas, tile);
    }
  }

  void _paintTile(Canvas canvas, HeatmapTileLayout tile) {
    final rect = _rect(tile.paint);
    if (rect.width <= 0 || rect.height <= 0) return;
    final change = tile.tile.change;
    final style = heatmapTileStyle(change, brightness);
    final fill = style.fill;
    if (fill != null) {
      canvas.drawRect(rect, Paint()..color = fill);
    } else {
      _stroke(canvas, rect, style.border!);
    }
    if (tile.tile.isMine) _paintMineFrame(canvas, rect);
    _paintLabel(
      canvas,
      rect,
      style.text,
      name: tile.tile.name,
      // 空心格子沒有今天的漲跌，價格也不是今天的：只寫股名
      price: change is TileChangeValue
          ? formatHeatmapPrice(tile.tile.close)
          : null,
      percent: change is TileChangeValue
          ? formatHeatmapPercent(change.percent)
          : null,
    );
  }

  /// 格子文字：股名、價格、漲跌幅各一行，置中；放不下時先省價格、再省漲跌幅
  /// （見 [heatmapTileLines]），股名放不下時縮短（見 [heatmapFitName]），再
  /// 放不下就整格不寫。字級隨格子大小（見 [heatmapTileFontSize]）。
  void _paintLabel(
    Canvas canvas,
    Rect rect,
    Color color, {
    required String name,
    required String? price,
    required String? percent,
  }) {
    if (rect.width < HeatmapParams.tileTextMinWidth ||
        rect.height < HeatmapParams.tileTextMinHeight) {
      return;
    }
    final fontSize = heatmapTileFontSize(rect.width, rect.height);
    final maxWidth = rect.width - 2 * HeatmapParams.textPadding;
    // 同一次繪製裡同一個字串只排版一次：量過的直接拿來畫
    final painters = <String, TextPainter>{};
    TextPainter make(String text) =>
        painters[text] ??= _text(text, color, fontSize: fontSize);

    try {
      final fitted = heatmapFitName(name, maxWidth, (text) => make(text).width);
      if (fitted == null) return;
      final namePainter = make(fitted);
      final pricePainter = price == null ? null : make(price);
      final percentPainter = percent == null ? null : make(percent);
      final pick = heatmapTileLines(
        nameFits: true,
        priceWidth: pricePainter?.width,
        percentWidth: percentPainter?.width,
        lineHeight: namePainter.height,
        width: maxWidth,
        height: rect.height,
      );
      if (!pick.name) return;
      final lines = [
        namePainter,
        if (pick.price) pricePainter!,
        if (pick.percent) percentPainter!,
      ];
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

  /// 自選或持股的雙線框（外深內淺各 1px）
  void _paintMineFrame(Canvas canvas, Rect rect) {
    _stroke(canvas, rect, HeatmapColors.mineOuter);
    _stroke(canvas, rect.deflate(1), HeatmapColors.mineInner);
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
  TextPainter _text(String text, Color color, {required double fontSize}) =>
      TextPainter(
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
      oldDelegate.fontFamily != fontFamily ||
      !listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback);

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final tile in layout)
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

  @override
  bool shouldRebuildSemantics(HeatmapPainter oldDelegate) =>
      shouldRepaint(oldDelegate) ||
      oldDelegate.labels != labels ||
      oldDelegate.onTileTap != onTileTap;
}

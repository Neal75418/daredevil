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
///
/// 即時比例（[suffix]，接在漲跌幅後面）最先捨：完整名稱、漲跌幅與比例都放得下
/// 才寫，不為了留比例去縮名稱。
@visibleForTesting
({String? name, bool showPercent, bool showSuffix}) heatmapHeaderLayout({
  required String name,
  required String? percent,
  String? suffix,
  required double maxWidth,
  required double Function(String text) measure,
}) {
  if (percent != null) {
    if (suffix != null &&
        measure(name) + measure(' $percent$suffix') <= maxWidth) {
      return (name: name, showPercent: true, showSuffix: true);
    }
    final room = maxWidth - measure(' $percent');
    final fitted = heatmapFitName(name, room, measure);
    if (fitted != null) {
      return (name: fitted, showPercent: true, showSuffix: false);
    }
  }
  return (
    name: heatmapFitName(name, maxWidth, measure),
    showPercent: false,
    showSuffix: false,
  );
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

/// 點了合併塊（[HeatmapOtherLayout]）
typedef HeatmapOtherTap =
    void Function(HeatmapIndustryLayout industry, HeatmapOtherLayout other);

/// 畫在圖上與無障礙描述用的文字（由頁面依語系組好傳入；函式以 identity
/// 比較，頁面要保存同一個實例，painter 才不會一直重畫）。依即時模式變化的
/// 文字收模式參數，由 painter 依自己的 [HeatmapPainter.liveMode] 呼叫。
@immutable
class HeatmapPaintLabels {
  const HeatmapPaintLabels({
    required this.uncategorized,
    required this.industrySemantics,
    required this.tileSemantics,
    required this.otherLabel,
    required this.otherShortLabel,
    required this.wholeLabel,
    required this.otherSemantics,
    required this.groupLabel,
    required this.groupShortLabel,
    required this.groupSemantics,
    required this.coverageSuffix,
    required this.noChangeLabel,
  });

  /// 產業別為空時的產業名稱
  final String uncategorized;

  /// 產業的描述；[mode] 是 painter 的 [HeatmapPainter.liveMode]
  final String Function(HeatmapIndustryLayout industry, HeatmapLiveMode? mode)
  industrySemantics;
  final String Function(HeatmapTileLayout tile) tileSemantics;

  /// 合併塊的標籤（「其他 N 檔」）
  final String Function(int count) otherLabel;

  /// 「其他 N 檔」寫不下時退用的短標籤（「其他」）
  final String otherShortLabel;

  /// 整個產業都合併、產業又有標題列時的標籤（「共 N 檔」，不重複產業名稱）
  final String Function(int count) wholeLabel;
  final String Function(
    HeatmapIndustryLayout industry,
    HeatmapOtherLayout other,
    HeatmapLiveMode? mode,
  )
  otherSemantics;

  /// 小產業合併塊的標籤（「其他 N 個產業」）
  final String Function(int count) groupLabel;

  /// 「其他 N 個產業」寫不下時退用的短標籤（「其他產業」）
  final String groupShortLabel;
  final String Function(HeatmapIndustryGroupLayout group, HeatmapLiveMode? mode)
  groupSemantics;

  /// 即時套色時接在產業與合併塊漲跌幅後面的比例（「・即時 96%」）
  final String Function(double coverage, HeatmapLiveMode mode) coverageSuffix;

  /// 即時套色時產業與合併塊沒有漲跌的文字（「未即時」）
  final String Function(HeatmapLiveMode mode) noChangeLabel;

  @override
  bool operator ==(Object other) =>
      other is HeatmapPaintLabels &&
      other.uncategorized == uncategorized &&
      other.otherShortLabel == otherShortLabel &&
      other.groupShortLabel == groupShortLabel &&
      identical(other.industrySemantics, industrySemantics) &&
      identical(other.tileSemantics, tileSemantics) &&
      identical(other.otherLabel, otherLabel) &&
      identical(other.wholeLabel, wholeLabel) &&
      identical(other.otherSemantics, otherSemantics) &&
      identical(other.groupLabel, groupLabel) &&
      identical(other.groupSemantics, groupSemantics) &&
      identical(other.coverageSuffix, coverageSuffix) &&
      identical(other.noChangeLabel, noChangeLabel);

  @override
  int get hashCode => Object.hash(
    uncategorized,
    otherShortLabel,
    groupShortLabel,
    identityHashCode(industrySemantics),
    identityHashCode(tileSemantics),
    identityHashCode(otherLabel),
    identityHashCode(wholeLabel),
    identityHashCode(otherSemantics),
    identityHashCode(groupLabel),
    identityHashCode(groupSemantics),
    identityHashCode(coverageSuffix),
    identityHashCode(noChangeLabel),
  );
}

/// 一次畫完全部格子（上千個 widget 太重）。
///
/// 無障礙分層：全市場只描述產業（與小產業合併塊）；放大到單一產業時才描述
/// 每個可互動格子（上千段描述讓螢幕閱讀器無法使用）。
class HeatmapPainter extends CustomPainter {
  HeatmapPainter({
    required this.layout,
    required this.smallIndustries,
    required this.brightness,
    required this.zoomed,
    required this.labels,
    required this.onIndustryTap,
    required this.onTileTap,
    required this.onOtherTap,
    required this.onSmallIndustriesTap,
    this.fontFamily,
    this.fontFamilyFallback,
    this.liveMode,
  });

  final List<HeatmapIndustryLayout> layout;

  /// 全市場圖上合併的小產業（見 [layoutHeatmapMarket]）；沒有時為 null
  final HeatmapIndustryGroupLayout? smallIndustries;
  final Brightness brightness;
  final bool zoomed;
  final HeatmapPaintLabels labels;

  /// 無障礙節點的點擊動作（螢幕閱讀器啟用產業節點放大、啟用格子進個股頁）。
  /// 傳穩定的實例（例如 State 的方法），語意才不會每次都重建。
  final ValueChanged<String> onIndustryTap;
  final ValueChanged<String> onTileTap;
  final HeatmapOtherTap onOtherTap;
  final ValueChanged<HeatmapIndustryGroupLayout> onSmallIndustriesTap;

  /// 圖上文字的字族，由畫面依 App 主題傳入（只取字族，字級與顏色由 painter
  /// 決定）；null 用引擎預設字型
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  /// 資料的即時套色時段（[HeatmapMarketData.liveMode]）；null 是正式資料，
  /// 產業標題與合併塊不寫即時比例與「未即時」
  final HeatmapLiveMode? liveMode;

  @override
  void paint(Canvas canvas, Size size) {
    for (final industry in layout) {
      final header = industry.header;
      if (header != null) _paintHeader(canvas, industry, header);
      for (final tile in industry.tiles) {
        _paintTile(canvas, tile);
      }
      final other = industry.other;
      if (other != null) _paintOther(canvas, industry, other);
    }
    final group = smallIndustries;
    if (group != null) _paintGroup(canvas, group);
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
    final (:percent, :suffix) = _weightedTexts(
      industry.industry.weightedChangePercent,
      industry.industry.liveCoverage,
    );
    final color = HeatmapColors.headerText(brightness);
    // 同一次繪製裡同一個字串只排版一次：量過的直接拿來畫
    final painters = <String, TextPainter>{};
    TextPainter make(String text) => painters[text] ??= _text(text, color);

    try {
      final layout = heatmapHeaderLayout(
        name: name,
        percent: percent,
        suffix: suffix,
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
        final percentPainter = make(
          layout.showSuffix ? ' $percent$suffix' : ' $percent',
        );
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
    if (tile.tile.isMine) _paintMineFrame(canvas, rect);
    final change = tile.tile.change;
    _paintLabel(
      canvas,
      rect,
      style.text,
      name: tile.tile.name,
      value: change is TileChangeValue
          ? formatHeatmapPercent(change.percent)
          : null,
      shortenName: true,
    );
  }

  /// 合併塊：照成員的加權漲跌上色（全是空心時畫空心），寫「其他 N 檔」；
  /// 整個產業都合併時，有標題列寫「共 N 檔」（名稱已在標題列），沒有才寫
  /// 產業名稱。成員有自選或持股時整塊加自選框。
  void _paintOther(
    Canvas canvas,
    HeatmapIndustryLayout industry,
    HeatmapOtherLayout other,
  ) {
    final rect = _rect(other.paint);
    if (rect.width <= 0 || rect.height <= 0) return;
    final percent = other.weightedChangePercent;
    final textColor = _paintFoldBlock(canvas, rect, percent, other.mineCount);
    final (percent: value, :suffix) = _weightedTexts(percent, other.coverage);
    final count = other.members.length;
    if (!other.wholeIndustry) {
      // 「其他 N 檔」縮短後看不懂：寫不下就退成「其他」，再寫不下就不寫
      // （不只寫一個數字，免得被當成一檔股票）
      _paintLabel(
        canvas,
        rect,
        textColor,
        name: labels.otherLabel(count),
        fallbackNames: [labels.otherShortLabel],
        value: value,
        suffix: suffix,
        shortenName: false,
      );
    } else if (industry.header != null) {
      // 產業名稱已在標題列（標題列太窄時常寫不下漲跌幅）：「共 N 檔」寫不下
      // 就只寫漲跌幅
      _paintLabel(
        canvas,
        rect,
        textColor,
        name: labels.wholeLabel(count),
        value: value,
        suffix: suffix,
        shortenName: false,
        percentWithoutName: true,
      );
    } else {
      _paintLabel(
        canvas,
        rect,
        textColor,
        name: industry.industry.name ?? labels.uncategorized,
        value: value,
        suffix: suffix,
        shortenName: true,
      );
    }
  }

  /// 小產業合併塊：照成員的加權漲跌上色，寫「其他 N 個產業」；寫不下退成
  /// 「其他產業」，再寫不下就不寫。成員有自選或持股時整塊加自選框。
  void _paintGroup(Canvas canvas, HeatmapIndustryGroupLayout group) {
    final rect = _rect(group.paint);
    if (rect.width <= 0 || rect.height <= 0) return;
    final percent = group.weightedChangePercent;
    final textColor = _paintFoldBlock(canvas, rect, percent, group.mineCount);
    final (percent: value, :suffix) = _weightedTexts(percent, group.coverage);
    _paintLabel(
      canvas,
      rect,
      textColor,
      name: labels.groupLabel(group.members.length),
      fallbackNames: [labels.groupShortLabel],
      value: value,
      suffix: suffix,
      shortenName: false,
    );
  }

  /// 產業標題與合併塊的漲跌文字：[percent]（漲跌幅；即時套色時沒有值寫
  /// [HeatmapPaintLabels.noChangeLabel]：盤中「未即時」、收盤後「未收盤」）
  /// 與接在後面的即時比例 [suffix]。正式資料（liveMode 為 null）時不寫比例，
  /// 沒有值也不寫。
  ({String? percent, String? suffix}) _weightedTexts(
    double? change,
    double? coverage,
  ) {
    final mode = liveMode;
    if (change == null) {
      return (
        percent: mode == null ? null : labels.noChangeLabel(mode),
        suffix: null,
      );
    }
    return (
      percent: formatHeatmapPercent(change),
      suffix: mode == null || coverage == null
          ? null
          : labels.coverageSuffix(coverage, mode),
    );
  }

  /// 合併塊的底：照加權漲跌上色（null 時畫空心），含自選或持股時加自選框；
  /// 回傳文字色
  Color _paintFoldBlock(
    Canvas canvas,
    Rect rect,
    double? percent,
    int mineCount,
  ) {
    final style = heatmapTileStyle(
      percent == null
          ? const TileChangeHollow(HollowReason.noChangeData)
          : TileChangeValue(percent),
      brightness,
    );
    final fill = style.fill;
    if (fill != null) {
      canvas.drawRect(rect, Paint()..color = fill);
    } else {
      _stroke(canvas, rect, style.border!);
    }
    if (mineCount > 0) _paintMineFrame(canvas, rect);
    return style.text;
  }

  /// 格子文字：名稱優先，第二行（[value]：漲跌幅或「未即時」）放得下才加
  /// （見 [heatmapTileLines]）；即時比例 [suffix] 接在第二行後面，放不下先捨。
  /// 字級隨格子大小（見 [heatmapTileFontSize]）。[shortenName] 為 false 時
  /// 名稱放不下就整格不寫。
  void _paintLabel(
    Canvas canvas,
    Rect rect,
    Color color, {
    required String name,
    required String? value,
    required bool shortenName,
    String? suffix,
    List<String> fallbackNames = const [],
    bool percentWithoutName = false,
  }) {
    if (rect.width < HeatmapParams.tileTextMinWidth ||
        rect.height < HeatmapParams.tileTextMinHeight) {
      return;
    }
    final fontSize = heatmapTileFontSize(rect.width, rect.height);
    final maxWidth = rect.width - 2 * HeatmapParams.textPadding;
    final painters = <String, TextPainter>{};
    TextPainter make(String text) =>
        painters[text] ??= _text(text, color, fontSize: fontSize);

    try {
      final fitted = shortenName
          ? heatmapFitName(name, maxWidth, (text) => make(text).width)
          : [
              name,
              ...fallbackNames,
            ].where((text) => make(text).width <= maxWidth).firstOrNull;
      final namePainter = fitted == null ? null : make(fitted);
      final withSuffix = value == null || suffix == null
          ? null
          : make('$value$suffix');
      final percentPainter = withSuffix != null && withSuffix.width <= maxWidth
          ? withSuffix
          : value == null
          ? null
          : make(value);
      if (namePainter == null) {
        // 名稱由別處標示（例如標題列）時，只寫漲跌幅
        if (percentWithoutName &&
            percentPainter != null &&
            percentPainter.width <= maxWidth &&
            percentPainter.height <= rect.height) {
          percentPainter.paint(
            canvas,
            Offset(
              rect.left + (rect.width - percentPainter.width) / 2,
              rect.top + (rect.height - percentPainter.height) / 2,
            ),
          );
        }
        return;
      }
      final pick = heatmapTileLines(
        nameFits: true,
        percentWidth: percentPainter?.width,
        lineHeight: namePainter.height,
        width: maxWidth,
        height: rect.height,
      );
      if (!pick.name) return;
      final lines = [namePainter, if (pick.percent) percentPainter!];
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
      !identical(oldDelegate.smallIndustries, smallIndustries) ||
      oldDelegate.brightness != brightness ||
      oldDelegate.zoomed != zoomed ||
      oldDelegate.labels != labels ||
      oldDelegate.fontFamily != fontFamily ||
      !listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback) ||
      oldDelegate.liveMode != liveMode;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    if (!zoomed) {
      return [
        for (final industry in layout)
          CustomPainterSemantics(
            rect: _rect(industry.bounds),
            properties: SemanticsProperties(
              label: labels.industrySemantics(industry, liveMode),
              textDirection: TextDirection.ltr,
              button: true,
              onTap: () => onIndustryTap(industry.industry.key),
            ),
          ),
        if (smallIndustries case final group? when group.interactive)
          CustomPainterSemantics(
            rect: _rect(group.paint),
            properties: SemanticsProperties(
              label: labels.groupSemantics(group, liveMode),
              textDirection: TextDirection.ltr,
              button: true,
              onTap: () => onSmallIndustriesTap(group),
            ),
          ),
      ];
    }
    return [
      for (final industry in layout) ...[
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
        if (industry.other case final other? when other.interactive)
          CustomPainterSemantics(
            rect: _rect(other.paint),
            properties: SemanticsProperties(
              label: labels.otherSemantics(industry, other, liveMode),
              textDirection: TextDirection.ltr,
              button: true,
              onTap: () => onOtherTap(industry, other),
            ),
          ),
      ],
    ];
  };

  @override
  bool shouldRebuildSemantics(HeatmapPainter oldDelegate) =>
      shouldRepaint(oldDelegate) ||
      oldDelegate.onIndustryTap != onIndustryTap ||
      oldDelegate.onTileTap != onTileTap ||
      oldDelegate.onOtherTap != onOtherTap ||
      oldDelegate.onSmallIndustriesTap != onSmallIndustriesTap;
}

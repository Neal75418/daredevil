import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_tooltip.dart';

/// 一個市場的熱力圖：佈局、繪製、點擊、滑鼠與長按提示。
///
/// 佈局依（資料、放大的產業、尺寸）快取，三者不變時沿用同一個 list，
/// painter 才不會重畫；提示畫在獨立一層，滑鼠移動只重建提示。即時套色的
/// 時段取資料自己的 [HeatmapMarketData.liveMode]。
class HeatmapView extends StatefulWidget {
  const HeatmapView({
    super.key,
    required this.data,
    required this.zoomIndustryKey,
    required this.onIndustryTap,
    required this.onTileTap,
    required this.onOtherTap,
    required this.onSmallIndustriesTap,
    required this.labels,
  });

  final HeatmapMarketData data;

  /// 放大的產業（[HeatmapIndustry.key]）；null 畫全市場
  final String? zoomIndustryKey;
  final ValueChanged<String> onIndustryTap;
  final ValueChanged<String> onTileTap;

  /// 點「其他 N 檔」（部分合併）：列出成員。整個產業合成的那塊照點產業標題，
  /// 呼叫 [onIndustryTap]
  final HeatmapOtherTap onOtherTap;

  /// 點全市場圖上的小產業合併塊（「其他 N 個產業」）：列出這些產業
  final ValueChanged<HeatmapIndustryGroupLayout> onSmallIndustriesTap;
  final HeatmapPaintLabels labels;

  @override
  State<HeatmapView> createState() => _HeatmapViewState();
}

/// 提示：指著的格子、產業內的合併塊或小產業合併塊（三者擇一）、所屬產業
/// （小產業合併塊沒有）、位置，以及算出它的那份佈局（佈局換了就在新佈局的
/// 同一個位置重查）
typedef _Hover = ({
  HeatmapMarketLayout layout,
  HeatmapIndustryLayout? industry,
  HeatmapTileLayout? tile,
  HeatmapOtherLayout? other,
  HeatmapIndustryGroupLayout? group,
  Offset at,
});

class _HeatmapViewState extends State<HeatmapView> {
  final _hover = ValueNotifier<_Hover?>(null);

  HeatmapMarketData? _cachedData;
  String? _cachedZoom;
  Size? _cachedSize;
  HeatmapMarketLayout _layout = HeatmapMarketLayout.empty;

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  /// 全市場合併放不下標題列的小產業；放大單一產業時不合併
  HeatmapMarketLayout _layoutFor(Size size) {
    if (identical(_cachedData, widget.data) &&
        _cachedZoom == widget.zoomIndustryKey &&
        _cachedSize == size) {
      return _layout;
    }
    final zoom = widget.zoomIndustryKey;
    final watch = Stopwatch()..start();
    _layout = zoom == null
        ? layoutHeatmapMarket(
            widget.data.industries,
            width: size.width,
            height: size.height,
          )
        : HeatmapMarketLayout(
            industries: layoutHeatmap(
              [
                for (final i in widget.data.industries)
                  if (i.key == zoom) i,
              ],
              width: size.width,
              height: size.height,
            ),
          );
    watch.stop();
    AppLogger.debug(
      'MarketHeatmap',
      '${widget.data.market} layout ${watch.elapsedMilliseconds}ms',
    );
    _cachedData = widget.data;
    _cachedZoom = zoom;
    _cachedSize = size;
    return _layout;
  }

  void _showAt(HeatmapMarketLayout layout, Offset at) =>
      _hover.value = _hoverAt(layout, at);

  /// [at] 在 [layout] 上指著的提示對象；都沒有時為 null（純計算）
  static _Hover? _hoverAt(HeatmapMarketLayout layout, Offset at) {
    final industries = layout.industries;
    final tile = tileAt(industries, at.dx, at.dy);
    if (tile != null) {
      final industry = industries.firstWhere(
        (l) => l.tiles.any((t) => identical(t, tile)),
      );
      return (
        layout: layout,
        industry: industry,
        tile: tile,
        other: null,
        group: null,
        at: at,
      );
    }
    final hit = otherAt(industries, at.dx, at.dy);
    if (hit != null) {
      return (
        layout: layout,
        industry: hit.industry,
        tile: null,
        other: hit.other,
        group: null,
        at: at,
      );
    }
    final group = smallIndustriesAt(layout, at.dx, at.dy);
    return group == null
        ? null
        : (
            layout: layout,
            industry: null,
            tile: null,
            other: null,
            group: group,
            at: at,
          );
  }

  /// 佈局換了（新一輪即時資料、放大、尺寸）而提示還開著：同一個位置在新佈局
  /// 重查並在這一幀畫出（盤中每輪換資料時提示不空白一幀）；查不到就收起。
  /// 結果在這一幀結束後才寫回 [_hover]：build 期間不改 notifier；這段時間
  /// 指標已經移動（[_hover] 換了）就不蓋掉。
  _Hover? _followLayout(_Hover hover, HeatmapMarketLayout layout) {
    final next = _hoverAt(layout, hover.at);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_hover.value, hover)) _hover.value = next;
    });
    return next;
  }

  // 無障礙節點的點擊：穩定的方法 tear-off，painter 比較時才相等
  void _semanticIndustryTap(String key) => widget.onIndustryTap(key);
  void _semanticTileTap(String symbol) => widget.onTileTap(symbol);
  void _semanticGroupTap(HeatmapIndustryGroupLayout group) =>
      widget.onSmallIndustriesTap(group);

  /// 合併塊的點擊（手勢與無障礙共用）：全市場圖上整個產業合成的那塊放大
  /// 該產業；其餘（包括已放大後仍整個合成一塊的）列出成員
  void _otherTap(HeatmapIndustryLayout industry, HeatmapOtherLayout other) {
    if (other.wholeIndustry && widget.zoomIndustryKey == null) {
      widget.onIndustryTap(industry.industry.key);
    } else {
      widget.onOtherTap(industry, other);
    }
  }

  void _tap(HeatmapMarketLayout layout, Offset at) {
    final industries = layout.industries;
    final header = industryHeaderAt(industries, at.dx, at.dy);
    if (header != null) {
      widget.onIndustryTap(header.industry.key);
      return;
    }
    final tile = tileAt(industries, at.dx, at.dy);
    if (tile != null) {
      widget.onTileTap(tile.tile.symbol);
      return;
    }
    final hit = otherAt(industries, at.dx, at.dy);
    if (hit != null) {
      _otherTap(hit.industry, hit.other);
      return;
    }
    final group = smallIndustriesAt(layout, at.dx, at.dy);
    if (group != null) widget.onSmallIndustriesTap(group);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    // 圖上文字與頁面其他文字同一套字族
    final font = theme.textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 撐滿父層給的最大尺寸：Stack 的大小由非 Positioned 的子元件決定，
        // 寬鬆的 constraints 下會縮成 0、點不到
        final size = constraints.biggest;
        if (!size.isFinite) return const SizedBox.shrink();
        final layout = _layoutFor(size);
        return SizedBox.fromSize(
          size: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: HeatmapPainter(
                      layout: layout.industries,
                      smallIndustries: layout.smallIndustries,
                      brightness: brightness,
                      zoomed: widget.zoomIndustryKey != null,
                      labels: widget.labels,
                      onIndustryTap: _semanticIndustryTap,
                      onTileTap: _semanticTileTap,
                      onOtherTap: _otherTap,
                      onSmallIndustriesTap: _semanticGroupTap,
                      fontFamily: font?.fontFamily,
                      fontFamilyFallback: font?.fontFamilyFallback,
                      liveMode: widget.data.liveMode,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: MouseRegion(
                  onHover: (e) => _showAt(layout, e.localPosition),
                  onExit: (_) => _hover.value = null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    // 無障礙動作由 painter 的產業／格子節點提供；這裡的節點沒有
                    // 名稱，啟用時會點到圖的正中央
                    excludeFromSemantics: true,
                    onTapUp: (d) => _tap(layout, d.localPosition),
                    // 手機：按住時顯示、移動時換格子、放開就收
                    onLongPressStart: (d) => _showAt(layout, d.localPosition),
                    onLongPressMoveUpdate: (d) =>
                        _showAt(layout, d.localPosition),
                    onLongPressEnd: (_) => _hover.value = null,
                    onLongPressCancel: () => _hover.value = null,
                  ),
                ),
              ),
              ValueListenableBuilder<_Hover?>(
                valueListenable: _hover,
                builder: (context, hover, _) {
                  final shown = hover == null || identical(hover.layout, layout)
                      ? hover
                      : _followLayout(hover, layout);
                  return shown == null
                      ? const SizedBox.shrink()
                      : _positioned(shown, size);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 提示靠在指標右下；指標在右半或下半時以中線翻到另一側（圖區太小時仍可能
  /// 被裁切）
  Widget _positioned(_Hover hover, Size size) {
    final right = hover.at.dx > size.width / 2;
    final below = hover.at.dy <= size.height / 2;
    return Positioned(
      left: right ? null : hover.at.dx + HeatmapParams.tooltipOffset,
      right: right
          ? size.width - hover.at.dx + HeatmapParams.tooltipOffset
          : null,
      top: below ? hover.at.dy + HeatmapParams.tooltipOffset : null,
      bottom: below
          ? null
          : size.height - hover.at.dy + HeatmapParams.tooltipOffset,
      child: IgnorePointer(child: _tooltip(hover)),
    );
  }

  Widget _tooltip(_Hover hover) {
    final group = hover.group;
    if (group != null) {
      return HeatmapIndustryGroupTooltip(
        group: group,
        title: widget.labels.groupLabel(group.members.length),
        liveMode: widget.data.liveMode,
      );
    }
    final industryName =
        hover.industry!.industry.name ?? widget.labels.uncategorized;
    final tile = hover.tile;
    if (tile != null) {
      return HeatmapTooltip(
        tile: tile.tile,
        industryName: industryName,
        dataDate: widget.data.dataDate,
        liveMode: widget.data.liveMode,
      );
    }
    final other = hover.other!;
    return HeatmapOtherTooltip(
      other: other,
      title: other.wholeIndustry
          ? industryName
          : widget.labels.otherLabel(other.members.length),
      industryName: industryName,
      liveMode: widget.data.liveMode,
    );
  }
}

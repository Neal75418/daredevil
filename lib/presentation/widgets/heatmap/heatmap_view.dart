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
/// painter 才不會重畫；提示畫在獨立一層，滑鼠移動只重建提示。
class HeatmapView extends StatefulWidget {
  const HeatmapView({
    super.key,
    required this.data,
    required this.zoomIndustryKey,
    required this.onIndustryTap,
    required this.onTileTap,
    required this.onOtherTap,
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
  final HeatmapPaintLabels labels;

  @override
  State<HeatmapView> createState() => _HeatmapViewState();
}

/// 提示：指著的格子或合併塊（兩者擇一）、所屬產業、位置，以及算出它的那份
/// 佈局（佈局換了就不畫）
typedef _Hover = ({
  List<HeatmapIndustryLayout> layout,
  HeatmapIndustryLayout industry,
  HeatmapTileLayout? tile,
  HeatmapOtherLayout? other,
  Offset at,
});

class _HeatmapViewState extends State<HeatmapView> {
  final _hover = ValueNotifier<_Hover?>(null);

  HeatmapMarketData? _cachedData;
  String? _cachedZoom;
  Size? _cachedSize;
  List<HeatmapIndustryLayout> _layout = const [];

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  List<HeatmapIndustryLayout> _layoutFor(Size size) {
    if (identical(_cachedData, widget.data) &&
        _cachedZoom == widget.zoomIndustryKey &&
        _cachedSize == size) {
      return _layout;
    }
    final zoom = widget.zoomIndustryKey;
    final industries = zoom == null
        ? widget.data.industries
        : [
            for (final i in widget.data.industries)
              if (i.key == zoom) i,
          ];
    final watch = Stopwatch()..start();
    _layout = layoutHeatmap(industries, width: size.width, height: size.height);
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

  void _showAt(List<HeatmapIndustryLayout> layout, Offset at) {
    final tile = tileAt(layout, at.dx, at.dy);
    if (tile != null) {
      final industry = layout.firstWhere(
        (l) => l.tiles.any((t) => identical(t, tile)),
      );
      _hover.value = (
        layout: layout,
        industry: industry,
        tile: tile,
        other: null,
        at: at,
      );
      return;
    }
    final hit = otherAt(layout, at.dx, at.dy);
    _hover.value = hit == null
        ? null
        : (
            layout: layout,
            industry: hit.industry,
            tile: null,
            other: hit.other,
            at: at,
          );
  }

  // 無障礙節點的點擊：穩定的方法 tear-off，painter 比較時才相等
  void _semanticIndustryTap(String key) => widget.onIndustryTap(key);
  void _semanticTileTap(String symbol) => widget.onTileTap(symbol);

  /// 合併塊的點擊（手勢與無障礙共用）：全市場圖上整個產業合成的那塊放大
  /// 該產業；其餘（包括已放大後仍整個合成一塊的）列出成員
  void _otherTap(HeatmapIndustryLayout industry, HeatmapOtherLayout other) {
    if (other.wholeIndustry && widget.zoomIndustryKey == null) {
      widget.onIndustryTap(industry.industry.key);
    } else {
      widget.onOtherTap(industry, other);
    }
  }

  void _tap(List<HeatmapIndustryLayout> layout, Offset at) {
    final header = industryHeaderAt(layout, at.dx, at.dy);
    if (header != null) {
      widget.onIndustryTap(header.industry.key);
      return;
    }
    final tile = tileAt(layout, at.dx, at.dy);
    if (tile != null) {
      widget.onTileTap(tile.tile.symbol);
      return;
    }
    final hit = otherAt(layout, at.dx, at.dy);
    if (hit != null) _otherTap(hit.industry, hit.other);
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
                      layout: layout,
                      brightness: brightness,
                      zoomed: widget.zoomIndustryKey != null,
                      labels: widget.labels,
                      onIndustryTap: _semanticIndustryTap,
                      onTileTap: _semanticTileTap,
                      onOtherTap: _otherTap,
                      fontFamily: font?.fontFamily,
                      fontFamilyFallback: font?.fontFamilyFallback,
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
                // 佈局換了（資料、放大、尺寸改變），舊提示指的格子可能已不在
                // 原處：不畫，等下一次指標移動。不在 build 期間改 notifier
                builder: (context, hover, _) =>
                    hover == null || !identical(hover.layout, layout)
                    ? const SizedBox.shrink()
                    : _positioned(hover, size),
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
    final industryName =
        hover.industry.industry.name ?? widget.labels.uncategorized;
    final tile = hover.tile;
    if (tile != null) {
      return HeatmapTooltip(tile: tile.tile, industryName: industryName);
    }
    final other = hover.other!;
    return HeatmapOtherTooltip(
      other: other,
      title: other.wholeIndustry
          ? industryName
          : widget.labels.otherLabel(other.members.length),
      industryName: industryName,
    );
  }
}

import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_tooltip.dart';

/// 一個市場的熱力圖：佈局、繪製、點擊、滑鼠與長按提示。
///
/// 佈局依（資料、尺寸）快取，兩者不變時沿用同一個 list，painter 才不會重畫；
/// 提示畫在獨立一層，滑鼠移動只重建提示。即時套色的時段取資料自己的
/// [HeatmapMarketData.liveMode]。
class HeatmapView extends StatefulWidget {
  const HeatmapView({
    super.key,
    required this.data,
    required this.onTileTap,
    required this.labels,
    required this.uncategorizedLabel,
  });

  final HeatmapMarketData data;
  final ValueChanged<String> onTileTap;
  final HeatmapPaintLabels labels;

  /// 產業別空白的股票在提示裡寫的產業名稱（「未分類」）
  final String uncategorizedLabel;

  @override
  State<HeatmapView> createState() => _HeatmapViewState();
}

/// 提示：指著的格子、位置，以及算出它的那份佈局（佈局換了就在新佈局的同一個
/// 位置重查）
typedef _Hover = ({
  List<HeatmapTileLayout> layout,
  HeatmapTileLayout tile,
  Offset at,
});

class _HeatmapViewState extends State<HeatmapView> {
  final _hover = ValueNotifier<_Hover?>(null);

  HeatmapMarketData? _cachedData;
  Size? _cachedSize;
  List<HeatmapTileLayout> _layout = const [];

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  List<HeatmapTileLayout> _layoutFor(Size size) {
    if (identical(_cachedData, widget.data) && _cachedSize == size) {
      return _layout;
    }
    final watch = Stopwatch()..start();
    _layout = layoutHeatmapTiles(
      widget.data.tiles,
      width: size.width,
      height: size.height,
    );
    watch.stop();
    AppLogger.debug(
      'MarketHeatmap',
      '${widget.data.market} layout ${watch.elapsedMilliseconds}ms',
    );
    _cachedData = widget.data;
    _cachedSize = size;
    return _layout;
  }

  void _showAt(List<HeatmapTileLayout> layout, Offset at) =>
      _hover.value = _hoverAt(layout, at);

  /// [at] 在 [layout] 上指著的格子；沒有時為 null（純計算）
  static _Hover? _hoverAt(List<HeatmapTileLayout> layout, Offset at) {
    final tile = heatmapTileAt(layout, at.dx, at.dy);
    return tile == null ? null : (layout: layout, tile: tile, at: at);
  }

  /// 佈局換了（新一輪即時資料、圖上的檔換了、尺寸）而提示還開著：同一個位置
  /// 在新佈局重查並在這一幀畫出（盤中每輪換資料時提示不空白一幀）；查不到就
  /// 收起。結果在這一幀結束後才寫回 [_hover]：build 期間不改 notifier；這段
  /// 時間指標已經移動（[_hover] 換了）就不蓋掉。
  _Hover? _followLayout(_Hover hover, List<HeatmapTileLayout> layout) {
    final next = _hoverAt(layout, hover.at);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_hover.value, hover)) _hover.value = next;
    });
    return next;
  }

  // 無障礙節點的點擊：穩定的方法 tear-off，painter 比較時才相等
  void _semanticTileTap(String symbol) => widget.onTileTap(symbol);

  void _tap(List<HeatmapTileLayout> layout, Offset at) {
    final tile = heatmapTileAt(layout, at.dx, at.dy);
    if (tile != null) widget.onTileTap(tile.tile.symbol);
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
                      labels: widget.labels,
                      onTileTap: _semanticTileTap,
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
                    // 無障礙動作由 painter 的格子節點提供；這裡的節點沒有名稱，
                    // 啟用時會點到圖的正中央
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
    final tile = hover.tile.tile;
    return HeatmapTooltip(
      tile: tile,
      industryName: tile.industry ?? widget.uncategorizedLabel,
      dataDate: widget.data.dataDate,
      liveMode: widget.data.liveMode,
    );
  }
}

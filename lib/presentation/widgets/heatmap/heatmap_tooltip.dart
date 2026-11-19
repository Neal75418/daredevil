import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_text.dart';

/// 熱力圖格子的提示：名稱、代號與產業、價格（即時套色時空心格子的價格是
/// 正式資料那天的收盤，標出日期）、漲跌幅（空心寫原因；盤中未即時另附正式
/// 資料那天的漲跌與日期）、市值
class HeatmapTooltip extends StatelessWidget {
  const HeatmapTooltip({
    super.key,
    required this.tile,
    required this.industryName,
    required this.dataDate,
    this.liveMode,
  });

  final HeatmapTile tile;

  /// 正式資料的日期（[HeatmapMarketData.dataDate]）
  final DateTime dataDate;

  /// 資料的即時套色時段（[HeatmapMarketData.liveMode]）；null 是正式資料
  final HeatmapLiveMode? liveMode;

  /// 所屬產業（產業別空白時是「未分類」）：圖上不分產業，只能從這裡知道
  final String industryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = tile.change;
    final changeText = switch (change) {
      TileChangeValue(:final percent) => formatHeatmapPercent(percent),
      TileChangeHollow(:final reason) => heatmapHollowReasonText(reason),
    };
    final previous = switch (change) {
      TileChangeHollow(:final previous?) => heatmapPreviousCloseText(previous),
      _ => null,
    };
    final cap = formatHeatmapCap(
      tile.marketCap,
      Localizations.localeOf(context),
    );
    return _TooltipCard(
      children: [
        Text(tile.name, style: theme.textTheme.titleSmall),
        Text(
          '${tile.symbol} · $industryName',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          heatmapTooltipPriceText(
            tile.close,
            // 即時套色時只有上色的格子換成即時價，空心的仍是正式資料的收盤
            closeDate: liveMode != null && change is TileChangeHollow
                ? dataDate
                : null,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          '${'marketHeatmap.tooltipChange'.tr()} $changeText',
          style: theme.textTheme.bodySmall,
        ),
        if (previous != null) Text(previous, style: theme.textTheme.bodySmall),
        Text(
          'marketHeatmap.tooltipCap'.tr(namedArgs: {'value': cap}),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
    child: Padding(
      padding: const EdgeInsets.all(DesignTokens.spacing8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

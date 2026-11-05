import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';

/// 熱力圖格子的提示：名稱、代號與產業、價格、漲跌幅（空心寫原因）、市值
class HeatmapTooltip extends StatelessWidget {
  const HeatmapTooltip({
    super.key,
    required this.tile,
    required this.industryName,
  });

  final HeatmapTile tile;

  /// 所屬產業（產業別空白時是「未分類」）：小產業在全市場圖上沒有標題列，
  /// 只能從這裡知道是哪個產業
  final String industryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = tile.change;
    final changeText = switch (change) {
      TileChangeValue(:final percent) => formatHeatmapPercent(percent),
      TileChangeHollow() => 'marketHeatmap.hollowNoChange'.tr(),
    };
    final cap = formatHeatmapCap(
      tile.marketCap,
      Localizations.localeOf(context),
    );
    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tile.name, style: theme.textTheme.titleSmall),
            Text(
              '${tile.symbol} · $industryName',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${'marketHeatmap.tooltipPrice'.tr()} '
              '${tile.close.toStringAsFixed(2)}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${'marketHeatmap.tooltipChange'.tr()} $changeText',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'marketHeatmap.tooltipCap'.tr(namedArgs: {'value': cap}),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
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
    return _TooltipCard(
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
    );
  }
}

/// 合併塊的提示：標籤（整個產業時是產業名稱）、所屬產業（整個產業時是檔數）、
/// 漲跌家數、市值加權漲跌、市值
class HeatmapOtherTooltip extends StatelessWidget {
  const HeatmapOtherTooltip({
    super.key,
    required this.other,
    required this.title,
    required this.industryName,
  });

  final HeatmapOtherLayout other;

  /// 「其他 N 檔」；整個產業都合併時是產業名稱
  final String title;
  final String industryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = other.breadth;
    final counts = {'up': '${b.up}', 'down': '${b.down}', 'flat': '${b.flat}'};
    final breadth = b.hollow > 0
        ? 'marketHeatmap.tooltipBreadthWithHollow'.tr(
            namedArgs: {...counts, 'hollow': '${b.hollow}'},
          )
        : 'marketHeatmap.tooltipBreadth'.tr(namedArgs: counts);
    final percent = other.weightedChangePercent;
    final cap = formatHeatmapCap(
      other.marketCap,
      Localizations.localeOf(context),
    );
    return _TooltipCard(
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        Text(
          other.wholeIndustry
              ? 'marketHeatmap.tooltipStocks'.tr(
                  namedArgs: {'count': '${other.members.length}'},
                )
              : industryName,
          style: theme.textTheme.bodySmall,
        ),
        Text(breadth, style: theme.textTheme.bodySmall),
        Text(
          '${'marketHeatmap.tooltipWeighted'.tr()} '
          '${percent == null ? 'marketHeatmap.hollowNoChange'.tr() : formatHeatmapPercent(percent)}',
          style: theme.textTheme.bodySmall,
        ),
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

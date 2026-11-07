import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_text.dart';

/// 熱力圖格子的提示：名稱、代號與產業、價格、漲跌幅（空心寫原因；盤中未即時
/// 另附正式資料那天的漲跌與日期）、市值
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
          '${'marketHeatmap.tooltipPrice'.tr()} '
          '${tile.close.toStringAsFixed(2)}',
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

/// 合併塊的提示：標籤（整個產業時是產業名稱）、所屬產業（整個產業時是檔數）、
/// 含幾檔自選或持股（有才寫）、漲跌家數、市值加權漲跌（即時套色時接即時比例）、
/// 市值
class HeatmapOtherTooltip extends StatelessWidget {
  const HeatmapOtherTooltip({
    super.key,
    required this.other,
    required this.title,
    required this.industryName,
    this.liveMode,
  });

  final HeatmapOtherLayout other;

  /// 「其他 N 檔」；整個產業都合併時是產業名稱
  final String title;
  final String industryName;

  /// 資料的即時套色時段（[HeatmapMarketData.liveMode]）；null 是正式資料
  final HeatmapLiveMode? liveMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breadth = heatmapBreadthText(other.breadth);
    final weighted = heatmapWeightedText(
      percent: other.weightedChangePercent,
      coverage: other.coverage,
      mode: liveMode,
      allNoClosingMatch: other.allNoClosingMatch,
    );
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
        // 合併塊的自選框表示「你的股票在裡面」：說是幾檔
        if (other.mineCount > 0)
          Text(
            'marketHeatmap.tooltipMine'.tr(
              namedArgs: {'count': '${other.mineCount}'},
            ),
            style: theme.textTheme.bodySmall,
          ),
        Text(breadth, style: theme.textTheme.bodySmall),
        Text(
          '${'marketHeatmap.tooltipWeighted'.tr()} $weighted',
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

/// 小產業合併塊的提示：「其他 N 個產業」、檔數、含幾檔自選或持股（有才寫）、
/// 漲跌家數、市值加權漲跌（即時套色時接即時比例）、市值
class HeatmapIndustryGroupTooltip extends StatelessWidget {
  const HeatmapIndustryGroupTooltip({
    super.key,
    required this.group,
    required this.title,
    this.liveMode,
  });

  final HeatmapIndustryGroupLayout group;

  /// 「其他 N 個產業」
  final String title;

  /// 資料的即時套色時段（[HeatmapMarketData.liveMode]）；null 是正式資料
  final HeatmapLiveMode? liveMode;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final weighted = heatmapWeightedText(
      percent: group.weightedChangePercent,
      coverage: group.coverage,
      mode: liveMode,
      allNoClosingMatch: group.allNoClosingMatch,
    );
    return _TooltipCard(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        Text(
          'marketHeatmap.tooltipStocks'.tr(
            namedArgs: {'count': '${group.stockCount}'},
          ),
          style: style,
        ),
        if (group.mineCount > 0)
          Text(
            'marketHeatmap.tooltipMine'.tr(
              namedArgs: {'count': '${group.mineCount}'},
            ),
            style: style,
          ),
        Text(heatmapBreadthText(group.breadth), style: style),
        Text('${'marketHeatmap.tooltipWeighted'.tr()} $weighted', style: style),
        Text(
          'marketHeatmap.tooltipCap'.tr(
            namedArgs: {
              'value': formatHeatmapCap(
                group.marketCap,
                Localizations.localeOf(context),
              ),
            },
          ),
          style: style,
        ),
      ],
    );
  }
}

/// 漲跌家數（有空心時另寫空心的檔數）：提示與清單共用
String heatmapBreadthText(HeatmapBreadth b) {
  final counts = {'up': '${b.up}', 'down': '${b.down}', 'flat': '${b.flat}'};
  return b.hollow > 0
      ? 'marketHeatmap.tooltipBreadthWithHollow'.tr(
          namedArgs: {...counts, 'hollow': '${b.hollow}'},
        )
      : 'marketHeatmap.tooltipBreadth'.tr(namedArgs: counts);
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

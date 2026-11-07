import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_mine_mark.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_text.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_tooltip.dart';

/// 「其他 N 個產業」的產業清單（從畫面下方拉出），點一列放大該產業。順序與
/// 「其他 N 檔」的清單同一套：含自選或持股的產業排最前面並加雙線框標記，
/// 其餘依市值加權漲跌由高到低，沒有漲跌資料的放最後。
///
/// 內容是打開當下的資料（[group] 與 [liveMode]），之後的即時更新不改它。
class HeatmapIndustryGroupSheet extends StatelessWidget {
  const HeatmapIndustryGroupSheet({
    super.key,
    required this.title,
    required this.group,
    required this.onIndustryTap,
    this.scrollController,
    this.liveMode,
  });

  /// 「其他 N 個產業」
  final String title;
  final HeatmapIndustryGroupLayout group;

  /// 回呼產業 key（[HeatmapIndustry.key]）
  final ValueChanged<String> onIndustryTap;

  /// 放在可拖動的面板裡時，由面板提供
  final ScrollController? scrollController;

  /// 資料的即時套色時段（[HeatmapMarketData.liveMode]）；null 是正式資料
  final HeatmapLiveMode? liveMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final locale = Localizations.localeOf(context);
    final weighted = heatmapWeightedText(
      percent: group.weightedChangePercent,
      coverage: group.coverage,
      mode: liveMode,
    );
    final members = sortHeatmapGroupMembers(group.members);
    return ListView.builder(
      controller: scrollController,
      itemCount: members.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing16,
              DesignTokens.spacing16,
              DesignTokens.spacing8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(heatmapBreadthText(group.breadth), style: muted),
                Text(
                  '${'marketHeatmap.tooltipWeighted'.tr()} $weighted',
                  style: muted,
                ),
              ],
            ),
          );
        }
        final industry = members[i - 1];
        final name = industry.name ?? 'marketHeatmap.uncategorized'.tr();
        final percent = industry.weightedChangePercent;
        final count = 'marketHeatmap.tooltipStocks'.tr(
          namedArgs: {'count': '${industry.tiles.length}'},
        );
        final cap = 'marketHeatmap.tooltipCap'.tr(
          namedArgs: {'value': formatHeatmapCap(industry.marketCap, locale)},
        );
        return ListTile(
          title: _hasMine(industry)
              ? Row(
                  children: [
                    Flexible(child: Text(name)),
                    const SizedBox(width: DesignTokens.spacing6),
                    HeatmapMineMark(
                      semanticLabel: 'marketHeatmap.mineMark'.tr(),
                    ),
                  ],
                )
              : Text(name),
          subtitle: Text('$count · $cap'),
          trailing: percent == null
              ? Text(heatmapNoChangeText(liveMode), style: muted)
              : Text(
                  heatmapWeightedText(
                    percent: percent,
                    coverage: industry.liveCoverage,
                    mode: liveMode,
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    // 與顯示的數字同一個值（0.00% 不上紅綠）
                    color: context.priceColor(
                      HeatmapParams.roundPercent(percent),
                    ),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
          onTap: () => onIndustryTap(industry.key),
        );
      },
    );
  }
}

bool _hasMine(HeatmapIndustry industry) => industry.tiles.any((t) => t.isMine);

/// 清單順序：含自選或持股的產業在前、其餘在後；兩組內各自依市值加權漲跌由高
/// 到低（看四捨五入到 2 位後、畫面上顯示的值；同值依市值），沒有漲跌資料的
/// 放最後（依市值）
@visibleForTesting
List<HeatmapIndustry> sortHeatmapGroupMembers(List<HeatmapIndustry> members) {
  double? percentOf(HeatmapIndustry i) => switch (i.weightedChangePercent) {
    final pct? => HeatmapParams.roundPercent(pct),
    null => null,
  };
  return [...members]..sort((a, b) {
    final ma = _hasMine(a);
    if (ma != _hasMine(b)) return ma ? -1 : 1;
    final pa = percentOf(a);
    final pb = percentOf(b);
    if (pa == null || pb == null) {
      if (pa != pb) return pa == null ? 1 : -1;
      return b.marketCap.compareTo(a.marketCap);
    }
    final byPercent = pb.compareTo(pa);
    return byPercent != 0 ? byPercent : b.marketCap.compareTo(a.marketCap);
  });
}

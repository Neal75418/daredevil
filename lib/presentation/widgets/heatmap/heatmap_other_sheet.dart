import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';

/// 「其他 N 檔」的成員清單（從畫面下方拉出）：依漲跌幅排序（漲最多在上，
/// 沒有漲跌資料的放最後），點一列進個股頁。合併的都是小型股，打開清單是想找
/// 「誰在動」，所以不照市值排；每列仍寫市值。
class HeatmapOtherSheet extends StatelessWidget {
  const HeatmapOtherSheet({
    super.key,
    required this.title,
    required this.other,
    required this.onStockTap,
    this.scrollController,
  });

  /// 例如「半導體業 · 其他 80 檔」
  final String title;
  final HeatmapOtherLayout other;
  final ValueChanged<String> onStockTap;

  /// 放在可拖動的面板裡時，由面板提供
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final locale = Localizations.localeOf(context);
    final b = other.breadth;
    final counts = {'up': '${b.up}', 'down': '${b.down}', 'flat': '${b.flat}'};
    final breadth = b.hollow > 0
        ? 'marketHeatmap.tooltipBreadthWithHollow'.tr(
            namedArgs: {...counts, 'hollow': '${b.hollow}'},
          )
        : 'marketHeatmap.tooltipBreadth'.tr(namedArgs: counts);
    final weighted = other.weightedChangePercent;
    final members = sortHeatmapOtherMembers(other.members);
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
                Text(breadth, style: muted),
                Text(
                  '${'marketHeatmap.tooltipWeighted'.tr()} '
                  '${weighted == null ? 'marketHeatmap.hollowNoChange'.tr() : formatHeatmapPercent(weighted)}',
                  style: muted,
                ),
              ],
            ),
          );
        }
        final tile = members[i - 1];
        final change = tile.change;
        final cap = 'marketHeatmap.tooltipCap'.tr(
          namedArgs: {'value': formatHeatmapCap(tile.marketCap, locale)},
        );
        return ListTile(
          title: Text(tile.name),
          subtitle: Text('${tile.symbol} · $cap'),
          trailing: switch (change) {
            TileChangeValue(:final percent) => Text(
              formatHeatmapPercent(percent),
              style: theme.textTheme.titleSmall?.copyWith(
                // 與顯示的數字同一個值（0.00% 不上紅綠）
                color: context.priceColor(HeatmapParams.roundPercent(percent)),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            TileChangeHollow() => Text(
              'marketHeatmap.hollowNoChange'.tr(),
              style: muted,
            ),
          },
          onTap: () => onStockTap(tile.symbol),
        );
      },
    );
  }
}

/// 清單順序：有漲跌的依漲跌幅由高到低（看四捨五入到 2 位後、畫面上顯示的
/// 值；同值依市值），沒有漲跌資料的放最後（依市值）
@visibleForTesting
List<HeatmapTile> sortHeatmapOtherMembers(List<HeatmapTile> members) {
  double? percentOf(HeatmapTile t) => switch (t.change) {
    TileChangeValue(:final percent) => HeatmapParams.roundPercent(percent),
    TileChangeHollow() => null,
  };
  return [...members]..sort((a, b) {
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

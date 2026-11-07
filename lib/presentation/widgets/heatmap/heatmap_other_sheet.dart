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

/// 「其他 N 檔」的成員清單（從畫面下方拉出）：自選或持股排最前面並加雙線框
/// 標記（合併塊的自選框表示它們在裡面，打開就要看得到），其餘依漲跌幅排序
/// （漲最多在上，沒有漲跌資料的放最後），點一列進個股頁。合併的都是小型股，
/// 打開清單是想找「誰在動」，所以不照市值排；每列仍寫市值。
///
/// 內容是打開當下的資料（[other] 與 [liveMode]），之後的即時更新不改它。
class HeatmapOtherSheet extends StatelessWidget {
  const HeatmapOtherSheet({
    super.key,
    required this.title,
    required this.other,
    required this.onStockTap,
    this.scrollController,
    this.liveMode,
  });

  /// 例如「半導體業 · 其他 80 檔」
  final String title;
  final HeatmapOtherLayout other;
  final ValueChanged<String> onStockTap;

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
    final breadth = heatmapBreadthText(other.breadth);
    final weighted = heatmapWeightedText(
      percent: other.weightedChangePercent,
      coverage: other.coverage,
      mode: liveMode,
      allNoClosingMatch: other.allNoClosingMatch,
    );
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
                  '${'marketHeatmap.tooltipWeighted'.tr()} $weighted',
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
          title: tile.isMine
              ? Row(
                  children: [
                    Flexible(child: Text(tile.name)),
                    const SizedBox(width: DesignTokens.spacing6),
                    HeatmapMineMark(
                      semanticLabel: 'marketHeatmap.mineMark'.tr(),
                    ),
                  ],
                )
              : Text(tile.name),
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
            TileChangeHollow(:final reason) => Text(
              heatmapHollowReasonText(reason),
              style: muted,
            ),
          },
          onTap: () => onStockTap(tile.symbol),
        );
      },
    );
  }
}

/// 清單順序：自選或持股在前、其餘在後；兩組內各自有漲跌的依漲跌幅由高到低
/// （看四捨五入到 2 位後、畫面上顯示的值；同值依市值），沒有漲跌資料的放
/// 最後（依市值）
@visibleForTesting
List<HeatmapTile> sortHeatmapOtherMembers(List<HeatmapTile> members) {
  double? percentOf(HeatmapTile t) => switch (t.change) {
    TileChangeValue(:final percent) => HeatmapParams.roundPercent(percent),
    TileChangeHollow() => null,
  };
  return [...members]..sort((a, b) {
    if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
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

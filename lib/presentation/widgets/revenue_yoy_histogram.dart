import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

/// 月營收年增分佈橫幅——「這個月市場整體好嗎」的一眼答案(2026-08-14)。
///
/// 動機:總覽 1,900+ 列只能逐列讀個股,缺全局視角。已申報列的年增就地
/// 聚合成 9 桶直方圖(<-30、每 10pp 一桶、≥+40),標題帶已申報家數、
/// 中位數與上漲家數比——體溫在標題,形狀在柱子。零新資料。
///
/// 呈現取捨:
/// - 純 flexbox 柱(FractionallySizedBox)而非 CustomPainter——柱高
///   可從 widget tree 直接測,不需要 golden
/// - 桶色依號誌:負桶跌色、正桶漲色(股價紅漲綠跌語意,同增減率欄)
/// - 兩端開放桶讓怪物(+109 萬%)也有位置,不會拉爆座標
class RevenueYoyHistogram extends StatelessWidget {
  const RevenueYoyHistogram({super.key, required this.values});

  /// 已申報列的單月年增(%),null 由呼叫端先濾除
  final List<double> values;

  /// 桶邊界:9 桶 = (<-30) + [-30..40) 每 10pp + (≥40)
  static const List<double> _edges = [-30, -20, -10, 0, 10, 20, 30, 40];

  static int get binCount => _edges.length + 1;

  /// 分桶(下緣含、上緣不含;首桶 < -30、末桶 ≥ +40)
  static List<int> binCounts(List<double> values) {
    final counts = List<int>.filled(binCount, 0);
    for (final v in values) {
      var bin = 0;
      while (bin < _edges.length && v >= _edges[bin]) {
        bin++;
      }
      counts[bin]++;
    }
    return counts;
  }

  static double? median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final counts = binCounts(values);
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();
    final med = median(values)!;
    // 「年增為正」嚴格取 v > 0:年增恰為 0 不算成長(柱狀圖上 0 落在
    // [0,10) 桶被塗漲色,是分桶邊界的取捨,兩處對持平的歸類刻意不同)
    final risingPct = values.where((v) => v > 0).length / values.length * 100;

    final downColor = PriceColors.downFor(theme.brightness);
    // 桶 i 的值域上緣 ≤0 → 負桶(跌色);其餘正桶(漲色)
    Color binColor(int i) =>
        (i < 4 ? downColor : AppTheme.upColor).withValues(alpha: 0.55);

    // 桶標籤:只標 -30/0/+40 三個錨點,其餘留白——9 個全標會擠成噪音
    String? edgeLabel(int i) => switch (i) {
      0 => '<-30%',
      4 => '0',
      8 => '≥40%',
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'revenueOverview.histogramCaption'.tr(
              namedArgs: {
                'count': '${values.length}',
                'median': '${med > 0 ? '+' : ''}${med.toStringAsFixed(1)}%',
                'rising': risingPct.toStringAsFixed(0),
              },
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing6),
          SizedBox(
            height: DesignTokens.histogramBarAreaHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < counts.length; i++) ...[
                  if (i > 0) const SizedBox(width: DesignTokens.spacing2),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: counts[i] / maxCount,
                      child: Container(
                        decoration: BoxDecoration(
                          color: binColor(i),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(DesignTokens.radiusXs),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.spacing2),
          Row(
            children: [
              for (var i = 0; i < counts.length; i++) ...[
                if (i > 0) const SizedBox(width: DesignTokens.spacing2),
                Expanded(
                  child: Text(
                    edgeLabel(i) ?? '',
                    textAlign: i == 0
                        ? TextAlign.left
                        : i == counts.length - 1
                        ? TextAlign.right
                        : TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: DesignTokens.fontSizeXs,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

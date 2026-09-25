import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/score_tier.dart';

/// 分級徽章 + 小字數字（評分改進 #5）
///
/// 分數點值差異無統計意義（score-報酬 IC ≈ 0.17）——列表以強/中/弱
/// 分級為主視覺，確切分數退為小字輔助（診斷/驗證仍看得到）。
///
/// 雙 horizon 模式（[ScoreTierBadge.dual]）：徽章級別與小字數字都取
/// 兩者較高分（與訊號成立「任一 horizon ≥ 門檻」同語意）。
class ScoreTierBadge extends StatelessWidget {
  const ScoreTierBadge({super.key, required double score})
    : shortScore = score,
      longScore = score;

  const ScoreTierBadge.dual({
    super.key,
    required this.shortScore,
    required this.longScore,
  });

  final double shortScore;
  final double longScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayScore = shortScore > longScore ? shortScore : longScore;
    final tier = ScoreTier.fromScore(displayScore);
    final style = _tierStyle(scheme, tier);
    final numberStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 11,
      height: 1,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: BorderRadius.circular(4),
            border: style.border == null
                ? null
                : Border.all(color: style.border!, width: 1),
          ),
          child: Text(
            tier.i18nKey.tr(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: style.text,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 5),
        // 只顯示分級依據的那個分數（較高者）。兩個 horizon 並排曾讓徽章在
        // 窄卡片被 FittedBox 縮到看不清（390pt 約 0.42 倍），也看不出分級
        // 看的是哪個；兩套權重的差異說明在「訊號卡怎麼看」。
        Text(displayScore.toStringAsFixed(0), style: numberStyle),
      ],
    );
  }

  // 分數是「符合目前模式條件的程度」，不是漲跌方向——紅綠專屬股價
  // （semantic_colors），這裡用品牌色的深淺表現強弱：強＝實心、中＝外框、
  // 弱＝灰框、觀察＝灰字。原本強／中是綠系，緊貼綠色的下跌數字會被讀成
  // 看跌。
  static ({Color? fill, Color? border, Color text}) _tierStyle(
    ColorScheme scheme,
    ScoreTier tier,
  ) => switch (tier) {
    ScoreTier.strong => (
      fill: scheme.primary,
      border: scheme.primary,
      text: scheme.onPrimary,
    ),
    ScoreTier.medium => (
      fill: null,
      border: scheme.primary,
      text: scheme.primary,
    ),
    ScoreTier.weak => (
      fill: null,
      border: scheme.onSurfaceVariant,
      text: scheme.onSurfaceVariant,
    ),
    ScoreTier.observation => (
      fill: null,
      border: null,
      text: scheme.onSurfaceVariant,
    ),
  };
}

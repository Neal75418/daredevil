import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 頂部橫幅卡片，顯示籌碼強度分數（0-100）、進度條與法人態度標籤。
class ChipStrengthIndicator extends StatelessWidget {
  const ChipStrengthIndicator({super.key, required this.strength});

  final ChipStrengthResult strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _ratingColor(strength.rating);

    // 資料不足:六域幾乎全空時分數停在 baseline、會被評成「中性」——
    // 「沒被量測」與「實測中性」逐 pixel 相同,仍是謊報(上櫃的持股/當沖/
    // 融資覆蓋系統性稀疏,正是重災區)。此時只給「資料不足」,分數/進度條/
    // 法人態度全不顯示(那些是無輸入下的預設值,不是量測結果)。
    if (strength.isInsufficient) {
      return Container(
        padding: const EdgeInsets.all(DesignTokens.spacing16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.battery_unknown,
              size: 18,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: DesignTokens.spacing6),
            Text(
              'chip.strength'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                'chip.insufficientCaption'.tr(
                  args: ['${strength.measuredDomains}'],
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            children: [
              Icon(Icons.battery_charging_full, size: 18, color: color),
              const SizedBox(width: DesignTokens.spacing6),
              Text(
                'chip.strength'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 評等徽章
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing10,
                  vertical: DesignTokens.spacing4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
                child: Text(
                  strength.rating.i18nKey.tr(),
                  // tint 上的文字走深色專屬解析（strong 紅本色僅 3.76:1）
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: PriceColors.chipRatingOnTint(
                      strength.rating,
                      theme.brightness,
                    ),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing12),

          // 分數＋進度條
          Row(
            children: [
              Text(
                '${strength.score}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                ' / 100',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: DesignTokens.spacing16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                  child: LinearProgressIndicator(
                    value: strength.score / 100,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing8),

          // 法人態度
          Row(
            children: [
              Text(
                'chip.institutionalAttitude'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: DesignTokens.spacing8),
              Text(
                strength.attitude.i18nKey.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _attitudeColor(strength.attitude, theme),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _ratingColor(ChipRating rating) => PriceColors.chipRating(rating);

  /// 法人態度色 —— 與 [_ratingColor] 同一多空語意軸（買超為多／紅，
  /// 賣超為空／綠），故沿用相同的 [PriceColors] 對應，不另立一套色階。
  Color _attitudeColor(InstitutionalAttitude attitude, ThemeData theme) {
    return switch (attitude) {
      InstitutionalAttitude.aggressiveBuy => PriceColors.up,
      InstitutionalAttitude.moderateBuy => PriceColors.chipBullish,
      InstitutionalAttitude.neutral => theme.colorScheme.onSurfaceVariant,
      InstitutionalAttitude.moderateSell => PriceColors.chipBearish,
      InstitutionalAttitude.aggressiveSell => PriceColors.down,
    };
  }
}

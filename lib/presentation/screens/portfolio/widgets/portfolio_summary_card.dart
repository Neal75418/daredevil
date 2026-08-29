import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 投資組合總覽卡片
class PortfolioSummaryCard extends StatelessWidget {
  const PortfolioSummaryCard({super.key, required this.summary});

  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 依顯示精度捨入後判方向：平盤（0）→ 中性色、不帶 +，與下方 _PnlItem 一致。
    final roundedPnl = AppNumberFormat.roundForDisplay(summary.totalPnl, 0);
    final pnlColor = roundedPnl == 0
        ? theme.colorScheme.onSurface
        : (roundedPnl > 0 ? AppTheme.upColor : AppTheme.downColor);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'portfolio.summary'.tr(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing8),

          // 總市值
          Text(
            'NT\$${_formatNumber(summary.totalMarketValue)}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing4),

          // 總損益
          Row(
            children: [
              Text(
                'portfolio.totalPnl'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: DesignTokens.spacing8),
              Text(
                '${roundedPnl > 0 ? "+" : ""}NT\$${_formatNumber(summary.totalPnl)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pnlColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: DesignTokens.spacing4),
              Text(
                '(${AppNumberFormat.signedPercent(summary.totalPnlPct, decimals: 1)})',
                style: theme.textTheme.bodySmall?.copyWith(color: pnlColor),
              ),
            ],
          ),
          // 缺價警示(靜默稽核 #5):缺當日價的持股以成本價計值、未實現
          // 損益恰為 0——上方的總市值/總損益因此偏樂觀,必須說出來
          if (summary.unpricedCount > 0) ...[
            const SizedBox(height: DesignTokens.spacing8),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: theme.brightness == Brightness.light
                      ? WarningColors.warningOnLight
                      : WarningColors.warning,
                ),
                const SizedBox(width: DesignTokens.spacing4),
                Text(
                  'portfolio.unpricedWarning'.tr(
                    namedArgs: {'count': '${summary.unpricedCount}'},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.brightness == Brightness.light
                        ? WarningColors.warningOnLight
                        : WarningColors.warning,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: DesignTokens.spacing12),

          // 損益明細
          Row(
            children: [
              Expanded(
                child: _PnlItem(
                  label: 'portfolio.unrealizedPnl'.tr(),
                  value: summary.totalUnrealizedPnl,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _PnlItem(
                  label: 'portfolio.realizedPnl'.tr(),
                  value: summary.totalRealizedPnl,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _PnlItem(
                  label: 'portfolio.dividendIncome'.tr(),
                  value: summary.totalDividends,
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) => LocalizedNumberFormat.compact(value);
}

class _PnlItem extends StatelessWidget {
  const _PnlItem({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final double value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // 依顯示精度（0 位）捨入後判方向：平盤/微負值→中性色、顯示 0（不帶 +/-）。
    final rounded = AppNumberFormat.roundForDisplay(value, 0);
    final color = rounded == 0
        ? theme.colorScheme.onSurface
        : (rounded > 0 ? AppTheme.upColor : AppTheme.downColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: DesignTokens.spacing2),
        Text(
          rounded == 0 ? '0' : AppNumberFormat.signedInteger(value),
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

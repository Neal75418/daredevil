import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/services/portfolio_analytics_service.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 投資組合績效卡片
///
/// 顯示期間報酬、最大回撤等績效指標
class PerformanceCard extends StatelessWidget {
  const PerformanceCard({super.key, required this.performance});

  final PortfolioPerformance performance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: DesignTokens.spacing8),
              Text(
                'portfolio.performance'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // 期間報酬
          _buildSectionLabel(theme, 'portfolio.periodReturns'.tr()),
          const SizedBox(height: DesignTokens.spacing8),
          Row(
            children: [
              Expanded(
                child: _ReturnItem(
                  label: 'portfolio.daily'.tr(),
                  value: performance.periodReturns.daily,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _ReturnItem(
                  label: 'portfolio.weekly'.tr(),
                  value: performance.periodReturns.weekly,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _ReturnItem(
                  label: 'portfolio.monthly'.tr(),
                  value: performance.periodReturns.monthly,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _ReturnItem(
                  label: 'portfolio.yearly'.tr(),
                  value: performance.periodReturns.yearly,
                  theme: theme,
                  isAnnualized: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // 總報酬與回撤
          Row(
            children: [
              Expanded(
                child: _MetricItem(
                  label: 'portfolio.totalReturn'.tr(),
                  value: performance.totalReturn,
                  isPercentage: true,
                  theme: theme,
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: 'portfolio.maxDrawdown'.tr(),
                  value: -performance.maxDrawdown,
                  isPercentage: true,
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ReturnItem extends StatelessWidget {
  const _ReturnItem({
    required this.label,
    required this.value,
    required this.theme,
    this.isAnnualized = false,
  });

  final String label;

  /// 報酬（%）；null 表示算不出來，顯示「—」
  final double? value;
  final ThemeData theme;
  final bool isAnnualized;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    // 依顯示精度（2 位）捨入後判方向：平盤/微負值→中性色、不帶 +，與數字一致。
    final rounded = value == null
        ? null
        : AppNumberFormat.roundForDisplay(value, 2);
    final color = switch (rounded) {
      null => theme.colorScheme.onSurfaceVariant,
      0 => theme.colorScheme.onSurface,
      > 0 => AppTheme.upColor,
      _ => AppTheme.downColor,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (isAnnualized) ...[
              const SizedBox(width: DesignTokens.spacing2),
              Tooltip(
                message: 'portfolio.yearlyHint'.tr(),
                child: Icon(
                  Icons.info_outline,
                  size: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: DesignTokens.spacing2),
        Text(
          value == null
              ? '—'
              : AppNumberFormat.signedPercent(value, decimals: 2),
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.theme,
    this.isPercentage = false,
  });

  final String label;
  final double value;
  final ThemeData theme;
  final bool isPercentage;

  @override
  Widget build(BuildContext context) {
    // 紅漲綠跌（回撤傳負值，虧損是下跌色），依顯示精度捨入後判方向：平盤→
    // 中性色。文字一律 round-then-sign（signedPercent/signedInteger）：平盤
    // 不帶 +、微負值不出現 -0.00
    final rounded = AppNumberFormat.roundForDisplay(
      value,
      isPercentage ? 2 : 0,
    );
    final color = rounded == 0
        ? theme.colorScheme.onSurface
        : (rounded > 0 ? AppTheme.upColor : AppTheme.downColor);

    final String formatted = isPercentage
        ? AppNumberFormat.signedPercent(value, decimals: 2)
        : AppNumberFormat.signedInteger(value);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacing12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing4),
          Text(
            formatted,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

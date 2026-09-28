import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/services/dividend_intelligence_service.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 根據殖利率取得對應顏色
///
/// - >= 5%: 紅色（高殖利率——台股偏多色）
/// - >= 3%: 橘色（中殖利率）
/// - < 3%: 灰色（低殖利率）
Color _getYieldColor(double yield_) {
  if (yield_ >= 5) return AppTheme.upColor;
  if (yield_ >= 3) return const Color(0xFFF59E0B); // 橘色
  return AppTheme.neutralSlateColor;
}

/// 股利分析卡片
///
/// 顯示投資組合的股利相關資訊：
/// - 預期年度股利
/// - 組合殖利率
/// - 各持股股利資訊
class DividendAnalysisCard extends StatelessWidget {
  const DividendAnalysisCard({super.key, required this.analysis});

  final DividendAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (analysis.stockDividends.isEmpty) {
      return const SizedBox.shrink();
    }

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
                Icons.payments_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: DesignTokens.spacing8),
              Text(
                'portfolio.dividendAnalysis'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // 總覽數據
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'portfolio.expectedDividend'.tr(),
                  value:
                      'NT\$${LocalizedNumberFormat.compact(analysis.totalExpectedDividend, Localizations.localeOf(context))}',
                  subValue: 'portfolio.yearly'.tr(),
                  theme: theme,
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'portfolio.yieldOnCost'.tr(),
                  value: '${analysis.portfolioYieldOnCost.toStringAsFixed(2)}%',
                  valueColor: _getYieldColor(analysis.portfolioYieldOnCost),
                  theme: theme,
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'portfolio.yieldOnMarket'.tr(),
                  value:
                      '${analysis.portfolioYieldOnMarket.toStringAsFixed(2)}%',
                  valueColor: _getYieldColor(analysis.portfolioYieldOnMarket),
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // 各持股股利資訊（最多顯示 5 筆）
          Text(
            'portfolio.stockDividends'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing8),

          for (var i = 0; i < analysis.stockDividends.length && i < 5; i++)
            _StockDividendRow(
              info: analysis.stockDividends[i],
              theme: theme,
              isLast: i == analysis.stockDividends.length - 1 || i == 4,
            ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
    required this.theme,
  });

  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
        if (subValue != null)
          Text(
            subValue!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }
}

class _StockDividendRow extends StatelessWidget {
  const _StockDividendRow({
    required this.info,
    required this.theme,
    required this.isLast,
  });

  final StockDividendInfo info;
  final ThemeData theme;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacing8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
      ),
      child: Row(
        children: [
          // 股票代碼和趨勢
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  info.symbol,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing4),
                _TrendIcon(trend: info.trend),
              ],
            ),
          ),

          // 每股股利
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppNumberFormat.currency(
                    info.estimatedDividendPerShare,
                    decimals: 2,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'portfolio.perShare'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: DesignTokens.fontSizeXs,
                  ),
                ),
              ],
            ),
          ),

          // 預期金額
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'NT\$${LocalizedNumberFormat.compact(info.expectedYearlyAmount, Localizations.localeOf(context))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.upColor,
                  ),
                ),
                Text(
                  'portfolio.expected'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: DesignTokens.fontSizeXs,
                  ),
                ),
              ],
            ),
          ),

          // 個人殖利率
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${info.personalYield.toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _getYieldColor(info.personalYield),
                  ),
                ),
                Text(
                  'portfolio.yield'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: DesignTokens.fontSizeXs,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendIcon extends StatelessWidget {
  const _TrendIcon({required this.trend});

  final DividendTrend trend;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (trend) {
      case DividendTrend.increasing:
        icon = Icons.trending_up;
        color = AppTheme.upColor;
      case DividendTrend.decreasing:
        icon = Icons.trending_down;
        color = AppTheme.downColor;
      case DividendTrend.stable:
        icon = Icons.trending_flat;
        color = AppTheme.neutralSlateColor;
    }

    return Icon(icon, size: 14, color: color);
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/mini_trend_chart.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 顯示融資融券資料：摘要卡片、趨勢圖與明細表。
class MarginTradingSection extends StatelessWidget {
  const MarginTradingSection({super.key, required this.history});

  final List<MarginTradingEntry> history;

  /// 走勢圖與表格顯示的列數。loader 為評分會多讀幾天
  /// （DataFreshness.chipMarginLookbackDays），畫面不跟著拉長。
  static const _displayRows = 10;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (history.isNotEmpty) _buildSummary(context),

        if (history.isNotEmpty) const SizedBox(height: DesignTokens.spacing12),

        SectionHeader(title: 'chip.sectionMargin'.tr(), icon: Icons.swap_horiz),
        const SizedBox(height: DesignTokens.spacing12),

        if (history.isEmpty)
          buildEmptyState(context, 'chip.noData'.tr())
        else ...[
          _buildTrendChart(),
          const SizedBox(height: DesignTokens.spacing12),
          _buildTable(context),
        ],
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);

    final sorted = List<MarginTradingEntry>.from(history)
      ..sort((a, b) => b.date.compareTo(a.date));
    final latest = sorted.first;
    final marginBal = latest.marginBalance ?? 0;
    final shortBal = latest.shortBalance ?? 0;

    // 計算融券/融資比——「高」門檻與評分層同一常數（2026-07-23 稽核修復：
    // 原 hardcode 10 恰為評分層的**低**檔界線，同概念 3 倍差）
    final shortMarginRatio = marginBal > 0 ? (shortBal / marginBal * 100) : 0.0;
    final isHighRatio =
        shortMarginRatio > ChipScoringParams.highShortMarginRatio;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(DesignTokens.spacing12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color: AppTheme.upColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 14,
                      color: AppTheme.upColor,
                    ),
                    const SizedBox(width: DesignTokens.spacing4),
                    Text(
                      'chip.marginBalance'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacing6),
                Text(
                  formatBalance(marginBal, Localizations.localeOf(context)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(DesignTokens.spacing12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color:
                    (isHighRatio
                            ? AppTheme.downColor
                            : theme.colorScheme.outline)
                        .withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.percent,
                      size: 14,
                      color: isHighRatio
                          ? AppTheme.downColor
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: DesignTokens.spacing4),
                    Text(
                      'chip.shortMarginRatio'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacing6),
                Text(
                  '${shortMarginRatio.toStringAsFixed(1)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isHighRatio
                        ? AppTheme.downColor
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    final sorted = List<MarginTradingEntry>.from(history)
      ..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.length < 2) return const SizedBox.shrink();

    final recent = sorted.length > _displayRows
        ? sorted.sublist(sorted.length - _displayRows)
        : sorted;
    final data = recent.map((e) => (e.marginBalance ?? 0).toDouble()).toList();
    return MiniTrendChart(
      dataPoints: data,
      lineColor: AppTheme.upColor,
      minY: 0,
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);

    final sorted = List<MarginTradingEntry>.from(history)
      ..sort((a, b) => b.date.compareTo(a.date));
    final displayData = sorted.take(_displayRows).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing12),
        child: Column(
          children: [
            // 標題
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacing8,
                horizontal: DesignTokens.spacing4,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'stockDetail.date'.tr(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'chip.marginBalance'.tr(),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'chip.shortBalance'.tr(),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'chip.shortMarginRatio'.tr(),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spacing8),
            ...displayData.asMap().entries.map((entry) {
              final index = entry.key;
              final margin = entry.value;
              final marginBal = margin.marginBalance ?? 0;
              final shortBal = margin.shortBalance ?? 0;
              final ratio = marginBal > 0 ? (shortBal / marginBal * 100) : 0.0;

              return Container(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spacing8,
                  horizontal: DesignTokens.spacing4,
                ),
                decoration: BoxDecoration(
                  color: index == 0
                      ? theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.3,
                        )
                      : (index.isEven
                            ? theme.colorScheme.surface
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${margin.date.month}/${margin.date.day}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: index == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatBalance(
                          marginBal,
                          Localizations.localeOf(context),
                        ),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatBalance(
                          shortBal,
                          Localizations.localeOf(context),
                        ),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacing6,
                          vertical: DesignTokens.spacing2,
                        ),
                        decoration: BoxDecoration(
                          color: ratio > ChipScoringParams.highShortMarginRatio
                              ? AppTheme.downColor.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusXs,
                          ),
                        ),
                        child: Text(
                          '${ratio.toStringAsFixed(1)}%',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight:
                                ratio > ChipScoringParams.highShortMarginRatio
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color:
                                ratio > ChipScoringParams.highShortMarginRatio
                                ? AppTheme.downColor
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

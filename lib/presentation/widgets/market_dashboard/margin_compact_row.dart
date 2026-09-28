import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/domain/services/market_reading_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/mini_trend_chart.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_reading_line.dart';

/// 融資融券精簡顯示
///
/// 兩欄並排，顯示融資增減和融券增減，帶漲跌箭頭
class MarginCompactRow extends StatelessWidget {
  const MarginCompactRow({
    super.key,
    required this.data,
    this.marginBalanceHistory,
    this.shortBalanceHistory,
    this.indexChangePercent,
  });

  final MarginTradingTotals data;

  /// 30日融資餘額歷史（供趨勢 sparkline，oldest→newest）
  final List<double>? marginBalanceHistory;

  /// 30日融券餘額歷史（供趨勢 sparkline，oldest→newest）
  final List<double>? shortBalanceHistory;

  /// 大盤（加權指數）漲跌幅（%），供籌碼槓桿判讀；null 時不顯示判讀行
  final double? indexChangePercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.marginChange == 0 && data.shortChange == 0) {
      return const SizedBox.shrink();
    }

    // 籌碼槓桿判讀：需大盤漲跌幅，缺則不顯示
    final changePct = indexChangePercent;
    final reading = changePct != null
        ? MarketReadingService.interpretMarginLeverage(
            marginChange: data.marginChange,
            indexChangePercent: changePct,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'marketOverview.margin'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: DesignTokens.spacing10),
        Row(
          children: [
            Expanded(
              child: _MarginItem(
                label: 'marketOverview.marginBalance'.tr(),
                change: data.marginChange,
                balance: data.marginBalance,
                history: marginBalanceHistory,
              ),
            ),
            const SizedBox(width: DesignTokens.spacing12),
            Expanded(
              child: _MarginItem(
                label: 'marketOverview.shortBalance'.tr(),
                change: data.shortChange,
                balance: data.shortBalance,
                history: shortBalanceHistory,
              ),
            ),
          ],
        ),
        if (data.marginBalance > 0 && data.shortBalance > 0) ...[
          const SizedBox(height: DesignTokens.spacing8),
          _ShortMarginRatioRow(
            ratio: data.shortBalance / data.marginBalance * 100,
          ),
        ],
        // 判讀層（籌碼槓桿）
        MarketReadingLine(reading: reading),
      ],
    );
  }
}

class _ShortMarginRatioRow extends StatelessWidget {
  const _ShortMarginRatioRow({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing12,
        vertical: DesignTokens.spacing6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'marketOverview.shortMarginRatio'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '${ratio.toStringAsFixed(2)}%',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarginItem extends StatelessWidget {
  const _MarginItem({
    required this.label,
    required this.change,
    required this.balance,
    this.history,
  });

  final String label;
  final double change;
  final double balance;
  final List<double>? history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.getPriceColor(change, theme.brightness);
    final icon = change > 0
        ? Icons.arrow_upward_rounded
        : change < 0
        ? Icons.arrow_downward_rounded
        : Icons.remove;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing12,
        vertical: DesignTokens.spacing10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: DesignTokens.spacing8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacing2),
                Text(
                  formatMarginSheets(change, Localizations.localeOf(context)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (balance != 0) ...[
                  const SizedBox(height: 1),
                  Text(
                    '${'marketOverview.balance'.tr()} ${formatMarginBalance(balance, Localizations.localeOf(context))}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: DesignTokens.fontSizeXs,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                // 30日趨勢 sparkline
                if (history != null && history!.length >= 2) ...[
                  const SizedBox(height: DesignTokens.spacing6),
                  MiniTrendChart(
                    dataPoints: history!,
                    height: 36,
                    lineColor: color,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 格式化增減張數：中文大數字用「萬張」，其他語系走
/// [LocalizedNumberFormat.compact]。
@visibleForTesting
String formatMarginSheets(double value, Locale locale) {
  final absVal = value.abs();
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  if (!LocalizedNumberFormat.usesChineseUnits(locale)) {
    return '$sign${LocalizedNumberFormat.compact(absVal, locale)}'
        '${'stockDetail.unitShares'.tr()}';
  }

  if (absVal >= 10000) {
    return '$sign${(absVal / 10000).toStringAsFixed(1)} 萬張';
  }
  return '$sign${NumberFormat('#,##0').format(absVal)} 張';
}

/// 格式化餘額：中文 萬張/億張，其他語系走 [LocalizedNumberFormat.compact]。
@visibleForTesting
String formatMarginBalance(double value, Locale locale) {
  final absVal = value.abs();
  if (!LocalizedNumberFormat.usesChineseUnits(locale)) {
    return '${LocalizedNumberFormat.compact(absVal, locale)}'
        '${'stockDetail.unitShares'.tr()}';
  }
  if (absVal >= 1e8) {
    return '${(absVal / 1e8).toStringAsFixed(1)} 億張';
  } else if (absVal >= 10000) {
    return '${(absVal / 10000).toStringAsFixed(1)} 萬張';
  }
  return '${NumberFormat('#,##0').format(absVal)} 張';
}

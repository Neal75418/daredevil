import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart'
    show formatLots;

/// 顯示今日 OHLCV（開盤、最高、最低、收盤、成交量）交易資料。
class OhlcvCard extends StatelessWidget {
  const OhlcvCard({
    super.key,
    required this.latestPrice,
    required this.priceChange,
  });

  final DailyPriceEntry? latestPrice;
  final double? priceChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 與顯示文字同精度（2 位）捨入後判方向：平盤/微負值（-0.004→0.00%）一律中性，
    // 收盤價配色、badge 箭頭與 +/- 號皆據此推導，與數字一致。
    final displayedChange = priceChange == null
        ? null
        : AppNumberFormat.roundForDisplay(priceChange!, 2);
    final priceColor = AppTheme.getPriceColor(
      displayedChange,
      theme.brightness,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, theme, priceColor, displayedChange),
            const SizedBox(height: DesignTokens.spacing16),
            // 價格格線
            Row(
              children: [
                Expanded(
                  child: _PriceCell(
                    label: 'stockDetail.open'.tr(),
                    value: latestPrice?.open,
                    valueColor: theme.colorScheme.onSurface,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _PriceCell(
                    label: 'stockDetail.high'.tr(),
                    value: latestPrice?.high,
                    valueColor: AppTheme.upColor,
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: theme.colorScheme.outlineVariant),
            Row(
              children: [
                Expanded(
                  child: _PriceCell(
                    label: 'stockDetail.low'.tr(),
                    value: latestPrice?.low,
                    valueColor: AppTheme.downColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _PriceCell(
                    label: 'stockDetail.close'.tr(),
                    value: latestPrice?.close,
                    valueColor: priceColor,
                    isBold: true,
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: theme.colorScheme.outlineVariant),
            // 成交量
            Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Text(
                  'stockDetail.volume'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatVolumeOrDash(
                    latestPrice?.volume,
                    Localizations.localeOf(context),
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    Color priceColor,
    double? displayedChange,
  ) {
    final change = displayedChange ?? 0;
    final IconData arrow = change > 0
        ? Icons.trending_up
        : (change < 0 ? Icons.trending_down : Icons.trending_flat);
    return Row(
      children: [
        Icon(
          Icons.candlestick_chart,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Text(
          'stockDetail.todayTrading'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (priceChange != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing8,
              vertical: DesignTokens.spacing4,
            ),
            decoration: BoxDecoration(
              color: priceColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  arrow,
                  size: 14,
                  color: PriceColors.onTintOf(
                    priceColor,
                    Theme.of(context).brightness,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing4),
                Text(
                  _formatChangeBadge(),
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    fontWeight: FontWeight.bold,
                    color: PriceColors.onTintOf(
                      priceColor,
                      Theme.of(context).brightness,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 格式化 OHLCV 卡片標題的漲跌 badge
  ///
  /// 百分比與絕對變動皆經 round-then-sign：平盤/微負值捨入歸零後不帶 `+`、
  /// 也不會出現 `-0.00`，與 badge 中性配色一致。
  String _formatChangeBadge() {
    final pctText = AppNumberFormat.signedPercent(priceChange!, decimals: 2);
    final close = latestPrice?.close;
    // 判零用「捨入後」值與 header badge 對齊（2026-07-23 稽核修復：原用
    // 原始值判零，-0.004 時 header 顯示 0.00% 而這裡仍走絕對值分支顯示
    // 「0.00 (0.00%)」甚至「-0.04 (0.00%)」）
    final displayed = AppNumberFormat.roundForDisplay(priceChange!, 2);
    if (close != null && displayed != 0) {
      final absChange = close * priceChange! / (100 + priceChange!);
      final absText = AppNumberFormat.signedFixed(absChange, decimals: 2);
      return '$absText ($pctText)';
    }
    return pctText;
  }

  /// 格式化成交量（處理 null）
  String _formatVolumeOrDash(double? volume, Locale locale) {
    if (volume == null) return '-';
    return _formatVolume(volume, locale);
  }

  /// 格式化成交量為台灣習慣的「張」單位
  ///
  /// API 回傳單位為「股」，台灣股市習慣用「張」（1張 = 1000股）
  String _formatVolume(double volume, Locale locale) {
    final lots = volume / 1000;
    if (lots < 1) return volume.toStringAsFixed(0);
    return formatLots(lots, locale);
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({
    required this.label,
    required this.value,
    required this.valueColor,
    this.isBold = false,
  });

  final String label;
  final double? value;
  final Color valueColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DesignTokens.spacing4),
        Text(
          value?.toStringAsFixed(2) ?? '-',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

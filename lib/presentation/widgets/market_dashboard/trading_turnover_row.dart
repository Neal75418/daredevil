import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/services/market_reading_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_reading_line.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/mini_bar_chart.dart';

/// 成交額統計列
///
/// 顯示市場總成交額，單位為億元
class TradingTurnoverRow extends StatelessWidget {
  const TradingTurnoverRow({
    super.key,
    required this.data,
    this.turnoverComparison,
    this.turnoverHistory,
    this.indexChangePercent,
  });

  final TradingTurnover data;
  final TurnoverComparison? turnoverComparison;

  /// 30日成交額歷史（供趨勢 bar chart，oldest→newest）
  final List<double>? turnoverHistory;

  /// 大盤（加權指數）漲跌幅（%），供量價判讀；null 時不顯示判讀行
  final double? indexChangePercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.totalTurnover == 0) {
      return const SizedBox.shrink();
    }

    // 量價判讀：需有 5 日均量比較 + 大盤漲跌幅，缺一不顯示
    final comparison = turnoverComparison;
    final changePct = indexChangePercent;
    final reading =
        (comparison != null &&
            comparison.avg5dTurnover > 0 &&
            changePct != null)
        ? MarketReadingService.interpretVolumePrice(
            todayTurnover: comparison.todayTurnover,
            avg5dTurnover: comparison.avg5dTurnover,
            indexChangePercent: changePct,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 標籤
              //
              // 半寬卡片 + EN 翻譯（"Trading Turnover"）或非預期長 key 時
              // 也用 Flexible + ellipsis 保護，避免擠掉右側數值的空間。
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.paid_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'marketOverview.tradingTurnover'.tr(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // 數值 + 均量比較
              //
              // 卡片寬度緊時（半寬 dashboard 排版 + 萬億級成交額 + 5 位數
              // 百分比），這條 Row 自然寬度會超出父 Row 給的剩餘空間（實測
              // 1-2 像素 overflow，screenshot 2026-06）。Flexible 提供
              // 上限，FittedBox(scaleDown) 在臨界時對整組做等比縮放；正常
              // 寬度不觸發、design intent 保留。
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTurnover(data.totalTurnover),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (turnoverComparison != null &&
                          turnoverComparison!.avg5dTurnover > 0) ...[
                        const SizedBox(width: 8),
                        _Avg5dBadge(
                          changePercent: turnoverComparison!.changePercent,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 判讀層（量價）
          MarketReadingLine(reading: reading),
          // 30日趨勢 bar chart
          if (turnoverHistory != null && turnoverHistory!.length >= 2) ...[
            const SizedBox(height: 8),
            MiniBarChart(
              dataPoints: turnoverHistory!,
              height: 32,
              positiveOnlyColor: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  /// 格式化成交額顯示
  ///
  /// 將元轉換為億元顯示
  /// 例如：642195569620 → "6,422.0 億元"（≥ 1000 億一位小數，其餘兩位）
  String _formatTurnover(double turnover) {
    if (turnover == 0) return '0 ${'marketOverview.unitBillion'.tr()}';

    final turnoverInHundredMillion = turnover / 100000000; // 轉換為億元

    if (turnoverInHundredMillion >= 10000) {
      // >= 10000 億（兆），顯示兩位小數
      final formatted = NumberFormat(
        '#,##0.00',
      ).format(turnoverInHundredMillion);
      return '$formatted ${'marketOverview.unitBillion'.tr()}';
    } else if (turnoverInHundredMillion >= 1000) {
      // >= 1000 億，顯示一位小數
      final formatted = NumberFormat(
        '#,##0.0',
      ).format(turnoverInHundredMillion);
      return '$formatted ${'marketOverview.unitBillion'.tr()}';
    } else {
      // < 1000 億，顯示兩位小數
      final formatted = NumberFormat(
        '#,##0.00',
      ).format(turnoverInHundredMillion);
      return '$formatted ${'marketOverview.unitBillion'.tr()}';
    }
  }
}

class _Avg5dBadge extends StatelessWidget {
  const _Avg5dBadge({required this.changePercent});

  final double changePercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 依顯示精度（0 位）捨入後判方向：微幅變動（如 +0.4%）捨入為 0 時中性、
    // 不帶 +，避免顯示「0%」卻著漲色。
    final rounded = AppNumberFormat.roundForDisplay(changePercent, 0);
    final color = AppTheme.getPriceColor(rounded, theme.brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        color: color.withValues(alpha: 0.1),
      ),
      child: Text(
        '${'marketOverview.avg5d'.tr()} ${AppNumberFormat.signedFixed(changePercent, decimals: 0)}%',
        style: theme.textTheme.labelSmall?.copyWith(
          color: PriceColors.onTintOf(color, Theme.of(context).brightness),
          fontWeight: FontWeight.w600,
          fontSize: DesignTokens.fontSizeXs,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

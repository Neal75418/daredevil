import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 持股卡片上與盤中即時報價有關的資料;null = 盤後行為
@immutable
class PositionCardLive {
  const PositionCardLive({this.flash, this.flashEnabled = true, this.caption});

  /// 本輪閃色事件(只閃現價)
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 例外標示(已翻譯):報價暫停／無報價／最後報價 HH:MM:SS
  final String? caption;
}

/// 單一持倉卡片
class PositionCard extends StatelessWidget {
  const PositionCard({
    super.key,
    required this.position,
    required this.onTap,
    this.live,
  });

  final PortfolioPositionData position;
  final VoidCallback onTap;

  /// 盤中即時報價;null = 盤後行為
  final PositionCardLive? live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 依顯示精度捨入後判方向：平盤/微負值→中性色，與數字一致。
    final roundedPnl = AppNumberFormat.roundForDisplay(
      position.unrealizedPnl,
      0,
    );
    final pnlColor = roundedPnl == 0
        ? theme.colorScheme.onSurface
        : (roundedPnl > 0 ? AppTheme.upColor : AppTheme.downColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing16,
          vertical: DesignTokens.spacing12,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        child: Row(
          children: [
            // 左側：股票資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        position.symbol,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing6),
                      Expanded(
                        child: Text(
                          position.stockName ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spacing4),
                  Wrap(
                    spacing: DesignTokens.spacing8,
                    children: [
                      Text(
                        '${'portfolio.avgCost'.tr()}: ${AppNumberFormat.currency(position.avgCost, decimals: 1)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      // 現價用一般文字色:閃色時疊在紅綠底上,灰字對比不夠
                      PriceFlash(
                        flash: live?.flash,
                        enabled: live?.flashEnabled ?? true,
                        child: Text(
                          '${'portfolio.currentPrice'.tr()}: ${AppNumberFormat.currency(position.currentPrice ?? 0, decimals: 1)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (live?.caption case final caption?) ...[
                    const SizedBox(height: DesignTokens.spacing2),
                    Text(
                      caption,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 右側：損益
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${AppNumberFormat.integer(position.quantity)} ${'portfolio.quantity'.tr()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacing2),
                Text(
                  AppNumberFormat.signedInteger(position.unrealizedPnl),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: pnlColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '(${AppNumberFormat.signedPercent(position.unrealizedPnlPct, decimals: 1)})',
                  style: theme.textTheme.labelSmall?.copyWith(color: pnlColor),
                ),
              ],
            ),
            const SizedBox(width: DesignTokens.spacing4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/constants/score_tier.dart';
import 'package:daredevil/core/extensions/trend_state_extension.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/reason_tags.dart';
import 'package:daredevil/presentation/widgets/score_tier_badge.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 股票預覽資料
class StockPreviewData {
  const StockPreviewData({
    required this.symbol,
    this.stockName,
    this.latestClose,
    this.priceChange,
    this.score,
    this.trendState,
    this.reasons = const [],
    this.isInWatchlist = false,
  });

  final String symbol;
  final String? stockName;
  final double? latestClose;
  final double? priceChange;
  final double? score;
  final String? trendState;
  final List<String> reasons;
  final bool isInWatchlist;
}

/// 顯示股票預覽 bottom sheet
///
/// [onMoveToGroup] 非 null 時顯示「移到分組」動作（自選股清單長按才提供）。
Future<void> showStockPreviewSheet({
  required BuildContext context,
  required StockPreviewData data,
  VoidCallback? onViewDetails,
  VoidCallback? onToggleWatchlist,
  VoidCallback? onMoveToGroup,
}) {
  HapticFeedback.mediumImpact();

  return showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => StockPreviewSheet(
      data: data,
      onViewDetails: onViewDetails,
      onToggleWatchlist: onToggleWatchlist,
      onMoveToGroup: onMoveToGroup,
    ),
  );
}

/// 股票預覽 bottom sheet 元件
class StockPreviewSheet extends StatelessWidget {
  const StockPreviewSheet({
    super.key,
    required this.data,
    this.onViewDetails,
    this.onToggleWatchlist,
    this.onMoveToGroup,
  });

  final StockPreviewData data;
  final VoidCallback? onViewDetails;
  final VoidCallback? onToggleWatchlist;

  /// 「移到分組」動作（非 null 才顯示，僅自選股清單長按提供）
  final VoidCallback? onMoveToGroup;

  /// 建構無障礙語義標籤（使用 AppStrings 集中管理的字串）
  String _buildSemanticLabel() {
    final parts = <String>[S.stockPreview, data.symbol];
    if (data.stockName != null) parts.add(data.stockName!);
    if (data.latestClose != null) {
      parts.add(S.accessibilityPrice(data.latestClose!));
    }
    if (data.priceChange != null) {
      parts.add(S.accessibilityPriceChange(data.priceChange!));
    }
    if (data.score != null && data.score! > 0) {
      parts.add(S.accessibilityScore(data.score!.toInt()));
      parts.add(ScoreTier.fromScore(data.score!).i18nKey.tr());
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.isDark;
    // 與顯示文字同精度（2 位）捨入後判方向：平盤/微負值（-0.004→0.00%）一律
    // 中性配色、中性箭頭，與 +/- 號一致。
    final displayedChange = data.priceChange == null
        ? null
        : AppNumberFormat.roundForDisplay(data.priceChange!, 2);
    final priceColor = AppTheme.getPriceColor(
      displayedChange,
      theme.brightness,
    );
    final isNeutral = displayedChange == null || displayedChange == 0;
    final isPositive = (displayedChange ?? 0) > 0;
    final trendColor = data.trendState.trendColorFor(theme.brightness);

    return Semantics(
      label: _buildSemanticLabel(),
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: DesignTokens.opacity20),
              blurRadius: DesignTokens.shadowBlurLg,
              offset: DesignTokens.shadowOffsetUp,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖曳把手
            const DragHandle(),

            // 內容區
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacing24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題列
                  Row(
                    children: [
                      // 趨勢指示器
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              trendColor.withValues(alpha: 0.2),
                              trendColor.withValues(alpha: 0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusXl,
                          ),
                          border: Border.all(
                            color: trendColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            data.trendState.trendEmoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ).animate().scale(
                        begin: const Offset(0.8, 0.8),
                        duration: AnimDurations.normal,
                        curve: AnimCurves.bounce,
                      ),
                      const SizedBox(width: DesignTokens.spacing16),

                      // 代號與名稱
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.symbol,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (data.stockName != null)
                              Text(
                                data.stockName!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 價格區
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (data.latestClose != null)
                            Text(
                              data.latestClose!.toStringAsFixed(2),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (data.priceChange != null)
                            Container(
                              margin: const EdgeInsets.only(
                                top: DesignTokens.spacing4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.spacing10,
                                vertical: DesignTokens.spacing4,
                              ),
                              decoration: BoxDecoration(
                                color: priceColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusMd,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 裝飾圖示 — 文字已包含正負號
                                  ExcludeSemantics(
                                    child: Icon(
                                      isNeutral
                                          ? Icons.trending_flat
                                          : (isPositive
                                                ? Icons.arrow_drop_up
                                                : Icons.arrow_drop_down),
                                      color: PriceColors.onTintOf(
                                        priceColor,
                                        Theme.of(context).brightness,
                                      ),
                                      size: 20,
                                    ),
                                  ),
                                  Text(
                                    AppNumberFormat.signedPercent(
                                      data.priceChange!,
                                      decimals: 2,
                                    ),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: PriceColors.onTintOf(
                                        priceColor,
                                        Theme.of(context).brightness,
                                      ),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // 評分區
                  if (data.score != null && data.score! > 0) ...[
                    const SizedBox(height: DesignTokens.spacing20),
                    _buildScoreSection(theme),
                  ],

                  // 訊號理由區
                  if (data.reasons.isNotEmpty) ...[
                    const SizedBox(height: DesignTokens.spacing16),
                    _buildReasonsSection(theme, isDark),
                  ],

                  // 操作按鈕
                  const SizedBox(height: DesignTokens.spacing24),
                  Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                                onToggleWatchlist?.call();
                              },
                              icon: Icon(
                                data.isInWatchlist
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: data.isInWatchlist ? Colors.amber : null,
                              ),
                              label: Text(
                                data.isInWatchlist
                                    ? S.stockRemoveFromWatchlist
                                    : S.stockAddToWatchlist,
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: DesignTokens.spacing14,
                                ),
                                side: BorderSide(
                                  color: data.isInWatchlist
                                      ? Colors.amber
                                      : theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacing12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                                onViewDetails?.call();
                              },
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: Text(S.stockViewDetails),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: DesignTokens.spacing14,
                                ),
                                // FilledButton 前景為 onPrimary（淺色白）：
                                // AppTheme.primaryColor 恆為深色版品牌亮色，
                                // 白字對比不足；主題 primary 淺色解析為
                                // brandOnLight 深藍達標，深色同值不變。
                                backgroundColor: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      )
                      .animate()
                      .fadeIn(
                        delay: AnimDurations.standard,
                        duration: AnimDurations.normal,
                      )
                      .slideY(begin: 0.2, duration: AnimDurations.normal),

                  // 移到分組（僅自選股清單長按提供 onMoveToGroup 時顯示）
                  if (onMoveToGroup != null) ...[
                    const SizedBox(height: DesignTokens.spacing12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                          onMoveToGroup!.call();
                        },
                        icon: const Icon(Icons.folder_outlined),
                        label: Text('watchlist.moveToGroup'.tr()),
                      ),
                    ),
                  ],

                  // 底部安全區域
                  SizedBox(
                    height:
                        MediaQuery.of(context).padding.bottom +
                        DesignTokens.spacing8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 與卡片同一個分級徽章：同一檔股票長按前後必須顯示同一個等級
  /// （曾各用 80/60/40 等級字、50/35/20 圓環色，與卡片的強中弱不一致）。
  Widget _buildScoreSection(ThemeData theme) {
    return Row(
      children: [
        Text(
          S.scoreLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: DesignTokens.spacing12),
        ScoreTierBadge(score: data.score!),
      ],
    );
  }

  Widget _buildReasonsSection(ThemeData theme, bool isDark) {
    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.reasonsLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spacing8),
            ReasonTags(reasons: data.reasons, translateCodes: true),
          ],
        )
        .animate()
        .fadeIn(delay: AnimDurations.press, duration: AnimDurations.normal)
        .slideY(begin: 0.1, duration: AnimDurations.normal);
  }
}

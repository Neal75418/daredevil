import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/rule_params_institutional.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/mini_bar_chart.dart';

/// 格式化金額（元）：中文 億/千萬/百萬（億依大小取 0/1/2 位小數），其他
/// 語系走 [LocalizedNumberFormat.compact]。
@visibleForTesting
String formatFlowAmount(double value, Locale locale) {
  final absVal = value.abs();
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  if (!LocalizedNumberFormat.usesChineseUnits(locale)) {
    return '$sign${LocalizedNumberFormat.compact(absVal, locale)}';
  }
  final inBillion = absVal / 100000000;
  if (inBillion >= 100) {
    return '$sign${inBillion.toStringAsFixed(0)} 億';
  } else if (inBillion >= 10) {
    return '$sign${inBillion.toStringAsFixed(1)} 億';
  } else if (inBillion >= 1) {
    return '$sign${inBillion.toStringAsFixed(2)} 億';
  }
  final inTenMillion = absVal / 10000000;
  if (inTenMillion >= 1) {
    return '$sign${inTenMillion.toStringAsFixed(1)} 千萬';
  }
  final inMillion = absVal / 1000000;
  return '$sign${inMillion.toStringAsFixed(0)} 百萬';
}

/// 法人動向卡片
///
/// 以三張小卡呈現外資/投信/自營淨買賣，帶左邊框裝飾條 + 合計行
class InstitutionalFlowChart extends StatelessWidget {
  const InstitutionalFlowChart({
    super.key,
    required this.data,
    this.streak,
    this.totalNetHistory,
  });

  final InstitutionalTotals data;
  final InstitutionalStreak? streak;

  /// 30日法人合計淨額歷史（供趨勢 bar chart，oldest→newest）
  final List<double>? totalNetHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.totalNet == 0 &&
        data.foreignNet == 0 &&
        data.trustNet == 0 &&
        data.dealerNet == 0) {
      return const SizedBox.shrink();
    }

    final items = [
      _FlowItem(
        'marketOverview.foreign'.tr(),
        data.foreignNet,
        CategoryColors.neutral,
        streak: streak?.foreignStreak,
      ),
      _FlowItem(
        'marketOverview.trust'.tr(),
        data.trustNet,
        CategoryColors.neutral,
        streak: streak?.trustStreak,
      ),
      _FlowItem(
        'marketOverview.dealer'.tr(),
        data.dealerNet,
        CategoryColors.neutral,
        streak: streak?.dealerStreak,
        // 自營淨額由造市庫存 + 權證避險 delta 主導，連續買超近乎結構性恆正，
        // 非看多訊號，標註提示降低誤讀。
        isDealer: true,
      ),
    ];

    // 找出最大絕對值，用於計算比例條寬度
    final maxAbs = items
        .map((e) => e.value.abs())
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題列右側掛「買賣超排行」入口(2026-08-05 法人排行頁)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'marketOverview.institutional'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            InkWell(
              onTap: () => context.push(AppRoutes.institutionalRanking),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing4,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'instRanking.entry'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacing10),

        // 三張法人卡片
        ...items.map(
          (item) => Padding(
            padding: EdgeInsets.only(
              bottom: item != items.last ? DesignTokens.spacing6 : 0,
            ),
            child: _FlowCard(item: item, maxAbs: maxAbs),
          ),
        ),

        // 合計
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            color: theme.colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'marketOverview.totalNet'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatFlowAmount(
                      data.totalNet,
                      Localizations.localeOf(context),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.getPriceColor(
                        data.totalNet,
                        theme.brightness,
                      ),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              // 30日趨勢 bar chart
              if (totalNetHistory != null && totalNetHistory!.length >= 2) ...[
                const SizedBox(height: 8),
                MiniBarChart(dataPoints: totalNetHistory!, height: 36),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FlowItem {
  const _FlowItem(
    this.label,
    this.value,
    this.color, {
    this.streak,
    this.isDealer = false,
  });
  final String label;
  final double value;
  final Color color;
  final int? streak;

  /// 是否為自營商（含避險部位，方向參考性低，需標註提示）
  final bool isDealer;
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.item, required this.maxAbs});

  final _FlowItem item;
  final double maxAbs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = item.value >= 0;
    final valueColor = AppTheme.getPriceColor(item.value, theme.brightness);

    // 比例條寬度（0.0 ~ 1.0）
    final ratio = maxAbs > 0 ? item.value.abs() / maxAbs : 0.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 左邊框色條
            Container(width: 3, color: item.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名稱 + 金額
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.label,
                              // 文字不得直接套用 item.color（現為
                              // CategoryColors.neutral，對淺色主題卡片底僅
                              // 2.43:1，一般文字未達 AA 4.5:1）——item.color
                              // 統一為單一中性灰後，僅保留給左側邊框條這類
                              // 裝飾用途，文字改用主題自帶、已對兩主題卡片
                              // 底校準過對比度的 onSurfaceVariant。
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // 自營商：含避險部位提示（ⓘ tooltip），降低連續買超誤讀
                            if (item.isDealer) ...[
                              const SizedBox(width: 3),
                              Tooltip(
                                message: 'marketOverview.dealerHedgeNote'.tr(),
                                triggerMode: TooltipTriggerMode.tap,
                                child: Icon(
                                  Icons.info_outline,
                                  size: DesignTokens.fontSizeXs,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (item.streak != null &&
                                item.streak!.abs() >= 2) ...[
                              const SizedBox(width: 6),
                              _StreakBadge(streak: item.streak!),
                            ],
                          ],
                        ),
                        Text(
                          formatFlowAmount(
                            item.value,
                            Localizations.localeOf(context),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: valueColor,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 比例條（center-anchored — 正值從中央向右、負值從中央向左）
                    //
                    // 早期版本是 edge-anchored（正→左邊起，負→右邊起），會讓
                    // 兩張卡並列時方向感反向，不利於跨市場交叉比較（例如
                    // TWSE 外資 +434 億 vs TPEx 外資 -115 億）。改成中央為 0、
                    // 兩側等量放，視覺上立刻看出正負與相對量級。
                    //
                    // 色彩語意：條的填色沿用上方金額數字已用的 valueColor
                    // （買超右/紅、賣超左/綠，台股慣例）而非 item.color
                    // ——買賣方向是明確的漲跌判斷，理應走 red/green。
                    // item.color（CategoryColors.neutral）現僅剩左側邊框條
                    // 一處裝飾用途，三個法人類別統一同色，不再承擔身份區分；
                    // 「哪個法人」改由文字內容本身（label 字樣）辨識。
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 4,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final halfWidth = constraints.maxWidth / 2;
                            final barWidth = halfWidth * ratio;
                            return Stack(
                              children: [
                                Container(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.15),
                                ),
                                // 中央 0 軸 tick（1px），低調但提供視覺錨點
                                Positioned(
                                  left: halfWidth - 0.5,
                                  top: 0,
                                  bottom: 0,
                                  width: 1,
                                  child: Container(
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                if (barWidth > 0)
                                  Positioned(
                                    left: isPositive
                                        ? halfWidth
                                        : halfWidth - barWidth,
                                    width: barWidth,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(color: valueColor),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBuy = streak > 0;
    final color = isBuy ? AppTheme.upColor : AppTheme.downColor;
    // streak 觸頂（達取數窗口上限）時顯示「90+」，否則顯示真實天數
    final countDisplay = streak.abs() >= InstitutionalParams.kStreakLookbackDays
        ? '${InstitutionalParams.kStreakLookbackDays}+'
        : '${streak.abs()}';
    final text = isBuy
        ? 'marketOverview.consecutiveBuy'.tr(namedArgs: {'count': countDisplay})
        : 'marketOverview.consecutiveSell'.tr(
            namedArgs: {'count': countDisplay},
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        color: color.withValues(alpha: 0.1),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: PriceColors.onTintOf(color, Theme.of(context).brightness),
          fontWeight: FontWeight.w600,
          fontSize: DesignTokens.fontSizeXs,
        ),
      ),
    );
  }
}

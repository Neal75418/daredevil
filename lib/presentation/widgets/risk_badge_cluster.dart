import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/risk_warnings.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/presentation/widgets/reason_tags.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 風險警示聚合徽章（option B）
///
/// 把一檔股票觸發的 **neutral 警訊類**訊號（[RiskWarnings.all]）聚合成右上角一顆
/// `⚠ N` pill、依最高嚴重度上色。階段重設計把警訊全丟 neutral 後、主畫面失去
/// 「這檔有紅旗」的可見性 — 本徽章把它補回來，**不影響 routing / score / evidence
/// chip**（純顯示層）。
///
/// 設計取捨（DB 實證撐腰）：強勢觀察 67% 卡片帶 ≥1 警訊、43% 帶 ≥2、單檔最多 3 →
/// 用「一排紅 chip」會灌爆固定高 [DesignTokens.stockCardHeight] 的卡片；聚合 pill
/// 只佔一格。視覺配方沿用 [WarningBadge]（同 token / 透明度 / 圓角）。
///
/// - 空 [warnings] → 不 render（zero-noise，對齊「健康即隱藏」哲學）
/// - N == 1 → 只顯 icon；N ≥ 2 → icon + 數字
/// - tap → [showAppBottomSheet] 列出每條警訊（嚴重度色點 + i18n label）
class RiskBadgeCluster extends StatelessWidget {
  const RiskBadgeCluster({super.key, required this.warnings});

  /// 該股的 warning-class 訊號（[RiskWarnings.all] 子集）。空 = 不顯示。
  final List<ReasonType> warnings;

  /// 嚴重度 → 顏色（severe 紅、moderate 琥珀）——僅用於 tint 底、邊框、色點。
  static Color _colorFor(RiskSeverity severity, ThemeData theme) {
    return switch (severity) {
      RiskSeverity.severe => AppTheme.errorColor,
      RiskSeverity.moderate => DesignTokens.warningColor(theme),
    };
  }

  /// 疊色 pill 上的文字／圖示色。tint 是 [_colorFor] 的 15%／25% 透明版，
  /// 同色前景對合成背景僅 1.8～4.2:1，必須用疊色專屬文字色（實測 4.9～6.3:1）。
  static Color _onTintFor(RiskSeverity severity, ThemeData theme) {
    return switch (severity) {
      RiskSeverity.severe => ErrorColors.onTintFor(theme.brightness),
      RiskSeverity.moderate => WarningColors.onTintFor(theme.brightness),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = context.isDark;
    final severity =
        RiskWarnings.topSeverity(warnings) ?? RiskSeverity.moderate;
    final color = _colorFor(severity, theme);
    final count = warnings.length;

    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing6,
        vertical: DesignTokens.spacing2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: isDark ? DesignTokens.opacity25 : DesignTokens.opacity15,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.6 : 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: _onTintFor(severity, theme),
          ),
          // N == 1 省數字（已有 icon + 顏色傳達），N ≥ 2 顯總數
          if (count >= 2) ...[
            const SizedBox(width: 2),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _onTintFor(severity, theme),
                fontWeight: FontWeight.w700,
                fontSize: DesignTokens.fontSizeXs,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: 'warning.risk.semantics'.tr(args: ['$count']),
      hint: 'warning.risk.tapHint'.tr(),
      button: true,
      child: GestureDetector(onTap: () => _showDetails(context), child: pill),
    );
  }

  void _showDetails(BuildContext context) {
    // severe 排前、moderate 排後，讓使用者先看到最該注意的
    final sorted = [...warnings]
      ..sort((a, b) {
        final sa = RiskWarnings.severityOf(a) == RiskSeverity.severe ? 0 : 1;
        final sb = RiskWarnings.severityOf(b) == RiskSeverity.severe ? 0 : 1;
        return sa.compareTo(sb);
      });

    showAppBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing20,
              0,
              DesignTokens.spacing20,
              DesignTokens.spacing20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: AppTheme.errorColor,
                    ),
                    const SizedBox(width: DesignTokens.spacing8),
                    Text(
                      'warning.risk.title'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacing12),
                for (final w in sorted) _riskRow(theme, w),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _riskRow(ThemeData theme, ReasonType warning) {
    final severity = RiskWarnings.severityOf(warning) ?? RiskSeverity.moderate;
    final color = _colorFor(severity, theme);
    final severityLabel = switch (severity) {
      RiskSeverity.severe => 'warning.risk.severe'.tr(),
      RiskSeverity.moderate => 'warning.risk.moderate'.tr(),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacing6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: DesignTokens.spacing12),
          Expanded(
            child: Text(
              ReasonTags.translateReasonCode(warning.code),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            severityLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

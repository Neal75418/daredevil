import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 可重用的空狀態 Widget，附有動畫插圖
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.useFlatIconColor = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 明確指定的圖示色。留 `null` 時依 [useFlatIconColor] 解析。
  final Color? iconColor;

  /// 以主題解析的平盤灰作為圖示色（與 [iconColor] 互斥）。
  ///
  /// 平盤灰是雙值設計（深色 `#A1A1A1`／淺色 `#717171`），`EmptyStates` 的
  /// 靜態工廠沒有 `BuildContext` 無法自行解析，故以旗標下放到 build。
  final bool useFlatIconColor;

  /// 精簡版：放在頁面中段、後面還有其他區塊時用（今日頁分頁沒訊號）。
  /// 完整版約 336 高，是為整頁空白設計的，放在中段會把後面的區塊推出
  /// 第一屏；精簡版只縮圖示與間距，標題、說明、按鈕都保留。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.isDark;
    final effectiveColor =
        iconColor ??
        (useFlatIconColor ? context.flatColor : theme.colorScheme.primary);

    return Semantics(
      label:
          '$title${subtitle != null ? ', $subtitle' : ''}${actionLabel != null ? ', $actionLabel' : ''}',
      child: Center(
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing32,
                  vertical: DesignTokens.spacing16,
                )
              : const EdgeInsets.all(DesignTokens.spacing32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 帶有背景的動畫圖示
              Container(
                    width: compact ? 64 : 120,
                    height: compact ? 64 : 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          effectiveColor.withValues(alpha: isDark ? 0.25 : 0.1),
                          effectiveColor.withValues(alpha: isDark ? 0.1 : 0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: effectiveColor.withValues(
                          alpha: isDark ? 0.3 : 0.2,
                        ),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: compact ? 32 : 56,
                      color: effectiveColor.withValues(alpha: 0.7),
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.05, 1.05),
                    duration: AnimDurations.breathe,
                    curve: AnimCurves.breathe,
                  ),
              SizedBox(
                height: compact
                    ? DesignTokens.spacing12
                    : DesignTokens.spacing24,
              ),
              // 標題
              Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  )
                  .animate()
                  .fadeIn(
                    delay: AnimDurations.standard,
                    duration: AnimDurations.moderate,
                  )
                  .slideY(begin: 0.2, duration: AnimDurations.moderate),
              if (subtitle != null) ...[
                const SizedBox(height: DesignTokens.spacing8),
                Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    )
                    .animate()
                    .fadeIn(
                      delay: AnimDurations.normal,
                      duration: AnimDurations.moderate,
                    )
                    .slideY(begin: 0.2, duration: AnimDurations.moderate),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(
                  height: compact
                      ? DesignTokens.spacing12
                      : DesignTokens.spacing24,
                ),
                FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    )
                    .animate()
                    .fadeIn(
                      delay: AnimDurations.moderate,
                      duration: AnimDurations.moderate,
                    )
                    .slideY(begin: 0.2, duration: AnimDurations.moderate),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 常見情境的預設空狀態
///
/// 使用 [S] (AppStrings) 進行集中字串管理，
/// 支援未來的多語系功能
class EmptyStates {
  EmptyStates._();

  /// 今日無推薦
  static Widget noRecommendations({
    VoidCallback? onRefresh,
    bool compact = false,
  }) {
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: S.emptyNoRecommendations,
      subtitle: S.emptyNoRecommendationsHint,
      actionLabel: onRefresh != null ? S.refresh : null,
      onAction: onRefresh,
      compact: compact,
    );
  }

  /// 完全沒有資料（全新安裝）：與「今天沒有訊號」是不同的狀態，不可共用文案
  static Widget firstBuild({required bool isUpdating, VoidCallback? onStart}) {
    // 更新中不給按鈕；label 也要一起拿掉——它會進語意朗讀，留著會讓
    // 螢幕閱讀器念出一顆畫面上不存在的按鈕
    final onAction = isUpdating ? null : onStart;
    return EmptyState(
      icon: isUpdating
          ? Icons.downloading_outlined
          : Icons.cloud_download_outlined,
      title: isUpdating
          ? 'empty.firstBuildRunningTitle'.tr()
          : 'empty.firstBuildIdleTitle'.tr(),
      subtitle: 'empty.firstBuildHint'.tr(),
      actionLabel: onAction == null ? null : 'empty.firstBuildStart'.tr(),
      onAction: onAction,
    );
  }

  /// 無符合篩選條件的股票
  static Widget noFilterResults({VoidCallback? onClearFilter}) {
    return EmptyState(
      icon: Icons.search_off_outlined,
      title: S.emptyNoFilterResults,
      subtitle: S.emptyNoFilterResultsHint,
      actionLabel: onClearFilter != null ? S.emptyClearFilter : null,
      onAction: onClearFilter,
      useFlatIconColor: true,
    );
  }

  /// 無符合篩選條件的股票 - 附有詳細元資料
  static Widget noFilterResultsWithMeta({
    required String filterName,
    required String conditionDescription,
    required List<String> dataRequirements,
    String? thresholdInfo,
    int? totalScanned,
    DateTime? dataDate,
    VoidCallback? onClearFilter,
  }) {
    return _EmptyStateWithMeta(
      filterName: filterName,
      conditionDescription: conditionDescription,
      dataRequirements: dataRequirements,
      thresholdInfo: thresholdInfo,
      totalScanned: totalScanned,
      dataDate: dataDate,
      onClearFilter: onClearFilter,
    );
  }

  /// 空的自選清單
  static Widget emptyWatchlist({VoidCallback? onAdd}) {
    return EmptyState(
      icon: Icons.star_outline_rounded,
      title: S.emptyNoWatchlist,
      subtitle: S.emptyNoWatchlistHint,
      actionLabel: onAdd != null ? S.emptyAddWatchlist : null,
      onAction: onAdd,
      iconColor: Colors.amber,
    );
  }

  /// 無新聞
  static Widget noNews({VoidCallback? onRefresh}) {
    return EmptyState(
      icon: Icons.article_outlined,
      title: S.emptyNoNews,
      subtitle: S.emptyNoNewsHint,
      actionLabel: onRefresh != null ? S.refresh : null,
      onAction: onRefresh,
    );
  }

  /// 錯誤狀態
  static Widget error({
    required String message,
    VoidCallback? onRetry,
    bool compact = false,
  }) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: S.emptyError,
      subtitle: message,
      actionLabel: onRetry != null ? S.retry : null,
      onAction: onRetry,
      iconColor: AppTheme.errorColor,
      compact: compact,
    );
  }

  /// 網路錯誤
  static Widget networkError({VoidCallback? onRetry, bool compact = false}) {
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: S.emptyNetworkError,
      subtitle: S.emptyNetworkErrorHint,
      actionLabel: onRetry != null ? S.retry : null,
      onAction: onRetry,
      iconColor: AppTheme.errorColor,
      compact: compact,
    );
  }
}

/// 附有篩選條件元資料的空狀態 Widget
///
/// 核心資訊（條件 + 閾值）預設顯示，
/// 「診斷資訊」和「資料需求」折疊在「更多詳情」中，降低新用戶資訊密度。
class _EmptyStateWithMeta extends StatefulWidget {
  const _EmptyStateWithMeta({
    required this.filterName,
    required this.conditionDescription,
    required this.dataRequirements,
    this.thresholdInfo,
    this.totalScanned,
    this.dataDate,
    this.onClearFilter,
  });

  final String filterName;
  final String conditionDescription;
  final List<String> dataRequirements;
  final String? thresholdInfo;
  final int? totalScanned;
  final DateTime? dataDate;
  final VoidCallback? onClearFilter;

  @override
  State<_EmptyStateWithMeta> createState() => _EmptyStateWithMetaState();
}

class _EmptyStateWithMetaState extends State<_EmptyStateWithMeta> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.isDark;
    final flatColor = context.flatColor;
    final hasDetails =
        widget.totalScanned != null ||
        widget.dataDate != null ||
        widget.dataRequirements.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spacing24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 圖示
            Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        flatColor.withValues(alpha: isDark ? 0.15 : 0.1),
                        flatColor.withValues(alpha: isDark ? 0.05 : 0.03),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: flatColor.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.filter_alt_off_outlined,
                    size: 48,
                    color: flatColor.withValues(alpha: 0.7),
                  ),
                )
                .animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                )
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.03, 1.03),
                  duration: AnimDurations.breathe,
                  curve: AnimCurves.breathe,
                ),

            const SizedBox(height: DesignTokens.spacing20),

            // 帶有篩選名稱的標題
            Text(
              'filterMeta.titleWithFilter'.tr(
                namedArgs: {'filter': widget.filterName},
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(
              delay: AnimDurations.press,
              duration: AnimDurations.normal,
            ),

            const SizedBox(height: DesignTokens.spacing16),

            // 條件說明卡片（核心：條件 + 閾值）
            Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignTokens.spacing16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 條件區塊
                      Row(
                        children: [
                          Icon(
                            Icons.rule_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: DesignTokens.spacing8),
                          Text(
                            'filterMeta.labelCondition'.tr(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spacing8),
                      Text(
                        widget.conditionDescription,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),

                      // 閾值資訊（若有）
                      if (widget.thresholdInfo != null) ...[
                        const SizedBox(height: DesignTokens.spacing8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacing10,
                            vertical: DesignTokens.spacing6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusSm,
                            ),
                          ),
                          child: Text(
                            widget.thresholdInfo!.tr(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
                .animate()
                .fadeIn(
                  delay: AnimDurations.standard,
                  duration: AnimDurations.normal,
                )
                .slideY(begin: 0.1, duration: AnimDurations.normal),

            // 更多詳情展開按鈕
            if (hasDetails) ...[
              const SizedBox(height: DesignTokens.spacing8),
              TextButton.icon(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                icon: AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: AnimDurations.standard,
                  child: const Icon(Icons.expand_more, size: 20),
                ),
                label: Text(
                  'filterMeta.moreDetails'.tr(),
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],

            // 折疊內容：診斷資訊 + 資料需求
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _buildExpandedDetails(theme),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: AnimDurations.normal,
            ),

            const SizedBox(height: DesignTokens.spacing8),

            // 提示文字
            Text(
              'filterMeta.hintEmpty'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(
              delay: AnimDurations.normal,
              duration: AnimDurations.normal,
            ),

            // 清除篩選按鈕
            if (widget.onClearFilter != null) ...[
              const SizedBox(height: DesignTokens.spacing20),
              FilledButton.tonal(
                    onPressed: widget.onClearFilter,
                    child: Text('filterMeta.labelClear'.tr()),
                  )
                  .animate()
                  .fadeIn(
                    delay: AnimDurations.moderate,
                    duration: AnimDurations.normal,
                  )
                  .slideY(begin: 0.1, duration: AnimDurations.normal),
            ],
          ],
        ),
      ),
    );
  }

  /// 展開後的詳情內容：診斷資訊 + 資料需求
  Widget _buildExpandedDetails(ThemeData theme) {
    return Column(
      children: [
        // 診斷資訊（掃描數量與日期）
        if (widget.totalScanned != null || widget.dataDate != null)
          Container(
            margin: const EdgeInsets.only(bottom: DesignTokens.spacing12),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing16,
              vertical: DesignTokens.spacing8,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXxl),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.dataDate != null) ...[
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: DesignTokens.spacing4),
                  Text(
                    'filterMeta.labelDate'.tr(
                      namedArgs: {
                        'date': DateFormat('MM/dd').format(widget.dataDate!),
                      },
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.totalScanned != null) ...[
                    const SizedBox(width: DesignTokens.spacing8),
                    Container(
                      width: 1,
                      height: DesignTokens.spacing12,
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: DesignTokens.spacing8),
                  ],
                ],
                if (widget.totalScanned != null) ...[
                  Icon(
                    Icons.analytics_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: DesignTokens.spacing4),
                  Text(
                    'filterMeta.labelScanned'.tr(
                      namedArgs: {
                        'count': NumberFormat.decimalPattern().format(
                          widget.totalScanned,
                        ),
                      },
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),

        // 資料需求區塊
        if (widget.dataRequirements.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DesignTokens.spacing12),
            margin: const EdgeInsets.only(bottom: DesignTokens.spacing8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.storage_outlined,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: DesignTokens.spacing8),
                    Text(
                      'filterMeta.labelData'.tr(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacing8),
                Wrap(
                  spacing: DesignTokens.spacing6,
                  runSpacing: DesignTokens.spacing6,
                  children: widget.dataRequirements.map((req) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacing10,
                        vertical: DesignTokens.spacing4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusXl,
                        ),
                      ),
                      child: Text(
                        req,
                        style: theme.textTheme.labelSmall?.copyWith(
                          // 底色是 secondaryContainer 疊 60% alpha，非實心，
                          // 淺色主題疊白後 onSecondaryContainer（白字）僅
                          // 3.09:1，不合格；改用 onSurface 達 5.52:1。深色
                          // 主題未受影響（onSecondaryContainer 沒變過），
                          // 維持原樣。
                          color: theme.brightness == Brightness.dark
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

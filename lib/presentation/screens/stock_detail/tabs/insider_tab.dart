import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/widgets/metric_card.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

// ==================================================
// UI 常數
// ==================================================

/// 表格顯示的最大月數
const _kMaxDisplayMonths = 12;

/// 判定持股變化為「顯著」的門檻（百分點）
const _kSignificantChangeThreshold = 1.0;

/// 顏色常數
///
/// 兩者為 MetricCard 的 accentColor（圖示＋裝飾邊框），非分類標記，
/// 故取自 chartPalette 而非 CategoryColors.neutral，避免兩張卡片
/// 視覺上完全無法區分。
///
/// 非頂層常數：chartPalette 依主題明暗解析，MetricCard 的圖示底色實際落在
/// `theme.colorScheme.surfaceContainerLow`（淺色主題 `#F8F9FA`），只取
/// 深色主題那組色盤在淺色主題下對比不足，故改為需要 [Brightness] 的函式，
/// 由呼叫端（有 BuildContext 之處）傳入 `Theme.of(context).brightness`。
Color _kInsiderRatioColor(Brightness brightness) =>
    CategoryColors.chartPaletteFor(brightness)[0]; // 藍 500／600

Color _kPledgeRatioColor(Brightness brightness) =>
    CategoryColors.chartPaletteFor(brightness)[2]; // 紫 500／600

/// 董監持股分頁 - 持股比例、質押比例、持股變化
class InsiderTab extends ConsumerStatefulWidget {
  const InsiderTab({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<InsiderTab> createState() => _InsiderTabState();
}

class _InsiderTabState extends ConsumerState<InsiderTab> {
  @override
  void initState() {
    super.initState();
    // Tab 初始化時載入內部人資料
    Future.microtask(() {
      ref.read(stockDetailProvider(widget.symbol).notifier).loadInsiderData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final insiderHistory = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.chip.insiderHistory),
    );
    final insiderTransfers = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.chip.insiderTransfers),
    );
    final isLoadingInsider = ref.watch(
      stockDetailProvider(
        widget.symbol,
      ).select((s) => s.loading.isLoadingInsider),
    );
    final insiderError = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.insiderError),
    );

    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (insiderError != null && !isLoadingInsider)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      insiderError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(stockDetailProvider(widget.symbol).notifier)
                        .loadInsiderData(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text('common.retry'.tr()),
                  ),
                ],
              ),
            ),

          // 關鍵指標卡片
          _buildMetricsRow(context, insiderHistory),
          const SizedBox(height: DesignTokens.spacing24),

          // 近期轉讓申報區段
          if (isLoadingInsider) ...[
            SectionHeader(
              title: 'stockDetail.insiderTransfer'.tr(),
              icon: Icons.swap_horiz,
            ),
            const SizedBox(height: DesignTokens.spacing12),
            _buildLoadingState(context),
            const SizedBox(height: DesignTokens.spacing24),
          ] else if (insiderTransfers.isNotEmpty) ...[
            SectionHeader(
              title: 'stockDetail.insiderTransfer'.tr(),
              icon: Icons.swap_horiz,
            ),
            const SizedBox(height: DesignTokens.spacing12),
            _buildTransferSection(context, insiderTransfers),
            const SizedBox(height: DesignTokens.spacing24),
          ],

          // 內部人持股歷史區段
          SectionHeader(
            title: 'stockDetail.insiderHistory'.tr(),
            icon: Icons.history,
          ),
          const SizedBox(height: DesignTokens.spacing12),

          if (isLoadingInsider)
            _buildLoadingState(context)
          else if (insiderHistory.isEmpty && insiderError == null)
            _buildEmptyState(context, 'stockDetail.insiderComingSoon'.tr())
          else
            _buildInsiderTable(context, insiderHistory),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacing24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildMetricsRow(
    BuildContext context,
    List<InsiderHoldingEntry> insiderHistory,
  ) {
    final latest = insiderHistory.isNotEmpty ? insiderHistory.first : null;
    final previous = insiderHistory.length >= 2 ? insiderHistory[1] : null;

    // 計算變動
    double? change;
    if (latest?.insiderRatio != null && previous?.insiderRatio != null) {
      change = latest!.insiderRatio! - previous!.insiderRatio!;
    }

    // 判斷質押比是否為高風險
    final pledgeRatio = latest?.pledgeRatio ?? 0;
    final isHighPledge =
        pledgeRatio >= FundamentalParams.highPledgeRatioThreshold;
    final brightness = Theme.of(context).brightness;

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: 'stockDetail.insiderRatio'.tr(),
            value: latest?.insiderRatio != null
                ? '${latest!.insiderRatio!.toStringAsFixed(1)}%'
                : '-',
            icon: Icons.people_alt,
            accentColor: _kInsiderRatioColor(brightness),
            subtitle: 'stockDetail.insiderRatioLabel'.tr(),
          ),
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Expanded(
          child: MetricCard(
            label: 'stockDetail.pledgeRatio'.tr(),
            value: latest?.pledgeRatio != null
                ? '${latest!.pledgeRatio!.toStringAsFixed(1)}%'
                : '-',
            icon: Icons.account_balance,
            accentColor: isHighPledge
                ? AppTheme.errorColor
                : _kPledgeRatioColor(brightness),
            subtitle: 'stockDetail.pledgeRatioLabel'.tr(),
            isWarning: isHighPledge,
          ),
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Expanded(
          child: MetricCard(
            label: 'stockDetail.insiderChange'.tr(),
            value: change != null
                ? '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}%'
                : '-',
            icon: _getChangeIcon(change),
            accentColor: _getChangeColor(context, change),
            subtitle: 'stockDetail.insiderChangeLabel'.tr(),
          ),
        ),
      ],
    );
  }

  /// 根據變化值取得對應的圖示
  ///
  /// - 正數: 向上趨勢
  /// - 負數: 向下趨勢
  /// - 零或 null: 持平/無資料
  IconData _getChangeIcon(double? change) {
    if (change == null || change == 0) return Icons.trending_flat;
    return change > 0 ? Icons.trending_up : Icons.trending_down;
  }

  /// 根據變化值取得對應的顏色
  ///
  /// - 正數: upColor（增持為正面訊號）
  /// - 負數: downColor（減持為負面訊號）
  /// - 零或 null: 灰色（無變化）
  Color _getChangeColor(BuildContext context, double? change) {
    // 走 canonical getPriceColor：淺色主題才拿得到較深的下跌綠與平盤灰
    // （2026-07-23 稽核修復：原手刻 sign→raw 色，與 PriceColors.forChange
    // 分岔——平盤 Colors.grey、負值淺色誤用深色版 downColor）
    return AppTheme.getPriceColor(change ?? 0, Theme.of(context).brightness);
  }

  Widget _buildInsiderTable(
    BuildContext context,
    List<InsiderHoldingEntry> holdings,
  ) {
    final theme = Theme.of(context);

    // 取最近 N 筆（已依日期降冪排序）
    final displayData = holdings.take(_kMaxDisplayMonths).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing12),
        child: Column(
          children: [
            // 含樣式背景的標題列
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
                    flex: 3,
                    child: Text(
                      'stockDetail.insiderDate'.tr(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'stockDetail.insiderRatioShort'.tr(),
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
                      'stockDetail.pledgeRatioShort'.tr(),
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
                      'stockDetail.insiderChangeShort'.tr(),
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
            // 資料列
            ...displayData.asMap().entries.map((entry) {
              final index = entry.key;
              final holding = entry.value;

              // 計算與前一筆的變動
              double? change;
              if (index < displayData.length - 1) {
                final prev = displayData[index + 1];
                if (holding.insiderRatio != null && prev.insiderRatio != null) {
                  change = holding.insiderRatio! - prev.insiderRatio!;
                }
              }

              final isHighPledge =
                  (holding.pledgeRatio ?? 0) >=
                  FundamentalParams.highPledgeRatioThreshold;

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
                      flex: 3,
                      child: Text(
                        _formatDate(holding.date),
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
                        holding.insiderRatio != null
                            ? '${holding.insiderRatio!.toStringAsFixed(1)}%'
                            : '-',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        holding.pledgeRatio != null
                            ? '${holding.pledgeRatio!.toStringAsFixed(1)}%'
                            : '-',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isHighPledge ? AppTheme.errorColor : null,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _buildChangeBadge(context, change),
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

  Widget _buildChangeBadge(BuildContext context, double? change) {
    final theme = Theme.of(context);

    if (change == null) {
      return Text(
        '-',
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }

    // 使用與 _getChangeColor 一致的邏輯：0 為中性
    final color = _getChangeColor(context, change);
    final prefix = change > 0 ? '+' : '';
    final isSignificant = change.abs() >= _kSignificantChangeThreshold;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing6,
          vertical: DesignTokens.spacing2,
        ),
        decoration: BoxDecoration(
          color: isSignificant
              ? color.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
        ),
        child: Text(
          '$prefix${change.toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: isSignificant ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildTransferSection(
    BuildContext context,
    List<InsiderTransferEntry> transfers,
  ) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing12),
        child: Column(
          children: transfers.map((t) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacing6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 身分 badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.downColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusXs,
                      ),
                    ),
                    child: Text(
                      t.identity,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.downColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing8),
                  // 詳情
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t.name} - ${t.transferMethod}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacing2),
                        Text(
                          'stockDetail.transferSharesLabel'.tr(
                            args: [
                              LocalizedNumberFormat.compact(
                                t.transferShares.toDouble(),
                                Localizations.localeOf(context),
                              ),
                            ],
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.downColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (t.validPeriodStart != null &&
                            t.validPeriodEnd != null) ...[
                          const SizedBox(height: DesignTokens.spacing2),
                          Text(
                            '${'stockDetail.validPeriod'.tr()}: '
                            '${_formatFullDate(t.validPeriodStart!)} ~ '
                            '${_formatFullDate(t.validPeriodEnd!)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 申報日期
                  Text(
                    _formatFullDate(t.reportDate),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacing24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Center(
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

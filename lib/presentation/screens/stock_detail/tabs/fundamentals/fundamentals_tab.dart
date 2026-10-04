import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/eps_table.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_helpers.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/profitability_card.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/revenue_table.dart';
import 'package:daredevil/presentation/widgets/metric_card.dart';

/// 關鍵指標卡片的 accentColor（圖示＋裝飾邊框）。
///
/// 既有缺陷（非本次色彩語意重構引入，Task 9 修復）：三者原為與色盤無關的
/// 字面值色（本益比 `#3498DB`、股價淨值比 `#9B59B6`、殖利率沿用
/// `AppTheme.dividendColor` `#A78BFA`），對 MetricCard 圖示（圖形物件，
/// 門檻 3.0:1）對比不足：本益比、殖利率對淺色主題 `surfaceContainerLow`
/// （`#F8F9FA`）純色背景分別僅 2.9912:1／2.5817:1，疊色後（`accentColor`
/// 10% alpha 疊 `surfaceContainerLow`）收窄至 2.7080:1／2.3730:1；股價淨值
/// 比則是深色主題疊色後對 `surfaceContainerLow`（`#27272A`）僅 2.8907:1
/// （`ColorContrast` 精算）。改用 [CategoryColors.chartPaletteFor] 取色，
/// 與 insider_tab.dart 的既有做法一致，三者分屬三色相（藍／橘／紫）避免
/// 同列相鄰卡片撞色。
///
/// 非頂層常數：chartPalette 依主題明暗解析，理由同 insider_tab.dart——
/// MetricCard 圖示底色實際落在 `theme.colorScheme.surfaceContainerLow`，
/// 只取單一主題那組色盤在另一主題下對比不保證足夠。
Color _kPerColor(Brightness brightness) =>
    CategoryColors.chartPaletteFor(brightness)[0]; // 藍 500／600

Color _kPbrColor(Brightness brightness) =>
    CategoryColors.chartPaletteFor(brightness)[1]; // 橘 500／600

Color _kYieldColor(Brightness brightness) =>
    CategoryColors.chartPaletteFor(brightness)[2]; // 紫 500／600

/// 基本面分頁 - 本益比、股價淨值比、營收、股利
class FundamentalsTab extends ConsumerStatefulWidget {
  const FundamentalsTab({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<FundamentalsTab> createState() => _FundamentalsTabState();
}

class _FundamentalsTabState extends ConsumerState<FundamentalsTab> {
  @override
  void initState() {
    super.initState();
    // Tab 初始化時載入基本面資料
    Future.microtask(() {
      ref.read(stockDetailProvider(widget.symbol).notifier).loadFundamentals();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fundamentals = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.fundamentals),
    );
    final isLoadingFundamentals = ref.watch(
      stockDetailProvider(
        widget.symbol,
      ).select((s) => s.loading.isLoadingFundamentals),
    );
    final fundamentalsError = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.fundamentalsError),
    );
    final showROCYear = ref.watch(
      settingsProvider.select((s) => s.showROCYear),
    );

    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 載入失敗提示
          if (fundamentalsError != null && !isLoadingFundamentals)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fundamentalsError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(stockDetailProvider(widget.symbol).notifier)
                        .loadFundamentals(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text('common.retry'.tr()),
                  ),
                ],
              ),
            ),

          // 關鍵指標卡片
          _buildMetricsRow(context, fundamentals),
          const SizedBox(height: DesignTokens.spacing24),

          // 月營收區段
          SectionHeader(
            title: 'stockDetail.monthlyRevenue'.tr(),
            icon: Icons.trending_up,
          ),
          const SizedBox(height: DesignTokens.spacing12),

          if (isLoadingFundamentals)
            buildLoadingState(context)
          else if (fundamentals.revenueHistory.isEmpty &&
              fundamentalsError == null)
            buildEmptyState(context, 'stockDetail.revenueComingSoon'.tr())
          else
            RevenueTable(
              revenues: fundamentals.revenueHistory,
              showROCYear: showROCYear,
            ),

          const SizedBox(height: DesignTokens.spacing24),

          // EPS 歷史區段
          SectionHeader(
            title: 'stockDetail.epsHistory'.tr(),
            icon: Icons.bar_chart,
          ),
          const SizedBox(height: DesignTokens.spacing12),

          if (isLoadingFundamentals)
            buildLoadingState(context)
          else if (fundamentals.epsHistory.isEmpty && fundamentalsError == null)
            buildEmptyState(context, 'stockDetail.epsComingSoon'.tr())
          else
            EpsTable(
              epsHistory: fundamentals.epsHistory,
              showROCYear: showROCYear,
            ),

          // 獲利能力卡片
          if (fundamentals.latestQuarterMetrics.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spacing16),
            ProfitabilityCard(metrics: fundamentals.latestQuarterMetrics),
          ],

          const SizedBox(height: DesignTokens.spacing24),

          // 股利區段
          SectionHeader(
            title: 'stockDetail.dividendHistory'.tr(),
            icon: Icons.payments,
          ),
          const SizedBox(height: DesignTokens.spacing12),

          if (isLoadingFundamentals)
            buildLoadingState(context)
          else if (fundamentals.dividendSummary case final summary?)
            summary.allBuilding
                ? buildEmptyState(context, 'stockDetail.dividendBuilding'.tr())
                : DividendSummaryTable(
                    summary: summary,
                    showROCYear: showROCYear,
                  )
          else if (fundamentalsError != null)
            buildEmptyState(context, 'stockDetail.dividendUnavailable'.tr()),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(
    BuildContext context,
    FundamentalsState fundamentals,
  ) {
    final per = fundamentals.latestPER;
    final brightness = Theme.of(context).brightness;

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: 'P/E',
            value: per != null && per.per > 0
                ? per.per.toStringAsFixed(1)
                : '-',
            icon: Icons.analytics,
            accentColor: _kPerColor(brightness),
            subtitle: 'stockDetail.perLabel'.tr(),
          ),
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Expanded(
          child: MetricCard(
            label: 'P/B',
            value: per != null && per.pbr > 0
                ? per.pbr.toStringAsFixed(2)
                : '-',
            icon: Icons.account_balance,
            accentColor: _kPbrColor(brightness),
            subtitle: 'stockDetail.pbrLabel'.tr(),
          ),
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Expanded(child: _buildYieldCard(fundamentals, brightness)),
      ],
    );
  }

  /// 殖利率卡：一般股票用官方估值；ETF 沒有官方估值，改顯示近一年殖利率
  Widget _buildYieldCard(
    FundamentalsState fundamentals,
    Brightness brightness,
  ) {
    if (!StockPatterns.isEtfCode(widget.symbol)) {
      final per = fundamentals.latestPER;
      return MetricCard(
        label: 'stockDetail.yield'.tr(),
        value: per != null && per.dividendYield > 0
            ? '${per.dividendYield.toStringAsFixed(2)}%'
            : '-',
        icon: Icons.percent,
        accentColor: _kYieldColor(brightness),
        subtitle: 'stockDetail.yieldLabel'.tr(),
      );
    }
    return MetricCard(
      label: 'stockDetail.yield'.tr(),
      value: switch (fundamentals.dividendSummary?.trailingYield) {
        TrailingYieldValue(:final ratio) =>
          '${(ratio * 100).toStringAsFixed(2)}%',
        TrailingYieldNone() => 'stockDetail.trailingYieldNone'.tr(),
        TrailingYieldBuilding() => 'stockDetail.dividendStatusBuilding'.tr(),
        null => '-',
      },
      icon: Icons.percent,
      accentColor: _kYieldColor(brightness),
      subtitle: 'stockDetail.trailingYieldLabel'.tr(),
    );
  }
}

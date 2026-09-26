import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/allocation_pie_chart.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/dividend_analysis_card.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/industry_allocation_card.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/performance_card.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/portfolio_summary_card.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/position_card.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/add_transaction_sheet.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 投資組合 Tab（嵌入 Watchlist 頁面）
class PortfolioTab extends ConsumerStatefulWidget {
  const PortfolioTab({super.key});

  @override
  ConsumerState<PortfolioTab> createState() => _PortfolioTabState();
}

class _PortfolioTabState extends ConsumerState<PortfolioTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(portfolioProvider.notifier).loadPositions(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(portfolioProvider);
    final theme = Theme.of(context);

    if (state.isLoading && state.positions.isEmpty) {
      return const GenericListShimmer(itemCount: 4);
    }

    if (state.error != null && state.positions.isEmpty) {
      void onRetry() => ref.read(portfolioProvider.notifier).loadPositions();
      return ErrorDisplay.isNetworkError(state.error!)
          ? EmptyStates.networkError(onRetry: onRetry)
          : EmptyStates.error(message: state.error!, onRetry: onRetry);
    }

    if (state.positions.isEmpty) {
      return _buildEmpty(theme);
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => ref.read(portfolioProvider.notifier).loadPositions(),
          child: CustomScrollView(
            slivers: [
              // Refresh 失敗時顯示 MaterialBanner
              if (state.error != null)
                SliverToBoxAdapter(
                  child: MaterialBanner(
                    content: Text(state.error!),
                    leading: Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => ref
                            .read(portfolioProvider.notifier)
                            .loadPositions(),
                        child: Text('common.retry'.tr()),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(portfolioProvider.notifier).clearError(),
                        child: Text('common.dismiss'.tr()),
                      ),
                    ],
                  ),
                ),

              // 頂部間距
              const SliverPadding(padding: EdgeInsets.only(top: 16)),

              // 總覽卡片
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: PortfolioSummaryCard(summary: state.summary),
                ),
              ),

              // 績效指標卡片
              if (state.performance != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: PerformanceCard(performance: state.performance!),
                  ),
                ),

              // 配置圓餅圖
              if (state.allocationMap.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Semantics(
                      label: S.accessibilityAllocationPieChart(
                        state.allocationMap.length,
                      ),
                      image: true,
                      child: AllocationPieChart(
                        allocationMap: state.allocationMap,
                      ),
                    ),
                  ),
                ),

              // 產業配置
              if (state.performance != null &&
                  state.performance!.industryAllocation.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: IndustryAllocationCard(
                      allocation: state.performance!.industryAllocation,
                    ),
                  ),
                ),

              // 股利分析
              if (state.dividendAnalysis != null &&
                  state.dividendAnalysis!.stockDividends.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  sliver: SliverToBoxAdapter(
                    child: DividendAnalysisCard(
                      analysis: state.dividendAnalysis!,
                    ),
                  ),
                ),

              // 持倉列表標題
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        'portfolio.positions'.tr(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'portfolio.positionCount'.tr(
                          namedArgs: {
                            'count': state.summary.positionCount.toString(),
                          },
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 持倉卡片（懶加載）
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                sliver: SliverList.builder(
                  itemCount: state.positions.length,
                  itemBuilder: (_, i) {
                    final position = state.positions[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PositionCard(
                        position: position,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          context.push(
                            AppRoutes.positionDetail(position.symbol),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // 浮動按鈕
        Positioned(
          right: 16,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
          child: FloatingActionButton(
            onPressed: _showAddTransaction,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // outline 在淺色主題是 #E0E0E8——當前景色時對白底僅 1.1~1.4:1
          // （原 icon @0.5 更僅 1.14），全部改用 onSurfaceVariant
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'portfolio.noPositions'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'portfolio.noPositionsHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _showAddTransaction,
            icon: const Icon(Icons.add),
            label: Text('portfolio.addTransaction'.tr()),
          ),
        ],
      ),
    );
  }

  void _showAddTransaction() {
    HapticFeedback.lightImpact();
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddTransactionSheet(),
    );
  }
}

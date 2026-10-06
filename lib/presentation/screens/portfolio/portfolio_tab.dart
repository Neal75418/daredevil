import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_live_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
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
import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';

/// 投資組合頁內容（router 的 /portfolio 全螢幕路由；從自選頁選單進入）
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
    // 登記的「是否已有今天正式資料」跟現在有關:跨過午夜等邊界時重算
    ref.watch(liveQuoteBoundaryProvider);

    if (state.isLoading && state.positions.isEmpty) {
      return const GenericListShimmer(itemCount: 4);
    }

    if (state.error != null && state.positions.isEmpty) {
      void onRetry() => ref.read(portfolioProvider.notifier).loadPositions();
      return FillRemainingScrollable(
        child: ErrorDisplay.isNetworkError(state.error!)
            ? EmptyStates.networkError(onRetry: onRetry)
            : EmptyStates.error(message: state.error!, onRetry: onRetry),
      );
    }

    if (state.positions.isEmpty) {
      return _buildEmpty(theme);
    }

    return LiveQuoteScope(
      registrations: portfolioRegistrations(
        state.positions,
        ref.read(appClockProvider).now(),
      ),
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () =>
                ref.read(portfolioProvider.notifier).loadPositions(),
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
                    child: Consumer(
                      builder: (context, ref, _) {
                        final live = ref.watch(portfolioLiveProvider);
                        return PortfolioSummaryCard(
                          summary: live.summary,
                          todayPnl: live.todayPnl,
                        );
                      },
                    ),
                  ),
                ),

                // 績效、配置、股利維持盤後:標資料日期(spec §7)
                if (state.priceDate case final date?)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'portfolio.postMarketAsOf'.tr(
                          namedArgs: {'date': '${date.month}/${date.day}'},
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                        Expanded(
                          child: Consumer(
                            builder: (context, ref, _) {
                              final status = ref.watch(
                                portfolioLiveProvider.select((l) => l.status),
                              );
                              if (status == null) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                status,
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
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
                        // 以代號為 key:清單重排時不把別檔的閃色狀態套到這一列
                        key: ValueKey(position.symbol),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Consumer(
                          builder: (context, ref, _) {
                            final merged = ref.watch(
                              portfolioLivePriceProvider(position.symbol),
                            );
                            final status = ref.watch(
                              liveQuoteCenterProvider.select(
                                (s) => s.symbolStatus[position.symbol],
                              ),
                            );
                            final flashOn = ref.watch(
                              settingsProvider.select((s) => s.priceFlash),
                            );
                            return PositionCard(
                              position: merged == null
                                  ? position
                                  : position.copyWithPrice(merged.price),
                              live: merged == null
                                  ? null
                                  : PositionCardLive(
                                      flash: merged.kind == MergedPriceKind.live
                                          ? merged.live?.flash
                                          : null,
                                      flashEnabled: flashOn,
                                      caption: LiveQuoteStatusRule.card(
                                        status: status,
                                        merged: merged,
                                      )?.text(),
                                    ),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context.push(
                                  AppRoutes.positionDetail(position.symbol),
                                );
                              },
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
      ),
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

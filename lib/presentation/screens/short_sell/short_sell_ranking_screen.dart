import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/data/models/tpex/tpex_short_sell_ranking.dart';
import 'package:daredevil/presentation/providers/short_sell_ranking_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';

/// 融券賣出排行畫面
class ShortSellRankingScreen extends ConsumerStatefulWidget {
  const ShortSellRankingScreen({super.key});

  @override
  ConsumerState<ShortSellRankingScreen> createState() =>
      _ShortSellRankingScreenState();
}

class _ShortSellRankingScreenState
    extends ConsumerState<ShortSellRankingScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(shortSellRankingProvider.notifier).loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shortSellRankingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('shortSell.title'.tr()),
            if (state.fetchedAt != null)
              Text(
                DateFormat('MM/dd HH:mm').format(state.fetchedAt!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: state.isLoading && state.rankings.isEmpty
          ? const GenericListShimmer(itemCount: 8)
          : state.error != null && state.rankings.isEmpty
          ? FillRemainingScrollable(
              child: ErrorDisplay.isNetworkError(state.error!)
                  ? EmptyStates.networkError(
                      onRetry: () => ref
                          .read(shortSellRankingProvider.notifier)
                          .loadData(),
                    )
                  : EmptyStates.error(
                      message: state.error!,
                      onRetry: () => ref
                          .read(shortSellRankingProvider.notifier)
                          .loadData(),
                    ),
            )
          : Column(
              children: [
                if (state.error != null && state.rankings.isNotEmpty)
                  MaterialBanner(
                    content: Text(state.error!),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: () => ref
                            .read(shortSellRankingProvider.notifier)
                            .loadData(),
                        child: Text('common.retry'.tr()),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(shortSellRankingProvider.notifier)
                            .clearError(),
                        child: Text('common.dismiss'.tr()),
                      ),
                    ],
                  ),
                Expanded(
                  child: ThemedRefreshIndicator(
                    onRefresh: () =>
                        ref.read(shortSellRankingProvider.notifier).loadData(),
                    child: state.rankings.isEmpty
                        ? _buildEmptyState(theme)
                        : _buildRankingList(theme, state.rankings),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return FillRemainingScrollable(
      child: EmptyState(icon: Icons.show_chart, title: 'shortSell.noData'.tr()),
    );
  }

  Widget _buildRankingList(
    ThemeData theme,
    List<TpexShortSellRanking> rankings,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing16,
        DesignTokens.spacing32,
      ),
      itemCount: rankings.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) return _buildTableHeader(theme);
        return _buildRankingItem(theme, rankings[index - 1]);
      },
    );
  }

  Widget _buildTableHeader(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacing8),
      padding: const EdgeInsets.symmetric(
        vertical: DesignTokens.spacing10,
        horizontal: DesignTokens.spacing12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'shortSell.stock'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'shortSell.currentBalance'.tr(),
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
              'shortSell.change'.tr(),
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingItem(ThemeData theme, TpexShortSellRanking item) {
    final change = item.balanceChange;
    final changeColor = change > 0
        ? AppTheme
              .downColor // 融券增加 = 看空 = 綠色（downColor）
        : change < 0
        ? AppTheme
              .upColor // 融券減少 = 回補 = 紅色（upColor）
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: () {
        ref.read(stockBrowsingContextProvider.notifier).set([
          for (final r in ref.read(shortSellRankingProvider).rankings) r.symbol,
        ]);
        context.push(AppRoutes.stockDetail(item.symbol));
      },
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: Row(
          children: [
            // 排名
            SizedBox(
              width: 32,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.rank <= 3
                      ? AppTheme.downColor.withValues(alpha: 0.1)
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                ),
                child: Text(
                  '${item.rank}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: item.rank <= 3
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: item.rank <= 3
                        ? AppTheme.downColor
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            // 股票代號 + 名稱
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.symbol,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    item.companyName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 當日餘額
            Expanded(
              flex: 2,
              child: Text(
                LocalizedNumberFormat.compact(
                  item.currentBalance.toDouble(),
                  Localizations.localeOf(context),
                ),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 變化
            Expanded(
              flex: 2,
              child: Text(
                '${change > 0 ? '+' : ''}${LocalizedNumberFormat.compact(change.toDouble(), Localizations.localeOf(context))}',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: changeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

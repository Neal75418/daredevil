import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/data/models/tpex/tpex_industry_eps.dart';
import 'package:daredevil/presentation/providers/industry_eps_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';

/// 產業別 EPS 排名畫面
class IndustryEpsScreen extends ConsumerStatefulWidget {
  const IndustryEpsScreen({super.key});

  @override
  ConsumerState<IndustryEpsScreen> createState() => _IndustryEpsScreenState();
}

class _IndustryEpsScreenState extends ConsumerState<IndustryEpsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(industryEpsProvider.notifier).loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(industryEpsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('industryEps.title'.tr()),
            if (state.fetchedAt != null)
              Text(
                DateFormat('MM/dd HH:mm').format(state.fetchedAt!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          if (state.quarterLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: DesignTokens.spacing16),
              child: Center(
                child: Text(
                  state.quarterLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: state.isLoading && state.allData.isEmpty
          ? const GenericListShimmer(itemCount: 8)
          : state.error != null && state.allData.isEmpty
          ? FillRemainingScrollable(
              child: ErrorDisplay.isNetworkError(state.error!)
                  ? EmptyStates.networkError(
                      onRetry: () =>
                          ref.read(industryEpsProvider.notifier).loadData(),
                    )
                  : EmptyStates.error(
                      message: state.error!,
                      onRetry: () =>
                          ref.read(industryEpsProvider.notifier).loadData(),
                    ),
            )
          : Column(
              children: [
                if (state.error != null && state.allData.isNotEmpty)
                  MaterialBanner(
                    content: Text(state.error!),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            ref.read(industryEpsProvider.notifier).loadData(),
                        child: Text('common.retry'.tr()),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(industryEpsProvider.notifier).clearError(),
                        child: Text('common.dismiss'.tr()),
                      ),
                    ],
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        ref.read(industryEpsProvider.notifier).loadData(),
                    child: state.allData.isEmpty
                        ? _buildEmptyState(theme)
                        : _buildContent(theme, state),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return FillRemainingScrollable(
      child: EmptyState(
        icon: Icons.analytics_outlined,
        title: 'industryEps.noData'.tr(),
        actionLabel: 'common.retry'.tr(),
        onAction: () => ref.read(industryEpsProvider.notifier).loadData(),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, IndustryEpsState state) {
    final filteredData = state.filteredData;

    return Column(
      children: [
        // 產業篩選器
        _buildIndustryFilter(theme, state),

        // 表頭
        _buildTableHeader(theme),

        // 資料列
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacing32),
            itemCount: filteredData.length,
            itemBuilder: (context, index) {
              return _buildEpsItem(theme, filteredData, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIndustryFilter(ThemeData theme, IndustryEpsState state) {
    final industries = state.industries;

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing12,
          vertical: DesignTokens.spacing6,
        ),
        itemCount: industries.length + 1, // +1 for "全部"
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final industry = isAll ? null : industries[index - 1];
          final isSelected = state.selectedIndustry == industry;

          return Padding(
            padding: const EdgeInsets.only(right: DesignTokens.spacing6),
            child: FilterChip(
              label: Text(
                isAll ? 'industryEps.all'.tr() : industry!,
                style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
              ),
              selected: isSelected,
              onSelected: (_) {
                ref
                    .read(industryEpsProvider.notifier)
                    .setIndustryFilter(isSelected ? null : industry);
              },
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacing16),
      padding: const EdgeInsets.symmetric(
        vertical: DesignTokens.spacing8,
        horizontal: DesignTokens.spacing12,
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
              'industryEps.stock'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'industryEps.eps'.tr(),
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
              'industryEps.netIncome'.tr(),
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

  Widget _buildEpsItem(
    ThemeData theme,
    List<TpexIndustryEps> filteredData,
    int index,
  ) {
    final item = filteredData[index];
    // 台股慣例：紅 = 獲利 / 上漲，綠 = 虧損 / 下跌
    final epsColor = item.eps > 0
        ? AppTheme.upColor
        : item.eps < 0
        ? AppTheme.downColor
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: () {
        ref.read(stockBrowsingContextProvider.notifier).set([
          for (final e in filteredData) e.symbol,
        ]);
        context.push(AppRoutes.stockDetail(item.symbol));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacing16),
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacing10,
          horizontal: DesignTokens.spacing12,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: Row(
          children: [
            // 股票資訊
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.symbol,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing6),
                      Flexible(
                        child: Text(
                          item.companyName,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    item.industry,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            // EPS
            Expanded(
              flex: 2,
              child: Text(
                item.eps.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: epsColor,
                ),
              ),
            ),
            // 稅後淨利
            Expanded(
              flex: 2,
              child: Text(
                LocalizedNumberFormat.compactFromThousands(
                  item.netIncome,
                  Localizations.localeOf(context),
                ),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

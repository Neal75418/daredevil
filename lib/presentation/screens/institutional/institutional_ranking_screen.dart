import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/data/database/dao/institutional_dao.dart';
import 'package:daredevil/presentation/providers/institutional_ranking_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

/// 法人買賣超排行——外資/投信 × 買超/賣超 四視角,各 Top 50。
///
/// 設計定稿(2026-08-05):金額為主排序(跨價位可比)、張數並列、
/// 連買/連賣天數欄(單日榜噪音的解毒劑)、雙買/雙賣 badge(外資投信
/// 同日同向=最強共識)。自營刻意不做。表格佈局沿用營收總覽的語言。
class InstitutionalRankingScreen extends ConsumerStatefulWidget {
  const InstitutionalRankingScreen({super.key});

  @override
  ConsumerState<InstitutionalRankingScreen> createState() =>
      _InstitutionalRankingScreenState();
}

class _InstitutionalRankingScreenState
    extends ConsumerState<InstitutionalRankingScreen> {
  static const double _cellWidth = 84;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(institutionalRankingProvider.notifier).loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(institutionalRankingProvider);
    final theme = Theme.of(context);
    final ranking = state.ranking;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('instRanking.title'.tr()),
            if (ranking != null)
              Text(
                DateFormat('yyyy/MM/dd').format(ranking.date),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.tableMaxWidth,
          ),
          child: state.isLoading && ranking == null
              ? const GenericListShimmer(itemCount: 10)
              // 靜默稽核 #9:DB 錯誤原本偽裝成「暫無資料」——provider 有寫
              // error 但這頁沒讀,且空狀態分支在 RefreshIndicator 外連下拉
              // 重試都不可達。比照 revenue_overview_screen 的 error 分支,
              // 另補重試入口。
              : state.error != null && ranking == null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: state.error!,
                  actionLabel: 'common.retry'.tr(),
                  onAction: () => ref
                      .read(institutionalRankingProvider.notifier)
                      .loadData(),
                )
              : ranking == null
              ? EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'instRanking.empty'.tr(),
                )
              : _buildList(state),
        ),
      ),
    );
  }

  Widget _buildList(InstitutionalRankingState state) {
    final theme = Theme.of(context);
    final rows = state.visibleRows;
    final watchlistSymbols = ref.watch(
      watchlistProvider.select((s) => s.watchedSymbols),
    );

    return ThemedRefreshIndicator(
      onRefresh: () =>
          ref.read(institutionalRankingProvider.notifier).loadData(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildViewSelector(state)),
          SliverToBoxAdapter(child: _buildColumnHeader(theme, state)),
          if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'instRanking.noRows'.tr(),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing24),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => _buildRow(
                  theme,
                  state,
                  rows[index],
                  index + 1,
                  watchlistSymbols,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewSelector(InstitutionalRankingState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Wrap(
        spacing: DesignTokens.spacing8,
        children: [
          for (final v in InstitutionalView.values)
            FilterChip(
              label: Text('instRanking.view.${v.name}'.tr()),
              selected: state.view == v,
              onSelected: (_) =>
                  ref.read(institutionalRankingProvider.notifier).setView(v),
            ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(ThemeData theme, InstitutionalRankingState state) {
    Widget h(String key) => SizedBox(
      width: _cellWidth,
      child: Text(
        key.tr(),
        textAlign: TextAlign.end,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: DesignTokens.fontSizeXs,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing16,
        DesignTokens.spacing4,
      ),
      child: Row(
        children: [
          const Spacer(),
          h('instRanking.colShares'),
          const SizedBox(width: DesignTokens.spacing12),
          h('instRanking.colAmount'),
          const SizedBox(width: DesignTokens.spacing12),
          h(
            state.isBuyView
                ? 'instRanking.colStreakBuy'
                : 'instRanking.colStreakSell',
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    ThemeData theme,
    InstitutionalRankingState state,
    InstitutionalRankingRow row,
    int rank,
    Set<String> watchlistSymbols,
  ) {
    final isWatched = watchlistSymbols.contains(row.symbol);
    // 多空語意軸共用紅綠(買超=紅、賣超=綠,同籌碼評等慣例)
    final directionColor = state.isBuyView
        ? AppTheme.upColor
        : PriceColors.downFor(theme.brightness);

    return InkWell(
      onTap: () => context.push(AppRoutes.stockDetail(row.symbol)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing16,
          vertical: DesignTokens.spacing8,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      '${row.symbol} ${row.name}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isWatched
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isWatched) ...[
                    const SizedBox(width: DesignTokens.spacing4),
                    Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                  if (row.isDualSide) ...[
                    const SizedBox(width: DesignTokens.spacing4),
                    _dualBadge(theme, state.isBuyView),
                  ],
                ],
              ),
            ),
            _numCell(
              theme,
              _formatShares(row.netShares),
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: DesignTokens.spacing12),
            _numCell(
              theme,
              _formatAmount(row.netAmount),
              color: directionColor,
            ),
            const SizedBox(width: DesignTokens.spacing12),
            _numCell(
              theme,
              row.streakDays > 1 ? '${row.streakDays}' : '—',
              color: row.streakDays >= 3
                  ? directionColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dualBadge(ThemeData theme, bool isBuy) {
    final base = isBuy
        ? AppTheme.upColor
        : PriceColors.downFor(theme.brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Text(
        isBuy ? 'instRanking.dualBuy'.tr() : 'instRanking.dualSell'.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: PriceColors.onTintOf(base, theme.brightness),
          fontSize: DesignTokens.fontSizeXs,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _numCell(ThemeData theme, String text, {required Color color}) {
    return SizedBox(
      width: _cellWidth,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// 張數(千股),千分位
  String _formatShares(double netShares) {
    final lots = (netShares.abs() / 1000).round();
    return NumberFormat('#,##0').format(lots);
  }

  /// 金額(億),一位小數
  String _formatAmount(double netAmount) {
    return '${(netAmount.abs() / 1e8).toStringAsFixed(1)}${'unit.billion'.tr()}';
  }
}

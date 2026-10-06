import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

/// 個股頁「新聞」分頁：這檔近 30 天的新聞（lazy 清單）
class StockNewsTab extends ConsumerStatefulWidget {
  const StockNewsTab({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<StockNewsTab> createState() => _StockNewsTabState();
}

class _StockNewsTabState extends ConsumerState<StockNewsTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    // await 前先取：抓取期間分頁可能被切走或換股拆掉，提示仍要出現
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _refreshing = true);
    final outcome = await ref.read(newsFetcherProvider).fetch();
    if (mounted) setState(() => _refreshing = false);
    showNewsFetchFeedback(messenger, outcome, errorColor: errorColor);
  }

  void _openStock(String symbol) => context.push(AppRoutes.stockDetail(symbol));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockNewsProvider(widget.symbol));
    final now = ref.read(appClockProvider).now();

    // primary: false 與其他 5 個分頁一致：捲清單不帶動外層報價區收合
    return CustomScrollView(
      primary: false,
      slivers: [
        SliverToBoxAdapter(
          child: _NoteRow(
            status: async.value?.nameStatus,
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
        ),
        ...async.when(
          skipLoadingOnReload: true,
          data: (data) => data.items.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.article_outlined,
                      title: S.stockNewsEmpty,
                    ),
                  ),
                ]
              : newsSectionSlivers(
                  sections: groupNewsByDay(data.items, now),
                  relatedStocksOf: (id) =>
                      data.otherStocksByNewsId[id] ?? const [],
                  onTap: (item, related) => showNewsPreviewSheet(
                    context,
                    item: item,
                    relatedStocks: related,
                    onStockTap: _openStock,
                  ),
                  onStockTap: _openStock,
                ),
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: NewsListShimmer(itemCount: 6),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStates.error(
                message: ErrorDisplay.message(e),
                onRetry: () => ref.invalidate(stockNewsProvider(widget.symbol)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.status,
    required this.refreshing,
    required this.onRefresh,
  });

  final StockNameStatus? status;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = switch (status) {
      StockNameStatus.matched => S.stockNewsNoteMatched,
      StockNameStatus.excluded => S.stockNewsNoteExcluded,
      StockNameStatus.notListed => S.stockNewsNoteNotListed,
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing8,
        DesignTokens.spacing8,
      ),
      child: Row(
        children: [
          Expanded(
            child: note == null
                ? const SizedBox.shrink()
                : Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          IconButton(
            tooltip: S.stockNewsRefresh,
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

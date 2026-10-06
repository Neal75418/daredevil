import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/news/heat_analysis_tab.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 新聞畫面 - 顯示近期市場新聞，支援篩選、搜尋與分類
class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(newsProvider.notifier).loadData();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        ref.read(newsProvider.notifier).setSearchQuery('');
      }
    });
  }

  Future<void> _refresh() async {
    // 先抓新聞再重讀本地（抓取失敗仍會重讀，見 NewsNotifier.refresh）；
    // 熱度分頁監聽新聞資料版本，不必在這裡 invalidate
    // await 前先取：抓取期間離開新聞頁，提示仍要出現
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final outcome = await ref.read(newsProvider.notifier).refresh();
    if (outcome != null) {
      showNewsFetchFeedback(messenger, outcome, errorColor: errorColor);
    }
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsProvider);
    // 任何地方抓完新聞（例如個股新聞分頁）都重讀；自己的 refresh 進行中會略過
    ref.listen(
      newsDataVersionProvider,
      (_, _) => ref.read(newsProvider.notifier).onNewsDataChanged(),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'common.search'.tr(),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () {
                        ref.read(newsProvider.notifier).setSearchQuery(value);
                      },
                    );
                  },
                )
              : Text(S.newsTitle),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
              tooltip: _isSearching
                  ? 'common.close'.tr()
                  : 'common.search'.tr(),
            ),
            IconButton(
              // 重新整理進行中改顯示轉圈——已有內容時列表保持原地
              //（不切 shimmer），進度回饋集中在這裡
              icon: state.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: S.refresh,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'news.allNewsTab'.tr()),
              Tab(text: 'news.heatTab'.tr()),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AllNewsTab(onRefresh: _refresh),
            const HeatAnalysisTab(),
          ],
        ),
      ),
    );
  }
}

// ==================================================
// 全部新聞分頁（篩選、清單、返回後重讀自選）
// ==================================================

class _AllNewsTab extends ConsumerStatefulWidget {
  const _AllNewsTab({required this.onRefresh});

  /// 重新整理回呼（由 NewsScreen 提供：抓新聞、重讀、顯示抓取結果）
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_AllNewsTab> createState() => _AllNewsTabState();
}

class _AllNewsTabState extends ConsumerState<_AllNewsTab> {
  /// 返回後重讀自選∪持股：個股頁可能加入或移除了自選，「自選」篩選要跟上
  Future<void> _openStock(String symbol) async {
    await context.push(AppRoutes.stockDetail(symbol));
    if (!mounted) return;
    await ref.read(newsProvider.notifier).reloadMySymbols();
  }

  void _showPreview(NewsItemEntry item, List<String> related) =>
      showNewsPreviewSheet(
        context,
        item: item,
        relatedStocks: related,
        onStockTap: _openStock,
      );

  Widget _emptyState(NewsState state) {
    if (state.filter is MineNewsFilter && state.searchQuery.isEmpty) {
      return state.mySymbols.isEmpty
          ? EmptyState(icon: Icons.star_outline, title: S.newsMineEmptyNoStocks)
          : EmptyState(
              icon: Icons.article_outlined,
              title: S.newsMineEmptyNoNews,
            );
    }
    return EmptyStates.noNews();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsProvider);

    return Column(
      children: [
        // 來源篩選標籤（重新整理時保留，避免整排 chips 閃爍消失）
        if (state.allNews.isNotEmpty)
          _NewsFilterChips(
            filter: state.filter,
            sourceCounts: state.sourceCounts,
            mineCount: state.mineCount,
            onSelected: ref.read(newsProvider.notifier).setFilter,
          ),
        // Refresh 失敗但有舊資料時顯示 MaterialBanner
        if (state.error != null && state.allNews.isNotEmpty)
          MaterialBanner(
            content: Text(state.error!),
            actions: [
              TextButton(
                onPressed: widget.onRefresh,
                child: Text('common.retry'.tr()),
              ),
              TextButton(
                onPressed: () => ref.read(newsProvider.notifier).clearError(),
                child: Text('common.dismiss'.tr()),
              ),
            ],
          ),
        // 新聞列表
        Expanded(
          child: ThemedRefreshIndicator(
            onRefresh: widget.onRefresh,
            // shimmer 只在「首次載入且尚無內容」時出現；已有內容的
            // 重新整理保持列表原地不動（進度看右上角按鈕轉圈）
            child: state.isLoading && state.allNews.isEmpty
                ? const NewsListShimmer(itemCount: 8)
                : state.error != null && state.allNews.isEmpty
                ? FillRemainingScrollable(
                    child: ErrorDisplay.isNetworkError(state.error!)
                        ? EmptyStates.networkError(onRetry: widget.onRefresh)
                        : EmptyStates.error(
                            message: state.error!,
                            onRetry: widget.onRefresh,
                          ),
                  )
                : state.filteredNews.isEmpty
                ? FillRemainingScrollable(child: _emptyState(state))
                : CustomScrollView(
                    slivers: newsSectionSlivers(
                      sections: groupNewsTodayYesterdayEarlier(
                        state.filteredNews,
                        ref.read(appClockProvider).now(),
                      ),
                      relatedStocksOf: state.relatedStocksOf,
                      onTap: _showPreview,
                      onStockTap: _openStock,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ==================================================
// 來源篩選標籤
// ==================================================

class _NewsFilterChips extends StatelessWidget {
  const _NewsFilterChips({
    required this.filter,
    required this.sourceCounts,
    required this.mineCount,
    required this.onSelected,
  });

  final NewsFilter filter;
  final Map<NewsSource, int> sourceCounts;
  final int mineCount;
  final ValueChanged<NewsFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // FilterChip 選中時的底色是 chipTheme.selectedColor，不是 M3 預設的實心
    // secondaryContainer——深色主題沒覆寫它，落回實心 secondaryContainer，
    // onSecondaryContainer 正確；淺色主題覆寫成 primaryColor@15% 疊白的
    // 淡藍色（見 app_theme.dart chipTheme），onSecondaryContainer 對這個
    // 合成色只有 1.14:1（幾乎看不見），故淺色主題改用 onSurface
    // （chipTheme.labelStyle 預設色，對淡藍合成色約 15:1）。
    final selectedLabelColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;

    Widget chip(NewsFilter value, String label) {
      final selected = value == filter;
      return FilterChip(
        selected: selected,
        label: Text(label),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: selected ? selectedLabelColor : theme.colorScheme.onSurface,
        ),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onSelected(value);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Wrap(
        spacing: DesignTokens.spacing8,
        runSpacing: DesignTokens.spacing8,
        children: [
          chip(
            NewsFilter.all,
            '${NewsSource.all.label} (${sourceCounts[NewsSource.all] ?? 0})',
          ),
          chip(NewsFilter.mine, '${S.newsFilterMine} ($mineCount)'),
          for (final source in NewsSource.values)
            if (source != NewsSource.all && (sourceCounts[source] ?? 0) > 0)
              chip(
                SourceNewsFilter(source),
                '${source.label} (${sourceCounts[source] ?? 0})',
              ),
        ],
      ),
    );
  }
}

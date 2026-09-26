import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_heat_provider.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/screens/news/heat_analysis_tab.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

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
    // 先抓 RSS 再重讀本地（RSS 失敗仍會重讀，見 NewsNotifier.refresh）
    await ref.read(newsProvider.notifier).refresh();
    // 熱度分析與全部新聞共用同一份 RSS 資料，重新整理完成後 invalidate
    // 讓熱度分頁的下次讀取反映新抓的新聞
    ref.invalidate(newsHeatProvider);
    // 刷新完成時觸覺回饋
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsProvider);

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
// 全部新聞分頁（原 NewsScreen body，邏輯不變）
// ==================================================

class _AllNewsTab extends ConsumerStatefulWidget {
  const _AllNewsTab({required this.onRefresh});

  /// 重新整理回呼（由 NewsScreen 提供，含 RSS 同步 + newsHeatProvider invalidate）
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_AllNewsTab> createState() => _AllNewsTabState();
}

class _AllNewsTabState extends ConsumerState<_AllNewsTab> {
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted) _showOpenLinkError();
      return;
    }
    try {
      final launched = await canLaunchUrl(uri);
      if (launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) _showOpenLinkError();
      }
    } catch (e) {
      if (mounted) _showOpenLinkError();
    }
  }

  void _showOpenLinkError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.newsCannotOpenLink),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showNewsPreview(NewsItemEntry item, List<String> relatedStocks) {
    final theme = Theme.of(context);

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 拖曳把手
            const DragHandle(
              margin: EdgeInsets.symmetric(vertical: DesignTokens.spacing8),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(DesignTokens.spacing16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 來源與時間
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacing8,
                            vertical: DesignTokens.spacing4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusXs,
                            ),
                          ),
                          child: Text(
                            item.source,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spacing8),
                        Text(
                          _formatFullTime(item.publishedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacing16),
                    // 標題
                    Text(
                      item.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // 相關股票
                    if (relatedStocks.isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spacing16),
                      Text(
                        S.newsRelatedStocks,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacing8),
                      Wrap(
                        spacing: DesignTokens.spacing8,
                        runSpacing: DesignTokens.spacing8,
                        children: relatedStocks.map((symbol) {
                          return ActionChip(
                            label: Text(symbol),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.pop(context);
                              context.push(AppRoutes.stockDetail(symbol));
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: DesignTokens.spacing24),
                    // 在瀏覽器開啟按鈕
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openUrl(item.url);
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: Text(S.newsOpenInBrowser),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsProvider);

    return Column(
      children: [
        // 來源篩選標籤（重新整理時保留，避免整排 chips 閃爍消失）
        if (state.allNews.isNotEmpty)
          _SourceFilterChips(
            selectedSource: state.selectedSource,
            sourceCounts: state.sourceCounts,
            onSelected: (source) {
              ref.read(newsProvider.notifier).setSourceFilter(source);
            },
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
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: ErrorDisplay.isNetworkError(state.error!)
                          ? EmptyStates.networkError(onRetry: widget.onRefresh)
                          : EmptyStates.error(
                              message: state.error!,
                              onRetry: widget.onRefresh,
                            ),
                    ),
                  )
                : state.filteredNews.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: EmptyStates.noNews(),
                    ),
                  )
                : _GroupedNewsList(
                    news: state.filteredNews,
                    newsStockMap: state.newsStockMap,
                    onTap: _showNewsPreview,
                  ),
          ),
        ),
      ],
    );
  }

  String _formatFullTime(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ==================================================
// 來源篩選標籤
// ==================================================

class _SourceFilterChips extends StatelessWidget {
  const _SourceFilterChips({
    required this.selectedSource,
    required this.sourceCounts,
    required this.onSelected,
  });

  final NewsSource selectedSource;
  final Map<NewsSource, int> sourceCounts;
  final ValueChanged<NewsSource> onSelected;

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

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Wrap(
        spacing: DesignTokens.spacing8,
        runSpacing: DesignTokens.spacing8,
        children: [
          for (final source in NewsSource.values)
            if (source == NewsSource.all || (sourceCounts[source] ?? 0) > 0)
              FilterChip(
                selected: source == selectedSource,
                label: Text('${source.label} (${sourceCounts[source] ?? 0})'),
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  color: source == selectedSource
                      ? selectedLabelColor
                      : theme.colorScheme.onSurface,
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  onSelected(source);
                },
              ),
        ],
      ),
    );
  }
}

// ==================================================
// 分組新聞列表
// ==================================================

class _GroupedNewsList extends StatelessWidget {
  const _GroupedNewsList({
    required this.news,
    required this.newsStockMap,
    required this.onTap,
  });

  final List<NewsItemEntry> news;
  final Map<String, List<String>> newsStockMap;
  final void Function(NewsItemEntry, List<String>) onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateContext.normalize(now);
    final yesterday = today.subtract(const Duration(days: 1));

    // 依日期分組新聞
    final todayNews = <NewsItemEntry>[];
    final yesterdayNews = <NewsItemEntry>[];
    final earlierNews = <NewsItemEntry>[];

    for (final item in news) {
      final itemDate = DateTime(
        item.publishedAt.year,
        item.publishedAt.month,
        item.publishedAt.day,
      );

      if (itemDate == today) {
        todayNews.add(item);
      } else if (itemDate == yesterday) {
        yesterdayNews.add(item);
      } else {
        earlierNews.add(item);
      }
    }

    // 建立帶 section header 的扁平索引清單，用於 lazy loading
    final sections = <(String title, List<NewsItemEntry> items)>[
      if (todayNews.isNotEmpty) (S.newsToday, todayNews),
      if (yesterdayNews.isNotEmpty) (S.newsYesterday, yesterdayNews),
      if (earlierNews.isNotEmpty) (S.newsEarlier, earlierNews),
    ];

    return CustomScrollView(
      slivers: [
        for (final (title, items) in sections) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(title: title, count: items.length),
          ),
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => _NewsListItem(
              item: items[index],
              relatedStocks: newsStockMap[items[index].id] ?? [],
              onTap: onTap,
            ),
          ),
        ],
      ],
    );
  }
}

// ==================================================
// 區段標題
// ==================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: DesignTokens.spacing8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing6,
              vertical: DesignTokens.spacing2,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================
// 新聞列表項目
// ==================================================

class _NewsListItem extends StatelessWidget {
  const _NewsListItem({
    required this.item,
    required this.relatedStocks,
    required this.onTap,
  });

  final NewsItemEntry item;
  final List<String> relatedStocks;
  final void Function(NewsItemEntry, List<String>) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const maxVisibleStocks = 3;
    final hasMoreStocks = relatedStocks.length > maxVisibleStocks;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap(item, relatedStocks);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing16,
          vertical: DesignTokens.spacing12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: DesignTokens.spacing8),
            // 來源與時間
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacing6,
                    vertical: DesignTokens.spacing2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                  ),
                  child: Text(
                    item.source,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Text(
                  _formatTime(item.publishedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            // 相關股票
            if (relatedStocks.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacing8),
              Wrap(
                spacing: DesignTokens.spacing4,
                runSpacing: DesignTokens.spacing4,
                children: [
                  ...relatedStocks.take(maxVisibleStocks).map((symbol) {
                    return _StockChip(
                      symbol: symbol,
                      onTap: () => context.push(AppRoutes.stockDetail(symbol)),
                    );
                  }),
                  if (hasMoreStocks)
                    _StockChip(
                      symbol: '+${relatedStocks.length - maxVisibleStocks}',
                      isOverflow: true,
                      onTap: () => onTap(item, relatedStocks),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) {
      return S.newsMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return S.newsHoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return S.newsDaysAgo(diff.inDays);
    } else if (dt.year == now.year) {
      return '${dt.month}/${dt.day}';
    } else {
      return '${dt.year}/${dt.month}/${dt.day}';
    }
  }
}

// ==================================================
// 股票標籤
// ==================================================

class _StockChip extends StatelessWidget {
  const _StockChip({
    required this.symbol,
    required this.onTap,
    this.isOverflow = false,
  });

  final String symbol;
  final VoidCallback onTap;
  final bool isOverflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing8,
          vertical: DesignTokens.spacing4,
        ),
        decoration: BoxDecoration(
          color: isOverflow
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        child: Text(
          symbol,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isOverflow
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isOverflow ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';

/// 新聞段落的 slivers（段落標題＋lazy 清單）——新聞頁與個股新聞分頁共用
List<Widget> newsSectionSlivers({
  required List<NewsSection> sections,
  required List<String> Function(String newsId) relatedStocksOf,
  required void Function(NewsItemEntry, List<String>) onTap,
  required ValueChanged<String> onStockTap,
}) => [
  for (final s in sections) ...[
    SliverToBoxAdapter(
      child: NewsSectionHeader(title: s.title, count: s.items.length),
    ),
    SliverList.builder(
      itemCount: s.items.length,
      itemBuilder: (context, index) => NewsListItem(
        item: s.items[index],
        relatedStocks: relatedStocksOf(s.items[index].id),
        onTap: onTap,
        onStockTap: onStockTap,
      ),
    ),
  ],
];

// ==================================================
// 區段標題
// ==================================================

class NewsSectionHeader extends StatelessWidget {
  const NewsSectionHeader({
    super.key,
    required this.title,
    required this.count,
  });

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

class NewsListItem extends StatelessWidget {
  const NewsListItem({
    super.key,
    required this.item,
    required this.relatedStocks,
    required this.onTap,
    required this.onStockTap,
  });

  final NewsItemEntry item;
  final List<String> relatedStocks;
  final void Function(NewsItemEntry, List<String>) onTap;
  final ValueChanged<String> onStockTap;

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
                    return NewsStockChip(
                      symbol: symbol,
                      onTap: () => onStockTap(symbol),
                    );
                  }),
                  if (hasMoreStocks)
                    NewsStockChip(
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

  String _formatTime(DateTime publishedAt) {
    final now = DateTime.now();
    final dt = publishedAt.toLocal();
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

class NewsStockChip extends StatelessWidget {
  const NewsStockChip({
    super.key,
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

// ==================================================
// 預覽與開原文
// ==================================================

/// 新聞預覽（底部面板）：來源、時間、標題、相關股票、開原文
void showNewsPreviewSheet(
  BuildContext context, {
  required NewsItemEntry item,
  required List<String> relatedStocks,
  required ValueChanged<String> onStockTap,
}) {
  final theme = Theme.of(context);

  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (sheetContext, scrollController) => Column(
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
                        formatNewsFullTime(item.publishedAt),
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
                            Navigator.pop(sheetContext);
                            onStockTap(symbol);
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
                        Navigator.pop(sheetContext);
                        openNewsUrl(context, item.url);
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

/// 以外部瀏覽器開新聞連結；非 http(s) 或開不了時跳錯誤提示
Future<void> openNewsUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
    _showOpenLinkError(context);
    return;
  }
  try {
    final launched = await canLaunchUrl(uri);
    if (launched) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      _showOpenLinkError(context);
    }
  } catch (e) {
    if (!context.mounted) return;
    _showOpenLinkError(context);
  }
}

void _showOpenLinkError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(S.newsCannotOpenLink),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

/// 抓新聞後的提示：全部失敗（錯誤樣式）、部分失敗（一般樣式）；全部成功不提示
///
/// [messenger] 與 [errorColor] 要在 `await` 抓取**之前**取好：抓取可能等上
/// 十幾秒，期間分頁被切走或換股拆掉，事後就拿不到 context，提示會遺失。
void showNewsFetchFeedback(
  ScaffoldMessengerState messenger,
  NewsFetchOutcome outcome, {
  required Color errorColor,
}) {
  final String message;
  final bool isError;
  if (outcome.allFailed) {
    message = S.newsFetchAllFailed;
    isError = true;
  } else if (outcome.partiallyFailed) {
    message = S.newsFetchPartialFailed(outcome.failedSources);
    isError = false;
  } else {
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? errorColor : null,
    ),
  );
}

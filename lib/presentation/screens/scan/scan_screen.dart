import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/presentation/screens/scan/filter_metadata.dart';
import 'package:daredevil/core/constants/ui_constants.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/responsive_helper.dart';
import 'package:daredevil/presentation/providers/pinned_thesis_provider.dart';
import 'package:daredevil/presentation/providers/scan_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/screens/scan/widgets/industry_filter_chip.dart';
import 'package:daredevil/presentation/screens/scan/widgets/scan_filter_bottom_sheet.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/stock_card.dart';
import 'package:daredevil/presentation/widgets/stock_preview_sheet.dart';
import 'package:daredevil/presentation/widgets/stock_search_delegate.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

/// 掃描畫面 - 顯示所有已分析股票與篩選功能
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _scrollController = ScrollController();

  /// 觀察區（接近觸發）section 是否展開（預設收摺，早期預警但不佔版面）
  bool _observationExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(scanProvider.notifier).loadData();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 當使用者捲動接近底部時觸發載入更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent -
            UiConstants.infiniteScrollThresholdPx) {
      ref.read(scanProvider.notifier).loadMore();
    }
  }

  /// 建立含有篩選條件元資料的空狀態 Widget
  Widget _buildEmptyState(
    ScanFilter filter, {
    required int totalScanned,
    required DateTime? dataDate,
  }) {
    // 對於「全部」篩選，使用簡單的空狀態
    if (filter == ScanFilter.all) {
      return EmptyStates.noFilterResults(
        onClearFilter: null, // 已顯示全部時無需清除
      );
    }

    // 取得篩選條件元資料
    final metadata = filter.metadata;

    // 翻譯資料需求標籤
    final dataReqLabels = metadata.dataRequirements
        .map((req) => req.labelKey.tr())
        .toList();

    return EmptyStates.noFilterResultsWithMeta(
      filterName: filter.labelKey.tr(),
      conditionDescription: metadata.conditionKey.tr(),
      dataRequirements: dataReqLabels,
      thresholdInfo: metadata.thresholdInfo,
      totalScanned: totalScanned,
      dataDate: dataDate,
      onClearFilter: () {
        ref.read(scanProvider.notifier).setFilter(ScanFilter.all);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);

    return Scaffold(
      appBar: _buildAppBar(context, state),
      body: ThemedRefreshIndicator(
        onRefresh: () => ref.read(scanProvider.notifier).loadData(),
        child: Column(
          children: [
            _buildFilterChips(context, state),
            _buildStockCount(context, state),
            _buildStockList(context, state),
          ],
        ),
      ),
    );
  }

  /// AppBar：標題 + 搜尋 + 排序選單 + 更多選單
  PreferredSizeWidget _buildAppBar(BuildContext context, ScanState state) {
    return AppBar(
      title: Text('scan.title'.tr()),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'stockSearch.tooltip'.tr(),
          onPressed: () => _openGlobalSearch(context),
        ),
        PopupMenuButton<ScanSort>(
          icon: const Icon(Icons.sort),
          tooltip: 'scan.sort'.tr(),
          initialValue: state.sort,
          onSelected: (sort) {
            HapticFeedback.selectionClick();
            ref.read(scanProvider.notifier).setSort(sort);
          },
          itemBuilder: (context) {
            return ScanSort.values.map((sort) {
              return PopupMenuItem(
                value: sort,
                child: Row(
                  children: [
                    if (state.sort == sort)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: DesignTokens.spacing8),
                    Text(sort.labelKey.tr()),
                  ],
                ),
              );
            }).toList();
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'scan.more'.tr(),
          onSelected: (value) {
            switch (value) {
              case 'short_sell_ranking':
                context.push(AppRoutes.shortSellRanking);
              case 'industry_eps':
                context.push(AppRoutes.industryEps);
              case 'industry_overview':
                context.push(AppRoutes.industry);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'short_sell_ranking',
              child: Row(
                children: [
                  const Icon(Icons.trending_down, size: 20),
                  const SizedBox(width: DesignTokens.spacing12),
                  Text('shortSell.title'.tr()),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'industry_eps',
              child: Row(
                children: [
                  const Icon(Icons.bar_chart, size: 20),
                  const SizedBox(width: DesignTokens.spacing12),
                  Text('industryEps.title'.tr()),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'industry_overview',
              child: Row(
                children: [
                  const Icon(Icons.category_outlined, size: 20),
                  const SizedBox(width: DesignTokens.spacing12),
                  Text('scan.industry'.tr()),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 篩選標籤列：全部 / 目前篩選 / 產業 / 更多篩選
  Widget _buildFilterChips(BuildContext context, ScanState state) {
    final theme = Theme.of(context);
    // FilterChip 選中時的底色是 chipTheme.selectedColor，不是 M3 預設的實心
    // secondaryContainer——深色主題沒覆寫它，落回實心 secondaryContainer，
    // onSecondaryContainer 正確（6.51:1）；淺色主題覆寫成
    // primaryColor@15% 疊白的淡藍色（見 app_theme.dart chipTheme），
    // onSecondaryContainer 對這個合成色只有 1.14:1（幾乎看不見），故淺色
    // 主題改用 onSurface（chipTheme.labelStyle 預設色，對淡藍合成色
    // 14.98:1）。
    final selectedLabelColor = context.isDark
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 「全部」標籤
            FilterChip(
              label: Text(ScanFilter.all.labelKey.tr()),
              labelStyle: TextStyle(
                color: state.filter == ScanFilter.all
                    ? selectedLabelColor
                    : theme.colorScheme.onSurface,
              ),
              selected: state.filter == ScanFilter.all,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                ref.read(scanProvider.notifier).setFilter(ScanFilter.all);
              },
            ),
            const SizedBox(width: DesignTokens.spacing8),
            // 目前選中的篩選條件（若非「全部」）
            if (state.filter != ScanFilter.all)
              FilterChip(
                label: Text(state.filter.labelKey.tr()),
                selected: true,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  ref.read(scanProvider.notifier).setFilter(ScanFilter.all);
                },
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  HapticFeedback.selectionClick();
                  ref.read(scanProvider.notifier).setFilter(ScanFilter.all);
                },
              ),
            if (state.filter != ScanFilter.all)
              const SizedBox(width: DesignTokens.spacing8),
            // 產業篩選
            if (state.industries.isNotEmpty)
              IndustryFilterChip(
                industries: state.industries,
                selected: state.industryFilter,
                onSelected: (industry) {
                  ref.read(scanProvider.notifier).setIndustryFilter(industry);
                },
              ),
            if (state.industries.isNotEmpty)
              const SizedBox(width: DesignTokens.spacing8),
            // 「更多篩選」按鈕 — 使用主色邊框提升視覺辨識度
            ActionChip(
              avatar: Icon(
                Icons.filter_list,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              label: Text('scan.moreFilters'.tr()),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              onPressed: () => showScanFilterBottomSheet(
                context: context,
                currentFilter: state.filter,
                onFilterSelected: (filter) {
                  ref.read(scanProvider.notifier).setFilter(filter);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 標頭文字：覆蓋透明度漏斗（可交易 → 有訊號 → 已載入），一行收窄。
  ///
  /// 有可交易池資料時顯示漏斗，讓使用者知道清單是訊號子集、非全市場掃描；
  /// 尚未算出（[ScanState.tradeableUniverseCount] = 0）時退回原本的數量/分頁顯示。
  String _coverageLabel(ScanState state) {
    if (state.tradeableUniverseCount > 0) {
      final args = {
        'universe': state.tradeableUniverseCount.toString(),
        'signals': state.totalAnalyzedCount.toString(),
      };
      return state.hasMore
          ? 'scan.coverageFunnelLoaded'.tr(
              namedArgs: {...args, 'loaded': state.stocks.length.toString()},
            )
          : 'scan.coverageFunnel'.tr(namedArgs: args);
    }
    return state.hasMore
        ? 'scan.stockCountLoaded'.tr(
            namedArgs: {
              'loaded': state.stocks.length.toString(),
              'total': state.totalCount.toString(),
            },
          )
        : 'scan.stockCount'.tr(
            namedArgs: {'count': state.stocks.length.toString()},
          );
  }

  /// 股票數量列（分頁時顯示已載入/總數）
  Widget _buildStockCount(BuildContext context, ScanState state) {
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.responsiveHorizontalPadding,
          vertical: 4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _coverageLabel(state),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 股票清單：載入中 / 錯誤 / 空狀態 / 列表或網格
  Widget _buildStockList(BuildContext context, ScanState state) {
    final theme = Theme.of(context);

    if (state.isLoading && state.stocks.isEmpty) {
      return const Expanded(child: StockListShimmer(itemCount: 8));
    }
    if (state.error != null && state.stocks.isEmpty) {
      void onRetry() => ref.read(scanProvider.notifier).loadData();
      return Expanded(
        child: ErrorDisplay.isNetworkError(state.error!)
            ? EmptyStates.networkError(onRetry: onRetry)
            : EmptyStates.error(message: state.error!, onRetry: onRetry),
      );
    }

    // 篩選切換中：顯示輕量 indicator + 保留空狀態或列表
    if (state.isFiltering && state.stocks.isEmpty) {
      return const Expanded(child: Center(child: LinearProgressIndicator()));
    }

    if (state.stocks.isEmpty) {
      return Expanded(
        child: _buildEmptyState(
          state.filter,
          totalScanned: state.totalAnalyzedCount,
          dataDate: state.dataDate,
        ),
      );
    }

    // 響應式佈局：平板/桌面使用 GridView
    final columns = context.responsiveGridColumns;
    final useGrid = columns > 1;

    final listWidget = useGrid
        ? _buildStockGrid(context, state, columns)
        : _buildStockListView(context, state);

    // 有資料但 refresh/loadMore 失敗時，顯示 MaterialBanner
    if (state.error != null) {
      return Expanded(
        child: Column(
          children: [
            MaterialBanner(
              content: Text(state.error!),
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              actions: [
                TextButton(
                  onPressed: () => ref.read(scanProvider.notifier).loadData(),
                  child: Text('common.retry'.tr()),
                ),
                TextButton(
                  onPressed: () => ref.read(scanProvider.notifier).clearError(),
                  child: Text('common.dismiss'.tr()),
                ),
              ],
            ),
            Expanded(child: listWidget),
          ],
        ),
      );
    }

    return Expanded(child: listWidget);
  }

  /// 手機佈局：ListView
  Widget _buildStockListView(BuildContext context, ScanState state) {
    final showLimitMarkers = ref.watch(
      settingsProvider.select((s) => s.limitAlerts),
    );
    // 觀察區放清單「最上面」（收摺 bar）。放底部會被一長串訊號 + 分頁埋住、
    // 捲不到；放頂部立刻看得到、展開才列出接近觸發股。
    final hasObservation = state.observationCount > 0;
    final headerCount = hasObservation ? 1 : 0;
    return ListView.builder(
      controller: _scrollController,
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      itemCount: headerCount + state.stocks.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // 頂部：觀察區（接近觸發）收摺 bar
        if (hasObservation && index == 0) {
          return _buildObservationSection(context, state, showLimitMarkers);
        }
        final stockIndex = index - headerCount;
        // 底部：載入更多指示器
        if (stockIndex == state.stocks.length) {
          return _buildLoadingIndicator(state);
        }
        return _buildStockCard(
          context,
          state.stocks[stockIndex],
          stockIndex,
          showLimitMarkers,
          isGrid: false,
        );
      },
    );
  }

  /// 觀察區（接近觸發）：可摺疊 section，放清單頂部，預設收摺。
  ///
  /// 觀察區 = 分數落在 [observation, signal) 的「快觸發但未成立」股，給早期預警；
  /// 與主清單（成立訊號）清楚分層、不混淆。展開時依 [isGrid] 排成格狀（桌面）
  /// 或直列（手機）。
  Widget _buildObservationSection(
    BuildContext context,
    ScanState state,
    bool showLimitMarkers, {
    bool isGrid = false,
    int columns = 1,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: () =>
              setState(() => _observationExpanded = !_observationExpanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.responsiveHorizontalPadding,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  _observationExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'scan.observationZone'.tr(
                    namedArgs: {'count': state.observationCount.toString()},
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'scan.observationHint'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_observationExpanded) ...[
          if (isGrid)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.responsiveHorizontalPadding,
                vertical: context.responsiveCardSpacing,
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: context.responsiveCardSpacing,
                  mainAxisSpacing: context.responsiveCardSpacing,
                  mainAxisExtent: DesignTokens.stockCardHeight,
                ),
                itemCount: state.observations.length,
                itemBuilder: (context, i) => _buildStockCard(
                  context,
                  state.observations[i],
                  i,
                  showLimitMarkers,
                  isGrid: true,
                ),
              ),
            )
          else
            for (var i = 0; i < state.observations.length; i++)
              _buildStockCard(
                context,
                state.observations[i],
                i,
                showLimitMarkers,
                isGrid: false,
              ),
          const Divider(height: 1), // 觀察股結束、以下為訊號清單
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// 平板/桌面佈局：GridView
  Widget _buildStockGrid(BuildContext context, ScanState state, int columns) {
    final showLimitMarkers = ref.watch(
      settingsProvider.select((s) => s.limitAlerts),
    );
    final padding = context.responsiveHorizontalPadding;
    final spacing = context.responsiveCardSpacing;

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 500,
      slivers: [
        // 觀察區（接近觸發）放最上面、橫跨整列（與手機版一致：頂部才看得到）
        if (state.observationCount > 0)
          SliverToBoxAdapter(
            child: _buildObservationSection(
              context,
              state,
              showLimitMarkers,
              isGrid: true,
              columns: columns,
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: spacing),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: DesignTokens.stockCardHeight,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildStockCard(
                context,
                state.stocks[index],
                index,
                showLimitMarkers,
                isGrid: true,
              ),
              childCount: state.stocks.length,
            ),
          ),
        ),
        if (state.hasMore)
          SliverToBoxAdapter(child: _buildLoadingIndicator(state)),
      ],
    );
  }

  /// 載入指示器
  Widget _buildLoadingIndicator(ScanState state) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      child: Center(
        child: state.isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// 共用的 StockCard 建構（不含 Slidable 包裝與動畫）
  Widget _buildCoreStockCard(
    BuildContext context,
    ScanStockItem stock,
    bool showLimitMarkers, {
    required bool isGrid,
  }) {
    // Consumer 隔離 pinned 狀態：釘選 toggle 只重建這張卡，不 mark 整個
    // ScanScreen dirty（比照 today_screen 的 Consumer 隔離慣例）
    return Consumer(
      builder: (context, cardRef, _) => StockCard(
        symbol: stock.symbol,
        stockName: stock.stockName,
        market: stock.market,
        latestClose: stock.latestClose,
        priceChange: stock.priceChange,
        score: stock.score,
        reasons: stock.reasonTypes,
        trendState: stock.trendState,
        isInWatchlist: stock.isInWatchlist,
        recentPrices: stock.recentPrices,
        showLimitMarkers: showLimitMarkers,
        // 釘選入口（掃描頁是發現訊號的主場）；mode 由 provider 以當日
        // dominant scoringMode 推斷
        pinned: cardRef.watch(
          pinnedThesisProvider.select(
            (s) => s.value?.isPinned(stock.symbol) ?? false,
          ),
        ),
        onPinToggle: () => _togglePin(stock.symbol),
        onTap: () => _openStockDetail(stock.symbol),
        onLongPress: isGrid
            ? () => _showStockContextMenu(context, stock)
            : () {
                showStockPreviewSheet(
                  context: context,
                  data: StockPreviewData(
                    symbol: stock.symbol,
                    stockName: stock.stockName,
                    latestClose: stock.latestClose,
                    priceChange: stock.priceChange,
                    score: stock.score,
                    trendState: stock.trendState,
                    reasons: stock.reasonTypes,
                    isInWatchlist: stock.isInWatchlist,
                  ),
                  onViewDetails: () => _openStockDetail(stock.symbol),
                  onToggleWatchlist: () {
                    ref
                        .read(scanProvider.notifier)
                        .toggleWatchlist(stock.symbol);
                  },
                );
              },
        onWatchlistTap: () {
          HapticFeedback.lightImpact();
          ref.read(scanProvider.notifier).toggleWatchlist(stock.symbol);
        },
      ),
    );
  }

  /// 單張股票卡片：List 模式包 Slidable，Grid 模式直接顯示，各自使用對應動畫
  Widget _buildStockCard(
    BuildContext context,
    ScanStockItem stock,
    int index,
    bool showLimitMarkers, {
    required bool isGrid,
  }) {
    final coreCard = _buildCoreStockCard(
      context,
      stock,
      showLimitMarkers,
      isGrid: isGrid,
    );

    // List 模式：包裝 Slidable 手勢
    final Widget card;
    if (isGrid) {
      card = RepaintBoundary(child: coreCard);
    } else {
      card = RepaintBoundary(
        child: Slidable(
          key: ValueKey(stock.symbol),
          // 向右滑動（startActionPane）→ 檢視詳情
          startActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.25,
            children: [
              SlidableAction(
                onPressed: (_) {
                  HapticFeedback.lightImpact();
                  _openStockDetail(stock.symbol);
                },
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                icon: Icons.visibility_outlined,
                label: 'scan.view'.tr(),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
            ],
          ),
          // 向左滑動（endActionPane）→ 切換自選
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.25,
            children: [
              SlidableAction(
                onPressed: (_) {
                  HapticFeedback.lightImpact();
                  ref.read(scanProvider.notifier).toggleWatchlist(stock.symbol);
                },
                backgroundColor: stock.isInWatchlist
                    ? AppTheme.errorColor
                    : Colors.amber,
                foregroundColor: Colors.white,
                icon: stock.isInWatchlist ? Icons.star_outline : Icons.star,
                label: stock.isInWatchlist
                    ? 'scan.remove'.tr()
                    : 'scan.favorite'.tr(),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ],
          ),
          child: coreCard,
        ),
      );
    }

    // 交錯進場動畫：List 前 10 筆 fadeIn+slideX，Grid 前 20 筆 fadeIn+scale
    if (isGrid) {
      if (index < 20) {
        return card
            .animate()
            .fadeIn(
              delay: Duration(
                milliseconds: UiConstants.gridAnimationDelayMs * index,
              ),
              duration: UiConstants.gridAnimationDurationMs.ms,
            )
            .scale(
              begin: const Offset(0.95, 0.95),
              duration: UiConstants.gridAnimationDurationMs.ms,
              curve: AnimCurves.smooth,
            );
      }
    } else {
      if (index < 10) {
        return card
            .animate()
            .fadeIn(
              delay: Duration(
                milliseconds: UiConstants.listAnimationDelayMs * index,
              ),
              duration: UiConstants.listAnimationDurationMs.ms,
            )
            .slideX(
              begin: 0.05,
              duration: UiConstants.listAnimationDurationMs.ms,
              curve: AnimCurves.smooth,
            );
      }
    }
    return card;
  }

  /// 釘選/取消釘選論點（掃描頁入口；mode 由 dominant 規則推斷）
  Future<void> _togglePin(String symbol) async {
    HapticFeedback.lightImpact();
    final notifier = ref.read(pinnedThesisProvider.notifier);
    final active = ref
        .read(pinnedThesisProvider)
        .value
        ?.active
        .where((t) => t.symbol == symbol)
        .toList();
    try {
      if (active != null && active.isNotEmpty) {
        await notifier.cancel(active.first.id);
      } else {
        await notifier.pin(symbol);
      }
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// 全域股票搜尋入口 — 開啟 [StockSearchDelegate]，選擇後導航到個股詳情。
  Future<void> _openGlobalSearch(BuildContext context) async {
    final symbol = await showSearch<String?>(
      context: context,
      delegate: StockSearchDelegate(ref),
    );
    if (symbol == null || !context.mounted) return;
    context.push(AppRoutes.stockDetail(symbol));
  }

  /// 設定瀏覽脈絡後開詳情頁——觀察區在畫面「最上面」、訊號區在後
  /// （與 _buildStockListView/_buildStockGrid 的渲染順序一致；審查發現
  /// 反過來會讓觀察區股票的鄰居對不上畫面）
  void _openStockDetail(String symbol) {
    final state = ref.read(scanProvider);
    ref.read(stockBrowsingContextProvider.notifier).set([
      for (final s in state.observations) s.symbol,
      for (final s in state.stocks) s.symbol,
    ]);
    context.push(AppRoutes.stockDetail(symbol));
  }

  /// 顯示股票操作選單（用於 Grid 佈局）
  void _showStockContextMenu(BuildContext context, ScanStockItem stock) {
    showStockPreviewSheet(
      context: context,
      data: StockPreviewData(
        symbol: stock.symbol,
        stockName: stock.stockName,
        latestClose: stock.latestClose,
        priceChange: stock.priceChange,
        score: stock.score,
        trendState: stock.trendState,
        reasons: stock.reasonTypes,
        isInWatchlist: stock.isInWatchlist,
      ),
      onViewDetails: () => _openStockDetail(stock.symbol),
      onToggleWatchlist: () {
        ref.read(scanProvider.notifier).toggleWatchlist(stock.symbol);
      },
    );
  }
}

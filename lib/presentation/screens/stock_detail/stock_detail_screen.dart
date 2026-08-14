import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/presentation/providers/pinned_thesis_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/widgets/stock_nav_bar.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/alerts_tab.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_tab.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_tab.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/insider_tab.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/technical/technical_tab.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/ai_summary_card.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/stock_detail_header.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/frosted_bar.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

/// 個股詳情畫面 - 以分頁顯示完整股票資訊
class StockDetailScreen extends ConsumerStatefulWidget {
  const StockDetailScreen({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scrollController = ScrollController();

  /// 顯示中的 symbol。巡檢換股走 [_swapTo] **原地換**（不重建 route）：
  /// 外框（AppBar/分頁列/導航列）不 remount，只有內容區換資料——避免
  /// pushReplacement 整頁重建的閃屏。選中分頁跨換股保留（巡檢時停在
  /// 籌碼頁連續翻閱）。
  late String _symbol;

  /// 換股載入中的目標（顯示細進度條；載完才切換 [_symbol]，冷載入
  /// 期間保留舊內容不閃 shimmer）
  String? _pendingSymbol;

  @override
  void initState() {
    super.initState();
    _symbol = widget.symbol;
    _tabController = TabController(length: 5, vsync: this);
    Future.microtask(() {
      final notifier = ref.read(stockDetailProvider(widget.symbol).notifier);
      notifier.loadData();
      notifier.loadFundamentals();
    });
  }

  @override
  void didUpdateWidget(covariant StockDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // route 換了 symbol 但重用同一個 State 的少見情況（深連結等），防禦處理
    if (oldWidget.symbol != widget.symbol) {
      _symbol = widget.symbol;
      _pendingSymbol = null;
      Future.microtask(() {
        final notifier = ref.read(stockDetailProvider(widget.symbol).notifier);
        notifier.loadData();
        notifier.loadFundamentals();
      });
    }
  }

  /// 巡檢換股：先載新股資料（舊內容保留在畫面上），載完一次性切換。
  /// 連點時最後的目標勝出（guard 比對 [_pendingSymbol]）。
  Future<void> _swapTo(String target) async {
    if (target == _symbol || target == _pendingSymbol) return;
    setState(() => _pendingSymbol = target);
    final notifier = ref.read(stockDetailProvider(target).notifier);
    await Future.wait([notifier.loadData(), notifier.loadFundamentals()]);
    if (!mounted || _pendingSymbol != target) return;
    setState(() {
      _symbol = target;
      _pendingSymbol = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 只 watch scaffold 需要的欄位，避免 loading flag 變動觸發全頁 rebuild
    final provider = stockDetailProvider(_symbol);
    final isLoading = ref.watch(provider.select((s) => s.loading.isLoading));
    final error = ref.watch(provider.select((s) => s.error));
    final stockName = ref.watch(provider.select((s) => s.stockName));
    final isInWatchlist = ref.watch(provider.select((s) => s.isInWatchlist));
    final priceChangeRaw = ref.watch(provider.select((s) => s.priceChange));
    final theme = Theme.of(context);

    // 依漲跌幅動態漸層
    final priceChange = priceChangeRaw ?? 0;
    final isPositive = priceChange > 0;
    final isNegative = priceChange < 0;

    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        if (isPositive)
          AppTheme.upColor.withValues(alpha: 0.15)
        else if (isNegative)
          AppTheme.downColor.withValues(alpha: 0.15)
        else
          theme.colorScheme.surface,
        theme.colorScheme.surface,
        theme.colorScheme.surface,
      ],
      stops: const [0.0, 0.3, 1.0],
    );

    return Scaffold(
      // 巡檢導航列：從清單（自選/今日/掃描…）進入時提供上一檔/下一檔，
      // _swapTo 原地換股（route 不動 → 返回鍵仍回到來源清單）。搜尋/
      // 深連結進入（不在瀏覽脈絡中）時 neighbors 為 null、整列不顯示。
      bottomNavigationBar: Consumer(
        builder: (context, ref, _) {
          final neighbors = browsingNeighbors(
            ref.watch(stockBrowsingContextProvider),
            _symbol,
          );
          if (neighbors == null) return const SizedBox.shrink();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 換股載入中：細進度條（舊內容保留、不閃 shimmer）
              if (_pendingSymbol != null)
                const LinearProgressIndicator(minHeight: 2),
              StockNavBar(
                prev: neighbors.prev,
                next: neighbors.next,
                position: neighbors.position,
                total: neighbors.total,
                onNavigate: _swapTo,
              ),
            ],
          );
        },
      ),
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: isLoading
            ? const SafeArea(child: StockDetailShimmer())
            : error != null
            ? SafeArea(
                child: ErrorDisplay.isNetworkError(error)
                    ? EmptyStates.networkError(
                        onRetry: () => ref
                            .read(stockDetailProvider(_symbol).notifier)
                            .loadData(),
                      )
                    : EmptyStates.error(
                        message: error,
                        onRetry: () => ref
                            .read(stockDetailProvider(_symbol).notifier)
                            .loadData(),
                      ),
              )
            : NestedScrollView(
                controller: _scrollController,
                headerSliverBuilder: (context, innerBoxScrolled) => [
                  // App Bar（毛玻璃：blur 下方內容，半透質感又不會疊影穿透）
                  SliverAppBar(
                    pinned: true,
                    floating: true,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    flexibleSpace: const FrostedBackground(),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _symbol,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (stockName != null)
                          Text(
                            stockName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    actions: [
                      // 釘選論點（出場層 Phase 2）：mode 由 dominant 規則推斷
                      Consumer(
                        builder: (context, ref, _) {
                          final pinned = ref.watch(
                            pinnedThesisProvider.select(
                              (s) => s.value?.isPinned(_symbol) ?? false,
                            ),
                          );
                          return IconButton(
                            tooltip: 'thesis.pinTooltip'.tr(),
                            icon: Icon(
                              pinned ? Icons.push_pin : Icons.push_pin_outlined,
                            ),
                            onPressed: () async {
                              final notifier = ref.read(
                                pinnedThesisProvider.notifier,
                              );
                              final active = ref
                                  .read(pinnedThesisProvider)
                                  .value
                                  ?.active
                                  .where((t) => t.symbol == _symbol)
                                  .toList();
                              try {
                                if (active != null && active.isNotEmpty) {
                                  await notifier.cancel(active.first.id);
                                } else {
                                  await notifier.pin(_symbol);
                                }
                              } on StateError catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message)),
                                );
                              }
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.compare_arrows),
                        onPressed: () {
                          context.push(AppRoutes.compare, extra: [_symbol]);
                        },
                        tooltip: 'comparison.compare'.tr(),
                      ),
                      IconButton(
                        icon: Icon(
                          isInWatchlist ? Icons.star : Icons.star_border,
                          color: isInWatchlist ? Colors.amber : null,
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(stockDetailProvider(_symbol).notifier)
                                .toggleWatchlist();
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is StateError ? e.message : '$e',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        tooltip: isInWatchlist
                            ? 'stock.removeFromWatchlist'.tr()
                            : 'stock.addToWatchlist'.tr(),
                      ),
                    ],
                  ),

                  // 股票標題
                  SliverToBoxAdapter(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final headerData = ref.watch(
                          provider.select((s) => StockHeaderData.fromState(s)),
                        );
                        return StockDetailHeader(
                          data: headerData,
                          symbol: _symbol,
                        );
                      },
                    ),
                  ),

                  // AI 智慧分析摘要
                  SliverToBoxAdapter(child: AiSummaryCard(symbol: _symbol)),

                  // Tab Bar（毛玻璃，與 App Bar 一致）
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      tabController: _tabController,
                      theme: theme,
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    // key 綁 symbol：Chip/Insider/Fundamentals 是 initState
                    // 載入型，原地換股需 remount 才會載新股資料
                    TechnicalTab(
                      key: ValueKey('tech-$_symbol'),
                      symbol: _symbol,
                    ),
                    ChipTab(key: ValueKey('chip-$_symbol'), symbol: _symbol),
                    InsiderTab(
                      key: ValueKey('insider-$_symbol'),
                      symbol: _symbol,
                    ),
                    FundamentalsTab(
                      key: ValueKey('fund-$_symbol'),
                      symbol: _symbol,
                    ),
                    AlertsTab(
                      key: ValueKey('alerts-$_symbol'),
                      symbol: _symbol,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 固定式 Tab bar 的 SliverPersistentHeaderDelegate
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate({required this.tabController, required this.theme});

  final TabController tabController;
  final ThemeData theme;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return FrostedBackground(
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicatorColor: theme.colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: DesignTokens.fontSizeMd,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: DesignTokens.fontSizeMd,
        ),
        tabs: [
          Tab(text: 'stockDetail.tabTechnical'.tr()),
          Tab(text: 'stockDetail.tabChip'.tr()),
          Tab(text: 'stockDetail.tabInsider'.tr()),
          Tab(text: 'stockDetail.tabFundamentals'.tr()),
          Tab(text: 'stockDetail.tabAlerts'.tr()),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    return tabController != oldDelegate.tabController ||
        theme != oldDelegate.theme;
  }
}

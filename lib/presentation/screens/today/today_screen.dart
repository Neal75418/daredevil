import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/presentation/screens/today/widgets/revenue_filing_entry.dart';
import 'package:daredevil/presentation/screens/today/widgets/quarterly_filing_entry.dart';
import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/domain/models/signal_names.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/responsive_helper.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/selected_mode_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/presentation/providers/update_history_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/api_rate_limit_dialog.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/frosted_bar.dart';
import 'package:daredevil/presentation/widgets/industry_ranking_section.dart';
import 'package:daredevil/presentation/widgets/update_history_sheet.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/providers/pinned_thesis_provider.dart';
import 'package:daredevil/presentation/widgets/pinned_thesis_section.dart';
import 'package:daredevil/presentation/widgets/stock_card.dart';
import 'package:daredevil/presentation/widgets/stock_search_delegate.dart';
import 'package:daredevil/presentation/widgets/stock_preview_sheet.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';
import 'package:daredevil/presentation/widgets/update_progress_banner.dart';

/// 今日畫面 - 顯示每日推薦
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// 起漲候選「未確認上升趨勢」艙是否展開(預設收合;切 mode 不重置,
  /// 使用者的展開偏好在同一次瀏覽內保留)
  bool _showTrendGated = false;

  @override
  void initState() {
    super.initState();
    // 首次建置時載入資料
    Future.microtask(() {
      ref.read(todayProvider.notifier).loadData();
      ref.read(watchlistProvider.notifier).loadData();
      ref.read(marketOverviewProvider.notifier).loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用 selector 分離 loading/error 狀態，避免 updateProgress 變更時重建整個畫面
    final isLoading = ref.watch(todayProvider.select((s) => s.isLoading));
    final error = ref.watch(todayProvider.select((s) => s.error));
    // 「有內容可顯示」改用 3-mode 同源判斷（取代已退役的 todayProvider.recommendations）：
    // 用於決定 loadData 出錯時要顯示全屏 error 還是保留現有內容（起漲候選 tab 有資料即視為有內容）。
    final hasRecommendations = ref.watch(
      modeRecommendationsProvider(
        ScoringMode.momentumEntry,
      ).select((async) => async.asData?.value.isNotEmpty ?? false),
    );
    // 使用 selector 只監聽 watchlist 的 symbols，避免不必要的重建
    final watchlistSymbols = ref.watch(
      watchlistProvider.select((s) => s.watchedSymbols),
    );

    return Scaffold(
      body: ThemedRefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(todayProvider.notifier).loadData(),
            ref.read(marketOverviewProvider.notifier).loadData(),
          ]);
        },
        child: isLoading
            ? const StockListShimmer(itemCount: 5)
            : error != null && !hasRecommendations
            ? _buildError(error)
            : _buildContent(watchlistSymbols),
      ),
    );
  }

  Widget _buildError(String error) {
    void onRetry() => ref.read(todayProvider.notifier).loadData();
    if (ErrorDisplay.isNetworkError(error)) {
      return EmptyStates.networkError(onRetry: onRetry);
    }
    return EmptyStates.error(message: error, onRetry: onRetry);
  }

  /// 響應式推薦清單：手機使用 SliverList，平板/桌面使用 SliverGrid
  Widget _buildRecommendationsList(
    BuildContext context,
    List<ModeRecommendation> recommendations,
    Set<String> watchlistSymbols,
    bool showLimitMarkers, {
    required ScoringMode mode,
  }) {
    // 起漲候選分艙(2026-08-12,顯示層):tab 承諾「上升趨勢中」,但實況
    // 11 檔裡 8 檔 trendState=DOWN——未確認上升趨勢的收合淡化,不動評分。
    // 只有 momentumEntry 分艙:強勢觀察本來就強、回檔觀察本來就在回。
    if (mode == ScoringMode.momentumEntry) {
      final split = splitByTrendGate(recommendations);
      if (split.gated.isNotEmpty) {
        // 前艙全空(全 DOWN 日)強制展開:否則畫面只剩一條收合列,像壞掉
        // ——8/12 實況 11 檔裡 8 檔 DOWN,全 DOWN 日並不遙遠(2026-08-13
        // 審查 3,實測空畫面)。此時收合列不可再點(收起來就什麼都沒有)。
        final locked = split.qualified.isEmpty;
        final expanded = _showTrendGated || locked;
        // 瀏覽脈絡=「當下可見的集合」:收合時滑 3 檔、展開時滑全部——
        // 若脈絡只給渲染子清單,展開後從前艙滑到艙界會無聲斷頭(審查 4)
        final browsingContext = expanded
            ? [...split.qualified, ...split.gated]
            : split.qualified;
        return SliverMainAxisGroup(
          slivers: [
            _buildCardsSliver(
              context,
              split.qualified,
              watchlistSymbols,
              showLimitMarkers,
              browsingContext: browsingContext,
            ),
            _buildTrendGateHeader(
              context,
              split.gated.length,
              expanded: expanded,
              locked: locked,
            ),
            if (expanded)
              _buildCardsSliver(
                context,
                split.gated,
                watchlistSymbols,
                showLimitMarkers,
                dimmed: true,
                browsingContext: browsingContext,
              ),
          ],
        );
      }
    }
    return _buildCardsSliver(
      context,
      recommendations,
      watchlistSymbols,
      showLimitMarkers,
    );
  }

  /// 「未確認上升趨勢」收合列(點擊展開/收合;[locked] 時不可收合)
  Widget _buildTrendGateHeader(
    BuildContext context,
    int count, {
    required bool expanded,
    required bool locked,
  }) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.responsiveHorizontalPadding,
          vertical: DesignTokens.spacing8,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          onTap: locked
              ? null
              : () => setState(() => _showTrendGated = !_showTrendGated),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spacing8,
              horizontal: DesignTokens.spacing8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.trending_flat,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Expanded(
                  child: Text(
                    'today.trendGateCollapsed'.tr(
                      namedArgs: {'count': '$count'},
                    ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!locked)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardsSliver(
    BuildContext context,
    List<ModeRecommendation> recommendations,
    Set<String> watchlistSymbols,
    bool showLimitMarkers, {
    bool dimmed = false,
    List<ModeRecommendation>? browsingContext,
  }) {
    final columns = context.responsiveGridColumns;
    final useGrid = columns > 1;
    final padding = context.responsiveHorizontalPadding;
    final spacing = context.responsiveCardSpacing;
    // 詳情頁左右滑的脈絡:預設=本清單;分艙時由呼叫端給「可見集合」
    final ctx = browsingContext ?? recommendations;

    Widget item(BuildContext context, int index) {
      final card = _buildRecommendationCard(
        context,
        recommendations,
        watchlistSymbols,
        index,
        showLimitMarkers,
        browsingContext: ctx,
      );
      // 淡化與族群轉向的 0 檔卡同語彙(同 0.45):掃過去自然跳過,點開仍可互動
      return dimmed ? Opacity(opacity: 0.45, child: card) : card;
    }

    if (useGrid) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: DesignTokens.stockCardHeight,
          ),
          itemCount: recommendations.length,
          itemBuilder: item,
        ),
      );
    }

    return SliverList.builder(
      itemCount: recommendations.length,
      itemBuilder: item,
    );
  }

  /// 建立推薦卡片([browsingContext] = 詳情頁左右滑的清單,預設同渲染清單)
  /// MA 階段警示條(跌破/站回共用)
  ///
  /// 兩條刻意走同一個 builder:2026-07-31 只做了跌破,站回那半漏了一個月才
  /// 補上——分開寫就是讓其中一半悄悄落後的典型結構。無觸發時完全不渲染。
  Widget _maStageBanner({
    required ThemeData theme,
    required Set<String> codes,
    required String labelKey,
    required IconData icon,
    required Color color,
  }) {
    return SliverToBoxAdapter(
      child: Consumer(
        builder: (context, ref, _) {
          final items = ref.watch(watchlistProvider).items;
          final hit = items
              .where((i) => i.reasons.any(codes.contains))
              .toList();
          if (hit.isEmpty) return const SizedBox.shrink();
          final names = hit.map((i) => i.stockName ?? i.symbol).join('、');
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing4,
              DesignTokens.spacing16,
              DesignTokens.spacing4,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing12,
                vertical: DesignTokens.spacing8,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: DesignTokens.spacing8),
                  Expanded(
                    child: Text(
                      labelKey.tr(
                        namedArgs: {'count': '${hit.length}', 'names': names},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecommendationCard(
    BuildContext context,
    List<ModeRecommendation> recommendations,
    Set<String> watchlistSymbols,
    int index,
    bool showLimitMarkers, {
    List<ModeRecommendation>? browsingContext,
  }) {
    final rec = recommendations[index];
    final navContext = browsingContext ?? recommendations;
    final isInWatchlist = watchlistSymbols.contains(rec.symbol);
    final columns = context.responsiveGridColumns;

    final card = RepaintBoundary(
      key: ValueKey('${rec.symbol}_$isInWatchlist'),
      // Consumer 隔離 pinned 狀態：釘選 toggle 只重建這張卡，
      // 不 mark 整個 TodayScreen dirty（同檔 AppBar/橫幅等 Consumer 同慣例）
      child: Consumer(
        builder: (context, cardRef, _) => StockCard(
          symbol: rec.symbol,
          stockName: rec.stockName,
          market: rec.market,
          latestClose: rec.latestClose,
          priceChange: rec.priceChange,
          // primary score 給 fallback / preview sheet 用（StockCard 內 dualScore
          // 不為 null 時會優先顯示雙 column）
          score: rec.modeScoreShort,
          dualScore: (rec.modeScoreShort, rec.modeScoreLong),
          reasons: rec.reasonTypes,
          warningReasons: rec.warningReasons,
          trendState: rec.trendState,
          recentPrices: rec.recentPrices,
          isInWatchlist: isInWatchlist,
          showLimitMarkers: showLimitMarkers,
          pinned: cardRef.watch(
            pinnedThesisProvider.select(
              (s) => s.value?.isPinned(rec.symbol) ?? false,
            ),
          ),
          onPinToggle: () => _togglePin(rec.symbol),
          onTap: () {
            HapticFeedback.lightImpact();
            _openStockDetail(navContext, rec.symbol);
          },
          onLongPress: () {
            showStockPreviewSheet(
              context: context,
              data: StockPreviewData(
                symbol: rec.symbol,
                stockName: rec.stockName,
                latestClose: rec.latestClose,
                priceChange: rec.priceChange,
                score: rec.modeScoreShort,
                trendState: rec.trendState,
                reasons: rec.reasonTypes,
                isInWatchlist: isInWatchlist,
              ),
              onViewDetails: () => _openStockDetail(navContext, rec.symbol),
              onToggleWatchlist: () =>
                  _toggleWatchlist(rec.symbol, isInWatchlist),
            );
          },
          onWatchlistTap: () => _toggleWatchlist(rec.symbol, isInWatchlist),
        ),
      ),
    );

    // 前 10/20 筆項目使用交錯進場動畫（Grid 顯示更多）
    final animateCount = columns > 1 ? 20 : 10;
    final animateDelay = columns > 1 ? 30 : 50;

    if (index < animateCount) {
      return card
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: animateDelay * index),
            duration: columns > 1
                ? AnimDurations.normal
                : AnimDurations.moderate,
          )
          .then()
          .custom(
            builder: (context, value, child) {
              if (columns > 1) {
                // Grid：縮放動畫
                return Transform.scale(
                  scale: 0.95 + 0.05 * value,
                  child: child,
                );
              }
              // List：水平滑入
              return Transform.translate(
                offset: Offset(20 * (1 - value), 0),
                child: child,
              );
            },
            duration: columns > 1
                ? AnimDurations.normal
                : AnimDurations.moderate,
            curve: AnimCurves.smooth,
          );
    }
    return card;
  }

  Widget _buildContent(Set<String> watchlistSymbols) {
    final theme = Theme.of(context);
    final showLimitMarkers = ref.watch(
      settingsProvider.select((s) => s.limitAlerts),
    );

    return CustomScrollView(
      slivers: [
        // App Bar（Consumer 隔離 isUpdating 狀態，避免進度更新時重建推薦清單）
        Consumer(
          builder: (context, ref, _) {
            final isUpdating = ref.watch(
              todayProvider.select((s) => s.isUpdating),
            );
            return SliverAppBar(
              pinned: true,
              floating: true,
              expandedHeight: 0, // Standard height
              // 毛玻璃 header：blur 下方內容，半透質感又不會疊影穿透。
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: const FrostedBackground(),
              title: Text(
                S.appName,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              actions: [
                if (isUpdating)
                  const Padding(
                    padding: EdgeInsets.all(DesignTokens.spacing12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _runUpdate,
                    tooltip: S.todayUpdateData,
                  ),
                // 全域搜尋（動線審查：「隨手查一檔」是高頻動作，
                // 不該只有掃描頁有入口）
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'stockSearch.tooltip'.tr(),
                  onPressed: () async {
                    final symbol = await showSearch<String?>(
                      context: context,
                      delegate: StockSearchDelegate(ref),
                    );
                    if (symbol == null || !context.mounted) return;
                    context.push(AppRoutes.stockDetail(symbol));
                  },
                ),
                // 鈴鐺 badge = 未封存的論點失效數（稀有事件的事件驅動提醒）
                Consumer(
                  builder: (context, ref, _) {
                    final invalidatedCount = ref.watch(
                      pinnedThesisProvider.select(
                        (s) => s.value?.invalidated.length ?? 0,
                      ),
                    );
                    return IconButton(
                      icon: Badge(
                        isLabelVisible: invalidatedCount > 0,
                        label: Text('$invalidatedCount'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                      onPressed: () => context.push(AppRoutes.alerts),
                      tooltip: S.todayPriceAlert,
                    );
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'scan.more'.tr(),
                  onSelected: (value) {
                    HapticFeedback.selectionClick();
                    switch (value) {
                      case 'news':
                        context.push(AppRoutes.news);
                      case 'settings':
                        context.push(AppRoutes.settings);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'news',
                      child: Row(
                        children: [
                          const Icon(Icons.newspaper_outlined, size: 20),
                          const SizedBox(width: DesignTokens.spacing12),
                          Text('nav.news'.tr()),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          const Icon(Icons.settings_outlined, size: 20),
                          const SizedBox(width: DesignTokens.spacing12),
                          Text(S.settings),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),

        // 更新進度橫幅（Consumer 隔離 updateProgress 頻繁更新）
        Consumer(
          builder: (context, ref, _) {
            final isUpdating = ref.watch(
              todayProvider.select((s) => s.isUpdating),
            );
            final updateProgress = ref.watch(
              todayProvider.select((s) => s.updateProgress),
            );
            if (isUpdating && updateProgress != null) {
              return SliverToBoxAdapter(
                child: UpdateProgressBanner(progress: updateProgress),
              );
            }
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          },
        ),

        // 最後更新時間 + 資料日期（Consumer 隔離日期狀態）
        //
        // 2026-06-19：最後更新時間整段 tappable，彈出 UpdateHistorySheet
        // 顯示最近 30 筆 update_run，含失敗 / partial 狀態與 message。
        // 上次 run 不是 SUCCESS 時 timestamp 旁有橘 / 紅 dot 提示。
        Consumer(
          builder: (context, ref, _) {
            final lastUpdate = ref.watch(
              todayProvider.select((s) => s.lastUpdate),
            );
            final dataDate = ref.watch(todayProvider.select((s) => s.dataDate));
            final historyAsync = ref.watch(updateHistoryProvider);
            if (lastUpdate == null && dataDate == null) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            // loading / error 時讓 badge 維持上次的 data —— 避免「狀態
            // 突然消失看起來像問題自己好了」的視覺誤導
            final latestRows = historyAsync.maybeWhen(
              data: (r) => r,
              orElse: () => null,
            );
            final latestStatus = (latestRows == null || latestRows.isEmpty)
                ? null
                : latestRows.first.status.toUpperCase();
            // 用有形狀的 Icon 取代純色 Container — color-blind user 看得出
            // 區別，screen reader 也能用 semanticLabel 念出來
            final ({IconData icon, Color color, String labelKey})? statusBadge =
                switch (latestStatus) {
                  'SUCCESS' => null, // 健康狀態不顯示，減少 noise
                  'PARTIAL' => (
                    icon: Icons.error_outline,
                    color: DesignTokens.warningColor(theme),
                    labelKey: 'updateHistory.statusPartial',
                  ),
                  'FAILED' => (
                    icon: Icons.cancel,
                    color: theme.colorScheme.error,
                    labelKey: 'updateHistory.statusFailed',
                  ),
                  _ => null,
                };
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing16,
                  DesignTokens.spacing8,
                  DesignTokens.spacing16,
                  DesignTokens.spacing4,
                ),
                child: Semantics(
                  button: true,
                  label: 'updateHistory.openHistoryHint'.tr(),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => UpdateHistorySheet.show(context),
                    // Vertical padding spacing12 = 12 + 14 (text) + 12 = 38pt
                    // 還差最少 6pt 到 iOS 44pt，所以再加 spacing4 = 44pt 整。
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacing8,
                        vertical:
                            DesignTokens.spacing12 + DesignTokens.spacing4 / 2,
                      ),
                      child: Wrap(
                        spacing: DesignTokens.spacing8,
                        runSpacing: DesignTokens.spacing4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (lastUpdate != null)
                            Text(
                              S.todayLastUpdate(S.dateFormat(lastUpdate)),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (lastUpdate != null && statusBadge != null)
                            Icon(
                              statusBadge.icon,
                              size: 14,
                              color: statusBadge.color,
                              semanticLabel: statusBadge.labelKey.tr(),
                            ),
                          if (lastUpdate != null && dataDate != null)
                            Text(
                              '·',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (dataDate != null)
                            Text(
                              S.todayDataDate(_formatDataDate(dataDate)),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        // 自選 MA 階段警示條:跌破(紅,2026-07-31 四階段風控)與站回
        // (綠,2026-08-21)。開 app 第一屏直接撞見——風控不能靠記得去掃描頁
        // 看,機會也一樣。兩條各自獨立渲染,同日都發生時並存不互相吃掉。
        //
        // 站回這半補得晚:RECLAIM_MA20/60 訊號一直有算、有落庫、有分數,
        // 卻沒有任何地方顯示。實機 2026-08-21 台積電站回季線,第一屏全無提示。
        _maStageBanner(
          theme: theme,
          codes: SignalName.maStageBreak,
          labelKey: 'today.watchlistMaBreak',
          icon: Icons.trending_down,
          color: theme.colorScheme.error,
        ),
        _maStageBanner(
          theme: theme,
          codes: SignalName.maStageReclaim,
          labelKey: 'today.watchlistMaReclaim',
          icon: Icons.trending_up_rounded,
          color: AppTheme.upColor,
        ),

        // 大盤總覽卡片（獨立 Consumer 隔離 market data rebuild）
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, _) {
              final marketState = ref.watch(marketOverviewProvider);
              if (!marketState.hasData && !marketState.isLoading) {
                if (marketState.error != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacing16,
                    ),
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(marketState.error!),
                        trailing: TextButton(
                          onPressed: () => ref
                              .read(marketOverviewProvider.notifier)
                              .loadData(),
                          child: Text('common.retry'.tr()),
                        ),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              return MarketDashboard(state: marketState);
            },
          ),
        ),

        // 族群排行（L1：族群決定 80%）— 大盤 context 之後、個股推薦之前。
        // 空資料 / 載入中自動收起，不佔版面。
        const SliverToBoxAdapter(child: IndustryRankingSection()),

        // 月營收公布中入口(僅每月上旬顯示;窗口外/無資料自動收起)
        const SliverToBoxAdapter(child: RevenueFilingEntrySection()),
        const SliverToBoxAdapter(child: QuarterlyFilingEntrySection()),

        // 部分錯誤橫幅（有推薦資料但重新整理失敗時顯示）
        Consumer(
          builder: (context, ref, _) {
            final error = ref.watch(todayProvider.select((s) => s.error));
            if (error == null) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text(error),
                actions: [
                  TextButton(
                    onPressed: () =>
                        ref.read(todayProvider.notifier).loadData(),
                    child: Text('common.retry'.tr()),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(todayProvider.notifier).clearError(),
                    child: Text('common.dismiss'.tr()),
                  ),
                ],
              ),
            );
          },
        ),

        // 釘選論點追蹤區（出場層）：一行摘要 strip、失效時轉紅自動展開。
        // 置於推薦標題前——你的下注單優先於今日候選，但平日只佔一行。
        const SliverToBoxAdapter(child: PinnedThesisSection()),

        // 推薦清單 header — 動態顯示「今日推薦 (N 檔)」
        //
        // **2026-06-20**：N 跟著該 mode tab 通過 eligibility filter 的清單長度走、
        // 不是固定「Top 20」。Mode A 通常 15-30、Mode B 飽和 30、Mode C 0-10。
        // 動態 N 讓 user 一眼知道「今天市場有幾檔機會」、不被舊 Top 20 字面誤導。
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(selectedModeProvider);
              final asyncRecs = ref.watch(modeRecommendationsProvider(mode));
              // loading / error 時用無 count 版本、避免「Top 0」尷尬
              final title = asyncRecs.maybeWhen(
                data: (recs) => S.todayTop10(recs.length),
                orElse: () => S.todayTop10Loading,
              );
              return SectionHeader(title: title, icon: Icons.trending_up);
            },
          ),
        ),

        // 2026-06-19：3-tab Mode UI 取代 dual-horizon SegmentedButton
        //
        // 動機：短線/長線兩 tab 在現階段 calibration 不夠成熟、95%+ 內容相同、
        // user 看不出真實差異；改成 mode-based 3 tab（起漲/強勢/弱勢）對應
        // user 真實的 3 種觀察心智。5D 跟 60D 雙 score 改在 StockCard 內並排
        // 顯示，user 一眼看到兩個 timeframe 強弱對比。
        //
        // horizon 選擇器/provider 已於 2026-06 移除：scan 定死 60D、stock
        // detail / comparison 定死 5D。Today 內 sort 預設按 5D abs(score) DESC。
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Consumer(
              builder: (context, ref, _) {
                final mode = ref.watch(selectedModeProvider);
                // 每個 mode 一行說明，解新用戶「該用哪個」的困惑
                final descKey = switch (mode) {
                  ScoringMode.momentumEntry => 'scoringMode.momentumEntryDesc',
                  ScoringMode.strengthObserve =>
                    'scoringMode.strengthObserveDesc',
                  ScoringMode.weaknessObserve =>
                    'scoringMode.weaknessObserveDesc',
                  _ => '',
                };
                return Column(
                  children: [
                    SegmentedButton<ScoringMode>(
                      segments: [
                        ButtonSegment(
                          value: ScoringMode.momentumEntry,
                          label: Text('scoringMode.momentumEntry'.tr()),
                          icon: const Icon(Icons.trending_up, size: 18),
                        ),
                        ButtonSegment(
                          value: ScoringMode.strengthObserve,
                          label: Text('scoringMode.strengthObserve'.tr()),
                          icon: const Icon(Icons.bolt, size: 18),
                        ),
                        ButtonSegment(
                          value: ScoringMode.weaknessObserve,
                          label: Text('scoringMode.weaknessObserve'.tr()),
                          icon: const Icon(Icons.warning_amber, size: 18),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (set) {
                        ref
                            .read(selectedModeProvider.notifier)
                            .select(set.first);
                      },
                    ),
                    if (descKey.isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spacing8),
                      Text(
                        descKey.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),

        // 推薦清單 — async（FutureProvider.family）
        Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(selectedModeProvider);
            final asyncRecs = ref.watch(modeRecommendationsProvider(mode));
            return asyncRecs.when(
              data: (recommendations) {
                if (recommendations.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStates.noRecommendations(onRefresh: _runUpdate),
                  );
                }
                return _buildRecommendationsList(
                  context,
                  recommendations,
                  watchlistSymbols,
                  showLimitMarkers,
                  mode: mode,
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              // 2026-07-30 審查:裸 Text('Error: ...') 升級成與畫面頂層一致
              // 的可重試錯誤狀態——mode 推薦掛掉時 user 原本只能重開 app。
              error: (e, _) {
                void onRetry() =>
                    ref.invalidate(modeRecommendationsProvider(mode));
                final msg = ErrorDisplay.message(e);
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorDisplay.isNetworkError(msg)
                      ? EmptyStates.networkError(onRetry: onRetry)
                      : EmptyStates.error(message: msg, onRetry: onRetry),
                );
              },
            );
          },
        ),

        // 底部間距
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  /// 設定瀏覽脈絡（當前 mode tab 的推薦順序）後開詳情頁
  void _openStockDetail(List<ModeRecommendation> recs, String symbol) {
    ref.read(stockBrowsingContextProvider.notifier).set([
      for (final r in recs) r.symbol,
    ]);
    context.push(AppRoutes.stockDetail(symbol));
  }

  /// 釘選/取消釘選論點（出場層 Phase 2）。mode 用當前 tab。
  Future<void> _togglePin(String symbol) async {
    HapticFeedback.lightImpact();
    final notifier = ref.read(pinnedThesisProvider.notifier);
    final state = ref.read(pinnedThesisProvider).value;
    final existing = state?.active.where((t) => t.symbol == symbol).toList();

    try {
      if (existing != null && existing.isNotEmpty) {
        await notifier.cancel(existing.first.id);
      } else {
        final mode = switch (ref.read(selectedModeProvider)) {
          ScoringMode.momentumEntry => 'momentum',
          ScoringMode.weaknessObserve => 'pullback',
          _ => 'strength',
        };
        await notifier.pin(symbol, mode: mode);
      }
    } on StateError catch (e) {
      if (!mounted) return;
      _showSnackBar(e.message, isError: true);
    }
  }

  Future<void> _toggleWatchlist(
    String symbol,
    bool currentlyInWatchlist,
  ) async {
    HapticFeedback.lightImpact();
    final notifier = ref.read(watchlistProvider.notifier);

    // 清除現有的 SnackBar，避免堆積（與 watchlist_screen 一致）
    ScaffoldMessenger.of(context).clearSnackBars();

    if (currentlyInWatchlist) {
      final success = await notifier.removeStock(symbol);
      if (!mounted) return;
      if (!success) {
        final watchlistState = ref.read(watchlistProvider);
        _showSnackBar(
          watchlistState.error ?? S.watchlistRemoveFailed,
          isError: true,
        );
      } else {
        HapticFeedback.mediumImpact();
        final messenger = ScaffoldMessenger.of(context);
        final errorColor = Theme.of(context).colorScheme.error;
        _showSnackBar(
          S.watchlistRemoved(symbol),
          action: SnackBarAction(
            label: S.watchlistUndo,
            onPressed: () {
              notifier.restoreStock(symbol).then((_) {
                // restoreStock 失敗時會設 watchlistProvider.state.error
                final error = ref.read(watchlistProvider).error;
                if (error != null && mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(error),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: errorColor,
                    ),
                  );
                }
              });
            },
          ),
          duration: const Duration(seconds: ApiConfig.longMessageDurationSec),
        );
      }
    } else {
      final success = await notifier.addStock(symbol);
      if (mounted) {
        if (success) HapticFeedback.mediumImpact();
        _showSnackBar(
          success ? S.watchlistAddedToWatchlist(symbol) : S.watchlistAddFailed,
          duration: const Duration(seconds: ApiConfig.shortMessageDurationSec),
          isError: !success,
        );
      }
    }
  }

  /// 在畫面重繪後顯示 SnackBar，避免生命週期問題
  void _showSnackBar(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(
      seconds: ApiConfig.shortMessageDurationSec,
    ),
    bool isError = false,
  }) {
    // 使用畫面回呼確保 SnackBar 在重建後顯示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: duration,
          action: action,
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
          showCloseIcon: action != null, // 有動作按鈕時顯示關閉圖示
          dismissDirection: DismissDirection.horizontal,
        ),
      );
    });
  }

  Future<void> _runUpdate() async {
    try {
      final result = await ref.read(todayProvider.notifier).runUpdate();

      if (mounted) {
        if (result.hasRateLimitError) {
          showApiRateLimitDialog(
            context,
            finMind: result.errors.any(isFinMindRateLimit),
          );
        }

        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.summary),
            behavior: SnackBarBehavior.floating,
            backgroundColor: result.hasWarnings
                ? theme.colorScheme.tertiary
                : null,
            action: result.hasWarnings
                ? SnackBarAction(
                    label: S.detail,
                    textColor: theme.colorScheme.onTertiary,
                    onPressed: () => _showWarningDetails(result.errors),
                  )
                : null,
            showCloseIcon: result.hasWarnings,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e is RateLimitException) {
          showApiRateLimitDialog(
            context,
            finMind: isFinMindRateLimit(e.toString()),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.todayUpdateFailed(ErrorDisplay.message(e))),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatDataDate(DateTime date) {
    final now = DateTime.now();
    final today = DateContext.normalize(now);
    final dataDay = DateContext.normalize(date);

    if (dataDay == today) {
      return S.todayDataToday;
    } else if (dataDay == today.subtract(const Duration(days: 1))) {
      return S.todayDataYesterday;
    } else {
      return '${date.month}/${date.day}';
    }
  }

  void _showWarningDetails(List<String> warnings) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.tertiary,
          size: 48,
        ),
        title: Text(S.todayWarningDetail),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.todayWarningItems),
            const SizedBox(height: DesignTokens.spacing8),
            ...warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacing4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(w, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
  }
}

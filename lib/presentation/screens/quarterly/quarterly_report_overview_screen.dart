import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';
import 'package:daredevil/core/utils/quarterly_filing_calendar.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/data/database/dao/quarterly_report_dao.dart';
import 'package:daredevil/presentation/providers/quarterly_report_overview_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/growth_bar_cell.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

/// 季報總覽——資料中最新一季的**完整**已申報清單。
///
/// 設計沿月營收總覽(2026-08-05 四輪討論定稿的同一語言):清單累積、
/// 完整、不被策展裁剪——排序與過濾都是使用者主動操作,預設顯示全量。
/// 公布期(4~5/7~8/10~11/1~3 月)清單逐日增長,頂部進度標明樣本範圍;
/// 期限後即為該季完整總表。
///
/// 與月營收的差異只有欄位語意:EPS(本期/去年同期,累計制)+淨利,
/// 「轉盈」取代「創高」當亮點徽章。
class QuarterlyReportOverviewScreen extends ConsumerStatefulWidget {
  const QuarterlyReportOverviewScreen({super.key});

  @override
  ConsumerState<QuarterlyReportOverviewScreen> createState() =>
      _QuarterlyReportOverviewScreenState();
}

class _QuarterlyReportOverviewScreenState
    extends ConsumerState<QuarterlyReportOverviewScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(quarterlyReportOverviewProvider.notifier).loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quarterlyReportOverviewProvider);
    final watchlistSymbols = ref.watch(
      watchlistProvider.select((s) => s.watchedSymbols),
    );
    final theme = Theme.of(context);
    final overview = state.overview;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('quarterlyOverview.title'.tr()),
            if (overview != null)
              Text(
                'quarterlyOverview.quarterLabel'.tr(
                  namedArgs: {
                    'year': '${overview.year}',
                    'quarter': '${overview.quarter}',
                  },
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      // 桌面寬視窗限寬置中(2026-08-05 營收頁實機回饋的同一課)
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.tableMaxWidth,
          ),
          child: state.isLoading && overview == null
              ? const GenericListShimmer(itemCount: 10)
              : state.error != null && overview == null
              ? EmptyState(icon: Icons.error_outline, title: state.error!)
              : overview == null
              ? EmptyState(
                  icon: Icons.request_quote_outlined,
                  title: 'quarterlyOverview.empty'.tr(),
                )
              : _buildList(state, overview, watchlistSymbols),
        ),
      ),
    );
  }

  Widget _buildList(
    QuarterlyReportOverviewState state,
    QuarterlyReportOverview overview,
    Set<String> watchlistSymbols,
  ) {
    final theme = Theme.of(context);
    final rows = state.visibleRows(watchlistSymbols);
    // 背景條滿條基準=可見清單 |EPS 年增差值| 的 p95(重尾馴服,見
    // GrowthBarCell.barScale;換排序/過濾自動重校)
    final maxAbsDelta = GrowthBarCell.barScale(rows.map((r) => r.epsYoyDelta));

    return ThemedRefreshIndicator(
      onRefresh: () =>
          ref.read(quarterlyReportOverviewProvider.notifier).loadData(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildProgressHeader(overview)),
          SliverToBoxAdapter(child: _buildControls(state)),
          SliverToBoxAdapter(child: _buildColumnHeader(theme)),
          if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: 'quarterlyOverview.noMatch'.tr(),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing24),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => _buildRow(
                  theme,
                  rows[index],
                  watchlistSymbols,
                  maxAbsDelta,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 公布期進度(同營收頁:只列真實可知的已公布家數,沒有分母)。
  ///
  /// 「公布中」須同時滿足:申報窗口內 **且** 顯示的季=窗口對應季——
  /// 否則窗口首日同步前,上季完整表會被標成「公布中」。
  Widget _buildProgressHeader(QuarterlyReportOverview overview) {
    final theme = Theme.of(context);
    final twseFiled = overview.filedByMarket[MarketCode.twse] ?? 0;
    final tpexFiled = overview.filedByMarket[MarketCode.tpex] ?? 0;
    final filed = twseFiled + tpexFiled;
    final expected = QuarterlyFilingCalendar.expectedFilingQuarter(
      TaiwanTime.now(),
    );
    final inProgress =
        expected != null &&
        overview.year == expected.year &&
        overview.quarter == expected.quarter;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing12,
        DesignTokens.spacing16,
        0,
      ),
      child: Text(
        inProgress
            ? 'quarterlyOverview.progressFiling'.tr(
                namedArgs: {
                  'twseFiled': '$twseFiled',
                  'tpexFiled': '$tpexFiled',
                },
              )
            : 'quarterlyOverview.progressComplete'.tr(
                namedArgs: {'count': '$filed'},
              ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildControls(QuarterlyReportOverviewState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DesignTokens.spacing8,
            children: [
              for (final f in QuarterlyFilter.values)
                FilterChip(
                  label: Text('quarterlyOverview.filter.${f.name}'.tr()),
                  selected: state.filter == f,
                  onSelected: (_) => ref
                      .read(quarterlyReportOverviewProvider.notifier)
                      .setFilter(f),
                ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing8),
          // 橫向捲動(2026-08-13):長語系(en)在手機寬會溢出/折行
          // ——與 SectionHeader trailing 同讓步策略,空間不夠自己捲
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<QuarterlySortBy>(
              segments: [
                for (final s in QuarterlySortBy.values)
                  ButtonSegment(
                    value: s,
                    label: Text('quarterlyOverview.sort.${s.name}'.tr()),
                  ),
              ],
              selected: {state.sortBy},
              onSelectionChanged: (selection) => ref
                  .read(quarterlyReportOverviewProvider.notifier)
                  .setSortBy(selection.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    ThemeData theme,
    QuarterlyReportOverviewRow row,
    Set<String> watchlistSymbols,
    double maxAbsDelta,
  ) {
    final isWatched = watchlistSymbols.contains(row.symbol);

    return InkWell(
      onTap: () => context.push(AppRoutes.stockDetail(row.symbol)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing16,
          vertical: DesignTokens.spacing8,
        ),
        child: Row(
          children: [
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
                  if (row.isTurnaround) ...[
                    const SizedBox(width: DesignTokens.spacing4),
                    // Flexible:同月營收頁——窄幅下固定寬徽章會擠爆列
                    Flexible(child: _turnaroundBadge(theme)),
                  ],
                ],
              ),
            ),
            _numCell(
              theme,
              row.eps?.toStringAsFixed(2) ?? '--',
              color: theme.colorScheme.onSurface,
              bold: true,
            ),
            const SizedBox(width: DesignTokens.spacing12),
            // EPS 年增差值(元):排序鍵直接顯示(帶號,紅=優於去年、
            // 綠=遜於去年,同股價語意);背景條=相對可見清單最大差值
            GrowthBarCell(
              width: _cellWidth,
              text: row.epsYoyDelta == null
                  ? '--'
                  : '${row.epsYoyDelta! > 0 ? '+' : ''}'
                        '${row.epsYoyDelta!.toStringAsFixed(2)}',
              value: row.epsYoyDelta,
              maxAbs: maxAbsDelta,
            ),
            const SizedBox(width: DesignTokens.spacing12),
            _numCell(
              theme,
              // 淨利單位千元 → 轉元再 compact(億/萬);負值(虧損)照實顯示
              row.netIncome == null
                  ? '--'
                  : LocalizedNumberFormat.compact(row.netIncome! * 1000),
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: DesignTokens.spacing12),
            _numCell(
              theme,
              // 淨利率:EPS 榜的品質維度(同 EPS 年增,含金量看利潤率)
              row.netMarginPct == null
                  ? '--'
                  : '${row.netMarginPct!.toStringAsFixed(1)}%',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _turnaroundBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.upColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Text(
        'quarterlyOverview.turnaround'.tr(),
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: theme.textTheme.labelSmall?.copyWith(
          color: PriceColors.onTintOf(AppTheme.upColor, theme.brightness),
          fontSize: DesignTokens.fontSizeXs,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildColumnHeader(ThemeData theme) {
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
          h('quarterlyOverview.epsCol'),
          const SizedBox(width: DesignTokens.spacing12),
          h('quarterlyOverview.yoyCol'),
          const SizedBox(width: DesignTokens.spacing12),
          h('quarterlyOverview.netIncomeCol'),
          const SizedBox(width: DesignTokens.spacing12),
          h('quarterlyOverview.marginCol'),
        ],
      ),
    );
  }

  // 62(2026-08-13 終審 Critical 1):加淨利率欄後 76×4+間距+padding=384
  // >375pt 手機寬直接溢出、股名歸零——與月營收頁同一筆帳(62×4+48+32=328,
  // 375 下股名剩 47px)。加欄前先重算;375 守門測試在 quarterly_overview_
  // screen_test。
  static const double _cellWidth = 62;

  Widget _numCell(
    ThemeData theme,
    String text, {
    required Color color,
    bool bold = false,
  }) {
    return SizedBox(
      width: _cellWidth,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

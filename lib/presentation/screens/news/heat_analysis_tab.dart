import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/heat_calculator.dart';
import 'package:daredevil/presentation/providers/news_heat_provider.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/warning_badge.dart';
import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';

/// 新聞頁「熱度分析」分頁：主流族群 + 焦點股（三模式交叉）
class HeatAnalysisTab extends ConsumerStatefulWidget {
  const HeatAnalysisTab({super.key});

  @override
  ConsumerState<HeatAnalysisTab> createState() => _HeatAnalysisTabState();
}

class _HeatAnalysisTabState extends ConsumerState<HeatAnalysisTab> {
  bool _pullbackOnly = false;
  bool _sortBySurge = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(newsHeatProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        final message = ErrorDisplay.message(e);
        return FillRemainingScrollable(
          child: ErrorDisplay.isNetworkError(message)
              ? EmptyStates.networkError(
                  onRetry: () => ref.invalidate(newsHeatProvider),
                )
              : EmptyStates.error(
                  message: message,
                  onRetry: () => ref.invalidate(newsHeatProvider),
                ),
        );
      },
      data: (data) {
        if (data.themes.isEmpty && data.stocks.isEmpty) {
          return Center(child: Text('news.heatEmpty'.tr()));
        }
        var stocks = _pullbackOnly
            ? data.stocks
                  .where(
                    (s) =>
                        data.modeBySymbol[s.symbol] ==
                        ScoringMode.weaknessObserve,
                  )
                  .toList()
            : data.stocks;
        // 爆量排序僅在 surgeReliable 時可用（見閘門說明於 SegmentedButton 顯示條件）；
        // 篇數序＝維持 provider 送來的原始順序，不額外重排。
        if (data.surgeReliable && _sortBySurge) {
          stocks = [...stocks]
            ..sort((a, b) {
              final byRatio = b.surgeRatio.compareTo(a.surgeRatio);
              if (byRatio != 0) return byRatio;
              final byMentions = b.mentions7d.compareTo(a.mentions7d);
              if (byMentions != 0) return byMentions;
              return a.symbol.compareTo(b.symbol);
            });
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(newsHeatProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'news.hotThemes'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final t in data.themes)
                _ThemeCard(
                  theme: t,
                  stockNames: data.stockNames,
                  surgeReliable: data.surgeReliable,
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'news.focusStocks'.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  FilterChip(
                    label: Text('news.pullbackOnly'.tr()),
                    selected: _pullbackOnly,
                    onSelected: (v) => setState(() => _pullbackOnly = v),
                  ),
                ],
              ),
              // 爆量閘門：基準窗新聞量不足時，排序切換連同爆量徽章一併隱藏，
              // 避免用不可信的排序誤導使用者（見 HeatResult.surgeReliable doc）。
              if (data.surgeReliable) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text('news.sortByMentions'.tr()),
                      ),
                      ButtonSegment(
                        value: true,
                        // 與 _SurgeBadge 共用「爆量」字串，避免重複翻譯維護。
                        label: Text('news.surgeBadge'.tr()),
                      ),
                    ],
                    selected: {_sortBySurge},
                    onSelectionChanged: (set) =>
                        setState(() => _sortBySurge = set.first),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              for (final s in stocks)
                _FocusStockTile(
                  heat: s,
                  name: data.stockNames[s.symbol],
                  mode: data.modeBySymbol[s.symbol],
                  priceChange: data.priceChangeBySymbol[s.symbol],
                  warning: data.warningBySymbol[s.symbol],
                  surgeReliable: data.surgeReliable,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.stockNames,
    this.surgeReliable = false,
  });

  final ThemeHeat theme;
  final Map<String, String> stockNames;

  /// 爆量閘門（見 [NewsHeatAnalysis.surgeReliable]）：false 時隱藏爆量徽章。
  final bool surgeReliable;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  theme.theme,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                if (surgeReliable && theme.isSurging) const _SurgeBadge(),
                const Spacer(),
                Text('news.articlesCount'.tr(args: ['${theme.articles7d}'])),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'news.prevWeekCount'.tr(args: ['${theme.articlesPrev21d}']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // 政策/產業級報導可能無任何上市公司名（如軍工的無人機條例新聞）
            // → 成分股為空時整塊不渲染，不留空白列
            if (theme.topStocks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final sym in theme.topStocks)
                    ActionChip(
                      label: Text(stockNames[sym] ?? sym),
                      onPressed: () => _openStockDetail(context, sym),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FocusStockTile extends StatelessWidget {
  const _FocusStockTile({
    required this.heat,
    this.name,
    this.mode,
    this.priceChange,
    this.warning,
    this.surgeReliable = false,
  });

  final StockHeat heat;
  final String? name;
  final ScoringMode? mode;

  /// 當日漲跌幅 %；缺值＝無法計算，不顯示（不可當 0%）。
  final double? priceChange;

  /// 生效警示（注意/處置股）；優先於 [StockHeat.hasRiskNews] 決定風險徽章文案。
  final TradingWarningEntry? warning;

  /// 爆量閘門（見 [NewsHeatAnalysis.surgeReliable]）：false 時隱藏爆量／新進榜徽章。
  final bool surgeReliable;

  /// 風險徽章文案：有生效警示者沿用既有 [WarningBadgeType.label]（與股票卡片
  /// 同一套注意股/處置股翻譯），否則若命中風險新聞關鍵字則用通用「風險新聞」；
  /// 兩者皆無則不顯示徽章（回傳 null）。
  String? _riskLabel() {
    final w = warning;
    if (w != null) {
      return switch (w.warningType) {
        'DISPOSAL' => WarningBadgeType.disposal.label,
        // 未知警示類型（理論上不會發生）保守當注意股處理，而非吞掉徽章。
        _ => WarningBadgeType.attention.label,
      };
    }
    if (heat.hasRiskNews) return 'news.riskNews'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isPullback = mode == ScoringMode.weaknessObserve;
    final riskLabel = _riskLabel();
    final change = priceChange;
    return Card(
      color: isPullback
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .3)
          : null,
      child: ListTile(
        title: Row(
          children: [
            Text(name ?? heat.symbol),
            const SizedBox(width: 6),
            Text(heat.symbol, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
            if (riskLabel != null) ...[
              _RiskBadge(label: riskLabel),
              const SizedBox(width: 6),
            ],
            if (surgeReliable && heat.isSurging) ...[
              const _SurgeBadge(),
              const SizedBox(width: 6),
            ],
            if (surgeReliable && heat.isNewEntrant) ...[
              const _NewEntrantBadge(),
              const SizedBox(width: 6),
            ],
            if (mode != null) _ModeBadge(mode: mode!),
          ],
        ),
        subtitle: Text(
          '${'news.articlesCount'.tr(args: ['${heat.mentions7d}'])} · '
          '${'news.sourcesCount'.tr(args: ['${heat.distinctSources7d}'])} · '
          '${'news.prevWeekCount'.tr(args: ['${heat.mentionsPrev21d}'])}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (change != null) ...[
              Text(
                _formatPriceChange(change),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.priceColor(change),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _openStockDetail(context, heat.symbol),
      ),
    );
  }
}

/// 格式化當日漲跌幅：正值帶 `+`（如 `+2.35%`），負值沿用 `-`（如 `-1.20%`），
/// 平盤與微負值捨入歸零時顯示 `0.00%`（不帶 `+`、非 `-0.00%`）。
String _formatPriceChange(double change) =>
    AppNumberFormat.signedPercent(change, decimals: 2);

class _SurgeBadge extends StatelessWidget {
  const _SurgeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'news.surgeBadge'.tr(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// 風險徽章：注意/處置股或風險新聞命中。與 [_SurgeBadge] 用**不同視覺
/// 通道**區分「危險 vs 熱門」：加 error 色外框＋警示圖示＋onErrorContainer
/// 文字色——同檔股票同時掛兩枚徽章時（列警且爆量）仍一眼可辨。
class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

/// 新進榜徽章：近窗達爆量門檻但基準窗零提及（見 [StockHeat.isNewEntrant]）。
class _NewEntrantBadge extends StatelessWidget {
  const _NewEntrantBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'news.newEntrant'.tr(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final ScoringMode mode;

  @override
  Widget build(BuildContext context) {
    // ScoringMode.displayKey 是既有 i18n key（scoringMode.*，Today screen 同源），
    // 照用避免另立一套字串（見 lib/core/constants/scoring_mode.dart）。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        mode.displayKey.tr(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

Future<void> _openStockDetail(BuildContext context, String symbol) async {
  // 照 news_screen.dart 既有慣例（AppRoutes.stockDetail + context.push）。
  // 返回後重讀自選∪持股：個股頁可能加入或移除了自選，新聞頁「自選」篩選要跟上
  final container = ProviderScope.containerOf(context, listen: false);
  await context.push(AppRoutes.stockDetail(symbol));
  await container.read(newsProvider.notifier).reloadMySymbols();
}

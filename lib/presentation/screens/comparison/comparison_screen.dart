import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/presentation/providers/comparison_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/screens/comparison/widgets/comparison_header.dart';
import 'package:daredevil/presentation/screens/comparison/widgets/comparison_table.dart';
import 'package:daredevil/presentation/screens/comparison/widgets/price_overlay_chart.dart';
import 'package:daredevil/presentation/screens/comparison/widgets/radar_comparison_chart.dart';
import 'package:daredevil/presentation/screens/comparison/widgets/stock_picker_sheet.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 比較畫面 - 並排顯示多檔股票分析
class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key, this.initialSymbols = const []});

  final List<String> initialSymbols;

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(comparisonProvider.notifier).addStocks(widget.initialSymbols);
    });
  }

  Future<void> _showStockPicker() async {
    final state = ref.read(comparisonProvider);
    if (!state.canAddMore) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('comparison.maxStocksReached'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final symbol = await showAppBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StockPickerSheet(existingSymbols: state.symbols),
    );

    if (symbol != null && mounted) {
      ref.read(comparisonProvider.notifier).addStock(symbol);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comparisonProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('comparison.title'.tr()),
        actions: [
          if (state.canAddMore)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showStockPicker,
              tooltip: 'comparison.addStock'.tr(),
            ),
        ],
      ),
      body: state.isLoading && state.symbols.isEmpty
          ? const GenericListShimmer(itemCount: 4)
          : state.error != null && state.symbols.isEmpty
          ? ErrorDisplay.isNetworkError(state.error!)
                ? EmptyStates.networkError(
                    onRetry: () =>
                        ref.read(comparisonProvider.notifier).reload(),
                  )
                : EmptyStates.error(
                    message: state.error!,
                    onRetry: () =>
                        ref.read(comparisonProvider.notifier).reload(),
                  )
          : Column(
              children: [
                // 錯誤橫幅（有股票時仍顯示，但不全頁替換）
                if (state.error != null)
                  MaterialBanner(
                    content: Text(state.error!),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            ref.read(comparisonProvider.notifier).reload(),
                        child: Text('common.retry'.tr()),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(comparisonProvider.notifier).clearError(),
                        child: Text('common.dismiss'.tr()),
                      ),
                    ],
                  ),

                // 股票標籤列
                if (state.symbols.isNotEmpty)
                  ComparisonHeader(
                    symbols: state.symbols,
                    stocksMap: state.stocksMap,
                    canAddMore: state.canAddMore,
                    onRemove: (s) =>
                        ref.read(comparisonProvider.notifier).removeStock(s),
                    onAdd: _showStockPicker,
                  ),

                const SizedBox(height: DesignTokens.spacing4),

                // 主要內容
                Expanded(
                  child: state.hasEnoughToCompare
                      ? _buildComparisonContent(state, theme)
                      : _buildEmptyState(state, theme),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ComparisonState state, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.compare_arrows,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: DesignTokens.spacing16),
          Text(
            'comparison.needMoreStocks'.tr(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing8),
          Text(
            'comparison.addStockHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing24),
          FilledButton.icon(
            onPressed: _showStockPicker,
            icon: const Icon(Icons.add),
            label: Text('comparison.addStock'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonContent(ComparisonState state, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 載入遮罩
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),

          // 價格疊加圖
          Semantics(
            label: S.accessibilityPriceComparisonChart(state.symbols.join('、')),
            image: true,
            child: PriceOverlayChart(
              symbols: state.symbols,
              priceHistoriesMap: state.priceHistoriesMap,
              stocksMap: state.stocksMap,
            ),
          ),

          const SizedBox(height: DesignTokens.spacing16),

          // 雷達圖
          Semantics(
            label: S.accessibilityRadarChart(state.symbols.join('、')),
            image: true,
            child: RadarComparisonChart(state: state),
          ),

          const SizedBox(height: DesignTokens.spacing16),

          // 比較表格
          Semantics(
            label: S.accessibilityComparisonTable(state.symbols.join('、')),
            container: true,
            child: ComparisonTable(state: state),
          ),

          const SizedBox(height: DesignTokens.spacing32),
        ],
      ),
    );
  }
}

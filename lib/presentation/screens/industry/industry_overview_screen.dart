import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/responsive_helper.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/scan_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';

/// 產業概覽狀態
class _IndustryOverviewState {
  const _IndustryOverviewState({
    this.industries = const [],
    this.isLoading = true,
    this.error,
  });

  final List<_IndustryItem> industries;
  final bool isLoading;
  final String? error;
}

class _IndustryItem {
  const _IndustryItem({required this.name, required this.stockCount});

  final String name;
  final int stockCount;
}

/// 產業概覽頁 — 展示各產業分類與股票數量
class IndustryOverviewScreen extends ConsumerStatefulWidget {
  const IndustryOverviewScreen({super.key});

  @override
  ConsumerState<IndustryOverviewScreen> createState() =>
      _IndustryOverviewScreenState();
}

class _IndustryOverviewScreenState
    extends ConsumerState<IndustryOverviewScreen> {
  _IndustryOverviewState _state = const _IndustryOverviewState();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final stockRepo = ref.read(stockRepositoryProvider);
      final counts = await stockRepo.getIndustryStockCounts();

      final items =
          counts.entries
              .map((e) => _IndustryItem(name: e.key, stockCount: e.value))
              .toList()
            ..sort((a, b) => b.stockCount.compareTo(a.stockCount));

      if (mounted) {
        setState(() {
          _state = _IndustryOverviewState(industries: items, isLoading: false);
        });
      }
    } catch (e, s) {
      AppLogger.warning('IndustryOverviewScreen', '載入產業資料失敗', e, s);
      if (mounted) {
        setState(() {
          _state = _IndustryOverviewState(
            isLoading: false,
            error: ErrorDisplay.message(e),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('scan.selectIndustry'.tr())),
      body: _state.isLoading
          ? const GenericListShimmer(itemCount: 8)
          : _state.error != null
          ? FillRemainingScrollable(
              child: ErrorDisplay.isNetworkError(_state.error!)
                  ? EmptyStates.networkError(
                      onRetry: () {
                        setState(() => _state = const _IndustryOverviewState());
                        _loadData();
                      },
                    )
                  : EmptyStates.error(
                      message: _state.error!,
                      onRetry: () {
                        setState(() => _state = const _IndustryOverviewState());
                        _loadData();
                      },
                    ),
            )
          : _buildIndustryList(theme),
    );
  }

  Widget _buildIndustryList(ThemeData theme) {
    final columns = context.responsiveGridColumns;
    final useGrid = columns > 1;
    final padding = context.responsiveHorizontalPadding;
    final spacing = context.responsiveCardSpacing;

    if (useGrid) {
      return GridView.builder(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: spacing),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          mainAxisExtent: 64,
        ),
        itemCount: _state.industries.length,
        itemBuilder: (context, index) =>
            _buildIndustryTile(theme, _state.industries[index]),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.only(
        top: DesignTokens.spacing8,
        bottom: MediaQuery.of(context).padding.bottom + DesignTokens.spacing16,
      ),
      itemCount: _state.industries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _buildIndustryTile(theme, _state.industries[index]),
    );
  }

  Widget _buildIndustryTile(ThemeData theme, _IndustryItem item) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.tertiaryContainer,
        child: Icon(
          Icons.factory_outlined,
          color: theme.colorScheme.onTertiaryContainer,
          size: 20,
        ),
      ),
      title: Text(item.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'scan.industryStockCount'.tr(
              namedArgs: {'count': item.stockCount.toString()},
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: DesignTokens.spacing4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () {
        ref.read(scanProvider.notifier).setIndustryFilter(item.name);
        context.pop();
      },
    );
  }
}

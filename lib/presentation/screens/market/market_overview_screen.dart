import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

/// 完整大盤總覽（從今日頁摘要條進入）。
///
/// 讀今日頁已載入的同一份 state，進頁不重新載入；下拉才
/// [MarketOverviewNotifier.loadData]。
class MarketOverviewScreen extends ConsumerWidget {
  const MarketOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(marketOverviewProvider);
    final notifier = ref.read(marketOverviewProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text('marketOverview.title'.tr())),
      body: ThemedRefreshIndicator(
        onRefresh: notifier.loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _content(context, state, notifier)),
            const SliverToBoxAdapter(
              child: SizedBox(height: DesignTokens.spacing24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    MarketOverviewState state,
    MarketOverviewNotifier notifier,
  ) {
    if (!state.hasData && !state.isLoading) {
      if (state.error != null) {
        return Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing16),
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(state.error!),
              trailing: TextButton(
                onPressed: notifier.loadData,
                child: Text('common.retry'.tr()),
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing32),
        child: Text(
          'marketOverview.pageEmpty'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return MarketDashboard(state: state);
  }
}

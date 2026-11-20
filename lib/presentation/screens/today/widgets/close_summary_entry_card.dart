import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/providers/close_summary_provider.dart';

/// 今日頁的收盤摘要入口：資料日、持股檔數、有待處理事件的檔數，點了進摘要頁。
///
/// 第一次載入中、錯誤、沒有任何列時整張不顯示，不擋今日頁主線（與族群排名
/// 同一做法）。重算途中沿用上一次的內容，不閃。
class CloseSummaryEntryCard extends ConsumerWidget {
  const CloseSummaryEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref
        .watch(closeSummaryProvider)
        .when(
          skipLoadingOnReload: true,
          data: (summary) => summary,
          loading: () => null,
          error: (_, _) => null,
        );
    if (summary == null || summary.sections.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final date = summary.dataDate;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing4,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.closeSummary),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing12,
              vertical: DesignTokens.spacing8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.summarize_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Expanded(
                  child: Text(
                    'closeSummary.entry'.tr(
                      namedArgs: {
                        'date': '${date.month}/${date.day}',
                        'holdings': '${summary.holdingCount}',
                        'events': '${summary.actionableStockCount}',
                      },
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

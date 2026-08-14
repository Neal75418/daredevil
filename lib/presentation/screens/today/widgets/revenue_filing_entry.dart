import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/presentation/providers/revenue_overview_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/today/widgets/filing_unfiled_label.dart';

/// 今日頁的「月營收公布中」入口(僅每月 1~[ApiConfig.mopsRevenueWindowLastDay]
/// 日顯示)。
///
/// 只是入口不是內容:進度+自選交卷數一行帶過,點擊進
/// [AppRoutes.revenueOverview] 的完整清單頁——清單的完整性在那裡,
/// 這裡刻意不做任何排行/策展(2026-08-05 設計討論:輪動榜會漏股)。
class RevenueFilingEntrySection extends ConsumerStatefulWidget {
  const RevenueFilingEntrySection({super.key});

  @override
  ConsumerState<RevenueFilingEntrySection> createState() =>
      _RevenueFilingEntrySectionState();
}

class _RevenueFilingEntrySectionState
    extends ConsumerState<RevenueFilingEntrySection> {
  /// 已觸發載入的日期鍵——複審 Medium #5:原本只在 initState 且當下在
  /// 窗口內才載入,而本 widget 常駐於 indexedStack 保活的 TodayScreen,
  /// State 永不重建 → App 掛著跨月時 loadData 永不執行、overview 恆
  /// null → 入口整個窗口隱形(它是總覽頁唯一導航入口,整條功能鏈
  /// 不可達直到重啟)。改為 build 期以「日」為冪等鍵補載:跨日後首次
  /// rebuild 即觸發,一天最多一次。
  String? _loadedDayKey;

  bool get _inWindow =>
      TaiwanTime.now().day <= ApiConfig.mopsRevenueWindowLastDay;

  void _ensureLoadedToday() {
    final now = TaiwanTime.now();
    final key = '${now.year}-${now.month}-${now.day}';
    if (_loadedDayKey == key) return;
    _loadedDayKey = key;
    Future.microtask(() {
      if (mounted) {
        ref.read(revenueOverviewProvider.notifier).loadData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_inWindow) return const SizedBox.shrink();
    _ensureLoadedToday();

    final overview = ref.watch(
      revenueOverviewProvider.select((s) => s.overview),
    );
    if (overview == null) return const SizedBox.shrink();

    // 月份 gate(複審 Low #4):公布窗口內但 DB 最新月還是**前前月**
    // (每月 1 日當晚同步前的常態)時,不顯示「6 月營收公布中」這種
    // 矛盾入口——等第一批新月資料落庫再現身。
    final now = TaiwanTime.now();
    final expected = DateTime(now.year, now.month - 1);
    if (overview.year != expected.year || overview.month != expected.month) {
      return const SizedBox.shrink();
    }

    final watchlistItems = ref.watch(
      watchlistProvider.select(
        (s) => [for (final i in s.items) (symbol: i.symbol, name: i.stockName)],
      ),
    );
    final theme = Theme.of(context);

    final filed = overview.rows.length;
    final filedSymbols = overview.rows.map((r) => r.symbol).toSet();
    final watchFiled = watchlistItems
        .where((i) => filedSymbols.contains(i.symbol))
        .length;
    // 沉默點名:「壓線的沉默也是資訊」——把還沒交卷的自選亮出來
    final unfiled = unfiledNamesLabel(
      watchlistItems: watchlistItems,
      filedSymbols: filedSymbols,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing4,
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: InkWell(
          onTap: () => context.push(AppRoutes.revenueOverview),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing12,
              vertical: DesignTokens.spacing8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'revenueOverview.entryTitle'.tr(
                          namedArgs: {'month': '${overview.month}'},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'revenueOverview.entrySubtitle'.tr(
                          namedArgs: {
                            'filed': '$filed',
                            'watchFiled': '$watchFiled',
                            'watchTotal': '${watchlistItems.length}',
                          },
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (unfiled != null)
                        Text(
                          'revenueOverview.entryUnfiled'.tr(
                            namedArgs: {'names': unfiled},
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
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
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/quarterly_filing_calendar.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/presentation/providers/quarterly_report_overview_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/today/widgets/filing_unfiled_label.dart';

/// 今日頁的季報入口——**常駐**,文案隨申報窗口切換(2026-08-06 定案):
///
/// - 公布期(窗口內且 DB 已有該季資料):「Q2 季報公布中・已公布 N 家」
/// - 其餘時間:「Q2 季報總表・共 N 家」——與月營收入口刻意**不同**:
///   月營收兩週就過期,窗口外藏起來沒損失;季報是整季唯一的基本面
///   總表,截止後那 ~7 週正是價值高峰,入口的存廢跟資料半衰期走,
///   不跟月營收對稱。唯一隱藏條件=DB 尚無季報資料(全新安裝)。
///
/// 其餘結構鏡射 [RevenueFilingEntrySection]:只是入口不是內容,點擊進
/// [AppRoutes.quarterlyOverview] 的完整清單頁。跨日補載用同一套
/// day-idempotent 機制(TodayScreen 被 indexedStack 保活,State 永不
/// 重建,initState 一次性載入會讓入口跨窗口隱形——2026-08-05 營收
/// 入口複審 Medium #5 的同一課)。
class QuarterlyFilingEntrySection extends ConsumerStatefulWidget {
  const QuarterlyFilingEntrySection({super.key});

  @override
  ConsumerState<QuarterlyFilingEntrySection> createState() =>
      _QuarterlyFilingEntrySectionState();
}

class _QuarterlyFilingEntrySectionState
    extends ConsumerState<QuarterlyFilingEntrySection> {
  String? _loadedDayKey;

  void _ensureLoadedToday() {
    final now = TaiwanTime.now();
    final key = '${now.year}-${now.month}-${now.day}';
    if (_loadedDayKey == key) return;
    _loadedDayKey = key;
    Future.microtask(() {
      if (mounted) {
        ref.read(quarterlyReportOverviewProvider.notifier).loadData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoadedToday();

    final overview = ref.watch(
      quarterlyReportOverviewProvider.select((s) => s.overview),
    );
    if (overview == null) return const SizedBox.shrink();

    // 「公布中」須同時滿足:窗口內 **且** DB 最新季=窗口對應季——
    // 窗口首日同步前(DB 還停在上一季)自動落回總表模式,不會出現
    // 「Q3 公布中」卻列著 Q2 清單的矛盾文案。
    final expected = QuarterlyFilingCalendar.expectedFilingQuarter(
      TaiwanTime.now(),
    );
    final inProgress =
        expected != null &&
        overview.year == expected.year &&
        overview.quarter == expected.quarter;

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
    // 沉默點名(僅公布中——總表模式全員已交,點名無意義)
    final unfiled = inProgress
        ? unfiledNamesLabel(
            watchlistItems: watchlistItems,
            filedSymbols: filedSymbols,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing4,
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: InkWell(
          onTap: () => context.push(AppRoutes.quarterlyOverview),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing12,
              vertical: DesignTokens.spacing8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.request_quote_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (inProgress
                                ? 'quarterlyOverview.entryTitle'
                                : 'quarterlyOverview.entryTitleComplete')
                            .tr(namedArgs: {'quarter': '${overview.quarter}'}),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        inProgress
                            ? 'quarterlyOverview.entrySubtitle'.tr(
                                namedArgs: {
                                  'filed': '$filed',
                                  'watchFiled': '$watchFiled',
                                  'watchTotal': '${watchlistItems.length}',
                                },
                              )
                            : 'quarterlyOverview.entrySubtitleComplete'.tr(
                                namedArgs: {'filed': '$filed'},
                              ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (unfiled != null)
                        Text(
                          'quarterlyOverview.entryUnfiled'.tr(
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

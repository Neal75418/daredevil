import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/close_summary_builder.dart';
import 'package:daredevil/domain/services/close_summary/throttle.dart';
import 'package:daredevil/presentation/providers/close_summary_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/close_summary/close_summary_row_tile.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

/// 收盤摘要頁：持股與自選股每檔一列，照交易決策表 v3 標出狀態與事件
/// （設計見 `docs/plans/2026-11-20-close-summary-design.md`）
class CloseSummaryScreen extends ConsumerStatefulWidget {
  const CloseSummaryScreen({super.key});

  @override
  ConsumerState<CloseSummaryScreen> createState() => _CloseSummaryScreenState();
}

class _CloseSummaryScreenState extends ConsumerState<CloseSummaryScreen> {
  @override
  void initState() {
    super.initState();
    // 今日頁的入口卡讓摘要一直活著，而 launchd 在 App 外寫入的每日更新不會
    // 通知 App：已經算好的摘要可能是舊的，進頁時重算一次（重算期間沿用舊內容）
    if (ref.exists(closeSummaryProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(closeSummaryProvider);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(closeSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('closeSummary.title'.tr())),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyStates.error(
          message: ErrorDisplay.message(error),
          onRetry: () => ref.invalidate(closeSummaryProvider),
        ),
        data: (summary) {
          if (summary == null) {
            return EmptyState(
              icon: Icons.summarize_outlined,
              title: 'closeSummary.emptyNoPrices'.tr(),
            );
          }
          if (summary.sections.isEmpty) {
            return EmptyState(
              icon: Icons.summarize_outlined,
              title: 'closeSummary.emptyNoStocks'.tr(),
            );
          }
          return ThemedRefreshIndicator(
            onRefresh: () async {
              ref.invalidate(closeSummaryProvider);
              // 重算失敗由上面的 error 分支顯示，這裡不往外丟
              try {
                await ref.read(closeSummaryProvider.future);
              } catch (_) {}
            },
            child: ListView(
              children: [
                _Header(
                  summary: summary,
                  now: ref.read(appClockProvider).now(),
                ),
                for (final section in summary.sections) ...[
                  const Divider(height: 1),
                  _SectionTitle(section: section),
                  for (final row in section.rows) CloseSummaryRowTile(row: row),
                ],
                const SizedBox(height: DesignTokens.spacing24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.now});

  final CloseSummary summary;

  /// 台灣時間；資料時間的狀態每次 build 用它重算（摘要算好之後時間會過去）
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final flags = closeSummaryTimeFlags(dataDate: summary.dataDate, now: now);
    final throttle = summary.throttle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing12,
        DesignTokens.spacing16,
        DesignTokens.spacing4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DesignTokens.spacing12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'closeSummary.dataDate'.tr(
                  namedArgs: {'date': _monthDay(summary.dataDate)},
                ),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                summary.institutionalPendingMarkets.isEmpty
                    ? 'closeSummary.institutionalReady'.tr()
                    : 'closeSummary.institutionalPending'.tr(
                        namedArgs: {
                          'markets': _markets(
                            summary.institutionalPendingMarkets,
                          ),
                        },
                      ),
                style: muted,
              ),
            ],
          ),
          if (summary.pricePendingMarkets.isNotEmpty)
            Text(
              'closeSummary.pricePending'.tr(
                namedArgs: {'markets': _markets(summary.pricePendingMarkets)},
              ),
              style: muted,
            ),
          if (flags.awaitingToday)
            Text('closeSummary.awaitingToday'.tr(), style: muted),
          if (flags.dataBehind)
            Text(
              'closeSummary.dataBehind'.tr(
                namedArgs: {'date': _monthDay(summary.dataDate)},
              ),
              style: muted?.copyWith(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: DesignTokens.spacing6),
          if (!summary.indexReady)
            Text('closeSummary.indexPending'.tr(), style: muted)
          else if (throttle == null)
            Text('closeSummary.indexInsufficient'.tr(), style: muted)
          else
            ..._throttleLines(throttle, theme, muted),
          if (summary.strongListGroupMissing)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacing4),
              child: Text('closeSummary.strongListMissing'.tr(), style: muted),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.market),
              child: Text('${'closeSummary.marketLink'.tr()} →'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _throttleLines(
    ThrottleReading throttle,
    ThemeData theme,
    TextStyle? muted,
  ) {
    String side(bool above) =>
        (above ? 'closeSummary.sideAbove' : 'closeSummary.sideBelow').tr();
    final state = switch (throttle.state) {
      ThrottleState.full => 'closeSummary.throttleFull',
      ThrottleState.reduced => 'closeSummary.throttleReduced',
      ThrottleState.flat => 'closeSummary.throttleFlat',
    }.tr();
    final breakDate = throttle.lastBreakDate;
    return [
      Text(
        'closeSummary.throttle'.tr(namedArgs: {'state': state}),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        'closeSummary.throttleDetail'.tr(
          namedArgs: {
            'close': AppNumberFormat.integer(throttle.close),
            'ma': AppNumberFormat.integer(throttle.ma20),
            'maSide': side(throttle.close >= throttle.ma20),
            'threshold': AppNumberFormat.integer(throttle.threshold),
            'thresholdSide': side(throttle.close >= throttle.threshold),
          },
        ),
        style: muted,
      ),
      Text(
        breakDate == null
            ? 'closeSummary.noBreak'.tr(
                namedArgs: {'days': '${throttle.lookbackTradingDays}'},
              )
            : throttle.tradingDaysSinceBreak == 0
            ? 'closeSummary.lastBreakToday'.tr()
            : 'closeSummary.lastBreak'.tr(
                namedArgs: {
                  'date': _monthDay(breakDate),
                  'days': '${throttle.tradingDaysSinceBreak}',
                },
              ),
        style: muted,
      ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.section});

  final CloseSummarySection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = section.isHoldings
        ? 'closeSummary.sectionHoldings'.tr()
        : section.groupName ?? 'closeSummary.sectionUngrouped'.tr();
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing6,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _monthDay(DateTime date) => '${date.month}/${date.day}';

/// 市場代碼 → 畫面名稱，上市在前
String _markets(Set<String> markets) => [
  for (final m in const [MarketCode.twse, MarketCode.tpex])
    if (markets.contains(m)) marketLabelKey(m).tr(),
  for (final m in markets)
    if (m != MarketCode.twse && m != MarketCode.tpex) m,
].join('closeSummary.listSeparator'.tr());

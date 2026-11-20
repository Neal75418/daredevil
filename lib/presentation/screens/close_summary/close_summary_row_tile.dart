import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/chip_checks.dart';
import 'package:daredevil/domain/services/close_summary/holding_checks.dart';
import 'package:daredevil/domain/services/close_summary/price_checks.dart';

/// 收盤摘要的一列（一檔股票），點了進個股詳情
class CloseSummaryRowTile extends StatelessWidget {
  const CloseSummaryRowTile({super.key, required this.row});

  final CloseSummaryRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lines = row.status == RowDataStatus.ok
        ? _detailLines(row)
        : [
            row.status == RowDataStatus.marketPending
                ? 'closeSummary.marketPending'.tr()
                : 'closeSummary.noTrade'.tr(),
          ];

    return InkWell(
      onTap: () => context.push(AppRoutes.stockDetail(row.symbol)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing16,
          vertical: DesignTokens.spacing10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headline(theme),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacing2),
                child: Text(line, style: muted),
              ),
            if (row.events.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacing6),
                child: Wrap(
                  spacing: DesignTokens.spacing6,
                  runSpacing: DesignTokens.spacing4,
                  children: [
                    for (final event in row.events) _EventChip(event: event),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headline(ThemeData theme) {
    final close = row.close;
    final change = row.changePct;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            '${row.name}  ${row.symbol}',
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (close != null)
          Text(
            close.toStringAsFixed(2),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        if (change != null) ...[
          const SizedBox(width: DesignTokens.spacing8),
          Text(
            AppNumberFormat.signedPercent(change),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: PriceColors.forChange(
                AppNumberFormat.roundForDisplay(change, 2),
                theme.brightness,
              ),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// 資料正常的列要寫的幾行說明
List<String> _detailLines(CloseSummaryRow row) {
  final lines = <String>[];

  final parts = <String>[
    if (row.volumeShares case final volume?)
      'closeSummary.volume'.tr(
        namedArgs: {'lots': AppNumberFormat.integer(volume / 1000)},
      ),
    ..._chipFlow(row.chip),
  ];
  if (parts.isNotEmpty) lines.add(parts.join(_partSeparator()));

  if (row.holding case final holding?) lines.addAll(_holdingLines(holding));

  if (row.role == GroupRole.thermometer) {
    final streak = row.thermometerStreak ?? 0;
    if (streak != 0) {
      final key = streak > 0
          ? (row.thermometerStreakAtLeast
                ? 'closeSummary.aboveMaAtLeast'
                : 'closeSummary.aboveMaDays')
          : (row.thermometerStreakAtLeast
                ? 'closeSummary.belowMaAtLeast'
                : 'closeSummary.belowMaDays');
      lines.add(key.tr(namedArgs: {'days': '${streak.abs()}'}));
    }
    return lines;
  }

  if (row.strongList case final check?) {
    final notPassed = _notPassed({
      'closeSummary.condRet20': check.ret20,
      'closeSummary.condLimitUp': check.limitUpIn20,
      'closeSummary.condAvgVolume': check.avgVolume20,
      'closeSummary.condAboveMa': check.aboveMa20,
    });
    final score = 'closeSummary.strongListScore'.tr(
      namedArgs: {'passed': '${check.passed}'},
    );
    lines.add(
      notPassed.isEmpty
          ? score
          : '$score${_partSeparator()}${'closeSummary.notPassed'.tr(namedArgs: {'items': notPassed})}',
    );
  }

  final sealParts = <String>[
    if (row.biasPct case final bias?)
      'closeSummary.bias'.tr(
        namedArgs: {'pct': AppNumberFormat.signedPercent(bias, decimals: 1)},
      ),
    ..._chipSeal(row.chip),
  ];
  if (sealParts.isNotEmpty) lines.add(sealParts.join(_partSeparator()));

  // 除名重審不看進場這一側（v3 的掃描排除這組），前提條件那行不寫
  if (row.prerequisites case final pre?
      when !pre.allPassed && row.role != GroupRole.delistReview) {
    lines.add(
      'closeSummary.prereqNotPassed'.tr(
        namedArgs: {
          'items': _notPassed({
            'closeSummary.prereqMoving': pre.moving,
            'closeSummary.prereqBias': pre.bias,
            'closeSummary.prereqRevenue': pre.revenue,
            'closeSummary.prereqVolume': pre.dayVolume,
          }),
        },
      ),
    );
  }
  return lines;
}

/// 外資、投信當日張數與連買連賣；法人未到時一句說明
List<String> _chipFlow(ChipCheck? chip) {
  if (chip == null) return ['closeSummary.institutionalPendingRow'.tr()];
  String party(String key, double shares, int streak) {
    final text = key.tr(namedArgs: {'lots': _signedLots(shares)});
    // 「連」是兩天以上（與法人排行頁同一做法）
    if (streak.abs() < 2) return text;
    final streakKey = streak > 0
        ? 'closeSummary.streakBuy'
        : 'closeSummary.streakSell';
    return '$text${streakKey.tr(namedArgs: {'days': '${streak.abs()}'})}';
  }

  return [
    party('closeSummary.foreign', chip.foreignNetShares, chip.foreignStreak),
    party('closeSummary.trust', chip.trustNetShares, chip.trustStreak),
  ];
}

/// 籌碼章與對做
List<String> _chipSeal(ChipCheck? chip) {
  final sealedBy = chip?.sealedBy;
  if (chip == null || sealedBy == null) return const [];
  final isForeign = sealedBy == ChipParty.foreign;
  final seal = 'closeSummary.chipSeal'.tr(
    namedArgs: {
      'party':
          (isForeign ? 'closeSummary.partyForeign' : 'closeSummary.partyTrust')
              .tr(),
      'days': '${(isForeign ? chip.foreignStreak : chip.trustStreak).abs()}',
    },
  );
  return [seal, if (chip.opposed) 'closeSummary.opposed'.tr()];
}

List<String> _holdingLines(HoldingCheck holding) {
  final lines = <String>[
    'closeSummary.holdingCost'.tr(
      namedArgs: {
        'cost': holding.avgCost.toStringAsFixed(2),
        'quantity': AppNumberFormat.integer(holding.quantity),
        'pnl': _signedWhole(holding.unrealizedPnl),
        'pct': AppNumberFormat.signedPercent(holding.unrealizedPct),
      },
    ),
  ];

  final parts = <String>[];
  final stop = holding.stopPrice;
  if (stop == null) {
    parts.add('closeSummary.costGateInsufficient'.tr());
  } else {
    parts.add(
      'closeSummary.costGate'.tr(
        namedArgs: {
          'price': stop.toStringAsFixed(2),
          'pct': AppNumberFormat.signedPercent(
            (stop / holding.closePrice - 1) * 100,
          ),
        },
      ),
    );
  }
  final days = holding.tradingDaysHeld;
  if (holding.timeStop == TimeStopState.lifted) {
    parts.add('closeSummary.reachedOneR'.tr());
  } else if (days == 0) {
    parts.add('closeSummary.holdingToday'.tr());
  } else if (days != null) {
    const total = CloseSummaryParams.timeStopTradingDays;
    // 過了 8 天（到期由事件標出）或算不出時間時只寫第幾天
    parts.add(
      holding.timeStop == null || days > total
          ? 'closeSummary.holdingDaysOnly'.tr(namedArgs: {'days': '$days'})
          : 'closeSummary.holdingDays'.tr(
              namedArgs: {'days': '$days', 'total': '$total'},
            ),
    );
  }
  lines.add(parts.join(_partSeparator()));
  return lines;
}

String _partSeparator() => 'closeSummary.partSeparator'.tr();

/// 帶正負號的整數：先捨入再決定正負號，捨入成 0 時不寫「-0」
String _signedWhole(double value) {
  final rounded = AppNumberFormat.roundForDisplay(value, 0);
  return AppNumberFormat.signedInteger(rounded == 0 ? 0 : rounded);
}

/// 買賣超（股）換成張數：先捨入再決定正負號；不到半張但不是 0 時留一位小數，
/// 不寫成「+0」「-0」
String _signedLots(double shares) {
  final lots = shares / 1000;
  final rounded = AppNumberFormat.roundForDisplay(lots, 0);
  if (rounded == 0 && lots != 0) {
    return AppNumberFormat.signedFixed(lots, decimals: 1);
  }
  return AppNumberFormat.signedInteger(rounded);
}

/// 未通過的條件名稱；資料不足的在名稱後加註
String _notPassed(Map<String, CheckOutcome> outcomes) => [
  for (final MapEntry(key: key, value: outcome) in outcomes.entries)
    if (outcome == CheckOutcome.fail)
      key.tr()
    else if (outcome == CheckOutcome.insufficient)
      '${key.tr()}${'closeSummary.insufficient'.tr()}',
].join('closeSummary.listSeparator'.tr());

/// 事件標籤：待處理與資訊用不同底色（都不用紅綠，紅綠留給股價漲跌）
class _EventChip extends StatelessWidget {
  const _EventChip({required this.event});

  final SummaryEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionable = event.kind.isActionable;
    return Container(
      key: ValueKey(
        actionable ? 'closeSummary.chip.actionable' : 'closeSummary.chip.info',
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing8,
        vertical: DesignTokens.spacing2,
      ),
      decoration: BoxDecoration(
        color: actionable
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Text(
        eventLabel(event),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: actionable
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
          fontWeight: actionable ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

/// 事件的畫面文字
String eventLabel(SummaryEvent event) {
  final key = 'closeSummary.event.${event.kind.name}';
  return switch (event.kind) {
    SummaryEventKind.belowMaStreak => key.tr(
      namedArgs: {'days': '${event.days ?? 0}'},
    ),
    SummaryEventKind.structureB => key.tr(
      namedArgs: {'days': '${event.supportPeriod ?? 0}'},
    ),
    SummaryEventKind.sectorCooling => key.tr(
      namedArgs: {'industry': event.industry ?? ''},
    ),
    _ => key.tr(),
  };
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/utils/taiwan_date_formatter.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_helpers.dart';

/// 個股頁股利表：今年＋前幾個完整年度與平均列。年度依除權息日的年份
/// （除息年度），金額與狀態的定義見 [DividendSummary]
class DividendSummaryTable extends StatelessWidget {
  const DividendSummaryTable({
    super.key,
    required this.summary,
    required this.showROCYear,
  });

  final DividendSummary summary;
  final bool showROCYear;

  static final _sharesFormat = intl.NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    final rows = [summary.current, ...summary.pastYears];
    final average = summary.average;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing12),
        child: Column(
          children: [
            buildTableHeader(context, [
              buildHeaderCell(context, 'stockDetail.dividendYear'.tr()),
              buildHeaderCell(
                context,
                'stockDetail.cashDividend'.tr(),
                textAlign: TextAlign.end,
              ),
              buildHeaderCell(
                context,
                'stockDetail.stockDividend'.tr(),
                textAlign: TextAlign.end,
              ),
              buildHeaderCell(
                context,
                'stockDetail.totalDividend'.tr(),
                textAlign: TextAlign.end,
              ),
            ]),
            const SizedBox(height: DesignTokens.spacing8),
            for (final (index, row) in rows.indexed)
              buildTableDataRow(context, index, [
                Expanded(
                  flex: 2,
                  child: _yearCell(context, row, isCurrent: index == 0),
                ),
                ..._rowCells(context, row),
              ]),
            if (average != null) ...[
              const Divider(height: DesignTokens.spacing16),
              buildTableDataRow(
                context,
                rows.length,
                _averageCells(context, average),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _yearCell(
    BuildContext context,
    DividendYearRow row, {
    required bool isCurrent,
  }) {
    final theme = Theme.of(context);
    final end = summary.displayEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showROCYear
              ? TaiwanDateFormatter.formatDualYear(row.year)
              : '${row.year}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (isCurrent &&
            end != null &&
            row.status != DividendYearStatus.building)
          Text(
            'stockDetail.dividendAsOf'.tr(
              namedArgs: {'date': '${end.month}/${end.day}'},
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }

  List<Widget> _rowCells(BuildContext context, DividendYearRow row) {
    final status = switch (row.status) {
      DividendYearStatus.paid => null,
      DividendYearStatus.none => 'stockDetail.dividendStatusNone'.tr(),
      DividendYearStatus.noRecord => 'stockDetail.dividendStatusNoRecord'.tr(),
      DividendYearStatus.notYet => 'stockDetail.dividendStatusNotYet'.tr(),
      DividendYearStatus.building => 'stockDetail.dividendStatusBuilding'.tr(),
    };
    if (status != null) return [_statusCell(context, status)];
    return _amountCells(
      context,
      cash: row.cash,
      stockShares: row.stockShares,
      cashCount: row.cashCount,
    );
  }

  List<Widget> _averageCells(BuildContext context, DividendAverage average) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return switch (average) {
      DividendAverageValue(
        :final fromYear,
        :final years,
        :final cash,
        :final stockShares,
      ) =>
        [
          Expanded(
            flex: 2,
            child: Text(
              years == ApiConfig.dividendBackfillYears
                  ? 'stockDetail.dividendAverageFull'.tr(
                      namedArgs: {'years': '$years'},
                    )
                  : 'stockDetail.dividendAverageSince'.tr(
                      namedArgs: {'year': '$fromYear', 'years': '$years'},
                    ),
              style: labelStyle,
            ),
          ),
          ..._amountCells(context, cash: cash, stockShares: stockShares),
        ],
      DividendAverageBuilding() => [
        Expanded(
          flex: 2,
          child: Text('stockDetail.dividendAverage'.tr(), style: labelStyle),
        ),
        _statusCell(context, 'stockDetail.dividendStatusBuilding'.tr()),
      ],
    };
  }

  Widget _statusCell(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Expanded(
      flex: 6,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<Widget> _amountCells(
    BuildContext context, {
    required double cash,
    required double stockShares,
    int cashCount = 0,
  }) {
    final theme = Theme.of(context);
    final stockYuan = summary.stockYuan(stockShares);
    final total = summary.totalYuan(cash, stockShares);
    return [
      Expanded(
        flex: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              cash > 0 ? AppNumberFormat.currency(cash, decimals: 2) : '-',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                // 品牌藍（AppTheme.dividendColor）只對深色底校準過，淺色底
                // 不到 3:1；primary 在淺色主題是 brandOnLight、深色主題同色
                color: cash > 0 ? theme.colorScheme.primary : null,
              ),
            ),
            if (cashCount > 1)
              Text(
                'stockDetail.dividendCashCount'.tr(
                  namedArgs: {'count': '$cashCount'},
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          stockShares <= 0
              ? '-'
              : stockYuan != null
              ? AppNumberFormat.currency(stockYuan, decimals: 2)
              : 'stockDetail.dividendSharesPerThousand'.tr(
                  namedArgs: {'shares': _sharesFormat.format(stockShares)},
                ),
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          total == null
              ? '—'
              : total > 0
              ? AppNumberFormat.currency(total, decimals: 2)
              : '-',
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    ];
  }
}

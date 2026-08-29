import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/taiwan_date_formatter.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/domain/services/revenue_stats.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_helpers.dart';

/// 顯示近 12 個月營收資料表，附月增率與年增率成長標章。
class RevenueTable extends StatelessWidget {
  const RevenueTable({
    super.key,
    required this.revenues,
    required this.showROCYear,
  });

  final List<FinMindRevenue> revenues;
  final bool showROCYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Sort by date descending and take last 12
    final sortedData = List<FinMindRevenue>.from(revenues)
      ..sort((a, b) {
        final yearCompare = b.revenueYear.compareTo(a.revenueYear);
        if (yearCompare != 0) return yearCompare;
        return b.revenueMonth.compareTo(a.revenueMonth);
      });
    final displayData = sortedData.take(12).toList();

    // 使用者選股法則 L2 門檻：「年增 > 30%，取近 3 月均值防單月雜訊」。
    // 不足三月或缺值時為 null（不顯示，不硬湊）。
    final avg3m = yoy3mAvg([
      for (final r in revenues)
        (year: r.revenueYear, month: r.revenueMonth, yoy: r.yoyGrowth),
    ]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing12),
        child: Column(
          children: [
            if (avg3m != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'stockDetail.revenueYoY3mAvg'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // 沿用表格同款 growth badge（round-then-sign／平盤中性色）
                  buildGrowthBadge(context, avg3m),
                ],
              ),
              const SizedBox(height: DesignTokens.spacing8),
            ],
            buildTableHeader(context, [
              buildHeaderCell(
                context,
                'stockDetail.revenueMonth'.tr(),
                flex: 3,
              ),
              buildHeaderCell(
                context,
                'stockDetail.revenueAmount'.tr(),
                flex: 3,
                textAlign: TextAlign.end,
              ),
              buildHeaderCell(
                context,
                'stockDetail.revenueMoM'.tr(),
                textAlign: TextAlign.end,
              ),
              buildHeaderCell(
                context,
                'stockDetail.revenueYoY'.tr(),
                textAlign: TextAlign.end,
              ),
            ]),
            const SizedBox(height: DesignTokens.spacing8),
            ...displayData.asMap().entries.map((entry) {
              final index = entry.key;
              final rev = entry.value;

              return buildTableDataRow(context, index, [
                Expanded(
                  flex: 3,
                  child: Text(
                    showROCYear
                        ? TaiwanDateFormatter.formatYearMonth(
                            rev.revenueYear,
                            rev.revenueMonth,
                          )
                        : '${rev.revenueYear}/${rev.revenueMonth.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: index == 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _formatRevenue(rev.revenue),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: buildGrowthBadge(context, rev.momGrowth),
                ),
                Expanded(
                  flex: 2,
                  child: buildGrowthBadge(context, rev.yoyGrowth),
                ),
              ]);
            }),
          ],
        ),
      ),
    );
  }

  /// [revenue] 單位為**千元**（見 `FinMindRevenue.revenue` 的欄位慣例）。
  ///
  /// 千元 → 億元 要 ÷100,000；千元 → 萬元 要 **÷10**（曾誤寫成 ÷10,000，
  /// 使該區間的數字小 1000 倍：99,976 千元（約 1 億）顯示成「10.0萬」。
  /// 破綻是交界處——R 從 99,999 走到 100,000，畫面從「10.0萬」跳成「1.0億」。
  /// 實測 1,976 檔中有 465 檔的最新月營收落在該區間）。
  String _formatRevenue(double revenue) {
    if (revenue >= 100000) {
      return '${(revenue / 100000).toStringAsFixed(1)}${'stockDetail.unitBillion'.tr()}';
    } else if (revenue >= 10000) {
      return '${(revenue / 10).toStringAsFixed(1)}${'stockDetail.unitTenThousand'.tr()}';
    }
    return '${revenue.toStringAsFixed(0)}${'stockDetail.unitThousand'.tr()}';
  }
}

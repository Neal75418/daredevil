import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';

export 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_helpers.dart'
    show buildEmptyState;

/// 籌碼 Tab 各區塊共用的輔助 Widget 與格式化工具。

/// 法人淨額摘要卡。
///
/// 圖示不再吃呼叫端傳入的法人分類色——法人色移除後三張卡片一律傳
/// `CategoryColors.neutral`（`#A1A1AA`），對本卡片底色
/// `surfaceContainerLow`（淺色主題 `#F8F9FA`）僅 2.43:1、對白色 Card
/// 2.56:1，兩者皆低於圖形物件門檻 3.0:1——比改動前的投信紫 `#9B59B6`
/// （4.43／4.67，合格）明確退步。而設計文件移除法人色的理由正是
/// 「身分改由圖示形狀區分」，被推上去承擔身分的圖示反而看不見。
///
/// 改走 `theme.colorScheme.onSurfaceVariant`：淺色 `#666680` 對
/// `#F8F9FA` 5.27:1，深色與 `CategoryColors.neutral` 同值（`#A1A1AA`）
/// 5.81:1、視覺零變化。手法與同一輪的 `institutional_flow_chart.dart`
/// 及 `institutional_section._buildTrendChart` 一致。
Widget buildSummaryCard(
  BuildContext context,
  String label,
  double value,
  IconData icon,
) {
  final theme = Theme.of(context);
  // 平盤（0）著中性色，不得著漲跌方向色（與 formatNet 的「0」文字一致）。
  // 走 getPriceColor 而非自行 switch：淺色主題才拿得到較深的下跌綠與平盤灰。
  final valueColor = AppTheme.getPriceColor(value, theme.brightness);

  return Container(
    padding: const EdgeInsets.all(DesignTokens.spacing12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      // 邊框原為 accentColor@0.3；法人身分色移除後改用容器邊界的語意 token。
      border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: DesignTokens.spacing4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacing6),
        Text(
          formatNet(value, Localizations.localeOf(context)),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

/// 法人明細表的欄位標題（8px 圓點 + 文字）。
///
/// 圓點的取色理由與退步數字同 [buildSummaryCard]——原名
/// `buildColoredHeader` 帶一個 `Color` 參數，法人色移除後三個呼叫端都傳
/// 同一個 `CategoryColors.neutral`，參數已無區辨作用且把不合格的色值
/// 推回呼叫端，故一併移除。
Widget buildColumnHeader(ThemeData theme, String label) {
  return Expanded(
    flex: 2,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    ),
  );
}

Widget buildDataRow(
  BuildContext context,
  ThemeData theme,
  int index,
  String dateLabel,
  List<double> values,
) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    decoration: BoxDecoration(
      color: index == 0
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : (index.isEven ? theme.colorScheme.surface : Colors.transparent),
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            dateLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        for (final v in values)
          Expanded(flex: 2, child: buildNetValue(context, v)),
      ],
    ),
  );
}

Widget buildNetValue(BuildContext context, double value) {
  // 平盤（0）著中性色，不得著漲跌方向色
  final color = AppTheme.getPriceColor(value, Theme.of(context).brightness);

  return Text(
    formatNet(value, Localizations.localeOf(context)),
    textAlign: TextAlign.end,
    style: TextStyle(
      fontSize: DesignTokens.fontSizeSm,
      fontWeight: FontWeight.w500,
      color: color,
    ),
  );
}

/// 格式化張數，依量級自動升階：中文 萬張/千張/張，其他語系走
/// [LocalizedNumberFormat.compact]（K/M…）。
///
/// 核心輔助函式，供 [formatNet]、[formatBalance] 及成交量格式化使用。
String formatLots(double lots, Locale locale) {
  final unit = 'stockDetail.unitShares'.tr();
  if (!LocalizedNumberFormat.usesChineseUnits(locale)) {
    return '${LocalizedNumberFormat.compact(lots, locale)}$unit';
  }
  if (lots >= 10000) {
    return '${(lots / 10000).toStringAsFixed(1)}萬$unit';
  } else if (lots >= 1000) {
    return '${(lots / 1000).toStringAsFixed(1)}千$unit';
  }
  return '${lots.toStringAsFixed(0)}$unit';
}

/// 格式化淨值，自動加正負號並轉換為張數單位。
/// 平盤（0）不帶符號（顯示「0」而非「+0」）。
String formatNet(double value, Locale locale) {
  final prefix = value > 0 ? '+' : (value < 0 ? '-' : '');
  final lots = value.abs() / 1000;
  if (lots < 1) return '${value > 0 ? '+' : ''}${value.toStringAsFixed(0)}';
  return '$prefix${formatLots(lots, locale)}';
}

/// 格式化餘額（已為張數單位）
String formatBalance(double value, Locale locale) => formatLots(value, locale);

/// 格式化持股變動（以千股為單位）。平盤（0）不帶 `+`。
String formatSharesChange(double value) {
  final prefix = value > 0 ? '+' : '';
  final absValue = value.abs();
  if (absValue >= 1000) {
    return '$prefix${(value / 1000).toStringAsFixed(1)}${'stockDetail.unitThousand'.tr()}${'stockDetail.unitShares'.tr()}';
  }
  return '$prefix${value.toStringAsFixed(0)}${'stockDetail.unitShares'.tr()}';
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:k_chart_plus/k_chart_plus.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/localized_number_format.dart';

/// 長按 K 棒時顯示的詳情浮層。
///
/// k_chart_plus 1.0.4 把內建的 `chartTranslations` 拿掉、改成由 app 提供
/// `detailBuilder`——好處是浮層樣式終於能跟 app 主題一致(套件版是固定的
/// 淺色卡片)。欄位與 i18n key 沿用既有的 `stockDetail.*`。
class KChartDetailPopup extends StatelessWidget {
  const KChartDetailPopup({
    super.key,
    required this.entity,
    this.fixedLength = 2,
  });

  final KLineEntity entity;
  final int fixedLength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(entity.time ?? 0);
    // change/ratio 由 KLineChartWidget 以「vs 前一根收盤」填入(2026-08-05
    // 複審修正:原 fallback close−open 是當日 K 內語意,跳空日方向會反)。
    // 首根無昨收 → null → 顯示 -- 、中性色。
    final change = entity.change;
    final changePct = entity.ratio;
    final changeColor = AppTheme.getPriceColor(change, theme.brightness);

    return Container(
      margin: const EdgeInsets.all(DesignTokens.spacing8),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing12,
        vertical: DesignTokens.spacing8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.96,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            intl.DateFormat('yyyy/MM/dd').format(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing4),
          _row(theme, 'stockDetail.open'.tr(), _fmt(entity.open)),
          _row(theme, 'stockDetail.high'.tr(), _fmt(entity.high)),
          _row(theme, 'stockDetail.low'.tr(), _fmt(entity.low)),
          _row(theme, 'stockDetail.close'.tr(), _fmt(entity.close)),
          _row(
            theme,
            'stockDetail.change'.tr(),
            change == null ? '--' : _fmt(change),
            valueColor: changeColor,
          ),
          _row(
            theme,
            'stockDetail.changePercent'.tr(),
            changePct == null ? '--' : '${changePct.toStringAsFixed(2)}%',
            valueColor: changeColor,
          ),
          _row(
            theme,
            'stockDetail.volume'.tr(),
            LocalizedNumberFormat.compact(
              entity.vol,
              Localizations.localeOf(context),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(fixedLength);

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              color: valueColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

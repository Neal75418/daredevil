import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

/// 資料落後提示（琥珀底）：「資料落後 N 個交易日（最新 M/D 收盤）· 立即更新」
///
/// 何時顯示由呼叫端決定（今日頁以交易日計算落後、更新中隱藏）；
/// 這裡只負責呈現，色彩組合登記在 semantic_colors 守門表（Today.dataStale）。
class DataStaleBanner extends StatelessWidget {
  const DataStaleBanner({
    super.key,
    required this.dataDate,
    required this.tradingDaysBehind,
    required this.onUpdate,
  });

  final DateTime dataDate;
  final int tradingDaysBehind;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = WarningColors.onTintFor(theme.brightness);
    return Container(
      padding: const EdgeInsets.only(
        left: DesignTokens.spacing12,
        right: DesignTokens.spacing4,
      ),
      decoration: BoxDecoration(
        color: WarningColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: fg),
          const SizedBox(width: DesignTokens.spacing8),
          Expanded(
            child: Text(
              'today.dataStale'.tr(
                namedArgs: {
                  'count': '$tradingDaysBehind',
                  'date': '${dataDate.month}/${dataDate.day}',
                },
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onUpdate,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              minimumSize: const Size(48, 44),
            ),
            child: Text('today.updateNow'.tr()),
          ),
        ],
      ),
    );
  }
}

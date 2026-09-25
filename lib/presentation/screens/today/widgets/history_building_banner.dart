import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/services/update/history_coverage.dart';

/// 歷史資料建置中提示：新安裝約需十多次更新才補齊一年歷史，這段期間
/// 訊號以不完整的歷史計算（52 週新高等長週期規則可能還不會觸發）。
///
/// 用主題的 primaryContainer／onPrimaryContainer 配對（Material 保證對比），
/// 資訊性質、不是警示。
class HistoryBuildingBanner extends StatelessWidget {
  const HistoryBuildingBanner({super.key, required this.coverage});

  final HistoryCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing12,
        vertical: DesignTokens.spacing8,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top, size: 16, color: scheme.onPrimaryContainer),
          const SizedBox(width: DesignTokens.spacing8),
          Expanded(
            child: Text(
              'today.historyBuilding'.tr(
                namedArgs: {
                  'percent': '${coverage.percent}',
                  'runs': '${coverage.remainingRuns}',
                },
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

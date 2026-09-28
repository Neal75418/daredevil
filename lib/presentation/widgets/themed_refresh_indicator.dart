import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/theme/app_theme.dart';

/// 重新整理操作的預設逾時時間
const _defaultTimeout = Duration(seconds: ApiConfig.refreshTimeoutSec);

/// 套用主題色與觸覺回饋的 RefreshIndicator
class ThemedRefreshIndicator extends StatelessWidget {
  const ThemedRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.timeout = _defaultTimeout,
  });

  final Widget child;
  final Future<void> Function() onRefresh;
  final double displacement;
  final double edgeOffset;

  /// 重新整理操作的逾時時間（預設 30 秒）
  final Duration timeout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.isDark;

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        try {
          await onRefresh().timeout(timeout);
        } on TimeoutException {
          // 逾時靜默處理 — indicator 會自動停止旋轉
        }
        HapticFeedback.lightImpact();
      },
      displacement: displacement,
      edgeOffset: edgeOffset,
      // 旋轉弧線是圖形物件（3:1）：AppTheme.primaryColor 對淺色
      // backgroundColor（surface #F8F9FA）不足 3:1（現為 2.41:1），改走主題
      // primary（淺色 brandOnLight，6.36:1）；深色同值不變。
      color: theme.colorScheme.primary,
      backgroundColor: isDark
          ? theme.colorScheme.surfaceContainerHigh
          : theme.colorScheme.surface,
      strokeWidth: 2.5,
      child: child,
    );
  }
}

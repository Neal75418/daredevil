import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/presentation/widgets/api_rate_limit_dialog.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 資料管理項目：強制同步與歷史資料進度
class DataManagementTile extends ConsumerStatefulWidget {
  const DataManagementTile({super.key});

  @override
  ConsumerState<DataManagementTile> createState() => _DataManagementTileState();
}

class _DataManagementTileState extends ConsumerState<DataManagementTile> {
  bool _isSyncing = false;
  String? _syncResult;
  bool? _syncSuccess;
  bool _hasWarnings = false;
  ({int completed, int total})? _historyProgress;

  @override
  void initState() {
    super.initState();
    _loadHistoryProgress();
  }

  Future<void> _loadHistoryProgress() async {
    final db = ref.read(databaseProvider);
    final progress = await db.getHistoricalDataProgress();
    if (mounted) {
      setState(() => _historyProgress = progress);
    }
  }

  Future<void> _forceSync() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings.forceSyncTitle'.tr()),
        content: Text('settings.forceSyncConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('settings.forceSync'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSyncing = true;
      _syncResult = null;
      _syncSuccess = null;
      _hasWarnings = false;
    });

    try {
      final result = await ref
          .read(todayProvider.notifier)
          .runUpdate(force: true);

      if (mounted) {
        final rateLimitErrors = result.errors.where(isRateLimitError).toList();
        if (rateLimitErrors.isNotEmpty) {
          showApiRateLimitDialog(
            context,
            finMind: rateLimitErrors.any(isFinMindRateLimit),
          );
        }

        setState(() {
          _isSyncing = false;
          // hasWarnings = 主更新成功但有後段步驟失敗（如重載大盤/推薦）
          _syncSuccess = result.success;
          _hasWarnings = result.hasWarnings;
          _syncResult = result.success
              ? result
                    .summary // summary 已包含警告數量（e.g.「… 3 項警告」）
              : 'settings.forceSyncFailed'.tr(
                  namedArgs: {'error': 'common.syncFailed'.tr()},
                );
        });
        _loadHistoryProgress();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (isRateLimitError(msg)) {
          showApiRateLimitDialog(context, finMind: isFinMindRateLimit(msg));
        }

        setState(() {
          _isSyncing = false;
          _syncSuccess = false;
          _syncResult = 'settings.forceSyncFailed'.tr(
            namedArgs: {'error': ErrorDisplay.message(e)},
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.sync_rounded, color: theme.colorScheme.primary),
          title: Text('settings.forceSync'.tr()),
          subtitle: Text('settings.forceSyncDescription'.tr()),
          trailing: _isSyncing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _isSyncing ? null : _forceSync,
        ),
        if (_syncResult != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _syncSuccess != true
                      ? Icons.error
                      : _hasWarnings
                      ? Icons.warning_amber
                      : Icons.check_circle,
                  size: 16,
                  color: _syncSuccess != true
                      ? AppTheme.errorColor
                      : _hasWarnings
                      ? DesignTokens.warningColor(theme)
                      : DesignTokens.successColor(theme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _syncResult!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _syncSuccess != true
                          ? AppTheme.errorColor
                          : _hasWarnings
                          ? DesignTokens.warningColor(theme)
                          : DesignTokens.successColor(theme),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_historyProgress != null) _buildHistoryProgress(theme),
      ],
    );
  }

  Widget _buildHistoryProgress(ThemeData theme) {
    final progress = _historyProgress!;
    final percent = progress.total > 0
        ? (progress.completed / progress.total * 100).round()
        : 0;
    final isComplete = percent >= 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.check_circle : Icons.history,
                size: 16,
                color: isComplete
                    ? DesignTokens.successColor(theme)
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'settings.historyProgress'.tr(
                    namedArgs: {
                      'completed': progress.completed.toString(),
                      'total': progress.total.toString(),
                      'percent': percent.toString(),
                    },
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            child: LinearProgressIndicator(
              value: progress.total > 0
                  ? progress.completed / progress.total
                  : 0,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete
                    ? DesignTokens.successColor(theme)
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

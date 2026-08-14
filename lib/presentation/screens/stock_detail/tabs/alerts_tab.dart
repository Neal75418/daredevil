import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/widgets/alert_type_icon.dart';
import 'package:daredevil/presentation/providers/notification_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';
import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/services/alert/alert_target_calculator.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/alert_quick_set.dart';

/// 到價提醒分頁 - 個股價格警示設定
class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  @override
  void initState() {
    super.initState();
    // Tab 初始化時載入警示
    Future.microtask(() {
      ref.read(priceAlertProvider.notifier).loadAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = ref.watch(
      stockDetailProvider(
        widget.symbol,
      ).select((s) => s.price.latestPrice?.close),
    );
    final priceHistory = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.price.priceHistory),
    );
    final alertState = ref.watch(priceAlertProvider);

    // 篩選此股票的警示
    final stockAlerts = alertState.alerts
        .where((alert) => alert.symbol == widget.symbol)
        .toList();

    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 當前價格顯示
          if (currentPrice != null) ...[
            _buildCurrentPriceCard(context, currentPrice),
            const SizedBox(height: DesignTokens.spacing24),
          ],

          // 快捷提醒(2026-08-07):價位 app 算好,使用者點一下就掛——
          // 主動權仍在使用者,app 不自動決定要盯什麼
          AlertQuickSet(
            bars: AlertQuickSet.toOhlc(priceHistory),
            currentPrice: currentPrice,
            // 已存在的目標價 → 該種類停用,避免建出一模一樣的第二筆
            existingTargets: {
              // 必須帶方向:同一個價位可以同時是「跌破」與「突破」兩種
              // 提醒(月線最典型),只比價格會把沒建過的那一種也封死
              for (final a in stockAlerts)
                if (a.isActive && a.triggeredAt == null)
                  (a.alertType, a.targetValue),
            },
            onSelected: (kind, target) =>
                _createQuickAlert(context, ref, kind, target),
          ),
          const SizedBox(height: DesignTokens.spacing20),

          // Alerts list
          SectionHeader(
            title: 'alert.title'.tr(),
            icon: Icons.notifications_active,
          ),
          const SizedBox(height: DesignTokens.spacing12),

          if (alertState.isLoading && stockAlerts.isEmpty)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (alertState.error != null && stockAlerts.isEmpty)
            _buildErrorState(context, ref, alertState.error!)
          else if (stockAlerts.isEmpty)
            _buildEmptyState(context)
          else ...[
            if (alertState.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacing12),
                child: MaterialBanner(
                  content: Text(alertState.error!),
                  leading: Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        ref.read(priceAlertProvider.notifier).clearError();
                        ref.read(priceAlertProvider.notifier).loadAlerts();
                      },
                      child: Text('common.retry'.tr()),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(priceAlertProvider.notifier).clearError(),
                      child: Text('common.dismiss'.tr()),
                    ),
                  ],
                ),
              ),
            ...stockAlerts.map((alert) => _buildAlertCard(context, ref, alert)),
          ],

          const SizedBox(height: DesignTokens.spacing16),

          // 新增警示按鈕
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showAddAlertDialog(context, ref, currentPrice),
              icon: const Icon(Icons.add),
              label: Text('alert.create'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createQuickAlert(
    BuildContext context,
    WidgetRef ref,
    AlertKind kind,
    AlertTarget target,
  ) async {
    final label = 'alert.quickSet.${kind.name}'.tr();
    // 🚨 建立時就要拿到權限(2026-08-08 二次審查):盤中輪詢的前置守門
    // 會在無權限時整輪跳過,若這裡不請求,使用者一輩子不會被通知,而且
    // 完全沒有徵兆。既有的 price_alert_dialog 本來就有這一步,個股頁
    // 的兩條路徑都漏了。
    // 🚨 回傳值不可丟(2026-08-08 三次審查 H-2):它為 false 時提醒仍會
    // 寫進 DB,但 GUI 輪詢會整輪跳過。若照樣顯示「已設定提醒」,使用者
    // 會相信盯盤已生效然後永遠等不到通知——謊報成功比報錯更糟。
    final granted = await ref
        .read(notificationProvider.notifier)
        .ensurePermission();
    final ok = await ref
        .read(priceAlertProvider.notifier)
        .createAlert(
          symbol: widget.symbol,
          // 用 AlertTarget 自己的映射,而非在此重新推導——它的存在理由
          // 就是防兩套邏輯漂移(2026-08-08 code review 指出原本沒用到)
          alertType: AlertType.values.firstWhere(
            (t) => t.value == target.alertTypeValue,
          ),
          targetValue: target.price,
          note: label,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? 'alert.createFailed'.tr()
              : granted
              ? 'alert.quickSet.created'.tr(
                  namedArgs: {
                    'label': label,
                    'price': target.price.toStringAsFixed(2),
                  },
                )
              // 建立成功但系統未授權:提醒存在,只是 App 開著時不會跳通知
              : 'alert.createdNoPermission'.tr(),
        ),
      ),
    );
  }

  Widget _buildCurrentPriceCard(BuildContext context, double price) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing16),
        child: Row(
          children: [
            Icon(
              Icons.monetization_on,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: DesignTokens.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'stockDetail.currentPrice'.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                  Text(
                    AppNumberFormat.currency(price, decimals: 2),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: DesignTokens.spacing12),
            Text(
              'alert.noAlerts'.tr(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: DesignTokens.spacing4),
            Text(
              'alert.noAlertsHint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: DesignTokens.spacing12),
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignTokens.spacing12),
            TextButton.icon(
              onPressed: () {
                ref.read(priceAlertProvider.notifier).clearError();
                ref.read(priceAlertProvider.notifier).loadAlerts();
              },
              icon: const Icon(Icons.refresh),
              label: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(
    BuildContext context,
    WidgetRef ref,
    PriceAlertEntry alert,
  ) {
    final theme = Theme.of(context);
    final alertType =
        AlertType.tryFromValue(alert.alertType) ?? AlertType.above;

    final description = getAlertDescription(alert, alertType);

    return Dismissible(
      key: Key('alert_${alert.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: DesignTokens.spacing16),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('common.delete'.tr()),
            content: Text('alert.deleteConfirm'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('common.cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.errorColor,
                ),
                child: Text('common.delete'.tr()),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        final notifier = ref.read(priceAlertProvider.notifier);
        notifier.deleteAlert(alert.id).then((_) {
          if (!context.mounted) return;
          final alertState = ref.read(priceAlertProvider);
          if (alertState.error != null) {
            notifier.clearError();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(alertState.error!),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('alert.deleted'.tr()),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: DesignTokens.spacing8),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: alert.isActive
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Icon(
              alertType.icon,
              color: alert.isActive
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.outline,
            ),
          ),
          title: Text(
            description,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: alert.isActive ? null : theme.colorScheme.outline,
            ),
          ),
          subtitle: alert.note?.isNotEmpty == true
              ? Text(alert.note!, style: theme.textTheme.bodySmall)
              : null,
          trailing: Switch(
            value: alert.isActive,
            onChanged: (value) {
              ref
                  .read(priceAlertProvider.notifier)
                  .toggleAlert(alert.id, value);
            },
          ),
        ),
      ),
    );
  }

  void _showAddAlertDialog(
    BuildContext context,
    WidgetRef ref,
    double? currentPrice,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: Breakpoints.sheetMaxWidth),
      builder: (context) => _AddAlertSheet(
        symbol: widget.symbol,
        currentPrice: currentPrice,
        onCreated: () {
          ref.read(priceAlertProvider.notifier).loadAlerts();
        },
      ),
    );
  }
}

/// 新增到價提醒 Bottom Sheet
class _AddAlertSheet extends ConsumerStatefulWidget {
  const _AddAlertSheet({
    required this.symbol,
    required this.currentPrice,
    required this.onCreated,
  });

  final String symbol;
  final double? currentPrice;
  final VoidCallback onCreated;

  @override
  ConsumerState<_AddAlertSheet> createState() => _AddAlertSheetState();
}

class _AddAlertSheetState extends ConsumerState<_AddAlertSheet> {
  AlertType _selectedType = AlertType.above;
  final _valueController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: DesignTokens.spacing16,
        right: DesignTokens.spacing16,
        top: 0,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + DesignTokens.spacing16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          const DragHandle(
            margin: EdgeInsets.only(
              top: DesignTokens.spacing12,
              bottom: DesignTokens.spacing8,
            ),
          ),
          // Header
          Row(
            children: [
              Text(
                'alert.create'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacing8),

          // Current price info
          if (widget.currentPrice case final currentPrice?)
            Container(
              padding: const EdgeInsets.all(DesignTokens.spacing12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: DesignTokens.spacing8),
                  Text(
                    'stockDetail.currentPrice'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    AppNumberFormat.currency(currentPrice, decimals: 2),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: DesignTokens.spacing16),

          // Alert type selector（快速建立只提供 3 種常用類型）
          // 完整類型清單（AlertType.values）可從「警示」分頁的「+」按鈕建立
          Text('alert.type'.tr(), style: theme.textTheme.labelLarge),
          const SizedBox(height: DesignTokens.spacing8),
          SegmentedButton<AlertType>(
            segments: [
              ButtonSegment(
                value: AlertType.above,
                label: Text('alert.typeAbove'.tr()),
                icon: const Icon(Icons.trending_up, size: 18),
              ),
              ButtonSegment(
                value: AlertType.below,
                label: Text('alert.typeBelow'.tr()),
                icon: const Icon(Icons.trending_down, size: 18),
              ),
              ButtonSegment(
                value: AlertType.changePct,
                label: Text('alert.typeChange'.tr()),
                icon: const Icon(Icons.percent, size: 18),
              ),
            ],
            selected: {_selectedType},
            onSelectionChanged: (selected) {
              setState(() {
                _selectedType = selected.first;
              });
            },
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // Target value input
          Text(
            _selectedType == AlertType.changePct
                ? 'alert.targetPercent'.tr()
                : 'alert.targetPrice'.tr(),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: DesignTokens.spacing8),
          TextField(
            controller: _valueController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              hintText: _selectedType == AlertType.changePct
                  ? 'alert.percentHint'.tr()
                  : 'alert.priceHint'.tr(),
              suffixText: _selectedType == AlertType.changePct
                  ? '%'
                  : 'alert.currency'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // Note input
          Text('alert.note'.tr(), style: theme.textTheme.labelLarge),
          const SizedBox(height: DesignTokens.spacing8),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              hintText: 'alert.noteHint'.tr(),
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
            maxLength: 500,
          ),
          const SizedBox(height: DesignTokens.spacing24),

          // Create button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isCreating ? null : _createAlert,
              icon: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text('alert.create'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createAlert() async {
    final valueText = _valueController.text.trim();
    if (valueText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('alert.emptyValue'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final value = double.tryParse(valueText);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('alert.notANumber'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('alert.mustBePositive'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    // 同快捷鈕:建立時就要拿到權限,否則盤中輪詢會整輪跳過且無徵兆
    // 🚨 回傳值不可丟(2026-08-08 三次審查 H-2):它為 false 時提醒仍會
    // 寫進 DB,但 GUI 輪詢會整輪跳過。若照樣顯示「已設定提醒」,使用者
    // 會相信盯盤已生效然後永遠等不到通知——謊報成功比報錯更糟。
    final granted = await ref
        .read(notificationProvider.notifier)
        .ensurePermission();

    final success = await ref
        .read(priceAlertProvider.notifier)
        .createAlert(
          symbol: widget.symbol,
          alertType: _selectedType,
          targetValue: value,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );

    setState(() => _isCreating = false);

    if (success && mounted) {
      widget.onCreated();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted ? 'alert.created'.tr() : 'alert.createdNoPermission'.tr(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('alert.createFailed'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

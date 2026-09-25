import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/presentation/providers/notification_provider.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 顯示建立或編輯價格警示的對話框
///
/// 傳入 [existingAlert] 時為編輯模式，pre-populate 既有值。
Future<bool?> showCreatePriceAlertDialog({
  required BuildContext context,
  required String symbol,
  String? stockName,
  double? currentPrice,
  PriceAlertEntry? existingAlert,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => CreatePriceAlertDialog(
      symbol: symbol,
      stockName: stockName,
      currentPrice: currentPrice,
      existingAlert: existingAlert,
    ),
  );
}

/// 建立價格警示的對話框
class CreatePriceAlertDialog extends ConsumerStatefulWidget {
  const CreatePriceAlertDialog({
    super.key,
    required this.symbol,
    this.stockName,
    this.currentPrice,
    this.existingAlert,
  });

  final String symbol;
  final String? stockName;
  final double? currentPrice;
  final PriceAlertEntry? existingAlert;

  bool get isEditing => existingAlert != null;

  @override
  ConsumerState<CreatePriceAlertDialog> createState() =>
      _CreatePriceAlertDialogState();
}

class _CreatePriceAlertDialogState
    extends ConsumerState<CreatePriceAlertDialog> {
  late AlertType _selectedType;
  final _valueController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingAlert case final alert?) {
      // 編輯模式：pre-populate 既有值
      _selectedType = AlertType.fromValue(alert.alertType);
      _valueController.text = alert.targetValue.toStringAsFixed(2);
      _noteController.text = alert.note ?? '';
    } else {
      // 建立模式
      _selectedType = AlertType.above;
      _valueController.text = _selectedType.initialInputText(
        currentPrice: widget.currentPrice,
      );
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.isEditing ? 'alert.edit'.tr() : 'alert.create'.tr()),
      content: ConstrainedBox(
        // 對話框需要寬度上限(2026-08-08 實機:3740px 的視窗下整個拉滿,
        // 「179.95」在最左、「元」在最右,兩者視覺上斷開)。AlertDialog
        // 本身不限內容寬度,而裡面的 Wrap 會吃滿可用寬度。560 是 Material 3
        // 對話框的標準上限;窄視窗時它只是上限、不影響收縮。
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 股票資訊
              Container(
                padding: const EdgeInsets.all(DesignTokens.spacing12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.symbol,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.stockName != null) ...[
                      const SizedBox(width: DesignTokens.spacing8),
                      Expanded(
                        child: Text(
                          widget.stockName!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: DesignTokens.spacing16),

              // 警示類型選擇
              Text(
                'alert.type'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DesignTokens.spacing8),
              // 🚨 不可用 SegmentedButton(2026-08-08 實機:視窗縮小時
              // RenderFlex overflow,標籤被壓成直排)。SegmentedButton 本質是
              // 一個 **Row——不換行、不捲動**,設計給 2~5 個互斥選項;這裡有
              // 23 種已實作的提醒類型,任何寬度不夠的視窗都必然爆版。
              // Wrap + ChoiceChip 會依可用寬度自動換行。
              //
              // 分成兩組(2026-08-08):這 23 種**不等價**——只有價格高於/
              // 低於會被盤中 CLI 每 5 分鐘檢查,其餘 21 種只有 app 內的收盤
              // 路徑會評估。平鋪成一排會讓人以為全部都是即時的。
              _buildTypeGroup(
                context,
                theme,
                title: 'alert.typeGroup.intraday'.tr(),
                subtitle: 'alert.typeGroup.intradayHint'.tr(),
                types: AlertType.values
                    .where(
                      (t) =>
                          t.isImplemented &&
                          AlertParams.intradayMonitoredTypes.contains(t.value),
                    )
                    .toList(),
              ),
              const SizedBox(height: DesignTokens.spacing12),
              _buildTypeGroup(
                context,
                theme,
                title: 'alert.typeGroup.daily'.tr(),
                subtitle: 'alert.typeGroup.dailyHint'.tr(),
                subtitleIsWarning: true,
                types: AlertType.values
                    .where(
                      (t) =>
                          t.isImplemented &&
                          !AlertParams.intradayMonitoredTypes.contains(t.value),
                    )
                    .toList(),
              ),
              const SizedBox(height: DesignTokens.spacing16),

              // 目標值輸入（自動觸發型不需要，整欄隱藏）
              if (_selectedType.requiresTargetValue) ...[
                TextField(
                  controller: _valueController,
                  decoration: InputDecoration(
                    labelText: _getValueLabel(),
                    hintText: _getValueHint(),
                    suffixText: _getValueSuffix(),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacing16),
              ],

              // 備註輸入（選填）
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: 'alert.note'.tr(),
                  hintText: 'alert.noteHint'.tr(),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                maxLength: 500,
              ),

              // 當前價格提示
              if (widget.currentPrice case final price?) ...[
                const SizedBox(height: DesignTokens.spacing12),
                Text(
                  'alert.currentPrice'.tr(args: [price.toStringAsFixed(2)]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context, false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _createAlert,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  widget.isEditing ? 'common.save'.tr() : 'alert.create'.tr(),
                ),
        ),
      ],
    );
  }

  Widget _buildTypeGroup(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required String subtitle,
    required List<AlertType> types,
    bool subtitleIsWarning = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          subtitle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: subtitleIsWarning
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DesignTokens.spacing8),
        Wrap(
          spacing: DesignTokens.spacing8,
          runSpacing: DesignTokens.spacing8,
          children: [
            for (final type in types)
              ChoiceChip(
                label: Text(
                  _getTypeLabel(type),
                  style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
                ),
                selected: _selectedType == type,
                // 編輯模式鎖定類型：editAlert 只更新數值與備註，切了也不會存
                onSelected: widget.isEditing && type != _selectedType
                    ? null
                    : (picked) {
                        if (!picked) return; // 互斥:不允許取消選取
                        setState(() {
                          _selectedType = type;
                          _valueController.text = type.initialInputText(
                            currentPrice: widget.currentPrice,
                          );
                        });
                      },
              ),
          ],
        ),
      ],
    );
  }

  String _getTypeLabel(AlertType type) {
    return type.label;
  }

  String _getValueLabel() {
    if (!_selectedType.requiresTargetValue) {
      return ''; // 不需要數值
    }
    return switch (_selectedType) {
      AlertType.above || AlertType.below => 'alert.targetPrice'.tr(),
      AlertType.changePct => 'alert.targetPercent'.tr(),
      AlertType.breakResistance ||
      AlertType.breakSupport => 'alert.targetPrice'.tr(),
      AlertType.volumeAbove => 'alert.targetVolume'.tr(),
      AlertType.rsiOverbought ||
      AlertType.rsiOversold => 'alert.rsiThreshold'.tr(),
      AlertType.crossAboveMa || AlertType.crossBelowMa => 'alert.maDays'.tr(),
      AlertType.revenueYoySurge => 'alert.revenueYoyThreshold'.tr(),
      AlertType.highDividendYield => 'alert.dividendYieldThreshold'.tr(),
      AlertType.peUndervalued => 'alert.peThreshold'.tr(),
      _ => '',
    };
  }

  String? _getValueSuffix() {
    if (_selectedType.isPriceTarget) return 'alert.currency'.tr();
    return switch (_selectedType) {
      AlertType.changePct ||
      AlertType.revenueYoySurge ||
      AlertType.highDividendYield => '%',
      AlertType.volumeAbove => 'alert.unit.lots'.tr(),
      AlertType.peUndervalued => 'alert.unit.times'.tr(),
      AlertType.crossAboveMa ||
      AlertType.crossBelowMa => 'alert.unit.dayMa'.tr(),
      _ => null,
    };
  }

  String _getValueHint() {
    if (!_selectedType.requiresTargetValue) {
      return ''; // 不需要數值
    }
    return switch (_selectedType) {
      AlertType.above || AlertType.below => 'alert.priceHint'.tr(),
      AlertType.changePct => 'alert.percentHint'.tr(),
      AlertType.breakResistance ||
      AlertType.breakSupport => 'alert.priceHint'.tr(),
      AlertType.volumeAbove => 'alert.volumeHint'.tr(),
      AlertType.rsiOverbought => 'alert.rsiOverboughtHint'.tr(),
      AlertType.rsiOversold => 'alert.rsiOversoldHint'.tr(),
      AlertType.crossAboveMa || AlertType.crossBelowMa => 'alert.maHint'.tr(),
      _ => '',
    };
  }

  Future<void> _createAlert() async {
    final valueText = _valueController.text.trim();
    if (_selectedType.requiresTargetValue && valueText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('alert.emptyValue'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final value = double.tryParse(valueText);
    if (_selectedType.requiresTargetValue && (value == null || value <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('alert.mustBePositive'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    // 建立提醒前確保已取得通知權限
    final hasPermission = await ref
        .read(notificationProvider.notifier)
        .ensurePermission();

    if (!hasPermission && mounted) {
      // 權限被拒絕，顯示提示但仍允許建立提醒（只是不會收到通知）
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('notification.permissionDenied'.tr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: ApiConfig.alertDialogDurationSec),
        ),
      );
    }

    final note = _noteController.text.isEmpty ? null : _noteController.text;
    // 不需目標值的類型一律存 0，不讓欄位殘值（例如預填現價）混進門檻
    final targetValue = _selectedType.requiresTargetValue ? value! : 0.0;
    final bool success;

    if (widget.isEditing) {
      success = await ref
          .read(priceAlertProvider.notifier)
          .editAlert(
            id: widget.existingAlert!.id,
            targetValue: targetValue,
            note: note,
          );
    } else {
      success = await ref
          .read(priceAlertProvider.notifier)
          .createAlert(
            symbol: widget.symbol,
            alertType: _selectedType,
            targetValue: targetValue,
            note: note,
          );
    }

    if (mounted) {
      setState(() => _isCreating = false);

      if (success) {
        HapticFeedback.lightImpact();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? 'alert.editSuccess'.tr()
                  : 'alert.created'.tr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('alert.createFailed'.tr()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

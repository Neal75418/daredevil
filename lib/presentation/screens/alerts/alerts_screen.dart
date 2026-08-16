import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/responsive_helper.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/widgets/alert_type_icon.dart';
import 'package:daredevil/presentation/widgets/pinned_thesis_section.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/price_alert_dialog.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 價格警示管理畫面
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(priceAlertProvider.notifier).loadAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(priceAlertProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('alert.title'.tr()),
        actions: [
          // 每日更新已會自動重算（UpdateService._refreshTrailingAlertsFailSafe）；
          // 這顆是手動入口——剛加完自選股、或想立刻看到結果時用。
          IconButton(
            icon: const Icon(Icons.stairs_outlined),
            tooltip: 'alert.trailingRefresh'.tr(),
            onPressed: state.isLoading ? null : _refreshTrailingAlerts,
          ),
        ],
      ),
      // 論點失效 section（出場層 Phase 2）置頂：與價格警示獨立的資料源，
      // 價格警示空/載入中也要能看到失效通知；空狀態自身零噪音。
      body: Column(
        children: [
          const PinnedThesisSection(invalidatedOnly: true),
          Expanded(child: _buildAlertBody(state, theme)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAlertDialog(context),
        tooltip: 'alert.create'.tr(),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 依均線階梯重算自動提醒（手動設定的不動，保證在 TrailingMaAlertService）
  Future<void> _refreshTrailingAlerts() async {
    final count = await ref
        .read(priceAlertProvider.notifier)
        .refreshTrailingAlerts();
    if (!mounted) return;

    // error 已由 notifier 寫進 state 並顯示，這裡不重複報一次
    if (ref.read(priceAlertProvider).error != null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'alert.trailingRefreshDone'.tr(namedArgs: {'count': '$count'})
              : 'alert.trailingRefreshEmpty'.tr(),
        ),
      ),
    );
  }

  Widget _buildAlertBody(PriceAlertState state, ThemeData theme) {
    return state.isLoading && state.alerts.isEmpty
        ? const GenericListShimmer(itemCount: 5)
        : state.error != null && state.alerts.isEmpty
        ? ErrorDisplay.isNetworkError(state.error!)
              ? EmptyStates.networkError(
                  onRetry: () =>
                      ref.read(priceAlertProvider.notifier).loadAlerts(),
                )
              : EmptyStates.error(
                  message: state.error!,
                  onRetry: () =>
                      ref.read(priceAlertProvider.notifier).loadAlerts(),
                )
        : state.alerts.isEmpty
        ? _buildEmptyState()
        : Column(
            children: [
              if (state.error != null)
                MaterialBanner(
                  content: Text(state.error!),
                  leading: const Icon(Icons.error_outline),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          ref.read(priceAlertProvider.notifier).loadAlerts(),
                      child: Text('common.retry'.tr()),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(priceAlertProvider.notifier).clearError(),
                      child: Text('common.dismiss'.tr()),
                    ),
                  ],
                ),
              Expanded(
                child: _buildAlertsList(state.alerts, state.stockNames, theme),
              ),
            ],
          );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.notifications_off_outlined,
      title: 'alert.noAlerts'.tr(),
      subtitle: 'alert.noAlertsHint'.tr(),
    );
  }

  Widget _buildAlertsList(
    List<PriceAlertEntry> alerts,
    Map<String, String> stockNames,
    ThemeData theme,
  ) {
    // 依股票代號分組警示
    final groupedAlerts = <String, List<PriceAlertEntry>>{};
    for (final alert in alerts) {
      groupedAlerts.putIfAbsent(alert.symbol, () => []).add(alert);
    }

    final horizontalPadding = context.responsiveHorizontalPadding;

    return ThemedRefreshIndicator(
      onRefresh: () => ref.read(priceAlertProvider.notifier).loadAlerts(),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 16,
        ),
        itemCount: groupedAlerts.length,
        itemBuilder: (context, index) {
          final symbol = groupedAlerts.keys.elementAt(index);
          final symbolAlerts = groupedAlerts[symbol]!;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 股票標題
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          // 徽章承載白字：AppTheme.primaryColor 恆為深色
                          // 主題的品牌亮色（現為 Blue 400 #60A5FA），白字
                          // 對比不足；改走主題 primary——淺色解析為
                          // brandOnLight 深藍、白字達標，深色維持同值。
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusXs,
                          ),
                        ),
                        child: Text(
                          symbol,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 名稱:只顯示代碼的話,提醒一多就認不出是哪一檔
                      // (2026-08-08 實機回報)。查不到名稱時整段省略,
                      // 不要顯示空白或代碼重複。
                      if (stockNames[symbol] != null) ...[
                        Flexible(
                          child: Text(
                            stockNames[symbol]!,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${symbolAlerts.length} ${'alert.title'.tr()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // 警示列表
                ...symbolAlerts.asMap().entries.map((entry) {
                  final alertIndex = entry.key;
                  final alert = entry.value;
                  return _buildAlertTile(
                    alert,
                    stockNames[alert.symbol],
                    theme,
                    alertIndex,
                  );
                }),
              ],
            ),
          ).animate().fadeIn(
            delay: Duration(milliseconds: 50 * index),
            duration: AnimDurations.normal,
          );
        },
      ),
    );
  }

  Widget _buildAlertTile(
    PriceAlertEntry alert,
    String? stockName,
    ThemeData theme,
    int index,
  ) {
    final alertType = AlertType.fromValue(alert.alertType);
    final isActive = alert.isActive;
    final wasTriggered = alert.triggeredAt != null;

    return Dismissible(
      key: Key('alert_${alert.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return await _confirmDelete(alert);
      },
      onDismissed: (_) async {
        await ref.read(priceAlertProvider.notifier).deleteAlert(alert.id);
        final alertState = ref.read(priceAlertProvider);
        if (alertState.error != null) {
          ref.read(priceAlertProvider.notifier).clearError();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(alertState.error!),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('alert.deleted'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: ListTile(
        onTap: () => showCreatePriceAlertDialog(
          context: context,
          symbol: alert.symbol,
          // 編輯路徑原本沒傳名稱,於是對話框標題只有代碼——而「新增」
          // 路徑一直有傳。同一個資訊在兩條路徑不一致(2026-08-08 實機)
          stockName: stockName,
          existingAlert: alert,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getAlertColor(alertType, theme).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          child: Icon(
            alertType.icon,
            color: _getAlertColor(alertType, theme),
            size: 20,
          ),
        ),
        title: Text(
          getAlertDescription(alert, alertType),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            decoration: wasTriggered ? TextDecoration.lineThrough : null,
            color: wasTriggered ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert.note?.isNotEmpty ?? false)
              Text(
                alert.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    // inactive tint 用 outline 而非 onSurfaceVariant——OSV
                    // 當 tint 時 OSV 文字對合成底在深色主題僅 4.47:1
                    color: wasTriggered
                        ? AppTheme.warningColor.withValues(alpha: 0.2)
                        : isActive
                        ? AppTheme.successColor.withValues(alpha: 0.2)
                        : theme.colorScheme.outline.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                    border: Border.all(
                      color: wasTriggered
                          ? AppTheme.warningColor.withValues(alpha: 0.5)
                          : isActive
                          ? AppTheme.successColor.withValues(alpha: 0.5)
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    wasTriggered
                        ? 'alert.triggered'.tr()
                        : isActive
                        ? 'alert.active'.tr()
                        : 'alert.inactive'.tr(),
                    // 疊色底上的文字不得與 tint 同色（合成後 1.8~4.3:1）
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: wasTriggered
                          ? WarningColors.onTintFor(theme.brightness)
                          : isActive
                          ? (theme.brightness == Brightness.light
                                ? QualityColors.brandOnLight
                                : QualityColors.brandOnDecorative)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (wasTriggered && alert.triggeredAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _formatDateTime(alert.triggeredAt!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Switch(
          value: isActive,
          onChanged: wasTriggered
              ? null
              : (value) {
                  HapticFeedback.lightImpact();
                  ref
                      .read(priceAlertProvider.notifier)
                      .toggleAlert(alert.id, value);
                },
        ),
      ),
    );
  }

  Color _getAlertColor(AlertType type, ThemeData theme) {
    // 三個分支的色值都需要依主題解析：AppTheme.primaryColor 恆為深色版
    // 品牌亮色（淺色底不過圖形 3:1 門檻），downColor 恆為 #2ED573（對白底
    // 1.93:1）。改走主題 primary 與 PriceColors.downFor。
    final primaryColor = theme.colorScheme.primary;
    final downColor = PriceColors.downFor(theme.brightness);
    return switch (type) {
      AlertType.above ||
      AlertType.breakResistance ||
      AlertType.week52High ||
      AlertType.kdGoldenCross ||
      AlertType.crossAboveMa => AppTheme.upColor,
      AlertType.below ||
      AlertType.breakSupport ||
      AlertType.week52Low ||
      AlertType.kdDeathCross ||
      AlertType.crossBelowMa => downColor,
      AlertType.changePct ||
      AlertType.volumeSpike ||
      AlertType.volumeAbove ||
      AlertType.rsiOverbought ||
      AlertType.rsiOversold => primaryColor,
      AlertType.revenueYoySurge ||
      AlertType.highDividendYield ||
      AlertType.peUndervalued ||
      AlertType.insiderBuying => AppTheme.upColor,
      // Killer Features：警示顏色（紅色系）
      AlertType.tradingWarning ||
      AlertType.tradingDisposal ||
      AlertType.insiderSelling ||
      AlertType.highPledgeRatio => downColor,
    };
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmDelete(PriceAlertEntry alert) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.delete'.tr()),
        content: Text('alert.deleteConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 顯示新增價格警示的對話框
  Future<void> _showAddAlertDialog(BuildContext context) async {
    final db = ref.read(databaseProvider);

    final symbol = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _StockSymbolInputDialog(db: db),
    );

    if (symbol == null || !mounted) return;

    // 取得對話框用的股票資訊
    final results = await Future.wait([
      db.getStock(symbol),
      db.getLatestPrice(symbol),
    ]);

    if (!context.mounted) return;

    final stock = results[0] as StockMasterEntry?;
    final latestPrice = results[1] as DailyPriceEntry?;

    final created = await showCreatePriceAlertDialog(
      context: context,
      symbol: symbol,
      stockName: stock?.name,
      currentPrice: latestPrice?.close,
    );

    if (created == true) {
      ref.read(priceAlertProvider.notifier).loadAlerts();
    }
  }
}

/// 股票代號輸入對話框（獨立 StatefulWidget）
/// 確保 TextEditingController 透過 State 生命週期正確管理
class _StockSymbolInputDialog extends StatefulWidget {
  const _StockSymbolInputDialog({required this.db});

  final AppDatabase db;

  @override
  State<_StockSymbolInputDialog> createState() =>
      _StockSymbolInputDialogState();
}

class _StockSymbolInputDialogState extends State<_StockSymbolInputDialog> {
  final _controller = TextEditingController();
  bool _isSearching = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final input = _controller.text.trim().toUpperCase();
    if (input.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorText = null;
    });

    try {
      final stock = await widget.db.getStock(input);
      if (!mounted) return;

      if (stock != null) {
        Navigator.pop(context, input);
      } else {
        setState(() {
          _isSearching = false;
          _errorText = 'alert.stockNotFound'.tr();
        });
      }
    } catch (e) {
      AppLogger.warning('AlertsScreen', '搜尋股票失敗', e);
      if (mounted) {
        setState(() {
          _isSearching = false;
          _errorText = ErrorDisplay.message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('alert.selectStock'.tr()),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: 'alert.stockSymbol'.tr(),
          hintText: 'alert.stockSymbolHint'.tr(),
          errorText: _errorText,
          border: const OutlineInputBorder(),
        ),
        autofocus: true,
        enabled: !_isSearching,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _search(),
      ),
      actions: [
        TextButton(
          onPressed: _isSearching ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _isSearching ? null : _search,
          child: _isSearching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('common.next'.tr()),
        ),
      ],
    );
  }
}

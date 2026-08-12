import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';

/// 顯示「移到分組」picker（股票長按 → 移到分組）
///
/// 列出現有分組（標示目前所屬）+「移出分組」（設 null）+「➕ 新增分組」
/// （建立並當場指定）。所有操作走 [WatchlistNotifier]。
Future<void> showMoveToGroupSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String symbol,
  required int? currentGroupId,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: Breakpoints.sheetMaxWidth),
    builder: (sheetContext) => _MoveToGroupSheet(
      ref: ref,
      symbol: symbol,
      currentGroupId: currentGroupId,
    ),
  );
}

/// 顯示「管理分組」sheet（⋮ 更多選單 → 管理分組）
///
/// 分組清單 + inline 改名 + 刪除（確認，成員變未分組）+「➕ 新增分組」。
Future<void> showManageGroupsSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: Breakpoints.sheetMaxWidth),
    builder: (sheetContext) => _ManageGroupsSheet(ref: ref),
  );
}

/// sheet 外層容器（拖曳把手 + surface 圓角 + bottom safe area）
class _SheetContainer extends StatelessWidget {
  const _SheetContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Flexible(child: child),
          SizedBox(
            height:
                MediaQuery.of(context).padding.bottom + DesignTokens.spacing8,
          ),
        ],
      ),
    );
  }
}

// ==================================================
// 移到分組 picker
// ==================================================

class _MoveToGroupSheet extends ConsumerWidget {
  const _MoveToGroupSheet({
    required this.ref,
    required this.symbol,
    required this.currentGroupId,
  });

  final WidgetRef ref;
  final String symbol;
  final int? currentGroupId;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final theme = Theme.of(context);
    // 監聽 provider 讓建立新分組後清單即時更新
    final groups = widgetRef.watch(watchlistProvider.select((s) => s.groups));
    final notifier = widgetRef.read(watchlistProvider.notifier);

    return _SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing24,
              DesignTokens.spacing8,
              DesignTokens.spacing24,
              DesignTokens.spacing8,
            ),
            child: Text(
              'watchlist.moveToGroup'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // 移出分組（設 null）
                ListTile(
                  leading: const Icon(Icons.layers_clear_outlined),
                  title: Text('watchlist.removeFromGroup'.tr()),
                  trailing: currentGroupId == null
                      ? const Icon(Icons.check, size: 20)
                      : null,
                  onTap: () async {
                    await notifier.assignGroup(symbol, null);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                const Divider(height: 1),
                // 現有分組
                for (final g in groups)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(g.name),
                    trailing: currentGroupId == g.id
                        ? const Icon(Icons.check, size: 20)
                        : null,
                    onTap: () async {
                      await notifier.assignGroup(symbol, g.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                // 新增分組並當場指定
                ListTile(
                  leading: Icon(Icons.add, color: theme.colorScheme.primary),
                  title: Text(
                    'watchlist.newGroup'.tr(),
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  onTap: () async {
                    final name = await _promptGroupName(
                      context,
                      title: 'watchlist.newGroup'.tr(),
                    );
                    if (name == null || name.trim().isEmpty) return;
                    final id = await notifier.createGroup(name);
                    if (id != null) {
                      await notifier.assignGroup(symbol, id);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================
// 管理分組 sheet
// ==================================================

class _ManageGroupsSheet extends ConsumerWidget {
  const _ManageGroupsSheet({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final theme = Theme.of(context);
    final groups = widgetRef.watch(watchlistProvider.select((s) => s.groups));
    final notifier = widgetRef.read(watchlistProvider.notifier);

    return _SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing24,
              DesignTokens.spacing8,
              DesignTokens.spacing24,
              DesignTokens.spacing8,
            ),
            child: Text(
              'watchlist.manageGroups'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacing24,
                      vertical: DesignTokens.spacing16,
                    ),
                    child: Text(
                      'watchlist.noGroups'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final g in groups)
                  ListTile(
                    leading: Icon(
                      g.isDefault
                          ? Icons.folder_special
                          : Icons.folder_outlined,
                    ),
                    title: Text(g.name),
                    subtitle: g.isDefault
                        ? Text('watchlist.defaultGroupHint'.tr())
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 設為/取消預設分組（新加入的自選自動落入預設分組）
                        IconButton(
                          icon: Icon(
                            g.isDefault ? Icons.star : Icons.star_outline,
                            size: 20,
                            color: g.isDefault
                                ? theme.colorScheme.primary
                                : null,
                          ),
                          tooltip: g.isDefault
                              ? 'watchlist.unsetDefaultGroup'.tr()
                              : 'watchlist.setDefaultGroup'.tr(),
                          onPressed: () async {
                            await notifier.setDefaultGroup(
                              g.isDefault ? null : g.id,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'watchlist.renameGroup'.tr(),
                          onPressed: () async {
                            final name = await _promptGroupName(
                              context,
                              title: 'watchlist.renameGroup'.tr(),
                              initial: g.name,
                            );
                            if (name != null && name.trim().isNotEmpty) {
                              await notifier.renameGroup(g.id, name);
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: theme.colorScheme.error,
                          ),
                          tooltip: 'watchlist.deleteGroup'.tr(),
                          onPressed: () async {
                            final confirmed = await _confirmDelete(
                              context,
                              g.name,
                            );
                            if (confirmed) {
                              await notifier.deleteGroup(g.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.add, color: theme.colorScheme.primary),
                  title: Text(
                    'watchlist.newGroup'.tr(),
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  onTap: () async {
                    final name = await _promptGroupName(
                      context,
                      title: 'watchlist.newGroup'.tr(),
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await notifier.createGroup(name);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================
// 共用 dialog helper
// ==================================================

/// 彈出分組名稱輸入對話框（新增 / 改名共用）。回傳 null 代表取消。
Future<String?> _promptGroupName(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(hintText: 'watchlist.newGroupHint'.tr()),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text('common.confirm'.tr()),
          ),
        ],
      );
    },
  );
}

/// 刪除分組確認對話框。回傳 true 代表確認刪除。
Future<bool> _confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('watchlist.deleteGroup'.tr()),
        content: Text(
          'watchlist.deleteGroupConfirm'.tr(namedArgs: {'name': name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('watchlist.deleteGroup'.tr()),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daredevil/domain/models/scan_models.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 顯示分組篩選條件的底部選單
///
/// [currentFilter] 目前選中的篩選條件，用於標記已選狀態。
/// [onFilterSelected] 使用者選擇篩選條件後的回呼。
void showScanFilterBottomSheet({
  required BuildContext context,
  required ScanFilter currentFilter,
  required ValueChanged<ScanFilter> onFilterSelected,
}) {
  final theme = Theme.of(context);
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // 拖曳把手
              const DragHandle(),
              // 標題
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'scan.moreFilters'.tr(),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              // 篩選群組
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.of(context).padding.bottom + 40,
                  ),
                  children: ScanFilterGroup.values
                      .where((group) => group != ScanFilterGroup.all)
                      .map((group) {
                        final filters = group.filters;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 群組標題
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 16,
                                bottom: 8,
                              ),
                              child: Text(
                                group.labelKey.tr(),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // 篩選標籤
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: filters.map((filter) {
                                final isSelected = currentFilter == filter;
                                return FilterChip(
                                  label: Text(filter.labelKey.tr()),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    onFilterSelected(filter);
                                    Navigator.pop(context);
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      })
                      .toList(),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

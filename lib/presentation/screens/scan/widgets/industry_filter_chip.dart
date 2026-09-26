import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 產業篩選 Chip — 點擊展開下拉選單
class IndustryFilterChip extends StatelessWidget {
  const IndustryFilterChip({
    super.key,
    required this.industries,
    required this.selected,
    required this.onSelected,
  });

  final List<String> industries;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selected != null;

    return FilterChip(
      avatar: hasSelection
          ? null
          : const Icon(Icons.factory_outlined, size: 16),
      label: Text(hasSelection ? selected! : 'scan.industry'.tr()),
      selected: hasSelection,
      onSelected: (_) => _showIndustryPicker(context, theme),
      deleteIcon: hasSelection ? const Icon(Icons.close, size: 16) : null,
      onDeleted: hasSelection ? () => onSelected(null) : null,
    );
  }

  void _showIndustryPicker(BuildContext context, ThemeData theme) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 拖曳把手
                const DragHandle(),
                // 標題
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        'scan.selectIndustry'.tr(),
                        style: theme.textTheme.titleLarge,
                      ),
                      const Spacer(),
                      if (selected != null)
                        TextButton(
                          onPressed: () {
                            onSelected(null);
                            Navigator.pop(context);
                          },
                          child: Text('scan.clearIndustry'.tr()),
                        ),
                    ],
                  ),
                ),
                // 產業列表
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: industries.length,
                    itemBuilder: (context, index) {
                      final industry = industries[index];
                      final isSelected = industry == selected;
                      return ListTile(
                        title: Text(industry),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        selected: isSelected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelected(isSelected ? null : industry);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

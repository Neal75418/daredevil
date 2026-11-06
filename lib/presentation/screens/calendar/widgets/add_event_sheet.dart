import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/event_calendar_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/device_time.dart';

/// 新增/編輯事件 BottomSheet
class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({super.key, this.initialDate, this.existingEvent});

  final DateTime? initialDate;

  /// 傳入既有事件時進入編輯模式
  final StockEventEntry? existingEvent;

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _symbolController = TextEditingController();

  late DateTime _date;
  String? _selectedSymbol;

  // 搜尋結果
  List<StockMasterEntry> _searchResults = [];
  Timer? _debounce;

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _date = existing.eventDate;
      _selectedSymbol = existing.symbol;
      if (existing.symbol != null) {
        _symbolController.text = existing.symbol!;
      }
    } else {
      _date = widget.initialDate ?? DeviceTime.now();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _symbolController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: DesignTokens.spacing16,
        right: DesignTokens.spacing16,
        top: DesignTokens.spacing16,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + DesignTokens.spacing16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 標題列
            Row(
              children: [
                Text(
                  (_isEditing ? 'calendar.editEvent' : 'calendar.addEvent')
                      .tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacing16),

            // 事件標題
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'calendar.eventTitle'.tr(),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              maxLength: 100,
            ),
            const SizedBox(height: DesignTokens.spacing12),

            // 事件日期
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'calendar.eventDate'.tr(),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('yyyy-MM-dd').format(_date)),
              ),
            ),
            const SizedBox(height: DesignTokens.spacing12),

            // 關聯股票（選填）
            TextField(
              controller: _symbolController,
              decoration: InputDecoration(
                labelText: 'calendar.eventStock'.tr(),
                border: const OutlineInputBorder(),
                suffixIcon: _selectedSymbol != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _selectedSymbol = null;
                            _symbolController.clear();
                            _searchResults = [];
                          });
                        },
                      )
                    : null,
              ),
              onChanged: _onSymbolSearch,
            ),

            // 搜尋結果
            if (_searchResults.isNotEmpty && _selectedSymbol == null)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                margin: const EdgeInsets.only(top: DesignTokens.spacing4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final stock = _searchResults[index];
                    return ListTile(
                      dense: true,
                      title: Text('${stock.symbol} ${stock.name}'),
                      onTap: () {
                        setState(() {
                          _selectedSymbol = stock.symbol;
                          _symbolController.text =
                              '${stock.symbol} ${stock.name}';
                          _searchResults = [];
                        });
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: DesignTokens.spacing12),

            // 描述
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'calendar.eventDescription'.tr(),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: DesignTokens.spacing24),

            // 按鈕
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(
                      MaterialLocalizations.of(context).okButtonLabel,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _onSymbolSearch(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      try {
        final stockRepo = ref.read(stockRepositoryProvider);
        final results = await stockRepo.searchStocks(query);
        if (mounted && _symbolController.text == query) {
          setState(() => _searchResults = results.take(8).toList());
        }
      } catch (_) {
        if (mounted) setState(() => _searchResults = []);
      }
    });
  }

  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('calendar.titleRequired'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _isSubmitting = true;
    try {
      final description = _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null;

      if (_isEditing) {
        await ref
            .read(eventCalendarProvider.notifier)
            .updateEvent(
              id: widget.existingEvent!.id,
              symbol: _selectedSymbol,
              eventDate: _date,
              title: title,
              description: description,
            );
      } else {
        await ref
            .read(eventCalendarProvider.notifier)
            .addEvent(
              symbol: _selectedSymbol,
              eventDate: _date,
              title: title,
              description: description,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (_isEditing ? 'calendar.eventUpdated' : 'calendar.eventAdded')
                  .tr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.warning('AddEventSheet', _isEditing ? '更新事件失敗' : '新增事件失敗', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorDisplay.message(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      _isSubmitting = false;
    }
  }
}

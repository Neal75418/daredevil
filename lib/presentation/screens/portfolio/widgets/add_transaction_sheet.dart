import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/portfolio_repository.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/device_time.dart';

/// 新增交易 BottomSheet
class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({super.key, this.initialSymbol, this.existingTx});

  final String? initialSymbol;
  final PortfolioTransactionEntry? existingTx;

  bool get isEditing => existingTx != null;

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  TransactionType _txType = TransactionType.buy;
  DateTime _date = DeviceTime.now();
  final _symbolController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController();
  final _taxController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedSymbol;
  String? _selectedStockName;
  List<StockMasterEntry> _searchResults = [];
  bool _isSearching = false;
  bool _isSubmitting = false;
  Timer? _searchDebounce;
  bool _feeManuallyEdited = false;
  bool _taxManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingTx case final tx?) {
      // 編輯模式：pre-populate 既有值
      _selectedSymbol = tx.symbol;
      _symbolController.text = tx.symbol;
      _txType = TransactionType.fromValue(tx.txType);
      _date = tx.date;
      _quantityController.text = tx.quantity.toString();
      _priceController.text = tx.price.toString();
      if (tx.fee > 0) _feeController.text = tx.fee.toString();
      if (tx.tax > 0) _taxController.text = tx.tax.toString();
      if (tx.note != null) _noteController.text = tx.note!;
      _loadStockName(tx.symbol);
    } else if (widget.initialSymbol != null) {
      _selectedSymbol = widget.initialSymbol;
      _symbolController.text = widget.initialSymbol!;
      _loadStockName(widget.initialSymbol!);
    }
  }

  Future<void> _loadStockName(String symbol) async {
    final stockRepo = ref.read(stockRepositoryProvider);
    final stock = await stockRepo.getStock(symbol);
    if (mounted && stock != null) {
      setState(() => _selectedStockName = stock.name);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _symbolController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    _taxController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacing24,
          DesignTokens.spacing16,
          DesignTokens.spacing24,
          DesignTokens.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(
              children: [
                Text(
                  'portfolio.addTransaction'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacing16),

            // 股票搜尋
            if (_selectedSymbol == null) ...[
              TextField(
                controller: _symbolController,
                decoration: InputDecoration(
                  labelText: 'portfolio.selectStock'.tr(),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: _onSearchChanged,
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(DesignTokens.spacing8),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (_searchResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
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
                            _selectedStockName = stock.name;
                            _symbolController.text = stock.symbol;
                            _searchResults = [];
                          });
                        },
                      );
                    },
                  ),
                ),
            ] else ...[
              // 已選股票
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing12,
                  vertical: DesignTokens.spacing8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Row(
                  children: [
                    Text(
                      '$_selectedSymbol ${_selectedStockName ?? ""}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _selectedSymbol = null;
                          _selectedStockName = null;
                          _symbolController.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: DesignTokens.spacing16),

            // 交易類型
            Text('portfolio.txType'.tr(), style: theme.textTheme.labelMedium),
            const SizedBox(height: DesignTokens.spacing8),
            SegmentedButton<TransactionType>(
              segments: [
                ButtonSegment(
                  value: TransactionType.buy,
                  label: Text('portfolio.txBuy'.tr()),
                ),
                ButtonSegment(
                  value: TransactionType.sell,
                  label: Text('portfolio.txSell'.tr()),
                ),
                ButtonSegment(
                  value: TransactionType.dividendCash,
                  label: Text('portfolio.txDividendCash'.tr()),
                ),
                ButtonSegment(
                  value: TransactionType.dividendStock,
                  label: Text('portfolio.txDividendStock'.tr()),
                ),
              ],
              selected: {_txType},
              onSelectionChanged: (set) => setState(() => _txType = set.first),
            ),
            const SizedBox(height: DesignTokens.spacing16),

            // 日期
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'portfolio.txDate'.tr(),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('yyyy-MM-dd').format(_date)),
              ),
            ),
            const SizedBox(height: DesignTokens.spacing12),

            // 數量 + 價格
            if (_txType == TransactionType.dividendCash ||
                _txType == TransactionType.dividendStock) ...[
              TextField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: _txType == TransactionType.dividendCash
                      ? 'portfolio.dividendIncome'.tr()
                      : 'portfolio.txQuantity'.tr(),
                  border: const OutlineInputBorder(),
                  suffixText: _txType == TransactionType.dividendCash
                      ? 'TWD'
                      : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      decoration: InputDecoration(
                        labelText: 'portfolio.txQuantity'.tr(),
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
                      onChanged: (_) => _autoCalcFees(),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing12),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'portfolio.txPrice'.tr(),
                        border: const OutlineInputBorder(),
                        suffixText: 'TWD',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (_) => _autoCalcFees(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacing12),

              // 手續費 + 交易稅
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feeController,
                      decoration: InputDecoration(
                        labelText: 'portfolio.txFee'.tr(),
                        border: const OutlineInputBorder(),
                        helperText: 'portfolio.feeAutoCalc'.tr(),
                        helperMaxLines: 2,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (_) => _feeManuallyEdited = true,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing12),
                  Expanded(
                    child: TextField(
                      controller: _taxController,
                      decoration: InputDecoration(
                        labelText: 'portfolio.txTax'.tr(),
                        border: const OutlineInputBorder(),
                        helperText: _txType == TransactionType.sell
                            ? 'portfolio.taxAutoCalc'.tr()
                            : null,
                        helperMaxLines: 2,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (_) => _taxManuallyEdited = true,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: DesignTokens.spacing12),

            // 備註
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'portfolio.txNote'.tr(),
                border: const OutlineInputBorder(),
              ),
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
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(MaterialLocalizations.of(context).okButtonLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();

    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final stockRepo = ref.read(stockRepositoryProvider);
        final results = await stockRepo.searchStocks(query);
        if (mounted && _symbolController.text == query) {
          setState(() {
            _searchResults = results.take(5).toList();
            _isSearching = false;
          });
        }
      } catch (e) {
        AppLogger.warning('AddTransactionSheet', '搜尋股票失敗', e);
        if (mounted && _symbolController.text == query) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ErrorDisplay.message(e)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    });
  }

  void _autoCalcFees() {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;

    if (qty > 0 && price > 0) {
      if (!_feeManuallyEdited) {
        _feeController.text = PortfolioRepository.calculateFee(
          qty,
          price,
        ).toStringAsFixed(0);
      }
      if (!_taxManuallyEdited && _txType == TransactionType.sell) {
        _taxController.text = PortfolioRepository.calculateTax(
          qty,
          price,
        ).toStringAsFixed(0);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DeviceTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_selectedSymbol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('portfolio.selectStock'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate fields before locking the button
    if (_txType == TransactionType.dividendCash ||
        _txType == TransactionType.dividendStock) {
      final amount = double.tryParse(_quantityController.text);
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('portfolio.invalidInput'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } else {
      final qty = double.tryParse(_quantityController.text);
      final price = double.tryParse(_priceController.text);
      if (qty == null || qty <= 0 || price == null || price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('portfolio.invalidInput'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    final notifier = ref.read(portfolioProvider.notifier);
    final symbol = _selectedSymbol!;
    final note = _noteController.text.trim().isNotEmpty
        ? _noteController.text.trim()
        : null;

    try {
      // 編輯模式：更新既有交易
      if (widget.isEditing) {
        final qty = double.tryParse(_quantityController.text)!;
        final price = double.tryParse(_priceController.text) ?? 0;
        final fee = double.tryParse(_feeController.text);
        final tax = double.tryParse(_taxController.text);

        await notifier.updateTransaction(
          txId: widget.existingTx!.id,
          symbol: symbol,
          date: _date,
          quantity: qty,
          price: price,
          fee: fee,
          tax: tax,
          note: note,
        );
      } else if (_txType == TransactionType.dividendCash ||
          _txType == TransactionType.dividendStock) {
        final amount = double.tryParse(_quantityController.text)!;
        await notifier.addDividend(
          symbol: symbol,
          date: _date,
          amount: amount,
          isCash: _txType == TransactionType.dividendCash,
          note: note,
        );
      } else {
        final qty = double.tryParse(_quantityController.text)!;
        final price = double.tryParse(_priceController.text)!;
        final fee = double.tryParse(_feeController.text);
        final tax = double.tryParse(_taxController.text);

        if (_txType == TransactionType.buy) {
          await notifier.addBuy(
            symbol: symbol,
            date: _date,
            quantity: qty,
            price: price,
            fee: fee,
            note: note,
          );
        } else if (_txType == TransactionType.sell) {
          await notifier.addSell(
            symbol: symbol,
            date: _date,
            quantity: qty,
            price: price,
            fee: fee,
            tax: tax,
            note: note,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? 'portfolio.transactionUpdated'.tr()
                  : 'portfolio.transactionAdded'.tr(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.warning('AddTransactionSheet', '新增交易失敗: $symbol', e);
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorDisplay.message(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

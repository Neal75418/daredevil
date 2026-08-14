import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 投資組合 Repository
///
/// 管理持倉與交易紀錄，使用 FIFO 方法計算損益。
class PortfolioRepository {
  PortfolioRepository({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  /// 台灣券商手續費率（0.1425%）
  static const double brokerageFeeRate = AnalysisParams.brokerageFeeRate;

  /// 台灣證交稅率（0.3%）
  static const double transactionTaxRate = AnalysisParams.transactionTaxRate;

  // ==================================================
  // 交易操作
  // ==================================================

  /// 計算建議手續費
  static double calculateFee(double quantity, double price) {
    final fee = quantity * price * brokerageFeeRate;
    return fee < AnalysisParams.minBrokerageFee
        ? AnalysisParams.minBrokerageFee
        : fee;
  }

  /// 計算建議交易稅（僅賣出）
  static double calculateTax(double quantity, double price) {
    return quantity * price * transactionTaxRate;
  }

  /// 新增買進交易
  Future<void> addBuyTransaction({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    String? note,
  }) async {
    if (quantity <= 0) {
      throw const ValidationException('portfolio.quantityMustBePositive');
    }
    if (price <= 0) {
      throw const ValidationException('portfolio.priceMustBePositive');
    }

    final actualFee = fee ?? calculateFee(quantity, price);

    await _wrapTransaction('addBuy', symbol, () async {
      await _db.insertTransaction(
        PortfolioTransactionCompanion.insert(
          symbol: symbol,
          txType: 'BUY',
          date: date,
          quantity: quantity,
          price: price,
          fee: Value(actualFee),
          note: Value(note),
        ),
      );
      await _recalculatePosition(symbol);
    });
  }

  /// 新增賣出交易
  ///
  /// 若賣出數量超過持有數量，會拋出 [ValidationException]
  /// (`portfolio.sellExceedsHolding`)。
  Future<void> addSellTransaction({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {
    if (quantity <= 0) {
      throw const ValidationException('portfolio.quantityMustBePositive');
    }
    if (price <= 0) {
      throw const ValidationException('portfolio.priceMustBePositive');
    }

    final actualFee = fee ?? calculateFee(quantity, price);
    final actualTax = tax ?? calculateTax(quantity, price);

    await _wrapTransaction('addSell', symbol, () async {
      // 驗證賣出數量不超過持有量（在 transaction 內確保原子性）
      final position = await _db.getPortfolioPosition(symbol);
      final currentQty = position?.quantity ?? 0;
      if (quantity > currentQty) {
        throw const ValidationException('portfolio.sellExceedsHolding');
      }

      await _db.insertTransaction(
        PortfolioTransactionCompanion.insert(
          symbol: symbol,
          txType: 'SELL',
          date: date,
          quantity: quantity,
          price: price,
          fee: Value(actualFee),
          tax: Value(actualTax),
          note: Value(note),
        ),
      );
      await _recalculatePosition(symbol);
    });
  }

  /// 新增股利交易
  Future<void> addDividendTransaction({
    required String symbol,
    required DateTime date,
    required double amount,
    required bool isCash,
    String? note,
  }) async {
    if (amount <= 0) {
      throw const ValidationException('portfolio.amountMustBePositive');
    }

    await _wrapTransaction('addDividend', symbol, () async {
      await _db.insertTransaction(
        PortfolioTransactionCompanion.insert(
          symbol: symbol,
          txType: isCash ? 'DIVIDEND_CASH' : 'DIVIDEND_STOCK',
          date: date,
          quantity: amount, // 股利金額或股數
          price: 0,
          note: Value(note),
        ),
      );
      await _recalculatePosition(symbol);
    });
  }

  /// 刪除交易紀錄並重新計算
  Future<void> deleteTransaction(int txId, String symbol) async {
    await _wrapTransaction('delete', symbol, () async {
      await _db.deleteTransaction(txId);
      await _recalculatePosition(symbol);
    });
  }

  /// 更新交易紀錄並重新計算 FIFO
  Future<void> updateTransaction({
    required int txId,
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {
    await _wrapTransaction('update', symbol, () async {
      await (_db.update(
        _db.portfolioTransaction,
      )..where((t) => t.id.equals(txId))).write(
        PortfolioTransactionCompanion(
          date: Value(date),
          quantity: Value(quantity),
          price: Value(price),
          fee: Value(fee ?? 0),
          tax: Value(tax ?? 0),
          note: Value(note),
        ),
      );
      await _recalculatePosition(symbol);
    });
  }

  /// 以 [DatabaseException] 包裝 Drift transaction 失敗。
  ///
  /// Drift / SQLite 原生例外（如 `SqliteException`）若直接 leak 到 provider，
  /// ErrorDisplay 會落到 `error.unknown.tr()`，使用者看不到可辨識訊息。
  /// 本 helper 統一將寫入路徑失敗包成 `DatabaseException`，並保留
  /// [ValidationException] 的 rethrow 以維持原契約（賣出量超持有、quantity ≤ 0）。
  Future<void> _wrapTransaction(
    String op,
    String symbol,
    Future<void> Function() body,
  ) async {
    try {
      await _db.transaction(body);
    } on ValidationException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Portfolio transaction failed ($op:$symbol)', e);
    }
  }

  // ==================================================
  // FIFO 損益計算
  // ==================================================

  /// 從所有交易紀錄重新計算某 symbol 的持倉
  ///
  /// 呼叫端已在 transaction 中，此處不再包裝避免巢狀 transaction
  Future<void> _recalculatePosition(String symbol) async {
    final transactions = await _db.getTransactionsForSymbol(symbol);

    if (transactions.isEmpty) {
      // 如果沒有交易紀錄，刪除 position
      final existing = await _db.getPortfolioPosition(symbol);
      if (existing != null) {
        await _db.deletePortfolioPosition(existing.id);
      }
      return;
    }

    // FIFO lot queue: 買入手續費分攤至每股成本，賣出費用直接扣除
    final List<_FifoLot> lots = [];
    double realizedPnl = 0;
    double totalDividend = 0;

    for (final tx in transactions) {
      switch (tx.txType) {
        case 'BUY':
          // 將買入手續費分攤至每股成本
          final feePerShare = tx.quantity > 0 ? tx.fee / tx.quantity : 0.0;
          lots.add(
            _FifoLot(
              quantity: tx.quantity,
              costPerShare: tx.price + feePerShare,
            ),
          );
        case 'SELL':
          double remainingToSell = tx.quantity;
          final sellPrice = tx.price;

          while (remainingToSell > 0 && lots.isNotEmpty) {
            final lot = lots.first;

            if (lot.quantity <= remainingToSell) {
              // 整批售出
              realizedPnl += (sellPrice - lot.costPerShare) * lot.quantity;
              remainingToSell -= lot.quantity;
              lots.removeAt(0);
            } else {
              // 部分售出
              realizedPnl += (sellPrice - lot.costPerShare) * remainingToSell;
              lot.quantity -= remainingToSell;
              remainingToSell = 0;
            }
          }
          // FIFO 一致性守衛：lots 已耗盡但仍有未配對 SELL 數量代表持倉與交易
          // 紀錄不一致。addSellTransaction 已在寫入前驗證，但 updateTransaction
          // 路徑（編輯既有 BUY 把數量改小）不會走那條檢查，必須在這裡 throw
          // 讓 transaction rollback，否則 realizedPnl 會少算掉未配對部份的成本。
          if (remainingToSell > 1e-9) {
            throw const ValidationException('portfolio.sellExceedsHolding');
          }
          // 賣出手續費與交易稅直接從已實現損益扣除
          realizedPnl -= tx.fee + tx.tax;
        case 'DIVIDEND_CASH':
          totalDividend += tx.quantity;
        case 'DIVIDEND_STOCK':
          // 股票股利：增加持股，成本為 0
          if (tx.quantity > 0) {
            lots.add(_FifoLot(quantity: tx.quantity, costPerShare: 0));
          }
      }
    }

    // 計算剩餘持倉的加權平均成本
    double totalQuantity = 0;
    double totalCost = 0;
    for (final lot in lots) {
      totalQuantity += lot.quantity;
      totalCost += lot.quantity * lot.costPerShare;
    }
    final avgCost = totalQuantity > 0 ? totalCost / totalQuantity : 0.0;

    // 更新或建立 position
    final existing = await _db.getPortfolioPosition(symbol);
    if (existing != null) {
      await _db.updatePortfolioPosition(
        id: existing.id,
        quantity: totalQuantity,
        avgCost: avgCost,
        realizedPnl: realizedPnl,
        totalDividendReceived: totalDividend,
      );
    } else {
      await _db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: symbol,
          quantity: Value(totalQuantity),
          avgCost: Value(avgCost),
          realizedPnl: Value(realizedPnl),
          totalDividendReceived: Value(totalDividend),
        ),
      );
    }
  }
}

/// FIFO lot（先進先出批次）
class _FifoLot {
  _FifoLot({required this.quantity, required this.costPerShare});

  double quantity;
  final double costPerShare;
}

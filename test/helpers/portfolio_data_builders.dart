import 'package:daredevil/data/database/app_database.dart';

/// 投資組合相關測試資料建構器

// ==========================================
// PortfolioPositionEntry
// ==========================================

PortfolioPositionEntry createTestPortfolioPosition({
  int id = 1,
  String symbol = 'TEST',
  double quantity = 1000,
  double avgCost = 100.0,
  double realizedPnl = 0,
  double totalDividendReceived = 0,
  String? note,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  return PortfolioPositionEntry(
    id: id,
    symbol: symbol,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    note: note,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

// ==========================================
// PortfolioTransactionEntry
// ==========================================

PortfolioTransactionEntry createTestPortfolioTransaction({
  int id = 1,
  String symbol = 'TEST',
  String txType = 'BUY',
  DateTime? date,
  double quantity = 1000,
  double price = 100.0,
  double fee = 143,
  double tax = 0,
  String? note,
  DateTime? createdAt,
}) {
  final now = DateTime.now();
  return PortfolioTransactionEntry(
    id: id,
    symbol: symbol,
    txType: txType,
    date: date ?? now,
    quantity: quantity,
    price: price,
    fee: fee,
    tax: tax,
    note: note,
    createdAt: createdAt ?? now,
  );
}

// ==========================================
// StockMasterEntry
// ==========================================

StockMasterEntry createTestStockMaster({
  String symbol = 'TEST',
  String name = '測試股',
  String market = 'TWSE',
  String? industry = '半導體',
  bool isActive = true,
  DateTime? updatedAt,
}) {
  return StockMasterEntry(
    symbol: symbol,
    name: name,
    market: market,
    industry: industry,
    isActive: isActive,
    updatedAt: updatedAt ?? DateTime.now(),
  );
}

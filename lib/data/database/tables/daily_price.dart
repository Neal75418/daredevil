import 'package:drift/drift.dart';

import 'package:daredevil/data/database/tables/stock_master.dart';

/// 每日 OHLCV 價格資料 Table
@DataClassName('DailyPriceEntry')
// (date, symbol) 複合(2026-08-29 效能稽核 #5):date-range GROUP BY 類
// 查詢(getPriceCountsByDayAndMarket、getSymbolsWithSufficientData、
// countPricesByDateAndMarket)免回表抓 symbol,DB 副本實測 counts 查詢
// 1,374→275ms、EQP 轉 COVERING;體積 +27.6MB、一次性建索引 0.3s。
// 舊單欄 (date) 版為本索引左前綴 → 進 legacyRedundantIndexes 清除。
@TableIndex(name: 'idx_daily_price_date_symbol', columns: {#date, #symbol})
class DailyPrice extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 交易日期（本地午夜、ISO-8601 text 儲存）
  DateTimeColumn get date => dateTime()();

  /// 開盤價
  RealColumn get open => real().nullable()();

  /// 最高價
  RealColumn get high => real().nullable()();

  /// 最低價
  RealColumn get low => real().nullable()();

  /// 收盤價
  RealColumn get close => real().nullable()();

  /// 成交量（股）
  RealColumn get volume => real().nullable()();

  /// 漲跌價差（來自 TWSE/TPEX API，用於計算漲跌幅）
  RealColumn get priceChange => real().named('price_change').nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

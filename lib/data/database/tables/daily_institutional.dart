import 'package:drift/drift.dart';

import 'package:daredevil/data/database/tables/stock_master.dart';

/// 三大法人每日買賣超 Table
@DataClassName('DailyInstitutionalEntry')
// 2026-07-29 索引衛生:移除 idx_daily_institutional_symbol_date 宣告——
// 與複合 PK (symbol,date) 的 autoindex 完全重複。既有 DB 由
// _ensureIndexHygiene 清除。
@TableIndex(name: 'idx_daily_institutional_date', columns: {#date})
class DailyInstitutional extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 交易日期
  DateTimeColumn get date => dateTime()();

  /// 外資買賣超（股——TWSE/TPEx API 回傳股數直接儲存）
  RealColumn get foreignNet => real().nullable()();

  /// 投信買賣超（股）
  RealColumn get investmentTrustNet => real().nullable()();

  /// 自營商買賣超（股）— 自行買賣 + 避險合計（對外口徑，媒體/TWSE 報的就是此值）
  RealColumn get dealerNet => real().nullable()();

  /// 自營商「自行買賣」買賣超（股，不含避險）
  ///
  /// FinMind 的 Dealer_self。自營避險部位結構性偏買，會使合計 [dealerNet]
  /// 連續買超天數失真（恆正）；此欄供「自行買賣」streak 等需要真實自營主動
  /// 方向的場景使用。
  ///
  /// ⚠️ 此欄以 idempotent ALTER 路徑（見 AppDatabase beforeOpen 的
  /// `_ensureDealerSelfNetColumn`）加入既有 DB，刻意「不」bump schema
  /// fingerprint，避免 wipe 掉使用者累積的 derived 資料。
  RealColumn get dealerSelfNet => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

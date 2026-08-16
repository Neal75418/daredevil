import 'package:drift/drift.dart';

import 'package:daredevil/data/database/tables/stock_master.dart';

/// 使用者自訂分組 Table（資料夾模式：一檔股票只歸屬一個分組）
///
/// 與內建的 `none/status/trend` 自動分組正交：此表是使用者手動建立、可命名的
/// 分組。[Watchlist.groupId] 以 FK 指回此表，刪除分組時成員的 groupId 會被
/// `KeyAction.setNull` 清空（成員回到「未分組」、不會連帶刪除股票）。
@DataClassName('WatchlistGroupEntry')
class WatchlistGroups extends Table {
  /// 自動遞增 ID
  IntColumn get id => integer().autoIncrement()();

  /// 分組名稱（使用者自訂）
  TextColumn get name => text().withLength(min: 1, max: 50)();

  /// 排序順序（數字越小越前面，預設 0）
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 預設分組旗標：新加入的自選自動落入此分組（全表最多一列為 true，
  /// 由 [UserDaoMixin.setDefaultWatchlistGroup] 的交易維持）。
  ///
  /// 掛在分組列上而非 app_settings 存 id：旗標跟著列走，改名不斷、
  /// 刪組自動失效，不需要懸空 id 的存在性檢查。
  /// 既有 DB 由 `_ensureWatchlistGroupsSchema` 的 ALTER 路徑補欄
  /// （whitelist 表不吃 fingerprint reset）。
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  /// 建立時間
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 使用者自選股清單 Table
@DataClassName('WatchlistEntry')
class Watchlist extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 加入自選股的時間
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 所屬自訂分組 ID（null 代表未分組）
  ///
  /// 刪除分組時 `KeyAction.setNull` 會把成員的 groupId 清空，不刪股票。
  IntColumn get groupId => integer().nullable().references(
    WatchlistGroups,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column> get primaryKey => {symbol};
}

/// 資料更新執行紀錄 Table
@DataClassName('UpdateRunEntry')
class UpdateRun extends Table {
  /// 自動遞增 ID
  IntColumn get id => integer().autoIncrement()();

  /// 更新的目標日期
  DateTimeColumn get runDate => dateTime()();

  /// 開始執行時間
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();

  /// 完成時間（執行中則為空）
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// 狀態：SUCCESS、FAILED、PARTIAL
  TextColumn get status => text()();

  /// 訊息（錯誤詳情等）
  TextColumn get message => text().nullable()();
}

/// 應用程式設定 Table（Key-Value 儲存）
@DataClassName('AppSettingEntry')
class AppSettings extends Table {
  /// 設定鍵
  TextColumn get key => text()();

  /// 設定值
  TextColumn get value => text()();

  /// 最後更新時間
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

/// 股價提醒 Table
///
/// 提醒類型：完整值域見 `AlertParams` 的 type 常數（價格/漲跌幅之外
/// 尚有營收、內部人等共 23 種）
@DataClassName('PriceAlertEntry')
class PriceAlert extends Table {
  /// 自動遞增 ID
  IntColumn get id => integer().autoIncrement()();

  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 提醒類型（值域見 AlertParams）
  TextColumn get alertType => text()();

  /// 目標值（價格或百分比）
  RealColumn get targetValue => real()();

  /// 是否啟用
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// 觸發時間（尚未觸發則為空）
  DateTimeColumn get triggeredAt => dateTime().nullable()();

  /// 備註說明
  TextColumn get note => text().nullable()();

  /// 自動維護者（`NULL` = 使用者手動設定，值域見 `AlertParams.managedBy*`）
  ///
  /// **NULL 是受保護的語意**：均線階梯([TrailingMaAlertService])每日重算並
  /// 改寫提醒價位，沒有這欄就分不出自動與手動，重算會把使用者特地設的
  /// 關鍵價位一起洗掉。自動流程只准動自己標記過的列。
  TextColumn get managedBy => text().nullable()();

  /// 建立時間
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 釘選論點 Table（出場層，評分改進 #3 Phase 2）
///
/// 把「推薦」升級為可追蹤的「論點」：釘選當日快照 + 每日失效檢查。
/// 語意（spec docs/plans/2026-07-11-exit-thesis-invalidation-design.md §4）：
/// - 一 symbol 同時只允許一筆 ACTIVE（service 層 enforcement）
/// - INVALIDATED 凍結不復活；重新看多請重新釘選（新記錄）
/// - 取消（誤觸）= 物理刪除；封存 = ARCHIVED 保留紀錄
@DataClassName('PinnedThesisEntry')
class PinnedThesis extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get symbol => text().references(StockMaster, #symbol)();

  /// 快照**資料日**（dataDate，非點擊時刻）
  DateTimeColumn get pinnedDate => dateTime()();

  /// 釘選資料日收盤——僅供顯示與 timeStop 基準，不代表可成交價
  RealColumn get referencePrice => real()();

  /// 釘選當下路由 mode（momentum / strength / pullback）
  TextColumn get mode => text()();

  /// 當日觸發規則碼快照（JSON array；v1 不顯示、留回溯用）
  TextColumn get triggeredRules => text()();

  RealColumn get scoreShort => real()();
  RealColumn get scoreLong => real()();

  /// ACTIVE / INVALIDATED / ARCHIVED
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();

  DateTimeColumn get invalidatedDate => dateTime().nullable()();

  /// ExitReason.name（現值域僅 timeStop——gate 砍掉 hardStop/trendBreak）
  TextColumn get invalidatedReason => text().nullable()();

  /// monitor 每次跑必更新（staleness 顯示用）
  DateTimeColumn get lastCheckedDate => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 僅於 status 實際變更時更新
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

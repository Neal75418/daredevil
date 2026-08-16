import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/dao/batch_query_mixin.dart';
import 'package:daredevil/data/database/tables/user_tables.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';
import 'package:daredevil/data/database/tables/daily_price.drift.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/domain/services/alert_evaluation_service.dart';

/// 自選股條目 + 其所屬分組名稱（未分組則 [groupName] 為 null）
///
/// [UserDaoMixin.getWatchlistWithGroups] 的回傳型別：把 watchlist entry 與
/// LEFT JOIN 取得的分組名稱綁在一起，供 provider 一次組出帶分組資訊的項目。
class WatchlistWithGroup {
  const WatchlistWithGroup({required this.entry, this.groupName});

  final WatchlistEntry entry;
  final String? groupName;
}

/// 使用者相關資料存取：自選股、設定、更新紀錄、股價提醒
mixin UserDaoMixin on $AppDatabase {
  // ==================================================
  // 自選股操作
  // ==================================================

  /// 取得所有自選股
  Future<List<WatchlistEntry>> getWatchlist() {
    return (select(
      watchlist,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  /// 加入自選股
  ///
  /// [groupId] 用 `Value` 三態：
  /// - `Value.absent()`（預設）→ 落入預設分組（無預設分組則未分組）
  /// - `Value(id)` → 指定分組（復原場景）；**分組已不存在時落回未分組**，
  ///   「移除 → 刪組 → 復原」的競態不炸 FK
  /// - `Value(null)` → 明確未分組（復原「本來就未分組」的股票——若走
  ///   absent 會被預設分組收編，這正是 2026-08-12 修的 bug）
  Future<void> addToWatchlist(
    String symbol, {
    Value<int?> groupId = const Value.absent(),
  }) {
    // transaction:讀分組與 insert 之間若分組被刪,INSERT OR IGNORE **不會**
    // 吞 FK violation(實測 SqliteException 787)——包進交易讓讀寫看同一份快照
    return transaction(() async {
      final int? resolved;
      if (groupId.present) {
        resolved = await _existingWatchlistGroupId(groupId.value);
      } else {
        resolved = (await getDefaultWatchlistGroup())?.id;
      }
      await into(watchlist).insert(
        WatchlistCompanion.insert(symbol: symbol, groupId: Value(resolved)),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// [id] 仍存在於 watchlist_groups 時回傳原值，否則 null（FK 防禦）
  Future<int?> _existingWatchlistGroupId(int? id) async {
    if (id == null) return null;
    final row = await (select(
      watchlistGroups,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.id;
  }

  /// 設定預設分組（[id] 為 null 代表清除預設）
  ///
  /// 交易內先全清再設，維持「全表最多一列 isDefault」的不變量——
  /// 同時兩個預設會讓「新加入落到哪」變成未定義行為。
  Future<void> setDefaultWatchlistGroup(int? id) {
    return transaction(() async {
      await (update(watchlistGroups)..where((t) => t.isDefault.equals(true)))
          .write(const WatchlistGroupsCompanion(isDefault: Value(false)));
      if (id != null) {
        await (update(watchlistGroups)..where((t) => t.id.equals(id))).write(
          const WatchlistGroupsCompanion(isDefault: Value(true)),
        );
      }
    });
  }

  /// 取得預設分組（未設定則 null）
  ///
  /// `limit(1)`：不變量由 [setDefaultWatchlistGroup] 維持，但此 DB 也被
  /// 外部工具直接寫過——多列時取一列，不炸 `getSingleOrNull`。
  Future<WatchlistGroupEntry?> getDefaultWatchlistGroup() {
    return (select(watchlistGroups)
          ..where((t) => t.isDefault.equals(true))
          // 多列時取 id 最小——外部工具寫壞不變量時 fallback 至少是穩定的
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 從自選股移除
  Future<void> removeFromWatchlist(String symbol) {
    return (delete(watchlist)..where((t) => t.symbol.equals(symbol))).go();
  }

  /// 檢查股票是否在自選股中
  Future<bool> isInWatchlist(String symbol) async {
    final result = await (select(
      watchlist,
    )..where((t) => t.symbol.equals(symbol))).getSingleOrNull();
    return result != null;
  }

  /// 取得單一自選股條目（含 createdAt 時間戳）
  Future<WatchlistEntry?> getWatchlistEntry(String symbol) {
    return (select(
      watchlist,
    )..where((t) => t.symbol.equals(symbol))).getSingleOrNull();
  }

  // ==================================================
  // 自選股自訂分組操作（資料夾模式：一檔一組）
  // ==================================================

  /// 取得所有自訂分組（依 sortOrder、再依建立時間排序）
  Future<List<WatchlistGroupEntry>> getWatchlistGroups() {
    return (select(watchlistGroups)..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
        .get();
  }

  /// 建立新分組，回傳新分組的 id
  ///
  /// 新分組的 sortOrder 取現有最大值 +1，確保附加在清單末端。
  Future<int> createWatchlistGroup(String name) async {
    final existing = await getWatchlistGroups();
    final nextSortOrder = existing.isEmpty
        ? 0
        : existing.map((g) => g.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    return into(watchlistGroups).insert(
      WatchlistGroupsCompanion.insert(
        name: name,
        sortOrder: Value(nextSortOrder),
      ),
    );
  }

  /// 重新命名分組
  Future<void> renameWatchlistGroup(int id, String name) {
    return (update(watchlistGroups)..where((t) => t.id.equals(id))).write(
      WatchlistGroupsCompanion(name: Value(name)),
    );
  }

  /// 刪除分組
  ///
  /// FK `onDelete: setNull` 會自動把成員的 groupId 清空（成員回到未分組、
  /// 不刪股票）。注意：SQLite 需 `PRAGMA foreign_keys = ON` 才會觸發 setNull，
  /// 此 pragma 已於 `beforeOpen` 設定。
  Future<void> deleteWatchlistGroup(int id) {
    return (delete(watchlistGroups)..where((t) => t.id.equals(id))).go();
  }

  /// 指定股票到分組（[groupId] 為 null 代表移出分組）
  Future<void> assignWatchlistGroup(String symbol, int? groupId) {
    return (update(watchlist)..where((t) => t.symbol.equals(symbol))).write(
      WatchlistCompanion(groupId: Value(groupId)),
    );
  }

  /// 取得所有自選股，並附帶各檔所屬分組名稱（未分組則 groupName 為 null）
  ///
  /// 以 LEFT JOIN watchlist_groups，一次查詢取回 entry + 分組名稱，避免在
  /// provider 端逐筆 lookup。回傳依 createdAt DESC（與 [getWatchlist] 一致）。
  Future<List<WatchlistWithGroup>> getWatchlistWithGroups() async {
    final query = select(watchlist).join([
      leftOuterJoin(
        watchlistGroups,
        watchlistGroups.id.equalsExp(watchlist.groupId),
      ),
    ])..orderBy([OrderingTerm.desc(watchlist.createdAt)]);

    final rows = await query.get();
    return rows.map((row) {
      final entry = row.readTable(watchlist);
      final group = row.readTableOrNull(watchlistGroups);
      return WatchlistWithGroup(entry: entry, groupName: group?.name);
    }).toList();
  }

  // ==================================================
  // 應用程式設定操作（Token 儲存用）
  // ==================================================

  /// 取得設定值
  Future<String?> getSetting(String key) async {
    final result = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return result?.value;
  }

  /// 設定設定值
  Future<void> setSetting(String key, String value) {
    return into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  /// 刪除設定
  Future<void> deleteSetting(String key) {
    return (delete(appSettings)..where((t) => t.key.equals(key))).go();
  }

  // ==================================================
  // 更新執行記錄操作
  // ==================================================

  /// 建立新的更新執行記錄
  Future<int> createUpdateRun(DateTime runDate, String status) {
    return into(
      updateRun,
    ).insert(UpdateRunCompanion.insert(runDate: runDate, status: status));
  }

  /// 更新執行狀態
  Future<void> finishUpdateRun(
    int id,
    String status, {
    String? message,
    DateTime? now,
  }) {
    return (update(updateRun)..where((t) => t.id.equals(id))).write(
      UpdateRunCompanion(
        finishedAt: Value(now ?? DateTime.now()),
        status: Value(status),
        message: Value(message),
      ),
    );
  }

  /// 收斂孤兒 RUNNING run(2026-07-30 審查)
  ///
  /// app 中途被殺(手機殺後台、崩潰)時,起手寫入的 RUNNING row 永遠不會
  /// 被 finish,歷史列表會顯示一筆永遠進行中的紀錄。DB beforeOpen 呼叫此
  /// 方法把「started_at 超過 [DataFreshness.orphanRunningCutoff]」的標成
  /// FAILED。**必須有 age cutoff**:macOS CLI(tool/daily_update.dart)與
  /// GUI 共用同一份 DB 各開獨立連線,無條件清會誤殺對方進行中的 run。
  /// 回傳收斂筆數。
  Future<int> failOrphanRunningRuns({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final cutoff = effectiveNow.subtract(DataFreshness.orphanRunningCutoff);
    return (update(updateRun)..where(
          (t) =>
              t.status.equals(UpdateStatus.running.code) &
              t.startedAt.isSmallerThanValue(cutoff),
        ))
        .write(
          UpdateRunCompanion(
            status: Value(UpdateStatus.failed.code),
            message: const Value('更新中斷(app 終止或崩潰)'),
            finishedAt: Value(effectiveNow),
          ),
        );
  }

  /// 更新執行記錄的資料日期
  ///
  /// 用於日期校正後更新 runDate，確保記錄的是實際資料日期
  Future<void> updateRunDate(int id, DateTime runDate) {
    return (update(updateRun)..where((t) => t.id.equals(id))).write(
      UpdateRunCompanion(runDate: Value(runDate)),
    );
  }

  /// 取得最新的更新執行記錄
  Future<UpdateRunEntry?> getLatestUpdateRun() {
    return (select(updateRun)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 最後一筆**成功**的 update_run
  ///
  /// 冷啟動 gate 判斷「資料夠不夠新」用。[getLatestUpdateRun] 不分 status，
  /// 拿它當新鮮度基準會讓一次失敗的嘗試看起來像「剛更新過」。
  Future<UpdateRunEntry?> getLatestSuccessfulUpdateRun() {
    return (select(updateRun)
          ..where((t) => t.status.equals(UpdateStatus.success.code))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 取得最近 N 筆更新執行記錄（包含 SUCCESS / PARTIAL / FAILED）
  ///
  /// UI 顯示「更新紀錄」歷史列表用，user tap Today 上的 timestamp 帶出。
  /// 依 id DESC 排（最新的在前）。
  Future<List<UpdateRunEntry>> getRecentUpdateRuns({int limit = 30}) {
    return (select(updateRun)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .get();
  }

  // ==================================================
  // 股價提醒操作
  // ==================================================

  /// 取得所有啟用中的股價提醒
  Future<List<PriceAlertEntry>> getActiveAlerts() {
    return (select(priceAlert)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// 取得所有股價提醒（包含啟用與停用）
  Future<List<PriceAlertEntry>> getAllAlerts() {
    return (select(
      priceAlert,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  /// 依 ID 取得單一提醒
  Future<PriceAlertEntry?> getAlertById(int id) {
    return (select(
      priceAlert,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 取得由 [managedBy] 自動維護的提醒，依 symbol 分組（ID 由小到大）。
  ///
  /// **手動提醒（`managed_by IS NULL`）不會出現在結果中**——自動維護流程
  /// 只准改寫或刪除自己標記過的列，這道過濾就是那條保證的實作點
  /// （見 `PriceAlert.managedBy` 與 `TrailingMaAlertService`）。
  ///
  /// 回傳**清單**而非單筆：GUI 與 launchd CLI 是兩個 process 共用同一個
  /// SQLite，同時 refresh 可能各插一筆。呼叫端必須把多出來的收斂掉——
  /// 清理迴圈只掃「已非自選股」的列，重複提醒否則會靜默留存並每天各自通知。
  Future<Map<String, List<PriceAlertEntry>>> getManagedAlerts(
    String managedBy,
  ) async {
    final rows =
        await (select(priceAlert)
              ..where((t) => t.managedBy.equals(managedBy))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    final grouped = <String, List<PriceAlertEntry>>{};
    for (final r in rows) {
      grouped.putIfAbsent(r.symbol, () => []).add(r);
    }
    return grouped;
  }

  /// 建立新的股價提醒
  ///
  /// [managedBy] 留空 = 使用者手動設定，自動維護流程不會碰它。
  Future<int> createPriceAlert({
    required String symbol,
    required String alertType,
    required double targetValue,
    String? note,
    String? managedBy,
  }) {
    return into(priceAlert).insert(
      PriceAlertCompanion.insert(
        symbol: symbol,
        alertType: alertType,
        targetValue: targetValue,
        note: Value(note),
        managedBy: Value(managedBy),
      ),
    );
  }

  /// 更新股價提醒
  Future<void> updatePriceAlert(int id, PriceAlertCompanion entry) {
    return (update(priceAlert)..where((t) => t.id.equals(id))).write(entry);
  }

  /// 停用股價提醒（標記為已觸發）
  /// 原子式「認領」觸發(2026-08-08 code review)。
  ///
  /// app 內輪詢與 launchd CLI 跑在**兩個 process、同一個 SQLite**;原本的
  /// 無條件 UPDATE 會讓兩邊都讀到 pending、都發通知(系統通知 + app 通知
  /// 各一)。條件式 UPDATE + 回傳受影響列數 → 只有搶到的那個 process
  /// 才通知。
  ///
  /// 回傳 true=本次搶到(應發通知)、false=別人先觸發了(不要重複叫)。
  /// 認領一筆提醒的「通知權」——**只當互斥鍵,不消費提醒**。
  ///
  /// 🔑 兩把鑰匙不可共用一副鎖(2026-08-08 四次審查 Q1/Q4):
  /// - `triggeredAt` = **機器互斥**,誰寫進去誰負責通知
  /// - `isActive`    = **使用者意圖**,只有使用者能改
  ///
  /// 舊版在認領時一併寫 `isActive=false`,於是補償(釋放)也得把它寫回
  /// true——那就會覆蓋掉使用者在「認領到通知送出」之間手動關掉的動作,
  /// 讓他剛親手停用的提醒自己復活。改為認領只碰 `triggeredAt`,送出成功
  /// 後才由 [consumeAlertClaim] 消費。
  Future<bool> claimAlertTrigger(int id, {DateTime? now}) async {
    final affected =
        await (update(
          priceAlert,
        )..where((t) => t.id.equals(id) & t.triggeredAt.isNull())).write(
          PriceAlertCompanion(triggeredAt: Value(now ?? DateTime.now())),
        );
    return affected > 0;
  }

  /// 通知**確實送出後**才消費這筆提醒(一次性提醒就此停用)。
  ///
  /// 與 [claimAlertTrigger] 分開的理由見該處:認領只是取得通知權,
  /// 「用掉」是另一件事,必須等真的送出去才發生。
  /// 回收逾期未結案的認領(2026-08-08 五次審查 I-1)。
  ///
  /// 認領之後、消費或釋放之前 process 被殺/斷電,該筆會卡在
  /// `(isActive=true, triggeredAt≠null)` ——**兩條路徑都撿不到**,而 UI
  /// 的開關還顯示 ON。這與 [failOrphanRunningRuns] 處理的孤兒 RUNNING
  /// 是同一個形狀,解法照抄:`beforeOpen` 時把超過租約的清回待監控。
  ///
  /// ⚠️ **必須有 cutoff**:app 內輪詢與 launchd CLI 是兩個 process,
  /// 無條件清會把對方正在處理中的認領搶走 → 重複通知。
  ///
  /// 只回收 `isActive = true` 的:已消費的 `(false, T)` 是正常終點。
  /// 回傳回收筆數。
  Future<int> reclaimStaleAlertClaims({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(
      DataFreshness.alertClaimLease,
    );
    return (update(priceAlert)..where(
          (t) =>
              t.isActive.equals(true) &
              t.triggeredAt.isNotNull() &
              t.triggeredAt.isSmallerThanValue(cutoff),
        ))
        .write(const PriceAlertCompanion(triggeredAt: Value(null)));
  }

  /// 🔑 **必須帶 [stamp]**(2026-08-08 五次審查 C-1):否則會覆蓋使用者
  /// 在「認領到送出」之間手動重新啟用的動作。交錯:CLI 認領(T1)→
  /// 使用者在 osascript 往返期間(N 筆就是 N 次 Process.run,數秒等級)
  /// 把提醒關掉再打開 → 通知這時才成功回來 → 無條件 consume 把它靜默
  /// 關掉,終態與「從未觸發、使用者自己停用」完全無法區分。
  ///
  /// 整個重新設計的前提是「機器不可寫使用者意圖欄位」,而我第一版只把
  /// 這條規則套到 release,consume 這一半原封不動——**同一個 bug 修一半**。
  Future<bool> consumeAlertClaim(int id, {required DateTime stamp}) async {
    final affected =
        await (update(priceAlert)
              ..where((t) => t.id.equals(id) & t.triggeredAt.equals(stamp)))
            .write(const PriceAlertCompanion(isActive: Value(false)));
    return affected > 0;
  }

  /// 釋放 [claimAlertTrigger] 搶到的認領——通知**沒送出去**時必須呼叫。
  ///
  /// 🚨 為什麼需要這支(2026-08-08 三次審查 C-1):認領一定要發生在通知
  /// **之前**,否則 app 內輪詢與 launchd CLI 兩個 process 會重複通知。
  /// 但代價是「已認領」不等於「已送達」——通知若失敗(osascript 被系統
  /// 抑制、plugin channel 斷線、設定把該類通知關掉),該筆會停在
  /// `isActive=false` + `triggeredAt!=null`,而**兩條路徑的 pending 過濾
  /// 都會永久跳過它**:使用者沒收到通知,收盤那條也再看不到,提醒等於
  /// 被靜默燒掉。有了釋放,失敗就退回可重試狀態,下一輪(5 分鐘後)再試。
  /// 撤銷 [claimAlertTrigger] 取得的通知權——通知**沒送出去**時呼叫。
  ///
  /// 🔑 **必須帶 [stamp]**(2026-08-08 四次審查 Q2-b):否則會把**別人剛
  /// 寫進去的**認領一起抹掉。真實交錯:CLI 認領(T1)→ 使用者把開關撥
  /// 回 ON(重置 triggeredAt)→ GUI 重新認領(T2)並成功通知 → CLI 這時
  /// 才發現自己失敗去釋放,把 T2 抹掉 → 同一次觸價被通知兩次。
  ///
  /// 也**不碰 `isActive`**:那是使用者意圖,不是機器該寫的欄位。
  ///
  /// 回傳是否真的撤銷了自己的那筆認領(false = 認領已被別人取代)。
  /// [stamp] 為**必填**(2026-08-08 五次審查 I-5):舊版設成 optional,
  /// 而 `stamp == null` 那條 fallback 的行為正是本輪判定為 bug 的舊行為
  /// (會抹掉別人剛寫的認領)。留著預設值等於留一個「忘了傳就靜默退回
  /// bug 版」的陷阱——**編譯器擋掉比註解可靠**。
  ///
  /// ⚠️ 這個 CAS 的正確性隱性依賴 `storeDateTimeAsText: true`(微秒精度)。
  /// 若改回預設的 unix 秒儲存,比對會靜默退化成秒粒度。
  Future<bool> releaseAlertClaim(int id, {required DateTime stamp}) async {
    final affected =
        await (update(priceAlert)
              ..where((t) => t.id.equals(id) & t.triggeredAt.equals(stamp)))
            .write(const PriceAlertCompanion(triggeredAt: Value(null)));
    return affected > 0;
  }

  /// **僅測試 seeding 使用**(2026-08-15 稽核):production 觸發一律走
  /// [claimAlertTrigger]+[consumeAlertClaim] 的併發 claim 機制——此方法
  /// 直接寫 triggeredAt 會繞過 claim 保護,誤用即重演併發重複觸發 bug
  Future<void> triggerAlert(int id, {DateTime? now}) {
    return (update(priceAlert)..where((t) => t.id.equals(id))).write(
      PriceAlertCompanion(
        isActive: const Value(false),
        triggeredAt: Value(now ?? DateTime.now()),
      ),
    );
  }

  /// 刪除股價提醒
  Future<void> deletePriceAlert(int id) {
    return (delete(priceAlert)..where((t) => t.id.equals(id))).go();
  }

  /// 比對提醒與當前價格，回傳已觸發的提醒
  ///
  /// [evaluationService] 可由呼叫端注入，避免 DAO 直接建立 domain service。
  Future<List<PriceAlertEntry>> checkAlerts(
    Map<String, double> currentPrices,
    Map<String, double> priceChanges, {
    AlertEvaluationService? evaluationService,
  }) async {
    final activeAlerts = await getActiveAlerts();
    if (activeAlerts.isEmpty) return [];

    final symbols = activeAlerts.map((a) => a.symbol).toSet().toList();

    // 統一時間基準，避免各 helper 各自呼叫 DateTime.now()
    final now = DateTime.now();

    // Data fetching stays in DAO (needs DB access)
    final volumeDataMap = await _fetchVolumeDataForAlerts(symbols, now);
    final priceHistoryMap = await _fetchPriceHistoryForAlerts(symbols, now);
    final indicatorDataMap = await _fetchIndicatorDataForAlerts(symbols, now);

    // 以批次查詢取代逐筆 N+1 模式，避免 N 個 symbol 產生 2N 次 DB 往返
    final disposalSymbols = await _fetchDisposalSymbolsBatch(symbols);
    final warningSymbols = await _fetchWarningSymbolsBatch(symbols);

    // Phase 3: 按需查詢進階警示所需的基本面/籌碼資料
    final alertTypes = activeAlerts.map((a) => a.alertType).toSet();
    final needsFundamental = alertTypes.any(
      (t) => const {
        'REVENUE_YOY_SURGE',
        'HIGH_DIVIDEND_YIELD',
        'PE_UNDERVALUED',
      }.contains(t),
    );
    final needsInsider = alertTypes.any(
      (t) => const {
        'INSIDER_SELLING',
        'INSIDER_BUYING',
        'HIGH_PLEDGE_RATIO',
      }.contains(t),
    );

    final revenueYoyMap = <String, double>{};
    final dividendYieldMap = <String, double>{};
    final peRatioMap = <String, double>{};
    final insiderChangeMap = <String, double>{};
    final pledgeRatioMap = <String, double>{};

    if (needsFundamental) {
      await _fetchFundamentalDataForAlerts(
        symbols,
        revenueYoyMap: revenueYoyMap,
        dividendYieldMap: dividendYieldMap,
        peRatioMap: peRatioMap,
      );
    }
    if (needsInsider) {
      await _fetchInsiderDataForAlerts(
        symbols,
        insiderChangeMap: insiderChangeMap,
        pledgeRatioMap: pledgeRatioMap,
      );
    }

    // Delegate evaluation to domain service (prefer injection from caller)
    final service = evaluationService ?? AlertEvaluationService();
    final result = service.evaluateAlerts(
      activeAlerts,
      AlertEvaluationContext(
        currentPrices: currentPrices,
        priceChanges: priceChanges,
        volumeDataMap: volumeDataMap,
        priceHistoryMap: priceHistoryMap,
        indicatorDataMap: indicatorDataMap,
        warningSymbols: warningSymbols,
        disposalSymbols: disposalSymbols,
        revenueYoyMap: revenueYoyMap,
        dividendYieldMap: dividendYieldMap,
        peRatioMap: peRatioMap,
        insiderChangeMap: insiderChangeMap,
        pledgeRatioMap: pledgeRatioMap,
      ),
    );

    // 自動停用未實作的警示類型（舊版 DB 殘留資料）
    for (final id in result.unimplementedIds) {
      await updatePriceAlert(
        id,
        const PriceAlertCompanion(isActive: Value(false)),
      );
    }

    return result.triggered;
  }

  // ==================================================
  // 警示檢查輔助方法 - Batch 1: 成交量警示
  // ==================================================

  /// 批次查詢成交量資料（最近 20 天）
  Future<Map<String, List<DailyPriceEntry>>> _fetchVolumeDataForAlerts(
    List<String> symbols,
    DateTime endDate,
  ) async {
    if (symbols.isEmpty) return {};
    final startDate = endDate.subtract(
      const Duration(days: AlertParams.volumeDataLookbackDays),
    );

    final query = select(dailyPrice)
      ..where((t) => t.symbol.isIn(symbols))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate))
      ..where((t) => t.date.isSmallerOrEqualValue(endDate))
      ..orderBy([
        (t) => OrderingTerm.asc(t.symbol),
        (t) => OrderingTerm.asc(t.date),
      ]);

    final results = await query.get();
    return BatchQueryHelper.groupBySymbol(results, (entry) => entry.symbol);
  }

  /// 批次查詢 52 週價格歷史
  Future<Map<String, List<DailyPriceEntry>>> _fetchPriceHistoryForAlerts(
    List<String> symbols,
    DateTime endDate,
  ) async {
    if (symbols.isEmpty) return {};
    final startDate = endDate.subtract(
      const Duration(days: AlertParams.week52LookbackDays),
    );

    final query = select(dailyPrice)
      ..where((t) => t.symbol.isIn(symbols))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate))
      ..where((t) => t.date.isSmallerOrEqualValue(endDate))
      ..orderBy([
        (t) => OrderingTerm.asc(t.symbol),
        (t) => OrderingTerm.asc(t.date),
      ]);

    final results = await query.get();
    return BatchQueryHelper.groupBySymbol(results, (entry) => entry.symbol);
  }

  /// 批次查詢技術指標資料（最近 30 天，用於計算 RSI 和 KD）
  Future<Map<String, List<DailyPriceEntry>>> _fetchIndicatorDataForAlerts(
    List<String> symbols,
    DateTime endDate,
  ) async {
    if (symbols.isEmpty) return {};
    final startDate = endDate.subtract(
      const Duration(days: AlertParams.indicatorDataLookbackDays),
    );

    final query = select(dailyPrice)
      ..where((t) => t.symbol.isIn(symbols))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate))
      ..where((t) => t.date.isSmallerOrEqualValue(endDate))
      ..orderBy([
        (t) => OrderingTerm.asc(t.symbol),
        (t) => OrderingTerm.asc(t.date),
      ]);

    final results = await query.get();
    return BatchQueryHelper.groupBySymbol(results, (entry) => entry.symbol);
  }

  /// 批次取得處置股代碼（批次查詢，供警示檢查使用）
  Future<Set<String>> _fetchDisposalSymbolsBatch(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    final results =
        await (select(tradingWarning)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.isActive.equals(true))
              ..where((t) => t.warningType.equals('DISPOSAL')))
            .get();
    return results.map((r) => r.symbol).toSet();
  }

  /// 批次取得有警示（不含處置）的股票代碼（批次查詢，供警示檢查使用）
  Future<Set<String>> _fetchWarningSymbolsBatch(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    final results =
        await (select(tradingWarning)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.isActive.equals(true))
              ..where((t) => t.warningType.isNotValue('DISPOSAL')))
            .get();
    return results.map((r) => r.symbol).toSet();
  }

  // ==================================================
  // 進階警示資料查詢（Phase 3）
  // ==================================================

  /// 批次查詢基本面資料：營收年增率、殖利率、本益比
  Future<void> _fetchFundamentalDataForAlerts(
    List<String> symbols, {
    required Map<String, double> revenueYoyMap,
    required Map<String, double> dividendYieldMap,
    required Map<String, double> peRatioMap,
  }) async {
    // 營收年增率：取最近 3 個月的營收資料（每 symbol 只用最新一筆）
    final cutoffDate = DateTime.now().subtract(const Duration(days: 120));
    final revenues =
        await (select(monthlyRevenue)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.date.isBiggerOrEqualValue(cutoffDate))
              ..orderBy([
                (t) => OrderingTerm.desc(t.revenueYear),
                (t) => OrderingTerm.desc(t.revenueMonth),
              ]))
            .get();

    // 每個 symbol 只取最新一筆
    final seenRevenue = <String>{};
    for (final r in revenues) {
      if (!seenRevenue.contains(r.symbol) && r.yoyGrowth != null) {
        revenueYoyMap[r.symbol] = r.yoyGrowth!;
        seenRevenue.add(r.symbol);
      }
    }

    // 殖利率和本益比：從 stockValuation 表取最近 30 天資料
    final valCutoff = DateTime.now().subtract(const Duration(days: 30));
    final valuations =
        await (select(stockValuation)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.date.isBiggerOrEqualValue(valCutoff))
              ..orderBy([(t) => OrderingTerm.desc(t.date)]))
            .get();

    final seenValuation = <String>{};
    for (final v in valuations) {
      if (!seenValuation.contains(v.symbol)) {
        if (v.dividendYield != null && v.dividendYield! > 0) {
          dividendYieldMap[v.symbol] = v.dividendYield!;
        }
        if (v.per != null && v.per! > 0) {
          peRatioMap[v.symbol] = v.per!;
        }
        seenValuation.add(v.symbol);
      }
    }
  }

  /// 批次查詢籌碼資料：董監持股變動、質押比例
  Future<void> _fetchInsiderDataForAlerts(
    List<String> symbols, {
    required Map<String, double> insiderChangeMap,
    required Map<String, double> pledgeRatioMap,
  }) async {
    // 董監持股：取最近 6 個月的資料（只需最新一筆的 sharesChange）
    final holdingCutoff = DateTime.now().subtract(const Duration(days: 180));
    final holdings =
        await (select(insiderHolding)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.date.isBiggerOrEqualValue(holdingCutoff))
              ..orderBy([(t) => OrderingTerm.desc(t.date)]))
            .get();

    // 按 symbol 分組，取最新一筆的既存 sharesChange
    final grouped = <String, List<InsiderHoldingEntry>>{};
    for (final h in holdings) {
      (grouped[h.symbol] ??= []).add(h);
    }
    for (final entry in grouped.entries) {
      final list = entry.value;
      if (list.isNotEmpty && list[0].sharesChange != null) {
        insiderChangeMap[entry.key] = list[0].sharesChange!;
      }
    }

    // 質押比例
    for (final entry in grouped.entries) {
      if (entry.value.isNotEmpty) {
        final latest = entry.value.first;
        if (latest.pledgeRatio != null) {
          pledgeRatioMap[entry.key] = latest.pledgeRatio!;
        }
      }
    }
  }
}

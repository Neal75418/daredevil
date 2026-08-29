// tool/ 共用的 DB 開啟入口——**唯一**允許呼叫 AppDatabase.forToolFile
// 的地方(guard 測試把關)。
//
// 為什麼要有這個檔案(2026-08-29 稽核):AppDatabase 的 schema fingerprint
// 不符時會 DROP 所有非 user-input 表。對 app DB 那是可接受的(derived
// data,隔天重抓);對 `tool/calibration.db` 是**九年歷史當場歸零**。
// 守衛原本只寫在 backfill.dart 一支裡,而 9 個 tool 會開這個檔案——
// 稽核實測其餘 8 支全裸奔,且只要有人照 CLAUDE.md 的 DB 變更流程 bump
// 一次 fingerprint 就會引爆(2026-07-18 已經真的燒過一次 1.2 GB)。
import 'package:sqlite3/sqlite3.dart';

import 'package:daredevil/data/database/app_database.dart';

/// fingerprint 不符——**開 DB 前**就中止,附人工處置指引。
class SchemaFingerprintMismatch implements Exception {
  const SchemaFingerprintMismatch(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 開啟 tool 用的 DB。
///
/// [allowSchemaReset] 只給「開 app DB 且資料皆為 derived」的 CLI
/// (daily_update / intraday_alert_check)——那裡 reset 是可接受的,
/// 隔天 syncer 重抓即可。校準鏈一律不得開。
AppDatabase openToolDatabase(String path, {bool allowSchemaReset = false}) {
  if (!allowSchemaReset) {
    final mismatch = checkSchemaFingerprint(path);
    if (mismatch != null) throw SchemaFingerprintMismatch(mismatch);
  }
  return AppDatabase.forToolFile(path);
}

/// 開 DB 前比對 schema fingerprint，不一致就中止並回傳錯誤訊息（null = 安全）。
///
/// 為什麼需要這道關卡：[AppDatabase] 的 `_ensureSchemaFingerprint` 在
/// fingerprint 不符時，會把所有**非 user-input whitelist** 的 Drift 表
/// `DROP` 後重建。對 app 而言這是可接受的——那些都是 derived data，隔天
/// syncer 重抓即可。對 `tool/calibration.db` 卻是**九年歷史當場歸零**：
/// 310 萬筆價格 + 250 萬筆法人，重抓要數十小時而且 FinMind 免費配額根本
/// 不夠。
///
/// 2026-07-18 實測（在副本上）：`calibration.db` 存的 fingerprint 是
/// `stage5b-dual-horizon-2026-04-11`、code 已是
/// `stage5b-news-mention-daily-2026-07-15`，開一次 tool 之後
/// `daily_price` / `stock_master` / `daily_institutional` 全部變 0 列。
/// 檔案大小不變（freelist 未回收），**從外觀完全看不出資料已經沒了**。
///
/// 修法不是在這裡自動 reset，而是要人工確認 schema 差異後補齊 + 更新
/// fingerprint（見錯誤訊息內的指引）。自動化這件事等於把「無聲毀資料」
/// 從一種路徑換到另一種。
String? checkSchemaFingerprint(String dbPath) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final hasTable = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='_drift_schema_fingerprint'",
    );
    // 沒有 fingerprint 表 = 這個 DB 還沒被現行機制管理過，交給
    // AppDatabase 自己初始化（它會走 `stored == null` 的 else 分支、只寫入
    // 不 drop）。
    if (hasTable.isEmpty) return null;

    final rows = db.select(
      'SELECT value FROM _drift_schema_fingerprint WHERE id = 1',
    );
    if (rows.isEmpty) return null;

    final stored = rows.first['value'] as String?;
    if (stored == null || stored == appSchemaFingerprint) return null;

    return '''
❌ Schema fingerprint 不符 — 已中止，未開啟 DB。
   DB   : $dbPath
   stored  = $stored
   expected= $appSchemaFingerprint

   直接開啟會觸發 AppDatabase 的 schema reset：所有非 user-input 表
   （daily_price / stock_master / daily_institutional / day_trading ...）
   會被 DROP 重建，歷史資料全數消失且檔案大小不變、事後難以察覺。

💡 處理方式：
   1. 先備份：sqlite3 "file:$dbPath?mode=ro" "VACUUM INTO '<backup>.db'"
   2. 比對 schema 差異（對照一個用現行 code 新建的空 DB）：
      SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%';
   3. 差異若只是「新增表 / 新增索引」，手動補上該表與索引後執行：
      UPDATE _drift_schema_fingerprint SET value='$appSchemaFingerprint' WHERE id=1;
   4. 若有既存表的欄位變動，必須先 ALTER TABLE 對齊再更新 fingerprint。
''';
  } finally {
    db.close();
  }
}

// watchlist_groups.is_default 欄位的 ALTER 升級路徑(2026-08-12)
//
// `watchlist_groups` 在 fingerprint reset 的白名單內——指紋 bump 不會
// migrate 它(`CREATE TABLE IF NOT EXISTS` 看到既存表直接跳過)。所以加
// `is_default` 欄必須走 `_ensureWatchlistGroupsSchema` 的 ALTER 路徑,
// 而這條測試模擬的就是真實升級場景:**帶著舊 schema 與使用者資料的 DB
// 被新版 app 開啟**。
//
// 若這條紅了,代表既有使用者(= 開發者自己的 587k 列正式 DB)升級後會炸
// `no such column: is_default`。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wg_default_col_test');
    dbFile = File('${tempDir.path}/wg_test.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('🚨 舊 DB(無 is_default 欄)開啟後補欄,既有分組與旗標語意保留', () async {
    // 1. 手工造一個「舊版 schema」的 DB:watchlist_groups 沒有 is_default
    //    (DDL 抄自加欄前的 generated schema,含一筆使用者分組)
    final raw = NativeDatabase(dbFile);
    final db1 = AppDatabase(raw);
    await db1.customSelect('SELECT 1').get(); // 建出完整新 schema
    // 用「刪欄」模擬舊 DB:SQLite 3.35+ 支援 DROP COLUMN
    await db1.customStatement(
      'ALTER TABLE watchlist_groups DROP COLUMN is_default',
    );
    await db1.customStatement(
      "INSERT INTO watchlist_groups (name, sort_order) VALUES ('備取觀察', 0)",
    );
    await db1.close();

    // 2. 重新開啟 → beforeOpen 的 ALTER 路徑必須補回欄位
    final db2 = AppDatabase(NativeDatabase(dbFile));
    final groups = await db2.getWatchlistGroups();

    expect(groups, hasLength(1), reason: '既有分組必須保留');
    expect(groups.single.name, '備取觀察');
    expect(
      groups.single.isDefault,
      isFalse,
      reason: '補欄後預設為 false——升級不得憑空指定預設分組',
    );

    // 3. ALTER 出來的 DDL 要與 generated schema 語意一致——少了 NOT NULL
    //    或 CHECK,這條要紅(欄位順序不同無妨,drift 按名稱讀)
    final ddl =
        (await db2
                .customSelect(
                  "SELECT sql FROM sqlite_master WHERE name = 'watchlist_groups'",
                )
                .getSingle())
            .read<String>('sql');
    expect(ddl, contains('is_default'));
    expect(
      ddl.replaceAll('"', ''),
      contains('is_default INTEGER NOT NULL DEFAULT 0'),
    );
    expect(ddl.replaceAll('"', ''), contains('CHECK (is_default IN (0, 1))'));

    // 4. 補欄後功能可用
    await db2.setDefaultWatchlistGroup(groups.single.id);
    expect((await db2.getDefaultWatchlistGroup())!.id, groups.single.id);
    await db2.close();
  });
}

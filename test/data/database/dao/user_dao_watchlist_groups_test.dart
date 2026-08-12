// Integration tests for watchlist 自訂分組（資料夾模式）DAO 方法
//
// 用 in-memory Drift (`AppDatabase.forTesting`) 驗證分組 CRUD、指定分組、
// LEFT JOIN 帶分組名稱，以及刪除分組時 FK `onDelete: setNull` 的行為
// （成員回到未分組、不連帶刪除股票）。

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  // watchlist.symbol 有 FK 參照 StockMaster，先建主檔再加自選
  Future<void> insertTestStocks() async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2454', name: '聯發科', market: 'TWSE'),
    ]);
  }

  group('createWatchlistGroup', () {
    test('建立分組並回傳遞增 id', () async {
      final id1 = await db.createWatchlistGroup('核心持股');
      final id2 = await db.createWatchlistGroup('觀察名單');

      expect(id1, isNonZero);
      expect(id2, greaterThan(id1));

      final groups = await db.getWatchlistGroups();
      expect(groups.map((g) => g.name), ['核心持股', '觀察名單']);
    });

    test('新分組 sortOrder 遞增（附加在末端）', () async {
      await db.createWatchlistGroup('A');
      await db.createWatchlistGroup('B');
      await db.createWatchlistGroup('C');

      final groups = await db.getWatchlistGroups();
      // 依 sortOrder asc 排序，順序應為建立順序
      expect(groups.map((g) => g.name), ['A', 'B', 'C']);
      expect(groups.map((g) => g.sortOrder), [0, 1, 2]);
    });
  });

  group('renameWatchlistGroup', () {
    test('改名後查詢回傳新名稱', () async {
      final id = await db.createWatchlistGroup('舊名');
      await db.renameWatchlistGroup(id, '新名');

      final groups = await db.getWatchlistGroups();
      expect(groups.single.name, '新名');
    });
  });

  group('assignWatchlistGroup', () {
    test('指定股票到分組，getWatchlistWithGroups 帶出分組名稱', () async {
      await insertTestStocks();
      await db.addToWatchlist('2330');
      final groupId = await db.createWatchlistGroup('核心');

      await db.assignWatchlistGroup('2330', groupId);

      final withGroups = await db.getWatchlistWithGroups();
      final entry = withGroups.firstWhere((w) => w.entry.symbol == '2330');
      expect(entry.entry.groupId, groupId);
      expect(entry.groupName, '核心');
    });

    test('指定 null 代表移出分組', () async {
      await insertTestStocks();
      await db.addToWatchlist('2330');
      final groupId = await db.createWatchlistGroup('核心');
      await db.assignWatchlistGroup('2330', groupId);

      await db.assignWatchlistGroup('2330', null);

      final withGroups = await db.getWatchlistWithGroups();
      final entry = withGroups.firstWhere((w) => w.entry.symbol == '2330');
      expect(entry.entry.groupId, isNull);
      expect(entry.groupName, isNull);
    });
  });

  group('getWatchlistWithGroups', () {
    test('未分組股票 groupName 為 null', () async {
      await insertTestStocks();
      await db.addToWatchlist('2317');

      final withGroups = await db.getWatchlistWithGroups();
      final entry = withGroups.single;
      expect(entry.entry.symbol, '2317');
      expect(entry.entry.groupId, isNull);
      expect(entry.groupName, isNull);
    });

    test('混合分組與未分組正確帶出名稱', () async {
      await insertTestStocks();
      await db.addToWatchlist('2330');
      await db.addToWatchlist('2317');
      await db.addToWatchlist('2454');
      final groupId = await db.createWatchlistGroup('科技');
      await db.assignWatchlistGroup('2330', groupId);
      await db.assignWatchlistGroup('2454', groupId);

      final withGroups = await db.getWatchlistWithGroups();
      final byName = {for (final w in withGroups) w.entry.symbol: w.groupName};
      expect(byName['2330'], '科技');
      expect(byName['2454'], '科技');
      expect(byName['2317'], isNull);
    });
  });

  group('deleteWatchlistGroup — FK onDelete setNull', () {
    test('刪除分組後成員變未分組、股票不被連帶刪除', () async {
      await insertTestStocks();
      await db.addToWatchlist('2330');
      await db.addToWatchlist('2317');
      final groupId = await db.createWatchlistGroup('待刪');
      await db.assignWatchlistGroup('2330', groupId);
      await db.assignWatchlistGroup('2317', groupId);

      await db.deleteWatchlistGroup(groupId);

      // 分組已刪
      expect(await db.getWatchlistGroups(), isEmpty);

      // 兩檔股票仍在自選清單（沒被 cascade 刪掉）
      final watchlist = await db.getWatchlist();
      expect(watchlist.map((w) => w.symbol), containsAll(['2330', '2317']));

      // 成員 groupId 被 setNull 清空
      final withGroups = await db.getWatchlistWithGroups();
      for (final w in withGroups) {
        expect(w.entry.groupId, isNull);
        expect(w.groupName, isNull);
      }
    });
  });

  // 預設分組（2026-08-12）：解決「加入自選一律未分組」的問題——實測連續
  // 四檔（新盛力/力成/技嘉/微星）都落在 NULL 組,對排程掃描不可見。
  // 選「分組上掛 is_default 旗標」而非 app_settings 存 id 或寫死組名:
  // 旗標跟著列走,改名不斷、刪組自動失效,不需要懸空 id 的存在性檢查。
  group('預設分組', () {
    test('🚨 單一預設不變量:設 B 後 A 的旗標必須自動清除', () async {
      final idA = await db.createWatchlistGroup('A');
      final idB = await db.createWatchlistGroup('B');

      await db.setDefaultWatchlistGroup(idA);
      await db.setDefaultWatchlistGroup(idB);

      final groups = await db.getWatchlistGroups();
      expect(
        groups.where((g) => g.isDefault).map((g) => g.id),
        [idB],
        reason: '同時兩個預設會讓「新加入落到哪」變成未定義行為',
      );
    });

    test('setDefaultWatchlistGroup(null) 清除所有預設', () async {
      final id = await db.createWatchlistGroup('A');
      await db.setDefaultWatchlistGroup(id);
      await db.setDefaultWatchlistGroup(null);

      expect(await db.getDefaultWatchlistGroup(), isNull);
    });

    test('無預設分組時,加入自選維持未分組(既有行為不變)', () async {
      await insertTestStocks();
      await db.addToWatchlist('2330');

      final entry = await db.getWatchlistEntry('2330');
      expect(entry!.groupId, isNull);
    });

    test('🚨 有預設分組時,新加入自動落入預設組', () async {
      await insertTestStocks();
      final id = await db.createWatchlistGroup('備取觀察');
      await db.setDefaultWatchlistGroup(id);

      await db.addToWatchlist('2330');

      final entry = await db.getWatchlistEntry('2330');
      expect(entry!.groupId, id, reason: '這是整個功能的核心行為');
    });

    test('明確指定 groupId 時覆蓋預設(復原場景)', () async {
      await insertTestStocks();
      final defaultId = await db.createWatchlistGroup('預設');
      final otherId = await db.createWatchlistGroup('原分組');
      await db.setDefaultWatchlistGroup(defaultId);

      await db.addToWatchlist('2330', groupId: Value(otherId));

      final entry = await db.getWatchlistEntry('2330');
      expect(entry!.groupId, otherId);
    });

    test('🚨 明確指定 null 時維持未分組,即使有預設(復原「本來就未分組」)', () async {
      await insertTestStocks();
      final defaultId = await db.createWatchlistGroup('預設');
      await db.setDefaultWatchlistGroup(defaultId);

      await db.addToWatchlist('2330', groupId: const Value(null));

      final entry = await db.getWatchlistEntry('2330');
      expect(
        entry!.groupId,
        isNull,
        reason: 'Value(null) 與 Value.absent() 語意不同:前者是「就是要未分組」',
      );
    });

    test('🚨 明確 groupId 指向已刪除的組 → 落回未分組,不炸 FK', () async {
      await insertTestStocks();
      final id = await db.createWatchlistGroup('曇花一現');
      await db.deleteWatchlistGroup(id);

      // 移除→刪組→復原 的競態:復原時原分組已不存在
      await db.addToWatchlist('2330', groupId: Value(id));

      final entry = await db.getWatchlistEntry('2330');
      expect(entry, isNotNull, reason: '復原本身必須成功');
      expect(entry!.groupId, isNull);
    });

    test('刪除預設組後,新加入回到未分組', () async {
      await insertTestStocks();
      final id = await db.createWatchlistGroup('預設');
      await db.setDefaultWatchlistGroup(id);
      await db.deleteWatchlistGroup(id);

      await db.addToWatchlist('2330');

      final entry = await db.getWatchlistEntry('2330');
      expect(entry!.groupId, isNull);
      expect(await db.getDefaultWatchlistGroup(), isNull);
    });
  });
}

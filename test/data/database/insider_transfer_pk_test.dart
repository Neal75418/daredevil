// 內部人轉讓 PK 補 transfer_method(2026-08-16)
//
// **實證**:2026-08-14 實機,2442 同一位「經理人未成年子女」同日以多種
// 方式申報,PK={symbol, reportDate, identity, name} 不含轉讓方式 →
// `insertOrReplace` 塌縮。當日 syncer 收到 7 筆、DB 實際只有 5 筆,而日誌
// 報「同步完成: 7 筆」(報的是輸入陣列長度)——資料少了兩筆,日誌卻宣稱
// 完整,那比少兩筆更危險。
//
// syncer 裡的 PK 碰撞哨(2026-08-05 加)當時註明「live 未見樣本…觀察到
// 實例再議 migration」。現在觀察到了,而且警告印兩次代表同一 PK 出現
// **三次**(`if (!pkSeen.add(pk))` 每次重複都印)。
//
// **為什麼不用聚合寫入**(把同 PK 的股數加總,零 schema 風險):
// `transferMethod` 直接顯示在 UI(insider_tab 的 `'${name} - ${method}'`),
// 聚合後畫面會顯示「盤後定價交易 243,844」而那其實是三種方式的總和——
// 少顯示兩筆是資訊不全,顯示錯的方式是資訊錯誤。
//
// **不 bump fingerprint / schemaVersion**:沿用 `_ensureRetiredSchemaDropped`
// 與 `_ensureDealerSelfNetColumn` 的 idempotent DDL 先例。指紋是手寫常數,
// 不動它就不會進入 wipe 路徑;既有資料以 INSERT SELECT 完整搬移。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2442', name: '新美齊', market: 'TWSE'),
    ]);
  });
  tearDown(() async => db.close());

  final reportDate = DateTime.utc(2026, 8, 14);

  InsiderTransferCompanion transfer(String method, int shares) =>
      InsiderTransferCompanion.insert(
        symbol: '2442',
        reportDate: reportDate,
        identity: '經理人未成年子女',
        name: '林傳捷之未成年子女',
        transferMethod: method,
        transferShares: shares,
        currentHolding: 1000000,
      );

  test('🚨 同人同日多種轉讓方式必須各存一筆(實機 2442 案例)', () async {
    await db.insertInsiderTransfers([
      transfer('盤後定價交易', 243844),
      transfer('鉅額逐筆交易', 500000),
      transfer('一般交易', 100000),
    ]);

    final rows = await db
        .customSelect(
          "SELECT transfer_method, transfer_shares FROM insider_transfer "
          "WHERE symbol='2442'",
        )
        .get();

    expect(
      rows,
      hasLength(3),
      reason:
          'PK 不含 transfer_method 時三筆會塌縮成一筆,轉讓總量低報 '
          '${500000 + 100000} 股。實機當日 7 筆進、5 筆出',
    );
    final total = rows.fold<int>(
      0,
      (s, r) => s + r.read<int>('transfer_shares'),
    );
    expect(total, 843844);
  });

  test('同人同日同方式仍應去重(真正的重複)', () async {
    await db.insertInsiderTransfers([
      transfer('盤後定價交易', 243844),
      transfer('盤後定價交易', 243844),
    ]);
    final rows = await db
        .customSelect("SELECT * FROM insider_transfer WHERE symbol='2442'")
        .get();
    expect(rows, hasLength(1), reason: '完全相同的申報是重複資料,該塌縮');
  });

  test('不同人同日同方式各存一筆', () async {
    await db.insertInsiderTransfers([
      transfer('鉅額逐筆交易', 243844),
      InsiderTransferCompanion.insert(
        symbol: '2442',
        reportDate: reportDate,
        identity: '經理人本人',
        name: '林傳捷',
        transferMethod: '鉅額逐筆交易',
        transferShares: 948530,
        currentHolding: 948530,
      ),
    ]);
    final rows = await db
        .customSelect("SELECT * FROM insider_transfer WHERE symbol='2442'")
        .get();
    expect(rows, hasLength(2));
  });

  group('既有 DB 升級(使用者最在意的:資料不得遺失)', () {
    /// 重建成**舊** PK 的表,模擬升級前的 live DB
    Future<void> downgradeToOldSchema() async {
      await db.customStatement('DROP TABLE insider_transfer');
      await db.customStatement('''
        CREATE TABLE insider_transfer (
          symbol TEXT NOT NULL REFERENCES stock_master (symbol) ON DELETE CASCADE,
          report_date TEXT NOT NULL,
          identity TEXT NOT NULL,
          name TEXT NOT NULL,
          transfer_method TEXT NOT NULL,
          transfer_shares INTEGER NOT NULL,
          current_holding INTEGER NOT NULL,
          valid_period_start TEXT NULL,
          valid_period_end TEXT NULL,
          PRIMARY KEY (symbol, report_date, identity, name)
        )
      ''');
      await db.customStatement(
        'CREATE INDEX idx_insider_transfer_date '
        'ON insider_transfer (report_date)',
      );
    }

    Future<List<String>> pkColumns() async {
      final info = await db
          .customSelect("PRAGMA table_info('insider_transfer')")
          .get();
      return info
          .where((r) => r.read<int>('pk') > 0)
          .map((r) => r.read<String>('name'))
          .toList();
    }

    test('🚨 升級後既有資料一列不少', () async {
      await downgradeToOldSchema();
      await db.insertInsiderTransfers([
        transfer('盤後定價交易', 243844),
        InsiderTransferCompanion.insert(
          symbol: '2442',
          reportDate: DateTime.utc(2026, 8, 13),
          identity: '董事本人',
          name: '某董事',
          transferMethod: '贈與',
          transferShares: 500,
          currentHolding: 9999,
          validPeriodStart: Value(DateTime.utc(2026, 8, 17)),
        ),
      ]);
      expect(await pkColumns(), isNot(contains('transfer_method')));

      await db.ensureInsiderTransferPk();

      expect(await pkColumns(), contains('transfer_method'), reason: 'PK 已升級');
      final rows = await db
          .customSelect('SELECT * FROM insider_transfer ORDER BY report_date')
          .get();
      expect(rows, hasLength(2), reason: '既有資料必須完整搬移');
      expect(rows.last.read<int>('transfer_shares'), 243844);
      expect(
        rows.first.read<String?>('valid_period_start'),
        isNotNull,
        reason: 'nullable 欄位的值也要搬過去',
      );
    });

    test('index 在升級後仍存在(DROP TABLE 會一併帶走)', () async {
      await downgradeToOldSchema();
      await db.ensureInsiderTransferPk();
      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='insider_transfer'",
          )
          .get();
      expect(
        idx.map((r) => r.read<String>('name')),
        contains('idx_insider_transfer_date'),
      );
    });

    test('重跑安全(idempotent)——每次開 app 都會執行', () async {
      await downgradeToOldSchema();
      await db.insertInsiderTransfers([transfer('盤後定價交易', 243844)]);
      await db.ensureInsiderTransferPk();
      await db.ensureInsiderTransferPk();
      await db.ensureInsiderTransferPk();
      final rows = await db
          .customSelect('SELECT * FROM insider_transfer')
          .get();
      expect(rows, hasLength(1), reason: '重跑不得複製或清空資料');
      expect(await pkColumns(), contains('transfer_method'));
    });

    test('🚨 殘留的 temp table 不得讓下次開啟炸掉(2026-08-16 code review)', () async {
      // 原實作是裸的 CREATE/INSERT/DROP/RENAME:任一步失敗(beforeOpen 的
      // lock timeout 是本專案有記載的失效模式)會留下 insider_transfer_new,
      // 下次開啟的 CREATE 就撞「table already exists」→ DB 對 GUI 與兩支 CLI
      // 全部開不了。這比它要修的低報嚴重得多。
      await downgradeToOldSchema();
      await db.insertInsiderTransfers([transfer('盤後定價交易', 243844)]);
      // 模擬上次中斷:temp table 殘留
      await db.customStatement(
        'CREATE TABLE insider_transfer_new (symbol TEXT NOT NULL)',
      );

      await db.ensureInsiderTransferPk();

      expect(await pkColumns(), contains('transfer_method'));
      final rows = await db
          .customSelect('SELECT * FROM insider_transfer')
          .get();
      expect(rows, hasLength(1), reason: '資料仍在');
      final leftover = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='insider_transfer_new'",
          )
          .get();
      expect(leftover, isEmpty, reason: 'temp table 不得殘留');
    });
  });
}

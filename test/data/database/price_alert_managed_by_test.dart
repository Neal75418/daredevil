// price_alert 補 managed_by 欄(2026-08-16)
//
// **為什麼要加**:均線階梯提醒([TrailingMaAlertService])每日重算並改寫
// 提醒價位。沒有這欄就分不出「自動維護的」與「使用者手動設的」——重算
// 會把使用者特地設的關鍵價位一起洗掉。`managed_by IS NULL` = 手動,
// 自動流程一律不得碰。
//
// **不 bump [appSchemaFingerprint] / [schemaVersion]**:沿用
// `_ensureDealerSelfNetColumn`、`_ensureMonthlyRevenueYtdColumn` 的先例
// ——nullable 欄位用 `ALTER TABLE ADD COLUMN` 就地補,既有資料原封不動。
// 指紋是手寫常數,不動它就不會進入 wipe 路徑。本測試就是那條保證的證據。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
  });
  tearDown(() async => db.close());

  Future<List<String>> columns() async {
    final info = await db
        .customSelect("PRAGMA table_info('price_alert')")
        .get();
    return info.map((r) => r.read<String>('name')).toList();
  }

  /// 重建成**舊** schema(無 managed_by),模擬升級前的 live DB
  Future<void> downgradeToOldSchema() async {
    await db.customStatement('DROP TABLE price_alert');
    await db.customStatement('''
      CREATE TABLE price_alert (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        symbol TEXT NOT NULL REFERENCES stock_master (symbol) ON DELETE CASCADE,
        alert_type TEXT NOT NULL,
        target_value REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)),
        triggered_at INTEGER NULL,
        note TEXT NULL,
        created_at INTEGER NOT NULL DEFAULT (unixepoch())
      )
    ''');
  }

  test('新安裝直接有 managed_by 欄', () async {
    expect(await columns(), contains('managed_by'));
  });

  test('🚨 既有 DB 升級:補欄且一列不少(使用者最在意的)', () async {
    await downgradeToOldSchema();
    await db.customStatement(
      'INSERT INTO price_alert (symbol, alert_type, target_value, note) '
      "VALUES ('2330', 'BELOW', 1150.5, '手動設的關鍵支撐')",
    );
    expect(await columns(), isNot(contains('managed_by')));

    await db.ensurePriceAlertManagedByColumn();

    expect(await columns(), contains('managed_by'));
    final rows = await db.customSelect('SELECT * FROM price_alert').get();
    expect(rows, hasLength(1), reason: '既有提醒必須完整保留');
    expect(rows.single.read<double>('target_value'), 1150.5);
    expect(rows.single.read<String?>('note'), '手動設的關鍵支撐');
    expect(
      rows.single.read<String?>('managed_by'),
      isNull,
      reason: '升級前既存的提醒一律視為手動——自動流程不得回頭改寫它們',
    );
  });

  test('重跑安全(idempotent)——每次開 app 都會執行', () async {
    await downgradeToOldSchema();
    await db.customStatement(
      'INSERT INTO price_alert (symbol, alert_type, target_value) '
      "VALUES ('2330', 'BELOW', 1150.5)",
    );
    await db.ensurePriceAlertManagedByColumn();
    await db.ensurePriceAlertManagedByColumn();
    await db.ensurePriceAlertManagedByColumn();

    final rows = await db.customSelect('SELECT * FROM price_alert').get();
    expect(rows, hasLength(1), reason: '重跑不得複製或清空資料');
  });

  test('managed_by 可寫入並讀回(Drift 欄位真的接上)', () async {
    await db
        .into(db.priceAlert)
        .insert(
          PriceAlertCompanion.insert(
            symbol: '2330',
            alertType: AlertParams.typeBelow,
            targetValue: 1150.5,
            managedBy: const Value(AlertParams.managedByTrailingMa),
          ),
        );
    final row = await db.customSelect('SELECT * FROM price_alert').getSingle();
    expect(row.read<String?>('managed_by'), AlertParams.managedByTrailingMa);
  });
}

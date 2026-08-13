// monthly_revenue.ytd_yoy_growth 的 ALTER 升級路徑(2026-08-13)
//
// monthly_revenue 不在 fingerprint 白名單——但 bump 指紋會 wipe 全部
// 非白名單表(含 58.7 萬列價格,重抓要燒掉數天 FinMind 配額),所以加欄
// 一律走 beforeOpen 的 idempotent ALTER(前例:daily_institutional 的
// dealer_self_net)。這條測試模擬真實升級:帶舊 schema+資料的 DB 被
// 新版 app 開啟。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mr_ytd_col_test');
    dbFile = File('${tempDir.path}/mr_test.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('🚨 舊 DB(無 ytd_yoy_growth 欄)開啟後補欄,既有營收資料保留', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    await db1.customStatement(
      'ALTER TABLE monthly_revenue DROP COLUMN ytd_yoy_growth',
    );
    await db1.customStatement(
      "INSERT INTO stock_master (symbol, name, market, is_active, updated_at) "
      "VALUES ('2330', '台積電', 'TWSE', 1, 1754000000)",
    );
    await db1.customStatement(
      "INSERT INTO monthly_revenue (symbol, date, revenue_year, revenue_month, revenue) "
      "VALUES ('2330', 1754000000, 2026, 7, 250000000)",
    );
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final rows = await db2
        .customSelect(
          "SELECT symbol, revenue, ytd_yoy_growth FROM monthly_revenue",
        )
        .get();
    expect(rows, hasLength(1), reason: '既有營收列必須保留');
    expect(rows.single.read<double>('revenue'), 250000000);
    expect(
      rows.single.readNullable<double>('ytd_yoy_growth'),
      isNull,
      reason: '補欄後舊列為 null——歷史月份的累計值本來就沒抓過',
    );

    final ddl =
        (await db2
                .customSelect(
                  "SELECT sql FROM sqlite_master WHERE name = 'monthly_revenue'",
                )
                .getSingle())
            .read<String>('sql');
    expect(ddl.replaceAll('"', ''), contains('ytd_yoy_growth'));
    await db2.close();
  });
}

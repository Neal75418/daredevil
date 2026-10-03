// dividend_distribution 補 close_before／reference_price、dividend_month_ledger
// 補 prices_recorded 的 ALTER 升級路徑（2026-10-03）
//
// bump fingerprint 會 wipe 全部行情表，所以加欄走 beforeOpen 的 idempotent
// ALTER。這條測試模擬真實升級：帶舊 schema＋資料的 DB 被新版開啟。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dividend_price_cols');
    dbFile = File('${tempDir.path}/db.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('🚨 舊 DB 開啟後補欄：配發列保留、價格為 null；完成紀錄保留、prices_recorded 為 false', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db1.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
      ),
    ]);
    await db1.completeDividendMonth(
      market: 'TWSE',
      month: const CalendarMonth(2025, 9),
      rows: const [],
      expectedKeys: {('2330', DateTime(2025, 9, 16))},
      listedRows: 1,
      skippedSymbols: const {},
      completedAt: DateTime(2026, 9, 30),
    );
    for (final column in ['close_before', 'reference_price']) {
      await db1.customStatement(
        'ALTER TABLE dividend_distribution DROP COLUMN $column',
      );
    }
    await db1.customStatement(
      'ALTER TABLE dividend_month_ledger DROP COLUMN prices_recorded',
    );
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final row = (await db2.getDividendDistributions('2330')).single;
    expect(row.cashDividend, 5);
    expect(row.closeBefore, isNull);
    expect(row.referencePrice, isNull);
    final ledger = (await db2.getDividendMonthLedgerEntries()).single;
    expect(ledger.pricesRecorded, isFalse, reason: '舊完成紀錄要讓回補重開補價');
    // 讀不到的欄位 drift 也回 null，要寫入再讀回才證明欄位真的補上了
    await db2.updateDividendDistributionPrices([
      (
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        closeBefore: 1000.0,
        referencePrice: 995.0,
      ),
    ]);
    final updated = (await db2.getDividendDistributions('2330')).single;
    expect((updated.closeBefore, updated.referencePrice), (1000.0, 995.0));
    await db2.close();
  });
}

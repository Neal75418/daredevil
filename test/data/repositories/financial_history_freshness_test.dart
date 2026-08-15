// 財報新鮮度檢查必須看「歷史完整性」而非只看最新一季(2026-08-16)
//
// **這是 2026-08-16 接入免費資產負債表時引入的迴歸**:官方端點把最新一季
// 寫進全市場後,`_syncFinancialStatement` 的檢查
//   `latestDate >= expectedQuarter → return 0`
// 對每一檔都成立,於是 FinMind 的 per-symbol 路徑**永遠不再執行**——而那是
// **歷史 Equity 的唯一來源**(官方端點只給當季)。
//
// 實測正式 DB:有 Q2 的 1,830 檔中,**529 檔缺 Q1**。ROE 的分母是「當期與
// 去年同期的平均權益」,這些股票的 ROE 算不出來,而且再也補不到——正好
// 打到這次改動想解決的那批回填佇列。
//
// 修法:最新一季存在**且**歷史季數足夠才跳過。季數門檻取
// [ApiConfig.financialHistoryMinQuarters](5 = 當期 + 前四季),對齊
// `_findEquityAboutOneYearBefore` 需要的「一年前那季」。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '1101', name: '台泥', market: 'TWSE'),
    ]);
  });
  tearDown(() async => db.close());

  Future<void> writeEquity(String symbol, List<DateTime> dates) async {
    await db.insertFinancialData([
      for (final d in dates)
        FinancialDataCompanion.insert(
          symbol: symbol,
          date: d,
          statementType: 'BALANCE',
          dataType: 'Equity',
          value: const Value(1000),
        ),
    ]);
  }

  test('🚨 只有最新一季時,季數不足(必須繼續回補歷史)', () async {
    // 這正是官方端點寫入後的狀態:全市場都有 Q2,但歷史是空的
    await writeEquity('2330', [DateTime(2026, 6, 30)]);
    final n = await db.countFinancialDataQuarters('2330', 'BALANCE');
    expect(n, 1);
    expect(
      n >= ApiConfig.financialHistoryMinQuarters,
      isFalse,
      reason: 'ROE 需要去年同期的權益,只有當季時不能算「已完整」',
    );
  });

  test('季數足夠時回報足夠(才可以跳過 FinMind)', () async {
    await writeEquity('2330', [
      DateTime(2026, 6, 30),
      DateTime(2026, 3, 31),
      DateTime(2025, 12, 31),
      DateTime(2025, 9, 30),
      DateTime(2025, 6, 30),
    ]);
    final n = await db.countFinancialDataQuarters('2330', 'BALANCE');
    expect(n, 5);
    expect(n >= ApiConfig.financialHistoryMinQuarters, isTrue);
  });

  test('只數該 statementType 的季別', () async {
    await writeEquity('2330', [DateTime(2026, 6, 30), DateTime(2026, 3, 31)]);
    await db.insertFinancialData([
      for (final d in [
        DateTime(2025, 12, 31),
        DateTime(2025, 9, 30),
        DateTime(2025, 6, 30),
      ])
        FinancialDataCompanion.insert(
          symbol: '2330',
          date: d,
          statementType: 'INCOME', // 不同 statementType
          dataType: 'EPS',
          value: const Value(1),
        ),
    ]);
    expect(await db.countFinancialDataQuarters('2330', 'BALANCE'), 2);
    expect(await db.countFinancialDataQuarters('2330', 'INCOME'), 3);
  });

  test('同一季多個 data_type 只算一季', () async {
    final d = DateTime(2026, 6, 30);
    await db.insertFinancialData([
      for (final t in ['Equity', 'TotalAssets', 'Liabilities'])
        FinancialDataCompanion.insert(
          symbol: '1101',
          date: d,
          statementType: 'BALANCE',
          dataType: t,
          value: const Value(1),
        ),
    ]);
    expect(await db.countFinancialDataQuarters('1101', 'BALANCE'), 1);
  });

  test('無資料回 0', () async {
    expect(await db.countFinancialDataQuarters('9999', 'BALANCE'), 0);
  });
}

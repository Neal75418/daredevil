// ROE 計算口徑(2026-08-15 數值稽核)
//
// 舊口徑:單季淨利 × 4 ÷ **期末**權益。問題是它拿去比 15% 這個**年度**
// 門檻,而且季節性強的公司(Q4 旺季/Q1 淡季)會系統性誤判。
// 全市場實測:舊法通過 405 檔、標準法 339 檔,其中 114 檔只有舊法會過
// (佔實際觸發量 28%),另 48 檔被舊法漏掉。
//
// 新口徑:近四季淨利合計 ÷ 平均權益((期末+去年同季期末)/2)。
// 資料不齊(缺季、缺去年權益)寧可**不產生該季 ROE**,不用錯的公式頂替。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  Future<void> put(
    String symbol,
    DateTime date,
    String statementType,
    String dataType,
    double value,
  ) => db.insertFinancialData([
    FinancialDataCompanion.insert(
      symbol: symbol,
      date: date,
      statementType: statementType,
      dataType: dataType,
      value: Value(value),
    ),
  ]);

  /// 塞滿四季淨利 + 兩個時點的權益
  Future<void> seedFull({
    required String symbol,
    required List<double> quarterlyNet, // 由舊到新,長度 4
    required double equityNow,
    required double equityYearAgo,
  }) async {
    const dates = [
      // 2025Q3, Q4, 2026Q1, Q2
      [2025, 9, 30],
      [2025, 12, 31],
      [2026, 3, 31],
      [2026, 6, 30],
    ];
    for (var i = 0; i < 4; i++) {
      await put(
        symbol,
        DateTime(dates[i][0], dates[i][1], dates[i][2]),
        'INCOME',
        'IncomeAfterTaxes',
        quarterlyNet[i],
      );
    }
    await put(symbol, DateTime(2026, 6, 30), 'BALANCE', 'Equity', equityNow);
    await put(
      symbol,
      DateTime(2025, 6, 30),
      'BALANCE',
      'Equity',
      equityYearAgo,
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '1111', name: '測試', market: 'TWSE'),
    ]);
  });

  tearDown(() async => db.close());

  test('🚨 ROE = 近四季淨利 ÷ 平均權益(非單季×4÷期末權益)', () async {
    // 四季各 10,合計 40;權益 期末 200 / 去年同期 200 → 平均 200
    // 標準法:40/200 = 20.0%   舊法:10×4/200 = 20.0%(此例兩者相同)
    // 改用不等權益凸顯差異:期末 200、去年 100 → 平均 150 → 40/150 = 26.67%
    await seedFull(
      symbol: '1111',
      quarterlyNet: [10, 10, 10, 10],
      equityNow: 200,
      equityYearAgo: 100,
    );
    final roe = await db.getROEHistoryBatch(['1111']);
    expect(roe['1111'], isNotNull);
    expect(
      roe['1111']!.first.value,
      closeTo(26.667, 0.01),
      reason: '40 ÷ ((200+100)/2) × 100 = 26.67;舊法會得 10×4÷200 = 20',
    );
  });

  test('🚨 季節性公司:單季×4 會嚴重高估(這正是舊口徑的病)', () async {
    // Q4 旺季 40、其餘各 5 → TTM = 55;權益 500(前後同)
    // 標準法:55/500 = 11.0%(不到 15% 門檻)
    // 舊法(以 Q4 當最新季):40×4/500 = 32%(遠超門檻)= 假優等生
    await seedFull(
      symbol: '1111',
      quarterlyNet: [5, 5, 5, 40], // 最新季是旺季
      equityNow: 500,
      equityYearAgo: 500,
    );
    final roe = await db.getROEHistoryBatch(['1111']);
    expect(
      roe['1111']!.first.value,
      closeTo(11.0, 0.01),
      reason: 'TTM 55 ÷ 500;舊法會算出 32% 讓它假裝是高 ROE 股',
    );
  });

  test('🚨 四季不齊 → 不產生該季 ROE(寧可少報不報錯)', () async {
    // 只有兩季淨利
    await put('1111', DateTime(2026, 6, 30), 'INCOME', 'IncomeAfterTaxes', 10);
    await put('1111', DateTime(2026, 3, 31), 'INCOME', 'IncomeAfterTaxes', 10);
    await put('1111', DateTime(2026, 6, 30), 'BALANCE', 'Equity', 200);
    await put('1111', DateTime(2025, 6, 30), 'BALANCE', 'Equity', 200);
    final roe = await db.getROEHistoryBatch(['1111']);
    expect(roe['1111'] ?? const [], isEmpty, reason: '缺季時用可得資料湊 ×4 正是舊口徑的錯誤');
  });

  test('缺去年同期權益 → 退回期末權益(不放棄該季,但不得用錯的分子)', () async {
    for (final d in [
      [2025, 9, 30],
      [2025, 12, 31],
      [2026, 3, 31],
      [2026, 6, 30],
    ]) {
      await put(
        '1111',
        DateTime(d[0], d[1], d[2]),
        'INCOME',
        'IncomeAfterTaxes',
        10,
      );
    }
    await put('1111', DateTime(2026, 6, 30), 'BALANCE', 'Equity', 200);
    final roe = await db.getROEHistoryBatch(['1111']);
    expect(
      roe['1111']!.first.value,
      closeTo(20.0, 0.01),
      reason: 'TTM 40 ÷ 期末 200 = 20%;分子仍是四季合計,不是單季×4',
    );
  });

  test('🚨 跨檔隔離:別檔的去年權益不得被借用(per-symbol 分組重構的守門)', () async {
    // 2026-08-29 效能重構:年比查找從「全體 equity 線性掃」改「先按
    // symbol 分組」——分組錯檔的症狀正是這條:A 檔缺去年權益,B 檔在
    // 同一時點有一筆巨大權益;A 必須走期末權益 fallback,不得借 B 的。
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2222', name: '別檔', market: 'TWSE'),
    ]);
    // A(1111):四季淨利齊、只有期末權益
    await seedFull(
      symbol: '1111',
      quarterlyNet: [10, 10, 10, 10],
      equityNow: 400,
      equityYearAgo: 0, // 會被「權益 ≤ 0 跳過」濾掉 → 等同缺去年權益
    );
    // B(2222):在 A 的去年同季時點有一筆巨大權益——借用會讓 A 的
    // avgEquity 變 (400+8000)/2 = 4200,ROE 從 10% 崩成 0.95%
    await put('2222', DateTime(2025, 6, 30), 'BALANCE', 'Equity', 8000);

    final roe = await db.getROEHistoryBatch(['1111', '2222']);
    final a = roe['1111']!.single;
    expect(a.value, closeTo(40 / 400 * 100, 0.001), reason: '期末權益 fallback');
  });

  test('權益為 0 或負 → 跳過(不除零、不產生負 ROE 噪音)', () async {
    await seedFull(
      symbol: '1111',
      quarterlyNet: [10, 10, 10, 10],
      equityNow: 0,
      equityYearAgo: 0,
    );
    final roe = await db.getROEHistoryBatch(['1111']);
    expect(roe['1111'] ?? const [], isEmpty);
  });
}

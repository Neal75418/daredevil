// 全市場財報解析(2026-08-16)
//
// **為什麼要接**:財報是 FinMind 額度的唯一瓶頸——逐檔、且損益表與資產
// 負債表各一次。129 檔待回填就是 258 次呼叫,佔小時額度 43%,實測當天
// 因額度保留只跑了 10 檔(日誌:「財報回填縮量: 上市 129 檔…已用 142/600」)。
//
// 而 TWSE/TPEx 有免費的全市場端點:t187ap06(綜合損益表)、t187ap07
// (資產負債表),各六業別,合計上市 975 + 上櫃 863 筆。
//
// **範圍只到資產負債表**(2026-08-16 切換來源時發現的兩個陷阱):
//   1. **單位差 1000 倍**:FinMind Equity 299,322,066,000(元)vs
//      TWSE 權益總計 299,322,066(千元)。
//   2. **損益表是年度累計、FinMind 是單季**:實測台泥 GrossProfit
//      Q1 6,208,390 + Q2 6,783,334 = 12,991,724 千元,恰為 TWSE 的
//      「營業毛利」。把累計值混進以單季為語意的 financial_data,會讓
//      2026-08-16 才改成同季 YoY 的 EPS 規則靜默錯亂(數字看起來都合理)。
//      EPS 更不能單純相減——它用加權平均股數計算。
//   故損益表維持 FinMind,本 model 只處理 BALANCE。
//
// **只寫有消費者的兩個欄位**(2026-08-16 grep 實證):
//   Equity(2 處,ROE 的分母)、TotalAssets(1 處)
// 其餘欄位(CashAndCashEquivalents / Liabilities / OrdinaryShare /
// TotalLiabilitiesEquity 等十餘個)全是 0 處消費者。它們與 margin 那組
// 「已備料未消費」不同——**這是新增**,而且免費端點隨時可再抓,不寫沒有
// 不可逆的損失,寫了只是讓已有 99 萬列的表繼續膨脹。
//
// **日期**:ROC 年 + 季別 → 季末日,必須與 FinMind 既有資料同格式,
// 否則 ROE 的近四季合計與 EPS 的去年同季比對會撈不到。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/twse/market_wide_financial.dart';

void main() {
  // 2026-08-16 從 live API 取回的實際列
  final incomeRow = <String, dynamic>{
    '出表日期': '1150815',
    '年度': '115',
    '季別': '2',
    '公司代號': '1101',
    '公司名稱': '台泥',
    '營業收入': '61292085.00',
    '營業毛利（毛損）淨額': '12991724.00',
    '本期淨利（淨損）': '4569799.00',
    '基本每股盈餘（元）': '0.38',
  };

  final balanceRow = <String, dynamic>{
    '出表日期': '1150815',
    '年度': '115',
    '季別': '2',
    '公司代號': '1101',
    '公司名稱': '台泥',
    '資產總計': '596016531.00',
    '負債總計': '296694465.00',
    '權益總計': '299322066.00',
    '每股參考淨值': '30.86',
  };

  group('日期換算', () {
    test('🚨 ROC 年季 → 季末日,必須與 FinMind 既有資料同格式', () {
      // financial_data 實際存的是季末日(實測 2392:2026-06-30、2026-03-31)
      final rows = MarketWideFinancial.parseBalance(balanceRow);
      expect(rows.first.date, DateTime(2026, 6, 30));
    });

    test('四季的季末日各自正確', () {
      for (final (q, expected) in [
        ('1', DateTime(2026, 3, 31)),
        ('2', DateTime(2026, 6, 30)),
        ('3', DateTime(2026, 9, 30)),
        ('4', DateTime(2026, 12, 31)),
      ]) {
        final r = MarketWideFinancial.parseBalance({...balanceRow, '季別': q});
        expect(r.first.date, expected, reason: 'Q$q');
      }
    });
  });

  group('資產負債表', () {
    test('🚨 單位必須轉成「元」——與 FinMind 既有資料一致', () {
      // 實測 DB(FinMind 來源):1101 的 Equity = 299,322,066,000 元
      // 而 TWSE 給的是 299,322,066 千元 —— 差 1000 倍。混寫會讓 ROE
      // 的分母差三個數量級,而且不會有任何錯誤訊息
      final rows = MarketWideFinancial.parseBalance(balanceRow);
      final byType = {for (final r in rows) r.dataType: r.value};
      expect(byType['Equity'], 299322066000.0, reason: 'ROE 的分母,單位=元');
      expect(byType['TotalAssets'], 596016531000.0);
    });

    test('只取有消費者的兩個欄位', () {
      final rows = MarketWideFinancial.parseBalance(balanceRow);
      expect({for (final r in rows) r.dataType}, {'Equity', 'TotalAssets'});
      expect(rows.every((r) => r.statementType == 'BALANCE'), isTrue);
      expect(rows.first.symbol, '1101');
    });

    test('🚨 Equity 取「權益總計」而非「歸屬於母公司業主之權益合計」', () {
      // 兩者在有非控制權益的公司會差很多(台泥 299,322,066 vs 237,429,168),
      // 而 FinMind 的 Equity 是合併總額——取錯會讓 ROE 系統性偏高
      final r = MarketWideFinancial.parseBalance({
        ...balanceRow,
        '歸屬於母公司業主之權益合計': '237429168.00',
      });
      expect(r.firstWhere((e) => e.dataType == 'Equity').value, 299322066000.0);
    });
  });

  group('防禦', () {
    test('代號為空 → 回空清單', () {
      expect(
        MarketWideFinancial.parseBalance({...balanceRow, '公司代號': ''}),
        isEmpty,
      );
    });

    test('年度或季別無法解析 → 回空清單', () {
      expect(
        MarketWideFinancial.parseBalance({...balanceRow, '年度': ''}),
        isEmpty,
      );
      expect(
        MarketWideFinancial.parseBalance({...balanceRow, '季別': 'X'}),
        isEmpty,
      );
    });

    test('🚨 數值缺失的欄位整筆略過,不寫 0', () {
      // 0 與「未申報」在權益/EPS 上語意完全不同(同 per=0 的教訓)
      final rows = MarketWideFinancial.parseBalance({
        ...balanceRow,
        '權益總計': '',
      });
      expect(rows.map((e) => e.dataType), ['TotalAssets']);
    });

    test('金融業的空白列(全欄位空)→ 回空清單', () {
      expect(
        MarketWideFinancial.parseBalance({
          '公司代號': '2801',
          '年度': '115',
          '季別': '2',
          '資產總計': '',
          '權益總計': '',
        }),
        isEmpty,
      );
    });
  });

  // ⚠️ 刻意不提供 parseIncome。這個測試用實測數字釘住原因,免得未來
  // 有人看到「損益表端點也是免費的」就順手接上去。
  test('🚨 文件:TWSE 損益表是年度累計,不可寫進以單季為語意的 financial_data', () {
    // 2026-08-16 實測(單位:千元)
    const finMindQ1GrossProfit = 6208390.0; // DB: 6,208,390,000 元
    const finMindQ2GrossProfit = 6783334.0; // DB: 6,783,334,000 元
    final twseGrossProfit = double.parse(incomeRow['營業毛利（毛損）淨額'] as String);

    expect(
      finMindQ1GrossProfit + finMindQ2GrossProfit,
      twseGrossProfit,
      reason: 'TWSE 的「營業毛利」= FinMind Q1 + Q2,證明它是年度累計',
    );

    // EPS 更不能相減:它用加權平均股數計算,Q1 0.1 + Q2 0.29 = 0.39
    // 而 TWSE 給 0.38 —— 差額不是誤差,是算法不同
    expect(
      double.parse(incomeRow['基本每股盈餘（元）'] as String),
      isNot(0.39),
      reason: 'EPS 的累計 ≠ 各季相加,所以也不能相減還原單季',
    );
  });

  test('🚨 上櫃用 SecuritiesCompanyCode 當代號欄(TWSE 用「公司代號」)', () {
    // 2026-08-16 實測:TPEx 的 mopsfin_t187ap07_O_* 代號欄名不同,
    // 數值欄名則相同。只認中文欄名的話上櫃 857 筆會全部解析失敗
    // ——實跑只出 4 筆。既有的 QuarterlyReportEntry 早已處理這個差異。
    final tpexRow = <String, dynamic>{
      'Date': '1150815',
      '年度': '115',
      '季別': '2',
      'SecuritiesCompanyCode': '1240',
      'CompanyName': '茂生農經',
      '資產總計': '2315123.00',
      '權益總計': '1200000.00',
    };
    final rows = MarketWideFinancial.parseBalance(tpexRow);
    expect(rows, hasLength(2));
    expect(rows.first.symbol, '1240');
    expect(
      rows.firstWhere((e) => e.dataType == 'TotalAssets').value,
      2315123000.0,
    );
  });
}

// MI_QFIIS 外資及陸資持股(2026-08-16)
//
// **為什麼要接這個端點**:外資持股比例原本只靠 FinMind 逐檔呼叫,而
// update_service 只同步「自選 + 熱門」(約 48 檔)。實測 2026-08-14:
// 上市候選 344 檔裡只有 82 檔有資料(24%),上櫃因為有輪替機制反而是
// 116/116(100%)。結果是**上櫃股拿到外資加分的機會是上市股的 4 倍**
// ——那不是市場事實,是資料缺口造成的系統性偏差。
//
// MI_QFIIS 一次回全市場 1,359 筆、免費、支援歷史日期,且欄位與既有
// `shareholding` 表一一對應,零 schema 改動。
//
// **解析的坑**:同一個回應裡欄位型別不一致(2026-08-16 對 live API 實測)
//   [3][4][5] 股數 → **帶千分位的字串** "2,034,140,000"
//   [6][7]   比率 → **已經是 double** 94.86
//   [8][9]   上限 → **字串** "100.00"
// 全部當字串解析會讓 double 欄位變成 "94.86" 再 parse(可行但多繞),
// 全部當 double 則字串欄位直接爆。逐欄按實際型別處理。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/twse/twse_foreign_shareholding.dart';

void main() {
  // 2026-08-16 從 live API 取回的實際列(未經修改)
  final liveRow = [
    '00400A',
    '主動國泰動能高息',
    'TW00000400A3',
    '2,034,140,000',
    '1,929,695,160',
    '104,444,840',
    94.86,
    5.13,
    '100.00',
    '100.00',
    '',
    '115/04/10',
  ];

  final date = DateTime(2026, 8, 14);

  test('解析 live API 的實際列', () {
    final r = TwseForeignShareholding.fromRow(liveRow, date);
    expect(r, isNotNull);
    expect(r!.symbol, '00400A');
    expect(r.sharesIssued, 2034140000, reason: '千分位字串要還原');
    expect(r.foreignRemainingShares, 1929695160);
    expect(r.foreignSharesRatio, 5.13, reason: '這欄 API 直接給 double');
    expect(r.foreignUpperLimitRatio, 100.0, reason: '這欄是字串');
  });

  test('🚨 持股比率取的是「全體外資及陸資持股比率」而非「尚可投資比率」', () {
    // [6] 尚可投資比率 94.86 與 [7] 持股比率 5.13 相加約 100——取錯欄位
    // 會讓幾乎每檔都看起來像「外資持股 95%」,方向完全相反
    final r = TwseForeignShareholding.fromRow(liveRow, date)!;
    expect(r.foreignSharesRatio, 5.13);
    expect(r.foreignSharesRatio, isNot(94.86));
  });

  test('欄位數不足回 null,不拋例外', () {
    expect(TwseForeignShareholding.fromRow(['2330', '台積電'], date), isNull);
  });

  test('代號為空回 null', () {
    final bad = List<dynamic>.from(liveRow)..[0] = '';
    expect(TwseForeignShareholding.fromRow(bad, date), isNull);
  });

  test('數值欄位無法解析時落 null,不填 0', () {
    // 0 與「未知」在持股比率上語意完全不同(同 per=0 的教訓)
    final bad = List<dynamic>.from(liveRow)
      ..[3] = '--'
      ..[7] = '';
    final r = TwseForeignShareholding.fromRow(bad, date);
    expect(r, isNotNull);
    expect(r!.sharesIssued, isNull);
    expect(r.foreignSharesRatio, isNull);
  });

  test('整數型別的比率也要接受(API 偶爾回整數)', () {
    final intRatio = List<dynamic>.from(liveRow)..[7] = 5;
    expect(
      TwseForeignShareholding.fromRow(intRatio, date)!.foreignSharesRatio,
      5.0,
    );
  });
}

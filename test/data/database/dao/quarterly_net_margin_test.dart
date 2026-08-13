// 季報淨利率(2026-08-13):netIncome/revenue 現成兩欄相除,顯示即消費
// (毛利率/營益率刻意不補欄——momentum5d 教訓:沒有消費者的資料管線
// 會爛著白跑;等有規則要吃利潤率再說)
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/dao/quarterly_report_dao.dart';

QuarterlyReportOverviewRow row({double? net, double? rev}) =>
    QuarterlyReportOverviewRow(
      symbol: '5289',
      name: '宜鼎',
      market: 'TWSE',
      eps: 166.45,
      netIncome: net,
      revenue: rev,
      priorEps: 5.70,
    );

void main() {
  test('🚨 淨利率 = 淨利/營收(同為千元,單位消掉)', () {
    expect(
      row(net: 15883392, rev: 35626019).netMarginPct,
      closeTo(44.58, 0.01),
    );
  });

  test('虧損照實為負', () {
    expect(row(net: -500, rev: 10000).netMarginPct, closeTo(-5.0, 0.01));
  });

  test('缺任一值或營收≤0 → null(不除零、不假 0)', () {
    expect(row(net: null, rev: 100).netMarginPct, isNull);
    expect(row(net: 100, rev: null).netMarginPct, isNull);
    expect(row(net: 100, rev: 0).netMarginPct, isNull);
  });
}

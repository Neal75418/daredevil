// 月營收表的單位換算(2026-08-29 領域稽核 HIGH)
//
// `FinMindRevenue.revenue` 的單位是**千元**——模型自己的註解寫死了這個慣例
// (「本欄位…一律以『千元』為慣例」,FinMind 來源值會 ÷1000 對齊)。
//
// `_formatRevenue` 的三個分支只有中間那個算錯:
//   R >= 100000 → R/100000 億   ✓ (千元 → 億元 要 ÷100,000)
//   R >= 10000  → R/10000  萬   ✗ (千元 → 萬元 應 ÷10,少了 1000 倍)
//   R <  10000  → R        千   ✓
//
// 一眼可見的破綻:R 從 99,999 走到 100,000,畫面從「10.0萬」跳成「1.0億」
// ——差一單位、跳 1000 倍。實測 1,976 檔中有 465 檔的最新月營收落在壞掉的
// 那個區間(例:1721 最新月 99,976 千元 ≈ 1 億,畫面顯示「10.0萬」)。
import 'package:daredevil/data/models/finmind/revenue.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/revenue_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  /// 單筆營收（千元）渲染後,取出表格裡出現的所有文字
  Future<List<String>> render(
    WidgetTester tester,
    double revenueInThousands,
  ) async {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      buildTestApp(
        RevenueTable(
          revenues: [
            FinMindRevenue(
              stockId: '1721',
              date: '2026-07-01',
              revenue: revenueInThousands,
              revenueMonth: 7,
              revenueYear: 2026,
            ),
          ],
          showROCYear: false,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
  }

  // buildTestApp 不載入翻譯,`.tr()` 回傳原始 key——與本 repo 其他 widget
  // 測試的慣例一致(見 revenue_overview_screen_test)。斷言連 key 一起比,
  // 才能同時釘住「數值」與「選了哪個單位分支」。
  const kBillion = 'stockDetail.unitBillion';
  const kTenThousand = 'stockDetail.unitTenThousand';
  const kThousand = 'stockDetail.unitThousand';

  test('前提:欄位單位是千元(模型註解的慣例)', () {
    // 這條不是重言式——它釘住本檔所有斷言賴以成立的前提。
    // 若日後有人把欄位改成「元」,這裡會提醒要一併改 _formatRevenue。
    final r = FinMindRevenue.fromJson({
      'stock_id': '2330',
      'date': '2026-07-01',
      'revenue': 467580548000, // FinMind 給的是「元」
      'revenue_month': 7,
      'revenue_year': 2026,
    });
    expect(r.revenue, 467580548); // 存成千元
  });

  testWidgets('億 分支正確(對照組——證明不是三個分支都壞)', (tester) async {
    // 467,580,548 千元 = 4,675.8 億元
    final texts = await render(tester, 467580548);
    expect(texts, contains('4675.8$kBillion'));
  });

  testWidgets('🚨 萬 分支不得小 1000 倍', (tester) async {
    // 99,976 千元 = 99,976,000 元 = 9,997.6 萬元
    final texts = await render(tester, 99976);
    expect(
      texts,
      contains('9997.6$kTenThousand'),
      reason: '舊碼除以 10000 而非 10,畫面顯示「10.0萬」——把 1 億講成 10 萬',
    );
  });

  testWidgets('🚨 億/萬 交界處不得跳 1000 倍', (tester) async {
    // 交界兩側只差 1 千元,顯示值必須連續:
    //   99,999 千元 = 9,999.9 萬
    //  100,000 千元 =    1.0 億 = 10,000 萬
    // 差 0.1 萬 → 連續。舊碼在此處是「10.0萬 → 1.0億」,跳 1000 倍
    // ——這是不必查任何資料就看得出來的破綻。
    final justUnder = await render(tester, 99999);
    final justOver = await render(tester, 100000);
    expect(justUnder, contains('9999.9$kTenThousand'));
    expect(justOver, contains('1.0$kBillion'));
  });

  testWidgets('千 分支照舊(未達 1000 萬者仍以千元表示)', (tester) async {
    final texts = await render(tester, 9999);
    expect(texts, contains('9999$kThousand'));
  });
}

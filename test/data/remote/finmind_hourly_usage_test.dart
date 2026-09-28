// FinMind 真實用量曾經沒有公開讀取點——只有配額用完時才會從例外訊息看到
// （2026-07-27 起由 FinMindClient.hourlyUsage 提供）
//
// 當時 update_service.dart 的註解（2026-07-26）：
//   「真實用量在 ApiBudgetTracker（per-vendor、sliding 1hr、只掛
//     FinMindClient）。但它目前**沒有公開讀取點**，內部算出的 used 只在
//     配額用完時出現在例外訊息裡——等看到已經來不及；且 tracker 未注入
//     UpdateService。待接出來後改印真值。」
//
// 同一段還記著當時的實測：更新日誌「報 94 calls，真實 API 呼叫約 2 次，
// **高報 47 倍**」。高報的方向特別有害——會讓人誤以為配額已緊而不敢調高
// 上櫃相關的 maxSyncCount。
//
// 2026-07-27 追查上櫃財報覆蓋率（EPS 上市 372 檔 vs 上櫃 14 檔）時，我連續
// 三次對「誰在吃 FinMind 額度」給出錯誤估算：
//   ① 說上櫃估值/營收走 FinMind 逐檔 → 實際走 _tpex.getAllValuation()
//      與 _tpex.getAllMonthlyRevenue()，全市場各 1 次
//   ② 據此估「尖峰 500/600、餘裕僅 100」→ 前提整個是錯的
//   ③ 據此建議「上櫃財報配額只能設 50 慢慢回填」→ 為了遷就不存在的壓力
// 實際上 FinMind 唯一的 per-symbol 消耗只有 getFinancialStatements。
//
// 三次都是靜態讀 code 推估。要停止這種錯誤，需要的是**真實數字**，
// 所以把 tracker 的計數接出來。
//
// **回 null 而非 0 是刻意的**：沒有 tracker 時回 0 會被讀成「這輪沒打 API」，
// 那是預設值假裝成量測結果——與本輪修掉的「零訊號股票顯示佐證中等」、
// 「未評分股票宣稱盤整」同一個病。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/api_budget_tracker.dart';
import 'package:daredevil/data/remote/finmind_client.dart';

void main() {
  test('🚨 hourlyUsage 須反映 tracker 的實際計數', () {
    final tracker = ApiBudgetTracker();
    final client = FinMindClient(budgetTracker: tracker);
    addTearDown(client.close);

    for (var i = 0; i < 7; i++) {
      tracker.recordCall(ApiVendor.finMind);
    }

    expect(client.hourlyUsage?.used, 7);
    expect(
      client.hourlyUsage?.budget,
      tracker.budgetFor(ApiVendor.finMind),
      reason: '配額要一起帶出來，否則 used 沒有比較基準',
    );
  });

  test('🚨 沒有 tracker 時回 null，不得回 0（0 會被讀成「這輪沒打 API」）', () {
    final client = FinMindClient();
    addTearDown(client.close);

    expect(client.hourlyUsage, isNull);
  });

  test('對照組：只計 FinMind，其他 vendor 的呼叫不得混入', () {
    final tracker = ApiBudgetTracker();
    final client = FinMindClient(budgetTracker: tracker);
    addTearDown(client.close);

    tracker.recordCall(ApiVendor.finMind);
    tracker.recordCall(ApiVendor.twse);
    tracker.recordCall(ApiVendor.tpex);
    tracker.recordCall(ApiVendor.tdcc);

    expect(
      client.hourlyUsage?.used,
      1,
      reason: 'FinMind 是唯一有硬額度的 vendor（600/hr），混入別家會讓數字失去意義',
    );
  });
}

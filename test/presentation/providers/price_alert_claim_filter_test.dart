import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

/// 收盤路徑只回報「本次真的搶到」的提醒(2026-08-08 三次審查 F-1)。
///
/// 為什麼要有這條:呼叫端(today_provider)會為回傳清單的**每一筆**發
/// 通知。上一輪修復只在迴圈裡 `continue` 跳過 triggeredIds,卻仍回傳
/// 未過濾的原清單——commit 宣稱重複通知已修好,實測仍會重複發。
/// 這條測試直接鎖住「沒搶到的不得出現在回傳值」。
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('🚨 已被別的 process 認領的提醒,claim 回 false(不得再通知)', () async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '3231', name: '緯創', market: 'TWSE'),
    ]);
    final id = await db.createPriceAlert(
      symbol: '3231',
      alertType: 'BELOW',
      targetValue: 180,
    );

    // 模擬盤中 CLI 先搶到
    expect(await db.claimAlertTrigger(id), isTrue);
    // 收盤路徑再來一次 → 必須拿不到,呼叫端才不會重複通知
    expect(await db.claimAlertTrigger(id), isFalse);

    final row = (await db.getAllAlerts()).firstWhere((a) => a.id == id);
    // 2026-08-08 四次審查:認領**不再**寫 isActive——那是使用者意圖欄位。
    // 認領只寫 triggeredAt(機器互斥),送出成功後才由 consumeAlertClaim
    // 消費。這樣「通知失敗要釋放」就不必把 isActive 寫回 true,也就不會
    // 覆蓋使用者在這段期間手動停用的動作。
    expect(row.isActive, isTrue, reason: '認領 ≠ 消費');
    expect(row.triggeredAt, isNotNull, reason: '互斥鍵已寫入,別人搶不到');

    await db.consumeAlertClaim(id, stamp: row.triggeredAt!);
    final consumed = (await db.getAllAlerts()).firstWhere((a) => a.id == id);
    expect(consumed.isActive, isFalse, reason: '送出成功才停用');
  });

  test('未被認領過的提醒 → 搶得到', () async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    final id = await db.createPriceAlert(
      symbol: '2330',
      alertType: 'ABOVE',
      targetValue: 1,
    );
    expect(await db.claimAlertTrigger(id), isTrue);
  });
}

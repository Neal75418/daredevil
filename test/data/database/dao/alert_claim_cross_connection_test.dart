import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

/// 提醒認領的**跨連線**互斥(2026-08-08 五次審查)。
///
/// **為什麼既有測試不夠**:`user_dao_alert_claim_test` 與
/// `price_alert_claim_filter_test` 都是「單一記憶體 DB 上的序列呼叫」——
/// 它們驗證的是條件式 UPDATE 的邏輯,**證明不了跨 process 的任何事**。
/// 而真實情況是 app 內輪詢與 launchd CLI 跑在兩個獨立 process、共用同一
/// 個 SQLite 檔案。整套去重協定的正確性完全押在那一句
/// `WHERE id = ? AND triggered_at IS NULL` 的原子性上,卻從未被真的併發
/// 執行過。
///
/// 這裡開**兩個各自獨立的 `AppDatabase.forToolFile`**(不同連線、同一個
/// 檔案),重現真實拓撲。
void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dd_claim_xproc');
    dbPath = '${tmp.path}/afterclose.sqlite';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> seedWith(AppDatabase db) async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '3231', name: '緯創', market: 'TWSE'),
    ]);
    return db.createPriceAlert(
      symbol: '3231',
      alertType: 'BELOW',
      targetValue: 179.95,
    );
  }

  test('🚨 兩條連線同時認領同一筆 → 只有一個搶得到', () async {
    final a = AppDatabase.forToolFile(dbPath);
    final id = await seedWith(a);
    final b = AppDatabase.forToolFile(dbPath);
    addTearDown(() async {
      await a.close();
      await b.close();
    });

    // 不 await 個別呼叫,讓兩者真的併發
    final results = await Future.wait([
      a.claimAlertTrigger(id),
      b.claimAlertTrigger(id),
    ]);

    expect(
      results.where((r) => r).length,
      1,
      reason:
          '恰好一個 process 取得通知權。若兩個都 true,使用者會收到重複警報'
          '(一個系統通知 + 一個 app 通知);若兩個都 false,提醒無聲消失。',
    );
  });

  test('🚨 一方釋放後,另一方才搶得到——且不會抹掉對方的認領', () async {
    final a = AppDatabase.forToolFile(dbPath);
    final id = await seedWith(a);
    final b = AppDatabase.forToolFile(dbPath);
    addTearDown(() async {
      await a.close();
      await b.close();
    });

    // ⚠️ 時戳必須相對於 `now` 產生,**不可寫死日期**(2026-08-10 實機):
    // 第一版用 `DateTime(2026, 8, 10, 10, 30)`,寫的當下那是未來時間所以
    // 綠;等真的到了 8/10 12:30,那個時戳變成兩小時前,於是連線開啟時的
    // `reclaimStaleAlertClaims`(15 分鐘租約)把它回收掉,B 就搶得到了
    // ——測試紅,但被測的機制其實是對的。同一天我已經在心跳測試與時區
    // 測試上犯過兩次同樣的日期依賴。
    final t1 = DateTime.now();
    expect(await a.claimAlertTrigger(id, now: t1), isTrue);
    expect(await b.claimAlertTrigger(id), isFalse, reason: 'A 持有期間 B 搶不到');

    // A 通知失敗 → 帶自己的 stamp 撤銷
    expect(await a.releaseAlertClaim(id, stamp: t1), isTrue);

    // B 重新搶到
    final t2 = t1.add(const Duration(minutes: 5));
    expect(await b.claimAlertTrigger(id, now: t2), isTrue);

    // A 的「遲來的釋放」帶著舊 stamp,不可抹掉 B 的認領
    expect(
      await a.releaseAlertClaim(id, stamp: t1),
      isFalse,
      reason: '舊 stamp 不該匹配到 B 的認領',
    );
    final row = (await b.getAllAlerts()).firstWhere((x) => x.id == id);
    expect(row.triggeredAt, t2, reason: 'B 的認領必須完好,否則同一次觸價會通知兩次');
  });

  // ⚠️ 刻意**不**在這裡測 busy_timeout(2026-08-08 五次審查實測):
  // 兩條連線在同一個 isolate 時,等寫鎖會阻塞 event loop → 持鎖的
  // transaction 永遠 commit 不了 → 測試整個掛住(第一版就是這樣,跑了
  // 5 分鐘沒結束)。這條性質需要真正的獨立 process/isolate 才測得出來,
  // 在 `flutter test` 內結構上做不到。
  //
  // 現況:`forToolFile` 已設 `busy_timeout = 5000`(該值來自 2026-08-08
  // 的實機重現——GUI 手動更新握住寫鎖時,launchd 那輪整個死在
  // SqliteException(5))。GUI 側的 executor **沒有**設 busy_timeout,
  // 那是已知缺口,記在此處以免被遺忘。
}

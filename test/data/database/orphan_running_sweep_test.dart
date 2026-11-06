import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/data/database/app_database.dart';
import '../../helpers/time_shift.dart';

/// 孤兒 RUNNING run 的啟動清理(2026-07-30 審查)。
///
/// 問題:update run 起手寫入的狀態若 app 中途被殺(手機殺後台、崩潰),
/// 該 row 永遠停在起手值,與「跑完但部分失敗」的 PARTIAL 無法區分,
/// 更新歷史列表會顯示一筆永遠轉圈的紀錄。
///
/// 修法:起手狀態改用 RUNNING;每次 DB 開啟(beforeOpen)把「開始已超過
/// 收斂門檻」的 RUNNING rows 收斂成 FAILED(message 標注中斷)。
///
/// **為何要 age cutoff(2026-07-30 審查)**:macOS 的 tool/daily_update.dart
/// (launchd 15:30)與 GUI app 共用同一份 sqlite、各開獨立連線——CLI 開啟
/// 觸發的 beforeOpen 若無條件清 RUNNING,會誤殺 GUI 正在進行的 run
/// (畫面進度條還在跑、歷史卻顯示「中斷」)。只清超過
/// [DataFreshness.orphanRunningCutoff] 的 row:真孤兒(app 被殺)通常隔
/// 數小時到數天才再開啟,收斂效果不受影響。
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('orphan_running_test');
    dbFile = File('${tempDir.path}/orphan_test.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('failOrphanRunningRuns:過門檻的 RUNNING→FAILED,完結 run 不動', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    final orphan1 = await db.createUpdateRun(
      DateTime(2026, 7, 29),
      UpdateStatus.running.code,
    );
    final orphan2 = await db.createUpdateRun(
      DateTime(2026, 7, 30),
      UpdateStatus.running.code,
    );
    final done = await db.createUpdateRun(
      DateTime(2026, 7, 30),
      UpdateStatus.running.code,
    );
    await db.finishUpdateRun(done, UpdateStatus.success.code, message: '正常完成');

    // rows 的 startedAt = 現在;把「現在」推到門檻之後 → 全部視為過期
    final future = DateTime.now().add(
      DataFreshness.orphanRunningCutoff + const Duration(minutes: 1),
    );
    final swept = await db.failOrphanRunningRuns(now: future);
    expect(swept, 2);

    final runs = await db.getRecentUpdateRuns();
    final byId = {for (final r in runs) r.id: r};
    expect(byId[orphan1]!.status, UpdateStatus.failed.code);
    expect(byId[orphan1]!.message, contains('中斷'));
    expect(byId[orphan1]!.finishedAt, isNotNull, reason: '收斂時要蓋 finishedAt');
    expect(byId[orphan2]!.status, UpdateStatus.failed.code);
    expect(byId[done]!.status, UpdateStatus.success.code);
    expect(byId[done]!.message, '正常完成');
  });

  test(
    '未過門檻的 RUNNING 不得誤殺(跨 process:CLI 開 DB 撞見 GUI 進行中)',
    skip: skipWhenTimeShifted,
    () async {
      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      await db.createUpdateRun(
        DateTime(2026, 7, 30),
        UpdateStatus.running.code,
      );

      final swept = await db
          .failOrphanRunningRuns(); // now=DeviceTime.now(),row 剛建（startedAt 由 SQLite 填真實時間）
      expect(swept, 0);

      final runs = await db.getRecentUpdateRuns();
      expect(runs.single.status, UpdateStatus.running.code);
    },
  );

  test('beforeOpen 接線:重開 DB 自動收斂「過期」的 RUNNING', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.createUpdateRun(DateTime(2026, 7, 30), UpdateStatus.running.code);
    // 把 startedAt 改成門檻外(模擬 app 被殺後隔了很久才重開)
    final stale = DateTime.now().subtract(
      DataFreshness.orphanRunningCutoff + const Duration(hours: 1),
    );
    await db1
        .update(db1.updateRun)
        .write(UpdateRunCompanion(startedAt: Value(stale)));
    await db1.close(); // 模擬 app 被殺(run 未 finish)

    final db2 = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db2.close);
    final runs = await db2.getRecentUpdateRuns(); // 觸發 open → beforeOpen
    expect(runs.single.status, UpdateStatus.failed.code);
    expect(runs.single.message, contains('中斷'));
  });
}

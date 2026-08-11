import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

/// update_run 的時間欄位時區一致性(2026-08-11 實機)。
///
/// **兩個欄位的儲存表示法不同**,這是真的:
/// ```
/// started_at   "2026-08-11 09:33:46"          → 解析成 UTC(isUtc=true)
/// finished_at  "2026-08-11T17:33:46 +08:00"   → 解析成本地(isUtc=false)
/// ```
/// 因為 `startedAt` 用 `dateTime().withDefault(currentDateAndTime)`(SQLite
/// 的 `CURRENT_TIMESTAMP`,UTC),而 `finishedAt` 由 Dart 的 `DateTime.now()`
/// 寫入。
///
/// **但語意是一致的**:09:33 UTC 與 17:33+08:00 是同一個瞬間,drift 正確
/// 往返,Dart 比較 DateTime 時比的也是瞬間。2026-08-11 我曾因為用 sqlite3
/// 把兩個字串拉出來、在外部都當本地時間解析,而誤報「差 8 小時」——
/// **那是分析工具的錯,不是產品的錯**。
///
/// **這兩條測試留著的理由**:表示法不一致是真實存在的脆弱點。若哪天有人
/// 改掉 `currentDateAndTime`、或 drift 的解析行為變了,這裡會先紅。特別是
/// `failOrphanRunningRuns` 用 `startedAt < now - 2h` 判斷孤兒——一旦時區
/// 對不上,**任何進行中的更新一開 DB 就會被標成 FAILED**。
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('🚨 startedAt 與 finishedAt 必須指向同一個瞬間', () async {
    final before = DateTime.now();
    final id = await db.createUpdateRun(DateTime(2026, 8, 11), 'RUNNING');
    await db.finishUpdateRun(id, 'SUCCESS');
    final after = DateTime.now();

    final run = (await db.getLatestUpdateRun())!;
    // 兩者都在這次測試的時間窗內 → 同基準。若 startedAt 是 UTC,
    // 它會落在 8 小時前,遠早於 before。
    expect(
      run.startedAt.isAfter(before.subtract(const Duration(minutes: 1))),
      isTrue,
      reason:
          'startedAt=${run.startedAt} 早於測試開始時間 $before —— '
          '八成是 SQLite CURRENT_TIMESTAMP 寫進了 UTC',
    );
    expect(
      run.startedAt.isBefore(after.add(const Duration(minutes: 1))),
      isTrue,
    );
    final duration = run.finishedAt!.difference(run.startedAt);
    expect(
      duration.inMinutes.abs(),
      lessThan(1),
      reason: '同一次測試內建立又結束,時長不該以小時計。實測 $duration',
    );
  });

  test('🚨 剛建立的 RUNNING 不可被孤兒回收誤殺', () async {
    // failOrphanRunningRuns 用 startedAt < now - 2h。startedAt 若慢 8 小時,
    // 剛開始的 run 立刻符合條件 → 被標成 FAILED。
    final id = await db.createUpdateRun(DateTime(2026, 8, 11), 'RUNNING');
    final reclaimed = await db.failOrphanRunningRuns();
    expect(reclaimed, 0, reason: '剛建立的 run 不該被當成孤兒');

    final run = (await db.getLatestUpdateRun())!;
    expect(run.id, id);
    expect(run.status, 'RUNNING', reason: '不可被改成 FAILED');
  });
}

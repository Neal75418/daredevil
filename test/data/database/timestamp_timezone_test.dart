// 時間戳的兩種寫入來源不會造成語意錯誤(2026-08-16 查證)
//
// **起因**:維運查表時發現同一列的兩個時間欄長得完全不同——
//   started_at  : 2026-08-16 10:20:50                  ← SQLite CURRENT_TIMESTAMP(UTC)
//   finished_at : 2026-08-16T18:20:50.416168 +08:00    ← Dart DateTime.now()(本地)
// 直接相減會看成「跑了 8 小時」,實際是 1 分鐘。
//
// **查證結論:不是 bug。** `storeDateTimeAsText: true` 之下,Drift 把無時區
// 標記的文字**解讀為 UTC**(讀回來帶 `Z`),兩種格式代表的是同一個絕對時刻,
// 所有經 Drift 的比較與運算都正確。
//
// **為什麼不「順手統一」**:改成 `clientDefault(() => DateTime.now())` 會讓
// 新舊列在同一欄出現兩種文字格式,而 `ORDER BY created_at` 是字串排序
// ——第 11 個字元 ' '(0x20) < 'T'(0x54),舊列會被永久排到新列前面。
// 那是把一個「肉眼看表會誤會」的問題,換成一個真的會排錯的問題。
// 實測正式 DB:每張表每欄都只有單一格式,現況零風險。
//
// 本測試釘住讓「不修」這個決定成立的前提。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('🚨 SQL 預設寫入的時間戳讀回來是正確的絕對時刻(不差 8 小時)', () async {
    final before = DateTime.now();
    final id = await db.createUpdateRun(DateTime(2026, 8, 14), 'RUNNING');
    final after = DateTime.now();

    final row = await db
        .customSelect('SELECT * FROM update_run WHERE id = $id')
        .getSingle();
    final startedAt = row.read<DateTime>('started_at');

    // 允許 1 分鐘誤差(SQL 預設只到秒);時區差會是 8 小時,一驗就分得出來
    expect(
      startedAt.isAfter(before.subtract(const Duration(minutes: 1))) &&
          startedAt.isBefore(after.add(const Duration(minutes: 1))),
      isTrue,
      reason:
          'Drift 必須把無時區標記的 CURRENT_TIMESTAMP 當 UTC 解讀。'
          '實際讀到 $startedAt,建立時間約 $before',
    );
  });

  group('孤兒 RUNNING 收斂——時間基準若錯,兩個方向都會出事', () {
    test('🚨 剛建立的 RUNNING 不得被誤殺', () async {
      // 誤殺的後果:GUI 正在跑的更新被 CLI 的 beforeOpen 標成 FAILED
      // (age cutoff 存在的唯一理由,見 user_dao.failOrphanRunningRuns)
      await db.createUpdateRun(DateTime(2026, 8, 14), 'RUNNING');
      expect(await db.failOrphanRunningRuns(), 0);
    });

    test('🚨 對照組:超過 cutoff 的 RUNNING 必須被清掉', () async {
      // 沒有這條,上一條的「0 筆」也可能是「查詢根本匹配不到任何列」
      // ——那會是反方向的靜默失效:孤兒永遠不收斂
      await db.createUpdateRun(DateTime(2026, 8, 14), 'RUNNING');
      final killed = await db.failOrphanRunningRuns(
        now: DateTime.now().add(
          DataFreshness.orphanRunningCutoff + const Duration(hours: 1),
        ),
      );
      expect(killed, 1);
    });
  });
}

// ThesisDao 測試 — 釘選論點表（出場層 Phase 2 Task 1）
//
// 驗證 spec §4 的關鍵語意：
//   1. 一 symbol 一 ACTIVE（service 層 enforcement）
//   2. INVALIDATED 凍結（僅 ACTIVE 可被 invalidate；不復活）
//   3. 取消 = 物理刪除；封存 = ARCHIVED
//   4. touchLastCheckedById 單筆蓋章（不篩 status；updatedAt 僅於 status 變更時動）
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/exit_params.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> pin(String symbol, {DateTime? date}) => db.pinThesis(
    symbol: symbol,
    pinnedDate: date ?? DateTime(2026, 7, 10),
    referencePrice: 100.0,
    mode: 'pullback',
    triggeredRules: '["PULLBACK_TO_MA20"]',
    scoreShort: 20,
    scoreLong: 30,
  );

  group('pinThesis — 一 symbol 一 ACTIVE', () {
    test('首次釘選成功、重複釘選同 symbol 丟 StateError', () async {
      await pin('2330');
      final active = await db.getActiveTheses();
      expect(active.length, 1);
      expect(active.first.symbol, '2330');
      expect(active.first.status, 'ACTIVE');

      expect(() => pin('2330'), throwsStateError);
    });

    test('失效後可重新釘選（新記錄、歷史保留）', () async {
      final firstId = await pin('2330');
      await db.invalidateThesis(
        firstId,
        invalidatedDate: DateTime(2026, 7, 11),
        reason: ExitReason.timeStop.name,
      );

      final secondId = await pin('2330', date: DateTime(2026, 7, 12));
      expect(secondId, isNot(firstId));

      final all = await db.getThesesByStatus('INVALIDATED');
      expect(all.length, 1);
      final active = await db.getActiveTheses();
      expect(active.single.id, secondId);
    });
  });

  group('invalidateThesis — 凍結語意', () {
    test('ACTIVE → INVALIDATED 寫入日期與 reason', () async {
      final id = await pin('2330');
      await db.invalidateThesis(
        id,
        invalidatedDate: DateTime(2026, 7, 11),
        reason: ExitReason.timeStop.name,
      );
      final row = (await db.getThesesByStatus('INVALIDATED')).single;
      expect(row.invalidatedReason, 'timeStop');
      expect(row.invalidatedDate, DateTime(2026, 7, 11));
    });

    test('已 INVALIDATED 再 invalidate → no-op（凍結、不覆寫）', () async {
      final id = await pin('2330');
      await db.invalidateThesis(
        id,
        invalidatedDate: DateTime(2026, 7, 11),
        reason: ExitReason.timeStop.name,
      );
      // 第二次企圖用不同日期覆寫
      await db.invalidateThesis(
        id,
        invalidatedDate: DateTime(2026, 7, 20),
        reason: ExitReason.timeStop.name,
      );
      final row = (await db.getThesesByStatus('INVALIDATED')).single;
      expect(row.invalidatedDate, DateTime(2026, 7, 11), reason: '首次寫入即凍結');
    });
  });

  group('archive / cancel', () {
    test('archiveThesis：INVALIDATED → ARCHIVED（保留紀錄）', () async {
      final id = await pin('2330');
      await db.invalidateThesis(
        id,
        invalidatedDate: DateTime(2026, 7, 11),
        reason: ExitReason.timeStop.name,
      );
      await db.archiveThesis(id);
      expect(await db.getThesesByStatus('INVALIDATED'), isEmpty);
      expect((await db.getThesesByStatus('ARCHIVED')).single.id, id);
    });

    test('deletePinnedThesis：物理刪除（誤觸取消）', () async {
      final id = await pin('2330');
      await db.deletePinnedThesis(id);
      expect(await db.getActiveTheses(), isEmpty);
      expect(await db.getThesesByStatus('INVALIDATED'), isEmpty);
      expect(await db.getThesesByStatus('ARCHIVED'), isEmpty);
    });
  });

  group('touchLastCheckedById', () {
    test('只蓋指定那筆，其餘不動', () async {
      final targetId = await pin('2330');
      await pin('2317');
      final checkedAt = DateTime(2026, 7, 12, 18);

      await db.touchLastCheckedById(targetId, checkedAt);

      final active = await db.getActiveTheses();
      final target = active.firstWhere((r) => r.id == targetId);
      final other = active.firstWhere((r) => r.id != targetId);
      expect(target.lastCheckedDate, checkedAt);
      expect(other.lastCheckedDate, isNull, reason: '逐筆蓋章不得波及其他論點');
    });

    test('🚨 不篩 status：已 INVALIDATED 的仍蓋得到', () async {
      final id = await pin('2330');
      await db.invalidateThesis(
        id,
        invalidatedDate: DateTime(2026, 7, 10),
        reason: 'timeStop',
      );
      final checkedAt = DateTime(2026, 7, 12, 18);

      await db.touchLastCheckedById(id, checkedAt);

      final row = (await db.getThesesByStatus('INVALIDATED')).single;
      expect(
        row.lastCheckedDate,
        checkedAt,
        reason: '本輪失效者確實在本輪被檢查過，lastCheckedDate 應凍結在本輪',
      );
    });
  });
}

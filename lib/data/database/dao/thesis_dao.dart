import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/user_tables.drift.dart';

/// 釘選論點 DAO（出場層）
///
/// 狀態語意見 `PinnedThesis` 表註解與 spec §4：
/// 一 symbol 一 ACTIVE、INVALIDATED 凍結、取消＝物理刪除。
mixin ThesisDaoMixin on $AppDatabase {
  $PinnedThesisTable get _thesis => pinnedThesis;

  /// 釘選論點。同 symbol 已有 ACTIVE → 丟 [StateError]
  /// （一 symbol 一 ACTIVE，service 層 enforcement，spec §4）。
  Future<int> pinThesis({
    required String symbol,
    required DateTime pinnedDate,
    required double referencePrice,
    required String mode,
    required String triggeredRules,
    required double scoreShort,
    required double scoreLong,
  }) {
    // transaction 包 check+insert：快速雙擊（兩個 pin() 交錯）不會產生
    // 兩筆 ACTIVE 破壞 invariant
    return transaction(() async {
      final existing =
          await (select(_thesis)..where(
                (t) => t.symbol.equals(symbol) & t.status.equals('ACTIVE'),
              ))
              .get();
      if (existing.isNotEmpty) {
        throw StateError(
          'symbol $symbol 已有 ACTIVE 釘選（id=${existing.first.id}）',
        );
      }
      return into(_thesis).insert(
        PinnedThesisCompanion.insert(
          symbol: symbol,
          pinnedDate: pinnedDate,
          referencePrice: referencePrice,
          mode: mode,
          triggeredRules: triggeredRules,
          scoreShort: scoreShort,
          scoreLong: scoreLong,
        ),
      );
    });
  }

  /// 全部 ACTIVE 釘選（monitor 與追蹤區用）
  Future<List<PinnedThesisEntry>> getActiveTheses() {
    return (select(_thesis)
          ..where((t) => t.status.equals('ACTIVE'))
          ..orderBy([(t) => OrderingTerm.desc(t.pinnedDate)]))
        .get();
  }

  /// 依狀態查詢（警示頁讀 INVALIDATED）
  Future<List<PinnedThesisEntry>> getThesesByStatus(String status) {
    return (select(_thesis)
          ..where((t) => t.status.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.pinnedDate)]))
        .get();
  }

  /// ACTIVE → INVALIDATED。**凍結語意**：僅 ACTIVE 可轉，已失效者 no-op
  /// （invalidatedDate/reason 一經寫入不覆寫——「不復活」的程式保障）。
  Future<void> invalidateThesis(
    int id, {
    required DateTime invalidatedDate,
    required String reason,
  }) async {
    await (update(
      _thesis,
    )..where((t) => t.id.equals(id) & t.status.equals('ACTIVE'))).write(
      PinnedThesisCompanion(
        status: const Value('INVALIDATED'),
        invalidatedDate: Value(invalidatedDate),
        invalidatedReason: Value(reason),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// INVALIDATED → ARCHIVED（封存、離開警示頁，保留紀錄）
  Future<void> archiveThesis(int id) async {
    await (update(
      _thesis,
    )..where((t) => t.id.equals(id) & t.status.equals('INVALIDATED'))).write(
      PinnedThesisCompanion(
        status: const Value('ARCHIVED'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 取消釘選 = 物理刪除（誤觸/改變心意；與失效紀律流程分離）
  Future<void> deletePinnedThesis(int id) async {
    await (delete(_thesis)..where((t) => t.id.equals(id))).go();
  }

  /// 單筆蓋「本次已檢查」章（staleness 顯示）。
  ///
  /// **刻意不篩 status**：`ThesisMonitorService` 在評估完成後才蓋章，而本輪
  /// 剛被 `invalidateThesis` 轉成 INVALIDATED 的那筆同樣需要蓋——它確實在
  /// 本輪被檢查過，`lastCheckedDate` 應凍結在本輪而非上一輪。
  /// 刻意不動 updatedAt（那是 status 變更專用）。
  Future<void> touchLastCheckedById(int id, DateTime checkedAt) async {
    await (update(_thesis)..where((t) => t.id.equals(id))).write(
      PinnedThesisCompanion(lastCheckedDate: Value(checkedAt)),
    );
  }
}

import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 內部人股權轉讓操作
mixin InsiderTransferDaoMixin on $AppDatabase {
  /// 取得指定股票的近期轉讓申報記錄
  ///
  /// 預設取最近 20 筆，按申報日期降冪排列。
  Future<List<InsiderTransferEntry>> getRecentTransfers(
    String symbol, {
    int limit = 20,
  }) {
    return (select(insiderTransfer)
          ..where((t) => t.symbol.equals(symbol))
          ..orderBy([(t) => OrderingTerm.desc(t.reportDate)])
          ..limit(limit))
        .get();
  }

  /// 刪除申報日在 [before] 前的「兩種轉讓方式擠在同一格」列（舊規則寫入），回傳刪除筆數。
  ///
  /// 舊解析規則讀「方式別股數」：兩種方式並存時官方把兩個股數接在同一格，
  /// 無分隔被讀成一個大數（3189 景碩 80000008000000）、以空格相隔則解析失敗
  /// 存成 0（2442）。官方只給當日快照，這些舊申報不會再被重抓覆寫，個股
  /// 詳情的內部人分頁又不限日期——不清就永遠顯示錯的股數。新規則以總股數為準、
  /// 寫入的同類列是對的，故以修正生效日切開；冪等，每次同步都可重跑。
  Future<int> deleteLegacyMultiMethodInsiderTransfers({
    required DateTime before,
  }) {
    return (delete(insiderTransfer)..where(
          (t) =>
              t.transferMethod.like('%交易%交易%') &
              t.reportDate.isSmallerThanValue(before),
        ))
        .go();
  }

  /// 批次新增內部人轉讓記錄
  Future<void> insertInsiderTransfers(
    List<InsiderTransferCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(insiderTransfer, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }
}

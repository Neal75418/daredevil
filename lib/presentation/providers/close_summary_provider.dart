import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/close_summary_builder.dart';
import 'package:daredevil/domain/services/close_summary/close_summary_loader.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 收盤摘要；資料庫沒有任何價格時為 null。
///
/// 什麼時候重算：
/// - 每日更新寫入新一輪（[dataUpdateEpochProvider]）。App 內更新、逾時後
///   遲到的回傳、回前景發現資料變了，都會 bump；App 外的更新還在跑時刻意不
///   bump，免得讀到寫到一半的資料。
/// - 自選、分組、持股三張表有寫入：入口卡所在的今日頁一直掛著，移組、記交易
///   後要立刻反映，不等下一輪更新。
/// - 價格與法人表不訂閱：每日更新途中逐批寫入，訂閱會一直重算，改由上面的
///   更新事件觸發。
final closeSummaryProvider = FutureProvider.autoDispose<CloseSummary?>((
  ref,
) async {
  ref.watch(dataUpdateEpochProvider);
  final db = ref.watch(databaseProvider);

  final subscription = db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.watchlist,
          db.watchlistGroups,
          db.portfolioPosition,
        ]),
      )
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);

  final input = await loadCloseSummaryInput(
    db,
    now: ref.read(appClockProvider).now(),
  );
  return input == null ? null : buildCloseSummary(input);
});

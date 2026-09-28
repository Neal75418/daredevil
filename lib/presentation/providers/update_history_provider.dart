import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 最近 N 筆 `update_run` 紀錄
///
/// **設計**：用 [FutureProvider] + watch [dataUpdateEpochProvider]，每輪 update
/// 跑完（不論成敗；前景手動 / B-lite cold-start / launchd CLI）後 epoch 自然
/// bump，list 自動 reload，user 不用手動下拉刷新。
///
/// list 限制 30 筆夠 cover 大概一個月每天的紀錄，超過 30 筆對 user 沒有
/// review 意義（要審計就直接 sqlite cli）。
final updateHistoryProvider = FutureProvider<List<UpdateRunEntry>>((ref) async {
  // bump signal — 任一處 update 完成都會觸發 reload
  ref.watch(dataUpdateEpochProvider);
  final repo = ref.read(marketDataRepositoryProvider);
  return repo.getRecentUpdateRuns(limit: 30);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/domain/services/update/history_coverage.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';

/// 歷史資料建置進度（今日頁「建置中」提示用）。
///
/// watch [dataUpdateEpochProvider]：只有 DB 真的更新過才重算——計算是一次
/// GROUP BY（660 MB DB 約 0.4 秒），回前景／下拉而 DB 沒變時沿用快取。
/// 資料日只用來定窗口右端（見 [loadHistoryCoverage]）；還沒有資料日時
/// 不查（今日頁此時不顯示進度，冷啟動也不必多排一次 GROUP BY）。
final historyCoverageProvider = FutureProvider<HistoryCoverage>((ref) {
  ref.watch(dataUpdateEpochProvider);
  final dataDate = ref.watch(todayProvider.select((s) => s.dataDate));
  if (dataDate == null) return const HistoryCoverage(covered: 0, total: 0);
  return loadHistoryCoverage(
    ref.watch(databaseProvider),
    ref.read(appClockProvider).now(),
    dataDate: dataDate,
  );
});

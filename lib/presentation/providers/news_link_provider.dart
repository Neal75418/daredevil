import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 新聞顯示用的簡稱比對器（新聞頁股票標籤與「自選」、個股新聞分頁共用）
///
/// 股票清單只在每日更新後變動，隨 [dataUpdateEpochProvider] 重建。
final newsLinkMatcherProvider = FutureProvider<StockNameMatcher>((ref) async {
  ref.watch(dataUpdateEpochProvider);
  final stocks = await ref.read(databaseProvider).getAllActiveStocks();
  return StockNameMatcher.forNewsLinks(stocks);
});

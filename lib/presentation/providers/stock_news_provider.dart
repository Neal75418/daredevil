import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_dedup.dart';
import 'package:daredevil/domain/services/news/news_stock_links.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 個股新聞分頁的內容
@immutable
class StockNews {
  const StockNews({
    required this.items,
    required this.otherStocksByNewsId,
    required this.nameStatus,
  });

  /// 這檔近 30 天的新聞（同日同標題去重、新到舊）
  final List<NewsItemEntry> items;

  /// newsId → 同一則新聞提到的其他股票（不含這檔）
  final Map<String, List<String>> otherStocksByNewsId;

  /// 這檔在比對器裡的名稱狀態（決定說明文案）
  final StockNameStatus nameStatus;
}

/// 個股新聞：代號對應到這檔的一律收；標題含這檔名稱的候選要完整比對、
/// 且結果包含這檔才收（「測試電子」不算進「測試」）
final stockNewsProvider = FutureProvider.autoDispose.family<StockNews, String>((
  ref,
  symbol,
) async {
  ref.watch(dataUpdateEpochProvider);
  ref.watch(newsDataVersionProvider);
  final matcher = await ref.watch(newsLinkMatcherProvider.future);
  final db = ref.read(databaseProvider);
  final since = ref
      .read(appClockProvider)
      .now()
      .subtract(const Duration(days: DataFreshness.newsRetentionDays));

  final candidates = await db.getNewsCandidatesForStock(
    symbol: symbol,
    names: matcher.namesOf(symbol),
    since: since,
  );
  final codeMap = await db.getNewsStockMappingsBatch([
    for (final n in candidates) n.id,
  ]);
  // 台積電 30 天候選上千則，比對放背景 isolate
  final related = await NewsStockLinks.mergeInBackground(
    news: candidates,
    codeMap: codeMap,
    matcher: matcher,
  );
  final items = NewsDedup.sameDayTitle([
    for (final n in candidates)
      if (related[n.id]?.contains(symbol) ?? false) n,
  ]);
  return StockNews(
    items: items,
    otherStocksByNewsId: {
      for (final n in items)
        n.id: [
          for (final s in related[n.id]!)
            if (s != symbol) s,
        ],
    },
    nameStatus: matcher.nameStatusOf(symbol),
  );
});

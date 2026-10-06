import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/request_deduplicator.dart';
import 'package:daredevil/domain/models/news_feed.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 新聞資料版本：每次「抓新聞」完成（不論成敗）遞增。
///
/// 新聞頁畫面、熱度分析、個股新聞監聽它重讀——讓任一處觸發的抓取，其他
/// 開著的畫面都看得到新資料。
final newsDataVersionProvider = NotifierProvider<NewsDataVersion, int>(
  NewsDataVersion.new,
);

class NewsDataVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

/// 一次抓新聞的結果（給按重新整理的人看的回饋）
@immutable
class NewsFetchOutcome {
  const NewsFetchOutcome({
    required this.totalSources,
    required this.failedSources,
  });

  final int totalSources;
  final int failedSources;

  bool get allFailed => totalSources > 0 && failedSources >= totalSources;

  bool get partiallyFailed => failedSources > 0 && !allFailed;
}

/// 新聞頁與個股新聞分頁共用的「抓新聞」（只抓 RSS；公告由每日更新抓）
///
/// 同一時間只跑一次：併發呼叫拿到同一個進行中的結果。完成後遞增
/// [newsDataVersionProvider]。
class NewsFetcher {
  NewsFetcher(this._ref);

  final Ref _ref;
  final _dedup = RequestDeduplicator<NewsFetchOutcome>();

  Future<NewsFetchOutcome> fetch() => _dedup('rss', _run);

  Future<NewsFetchOutcome> _run() async {
    final total = NewsFeedSource.defaultSources.length;
    NewsFetchOutcome outcome;
    try {
      final result = await _ref.read(newsRepositoryProvider).syncNews();
      outcome = NewsFetchOutcome(
        totalSources: total,
        failedSources: {for (final e in result.errors) e.sourceName}.length,
      );
    } catch (e) {
      AppLogger.warning('NewsFetcher', 'RSS 同步失敗', e);
      outcome = NewsFetchOutcome(totalSources: total, failedSources: total);
    }
    _ref.read(newsDataVersionProvider.notifier).bump();
    return outcome;
  }
}

final newsFetcherProvider = Provider<NewsFetcher>(NewsFetcher.new);

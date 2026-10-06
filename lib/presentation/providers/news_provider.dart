import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_dedup.dart';
import 'package:daredevil/domain/services/news/news_stock_links.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==================================================
// 新聞來源
// ==================================================

/// 可用的新聞來源篩選選項
enum NewsSource {
  all,
  announcement,
  yahoo,
  cnyes,
  cna,
  udn,
  ltn;

  String get label =>
      'empty.source${name[0].toUpperCase()}${name.substring(1)}'.tr();

  /// 比對 RSS feed 中的來源名稱
  bool matches(String sourceName) {
    return switch (this) {
      NewsSource.all => true,
      NewsSource.announcement => sourceName == '重大訊息',
      NewsSource.yahoo => sourceName == 'Yahoo財經',
      NewsSource.cnyes => sourceName == '鉅亨網',
      NewsSource.cna => sourceName == '中央社',
      NewsSource.udn => sourceName == '經濟日報',
      NewsSource.ltn => sourceName == '自由財經',
    };
  }
}

// ==================================================
// 新聞頁篩選
// ==================================================

/// 新聞頁的篩選（單選）：全部、自選，或單一來源
sealed class NewsFilter {
  const NewsFilter();

  static const all = SourceNewsFilter(NewsSource.all);
  static const mine = MineNewsFilter();
}

/// 相關股票有任一檔是自選或持股的新聞
final class MineNewsFilter extends NewsFilter {
  const MineNewsFilter();

  @override
  bool operator ==(Object other) => other is MineNewsFilter;

  @override
  int get hashCode => (MineNewsFilter).hashCode;
}

/// 單一來源（`NewsSource.all` 即全部）
final class SourceNewsFilter extends NewsFilter {
  const SourceNewsFilter(this.source);

  final NewsSource source;

  @override
  bool operator ==(Object other) =>
      other is SourceNewsFilter && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

// ==================================================
// 新聞狀態
// ==================================================

/// 新聞頁面狀態
class NewsState {
  NewsState({
    this.allNews = const [],
    this.relatedStocksByNewsId = const {},
    this.mySymbols = const {},
    this.isLoading = false,
    this.error,
    this.filter = NewsFilter.all,
    this.searchQuery = '',
  });

  final List<NewsItemEntry> allNews;

  /// newsId → 相關股票（代號對應 ∪ 簡稱比對，見 `NewsStockLinks`）。
  /// 只供顯示，不是 news_stock_map 的內容，不得寫回資料庫
  final Map<String, List<String>> relatedStocksByNewsId;

  /// 自選∪持股
  final Set<String> mySymbols;

  final bool isLoading;
  final String? error;
  final NewsFilter filter;
  final String searchQuery;

  /// 依篩選與搜尋關鍵字過濾的新聞（同日同標題去重後）
  List<NewsItemEntry> get filteredNews {
    var result = switch (filter) {
      MineNewsFilter() => _dedupedMine,
      SourceNewsFilter(:final source) =>
        _dedupedBySource[source] ?? const <NewsItemEntry>[],
    };
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where((n) => n.title.toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  /// 各來源檢視（全部／單一來源）去重後的清單，建構時算一次；規則見
  /// `NewsDedup`。去重在來源過濾**之後**做：全部檢視隱藏轉載、單一來源
  /// 檢視仍看得到該來源自己的那份。
  late final Map<NewsSource, List<NewsItemEntry>> _dedupedBySource = {
    for (final source in NewsSource.values)
      source: NewsDedup.sameDayTitle(
        source == NewsSource.all
            ? allNews
            : allNews.where((n) => source.matches(n.source)).toList(),
      ),
  };

  late final List<NewsItemEntry> _dedupedMine = NewsDedup.sameDayTitle([
    for (final n in allNews)
      if (relatedStocksByNewsId[n.id]?.any(mySymbols.contains) ?? false) n,
  ]);

  /// 各來源的新聞數量（與各檢視實際顯示的清單一致）
  late final Map<NewsSource, int> sourceCounts = {
    for (final e in _dedupedBySource.entries) e.key: e.value.length,
  };

  /// 「自選」的新聞數量（去重後）
  late final int mineCount = _dedupedMine.length;

  /// 這則新聞要顯示的股票標籤：「自選」篩選下自選與持股排前（各組維持原順序）
  List<String> relatedStocksOf(String newsId) {
    final related = relatedStocksByNewsId[newsId] ?? const <String>[];
    if (filter is! MineNewsFilter) return related;
    return [
      ...related.where(mySymbols.contains),
      ...related.where((s) => !mySymbols.contains(s)),
    ];
  }

  NewsState copyWith({
    List<NewsItemEntry>? allNews,
    Map<String, List<String>>? relatedStocksByNewsId,
    Set<String>? mySymbols,
    bool? isLoading,
    Object? error = sentinel,
    NewsFilter? filter,
    String? searchQuery,
  }) {
    return NewsState(
      allNews: allNews ?? this.allNews,
      relatedStocksByNewsId:
          relatedStocksByNewsId ?? this.relatedStocksByNewsId,
      mySymbols: mySymbols ?? this.mySymbols,
      isLoading: isLoading ?? this.isLoading,
      error: error == sentinel ? this.error : error as String?,
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

// ==================================================
// 新聞 Notifier
// ==================================================

class NewsNotifier extends Notifier<NewsState> {
  @override
  NewsState build() => NewsState();

  /// refresh 進行中旗標（防連點；抓取本身另由 `NewsFetcher` 去重）
  bool _isRefreshing = false;

  /// 載入世代：較早開始的載入較晚完成時，不覆蓋較新的結果
  int _loadGeneration = 0;

  /// 重新整理：先抓新聞（共用 `NewsFetcher`），再重讀本地資料
  ///
  /// 抓取失敗不阻擋本地重讀——離線時顯示既有新聞勝於整頁錯誤。回傳抓取
  /// 結果供畫面提示；已有 refresh 進行中時回 null。
  Future<NewsFetchOutcome?> refresh({int days = 7}) async {
    if (_isRefreshing) return null;
    _isRefreshing = true;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final outcome = await ref.read(newsFetcherProvider).fetch();
      await loadData(days: days);
      return outcome;
    } finally {
      _isRefreshing = false;
    }
  }

  /// 新聞資料版本遞增時由畫面呼叫：自己的 refresh 進行中會自行重讀，略過
  void onNewsDataChanged() {
    if (_isRefreshing) return;
    loadData();
  }

  /// 載入新聞資料
  Future<void> loadData({int days = 7}) async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final newsRepo = ref.read(newsRepositoryProvider);
      final db = ref.read(databaseProvider);

      final news = await newsRepo.getRecentNews(days: days);
      final mine = await db.getWatchlistAndHoldingSymbols();
      if (generation != _loadGeneration) return;

      if (news.isEmpty) {
        state = state.copyWith(
          allNews: [],
          relatedStocksByNewsId: {},
          mySymbols: mine,
          isLoading: false,
        );
        return;
      }

      final codeMap = await db.getNewsStockMappingsBatch([
        for (final n in news) n.id,
      ]);
      final matcher = await ref.read(newsLinkMatcherProvider.future);
      final related = await NewsStockLinks.mergeInBackground(
        news: news,
        codeMap: codeMap,
        matcher: matcher,
      );
      if (generation != _loadGeneration) return;

      state = state.copyWith(
        allNews: news,
        relatedStocksByNewsId: related,
        mySymbols: mine,
        isLoading: false,
      );
    } catch (e) {
      if (generation != _loadGeneration) return;
      AppLogger.warning('NewsNotifier', '載入新聞失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e), isLoading: false);
    }
  }

  /// 從新聞頁推出去的頁面返回後重讀自選∪持股（不重抓新聞、不重算相關股票）
  Future<void> reloadMySymbols() async {
    try {
      final mine = await ref
          .read(databaseProvider)
          .getWatchlistAndHoldingSymbols();
      state = state.copyWith(mySymbols: mine);
    } catch (e) {
      AppLogger.warning('NewsNotifier', '重讀自選與持股失敗', e);
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 設定篩選
  void setFilter(NewsFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// 設定搜尋關鍵字
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

// ==================================================
// Provider
// ==================================================

final newsProvider = NotifierProvider<NewsNotifier, NewsState>(
  NewsNotifier.new,
);

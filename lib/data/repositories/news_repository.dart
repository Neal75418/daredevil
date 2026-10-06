import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/rss_parser.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/repositories/news_repository.dart';

/// 新聞資料 Repository
class NewsRepository implements INewsRepository {
  NewsRepository({
    required AppDatabase database,
    required RssParser rssParser,
    TwseClient? twseClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _rssParser = rssParser,
       _twseClient = twseClient,
       _clock = clock;

  final AppDatabase _db;
  final RssParser _rssParser;

  /// 重大訊息同步用；null 時 [syncMaterialInfo] 直接回 0（測試便利）
  final TwseClient? _twseClient;
  final AppClock _clock;

  /// 從所有 RSS feeds 同步新聞
  ///
  /// 回傳 [NewsSyncResult]，包含新增筆數和錯誤資訊
  @override
  Future<NewsSyncResult> syncNews({List<NewsFeedSource>? sources}) async {
    final feedSources = sources ?? NewsFeedSource.defaultSources;
    final parseResult = await _rssParser.parseAllFeeds(feedSources);

    if (parseResult.items.isEmpty) {
      return NewsSyncResult(itemsAdded: 0, errors: parseResult.errors);
    }

    final newsItems = parseResult.items;

    // 預先載入所有上市股票以提升查詢效率
    final activeStocks = await _db.getAllActiveStocks();
    final stockSymbols = activeStocks.map((s) => s.symbol).toSet();

    // 準備資料
    final newsCompanions = <NewsItemCompanion>[];
    final mappingCompanions = <NewsStockMapCompanion>[];

    for (final item in newsItems) {
      newsCompanions.add(
        NewsItemCompanion.insert(
          id: item.id,
          source: item.source,
          title: item.title,
          content: Value(item.content),
          url: item.url,
          category: item.category,
          publishedAt: item.publishedAt,
        ),
      );

      // 從標題擷取並建立股票關聯
      final stockCodes = item.extractStockCodes();
      for (final code in stockCodes) {
        if (stockSymbols.contains(code)) {
          mappingCompanions.add(
            NewsStockMapCompanion.insert(newsId: item.id, symbol: code),
          );
        }
      }
    }

    // 在單一 Transaction 中批次寫入
    // 注意：itemsAdded 為嘗試寫入筆數（insertOrIgnore 會跳過重複項）
    await _db.transaction(() async {
      // 批次寫入新聞
      await _db.batch((b) {
        for (final companion in newsCompanions) {
          b.insert(_db.newsItem, companion, mode: InsertMode.insertOrIgnore);
        }
      });

      // 批次寫入股票關聯
      if (mappingCompanions.isNotEmpty) {
        await _db.batch((b) {
          for (final companion in mappingCompanions) {
            b.insert(
              _db.newsStockMap,
              companion,
              mode: InsertMode.insertOrIgnore,
            );
          }
        });
      }
    });

    return NewsSyncResult(
      itemsAdded: newsCompanions.length,
      errors: parseResult.errors,
    );
  }

  /// 同步自選∪持倉股的重大訊息公告（TWSE t187ap04_L 當日檔）
  ///
  /// 公告是**一手訊號**（庫藏股/大單/法說會/財測），比媒體新聞快且官方；
  /// 以穩定 id（mops_代號_日期_時間）insertOrIgnore，每日檔天然累積、
  /// 重跑冪等。公司代號直接建立股票關聯（100% 對應，免抽取）。
  Future<int> syncMaterialInfo() async {
    final client = _twseClient;
    if (client == null) return 0;

    final symbols = await _db.getWatchlistAndHoldingSymbols();
    if (symbols.isEmpty) return 0;

    final rows = await client.getMaterialInformation();
    final newsRows = <NewsItemCompanion>[];
    final mappingRows = <NewsStockMapCompanion>[];
    for (final info in rows) {
      if (!symbols.contains(info.code)) continue;
      final publishedAt = info.publishedAtUtc;
      if (publishedAt == null || info.subject.isEmpty) continue;
      final id = 'mops_${info.code}_${info.speakDate}_${info.speakTime}';
      newsRows.add(
        NewsItemCompanion.insert(
          id: id,
          source: '重大訊息',
          title: '${info.code} ${info.name}｜${info.subject}',
          content: Value(info.description),
          // 資料集無單則深連結，指向 MOPS 重大訊息查詢頁
          url: 'https://mops.twse.com.tw/mops/web/t05st01',
          category: 'ANNOUNCEMENT',
          publishedAt: publishedAt,
        ),
      );
      mappingRows.add(
        NewsStockMapCompanion.insert(newsId: id, symbol: info.code),
      );
    }

    await _db.insertNewsWithMappings(newsRows, mappingRows);
    return newsRows.length;
  }

  /// 取得最近新聞（Database 層級過濾）
  ///
  /// [days] - 回溯天數（預設 3 天）
  /// [limit] - 回傳上限（預設無限制）
  /// [offset] - 略過筆數（分頁用，預設 0）
  @override
  Future<List<NewsItemEntry>> getRecentNews({
    int days = 3,
    int? limit,
    int offset = 0,
  }) async {
    final cutoff = _clock.now().subtract(Duration(days: days));
    final query = _db.select(_db.newsItem)
      ..where((n) => n.publishedAt.isBiggerOrEqualValue(cutoff))
      ..orderBy([(n) => OrderingTerm.desc(n.publishedAt)]);

    // 套用分頁
    if (limit != null) {
      query.limit(limit, offset: offset);
    }

    return query.get();
  }

  /// 批次取得多檔股票的新聞（避免 N+1 問題）
  ///
  /// 回傳 Map：symbol -> 新聞清單
  @override
  Future<Map<String, List<NewsItemEntry>>> getNewsForStocksBatch(
    List<String> symbols, {
    int days = 3,
  }) async {
    if (symbols.isEmpty) return {};

    final cutoff = _clock.now().subtract(Duration(days: days));

    // 一次查詢所有關聯
    final mappings = await (_db.select(
      _db.newsStockMap,
    )..where((m) => m.symbol.isIn(symbols))).get();

    if (mappings.isEmpty) return {};

    // 取得所有不重複的新聞 ID
    final newsIds = mappings.map((m) => m.newsId).toSet().toList();

    // 一次查詢所有新聞並套用日期過濾
    final newsItems =
        await (_db.select(_db.newsItem)
              ..where((n) => n.id.isIn(newsIds))
              ..where((n) => n.publishedAt.isBiggerOrEqualValue(cutoff))
              ..orderBy([(n) => OrderingTerm.desc(n.publishedAt)]))
            .get();

    // 建立快速查詢 Map
    final newsMap = {for (final item in newsItems) item.id: item};

    // 依股票分組
    final result = <String, List<NewsItemEntry>>{};
    for (final mapping in mappings) {
      final newsItem = newsMap[mapping.newsId];
      if (newsItem != null) {
        result.putIfAbsent(mapping.symbol, () => []).add(newsItem);
      }
    }

    return result;
  }

  /// 清理舊新聞（超過 N 天）
  ///
  /// 使用 Cascade Delete 自動刪除關聯資料
  @override
  Future<int> cleanupOldNews({
    int olderThanDays = DataFreshness.newsRetentionDays,
  }) async {
    final cutoff = _clock.now().subtract(Duration(days: olderThanDays));

    // 刪除舊新聞，Cascade Delete 會處理關聯
    return (_db.delete(
      _db.newsItem,
    )..where((n) => n.publishedAt.isSmallerThanValue(cutoff))).go();
  }
}

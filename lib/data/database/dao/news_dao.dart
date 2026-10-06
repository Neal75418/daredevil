import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/news_tables.drift.dart';

/// 新聞相關資料存取
mixin NewsDaoMixin on $AppDatabase {
  // ==================================================
  // 新聞操作
  // ==================================================

  /// 批次取得多則新聞的股票關聯（批次查詢）
  ///
  /// 回傳 newsId -> 股票代碼列表 的 Map
  Future<Map<String, List<String>>> getNewsStockMappingsBatch(
    List<String> newsIds,
  ) async {
    if (newsIds.isEmpty) return {};

    final results = await (select(
      newsStockMap,
    )..where((t) => t.newsId.isIn(newsIds))).get();

    // 依 newsId 分組
    final grouped = <String, List<String>>{};
    for (final entry in results) {
      grouped.putIfAbsent(entry.newsId, () => []).add(entry.symbol);
    }

    return grouped;
  }

  /// 個股新聞的候選：[since] 之後、代號對應到 [symbol] 或標題含 [names] 任一者，新到舊
  ///
  /// 標題比對用 `instr()`（分大小寫、不吃 `%`／`_` 萬用字元）。時間比較由
  /// drift 換成 `julianday()` 兩邊比（DateTime 以文字儲存時的行為），截止點
  /// 傳本地或 UTC 時間結果相同。
  Future<List<NewsItemEntry>> getNewsCandidatesForStock({
    required String symbol,
    required List<String> names,
    required DateTime since,
  }) {
    final mappedIds = selectOnly(newsStockMap)
      ..addColumns([newsStockMap.newsId])
      ..where(newsStockMap.symbol.equals(symbol));
    Expression<bool> matches = newsItem.id.isInQuery(mappedIds);
    for (final name in names) {
      matches =
          matches |
          FunctionCallExpression<int>('instr', [
            newsItem.title,
            Variable<String>(name),
          ]).isBiggerThanValue(0);
    }
    return (select(newsItem)
          ..where((t) => t.publishedAt.isBiggerOrEqualValue(since) & matches)
          ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)]))
        .get();
  }

  /// 讀取所有已存的重大訊息公告（source=重大訊息）＋其關聯股票。
  ///
  /// 回傳 (symbol, text)：text＝標題＋內文合併，供 investorConferenceDate
  /// 等純文字解析。公告永久累積（不像 API 單日檔），故法說會等衍生事件
  /// 應以此為來源、不重打 API。
  Future<List<({String symbol, String text})>>
  getMaterialAnnouncements() async {
    final rows = await (select(newsItem).join([
      innerJoin(newsStockMap, newsStockMap.newsId.equalsExp(newsItem.id)),
    ])..where(newsItem.source.equals('重大訊息'))).get();
    return [
      for (final r in rows)
        (
          symbol: r.readTable(newsStockMap).symbol,
          text:
              '${r.readTable(newsItem).title}\n'
              '${r.readTable(newsItem).content ?? ''}',
        ),
    ];
  }

  /// 批次寫入新聞與股票關聯（單一交易、insertOrIgnore 去重）
  ///
  /// 供重大訊息等非 RSS 來源共用；id 穩定即天然冪等。
  Future<void> insertNewsWithMappings(
    List<NewsItemCompanion> newsRows,
    List<NewsStockMapCompanion> mappingRows,
  ) async {
    if (newsRows.isEmpty) return;
    await transaction(() async {
      await batch((b) {
        for (final r in newsRows) {
          b.insert(newsItem, r, mode: InsertMode.insertOrIgnore);
        }
      });
      if (mappingRows.isNotEmpty) {
        await batch((b) {
          for (final r in mappingRows) {
            b.insert(newsStockMap, r, mode: InsertMode.insertOrIgnore);
          }
        });
      }
    });
  }

  // ==================================================
  // 每日提及數快照（新聞熱度發現層）
  // ==================================================

  /// 快照 upsert（(date,kind,itemKey) 覆蓋）
  ///
  /// ⚠️ production 每日回補實際走 replaceMentionCountsInWindow；本方法
  /// 僅測試 seeding 使用（2026-07-23 稽核確認 lib 零呼叫）
  Future<void> upsertMentionCounts(List<NewsMentionDailyCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      for (final r in rows) {
        b.insert(newsMentionDaily, r, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 窗內全量覆寫：先刪 [from, to]（含端點）日期範圍內全部快照列再批次寫入，
  /// 使重算對「已消失的 key」也冪等（殘留列歸零）
  Future<void> replaceMentionCountsInWindow({
    required DateTime from,
    required DateTime to,
    required List<NewsMentionDailyCompanion> rows,
  }) async {
    await transaction(() async {
      await (delete(newsMentionDaily)..where(
            (t) =>
                t.date.isBiggerOrEqualValue(from) &
                t.date.isSmallerOrEqualValue(to),
          ))
          .go();
      if (rows.isNotEmpty) {
        await batch((b) {
          for (final r in rows) {
            b.insert(newsMentionDaily, r, mode: InsertMode.insertOrReplace);
          }
        });
      }
    });
  }

  /// 讀取快照（date >= from），未來回測用；測試亦用此驗證寫入
  Future<List<NewsMentionDailyEntry>> getMentionCounts({
    required DateTime from,
  }) {
    return (select(newsMentionDaily)
          ..where((t) => t.date.isBiggerOrEqualValue(from))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }
}

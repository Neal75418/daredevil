import 'package:drift/drift.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 融資融券操作
mixin MarginTradingDaoMixin on $AppDatabase {
  /// 取得股票的融資融券歷史
  Future<List<MarginTradingEntry>> getMarginTradingHistory(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final query = select(marginTrading)
      ..where((t) => t.symbol.equals(symbol))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.date)]);
    return query.get();
  }

  /// 取得指定日期的融資融券資料筆數（新鮮度檢查用）
  Future<int> getMarginTradingCountForDate(DateTime date) async {
    // 使用本地時間午夜以匹配資料庫儲存格式
    final startOfDay = DateContext.normalize(date);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final countExpr = marginTrading.symbol.count();
    final query = selectOnly(marginTrading)
      ..addColumns([countExpr])
      ..where(marginTrading.date.isBiggerOrEqualValue(startOfDay))
      ..where(marginTrading.date.isSmallerThanValue(endOfDay));
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// 窗內各（交易日, 市場）的融資融券筆數（缺漏日回補掃描用）。
  ///
  /// 一次 GROUP BY 取代逐 (日, 市場) 的 [countMarginTradingByDateAndMarket]——40 天窗
  /// 每輪每日更新累積 ~140 次逐日 COUNT（2026-08-29 效能稽核 #4，
  /// getPriceCountsByDayAndMarket 批次化前例的 sibling）。
  /// 回傳 market → 'yyyy-MM-dd' → 筆數；無資料的 (日, 市場) 不在 Map
  /// （caller 以 `?? 0` 處理）。日期鍵取儲存文字前綴（全庫皆本地午夜，
  /// 與逐日精確比對等價，由真 DB 對照測試釘住）。
  Future<Map<String, Map<String, int>>> getMarginTradingCountsByDayAndMarket({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final rows = await customSelect(
      '''
      SELECT substr(t.date, 1, 10) AS d, sm.market AS market, COUNT(*) AS n
      FROM margin_trading t
      INNER JOIN stock_master sm ON t.symbol = sm.symbol
      WHERE t.date >= ? AND t.date <= ?
      GROUP BY d, market
      ''',
      variables: [
        Variable.withDateTime(startDate),
        Variable.withDateTime(endDate),
      ],
      readsFrom: {marginTrading, stockMaster},
    ).get();

    final result = <String, Map<String, int>>{};
    for (final row in rows) {
      result.putIfAbsent(row.read<String>('market'), () => {})[row.read<String>(
        'd',
      )] = row.read<int>(
        'n',
      );
    }
    return result;
  }

  /// 計算某日、某市場（TWSE / TPEx）的融資融券筆數
  ///
  /// 缺漏日回補的偵測用。**必須 per-market**：合併門檻
  /// （`DataFreshness.fullMarketThreshold` = 1500）是以上市+上櫃合計校準的，
  /// 但上市單邊約 1,280 筆——若上櫃端點失敗、只寫進上市，合併筆數仍低於門檻，
  /// 該日會被永遠判為缺漏而無限重抓。與
  /// [PriceDaoMixin.countPricesByDateAndMarket] 同模式。
  Future<int> countMarginTradingByDateAndMarket(
    DateTime date,
    String market,
  ) async {
    final startOfDay = DateContext.normalize(date);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await customSelect(
      '''
      SELECT COUNT(*) as cnt
      FROM margin_trading mt
      INNER JOIN stock_master sm ON mt.symbol = sm.symbol
      WHERE mt.date >= ? AND mt.date < ? AND sm.market = ?
      ''',
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
        Variable.withString(market),
      ],
    ).getSingle();
    return result.read<int>('cnt');
  }

  /// 批次新增融資融券資料
  Future<void> insertMarginTradingData(
    List<MarginTradingCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(marginTrading, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }
}

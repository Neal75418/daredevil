import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 當沖操作
mixin DayTradingDaoMixin on $AppDatabase {
  /// 取得股票的當沖歷史
  Future<List<DayTradingEntry>> getDayTradingHistory(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final query = select(dayTrading)
      ..where((t) => t.symbol.equals(symbol))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.date)]);
    return query.get();
  }

  /// 取得指定日期的當沖資料筆數（新鮮度檢查用）
  Future<int> getDayTradingCountForDate(DateTime date) async {
    // 使用本地時間午夜以匹配資料庫儲存格式
    final startOfDay = DateContext.normalize(date);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final countExpr = dayTrading.symbol.count();
    final query = selectOnly(dayTrading)
      ..addColumns([countExpr])
      ..where(dayTrading.date.isBiggerOrEqualValue(startOfDay))
      ..where(dayTrading.date.isSmallerThanValue(endOfDay));
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// 批次新增當沖資料
  Future<void> insertDayTradingData(List<DayTradingCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(dayTrading, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 刪除指定日期範圍內的當沖資料
  ///
  /// 用於清理可能存在的重複記錄（由於 UTC/本地時間不一致）
  /// 刪除日期區間內、**指定市場**的當沖列。
  ///
  /// 兩個必須同時成立的保證：
  /// 1. **同日變體時間戳要清掉**——歷史上 UTC/本地不一致造成同一天有多個非
  ///    午夜時間戳的列，即使該股不在本次批次也要清（原設計意圖，有測試守）。
  /// 2. **不得跨市場刪除**——本方法原本無條件刪光區間內所有列，在 TWSE 單一
  ///    writer 時代無害；接上櫃後兩市場寫同一天會互相清除，且因為刪完立刻
  ///    寫入自己的資料，筆數看起來正常，不會有任何錯誤訊號。
  ///
  /// 故以 `stock_master.market` 限縮：清得到同市場的變體，碰不到另一市場。
  Future<int> deleteDayTradingForDateRange(
    DateTime startDate,
    DateTime endDate, {
    required String market,
  }) async {
    return customUpdate(
      'DELETE FROM day_trading '
      'WHERE date >= ? AND date <= ? '
      'AND symbol IN (SELECT symbol FROM stock_master WHERE market = ?)',
      variables: [
        Variable.withDateTime(startDate),
        Variable.withDateTime(endDate),
        Variable.withString(market),
      ],
      updates: {dayTrading},
    );
  }

  /// 取得資料庫中最新的當沖資料日期
  ///
  /// 用於上櫃股票的新鮮度檢查基準。
  /// 回傳 TWSE 批次同步後的實際資料日期。
  Future<DateTime?> getLatestDayTradingDate() async {
    final result =
        await (select(dayTrading)
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(1))
            .getSingleOrNull();
    return result?.date;
  }

  /// 批次取得最新當沖資料 Map
  ///
  /// 用於 Isolate 評分時傳遞當沖資料。
  /// 優先取得指定日期的資料，若無則取得最近 5 天內的最新資料。
  /// 回傳 symbol -> dayTradingRatio 的對應表。
  Future<Map<String, double>> getDayTradingMapForDate(DateTime date) async {
    final startOfDay = DateContext.normalize(date);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // 先嘗試取得指定日期的資料
    var results =
        await (select(dayTrading)
              ..where((t) => t.date.isBiggerOrEqualValue(startOfDay))
              ..where((t) => t.date.isSmallerThanValue(endOfDay)))
            .get();

    // 若指定日期沒有資料，取得最近 5 天內最新一天的資料
    if (results.isEmpty) {
      final lookbackStart = startOfDay.subtract(
        const Duration(days: DataFreshness.dayTradingFallbackDays),
      );
      final latestDateResult = await customSelect(
        '''
      SELECT MAX(date) as latest_date
      FROM day_trading
      WHERE date >= ? AND date < ?
      ''',
        variables: [
          Variable.withDateTime(lookbackStart),
          Variable.withDateTime(endOfDay),
        ],
      ).getSingleOrNull();

      // 用 read<DateTime?> 走 drift 內建型別化轉換，而非手動
      // read<String?> + DateTime.parse。手動 parse 對帶明確 UTC offset 的
      // 字串（本地日期一律如此）會回傳 isUtc=true，DateContext.normalize
      // 直接讀其 .year/.month/.day 會拿到 UTC 曆日、比本地曆日落後一天，
      // 導致下方查詢範圍位移一天——不是查無資料，而是靜默查到「更舊一天」
      // 的資料當作最新回傳。
      final latestDate = latestDateResult?.read<DateTime?>('latest_date');
      if (latestDate != null) {
        final latestStartOfDay = DateContext.normalize(latestDate);
        final latestEndOfDay = latestStartOfDay.add(const Duration(days: 1));

        results =
            await (select(dayTrading)
                  ..where((t) => t.date.isBiggerOrEqualValue(latestStartOfDay))
                  ..where((t) => t.date.isSmallerThanValue(latestEndOfDay)))
                .get();
      }
    }

    final map = <String, double>{};
    for (final entry in results) {
      if (entry.dayTradingRatio != null) {
        map[entry.symbol] = entry.dayTradingRatio!;
      }
    }
    return map;
  }
}

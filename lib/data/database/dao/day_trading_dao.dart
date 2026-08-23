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
  /// 某日某市場的當沖筆數（新鮮度檢查用）
  ///
  /// **必須分市場**：不分市場的版本在 TWSE 是唯一 writer 時等價，接上櫃之後
  /// 會變成「上櫃先寫了 800 列 → 上市的閘門看到 800 > 100 → 整批跳過」，
  /// 當沖規則對整個上市市場失明，而 `tool/backfill.dart` 還會把該日記成成功、
  /// 永不重試。比照 `countPricesByDateAndMarket` / `countMarginTradingByDateAndMarket`。
  Future<int> getDayTradingCountForDateAndMarket(
    DateTime date,
    String market,
  ) async {
    final startOfDay = DateContext.normalize(date);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM day_trading dt '
      'INNER JOIN stock_master sm ON dt.symbol = sm.symbol '
      'WHERE dt.date >= ? AND dt.date < ? AND sm.market = ?',
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
        Variable.withString(market),
      ],
      readsFrom: {dayTrading, stockMaster},
    ).getSingle();
    return result.read<int>('cnt');
  }

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
  /// 刪除日期區間內、**本次同步所擁有**的當沖列。
  ///
  /// 「擁有」＝ `stock_master.market` 屬於 [market]，**或** 出現在本次寫入的
  /// [batchSymbols] 裡。兩個條件缺一不可：
  ///
  /// - 只用 [market]：`market` 是可變的分類，不等於「哪條管線寫的」。上櫃轉
  ///   上市的股票在 `stock_master` 更新前，由上市管線寫入卻被歸類為 TPEx
  ///   （`tool/calibration.db` 實測 36 檔），其同日變體會清不到。
  /// - 只用 [batchSymbols]：清不到「不在本次批次、但同市場」的殘留變體，
  ///   那正是 2026-07-14 事故留下的護欄要防的。
  ///
  /// 兩者聯集同時滿足：
  /// 1. **同日變體時間戳要清掉**——歷史 UTC/本地不一致造成的髒資料。
  /// 2. **不得跨市場刪除**——接上櫃後兩市場寫同一天會互相清除，而且刪完立刻
  ///    寫入自己的資料，筆數看起來正常，不會有任何錯誤訊號。
  ///    （批次條件不破壞這點：本次批次裡的股票本來就要被覆寫。）
  Future<int> deleteDayTradingForDateRange(
    DateTime startDate,
    DateTime endDate, {
    required String market,
    required Set<String> batchSymbols,
  }) async {
    final placeholders = batchSymbols.isEmpty
        ? 'NULL'
        : List.filled(batchSymbols.length, '?').join(',');
    return customUpdate(
      'DELETE FROM day_trading '
      'WHERE date >= ? AND date <= ? '
      'AND (symbol IN (SELECT symbol FROM stock_master WHERE market = ?) '
      'OR symbol IN ($placeholders))',
      variables: [
        Variable.withDateTime(startDate),
        Variable.withDateTime(endDate),
        Variable.withString(market),
        for (final s in batchSymbols) Variable.withString(s),
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

import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/market_day_finality.dart';
import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 盤後資料抓取狀態（定案判斷）
mixin MarketDayFetchDaoMixin on $AppDatabase {
  /// 記錄一次全市場抓取。同鍵以最後寫入者為準（不取較大時間）：並行時
  /// 較晚寫入的若是初值，只會讓該列回到未定案，不會把初值誤標成定案。
  Future<void> upsertMarketDayFetch({
    required String dataset,
    required String market,
    required DateTime date,
    required DateTime fetchedAt,
    required int rowCount,
  }) {
    return into(marketDayFetch).insertOnConflictUpdate(
      MarketDayFetchCompanion.insert(
        dataset: dataset,
        market: market,
        date: DateContext.normalize(date),
        fetchedAt: fetchedAt,
        rowCount: rowCount,
      ),
    );
  }

  Future<MarketDayFetchEntry?> getMarketDayFetch(
    String dataset,
    String market,
    DateTime date,
  ) {
    final day = DateContext.normalize(date);
    return (select(marketDayFetch)..where(
          (t) =>
              t.dataset.equals(dataset) &
              t.market.equals(market) &
              t.date.equals(day),
        ))
        .getSingleOrNull();
  }

  /// 資料日 ≥ [since] 的所有狀態列
  Future<List<MarketDayFetchEntry>> getMarketDayFetchesSince(DateTime since) {
    final from = DateContext.normalize(since);
    return (select(
      marketDayFetch,
    )..where((t) => t.date.isBiggerOrEqualValue(from))).get();
  }

  Future<bool> isMarketDayFinal({
    required MarketDataset dataset,
    required String market,
    required DateTime date,
  }) async {
    final row = await getMarketDayFetch(dataset.code, market, date);
    return row != null &&
        isFetchFinal(dataDate: row.date, fetchedAtTaipei: row.fetchedAt);
  }
}

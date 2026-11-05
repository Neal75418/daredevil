import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.drift.dart';

/// 某市場最新正式資料日的內容摘要：任何一項不同就重讀熱力圖。
///
/// 只比對內容、不看是誰在什麼時候寫的：很多寫入不改日期（21:30 覆寫 15:30、
/// 停市日重寫前一日、逐檔回補、除權息補正），launchd 在背景寫入時也沒有通知。
typedef HeatmapFingerprint = ({
  DateTime date,
  int rows,
  int changeRows,
  double? changeSum,
  double? closeSum,
});

/// 熱力圖一格的價格資料
typedef HeatmapPriceRow = ({
  String symbol,
  String name,
  String? industry,
  double close,
  double? priceChange,
});

/// 大盤熱力圖的讀取（只讀）
mixin HeatmapDaoMixin on $AppDatabase {
  /// 該市場最近一個有正式資料（`market_day_fetch` 的 `prices` 紀錄）的日子。
  ///
  /// 不用裸 `MAX(daily_price.date)`：逐檔回補只寫了幾檔的日子會被當成「今天」。
  /// 用 customSelect＋`read<DateTime?>`：drift 的 `.max()` 在文字日期模式下回
  /// UTC，normalize 後在 +08:00 的機器上會差一天。
  Future<DateTime?> getLatestFormalPriceDate(String market) async {
    final row = await customSelect(
      'SELECT MAX(date) AS max_date FROM market_day_fetch '
      'WHERE dataset = ? AND market = ?',
      variables: [
        Variable.withString(MarketDataset.prices.code),
        Variable.withString(market),
      ],
      readsFrom: {marketDayFetch},
    ).getSingleOrNull();
    final date = row?.read<DateTime?>('max_date');
    return date == null ? null : DateContext.normalize(date);
  }

  /// 最新正式資料日、該日該市場 `daily_price` 的列數、非空漲跌數、漲跌合計、
  /// 收盤合計；沒有正式資料日時回 null。
  Future<HeatmapFingerprint?> getHeatmapFingerprint(String market) async {
    final date = await getLatestFormalPriceDate(market);
    if (date == null) return null;
    final row = await customSelect(
      '''
      SELECT COUNT(*) AS row_count,
             COUNT(dp.price_change) AS change_rows,
             SUM(dp.price_change) AS change_sum,
             SUM(dp.close) AS close_sum
      FROM daily_price dp
      INNER JOIN stock_master sm ON dp.symbol = sm.symbol
      WHERE sm.market = ? AND dp.date >= ? AND dp.date < ?
      ''',
      variables: [
        Variable.withString(market),
        Variable.withDateTime(date),
        Variable.withDateTime(date.add(const Duration(days: 1))),
      ],
      readsFrom: {dailyPrice, stockMaster},
    ).getSingle();
    return (
      date: date,
      rows: row.read<int>('row_count'),
      changeRows: row.read<int>('change_rows'),
      changeSum: row.readNullable<double>('change_sum'),
      closeSum: row.readNullable<double>('close_sum'),
    );
  }

  /// 該市場、該日、仍上架、有收盤價的股票（代號升冪）。漲跌價差原值照回，
  /// 空值不退回前一筆收盤。
  Future<List<HeatmapPriceRow>> getHeatmapPriceRows(
    String market,
    DateTime date,
  ) async {
    final day = DateContext.normalize(date);
    final rows = await customSelect(
      '''
      SELECT sm.symbol, sm.name, sm.industry, dp.close, dp.price_change
      FROM daily_price dp
      INNER JOIN stock_master sm ON dp.symbol = sm.symbol
      WHERE sm.market = ? AND sm.is_active = 1
        AND dp.date >= ? AND dp.date < ?
        AND dp.close IS NOT NULL
      ORDER BY sm.symbol
      ''',
      variables: [
        Variable.withString(market),
        Variable.withDateTime(day),
        Variable.withDateTime(day.add(const Duration(days: 1))),
      ],
      readsFrom: {dailyPrice, stockMaster},
    ).get();
    return [
      for (final r in rows)
        (
          symbol: r.read<String>('symbol'),
          name: r.read<String>('name'),
          industry: r.readNullable<String>('industry'),
          close: r.read<double>('close'),
          priceChange: r.readNullable<double>('price_change'),
        ),
    ];
  }
}

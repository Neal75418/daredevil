import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 外資持股操作
mixin ShareholdingDaoMixin on $AppDatabase {
  /// 取得股票的持股歷史
  Future<List<ShareholdingEntry>> getShareholdingHistory(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final query = select(shareholding)
      ..where((t) => t.symbol.equals(symbol))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.date)]);
    return query.get();
  }

  /// 取得股票的最新持股資料
  Future<ShareholdingEntry?> getLatestShareholding(String symbol) {
    return (select(shareholding)
          ..where((t) => t.symbol.equals(symbol))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 批次取得多檔股票的最新持股資料
  ///
  /// 用於 Isolate 評分時傳遞外資持股資料。
  /// 回傳 symbol -> ShareholdingEntry 的對應表。
  /// [asOf] 給定時只取該日（含）以前的資料
  ///
  /// 無上界的全域 `MAX(date)` 在對歷史日重跑時會把**未來**的基本面寫進當日
  /// 訊號（`daily_reason` → `rule_accuracy` 的輸入）。`tool/replay_calibrator`
  /// 早已做 point-in-time 過濾，此處補上同一口徑，讓 runtime 與 calibrator
  /// 結構上一致，也讓「把歷史重放進 daily_reason」成為安全的操作。
  ///
  /// 省略時維持原本的全域最新語意（正式路徑的評分日恆為今日，實測四張
  /// 基本面表無任何超前列，故行為不變）。
  Future<Map<String, ShareholdingEntry>> getLatestShareholdingsBatch(
    List<String> symbols, {
    DateTime? asOf,
  }) async {
    if (symbols.isEmpty) return {};

    final results = await customSelect(
      '''
    SELECT s.*
    FROM shareholding s
    INNER JOIN (
      SELECT symbol, MAX(date) as max_date
      FROM shareholding
      WHERE symbol IN (${symbols.map((_) => '?').join(', ')})
      ${asOf == null ? '' : 'AND date <= ?'}
      GROUP BY symbol
    ) latest ON s.symbol = latest.symbol AND s.date = latest.max_date
    ''',
      variables: [
        ...symbols.map((s) => Variable.withString(s)),
        if (asOf != null) Variable.withDateTime(asOf),
      ],
    ).get();

    final map = <String, ShareholdingEntry>{};
    for (final row in results) {
      final symbol = row.read<String>('symbol');
      map[symbol] = ShareholdingEntry(
        symbol: symbol,
        // 用 read<DateTime> 走 drift 內建型別化轉換，而非手動
        // read<String> + DateTime.parse。手動 parse 對帶明確 UTC offset 的
        // 字串（本地日期一律如此）會回傳 isUtc=true，直接讀 .day/.month
        // 會拿到 UTC 曆日、比本地曆日落後一天（與融資融券同型 bug）。
        date: row.read<DateTime>('date'),
        foreignRemainingShares: row.read<double?>('foreign_remaining_shares'),
        foreignSharesRatio: row.read<double?>('foreign_shares_ratio'),
        foreignUpperLimitRatio: row.read<double?>('foreign_upper_limit_ratio'),
        sharesIssued: row.read<double?>('shares_issued'),
      );
    }
    return map;
  }

  /// 批次取得 N 天前的外資持股資料
  ///
  /// 用於計算外資持股變化量（foreignSharesRatioChange）。
  /// 取得每檔股票在指定日期之前最接近的持股資料。
  Future<Map<String, ShareholdingEntry>> getShareholdingsBeforeDateBatch(
    List<String> symbols, {
    required DateTime beforeDate,
  }) async {
    if (symbols.isEmpty) return {};

    final results = await customSelect(
      '''
    SELECT s.*
    FROM shareholding s
    INNER JOIN (
      SELECT symbol, MAX(date) as max_date
      FROM shareholding
      WHERE symbol IN (${symbols.map((_) => '?').join(', ')})
        AND date < ?
      GROUP BY symbol
    ) prev ON s.symbol = prev.symbol AND s.date = prev.max_date
    ''',
      variables: [
        ...symbols.map((s) => Variable.withString(s)),
        Variable.withDateTime(beforeDate),
      ],
    ).get();

    final map = <String, ShareholdingEntry>{};
    for (final row in results) {
      final symbol = row.read<String>('symbol');
      map[symbol] = ShareholdingEntry(
        symbol: symbol,
        // 與 getLatestShareholdingsBatch 同型修法：read<DateTime> 走 drift
        // 內建型別化轉換，避免手動 parse 帶 offset 字串時漏 .toLocal()
        // 而讀到 UTC 曆日。
        date: row.read<DateTime>('date'),
        foreignRemainingShares: row.read<double?>('foreign_remaining_shares'),
        foreignSharesRatio: row.read<double?>('foreign_shares_ratio'),
        foreignUpperLimitRatio: row.read<double?>('foreign_upper_limit_ratio'),
        sharesIssued: row.read<double?>('shares_issued'),
      );
    }
    return map;
  }

  /// 批次新增持股資料
  /// 指定日期的外資持股列數(全市場同步的新鮮度檢查用)
  Future<int> countShareholdingForDate(DateTime date) async {
    final total = shareholding.symbol.count();
    final query = selectOnly(shareholding)
      ..addColumns([total])
      ..where(shareholding.date.equals(date));
    return (await query.getSingle()).read(total) ?? 0;
  }

  Future<void> insertShareholdingData(
    List<ShareholdingCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(shareholding, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }
}

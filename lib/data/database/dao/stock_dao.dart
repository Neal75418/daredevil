import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/stock_master.drift.dart';

/// 股票主檔操作
mixin StockDaoMixin on $AppDatabase {
  /// 取得所有上市中的股票
  Future<List<StockMasterEntry>> getAllActiveStocks() {
    return (select(stockMaster)..where((t) => t.isActive.equals(true))).get();
  }

  /// 依股票代碼取得股票
  Future<StockMasterEntry?> getStock(String symbol) {
    return (select(
      stockMaster,
    )..where((t) => t.symbol.equals(symbol))).getSingleOrNull();
  }

  /// 新增或更新股票主檔
  Future<void> upsertStock(StockMasterCompanion entry) {
    return into(stockMaster).insertOnConflictUpdate(entry);
  }

  /// 批次新增或更新股票
  Future<void> upsertStocks(List<StockMasterCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(stockMaster, entry, onConflict: DoUpdate((_) => entry));
      }
    });
  }

  /// 依代碼或名稱搜尋股票（Database 層級過濾）
  Future<List<StockMasterEntry>> searchStocks(String query) {
    final lowerQuery = '%${query.toLowerCase()}%';
    return (select(stockMaster)
          ..where((t) => t.isActive.equals(true))
          ..where(
            (t) =>
                t.symbol.lower().like(lowerQuery) |
                t.name.lower().like(lowerQuery),
          ))
        .get();
  }

  /// 依市場取得股票（Database 層級過濾）
  Future<List<StockMasterEntry>> getStocksByMarket(String market) {
    return (select(stockMaster)
          ..where((t) => t.isActive.equals(true))
          ..where((t) => t.market.equals(market)))
        .get();
  }

  /// 批次取得 symbol → market 對照（覆蓋率統計用）
  ///
  /// 只取兩個欄位，避免 [getStocksByMarket] 那種全表 materialize；
  /// symbol 是 PK，走索引。
  Future<Map<String, String>> getMarketsForSymbolsBatch(
    List<String> symbols,
  ) async {
    if (symbols.isEmpty) return {};
    final query = selectOnly(stockMaster)
      ..addColumns([stockMaster.symbol, stockMaster.market])
      ..where(stockMaster.symbol.isIn(symbols));
    final rows = await query.get();
    return {
      for (final r in rows)
        r.read(stockMaster.symbol)!: r.read(stockMaster.market)!,
    };
  }

  /// 依市場計算在市股票數（覆蓋率門檻用；不需要 row 內容就別 materialize）
  Future<int> countStocksByMarket(String market) async {
    final countExpr = stockMaster.symbol.count();
    final query = selectOnly(stockMaster)
      ..addColumns([countExpr])
      ..where(stockMaster.isActive.equals(true))
      ..where(stockMaster.market.equals(market));
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  /// 取得所有不重複的產業類別（已排序）
  Future<List<String>> getDistinctIndustries() async {
    final query = selectOnly(stockMaster, distinct: true)
      ..addColumns([stockMaster.industry])
      ..where(stockMaster.isActive.equals(true))
      ..where(stockMaster.industry.isNotNull());
    final rows = await query.get();
    return rows
        .map((row) => row.read(stockMaster.industry))
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
  }

  /// 取得指定產業的所有股票代碼
  Future<Set<String>> getSymbolsByIndustry(String industry) async {
    if (industry.isEmpty) return {};
    final results =
        await (select(stockMaster)
              ..where((t) => t.isActive.equals(true))
              ..where((t) => t.industry.equals(industry)))
            .get();
    return results.map((s) => s.symbol).toSet();
  }

  /// 取得各產業的股票數量
  Future<Map<String, int>> getIndustryStockCounts() async {
    final query = selectOnly(stockMaster)
      ..addColumns([stockMaster.industry, stockMaster.symbol.count()])
      ..where(stockMaster.isActive.equals(true))
      ..where(stockMaster.industry.isNotNull())
      ..groupBy([stockMaster.industry]);
    final rows = await query.get();
    final result = <String, int>{};
    for (final row in rows) {
      final industry = row.read(stockMaster.industry);
      final count = row.read(stockMaster.symbol.count());
      if (industry != null && industry.isNotEmpty && count != null) {
        result[industry] = count;
      }
    }
    return result;
  }

  /// 批次取得多檔股票（批次查詢）
  ///
  /// 回傳 symbol -> 股票資料 的 Map
  Future<Map<String, StockMasterEntry>> getStocksBatch(
    List<String> symbols,
  ) async {
    if (symbols.isEmpty) return {};

    final results = await (select(
      stockMaster,
    )..where((t) => t.symbol.isIn(symbols))).get();

    return {for (final stock in results) stock.symbol: stock};
  }

  /// 官方權威範圍(上市四碼非 ETF)內仍存活的股票數
  ///
  /// 給 `syncStockList` 當「上一輪的既有規模」基準用:sanity floor 是絕對
  /// 下限,擋災難性的部分回應;floor 通過之後仍可能缺漏(`api_config` 自承
  /// 「1000 縮盲區至 ~93 檔」),那段盲區只能靠與既有規模比才看得出來。
  /// DB 本身就是上一輪的結果,不必另外持久化 state。
  ///
  /// ⚠️ 範圍必須與 `stock_repository` 的 `inOfficialUniverse` 一致——
  /// 兩邊算的若不是同一個母體,比例比較就沒有意義。
  Future<int> countActiveOfficialUniverse() async {
    final total = stockMaster.symbol.count();
    final query = selectOnly(stockMaster)
      ..addColumns([total])
      ..where(
        stockMaster.isActive.equals(true) &
            stockMaster.market.equals('TWSE') &
            stockMaster.symbol.length.equals(4) &
            stockMaster.symbol.like('00%').not(),
      );
    return (await query.getSingle()).read(total) ?? 0;
  }

  /// 將不在指定清單中的股票標記為下市（isActive = false）
  ///
  /// 回傳被標記為下市的股票數量
  Future<int> deactivateStocksNotIn(Set<String> activeSymbols) async {
    if (activeSymbols.isEmpty) return 0;

    final result =
        await (update(stockMaster)..where(
              (t) => t.isActive.equals(true) & t.symbol.isNotIn(activeSymbols),
            ))
            .write(const StockMasterCompanion(isActive: Value(false)));

    return result;
  }
}

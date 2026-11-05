import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/heatmap_dao.dart';
import 'package:daredevil/domain/models/heatmap.dart';

/// 大盤熱力圖的資料來源：組出分組計算的輸入（只讀資料庫）
class HeatmapRepository {
  HeatmapRepository(this._db);

  final AppDatabase _db;

  /// 該市場最新正式資料日的內容指紋；沒有正式資料時回 null
  Future<HeatmapFingerprint?> fingerprint(String market) =>
      _db.getHeatmapFingerprint(market);

  /// [market] 在 [date] 的價格列、兩個股數來源各自最新一筆（股數欄位為空的
  /// 來源不帶），以及自選∪持股。
  Future<HeatmapMarketInput> loadInput(String market, DateTime date) async {
    final rows = await _db.getHeatmapPriceRows(market, date);
    final symbols = [for (final r in rows) r.symbol];
    final foreign = await _db.getLatestShareholdingsBatch(symbols);
    final insider = await _db.getLatestInsiderHoldingsBatch(symbols);
    final mine = await _db.getWatchlistAndHoldingSymbols();

    HeatmapShares? shares(double? value, DateTime? asOf) =>
        value == null || asOf == null ? null : (shares: value, date: asOf);

    return HeatmapMarketInput(
      market: market,
      dataDate: DateContext.normalize(date),
      stocks: [
        for (final r in rows)
          HeatmapStockInput(
            symbol: r.symbol,
            name: r.name,
            industry: r.industry,
            close: r.close,
            priceChange: r.priceChange,
            foreign: shares(
              foreign[r.symbol]?.sharesIssued,
              foreign[r.symbol]?.date,
            ),
            insider: shares(
              insider[r.symbol]?.sharesIssued,
              insider[r.symbol]?.date,
            ),
          ),
      ],
      mine: mine,
    );
  }
}

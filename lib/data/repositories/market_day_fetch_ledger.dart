import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 一筆成功記錄的抓取
typedef LedgerRecord = ({
  MarketDataset dataset,
  String market,
  DateTime date,
  int rows,
});

/// 一輪更新（或一次修復工具執行）的盤後資料抓取記錄器
///
/// 由 repository 在**寫入資料的同一個 transaction** 內呼叫 [report]，回報實際
/// 寫入的市場、資料日、列數（事實由源頭回報，不由呼叫端回推）。只有全市場
/// 抓取會拿到 ledger；逐檔或部分股票的寫入路徑傳 null，不記錄。
///
/// [fetchedAt] 是本輪開始的台北時間，比實際請求早。它只可能讓判定偏向
/// 「未定案」，不會把初值誤判成定案。
///
/// ⚠️ 必須與呼叫它的 repository 共用同一個 [AppDatabase] 實例：狀態寫入要
/// 落在 repository 的 transaction 內，而 Drift 的 transaction 綁在實例上。
class MarketDayFetchLedger {
  MarketDayFetchLedger({required AppDatabase database, required this.fetchedAt})
    : _db = database;

  final AppDatabase _db;
  final DateTime fetchedAt;
  final Map<String, int> _stockCounts = {};
  final List<LedgerRecord> _recorded = [];

  List<LedgerRecord> get recorded => List.unmodifiable(_recorded);

  Future<bool> report({
    required MarketDataset dataset,
    required String market,
    required DateTime date,
    required int rows,
  }) async {
    final day = DateContext.normalize(date);
    final label = '${dataset.code}/$market ${DateContext.formatYmd(day)}';
    final stocks = _stockCounts[market] ??= await _db.countStocksByMarket(
      market,
    );
    final need = (stocks * dataset.minCoverageRatio).ceil();
    if (stocks == 0 || rows < need) {
      AppLogger.info('FetchLedger', '$label 寫入 $rows 列 < 門檻 $need，不記錄抓取狀態');
      return false;
    }
    if (dataset == MarketDataset.dayTrading) {
      // 當沖比例的分母是同日成交量；價格覆蓋不足時比例整片是 0，
      // 記成定案就永遠不會重抓（設計文件 §4.6）
      final priced = await _db.countPricesInDayAndMarket(day, market);
      final priceNeed = (stocks * ApiConfig.tradingBackfillMinCoverageRatio)
          .ceil();
      if (priced < priceNeed) {
        AppLogger.info(
          'FetchLedger',
          '$label 價格覆蓋不足（$priced < $priceNeed），不記錄當沖抓取狀態',
        );
        return false;
      }
    }
    await _db.upsertMarketDayFetch(
      dataset: dataset.code,
      market: market,
      date: day,
      fetchedAt: fetchedAt,
      rowCount: rows,
    );
    _recorded.add((dataset: dataset, market: market, date: day, rows: rows));
    return true;
  }
}

import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/price_candidate_filter.dart';

/// TWSE 上市股票價格資料來源
///
/// 封裝 TWSE API 呼叫與資料轉換邏輯。
class TwsePriceSource {
  TwsePriceSource({required TwseClient client}) : _client = client;

  /// 連續空月份上限，超過即推測為上市前，停止回溯
  static const _maxConsecutiveEmptyMonths = 3;

  final TwseClient _client;

  /// 從 TWSE API 取得指定月份的價格，轉換為 DB 格式
  ///
  /// **從最新月份往回抓取**（newest → oldest），有兩個好處：
  /// 1. 連續空月份早期終止：連續 3 個月無資料時推測為上市前，跳過更早月份
  /// 2. 優先取得最新資料：rate limit 時至少已取得近期資料
  ///
  /// API 請求間加入延遲避免 rate limit。
  Future<List<DailyPriceCompanion>> fetchMonthlyPrices({
    required String symbol,
    required List<DateTime> months,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final allPrices = <TwseDailyPrice>[];
    var consecutiveEmpty = 0;
    // 全滅偵測:單月失敗換部分資料是划算的,但「所有月份都失敗」再回空清單
    // 就會被上游(HistoricalPriceSyncer 退避記帳)誤讀成「成功但已無資料」,
    // 蓋下 30 天凍結——TWSE 格式變更的一個晚上可凍住整批上市股
    // (2026-06 STOCK_DAY_ALL 改 CSV 靜默失效有前科)。全滅必須拋錯。
    var anyMonthSucceeded = false;
    Object? lastError;

    // 從最新月份往回遍歷
    for (var i = months.length - 1; i >= 0; i--) {
      final month = months[i];
      try {
        final monthData = await _client.getStockMonthlyPrices(
          code: symbol,
          year: month.year,
          month: month.month,
        );
        anyMonthSucceeded = true;
        if (monthData.isEmpty) {
          consecutiveEmpty++;
          if (consecutiveEmpty >= _maxConsecutiveEmptyMonths) {
            AppLogger.debug(
              'TwsePriceSource',
              '$symbol: 連續 $consecutiveEmpty 個月無資料，推測為上市前，跳過剩餘 $i 個月',
            );
            break;
          }
        } else {
          consecutiveEmpty = 0;
          allPrices.addAll(monthData);
        }
      } on RateLimitException {
        AppLogger.warning('TwsePriceSource', '$symbol: 上市價格同步觸發 API 速率限制');
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        // 網路錯誤是不確定狀態（該月可能有資料），重置計數器避免誤判
        consecutiveEmpty = 0;
        lastError = e;
        AppLogger.warning(
          'TwsePriceSource',
          '$symbol: ${month.year}-${month.month} 月份價格取得失敗',
          e,
        );
      }

      if (i > 0) {
        await Future.delayed(
          const Duration(milliseconds: ApiConfig.priceBatchQueryDelayMs),
        );
      }
    }

    if (!anyMonthSucceeded && lastError != null) {
      throw DatabaseException('$symbol: 所有月份價格取得皆失敗', lastError);
    }

    // 過濾至請求的日期範圍
    return allPrices
        .where((p) => !p.date.isBefore(startDate) && !p.date.isAfter(endDate))
        .map((price) {
          return DailyPriceCompanion.insert(
            symbol: price.code,
            date: price.date,
            open: Value(price.open),
            high: Value(price.high),
            low: Value(price.low),
            close: Value(price.close),
            volume: Value(price.volume),
            priceChange: Value(price.change),
          );
        })
        .toList();
  }

  /// 取得全市場上市股票價格
  ///
  /// [date] 參數自 2026-06 起被 STOCK_DAY_ALL 端點忽略（永遠回最新日）
  /// ——歷史回補一律走 [fetchAllDailyPricesHistorical]（MI_INDEX）。
  Future<List<TwseDailyPrice>> fetchAllDailyPrices({DateTime? date}) {
    return _client.getAllDailyPrices(date: date);
  }

  /// 歷史全市場行情（MI_INDEX；backfill 用——STOCK_DAY_ALL 不支援歷史）
  Future<List<TwseDailyPrice>> fetchAllDailyPricesHistorical(DateTime date) {
    return _client.getAllDailyPricesHistorical(date);
  }

  /// 將原始上市股票資料轉換為 DB 格式（價格 + 股票主檔 + 候選股）
  ({
    List<DailyPriceCompanion> priceEntries,
    List<StockMasterCompanion> stockEntries,
    List<String> candidates,
    DateTime? dataDate,
  })
  processDailyPrices(List<TwseDailyPrice> prices) {
    final priceEntries = prices
        .where((price) => StockPatterns.isValidCode(price.code))
        .map((price) {
          return DailyPriceCompanion.insert(
            symbol: price.code,
            date: price.date,
            open: Value(price.open),
            high: Value(price.high),
            low: Value(price.low),
            close: Value(price.close),
            volume: Value(price.volume),
            priceChange: Value(price.change),
          );
        })
        .toList();

    final stockEntries = prices
        .where((p) => p.name.isNotEmpty && StockPatterns.isValidCode(p.code))
        .map((price) {
          return StockMasterCompanion.insert(
            symbol: price.code,
            name: price.name,
            market: MarketCode.twse,
            isActive: const Value(true),
          );
        })
        .toList();

    final candidates = quickFilterPrices(
      prices,
      getCode: (p) => p.code,
      getClose: (p) => p.close,
      getChange: (p) => p.change,
      getVolume: (p) => p.volume,
    );

    return (
      priceEntries: priceEntries,
      stockEntries: stockEntries,
      candidates: candidates,
      dataDate: prices.isNotEmpty ? prices.first.date : null,
    );
  }
}

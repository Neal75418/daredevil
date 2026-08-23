import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/safe_execution.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/domain/repositories/trading_repository.dart';

/// 交易資料 Repository
///
/// 處理：當沖、融資融券
class TradingRepository implements ITradingRepository {
  TradingRepository({
    required AppDatabase database,
    required TwseClient twseClient,
    required TpexClient tpexClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _twseClient = twseClient,
       _tpexClient = tpexClient,
       _clock = clock;

  final AppDatabase _db;
  final TwseClient _twseClient;
  final TpexClient _tpexClient;
  final AppClock _clock;

  /// 判定批次資料為「最新」的最低筆數門檻
  /// 若該日期已有超過此數量的資料，則跳過 API 呼叫
  static const _batchFreshnessThreshold = DataFreshness.twseBatchThreshold;

  // ==================================================
  // 當沖
  // ==================================================

  /// 取得當沖歷史資料
  @override
  Future<List<DayTradingEntry>> getDayTradingHistory(
    String symbol, {
    int days = 30,
  }) async {
    final startDate = _clock.now().subtract(
      Duration(days: days + DataFreshness.dayTradingBufferDays),
    );
    return _db.getDayTradingHistory(symbol, startDate: startDate);
  }

  /// 從 TWSE 同步全市場當沖資料（免費 API）
  ///
  /// 使用 TWSE 官方 API，無需 Token。
  /// 比透過 FinMind 逐檔同步快很多。
  ///
  /// 包含新鮮度檢查以避免不必要的 API 呼叫。
  /// 設定 [force] 為 true 可略過新鮮度檢查。
  @override
  Future<int> syncAllDayTradingFromTwse({
    DateTime? date,
    bool force = false,
  }) async {
    try {
      final targetDate = DateContext.normalize(date ?? _clock.now());

      // 新鮮度檢查：若已有目標日期資料則跳過
      if (!force) {
        // 分市場計數：不分市場會讓上櫃寫入的列把上市的閘門頂過門檻
        final existingCount = await _db.getDayTradingCountForDateAndMarket(
          targetDate,
          MarketCode.twse,
        );
        if (existingCount > _batchFreshnessThreshold) {
          return 0;
        }
      }

      // 1. 取得當沖資料（比例為 0，因為 API 不提供）
      final data = await _twseClient.getAllDayTradingData(date: targetDate);

      AppLogger.info(
        'TradingRepo',
        'TWSE 當沖原始筆數: ${data.length}，日期: $targetDate',
      );

      if (data.isEmpty) return 0;

      // `await` 不可省：Dart 的 `return future;` 在 try 內會**先離開 try**，
      // catch 收不到內部例外——DatabaseException 包裝形同虛設，且 Error 子型別
      // 會躲過上游 market_data_updater 的 `on Exception catch`，讓整個回補迴圈
      // 而非單日被中斷。實測 FK 787（新掛牌股尚未進 stock_master）會裸奔而出。
      return await _persistDayTrading(
        dataDate: targetDate,
        market: MarketCode.twse,
        items: [
          for (final item in data)
            (
              code: item.code,
              buy: item.buyVolume,
              sell: item.sellVolume,
              volume: item.totalVolume,
            ),
        ],
      );
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync day trading from TWSE', e);
    }
  }

  /// 當沖寫入的共用路徑（上市／上櫃）
  ///
  /// 兩市場的差異只在**取得原始資料的方式與日期來源**；比例計算、delete
  /// window、寫入與統計日誌完全相同，抽出共用避免兩份實作漂移。
  ///
  /// [dataDate] 已 normalize 的資料日。上市傳請求日（端點吃日期、且有
  /// 「回應日期≠請求日期就丟棄」的守衛）；上櫃傳**回應的日期**（端點無視請求
  /// 日期、永遠回最新交易日）。
  Future<int> _persistDayTrading({
    required DateTime dataDate,
    required String market,
    required List<({String code, double buy, double sell, double volume})>
    items,
  }) async {
    if (items.isEmpty) return 0;

    // 比例的分母來自價格表同日總量。取不到就給 0——0 在當沖語意下代表
    // 「無當沖」，而分母未知時給任何非零值都是編造。
    var prices = await _db.getPricesForDate(dataDate);
    if (prices.isEmpty) {
      final start = DateTime(dataDate.year, dataDate.month, dataDate.day);
      final end = start
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final result = await _db.getAllPricesInRange(
        startDate: start,
        endDate: end,
      );
      prices = result.values.expand((list) => list).toList();
    }
    final volumeMap = <String, double>{
      for (final p in prices)
        if (p.volume != null) p.symbol: p.volume!.toDouble(),
    };

    // 比例失真時第一個要看的數字：分母是從幾列價格取出來的。
    // 兩市場寫同一張表，但價格覆蓋可能只有一邊到位。
    AppLogger.info(
      'TradingRepo',
      '用於計算比例的價格資料: ${volumeMap.length} 筆 ($market, $dataDate)',
    );

    final entries = <DayTradingCompanion>[];
    for (final item in items) {
      if (!StockPatterns.isValidCode(item.code)) continue;

      final total = volumeMap[item.code] ?? 0;
      var ratio = total > 0 ? (item.volume / total) * 100 : 0.0;
      if (ratio > DataFreshness.dayTradingMaxValidRatio) {
        ratio = DataFreshness.dayTradingMaxValidRatio;
      }
      if (ratio < 0) ratio = 0;

      entries.add(
        DayTradingCompanion.insert(
          symbol: item.code,
          date: dataDate,
          buyVolume: Value(item.buy),
          sellVolume: Value(item.sell),
          dayTradingRatio: Value(ratio),
          tradeVolume: Value(item.volume),
        ),
      );
    }
    // **刻意不刪**：舊版上市路徑走的是 delete-then-insert，批次全被
    // isValidCode 濾掉時仍會執行刪除，把該市場當日資料清空卻不寫回任何東西
    // （例如某日回應全是權證）。這裡改為什麼都不做——沒東西可寫就不該動既有
    // 資料。上櫃路徑到不了這裡（client 端已先濾過），只有上市會踩到。
    if (entries.isEmpty) return 0;

    // 刪除舊記錄（歷史上 UTC/本地不一致造成的同日變體時間戳）。
    // 範圍限縮在本市場 ∪ 本次批次——見 deleteDayTradingForDateRange 的說明。
    final deleteStart = dataDate.subtract(
      const Duration(hours: DataFreshness.dayTradingDeleteWindowBeforeHours),
    );
    final deleteEnd = dataDate.add(
      const Duration(hours: DataFreshness.dayTradingDeleteWindowAfterHours),
    );
    await _db.transaction(() async {
      await _db.deleteDayTradingForDateRange(
        deleteStart,
        deleteEnd,
        market: market,
        batchSymbols: {for (final e in entries) e.symbol.value},
      );
      await _db.insertDayTradingData(entries);
    });

    final high = entries
        .where(
          (e) =>
              (e.dayTradingRatio.value ?? 0) >=
              DataFreshness.dayTradingHighDisplayRatio,
        )
        .toList();
    final extreme = entries
        .where(
          (e) =>
              (e.dayTradingRatio.value ?? 0) >=
              DataFreshness.dayTradingExtremeDisplayRatio,
        )
        .length;
    final zero = entries
        .where((e) => (e.dayTradingRatio.value ?? 0) == 0)
        .length;

    final label = market == MarketCode.twse ? '上市, TWSE' : '上櫃, TPEx';
    AppLogger.info(
      'TradingRepo',
      '當沖資料寫入 ${entries.length} 筆 ($label, $dataDate): '
          '高比例(>=60%)=${high.length}，極高(>=70%)=$extreme，零比例=$zero',
    );
    if (high.isNotEmpty) {
      AppLogger.info(
        'TradingRepo',
        '高當沖股票: ${high.map((e) => '${e.symbol.value}'
            '(${e.dayTradingRatio.value?.toStringAsFixed(1)}%)').join(', ')}',
      );
    }
    return entries.length;
  }

  /// 同步上櫃當沖（TPEx `/www/zh-tw/intraday/stat`，免費無額度）
  ///
  /// **日期由回應決定**：端點無視請求日期、永遠回最新交易日，故先取資料再依
  /// 其 `date` 做新鮮度檢查與寫入。照抄上市的「用請求日期寫入」會把最新資料
  /// 掛到錯誤的日子上，而且筆數正常、毫無訊號。
  ///
  /// 呼叫端不傳日期正是為此——簽章上就杜絕誤用。
  @override
  Future<int> syncAllDayTradingFromTpex({bool force = false}) async {
    try {
      // 端點免費且 client 端有快取，先抓再判新鮮度的成本可忽略
      final data = await _tpexClient.getAllDayTradingData();
      if (data.isEmpty) return 0;

      final dataDate = DateContext.normalize(data.first.date);

      if (!force) {
        final existing = await _db.getDayTradingCountForDateAndMarket(
          dataDate,
          MarketCode.tpex,
        );
        if (existing > _batchFreshnessThreshold) {
          AppLogger.info('TradingRepo', '上櫃當沖 $dataDate 已有 $existing 筆，跳過');
          return 0;
        }
      }

      // `await` 不可省：Dart 的 `return future;` 在 try 內會**先離開 try**，
      // catch 收不到內部例外——DatabaseException 包裝形同虛設，且 Error 子型別
      // 會躲過上游 market_data_updater 的 `on Exception catch`，讓整個回補迴圈
      // 而非單日被中斷。實測 FK 787（新掛牌股尚未進 stock_master）會裸奔而出。
      return await _persistDayTrading(
        dataDate: dataDate,
        market: MarketCode.tpex,
        items: [
          for (final d in data)
            (
              code: d.code,
              buy: d.buyVolume,
              sell: d.sellVolume,
              volume: d.totalVolume,
            ),
        ],
      );
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync day trading from TPEx', e);
    }
  }

  // ==================================================
  // 融資融券 - TWSE API
  // ==================================================

  /// 取得融資融券歷史資料
  @override
  Future<List<MarginTradingEntry>> getMarginTradingHistory(
    String symbol, {
    int days = 30,
  }) async {
    final startDate = _clock.now().subtract(
      Duration(days: days + DataFreshness.marginTradingBufferDays),
    );
    return _db.getMarginTradingHistory(symbol, startDate: startDate);
  }

  /// 從 TWSE/TPEX 同步全市場融資融券資料（免費 API）
  ///
  /// 使用 TWSE + TPEX 官方 API，無需 Token。
  /// 並行取得上市與上櫃融資融券資料。
  ///
  /// 包含新鮮度檢查以避免不必要的 API 呼叫。
  /// 設定 [force] 為 true 可略過新鮮度檢查。
  @override
  Future<int?> syncAllMarginTrading({
    DateTime? date,
    bool force = false,
  }) async {
    try {
      final targetDate = date ?? _clock.now();

      // 新鮮度檢查：若已有目標日期資料則跳過
      // 提高閾值至 1500 以涵蓋上市+上櫃股票
      if (!force) {
        final existingCount = await _db.getMarginTradingCountForDate(
          targetDate,
        );
        if (existingCount > DataFreshness.fullMarketThreshold) {
          AppLogger.debug('TradingRepo', '融資融券資料已快取 ($existingCount 筆)，跳過同步');
          return null;
        }
      }

      // 並行取得上市與上櫃融資融券資料（錯誤隔離，允許部分成功）
      // safeAwait 立即包裹原始 Future，避免 unhandled async error
      // TPEx 融資融券 API 有 T+1 延遲：傳入今日日期會回傳空資料。
      // 省略 d 參數時 API 自動回傳最新可用資料（與 TWSE 行為一致）。
      final (twseData, tpexData) = await safeAwaitPair(
        _twseClient.getAllMarginTradingData(),
        _tpexClient.getAllMarginTradingData(),
        firstDefault: <TwseMarginTrading>[],
        secondDefault: <TpexMarginTrading>[],
        tag: 'TradingRepo',
        firstDescription: '上市融資融券取得失敗，繼續處理上櫃',
        secondDescription: '上櫃融資融券取得失敗，繼續處理上市',
      );

      if (twseData.isEmpty && tpexData.isEmpty) return 0;

      // 取得已知股票代碼集合，過濾非 stocks 表中的代碼以避免 FK 違規
      final activeStocks = await _db.getAllActiveStocks();
      final validSymbols = activeStocks.map((s) => s.symbol).toSet();

      // 建立融資融券 entries（TWSE 和 TPEx 單位皆為張，無需轉換）。
      // named 參數：六個連續 double 用 positional 時任兩個對調
      // 編譯器不會抓、資料靜默寫錯欄位。
      MarginTradingCompanion buildEntry({
        required String code,
        required DateTime date,
        required double marginBuy,
        required double marginSell,
        required double marginBalance,
        required double shortBuy,
        required double shortSell,
        required double shortBalance,
      }) {
        return MarginTradingCompanion.insert(
          symbol: code,
          date: date,
          marginBuy: Value(marginBuy),
          marginSell: Value(marginSell),
          marginBalance: Value(marginBalance),
          shortBuy: Value(shortBuy),
          shortSell: Value(shortSell),
          shortBalance: Value(shortBalance),
        );
      }

      final twseEntries = twseData
          .where(
            (item) =>
                StockPatterns.isValidCode(item.code) &&
                validSymbols.contains(item.code),
          )
          .map(
            (item) => buildEntry(
              code: item.code,
              date: item.date,
              marginBuy: item.marginBuy,
              marginSell: item.marginSell,
              marginBalance: item.marginBalance,
              shortBuy: item.shortBuy,
              shortSell: item.shortSell,
              shortBalance: item.shortBalance,
            ),
          )
          .toList();

      final tpexEntries = tpexData
          .where(
            (item) =>
                StockPatterns.isValidCode(item.code) &&
                validSymbols.contains(item.code),
          )
          .map(
            (item) => buildEntry(
              code: item.code,
              date: item.date,
              marginBuy: item.marginBuy,
              marginSell: item.marginSell,
              marginBalance: item.marginBalance,
              shortBuy: item.shortBuy,
              shortSell: item.shortSell,
              shortBalance: item.shortBalance,
            ),
          )
          .toList();

      // 合併並寫入（transaction 保護避免部分寫入）
      final allEntries = [...twseEntries, ...tpexEntries];
      await _db.transaction(() async {
        await _db.insertMarginTradingData(allEntries);
      });

      AppLogger.info(
        'TradingRepo',
        '融資融券同步: ${allEntries.length} 筆 (上市 ${twseEntries.length}, 上櫃 ${tpexEntries.length})',
      );

      return allEntries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to sync margin trading from TWSE/TPEX',
        e,
      );
    }
  }

  /// 回補指定歷史交易日、指定市場的融資融券（詳細語意見介面註解）
  @override
  Future<({int twseRows, int tpexRows})> backfillMarginTradingByDate({
    required DateTime date,
    required Set<String> markets,
  }) async {
    const empty = (twseRows: 0, tpexRows: 0);
    if (markets.isEmpty) return empty;
    try {
      final targetDate = DateContext.normalize(date);

      // 只抓缺漏的市場（重寫已存在的市場會讓 caller 誤判為有進度）。
      // 明確傳日期（與每日路徑相反）；錯誤隔離，允許單邊成功。
      final twseFuture = markets.contains(MarketCode.twse)
          ? safeAwait(
              _twseClient.getAllMarginTradingData(date: targetDate),
              <TwseMarginTrading>[],
              tag: 'TradingRepo',
              description: '上市融資融券回補失敗，繼續處理上櫃',
            )
          : Future.value(<TwseMarginTrading>[]);
      final tpexFuture = markets.contains(MarketCode.tpex)
          ? safeAwait(
              _tpexClient.getAllMarginTradingData(date: targetDate),
              <TpexMarginTrading>[],
              tag: 'TradingRepo',
              description: '上櫃融資融券回補失敗，繼續處理上市',
            )
          : Future.value(<TpexMarginTrading>[]);

      final twseData = await twseFuture;
      final tpexData = await tpexFuture;
      if (twseData.isEmpty && tpexData.isEmpty) return empty;

      final activeStocks = await _db.getAllActiveStocks();
      final validSymbols = activeStocks.map((s) => s.symbol).toSet();

      // 端點失效防護：只留「entry 自身日期 == 請求日期」的列。端點若無視
      // date 參數回最新交易日，整批被丟棄（回 0），不會寫出錯誤日期的資料。
      bool keep(String code, DateTime entryDate) =>
          StockPatterns.isValidCode(code) &&
          validSymbols.contains(code) &&
          DateContext.normalize(entryDate) == targetDate;

      MarginTradingCompanion companion({
        required String code,
        required double marginBuy,
        required double marginSell,
        required double marginBalance,
        required double shortBuy,
        required double shortSell,
        required double shortBalance,
      }) => MarginTradingCompanion.insert(
        symbol: code,
        date: targetDate,
        marginBuy: Value(marginBuy),
        marginSell: Value(marginSell),
        marginBalance: Value(marginBalance),
        shortBuy: Value(shortBuy),
        shortSell: Value(shortSell),
        shortBalance: Value(shortBalance),
      );

      final twseEntries = [
        for (final item in twseData)
          if (keep(item.code, item.date))
            companion(
              code: item.code,
              marginBuy: item.marginBuy,
              marginSell: item.marginSell,
              marginBalance: item.marginBalance,
              shortBuy: item.shortBuy,
              shortSell: item.shortSell,
              shortBalance: item.shortBalance,
            ),
      ];
      final tpexEntries = [
        for (final item in tpexData)
          if (keep(item.code, item.date))
            companion(
              code: item.code,
              marginBuy: item.marginBuy,
              marginSell: item.marginSell,
              marginBalance: item.marginBalance,
              shortBuy: item.shortBuy,
              shortSell: item.shortSell,
              shortBalance: item.shortBalance,
            ),
      ];

      final entries = [...twseEntries, ...tpexEntries];
      if (entries.isEmpty) {
        // 只列出**有抓**的市場，避免「上市 0 筆」被誤讀成日期不符
        final detail = [
          if (markets.contains(MarketCode.twse)) '上市 ${twseData.length}',
          if (markets.contains(MarketCode.tpex)) '上櫃 ${tpexData.length}',
        ].join(', ');
        AppLogger.warning(
          'TradingRepo',
          '融資融券回補 ${DateContext.formatYmd(targetDate)}: '
              '端點回應無該日資料（$detail 筆皆非目標日）',
        );
        return empty;
      }

      await _db.transaction<void>(() async {
        await _db.insertMarginTradingData(entries);
      });

      AppLogger.info(
        'TradingRepo',
        '融資融券回補 ${DateContext.formatYmd(targetDate)}: '
            '上市 ${twseEntries.length}, 上櫃 ${tpexEntries.length} 筆',
      );
      return (twseRows: twseEntries.length, tpexRows: tpexEntries.length);
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to backfill margin trading for ${DateContext.formatYmd(date)}',
        e,
      );
    }
  }
}

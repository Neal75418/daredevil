import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/repositories/fundamental_repository.dart';

/// 基本面資料 Repository（營收、本益比、股價淨值比、殖利率）
class FundamentalRepository implements IFundamentalRepository {
  FundamentalRepository({
    required AppDatabase db,
    required FinMindClient finMind,
    required TwseClient twse,
    required TpexClient tpex,
    required MopsClient mops,
    AppClock clock = const SystemClock(),
  }) : _db = db,
       _finMind = finMind,
       _twse = twse,
       _tpex = tpex,
       _mops = mops,
       _clock = clock;

  final AppDatabase _db;
  final FinMindClient _finMind;
  final TwseClient _twse;
  final TpexClient _tpex;

  /// 月營收公布期漸進來源(舊版 MOPS)。required:update_service_factory
  /// 漏接 optional client 導致功能靜默不執行的前科(見 stock_repository
  /// 的 _twseClient 註解),新 client 一律編譯期強制。
  final MopsClient _mops;
  final AppClock _clock;

  /// 同步 API 資料的通用模板方法
  ///
  /// 自動處理：
  /// - 空資料檢查
  /// - RateLimitException 重拋
  /// - 一般異常記錄
  ///
  /// 範例：
  /// ```dart
  /// return _syncDataTemplate(
  ///   operationName: '月營收',
  ///   symbol: symbol,
  ///   fetchData: () => _finMind.getMonthlyRevenue(...),
  ///   mapToCompanion: (data) => data.map(...).toList(),
  ///   persistData: (entries) => _db.insertMonthlyRevenue(entries),
  /// );
  /// ```
  Future<int> _syncDataTemplate<T, C>({
    required String operationName,
    String? symbol,
    required Future<List<T>> Function() fetchData,
    required List<C> Function(List<T>) mapToCompanion,
    required Future<void> Function(List<C>) persistData,
  }) async {
    try {
      final data = await fetchData();
      if (data.isEmpty) return 0;

      final entries = mapToCompanion(data);
      await persistData(entries);
      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      // 之前 return 0 會讓 caller 把「DB/parse 失敗」當成「同步 0 筆」，
      // FundamentalSyncer 把錯誤降級為 info log 而不上報 ctx.result.errors，
      // 下游 EPS/ROE/dividend rule 靜默退化。改 throw DatabaseException 讓
      // upstream catch (e) 仍可優雅降級但保留 cause + 真實 stack。
      final symbolInfo = symbol != null ? ': $symbol' : '';
      throw DatabaseException('Failed to sync $operationName$symbolInfo', e);
    }
  }

  /// 同步單檔股票的月營收資料
  ///
  /// 回傳同步筆數
  @override
  Future<int> syncMonthlyRevenue({
    required String symbol,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _syncDataTemplate(
      operationName: '月營收',
      symbol: symbol,
      fetchData: () => _finMind.getMonthlyRevenue(
        stockId: symbol,
        startDate: DateContext.formatYmd(startDate),
        endDate: DateContext.formatYmd(endDate),
      ),
      mapToCompanion: (data) {
        // 計算成長率
        final withGrowth = FinMindRevenue.calculateGrowthRates(data);

        // 轉換為 Database 資料
        return withGrowth.map((r) {
          final date = DateTime(r.revenueYear, r.revenueMonth);
          return MonthlyRevenueCompanion.insert(
            symbol: symbol,
            date: date,
            revenueYear: r.revenueYear,
            revenueMonth: r.revenueMonth,
            revenue: r.revenue,
            momGrowth: Value(r.momGrowth),
            yoyGrowth: Value(r.yoyGrowth),
          );
        }).toList();
      },
      persistData: (entries) => _db.insertMonthlyRevenue(entries),
    );
  }

  /// 同步單檔股票的估值資料（本益比/股價淨值比/殖利率）
  ///
  /// 回傳同步筆數
  @override
  Future<int> syncValuationData({
    required String symbol,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _syncDataTemplate(
      operationName: '估值資料',
      symbol: symbol,
      fetchData: () => _finMind.getPERData(
        stockId: symbol,
        startDate: DateContext.formatYmd(startDate),
        endDate: DateContext.formatYmd(endDate),
      ),
      mapToCompanion: (data) => data.map((r) {
        // 正規化到當日 00:00：r.date 解析失敗時 fallback 的 _clock.now() 含時間戳，
        // 會讓 PK (symbol,date) 每次不同、無法去重（同 valuation 重複膨脹根因）。
        final parsedDate = DateContext.normalize(
          DateTime.tryParse(r.date) ?? _clock.now(),
        );
        return StockValuationCompanion.insert(
          symbol: symbol,
          date: parsedDate,
          per: Value(r.per),
          pbr: Value(r.pbr),
          dividendYield: Value(r.dividendYield),
        );
      }).toList(),
      persistData: (entries) => _db.insertValuationData(entries),
    );
  }

  /// 使用 TWSE BWIBBU_d 同步全市場估值資料（免費、無限制）
  ///
  /// 取代個別 FinMind 呼叫以進行每日更新。
  /// 注意：此方法僅同步上市股票，上櫃股票需使用 [syncOtcValuation]。
  @override
  Future<int> syncAllMarketValuation(
    DateTime date, {
    bool force = false,
  }) async {
    try {
      final data = await _twse.getAllStockValuation(date: date);

      if (data.isEmpty) return 0;

      // 轉換為 Database 資料
      // 過濾無效資料（通常 PE > 0，殖利率 >= 0）
      final entries = data.map((r) {
        return StockValuationCompanion.insert(
          symbol: r.code,
          date: r.date,
          per: Value(r.per),
          pbr: Value(r.pbr),
          dividendYield: Value(r.dividendYield),
        );
      }).toList();

      await _db.insertValuationData(entries);

      AppLogger.info('FundamentalRepo', '估值同步: ${entries.length} 筆 (上市, TWSE)');

      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync TWSE all-market valuation', e);
    }
  }

  /// 補充上櫃股票的估值資料（使用 TPEX OpenAPI 批次取得）
  ///
  /// [symbols] 為要同步的上櫃股票代碼清單。
  /// 使用 TPEX 免費 OpenAPI 一次取得所有上櫃股票估值資料。
  /// 設定 [force] 為 true 可略過新鮮度檢查。
  ///
  /// 回傳成功同步的股票數量。
  @override
  Future<int> syncOtcValuation(
    List<String> symbols, {
    DateTime? date,
    bool force = false,
  }) async {
    if (symbols.isEmpty) return 0;

    final targetDate = date ?? _clock.now();

    // 新鮮度檢查：過濾掉已有近期估值資料的股票（3 天內視為新鮮）
    List<String> symbolsToSync = symbols;
    if (!force) {
      final freshThreshold = targetDate.subtract(
        const Duration(days: DataFreshness.otcValuationFreshDays),
      );
      final needSync = <String>[];

      final latestMap = await _db.getLatestValuationsBatch(symbols);
      for (final symbol in symbols) {
        final latest = latestMap[symbol];
        // 若無資料或資料過舊則需要同步
        if (latest == null || latest.date.isBefore(freshThreshold)) {
          needSync.add(symbol);
        }
      }
      symbolsToSync = needSync;

      if (symbolsToSync.isEmpty) {
        AppLogger.info('FundamentalRepo', '上櫃估值: 所有股票已有最新資料，跳過同步');
        return 0;
      }

      AppLogger.info(
        'FundamentalRepo',
        '上櫃估值新鮮度檢查: ${symbols.length} 檔中 ${symbolsToSync.length} 檔需同步',
      );
    }

    // 使用 TPEX OpenAPI 批次取得全市場估值（1 次 API 呼叫）
    final symbolSet = symbolsToSync.toSet();

    try {
      final allData = await _tpex.getAllValuation(date: targetDate);

      if (allData.isEmpty) {
        AppLogger.warning('FundamentalRepo', 'TPEX 估值 API 回傳空資料');
        return 0;
      }

      // 篩選出需要的股票
      final entries = <StockValuationCompanion>[];
      for (final item in allData) {
        if (!symbolSet.contains(item.code)) continue;

        entries.add(
          StockValuationCompanion.insert(
            symbol: item.code,
            date: item.date,
            per: Value(item.per),
            pbr: Value(item.pbr),
            dividendYield: Value(item.dividendYield),
          ),
        );
      }

      // 批次寫入資料庫
      if (entries.isNotEmpty) {
        await _db.insertValuationData(entries);
      }

      final skippedCount = symbols.length - symbolsToSync.length;
      AppLogger.info(
        'FundamentalRepo',
        '上櫃估值同步完成: ${entries.length}/${symbolsToSync.length} 檔 '
            '(API calls: 1, 跳過: $skippedCount)',
      );

      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync TPEX OTC valuation batch', e);
    }
  }

  /// 使用 TWSE Open Data 同步全市場月營收（免費、無限制）
  ///
  /// 取代個別 FinMind 呼叫以進行最新月份更新。
  /// API 端點：https://openapi.twse.com.tw/v1/opendata/t187ap05_L
  /// 注意：此方法僅同步上市股票，上櫃股票需使用 [syncOtcRevenue]。
  ///
  /// 回傳：同步筆數，或 null 表示跳過（已有資料）
  @override
  Future<int?> syncAllMarketRevenue(DateTime date, {bool force = false}) async {
    try {
      // 註：OpenData 僅回傳「最新」月份
      // 無法指定日期。我們只抓取可用的資料

      final data = await _twse.getAllMonthlyRevenue();

      if (data.isEmpty) return 0;

      // 版本檢查：檢查是否已有該月資料
      // 避免重複 API 呼叫和 Database 寫入
      final sample = data.first;
      final dataYear = sample.year;
      final dataMonth = sample.month;

      if (!force) {
        // 只數上市：本方法抓的是 `getAllMonthlyRevenue()`（上市），上櫃
        // 由 syncOtcCandidatesFundamentals 另外寫入。用不分市場的總數
        // 判斷，等於讓上櫃的筆數替上市背書 —— 實測 2026/06 全市場 1,316
        // 筆裡有 249 筆是上櫃，而上市自身 1,067 對門檻只有 6.7% 餘裕。
        final existingCount = await _db.getRevenueCountForYearMonth(
          dataYear,
          dataMonth,
          market: MarketCode.twse,
        );
        // 門檻 1000：上市非 ETF 約 1,080 檔，實測涵蓋率 98%
        if (existingCount > DataFreshness.revenueRecordThreshold) {
          AppLogger.debug(
            'FundamentalRepo',
            '$dataYear/$dataMonth 上市營收已快取 ($existingCount 筆)，跳過同步',
          );
          return null;
        }
      }

      // 過濾有效資料
      final stockList = await _db.getAllActiveStocks();
      final validSymbols = stockList.map((s) => s.symbol).toSet();
      final validData = data
          .where((r) => validSymbols.contains(r.code))
          .toList();

      AppLogger.info(
        'FundamentalRepo',
        '營收同步 $dataYear/$dataMonth: ${validData.length}/${data.length} 檔 (上市, TWSE)',
      );

      final entries = validData.map((r) {
        final recordDate = DateTime(r.year, r.month);
        return MonthlyRevenueCompanion.insert(
          symbol: r.code,
          date: recordDate,
          revenueYear: r.year,
          revenueMonth: r.month,
          revenue: r.revenue,
          momGrowth: Value(r.momGrowth),
          yoyGrowth: Value(r.yoyGrowth),
          ytdYoyGrowth: Value(r.ytdYoyGrowth),
        );
      }).toList();

      await _db.insertMonthlyRevenue(entries);
      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync TWSE all-market revenue', e);
    }
  }

  /// 補充上櫃股票的營收資料（使用 TPEX OpenAPI）
  ///
  /// [symbols] 為要同步的上櫃股票代碼清單。
  /// 使用 TPEX OpenAPI 一次取得所有股票營收，免費無限制。
  /// 設定 [force] 為 true 可略過新鮮度檢查。
  ///
  /// 回傳成功同步的股票數量。
  @override
  Future<int> syncOtcRevenue(List<String> symbols, {bool force = false}) async {
    if (symbols.isEmpty) return 0;

    // 新鮮度檢查：過濾掉已追上「上一個月」的股票
    //
    // **不能拿當下年月比對**：台股月營收於次月 10 日前公布，DB 裡能有的最新月
    // **永遠不會是當月**。原本比對「當下年月」，條件恆為 false → 每次
    // 更新都判定全部需要同步、白打 TPEX。
    //
    // **刻意用「上一個月」而非 [TaiwanCalendar.expectedLatestRevenueMonth]**：
    // 那個函式在 1–10 日會保守退兩個月，因為它服務的是 FinMind 回補（誤判
    // 「缺月」要付額度）。這裡的來源是 TPEX 全市場端點——免費、已 memoize，
    // 誤抓的代價是一次快取內呼叫；退兩個月的代價卻是每月 1–10 日這十天
    // 整批上櫃股跳過同步，比上市路徑（`syncAllMarketRevenue` 走筆數門檻，
    // 會跟著公布進度走）落後一個月。用 M-1 則在公布期逐輪重試、自動收斂。
    //
    // 時鐘用 `_clock.now()`：原本收的 `date` 參數在 coordinator 會被校正成
    // 實際價格資料日（見 `UpdateService._syncPricesAndHistory`），那是「資料
    // 屬於哪天」，不是「現在幾號」；拿它判公布進度會在假日或補跑時算錯，
    // 故該參數已移除。
    List<String> symbolsToSync = symbols;
    if (!force) {
      final now = _clock.now();
      final expected = DateTime(now.year, now.month - 1, 1);
      final expectedKey = expected.year * 100 + expected.month;
      final needSync = <String>[];

      final latestMap = await _db.getLatestMonthlyRevenuesBatch(symbols);
      for (final symbol in symbols) {
        final latest = latestMap[symbol];
        // 已追上（或超前）應公布月即算新鮮
        final isFresh =
            latest != null &&
            (latest.revenueYear * 100 + latest.revenueMonth) >= expectedKey;
        if (!isFresh) {
          needSync.add(symbol);
        }
      }
      symbolsToSync = needSync;

      if (symbolsToSync.isEmpty) {
        AppLogger.info('FundamentalRepo', '上櫃營收: 所有股票已有應公布的最新月，跳過同步');
        return 0;
      }

      AppLogger.info(
        'FundamentalRepo',
        '上櫃營收新鮮度檢查: ${symbols.length} 檔中 ${symbolsToSync.length} 檔需同步',
      );
    }

    // 使用 TPEX OpenAPI 一次取得所有股票營收（免費無限制）
    final symbolSet = symbolsToSync.toSet();

    try {
      final allData = await _tpex.getAllMonthlyRevenue();

      if (allData.isEmpty) {
        AppLogger.warning('FundamentalRepo', 'TPEX 營收 API 回傳空資料');
        return 0;
      }

      var successCount = 0;
      final entries = <MonthlyRevenueCompanion>[];

      for (final item in allData) {
        if (!symbolSet.contains(item.code)) continue;

        entries.add(
          MonthlyRevenueCompanion.insert(
            symbol: item.code,
            date: item.date,
            revenueYear: item.revenueYear,
            revenueMonth: item.revenueMonth,
            revenue: item.revenue,
            momGrowth: Value(item.momGrowth),
            yoyGrowth: Value(item.yoyGrowth),
            ytdYoyGrowth: Value(item.ytdYoyGrowth),
          ),
        );
        successCount++;
      }

      // 批次寫入資料庫
      if (entries.isNotEmpty) {
        await _db.insertMonthlyRevenue(entries);
      }

      final skippedCount = symbols.length - symbolsToSync.length;
      AppLogger.info(
        'FundamentalRepo',
        '上櫃營收同步完成: $successCount/${symbolsToSync.length} 檔 '
            '(TPEX OpenAPI, 跳過: $skippedCount)',
      );

      return successCount;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync TPEX OTC revenue batch', e);
    }
  }

  /// 公布期漸進營收同步(舊版 MOPS,每月 1~14 日)。
  ///
  /// TWSE openapi 彙總表是月批式(申報期結束才切月),這裡在申報期間
  /// 逐日吃 MOPS 的漸進 CSV——營收訊號公布當晚即觸發,不等 10 日後
  /// 補考。與 openapi 同單位(千元,2026-08-03 台泥 6 月值逐位元對帳),
  /// 走同一個 upsert,兩源天然可互換。
  ///
  /// 回傳:寫入筆數;窗口外/全部跳過/來源掛掉 → null。
  /// **fail-soft**:mopsov 是官方舊版過渡站,可能隨時關站——任何錯誤
  /// 只記 warning,不得中斷更新管線(退回等 openapi 的現狀,零下行)。
  Future<int?> syncInProgressRevenue(DateTime date) async {
    // 窗口與目標月用**真實今天**而非傳入的校正交易日(2026-08-05 複審
    // Low #5):月初逢非交易日時校正日是上月末(8/1 週六→7/31、元旦→
    // 12/31),day>14 導致公布首日整段跳過——「公布當晚觸發」的承諾
    // 在每月 1~2 日打折,元旦年年必發生。申報窗口是日曆概念,跟交易日
    // 校正無關。
    final now = _clock.now();
    if (now.day > ApiConfig.mopsRevenueWindowLastDay) return null;

    // 目標月 = 上個月(Dart DateTime 月 0 自動正規化為去年 12 月)
    final target = DateTime(now.year, now.month - 1);

    var total = 0;
    var wrote = false;
    // 窗口內一律抓、不設覆蓋門檻跳過(2026-08-05 修):上櫃沒有月批全量源
    // 接手(openapi 只涵蓋上市),若以覆蓋數提前跳過,8/10 壓線申報的上櫃
    // 公司會永遠缺漏。省下的只是一次免費請求,代價卻是清單不完整——
    // upsert 冪等且兩源數值逐位元一致,重複寫零風險。
    for (final mopsMarket in MopsMarket.values) {
      try {
        final rows = await _mops.getInProgressRevenue(
          year: target.year,
          month: target.month,
          market: mopsMarket,
        );
        if (rows.isEmpty) continue;

        final stockList = await _db.getAllActiveStocks();
        final validSymbols = stockList.map((st) => st.symbol).toSet();
        final entries = rows
            .where((r) => validSymbols.contains(r.code))
            .map(
              (r) => MonthlyRevenueCompanion.insert(
                symbol: r.code,
                date: DateTime(r.year, r.month),
                revenueYear: r.year,
                revenueMonth: r.month,
                revenue: r.revenue,
                momGrowth: Value(r.momGrowth),
                yoyGrowth: Value(r.yoyGrowth),
                ytdYoyGrowth: Value(r.ytdYoyGrowth),
              ),
            )
            .toList();
        if (entries.isEmpty) continue;

        await _db.insertMonthlyRevenue(entries);
        total += entries.length;
        wrote = true;
      } catch (e) {
        // 含 RateLimit/Network:MOPS 無額度概念,且為選配增強源,
        // 一律 fail-soft——這是與其他 syncer 慣例的刻意偏離
        AppLogger.warning(
          'FundamentalRepo',
          'MOPS 公布期營收同步失敗(${mopsMarket.name}),退回等 openapi',
          e,
        );
      }
    }

    if (wrote) {
      AppLogger.info(
        'FundamentalRepo',
        'MOPS 公布期營收: ${target.year}/${target.month} 寫入 $total 筆',
      );
    }
    return wrote ? total : null;
  }

  /// 同步單檔股票的損益表資料（含 EPS、營收、毛利等）
  ///
  /// 從 FinMind API 取得近 2 年的季度損益表資料並寫入 DB。
  /// 新鮮度檢查為發布行事曆感知（[TaiwanCalendar.expectedLatestReportQuarter]），
  /// 已有應發布的最新一季即跳過。
  @override
  Future<int> syncFinancialStatements({
    required String symbol,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // 新鮮度檢查：已有「此刻應已發布的最新一季」則跳過。
      // 不能用「距今 N 天」啟發式——財報日期是季度截止日，發布後只有
      // ~2-6 週會通過天數檢查，其餘時間每次更新都重抓全部候選股。
      final latestDate = await _db.getLatestFinancialDataDate(symbol, 'INCOME');
      final expectedQuarter = TaiwanCalendar.expectedLatestReportQuarter(
        _clock.now(),
      );
      if (latestDate != null && !latestDate.isBefore(expectedQuarter)) {
        return 0;
      }

      final data = await _finMind.getFinancialStatements(
        stockId: symbol,
        startDate: DateContext.formatYmd(startDate),
        endDate: DateContext.formatYmd(endDate),
      );
      if (data.isEmpty) return 0;

      final entries = <FinancialDataCompanion>[];
      for (final item in data) {
        try {
          entries.add(
            FinancialDataCompanion.insert(
              symbol: symbol,
              date: DateContext.parseQuarterDate(item.date),
              statementType: 'INCOME',
              dataType: item.type,
              value: Value(item.value),
              originName: Value(item.origin),
            ),
          );
        } catch (e) {
          AppLogger.debug(
            'FundamentalRepo',
            '$symbol: 跳過無法解析的財報項目 (date=${item.date})',
          );
        }
      }

      await _db.insertFinancialData(entries);
      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to sync financial statements: $symbol',
        e,
      );
    }
  }
}

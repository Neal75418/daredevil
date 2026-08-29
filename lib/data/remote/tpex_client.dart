import 'package:dio/dio.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/lru_cache.dart';
import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/data/models/tpex/models.dart';
import 'package:daredevil/data/models/twse/exright_preannouncement.dart';
import 'package:daredevil/data/models/twse/market_wide_financial.dart';
import 'package:daredevil/data/models/twse/quarterly_report_entry.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/data/remote/insider_holding_aggregator.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';

export 'package:daredevil/data/models/tpex/models.dart';

/// 台灣證券櫃檯買賣中心 (TPEX/OTC) API 客戶端
///
/// 提供免費存取上櫃股票市場資料。
/// 與 TwseClient 架構一致，用於取得上櫃股票的價格和法人資料。
/// 無需認證。
///
/// API 來源:
/// - 每日股價: https://www.tpex.org.tw/web/stock/aftertrading/daily_close_quotes/stk_quote_result.php
/// - 法人買賣: https://www.tpex.org.tw/web/stock/3insti/daily_trade/3itrade_hedge_result.php
class TpexClient {
  TpexClient({Dio? dio, AppClock clock = const SystemClock()})
    : _dio = dio ?? MarketClientMixin.createDio(ApiEndpoints.tpexBaseUrl),
      _clock = clock;

  /// 當沖凍結偵測的時間來源。可注入：守衛比對「資料日 vs 現在」，測試用
  /// 固定 payload（存檔的真實回應）時牆鐘一走過 stale 窗就整批變紅——
  /// 2026-08-29 實發：8/23 寫的測試因 fixture 日期滿 8 天全數炸掉。
  final AppClock _clock;

  static const String _tag = 'TPEX';

  /// 「回應未帶日期」的哨兵值——回補守衛用，見 [getAllMarginTradingData]。
  /// 刻意選一個不可能是交易日的日期，讓「回應沒帶日期」與「日期不符」收斂到
  /// 同一條 fail-closed 路徑。
  static final DateTime _unknownDateSentinel = DateTime.utc(1970);

  final Dio _dio;
  final LruCache<String, dynamic> _cache = LruCache(
    maxSize: CacheConfig.marketClientCacheMaxSize,
    ttl: const Duration(minutes: CacheConfig.marketClientCacheTtlMin),
  );

  /// 新版 afterTrading/otc（歷史回補替代端點）→ [TpexDailyPrice] 列表。
  ///
  /// 舊 daily_close_quotes 端點自 2026-06 起忽略歷史 date（永遠回最新日，
  /// 與 TWSE STOCK_DAY_ALL 同症狀）；/www/zh-tw/afterTrading/otc?type=EW
  /// 經 2026-07-12 活體驗證支援歷史日期。
  ///
  /// row 佈局：[代號, 名稱, 收盤, 漲跌(帶號、可為「除息」等非數字), 開,
  /// 高, 低, 成交股數, 成交金額, 成交筆數, ...]。
  /// 回應日期 ≠ [requestedDate] → 回空（端點失效防護）。public 供測試。
  static List<TpexDailyPrice> parseAfterTradingOtcDailyPrices(
    Map<dynamic, dynamic> json,
    DateTime requestedDate,
  ) {
    final expected =
        '${requestedDate.year.toString().padLeft(4, '0')}'
        '${requestedDate.month.toString().padLeft(2, '0')}'
        '${requestedDate.day.toString().padLeft(2, '0')}';
    if (json['date']?.toString() != expected) return const [];

    final tables = json['tables'];
    if (tables is! List || tables.isEmpty) return const [];
    final first = tables.first;
    if (first is! Map) return const [];
    final rows = first['data'];
    if (rows is! List) return const [];

    final result = <TpexDailyPrice>[];
    for (final raw in rows) {
      if (raw is! List || raw.length < 8) continue;
      final code = raw[0]?.toString().trim() ?? '';
      if (code.isEmpty) continue;
      result.add(
        TpexDailyPrice(
          date: requestedDate,
          code: code,
          name: raw[1]?.toString().trim() ?? '',
          close: TwParseUtils.parsePrice(raw[2]?.toString()),
          change: TwParseUtils.parseFormattedDouble(raw[3]?.toString()),
          open: TwParseUtils.parsePrice(raw[4]?.toString()),
          high: TwParseUtils.parsePrice(raw[5]?.toString()),
          low: TwParseUtils.parsePrice(raw[6]?.toString()),
          volume: TwParseUtils.parseFormattedDouble(raw[7]?.toString()),
        ),
      );
    }
    return result;
  }

  /// 歷史全市場行情（新版 afterTrading/otc；backfill 用）。
  Future<List<TpexDailyPrice>> getAllDailyPricesHistorical(DateTime date) {
    return MarketClientMixin.executeRequest(_tag, '歷史全市場價格', () async {
      final dateStr =
          '${date.year.toString().padLeft(4, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.day.toString().padLeft(2, '0')}';
      final cacheKey = 'otcDailyHist:$dateStr';
      final cached = _cache.get(cacheKey) as List<TpexDailyPrice>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        '/www/zh-tw/afterTrading/otc',
        queryParameters: {'date': dateStr, 'type': 'EW', 'response': 'json'},
      );
      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }
      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '歷史全市場價格',
      );
      if (data == null) return <TpexDailyPrice>[];

      final result = parseAfterTradingOtcDailyPrices(data, date);
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 取得最新交易日所有上櫃股票價格（OHLCV）
  ///
  /// 端點: [ApiEndpoints.tpexDailyPricesAll]（daily_close_quotes）。
  /// ⚠️ date 參數自 2026-06 起被端點忽略（永遠回最新日）——歷史回補
  /// 走 [getAllDailyPricesHistorical]。
  Future<List<TpexDailyPrice>> getAllDailyPrices({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '全市場價格', () async {
      final cacheKey = date != null
          ? 'dailyPrices:${TwParseUtils.formatDateCompact(date)}'
          : 'dailyPrices';
      final cached = _cache.get(cacheKey) as List<TpexDailyPrice>?;
      if (cached != null) return cached;

      final targetDate = date ?? DateTime.now();
      final rocDateStr = TwParseUtils.toRocDateString(targetDate);

      final response = await _dio.get(
        ApiEndpoints.tpexDailyPricesAll,
        queryParameters: {'l': 'zh-tw', 'd': rocDateStr, 'o': 'json'},
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '全市場價格',
      );
      if (data == null) return [];

      final table = MarketClientMixin.extractTpexTable(
        data,
        targetDate,
        _tag,
        '全市場價格',
      );
      if (table == null) return [];

      final result = MarketClientMixin.parseRows(
        rows: table.rows,
        parser: (row) => _parseDailyPriceRow(row, table.date),
        tag: _tag,
        operation: '全市場價格',
        date: table.date,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析每日價格資料列
  ///
  /// 列格式: [代號, 名稱, 收盤, 漲跌, 開盤, 最高, 最低, 均價, 成交股數, 成交金額, 成交筆數, 最後買價, 最後賣價, 發行股數, 次日參考價, 次日漲停價, 次日跌停價]
  TpexDailyPrice? _parseDailyPriceRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 11,
      tag: _tag,
      operation: '每日價格',
      parser: () {
        final code = row[0]?.toString().trim() ?? '';
        // isTpexPriceCode：含上櫃 ETF（2026-07-23 稽核修復，與歷史回補一致）
        if (code.isEmpty || !StockPatterns.isTpexPriceCode(code)) return null;
        return TpexDailyPrice(
          date: date,
          code: code,
          name: row[1]?.toString().trim() ?? '',
          close: TwParseUtils.parsePrice(row[2]),
          change: TwParseUtils.parseFormattedDouble(row[3]),
          open: TwParseUtils.parsePrice(row[4]),
          high: TwParseUtils.parsePrice(row[5]),
          low: TwParseUtils.parsePrice(row[6]),
          volume: TwParseUtils.parseFormattedDouble(row[8]),
          turnover: TwParseUtils.parseFormattedDouble(row[9]),
        );
      },
    );
  }

  /// 取得所有上櫃股票的法人買賣超資料
  ///
  /// 端點: /web/stock/3insti/daily_trade/3itrade_hedge_result.php
  Future<List<TpexInstitutional>> getAllInstitutionalData({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '法人資料', () async {
      final cacheKey = date != null
          ? 'institutional:${TwParseUtils.formatDateCompact(date)}'
          : 'institutional';
      final cached = _cache.get(cacheKey) as List<TpexInstitutional>?;
      if (cached != null) return cached;

      final targetDate = date ?? DateTime.now();
      final rocDateStr = TwParseUtils.toRocDateString(targetDate);

      final response = await _dio.get(
        ApiEndpoints.tpexInstitutional,
        queryParameters: {'l': 'zh-tw', 'd': rocDateStr, 't': 'D', 'o': 'json'},
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '法人資料',
      );
      if (data == null) return [];

      final table = MarketClientMixin.extractTpexTable(
        data,
        targetDate,
        _tag,
        '法人資料',
      );
      if (table == null) return [];

      final result = MarketClientMixin.parseRows(
        rows: table.rows,
        parser: (row) => _parseInstitutionalRow(row, table.date),
        tag: _tag,
        operation: '法人資料',
        date: table.date,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析法人資料列
  ///
  /// TPEX 欄位格式 (24 欄):
  /// [0] 代號, [1] 名稱
  /// [2-4] 外資及陸資(不含外資自營商) 買/賣/淨
  /// [5-7] 外資自營商 買/賣/淨
  /// [8-10] 外資及陸資(合計) 買/賣/淨
  /// [11-13] 投信 買/賣/淨
  /// [14-16] 自營商(自行) 買/賣/淨（[16] → dealerSelfNet，不含避險）
  /// [17-19] 自營商(避險) 買/賣/淨
  /// [20-22] 自營商(合計) 買/賣/淨
  /// [23] 三大法人買賣超股數合計
  ///
  /// 注意：TPEX API 回傳的是「股數」，存入資料庫時需除以 1000 轉換為「張」
  TpexInstitutional? _parseInstitutionalRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 24,
      tag: _tag,
      operation: '法人資料',
      parser: () {
        final code = row[0]?.toString().trim() ?? '';
        if (code.isEmpty || !StockPatterns.isTpexCode(code)) return null;
        return TpexInstitutional(
          date: date,
          code: code,
          name: row[1]?.toString().trim() ?? '',
          // [2-4] 外陸資(不含外資自營)——與 TWSE T86 主欄位同口徑
          // （2026-07-23 稽核修復：原取 [8-10] 合計含外資自營，造成同一
          // DB 欄上市/上櫃兩種口徑靜默不一致）
          foreignBuy: TwParseUtils.parseFormattedDouble(row[2]) ?? 0,
          foreignSell: TwParseUtils.parseFormattedDouble(row[3]) ?? 0,
          foreignNet: TwParseUtils.parseFormattedDouble(row[4]) ?? 0,
          investmentTrustBuy: TwParseUtils.parseFormattedDouble(row[11]) ?? 0,
          investmentTrustSell: TwParseUtils.parseFormattedDouble(row[12]) ?? 0,
          investmentTrustNet: TwParseUtils.parseFormattedDouble(row[13]) ?? 0,
          dealerBuy: TwParseUtils.parseFormattedDouble(row[20]) ?? 0,
          dealerSell: TwParseUtils.parseFormattedDouble(row[21]) ?? 0,
          dealerNet: TwParseUtils.parseFormattedDouble(row[22]) ?? 0,
          // [16] 自營商(自行) 買賣超 — 不含避險，供真實主動方向 streak
          dealerSelfNet: TwParseUtils.parseFormattedDouble(row[16]) ?? 0,
          totalNet: TwParseUtils.parseFormattedDouble(row[23]) ?? 0,
        );
      },
    );
  }

  /// 取得三大法人買賣金額統計（市場總計）
  ///
  /// 端點: /web/stock/3insti/3insti_summary/3itrdsum_result.php
  /// 回傳外資、投信、自營商的買賣金額（元），可用於大盤總覽顯示
  ///
  /// [date] 可選，指定日期。省略則取最新。
  Future<TpexInstitutionalAmounts?> getInstitutionalAmounts({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '法人金額統計', () async {
      final targetDate = date ?? DateTime.now();
      final rocDateStr = TwParseUtils.toRocDateString(targetDate);

      final response = await _dio.get(
        ApiEndpoints.tpexInstitutionalAmounts,
        queryParameters: {'l': 'zh-tw', 'd': rocDateStr, 't': 'D', 'o': 'json'},
      );

      if (response.statusCode != 200) return null;

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '法人金額統計',
      );
      if (data == null) return null;

      final table = MarketClientMixin.extractTpexTable(
        data,
        targetDate,
        _tag,
        '法人金額統計',
      );
      if (table == null) return null;

      final actualDate = table.date;
      final rows = table.rows;

      // data 結構:
      // [["外資及陸資合計", "買進金額", "賣出金額", "買賣超"],
      //  ["　外資及陸資(不含自營商)", ...],
      //  ["　外資自營商", ...],
      //  ["投信", ...],
      //  ["自營商合計", ...], ...]
      double foreignNet = 0;
      double trustNet = 0;
      double dealerNet = 0;

      for (final row in rows) {
        if (row is! List || row.length < 4) continue;
        final name = row[0]?.toString().trim() ?? '';
        final netAmount = TwParseUtils.parseFormattedDouble(row[3]) ?? 0;

        // 使用「外資及陸資(不含自營商)」而非合計，與 TWSE 一致
        if (name.contains('外資及陸資') && name.contains('不含')) {
          foreignNet = netAmount;
        } else if (name == '投信') {
          trustNet = netAmount;
        } else if (name == '自營商合計') {
          dealerNet = netAmount;
        }
      }

      return TpexInstitutionalAmounts(
        date: actualDate,
        foreignNet: foreignNet,
        trustNet: trustNet,
        dealerNet: dealerNet,
      );
    });
  }

  /// 取得所有上櫃股票的估值資料（本益比、股價淨值比、殖利率）
  ///
  /// 使用 TPEX OpenAPI，免費無限制。
  /// 端點: /openapi/v1/tpex_mainboard_peratio_analysis
  ///
  /// 回傳所有上櫃股票的估值資料，一次 API 呼叫取得全市場。
  Future<List<TpexValuation>> getAllValuation({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '估值資料', () async {
      const cacheKey = 'valuation';
      final cached = _cache.get(cacheKey) as List<TpexValuation>?;
      if (cached != null) return cached;

      // 估值 API 不回傳統一交易日，且過去 fallback 用 DateTime.now()（含時間戳）→
      // 同日多次同步會產生不同 PK、無法去重。正規化到當日 00:00（同 daily_price 口徑）。
      final targetDate = DateContext.normalize(date ?? DateTime.now());

      // TPEX OpenAPI 只回傳最新資料，不接受日期參數
      final response = await _dio.get(
        ApiEndpoints.tpexValuation,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '估值資料: 非預期資料型別 (expected List)');
        return [];
      }

      final results = <TpexValuation>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = _parseValuationItem(item, targetDate);
        if (parsed != null) results.add(parsed);
      }

      // 估值 API 不回傳統一日期欄位，使用第一筆資料的日期或 targetDate
      final effectiveDate = results.isNotEmpty
          ? results.first.date
          : targetDate;
      final dateFormatted = TwParseUtils.formatDateYmd(effectiveDate);
      AppLogger.info(_tag, '估值資料: ${results.length} 筆 ($dateFormatted)');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 解析估值資料項目
  ///
  /// JSON 格式:
  /// {
  ///   "Date": "1150126",           // 民國年月日 YYYMMDD
  ///   "SecuritiesCompanyCode": "1240",
  ///   "CompanyName": "茂達",
  ///   "PriceEarningRatio": "12.34",
  ///   "DividendPerShare": "2.50",
  ///   "YieldRatio": "3.45",
  ///   "PriceBookRatio": "1.23"
  /// }
  TpexValuation? _parseValuationItem(
    Map<String, dynamic> json,
    DateTime fallbackDate,
  ) {
    try {
      final code = json['SecuritiesCompanyCode']?.toString().trim() ?? '';
      if (code.isEmpty) return null;

      // 過濾非股票代碼（上櫃股票為 4 碼數字）
      if (!StockPatterns.isTpexCode(code)) return null;

      // 解析日期（使用共用驗證方法，無效時使用 fallback）
      final actualDate =
          TwParseUtils.parseCompactRocDate(json['Date']?.toString()) ??
          fallbackDate;

      // 解析數值（"N/A" 視為 null）
      double? parsePer(dynamic value) {
        if (value == null || value == 'N/A' || value == '') return null;
        return double.tryParse(value.toString());
      }

      return TpexValuation(
        date: actualDate,
        code: code,
        name: json['CompanyName']?.toString().trim() ?? '',
        per: parsePer(json['PriceEarningRatio']),
        pbr: parsePer(json['PriceBookRatio']),
        dividendYield: parsePer(json['YieldRatio']),
      );
    } catch (e) {
      AppLogger.warning(_tag, '解析估值資料失敗', e);
      return null;
    }
  }

  /// 取得所有上櫃股票的融資融券資料
  ///
  /// 端點: /web/stock/margin_trading/margin_sbl/margin_sbl_result.php
  Future<List<TpexMarginTrading>> getAllMarginTradingData({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '融資融券', () async {
      final cacheKey = date != null
          ? 'marginTrading:${TwParseUtils.formatDateCompact(date)}'
          : 'marginTrading';
      final cached = _cache.get(cacheKey) as List<TpexMarginTrading>?;
      if (cached != null) return cached;

      final queryParams = <String, String>{'l': 'zh-tw', 'o': 'json'};
      if (date != null) {
        queryParams['d'] = TwParseUtils.toRocDateString(date);
      }

      final response = await _dio.get(
        ApiEndpoints.tpexMarginTrading,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '融資融券',
      );
      if (data == null) return [];

      // extractTpexTable 在回應缺日期表頭時會 fallback 到傳入的日期。回補
      // （明確指定日期）時若拿請求日期當 fallback，「回應沒帶日期」的列會被
      // 蓋上請求日期、騙過下游的日期過濾（fail open）。改傳 sentinel：回應
      // 沒帶日期 → table.date == sentinel ≠ 請求日期 → 下方守衛擋掉。
      final table = MarketClientMixin.extractTpexTable(
        data,
        date != null ? _unknownDateSentinel : DateTime.now(),
        _tag,
        '融資融券',
      );
      if (table == null) return [];

      // 端點失效防護（fail closed）：回應日期不符或無從判定 → 整批丟棄
      if (date != null && !DateContext.isSameDay(table.date, date)) {
        AppLogger.warning(_tag, '融資融券回應日期 ${table.date} ≠ 請求 $date，丟棄');
        return [];
      }

      final result = MarketClientMixin.parseRows(
        rows: table.rows,
        parser: (row) => _parseMarginTradingRow(row, table.date),
        tag: _tag,
        operation: '融資融券',
        date: table.date,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析融資融券資料列
  ///
  /// margin_balance 端點欄位格式 (20 欄，單位：張):
  /// [0] 代號, [1] 名稱
  /// [2] 前資餘額, [3] 資買, [4] 資賣, [5] 現償, [6] 資餘額,
  /// [7] 資屬證金, [8] 資使用率(%), [9] 資限額
  /// [10] 前券餘額, [11] 券賣, [12] 券買, [13] 券償, [14] 券餘額,
  /// [15] 券屬證金, [16] 券使用率(%), [17] 券限額
  /// [18] 資券相抵(張), [19] 備註
  ///
  /// 單位與 TWSE 相同（張），無需額外轉換。
  TpexMarginTrading? _parseMarginTradingRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 15,
      tag: _tag,
      operation: '融資融券',
      parser: () {
        final code = row[0]?.toString().trim() ?? '';
        if (code.isEmpty || !StockPatterns.isTpexCode(code)) return null;
        return TpexMarginTrading(
          date: date,
          code: code,
          name: row[1]?.toString().trim() ?? '',
          marginBuy: TwParseUtils.parseFormattedDouble(row[3]) ?? 0,
          marginSell: TwParseUtils.parseFormattedDouble(row[4]) ?? 0,
          marginBalance: TwParseUtils.parseFormattedDouble(row[6]) ?? 0,
          shortBuy: TwParseUtils.parseFormattedDouble(row[12]) ?? 0,
          shortSell: TwParseUtils.parseFormattedDouble(row[11]) ?? 0,
          shortBalance: TwParseUtils.parseFormattedDouble(row[14]) ?? 0,
        );
      },
    );
  }

  // ==================================================
  // Killer Features API (免費 OpenAPI)
  // ==================================================

  /// 取得上櫃注意股票清單
  ///
  /// 使用 TPEX OpenAPI，免費無限制。
  /// 端點: /openapi/v1/tpex_trading_warning_information
  ///
  /// 回傳交易量異常、價格異常波動的股票清單。
  Future<List<TpexTradingWarning>> getTradingWarnings() {
    return MarketClientMixin.executeRequest(_tag, '注意股票', () async {
      final response = await _dio.get(
        ApiEndpoints.tpexTradingWarning,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '注意股票: 非預期資料型別');
        return [];
      }

      final results = <TpexTradingWarning>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = _parseTradingWarningItem(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '注意股票: ${results.length} 筆');
      return results;
    });
  }

  /// 解析注意股票項目
  ///
  /// 無效日期時回傳 null，避免污染資料庫。
  TpexTradingWarning? _parseTradingWarningItem(Map<String, dynamic> json) {
    try {
      final code = json['SecuritiesCompanyCode']?.toString().trim() ?? '';
      if (code.isEmpty) return null;

      // 解析公告日期（格式: "1150126" -> 民國 115 年 01 月 26 日）
      // TPEX OpenAPI 使用 "Date" 欄位
      final dateStr = json['Date']?.toString();
      final date = TwParseUtils.parseCompactRocDate(dateStr);
      if (date == null) {
        AppLogger.debug(_tag, '注意股票日期解析失敗: code=$code, date=$dateStr');
        return null;
      }

      return TpexTradingWarning(
        date: date,
        code: code,
        // TPEX OpenAPI 欄位: TradingInformation（交易資訊說明）
        reasonDescription: json['TradingInformation']?.toString().trim(),
        warningType: 'ATTENTION',
      );
    } catch (e) {
      AppLogger.debug(_tag, '注意股票項目解析失敗: $e');
      return null;
    }
  }

  /// 取得上櫃處置股票清單
  ///
  /// 使用 TPEX OpenAPI，免費無限制。
  /// 端點: /openapi/v1/tpex_disposal_information
  ///
  /// 回傳交易受限制的股票清單。
  /// 上櫃除權除息預告表（tpex_exright_prepost,免額度)——帶確定交易日
  ///
  /// 與 TWSE TWT48U_ALL 同構,為行事曆除權息事件的上櫃資料源。
  Future<List<ExRightPreannouncement>> getExRightPreannouncements() {
    return MarketClientMixin.executeRequest(_tag, '除權息預告', () async {
      final response = await _dio.get(
        ApiEndpoints.tpexExRightPreannouncement,
        options: Options(headers: {'Accept': 'application/json'}),
      );
      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }
      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '除權息預告: 非預期資料型別');
        return <ExRightPreannouncement>[];
      }
      final results = data
          .whereType<Map<String, dynamic>>()
          .map(ExRightPreannouncement.tryFromTpexJson)
          .whereType<ExRightPreannouncement>()
          .toList();
      AppLogger.info(_tag, '除權息預告: ${results.length} 筆');
      return results;
    });
  }

  Future<List<TpexTradingWarning>> getDisposalInfo() {
    return MarketClientMixin.executeRequest(_tag, '處置股票', () async {
      final response = await _dio.get(
        ApiEndpoints.tpexDisposal,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '處置股票: 非預期資料型別');
        return [];
      }

      final results = <TpexTradingWarning>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = _parseDisposalItem(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '處置股票: ${results.length} 筆');
      return results;
    });
  }

  /// 解析處置股票項目
  ///
  /// 無效日期時回傳 null，避免污染資料庫。
  TpexTradingWarning? _parseDisposalItem(Map<String, dynamic> json) {
    try {
      final code = json['SecuritiesCompanyCode']?.toString().trim() ?? '';
      if (code.isEmpty) return null;

      // 解析公告日期（必要欄位）
      // TPEX OpenAPI 使用 "Date" 欄位
      final dateStr = json['Date']?.toString();
      final date = TwParseUtils.parseCompactRocDate(dateStr);
      if (date == null) {
        AppLogger.debug(_tag, '處置股票日期解析失敗: code=$code, date=$dateStr');
        return null;
      }

      // 解析處置起訖日期（從 DispositionPeriod 欄位，格式: "1150126~1150206"）
      DateTime? startDate;
      DateTime? endDate;
      final periodStr = json['DispositionPeriod']?.toString();
      if (periodStr != null && periodStr.contains('~')) {
        final parts = periodStr.split('~');
        if (parts.length == 2) {
          startDate = TwParseUtils.parseCompactRocDate(parts[0].trim());
          endDate = TwParseUtils.parseCompactRocDate(parts[1].trim());
        }
      }

      return TpexTradingWarning(
        date: date,
        code: code,
        // TPEX OpenAPI 欄位: DispositionReasons（處置原因）
        reasonDescription: json['DispositionReasons']?.toString().trim(),
        // TPEX OpenAPI 欄位: DisposalCondition（處置措施說明）
        disposalMeasures: json['DisposalCondition']?.toString().trim(),
        disposalStartDate: startDate,
        disposalEndDate: endDate,
        warningType: 'DISPOSAL',
      );
    } catch (e) {
      AppLogger.debug(_tag, '處置股票項目解析失敗: $e');
      return null;
    }
  }

  /// 取得上櫃董監持股資料（彙總版）
  ///
  /// 使用 TPEX OpenAPI，免費無限制。
  /// 1. 從 mopsfin_t187ap03_O 取得已發行股數
  /// 2. 從 mopsfin_t187ap11_O 取得個別董監持股記錄
  /// 3. 彙總計算每家公司的董監持股比例和質押比例
  ///
  /// 回傳彙總後的董監事持股資料（每家公司一筆）。
  Future<List<TpexInsiderHolding>> getInsiderHoldings() {
    return MarketClientMixin.executeRequest(_tag, '董監持股', () async {
      // 1. 取得已發行股數
      final stockInfoResponse = await _dio.get(
        ApiEndpoints.tpexStockInfo,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      final issuedSharesMap = stockInfoResponse.statusCode == 200
          ? InsiderHoldingAggregator.parseIssuedShares(
              stockInfoResponse.data,
              codeKey: 'SecuritiesCompanyCode',
              sharesKey: 'IssueShares',
            )
          : <String, double>{};

      AppLogger.debug(_tag, '已發行股數: ${issuedSharesMap.length} 家公司');

      // 2. 取得個別董監持股記錄
      final response = await _dio.get(
        ApiEndpoints.tpexInsiderHolding,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200) {
        // 董監持股 API 回傳 List（Dio responseType: json 會自動解析）
        final data = response.data;
        if (data is! List) {
          AppLogger.warning(_tag, '董監持股: 非預期資料型別');
          return [];
        }

        // 3-4. 彙總 + 比例計算（共用 aggregator，與 TWSE 同一套業務規則）
        final companyData = InsiderHoldingAggregator.aggregateRecords(
          data,
          codeFilter: StockPatterns.isTpexCode,
        );
        final results =
            InsiderHoldingAggregator.buildRatios(companyData, issuedSharesMap)
                .map(
                  (r) => TpexInsiderHolding(
                    date: r.date,
                    code: r.code,
                    insiderRatio: r.insiderRatio,
                    pledgeRatio: r.pledgeRatio,
                    sharesIssued: r.sharesIssued,
                  ),
                )
                .toList();

        AppLogger.info(_tag, '董監持股彙總: ${results.length} 家公司');
        return results;
      }

      throw ApiException(
        '$_tag OpenAPI error: ${response.statusCode}',
        response.statusCode,
      );
    });
  }

  /// 取得櫃買指數歷史資料
  ///
  /// 使用 TPEX OpenAPI `/v1/tpex_index`，免費無需認證。
  /// 回傳近月每日 OHLC + Change 資料，轉換為 `TwseMarketIndex` 複用現有 model。
  ///
  /// JSON 格式：
  /// ```json
  /// [{"Date":"20260312","Open":"293.80","High":"295.00","Low":"290.50",
  ///   "Close":"291.20","Change":"-2.60",...}]
  /// ```
  Future<List<TwseMarketIndex>> getTpexIndex() {
    return MarketClientMixin.executeRequest(_tag, '櫃買指數', () async {
      const cacheKey = 'tpexIndex';
      final cached = _cache.get(cacheKey) as List<TwseMarketIndex>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexIndex,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '櫃買指數: 非預期資料型別');
        return [];
      }

      final results = <TwseMarketIndex>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = _parseTpexIndexItem(item);
        if (parsed != null) results.add(parsed);
      }

      // 按日期升序排列（最舊在前），與 TWSE index history 一致
      results.sort((a, b) => a.date.compareTo(b.date));

      AppLogger.info(_tag, '櫃買指數: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 解析櫃買指數項目
  TwseMarketIndex? _parseTpexIndexItem(Map<String, dynamic> json) {
    try {
      final dateStr = json['Date']?.toString();
      if (dateStr == null || dateStr.length != 8) return null;

      final year = int.tryParse(dateStr.substring(0, 4));
      final month = int.tryParse(dateStr.substring(4, 6));
      final day = int.tryParse(dateStr.substring(6, 8));
      if (year == null || month == null || day == null) return null;

      final date = DateTime(year, month, day);
      final close = double.tryParse(json['Close']?.toString() ?? '');
      final change = double.tryParse(json['Change']?.toString() ?? '');
      if (close == null) return null;

      final changeVal = change ?? 0;
      final prevClose = close - changeVal;
      final changePct = prevClose != 0 ? (changeVal / prevClose) * 100 : 0.0;

      return TwseMarketIndex(
        date: date,
        name: '櫃買指數',
        close: close,
        change: changeVal,
        changePercent: changePct,
      );
    } catch (e) {
      AppLogger.debug(_tag, '解析櫃買指數項目失敗: $e');
      return null;
    }
  }

  /// 取得上櫃公司每月營業收入彙總表
  ///
  /// 使用 TPEX OpenAPI，免費無限制。
  /// 端點: /openapi/v1/mopsfin_t187ap05_O
  ///
  /// 回傳所有上櫃公司的月營收資料，包含月增率和年增率。
  /// 一次 API 呼叫取得全市場資料，取代 FinMind 批次 API。
  Future<List<TpexMonthlyRevenue>> getAllMonthlyRevenue() {
    return MarketClientMixin.executeRequest(_tag, '月營收', () async {
      const cacheKey = 'monthlyRevenue';
      final cached = _cache.get(cacheKey) as List<TpexMonthlyRevenue>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexMonthlyRevenue,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '月營收: 非預期資料型別');
        return [];
      }

      final results = <TpexMonthlyRevenue>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = _parseMonthlyRevenueItem(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '月營收: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 解析月營收項目
  ///
  /// JSON 格式:
  /// {
  ///   "出表日期": "1150117",
  ///   "資料年月": "11412",           // 民國年月 YYYMM
  ///   "公司代號": "1240",
  ///   "公司名稱": "茂生農經",
  ///   "營業收入-當月營收": "240962",  // 千元
  ///   "營業收入-上月比較增減(%)": "8.26",
  ///   "營業收入-去年同月增減(%)": "-7.42",
  ///   ...
  /// }
  TpexMonthlyRevenue? _parseMonthlyRevenueItem(Map<String, dynamic> json) {
    // 解析邏輯已搬入 model(2026-08-13,含累計年增的自洽政策),
    // 這裡只留 try/catch 與記錄——model 對壞形狀回 null 不丟
    try {
      return TpexMonthlyRevenue.fromJson(json);
    } catch (e) {
      AppLogger.debug(_tag, '月營收項目解析失敗: $e');
      return null;
    }
  }

  /// 取得上櫃已宣告股利
  ///
  /// 使用 TPEX OpenAPI (mopsfin_t187ap39_O)。
  /// 回傳所有已宣告的除權息資料，含除息交易日、現金/股票股利。
  Future<List<TpexDeclaredDividend>> getDeclaredDividends() {
    return MarketClientMixin.executeRequest(_tag, '已宣告股利', () async {
      const cacheKey = 'declaredDividend';
      final cached = _cache.get(cacheKey) as List<TpexDeclaredDividend>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexDeclaredDividend,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '已宣告股利: 非預期資料型別');
        return [];
      }

      final results = <TpexDeclaredDividend>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TpexDeclaredDividend.tryFromJson(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '已宣告股利: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上櫃內部人股權轉讓申報資料
  ///
  /// 使用 TPEX OpenAPI (t187ap12_O)。
  /// 回傳董監事、經理人、大股東的股權轉讓申報記錄。
  Future<List<TpexInsiderTransfer>> getInsiderTransfers() {
    return MarketClientMixin.executeRequest(_tag, '內部人轉讓', () async {
      const cacheKey = 'insiderTransfer';
      final cached = _cache.get(cacheKey) as List<TpexInsiderTransfer>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexInsiderTransfer,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '內部人轉讓: 非預期資料型別');
        return [];
      }

      final results = <TpexInsiderTransfer>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TpexInsiderTransfer.tryFromJson(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '內部人轉讓: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上櫃最新一季綜合損益表(mopsfin_t187ap06_O_*,六業別合併)。
  ///
  /// 上櫃全市場資產負債表(mopsfin_t187ap07_O_*,六業別合併)
  ///
  /// 與 [TwseClient.getAllBalanceSheets] 同構。2026-08-16 接入,取代
  /// FinMind 逐檔的 BalanceSheet。⚠️ 金額單位千元,由 model 轉成元。
  Future<List<MarketWideFinancial>> getAllBalanceSheets() {
    return MarketClientMixin.executeRequest(_tag, '資產負債表', () async {
      const cacheKey = 'balanceSheets';
      final cached = _cache.get(cacheKey) as List<MarketWideFinancial>?;
      if (cached != null) return cached;

      final results = <MarketWideFinancial>[];
      var okVariants = 0;
      Object? firstError;
      for (final suffix in ApiEndpoints.quarterlyReportIndustrySuffixes) {
        try {
          final response = await _dio.get(
            ApiEndpoints.tpexBalanceSheet(suffix),
          );
          if (response.statusCode != 200) {
            throw ApiException(
              '$_tag OpenData API error: ${response.statusCode}',
              response.statusCode,
            );
          }
          final data = response.data;
          if (data is! List) {
            AppLogger.warning(_tag, '資產負債表($suffix): 非預期資料型別');
            continue;
          }
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            results.addAll(MarketWideFinancial.parseBalance(item));
          }
          okVariants++;
        } on RateLimitException {
          rethrow;
        } catch (e) {
          AppLogger.warning(_tag, '資產負債表($suffix)失敗,其餘業別照收', e);
          firstError ??= e;
        }
      }
      if (okVariants == 0 && firstError != null) throw firstError;

      AppLogger.info(
        _tag,
        '資產負債表: ${results.length} 筆'
        '($okVariants/${ApiEndpoints.quarterlyReportIndustrySuffixes.length} 業別)',
      );
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 語意與 [TwseClient.getQuarterlyReports] 完全同構(欄名差異由
  /// QuarterlyReportEntry 的雙 key fallback 吸收);per-variant 隔離
  /// 同款:單業別失敗照收其餘、全滅才拋、RateLimit 直接 rethrow。
  Future<List<QuarterlyReportEntry>> getQuarterlyReports() {
    return MarketClientMixin.executeRequest(_tag, '季報', () async {
      const cacheKey = 'quarterlyReports';
      final cached = _cache.get(cacheKey) as List<QuarterlyReportEntry>?;
      if (cached != null) return cached;

      final results = <QuarterlyReportEntry>[];
      var okVariants = 0;
      Object? firstError;
      for (final suffix in ApiEndpoints.quarterlyReportIndustrySuffixes) {
        try {
          final response = await _dio.get(
            ApiEndpoints.tpexQuarterlyReport(suffix),
            options: Options(headers: {'Accept': 'application/json'}),
          );
          if (response.statusCode != 200) {
            throw ApiException(
              '$_tag OpenAPI error: ${response.statusCode}',
              response.statusCode,
            );
          }
          final data = response.data;
          if (data is! List) {
            AppLogger.warning(_tag, '季報($suffix): 非預期資料型別');
            continue;
          }
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final parsed = QuarterlyReportEntry.tryFromJson(item);
            if (parsed != null) results.add(parsed);
          }
          okVariants++;
        } on RateLimitException {
          rethrow;
        } catch (e) {
          AppLogger.warning(_tag, '季報($suffix)失敗,其餘業別照收', e);
          firstError ??= e;
        }
      }
      if (okVariants == 0 && firstError != null) throw firstError;
      AppLogger.info(
        _tag,
        '季報: ${results.length} 筆($okVariants/'
        '${ApiEndpoints.quarterlyReportIndustrySuffixes.length} 業別)',
      );
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上櫃融券賣出排行
  ///
  /// 使用 TPEX OpenAPI (tpex_margin_trading_short_sell)。
  /// 回傳融券賣出排名 Top 20，含前日餘額、當日餘額及融券賣出量。
  Future<List<TpexShortSellRanking>> getShortSellRanking() {
    return MarketClientMixin.executeRequest(_tag, '融券排行', () async {
      const cacheKey = 'shortSellRanking';
      final cached = _cache.get(cacheKey) as List<TpexShortSellRanking>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexShortSellRanking,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '融券排行: 非預期資料型別');
        return [];
      }

      final results = <TpexShortSellRanking>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TpexShortSellRanking.tryFromJson(item);
        if (parsed != null) results.add(parsed);
      }

      // 按排名排序
      results.sort((a, b) => a.rank.compareTo(b.rank));

      AppLogger.info(_tag, '融券排行: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上櫃股東會日程
  ///
  /// 使用 TPEX OpenAPI (t187ap41_O)。
  /// 回傳股東會開會日期、地點、是否改選董監、電子投票。
  Future<List<TpexShareholderMeeting>> getShareholderMeetings() {
    return MarketClientMixin.executeRequest(_tag, '股東會日程', () async {
      const cacheKey = 'shareholderMeeting';
      final cached = _cache.get(cacheKey) as List<TpexShareholderMeeting>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexShareholderMeeting,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '股東會日程: 非預期資料型別');
        return [];
      }

      final results = <TpexShareholderMeeting>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TpexShareholderMeeting.tryFromJson(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '股東會日程: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上櫃產業別 EPS 資料
  ///
  /// 使用 TPEX OpenAPI (mopsfin_t187ap14_O)。
  /// 回傳各產業公司的基本每股盈餘、營收、營業利益、稅後淨利。
  /// 為季報資料，每季更新一次。
  Future<List<TpexIndustryEps>> getIndustryEps() {
    return MarketClientMixin.executeRequest(_tag, '產業EPS', () async {
      const cacheKey = 'industryEps';
      final cached = _cache.get(cacheKey) as List<TpexIndustryEps>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexIndustryEps,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenAPI error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '產業EPS: 非預期資料型別');
        return [];
      }

      final results = <TpexIndustryEps>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TpexIndustryEps.tryFromJson(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '產業EPS: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 釋放底層 Dio HTTP 連線資源與 LRU 回應快取。
  ///
  /// 由 Riverpod provider 的 `ref.onDispose` 呼叫；ad-hoc 流程
  /// （如 `BackgroundUpdateService`）也應在 `try/finally` 中呼叫。
  void close() {
    _dio.close(force: false);
    _cache.clear();
  }

  /// 上櫃現股當沖交易統計（逐檔）
  ///
  /// **與上市的日期語意相反**：TWSE TWTB4U 吃 `date` 參數，那條路的守衛是
  /// 「回應日期 ≠ 請求日期就整批丟棄」；本端點**無視 `date` 參數、永遠回最新
  /// 交易日**（2026-08-23 實測六個日期回同一份資料、md5 相同），故資料日期
  /// 取自回應的 `date`，呼叫端據此寫入，不可用請求日期。
  ///
  /// 回應含兩張表：第一張是全市場彙總，**逐檔在第二張**——不可重用只取
  /// `tables.first` 的既有 helper。`stat` 是小寫 `ok`（上市是大寫 `OK`）。
  Future<List<TpexDayTrading>> getAllDayTradingData() {
    return MarketClientMixin.executeRequest(_tag, '當沖資料', () async {
      const cacheKey = 'tpexDayTrading';
      final cached = _cache.get(cacheKey) as List<TpexDayTrading>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexDayTrading,
        queryParameters: {'type': 'Daily', 'response': 'json'},
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '當沖資料',
      );
      if (data == null) return const <TpexDayTrading>[];

      if (data['stat']?.toString().toLowerCase() != 'ok') {
        return const <TpexDayTrading>[];
      }

      // 資料日期：無從驗證就整批丟棄——寫錯日期比沒資料糟。
      final dataDate = TwParseUtils.parseAdDateOrNull(data['date']?.toString());
      if (dataDate == null) {
        AppLogger.warning(_tag, '當沖回應缺 date 欄位，整批丟棄');
        return const <TpexDayTrading>[];
      }

      // 日期上下界:parseAdDateOrNull 只擋 year < 2000。此路徑刻意放棄了上市
      // 那道「回應日期 ≠ 請求日期就丟棄」的守衛（端點無視請求日期），而那道
      // 守衛同時兼任「端點凍結偵測器」。本檔已有兩個端點靜默凍在某一天的
      // 前例，故在此補回下界；未來日期一律拒收（會寫出永遠讀不到的列）。
      final now = DateContext.normalize(_clock.now());
      if (dataDate.isAfter(now)) {
        AppLogger.warning(_tag, '當沖回應日期 $dataDate 在未來，整批丟棄');
        return const <TpexDayTrading>[];
      }
      final staleDays = now.difference(dataDate).inDays;
      if (staleDays > ApiConfig.tpexDayTradingMaxStaleDays) {
        AppLogger.warning(
          _tag,
          '當沖回應日期 $dataDate 已過期 $staleDays 天（端點可能凍結），整批丟棄',
        );
        return const <TpexDayTrading>[];
      }

      // 逐檔在第二張表：**兩張表都是 6 欄**，不能用欄數判別（早期版本正是
      // 這樣寫，選到彙總表回 0 筆、不報錯、還被快取 30 分鐘）。改以 `fields`
      // 是否含「證券代號」判斷——比照 TwseClient 以 title 判別的做法。
      final tables = data['tables'];
      if (tables is! List) return const <TpexDayTrading>[];
      List<dynamic>? rows;
      for (final t in tables) {
        if (t is! Map) continue;
        final fields = t['fields'];
        if (fields is! List || !fields.contains('證券代號')) continue;
        final d = t['data'];
        if (d is List) {
          rows = d;
          break;
        }
      }
      if (rows == null) {
        AppLogger.warning(_tag, '當沖回應找不到逐檔表（fields 無「證券代號」），整批丟棄');
        return const <TpexDayTrading>[];
      }

      final result = <TpexDayTrading>[];
      for (final raw in rows) {
        if (raw is! List || raw.length < 6) continue;
        final code = raw[0]?.toString().trim() ?? '';
        // ETF／債券等非個股代號一併排除（比照上市路徑）
        if (!StockPatterns.isValidCode(code)) continue;

        // 千分位逗號、全形空白、`--` 哨兵一併處理；解析不出來就跳過該列，
        // 不落 0——0 在當沖語意下是合法值（無當沖），不可與「讀不到」混淆。
        final volume = TwParseUtils.parseFormattedDouble(raw[3]);
        final buy = TwParseUtils.parseFormattedDouble(raw[4]);
        final sell = TwParseUtils.parseFormattedDouble(raw[5]);
        if (volume == null || buy == null || sell == null) continue;

        result.add(
          TpexDayTrading(
            date: dataDate,
            code: code,
            name: raw[1]?.toString().trim() ?? '',
            buyVolume: buy,
            sellVolume: sell,
            totalVolume: volume,
          ),
        );
      }

      // 「找到表但解析出 0 筆」與「休市」在回傳值上無法區分，而它正是判別法
      // 出錯時的樣子——不快取、且出聲，否則錯誤會被凍結一個 TTL。
      if (result.isEmpty) {
        AppLogger.warning(_tag, '當沖逐檔表有 ${rows.length} 列但解析出 0 筆，不快取');
        return result;
      }

      AppLogger.info(_tag, '當沖資料: ${result.length} 筆 (上櫃, $dataDate)');
      _cache.put(cacheKey, result);
      return result;
    });
  }
}

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/lru_cache.dart';
import 'package:daredevil/core/utils/tw_parse_utils.dart';
import 'package:daredevil/data/models/tpex/tpex_insider_transfer.dart';
import 'package:daredevil/data/models/twse/models.dart';
import 'package:daredevil/data/remote/insider_holding_aggregator.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';

export 'package:daredevil/data/models/twse/models.dart';

/// 台灣證券交易所 (TWSE) API 客戶端
///
/// 提供免費存取台股市場資料。
/// 使用 TWSE 官方網站 JSON API 以取得更快的資料更新。
/// 無需認證。
///
/// API 來源:
/// - 每日股價: https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY_ALL
/// - 歷史資料: https://www.twse.com.tw/exchangeReport/STOCK_DAY
class TwseClient {
  TwseClient({Dio? dio})
    : _dio = dio ?? MarketClientMixin.createDio(ApiEndpoints.twseBaseUrl);

  static const String _tag = 'TWSE';
  final Dio _dio;
  final LruCache<String, dynamic> _cache = LruCache(
    maxSize: CacheConfig.marketClientCacheMaxSize,
    ttl: const Duration(minutes: CacheConfig.marketClientCacheTtlMin),
  );

  /// 取得最新交易日所有股票價格
  ///
  /// 回傳所有上市股票的 OHLCV 資料。
  /// 使用 TWSE 官方網站 API，更新速度比 Open Data API 快。
  ///
  /// 端點: /rwd/zh/afterTrading/STOCK_DAY_ALL
  ///
  /// ⚠️ `date=YYYYMMDD` 參數自 2026-06 CSV 化後被端點忽略（永遠回最新
  /// 日）——歷史回補走 [getAllDailyPricesHistorical]（MI_INDEX）。Cache key
  /// 仍依 date 區分避免互相覆蓋。
  Future<List<TwseDailyPrice>> getAllDailyPrices({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '全市場價格', () async {
      final cacheKey = date != null
          ? 'dailyPrices:${TwParseUtils.formatDateCompact(date)}'
          : 'dailyPrices';
      final cached = _cache.get(cacheKey) as List<TwseDailyPrice>?;
      if (cached != null) return cached;

      final queryParams = <String, dynamic>{'response': 'json'};
      if (date != null) {
        queryParams['date'] = TwParseUtils.formatDateCompact(date);
      }

      final response = await _dio.get(
        ApiEndpoints.twseDailyPricesAll,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      // TWSE 2026-06 起把 STOCK_DAY_ALL 的回應從 JSON 改成 CSV（同一端點、僅
      // 格式變更）。偵測到 CSV 就就地轉成與 JSON 同 shape 的 Map，不動共用的
      // decodeResponseData（零波及其他端點），且 TWSE 哪天又改回 JSON 也自動相容。
      final raw = response.data;
      final data = (raw is String && raw.trimLeft().startsWith('日期'))
          ? parseDailyPriceCsvToMap(raw)
          : MarketClientMixin.decodeResponseData(raw, _tag, '全市場價格');
      if (data == null) return [];

      final rows = MarketClientMixin.validateTwseStat(data, _tag, '全市場價格');
      if (rows == null) return [];

      // 用 response 內標示的日期（可能跟 requested date 不同：例如該日非
      // 交易日，TWSE 會回最近一個交易日的資料）
      final dateStr = data['date']?.toString() ?? '';
      final responseDate = TwParseUtils.parseAdDate(dateStr);

      final result = MarketClientMixin.parseRows(
        rows: rows,
        parser: (row) => _parseDailyPriceRow(row, responseDate),
        tag: _tag,
        operation: '全市場價格',
        date: responseDate,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// MI_INDEX（每日收盤行情全部）→ [TwseDailyPrice] 列表。
  ///
  /// **歷史回補替代端點**：STOCK_DAY_ALL 自 2026-06 CSV 化後忽略 date
  /// 參數；MI_INDEX?date=yyyyMMdd&type=ALLBUT0999 經 2026-07-12 活體驗證
  /// 支援歷史日期。回應為多表結構，收盤行情表以 fields 首欄「證券代號」
  /// 辨識（不依賴表序）。
  ///
  /// row 佈局：[代號, 名稱, 成交股數, 成交筆數, 成交金額, 開, 高, 低, 收,
  /// 漲跌(+/-)(html), 漲跌價差, ...]。漲跌號從 html 取正負、乘上價差。
  /// 回應日期 ≠ [requestedDate] → 回空（端點失效防護）。public 供測試。
  /// 解析 BWIBBU 估值列。public 供測試(主方法自建 Dio、不可注入)。
  ///
  /// **缺值一律回 null,不得寫 0**(2026-08-15 數值稽核):端點對「無法
  /// 計算」的欄位回 `-`——虧損公司無本益比、未配息無殖利率。舊實作
  /// `?? 0.0` 把它落庫成 0,與「本益比 0」(極度便宜)語意完全相反。
  /// 實測 production 每日 213–246 檔(約 20%)per=0,其中 38 檔明明獲利;
  /// 而同欄位的 TPEX 路徑寫的是 NULL,兩市場語意不一致會讓跨市場的
  /// 排序/分位數/平均本益比統計全部不成立。
  ///
  /// 注意:交易所明確回的 `0.00`(如確定不配息)**是資訊**,照常保留;
  /// 只有解析不出數值時才回 null。
  static List<TwseValuation> parseValuationRows(
    List<dynamic> data,
    DateTime resDate,
  ) {
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      double? num(String key) {
        final raw = map[key]?.toString().replaceAll(',', '');
        if (raw == null || raw.isEmpty) return null;
        return double.tryParse(raw);
      }

      return TwseValuation(
        code: map['Code']?.toString() ?? '',
        date: resDate,
        per: num('PEratio'),
        pbr: num('PBratio'),
        dividendYield: num('DividendYield'),
      );
    }).toList();
  }

  static List<TwseDailyPrice> parseMiIndexDailyPrices(
    Map<dynamic, dynamic> json,
    DateTime requestedDate,
  ) {
    final expected =
        '${requestedDate.year.toString().padLeft(4, '0')}'
        '${requestedDate.month.toString().padLeft(2, '0')}'
        '${requestedDate.day.toString().padLeft(2, '0')}';
    if (json['date']?.toString() != expected) return const [];

    final tables = json['tables'];
    if (tables is! List) return const [];

    List<dynamic>? rows;
    for (final table in tables) {
      if (table is! Map) continue;
      final fields = table['fields'];
      if (fields is List &&
          fields.isNotEmpty &&
          fields.first.toString().contains('證券代號')) {
        rows = table['data'] as List<dynamic>?;
        break;
      }
    }
    if (rows == null) return const [];

    final result = <TwseDailyPrice>[];
    for (final raw in rows) {
      if (raw is! List || raw.length < 11) continue;
      final code = raw[0]?.toString().trim() ?? '';
      if (code.isEmpty) continue;

      final changeAbs = TwParseUtils.parseFormattedDouble(raw[10]?.toString());
      final signHtml = raw[9]?.toString() ?? '';
      double? change;
      if (changeAbs != null) {
        if (signHtml.contains('-')) {
          change = -changeAbs;
        } else if (signHtml.contains('+')) {
          change = changeAbs;
        } else {
          change = 0.0;
        }
      }

      result.add(
        TwseDailyPrice(
          date: requestedDate,
          code: code,
          name: raw[1]?.toString().trim() ?? '',
          open: TwParseUtils.parsePrice(raw[5]?.toString()),
          high: TwParseUtils.parsePrice(raw[6]?.toString()),
          low: TwParseUtils.parsePrice(raw[7]?.toString()),
          close: TwParseUtils.parsePrice(raw[8]?.toString()),
          volume: TwParseUtils.parseFormattedDouble(raw[2]?.toString()),
          change: change,
        ),
      );
    }
    return result;
  }

  /// 歷史全市場行情（MI_INDEX 端點；backfill 用）。
  ///
  /// 與 [getAllDailyPrices]（STOCK_DAY_ALL、僅最新日）分工：每日同步走
  /// 舊端點，歷史回補走本方法。
  Future<List<TwseDailyPrice>> getAllDailyPricesHistorical(DateTime date) {
    return MarketClientMixin.executeRequest(_tag, '歷史全市場價格', () async {
      final dateStr = TwParseUtils.formatDateCompact(date);
      final cacheKey = 'miIndexDaily:$dateStr';
      final cached = _cache.get(cacheKey) as List<TwseDailyPrice>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        '/rwd/zh/afterTrading/MI_INDEX',
        queryParameters: {
          'date': dateStr,
          'type': 'ALLBUT0999',
          'response': 'json',
        },
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
      if (data == null) return <TwseDailyPrice>[];

      final result = parseMiIndexDailyPrices(data, date);
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析每日價格資料列
  ///
  /// 列格式: [代號, 名稱, 成交股數, 成交金額, 開盤價, 最高價, 最低價, 收盤價, 漲跌價差, 成交筆數]
  TwseDailyPrice? _parseDailyPriceRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 10,
      tag: _tag,
      operation: '每日價格',
      parser: () {
        final code = row[0]?.toString() ?? '';
        if (code.isEmpty) return null;
        return TwseDailyPrice(
          date: date,
          code: code,
          name: row[1]?.toString() ?? '',
          open: TwParseUtils.parsePrice(row[4]),
          high: TwParseUtils.parsePrice(row[5]),
          low: TwParseUtils.parsePrice(row[6]),
          close: TwParseUtils.parsePrice(row[7]),
          volume: TwParseUtils.parseFormattedDouble(row[2]),
          change: TwParseUtils.parseFormattedDouble(row[8]),
        );
      },
    );
  }

  /// 將 STOCK_DAY_ALL 的 CSV 回應轉成與 JSON 路徑相同 shape 的 Map
  /// （`{stat, date, data}`），讓下游 [MarketClientMixin.validateTwseStat] 與
  /// [_parseDailyPriceRow] 完全沿用、無需改動。
  ///
  /// 背景：TWSE 於 2026-06 把此端點回應從 JSON 改為 CSV（同端點、僅格式變更）。
  ///
  /// CSV 欄位：`[日期(民國), 證券代號, 證券名稱, 成交股數, 成交金額, 開, 高, 低,
  /// 收, 漲跌價差, 成交筆數]`。剝掉首欄「日期」後，剩餘 10 欄即與 JSON `data`
  /// row 同佈局（`[代號, 名稱, 成交股數, …]`）。日期改放頂層 `date`（轉 8 碼西元
  /// 字串供 [TwParseUtils.parseAdDate] 沿用）。無有效資料列時回傳 null。
  @visibleForTesting
  static Map<String, dynamic>? parseDailyPriceCsvToMap(String csv) {
    String? adDate;
    final dataRows = <List<String>>[];
    for (final line in csv.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      // 跳過空行與 header（header 以未加引號的「日期」開頭）
      if (trimmed.isEmpty || trimmed.startsWith('日期')) continue;
      final cells = _splitQuotedCsvLine(trimmed);
      if (cells.length < 11) continue;
      final rocDate = TwParseUtils.parseCompactRocDate(cells[0]);
      if (rocDate == null) continue;
      // 整批同一交易日：取第一筆有效日期，轉 8 碼西元字串
      adDate ??=
          '${rocDate.year}'
          '${rocDate.month.toString().padLeft(2, '0')}'
          '${rocDate.day.toString().padLeft(2, '0')}';
      dataRows.add(cells.sublist(1)); // 剝掉日期欄 → 同 JSON row 佈局
    }
    if (adDate == null || dataRows.isEmpty) return null;
    return {'stat': 'OK', 'date': adDate, 'data': dataRows};
  }

  /// 拆解 TWSE CSV 資料行（每欄以雙引號包覆，如 `"1150624","2330",…`）。
  /// 去除外層引號後以 `","` 切分，可正確處理欄位內含逗號（如千分位數字）。
  static List<String> _splitQuotedCsvLine(String line) {
    var s = line;
    if (s.startsWith('"')) s = s.substring(1);
    if (s.endsWith('"')) s = s.substring(0, s.length - 1);
    return s.split('","');
  }

  /// 取得所有股票的法人買賣超資料
  ///
  /// 端點: /rwd/zh/fund/T86（三大法人買賣超日報）
  /// 注意：TWSE API 回傳的是「股數」，存入資料庫時需除以 1000 轉換為「張」
  Future<List<TwseInstitutional>> getAllInstitutionalData({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '法人資料', () async {
      final cacheKey = date != null
          ? 'institutional:${TwParseUtils.formatDateCompact(date)}'
          : 'institutional';
      final cached = _cache.get(cacheKey) as List<TwseInstitutional>?;
      if (cached != null) return cached;

      final queryParams = <String, dynamic>{
        'response': 'json',
        'selectType': 'ALLBUT0999',
      };

      if (date != null) {
        queryParams['date'] = TwParseUtils.formatDateCompact(date);
      }

      final response = await _dio.get(
        ApiEndpoints.twseInstitutional,
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
        '法人資料',
      );
      if (data == null) return [];

      final rows = MarketClientMixin.validateTwseStat(data, _tag, '法人資料');
      if (rows == null) return [];

      final dateStr = data['date']?.toString() ?? '';
      final parsedDate = TwParseUtils.parseAdDate(dateStr);

      final result = MarketClientMixin.parseRows(
        rows: rows,
        parser: (row) => _parseInstitutionalRow(row, parsedDate),
        tag: _tag,
        operation: '法人資料',
        date: parsedDate,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 全市場外資及陸資持股(MI_QFIIS,免費、支援歷史日期)
  ///
  /// 端點: /rwd/zh/fund/MI_QFIIS。2026-08-16 接入,補上市股外資持股覆蓋
  /// ——原本只靠 FinMind 逐檔、且只同步自選+熱門約 48 檔,實測上市候選
  /// 344 檔僅 82 檔有資料,而上櫃因有輪替機制是 100%。
  Future<List<TwseForeignShareholding>> getAllForeignShareholding({
    DateTime? date,
  }) {
    return MarketClientMixin.executeRequest(_tag, '外資持股', () async {
      final cacheKey = date != null
          ? 'foreignShareholding:${TwParseUtils.formatDateCompact(date)}'
          : 'foreignShareholding';
      final cached = _cache.get(cacheKey) as List<TwseForeignShareholding>?;
      if (cached != null) return cached;

      final queryParams = <String, dynamic>{
        'response': 'json',
        'selectType': 'ALLBUT0999',
        if (date != null) 'date': TwParseUtils.formatDateCompact(date),
      };

      final response = await _dio.get(
        ApiEndpoints.twseForeignShareholding,
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
        '外資持股',
      );
      if (data == null) return [];
      final rows = MarketClientMixin.validateTwseStat(data, _tag, '外資持股');
      if (rows == null) return [];

      // 回應自帶日期:非交易日查詢時 TWSE 會回最近有資料的那天,
      // 用 request date 落庫會把資料標成錯的日子
      final parsedDate = TwParseUtils.parseAdDate(
        data['date']?.toString() ?? '',
      );

      final result = MarketClientMixin.parseRows(
        rows: rows,
        parser: (row) => TwseForeignShareholding.fromRow(row, parsedDate),
        tag: _tag,
        operation: '外資持股',
        date: parsedDate,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析法人資料列
  ///
  /// T86（selectType=ALLBUT0999）回傳 19 欄陣列（已對 live API 驗證）：
  /// [0] 代號, [1] 名稱
  /// [2] 外陸資(不含外資自營)買進, [3] 賣出, [4] 外陸資買賣超（→ foreignNet）
  /// [5] 外資自營買進, [6] 賣出, [7] 外資自營買賣超
  /// [8] 投信買進, [9] 賣出, [10] 投信買賣超（→ investmentTrustNet）
  /// [11] 自營商買賣超(合計)（→ dealerNet，含避險，對外口徑）
  /// [12] 自營商(自行買賣)買進, [13] 賣出, [14] 自營商(自行買賣)買賣超（→ dealerSelfNet）
  /// [15] 自營商(避險)買進, [16] 賣出, [17] 自營商(避險)買賣超
  /// [18] 三大法人買賣超（→ totalNet）
  ///
  /// 算術不變式（已對 1318/1318 row 驗證）：[11] 合計 = [14] 自行 + [17] 避險。
  ///
  /// 注意：dealerBuy/dealerSell 下游未消費，為口徑正確取「自行 + 避險」合併
  /// （[12]+[15] / [13]+[16]）。
  TwseInstitutional? _parseInstitutionalRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 19,
      tag: _tag,
      operation: '法人資料',
      parser: () {
        final code = row[0]?.toString() ?? '';
        if (code.isEmpty) return null;
        final dealerSelfBuy = TwParseUtils.parseFormattedDouble(row[12]) ?? 0;
        final dealerSelfSell = TwParseUtils.parseFormattedDouble(row[13]) ?? 0;
        final dealerHedgeBuy = TwParseUtils.parseFormattedDouble(row[15]) ?? 0;
        final dealerHedgeSell = TwParseUtils.parseFormattedDouble(row[16]) ?? 0;
        return TwseInstitutional(
          date: date,
          code: code,
          name: row[1]?.toString() ?? '',
          foreignBuy: TwParseUtils.parseFormattedDouble(row[2]) ?? 0,
          foreignSell: TwParseUtils.parseFormattedDouble(row[3]) ?? 0,
          foreignNet: TwParseUtils.parseFormattedDouble(row[4]) ?? 0,
          investmentTrustBuy: TwParseUtils.parseFormattedDouble(row[8]) ?? 0,
          investmentTrustSell: TwParseUtils.parseFormattedDouble(row[9]) ?? 0,
          investmentTrustNet: TwParseUtils.parseFormattedDouble(row[10]) ?? 0,
          // 自營商買進/賣出取「自行 + 避險」合併（下游未用，僅為口徑正確）
          dealerBuy: dealerSelfBuy + dealerHedgeBuy,
          dealerSell: dealerSelfSell + dealerHedgeSell,
          // [11] 自營商買賣超(合計) — 含避險，對外口徑（媒體/TWSE 報的值）
          dealerNet: TwParseUtils.parseFormattedDouble(row[11]) ?? 0,
          // [14] 自營商(自行買賣)買賣超 — 不含避險，供真實主動方向 streak
          dealerSelfNet: TwParseUtils.parseFormattedDouble(row[14]) ?? 0,
          // [18] 三大法人買賣超
          totalNet: TwParseUtils.parseFormattedDouble(row[18]) ?? 0,
        );
      },
    );
  }

  /// 取得特定股票的歷史價格（每次一個月）
  ///
  /// [code] - 股票代碼（例如 "2330"）
  /// [year] - 西元年（例如 2026）
  /// [month] - 月份（1-12）
  ///
  /// 端點: /exchangeReport/STOCK_DAY
  ///
  /// 參數無效時拋出 [ArgumentError]
  Future<List<TwseDailyPrice>> getStockMonthlyPrices({
    required String code,
    required int year,
    required int month,
  }) {
    // 驗證股票代碼（台股通常為 4-6 碼數字）
    if (code.isEmpty) {
      throw ArgumentError.value(code, 'code', 'Stock code cannot be empty');
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(code)) {
      throw ArgumentError.value(
        code,
        'code',
        'Stock code must be 4-6 digits (e.g., "2330")',
      );
    }

    // 驗證年份（TWSE 歷史資料的合理範圍）
    if (year < 1990 || year > 2100) {
      throw ArgumentError.value(
        year,
        'year',
        'Year must be between 1990 and 2100',
      );
    }

    // 驗證月份
    if (month < 1 || month > 12) {
      throw ArgumentError.value(
        month,
        'month',
        'Month must be between 1 and 12',
      );
    }

    // 防止未來日期
    final now = DateTime.now();
    if (year > now.year || (year == now.year && month > now.month)) {
      AppLogger.debug(_tag, '$code: 查詢日期大於今日 ($year/$month)，跳過');
      return Future.value([]);
    }

    return MarketClientMixin.executeRequest(_tag, '月價格', () async {
      // 格式化日期為 YYYYMMDD（該月第一天）
      final dateStr = '$year${month.toString().padLeft(2, '0')}01';

      final response = await _dio.get(
        '${ApiEndpoints.twseBaseUrl}${ApiEndpoints.twseStockDay}',
        queryParameters: {'response': 'json', 'date': dateStr, 'stockNo': code},
      );

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag historical API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '月價格',
      );
      if (data == null) return [];

      final rows = MarketClientMixin.validateTwseStat(data, _tag, '月價格');
      if (rows == null) return [];

      final results = rows
          .map((row) => _parseHistoricalRow(row as List<dynamic>, code))
          .whereType<TwseDailyPrice>()
          .toList();
      AppLogger.debug(_tag, '月價格($code): $year/$month -> ${results.length} 筆');
      return results;
    });
  }

  /// 解析 TWSE 歷史資料列
  TwseDailyPrice? _parseHistoricalRow(List<dynamic> row, String code) {
    // 列格式: [日期, 成交股數, 成交金額, 開盤價, 最高價, 最低價, 收盤價, 漲跌價差, 成交筆數, ...]
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 9,
      tag: _tag,
      operation: '歷史價格',
      parser: () {
        final date = TwParseUtils.parseSlashRocDate(row[0].toString());
        if (date == null) return null;
        return TwseDailyPrice(
          date: date,
          code: code,
          name: '',
          // parsePrice(2026-08-01 審查補漏):此端點是上市個股歷史回補
          // 的實際路徑,初版零價 sweep 漏了它——無成交日的 0.00 會持續
          // 灌進 52 週窗,beforeOpen 清理只能兜底追不上源頭
          open: TwParseUtils.parsePrice(row[3]),
          high: TwParseUtils.parsePrice(row[4]),
          low: TwParseUtils.parsePrice(row[5]),
          close: TwParseUtils.parsePrice(row[6]),
          volume: TwParseUtils.parseFormattedDouble(row[1]),
          change: TwParseUtils.parseFormattedDouble(row[7]),
        );
      },
    );
  }

  /// 取得所有股票的融資融券資料
  ///
  /// 端點: /rwd/zh/marginTrading/MI_MARGN（融資融券餘額）
  /// [date] 為 null 時取最新可用交易日（每日路徑）；指定日期時回補該日
  /// （端點支援歷史日期，2026-07-14 活體驗證）。
  Future<List<TwseMarginTrading>> getAllMarginTradingData({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '融資融券', () async {
      // cache key 必須含日期，否則回補不同日會互相污染
      final cacheKey = date != null
          ? 'marginTrading:${TwParseUtils.formatDateCompact(date)}'
          : 'marginTrading';
      final cached = _cache.get(cacheKey) as List<TwseMarginTrading>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.twseMarginTrading,
        queryParameters: {
          'response': 'json',
          'selectType': 'ALL',
          if (date != null) 'date': TwParseUtils.formatDateCompact(date),
        },
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

      if (data['stat'] != 'OK') return [];

      // entries 一律蓋**回應自身的日期**（非請求日期）——回補時呼叫端據此
      // 過濾，端點若回錯日期只會被丟棄，不會寫出錯誤日期的列
      final dateStr = data['date']?.toString() ?? '';
      final responseDate = TwParseUtils.parseAdDate(dateStr);

      // 資料在 'tables' 陣列中，第二個表格含個股資料
      final tables = data['tables'] as List<dynamic>?;
      if (tables == null || tables.length < 2) return [];

      final stockTable = tables[1] as Map<String, dynamic>?;
      if (stockTable == null) return [];
      final List<dynamic> rows = stockTable['data'] ?? [];

      final result = MarketClientMixin.parseRows(
        rows: rows,
        parser: (row) => _parseMarginTradingRow(row, responseDate),
        tag: _tag,
        operation: '融資融券',
        date: responseDate,
      );
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析融資融券資料列
  ///
  /// 列格式: [代號, 名稱, 融資買進, 融資賣出, 融資現償, 融資前餘, 融資今餘, 融資限額,
  ///         融券買進, 融券賣出, 融券現償, 融券前餘, 融券今餘, 融券限額, 資券互抵, 備註]
  TwseMarginTrading? _parseMarginTradingRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 14,
      tag: _tag,
      operation: '融資融券',
      parser: () {
        final code = row[0]?.toString() ?? '';
        if (code.isEmpty) return null;
        return TwseMarginTrading(
          date: date,
          code: code,
          name: row[1]?.toString() ?? '',
          marginBuy: TwParseUtils.parseFormattedDouble(row[2]) ?? 0,
          marginSell: TwParseUtils.parseFormattedDouble(row[3]) ?? 0,
          marginBalance: TwParseUtils.parseFormattedDouble(row[6]) ?? 0,
          shortBuy: TwParseUtils.parseFormattedDouble(row[8]) ?? 0,
          shortSell: TwParseUtils.parseFormattedDouble(row[9]) ?? 0,
          shortBalance: TwParseUtils.parseFormattedDouble(row[12]) ?? 0,
        );
      },
    );
  }

  /// 取得所有股票的估值資料（本益比、股價淨值比、殖利率）
  ///
  /// 使用 TWSE Open Data API 取得可靠的結構化資料
  /// 端點: https://openapi.twse.com.tw/v1/exchangeReport/BWIBBU_ALL
  Future<List<TwseValuation>> getAllStockValuation({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '估值資料', () async {
      const cacheKey = 'valuation';
      final cached = _cache.get(cacheKey) as List<TwseValuation>?;
      if (cached != null) return cached;

      // 建立獨立的 Dio 以避免基礎 URL 衝突（Open Data baseUrl 不同）
      // Open Data 欄位: Code, Name, PEratio, DividendYield, PBratio
      final openDataDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(
            seconds: ApiConfig.twseConnectTimeoutSec,
          ),
          receiveTimeout: const Duration(
            seconds: ApiConfig.twseReceiveTimeoutSec,
          ),
        ),
      );
      final Response response;
      try {
        response = await openDataDio.get(
          ApiEndpoints.twseValuation,
          options: Options(responseType: ResponseType.json),
        );
      } finally {
        openDataDio.close();
      }

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '估值資料: 非預期資料型別');
        return [];
      }
      // Open Data 不回傳交易日。過去用 DateTime.now()（含時間戳）當 date，使
      // PK (symbol,date) 每次同步都不同 → insertOrReplace 無法去重 → 重複膨脹。
      // 正規化到當日 00:00（同 daily_price 口徑），同日多次同步即可去重。
      final resDate = DateContext.normalize(date ?? DateTime.now());

      final results = parseValuationRows(data, resDate);

      AppLogger.info(_tag, '估值資料: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上市公司每日重大訊息（當日檔）
  ///
  /// 來源: TWSE Open Data API (t187ap04_L)；中文鍵、「主旨 」尾帶空格
  Future<List<TwseMaterialInfo>> getMaterialInformation() {
    return MarketClientMixin.executeRequest(_tag, '重大訊息', () async {
      const cacheKey = 'material_info';
      final cached = _cache.get(cacheKey) as List<TwseMaterialInfo>?;
      if (cached != null) return cached;

      final openDataDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(
            seconds: ApiConfig.twseConnectTimeoutSec,
          ),
          receiveTimeout: const Duration(
            seconds: ApiConfig.twseReceiveTimeoutSec,
          ),
        ),
      );
      final Response response;
      try {
        response = await openDataDio.get(
          ApiEndpoints.twseMaterialInfo,
          options: Options(responseType: ResponseType.json),
        );
      } finally {
        openDataDio.close();
      }

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '重大訊息: 非預期資料型別');
        return <TwseMaterialInfo>[];
      }
      final results = data
          .map((e) => TwseMaterialInfo.fromJson(e as Map<String, dynamic>))
          .where((e) => e.code.isNotEmpty)
          .toList();
      AppLogger.info(_tag, '重大訊息: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得停資停券預告表
  ///
  /// 來源: TWSE Open Data API (BFI84U)
  /// 端點: https://openapi.twse.com.tw/v1/exchangeReport/BFI84U
  /// 欄位: Code, Name, StartDate, EndDate, Reason（日期為民國年 yyyMMdd）
  Future<List<TwseShortSuspension>> getShortSellingSuspensions() {
    return MarketClientMixin.executeRequest(_tag, '停券預告', () async {
      const cacheKey = 'short_suspension';
      final cached = _cache.get(cacheKey) as List<TwseShortSuspension>?;
      if (cached != null) return cached;

      final openDataDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(
            seconds: ApiConfig.twseConnectTimeoutSec,
          ),
          receiveTimeout: const Duration(
            seconds: ApiConfig.twseReceiveTimeoutSec,
          ),
        ),
      );
      final Response response;
      try {
        response = await openDataDio.get(
          ApiEndpoints.twseShortSuspension,
          options: Options(responseType: ResponseType.json),
        );
      } finally {
        openDataDio.close();
      }

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '停券預告: 非預期資料型別');
        return <TwseShortSuspension>[];
      }
      final results = data
          .map((e) => TwseShortSuspension.fromJson(e as Map<String, dynamic>))
          .where((e) => e.code.isNotEmpty)
          .toList();
      AppLogger.info(_tag, '停券預告: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 上市除權除息預告表（TWT48U_ALL,免額度)——帶確定除權息交易日
  ///
  /// 行事曆除權息事件的資料源:大宗「已宣告股利」(t187ap45)只帶金額
  /// 不帶日期,只有本預告表有確定交易日(2026-08-01 實測 122 筆、
  /// 滾動前瞻約兩個月)。
  Future<List<ExRightPreannouncement>> getExRightPreannouncements() {
    return MarketClientMixin.executeRequest(_tag, '除權息預告', () async {
      const cacheKey = 'exright_preannouncement';
      final cached = _cache.get(cacheKey) as List<ExRightPreannouncement>?;
      if (cached != null) return cached;

      final response = await _dio.get(ApiEndpoints.twseExRightPreannouncement);
      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
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
          .map(ExRightPreannouncement.tryFromTwseJson)
          .whereType<ExRightPreannouncement>()
          .toList();
      AppLogger.info(_tag, '除權息預告: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得上市內部人持股轉讓事前申報(每日,t187ap12_L)。
  ///
  /// 2026-08-05 補接:內部人轉讓面板原本只有上櫃源,上市側永遠空白——
  /// 監控範圍恰好漏掉部位最重的市場,且空白會被誤讀成「今天沒異動」。
  Future<List<TpexInsiderTransfer>> getInsiderTransfers() {
    return MarketClientMixin.executeRequest(_tag, '內部人轉讓', () async {
      const cacheKey = 'insiderTransfer';
      final cached = _cache.get(cacheKey) as List<TpexInsiderTransfer>?;
      if (cached != null) return cached;

      final response = await _dio.get(ApiEndpoints.twseInsiderTransfer);

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '內部人轉讓: 非預期資料型別');
        return <TpexInsiderTransfer>[];
      }

      final results = <TpexInsiderTransfer>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TpexInsiderTransfer.tryFromTwseJson(item);
        if (parsed != null) results.add(parsed);
      }
      _cache.put(cacheKey, results);
      AppLogger.info(_tag, '內部人轉讓: ${results.length} 筆');
      return results;
    });
  }

  /// 取得上市最新一季綜合損益表(t187ap06_L_*,六業別合併)。
  ///
  /// 公布期逐日填充:誰申報了就出現誰——「最新一季財報總覽」的清單
  /// 完整性以此官方事實為基礎,不受自家 FinMind 回補佇列進度影響
  /// (2026-08-06,沿月營收 MOPS 源同一設計原則)。
  ///
  /// 六業別 per-variant 隔離:單一業別失敗記 warning、其餘照收,全部
  /// 失敗才拋(RateLimitException 一律直接 rethrow)——金融業別平日
  /// 常態零星,單端點異常不該砍掉整份清單。
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
            ApiEndpoints.twseQuarterlyReport(suffix),
          );
          if (response.statusCode != 200) {
            throw ApiException(
              '$_tag OpenData API error: ${response.statusCode}',
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

  /// 上市全市場資產負債表(t187ap07_L_*,六業別合併)
  ///
  /// 2026-08-16 接入,取代 FinMind 逐檔的 `getBalanceSheet`——那是額度
  /// 的唯一瓶頸(實測 129 檔待回填 = 258 次呼叫,佔小時額度 43%,當天
  /// 因額度保留只跑了 10 檔)。本端點免費、一次全市場。
  ///
  /// 六業別 per-variant 隔離,與 [getQuarterlyReports] 同設計:單一業別
  /// 失敗記 warning、其餘照收,全滅才拋。
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
            ApiEndpoints.twseBalanceSheet(suffix),
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

  /// 取得所有股票的月營收（最新月份）
  ///
  /// 來源: TWSE Open Data API (t187ap05_L)
  /// 端點: https://openapi.twse.com.tw/v1/opendata/t187ap05_L
  ///
  /// 此 API 回傳所有上市公司的最新營收資料。
  /// 比透過 FinMind 逐檔擷取快得多。
  Future<List<TwseMonthlyRevenue>> getAllMonthlyRevenue() {
    return MarketClientMixin.executeRequest(_tag, '月營收', () async {
      const cacheKey = 'monthlyRevenue';
      final cached = _cache.get(cacheKey) as List<TwseMonthlyRevenue>?;
      if (cached != null) return cached;

      // 使用完整 URL 以覆蓋基礎 URL (www.twse.com.tw)
      final response = await _dio.get(ApiEndpoints.twseMonthlyRevenue);

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '月營收: 非預期資料型別');
        return [];
      }
      // 年月合理性過濾(2026-08-05 複審 Low #12):TPEx 版有 month 1..12
      // 檢核、本側原本沒有——單筆髒年月(如 2027/x 或 month=13)落庫會
      // 永久劫持營收總覽的「最新月」錨點且無清理路徑;整批欄位缺失
      // (year=0)則會讓 freshness check 永久「已快取」跳過。
      final results = data
          .map(
            (json) => TwseMonthlyRevenue.fromJson(json as Map<String, dynamic>),
          )
          .where(
            (r) =>
                r.month >= 1 &&
                r.month <= 12 &&
                r.year >= 2000 &&
                r.year <= DateTime.now().year + 1,
          )
          .toList();
      AppLogger.info(_tag, '月營收: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 取得所有股票的當沖資料
  ///
  /// 端點: /exchangeReport/TWTB4U（當日沖銷交易標的）
  /// 免費 API，無需 token。
  Future<List<TwseDayTrading>> getAllDayTradingData({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '當沖資料', () async {
      final targetDate = date ?? DateTime.now();
      final cacheKey = date != null
          ? 'dayTrading:${TwParseUtils.formatDateCompact(date)}'
          : 'dayTrading';
      final cached = _cache.get(cacheKey) as List<TwseDayTrading>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.twseDayTrading,
        queryParameters: {
          'response': 'json',
          'date': TwParseUtils.formatDateCompact(targetDate),
        },
        options: Options(responseType: ResponseType.plain),
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
      if (data == null) return [];

      if (data['stat'] != 'OK') return [];

      // 端點失效防護（fail closed）：呼叫端（TradingRepository）以**請求日期**
      // 寫入，端點若像 STOCK_DAY_ALL 一樣無視 date 參數、回最新交易日，就會把
      // 最新資料寫成歷史日期（資料污染）。日期不符**或回應根本沒帶日期**都整批
      // 丟棄——無從驗證的資料一律不可信。
      //
      // ⚠️ 此守衛在**每日路徑上也生效**：`syncAllDayTradingFromTwse` 一律傳日期
      // （`date ?? _clock.now()` 永不為 null）。代價是 TWSE 若拿掉 `data['date']`
      // 欄位，每日當沖同步也會回 0 筆（有 warning）——這是刻意的取捨：寧可少資料
      // 也不要寫錯日期的資料。
      if (date != null) {
        final responseDate = data['date']?.toString();
        final requestedDate = TwParseUtils.formatDateCompact(targetDate);
        if (responseDate != requestedDate) {
          AppLogger.warning(
            _tag,
            '當沖資料回應日期 ${responseDate ?? "(無)"} ≠ 請求 $requestedDate，丟棄',
          );
          return [];
        }
      }

      // TWTB4U 回傳多個表格。我們需要含詳細個股資料的那個。
      // 通常是第二個表格，但以防萬一用標題來找。
      List<dynamic> rows = [];

      if (data.containsKey('tables')) {
        final List<dynamic> tables = data['tables'];
        for (final table in tables) {
          final title = table['title']?.toString() ?? '';
          if (title.contains('當日沖銷交易標的')) {
            rows = table['data'] ?? [];
            break;
          }
        }
        // 若以標題找不到，則嘗試從第二個表格（索引 1）載入作為備案
        if (rows.isEmpty && tables.length > 1) {
          rows = tables[1]['data'] ?? [];
        }
      } else {
        rows = data['data'] ?? [];
      }

      final result = <TwseDayTrading>[];
      for (final row in rows) {
        if (row is List && row.length >= 6) {
          final parsed = _parseDayTradingRow(row, targetDate);
          if (parsed != null) result.add(parsed);
        }
      }

      AppLogger.info(_tag, '當沖資料: ${result.length} 筆');
      _cache.put(cacheKey, result);
      return result;
    });
  }

  /// 解析當沖資料列
  ///
  /// 列格式: [代號, 名稱, (空), 當沖成交股數, 當沖買進金額, 當沖賣出金額]
  /// 註: TWSE TWTB4U API 不提供比例，需另行計算
  TwseDayTrading? _parseDayTradingRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 6,
      tag: _tag,
      operation: '當沖資料',
      parser: () {
        final code = row[0]?.toString().trim() ?? '';
        if (code.isEmpty || code.length < 4) return null;
        return TwseDayTrading(
          date: date,
          code: code,
          name: row[1]?.toString().trim() ?? '',
          buyVolume: TwParseUtils.parseFormattedDouble(row[4]) ?? 0,
          sellVolume: TwParseUtils.parseFormattedDouble(row[5]) ?? 0,
          totalVolume: TwParseUtils.parseFormattedDouble(row[3]) ?? 0,
        );
      },
    );
  }

  // ==================================================
  // 大盤指數 API
  // ==================================================

  /// 取得大盤各類指數收盤行情
  ///
  /// 端點: /rwd/zh/afterTrading/MI_INDEX
  /// 回傳加權指數、電子類指數、金融保險類指數等
  ///
  /// [date] 可選，指定日期取歷史指數（格式 YYYYMMDD）。省略則取最新。
  Future<List<TwseMarketIndex>> getMarketIndices({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '大盤指數', () async {
      final queryParams = <String, dynamic>{'response': 'json', 'type': 'IND'};
      if (date != null) {
        queryParams['date'] = TwParseUtils.formatDateCompact(date);
      }

      final response = await _dio.get(
        ApiEndpoints.twseMarketIndex,
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
        '大盤指數',
      );
      if (data == null) return [];

      if (data['stat'] != 'OK') {
        AppLogger.warning(_tag, '大盤指數: stat=${data['stat']}，可能為非交易日或盤中');
        return [];
      }

      final results = <TwseMarketIndex>[];

      // 解析日期
      final dateStr = data['date']?.toString() ?? '';
      final parsedDate = TwParseUtils.parseAdDate(dateStr);

      // MI_INDEX 回傳多個 tables，每個 table 包含不同類型的指數
      final tables = data['tables'] as List<dynamic>?;
      if (tables == null || tables.isEmpty) {
        // 嘗試直接從 data 取得（舊格式）
        final rows = data['data'] as List<dynamic>?;
        if (rows != null) {
          for (final row in rows) {
            final parsed = _parseMarketIndexRow(
              row as List<dynamic>,
              parsedDate,
            );
            if (parsed != null) results.add(parsed);
          }
        }
      } else {
        // 新格式：遍歷所有 tables
        for (var ti = 0; ti < tables.length; ti++) {
          final table = tables[ti] as Map<String, dynamic>;
          final title = table['title']?.toString() ?? '';
          final rows = table['data'] as List<dynamic>?;
          if (rows == null || rows.isEmpty) continue;
          var parsedInTable = 0;
          for (final row in rows) {
            final parsed = _parseMarketIndexRow(
              row as List<dynamic>,
              parsedDate,
            );
            if (parsed != null) {
              results.add(parsed);
              parsedInTable++;
            }
          }
          if (parsedInTable == 0) {
            final sample = rows.first;
            AppLogger.debug(
              _tag,
              '大盤指數 table[$ti] "$title": ${rows.length} 行全部跳過，'
              '樣本=${sample is List ? sample.take(3).toList() : sample}',
            );
          }
        }
      }

      if (results.isEmpty) {
        // 診斷：列出每個 table 的 keys 與 row 數量，幫助排查格式變更
        final diag = <String>[];
        if (tables != null) {
          for (var ti = 0; ti < tables.length && ti < 3; ti++) {
            final t = tables[ti];
            if (t is Map<String, dynamic>) {
              final rowCount = (t['data'] as List?)?.length ?? 0;
              final sample = (t['data'] as List?)?.firstOrNull;
              diag.add(
                't$ti: keys=${t.keys.take(5).toList()}, '
                'rows=$rowCount, '
                'sample=${sample is List ? sample.take(3).toList() : sample.runtimeType}',
              );
            } else {
              diag.add('t$ti: type=${t.runtimeType}');
            }
          }
        }
        AppLogger.warning(
          _tag,
          '大盤指數: 解析後 0 筆 (tables=${tables?.length ?? 0}) '
          '${diag.isNotEmpty ? diag.join(' | ') : ""}',
        );
      } else {
        AppLogger.debug(_tag, '大盤指數 API 原始: ${results.length} 筆');
      }
      return results;
    });
  }

  /// 解析大盤指數資料列
  ///
  /// 列格式: [指數名稱, 收盤指數, 漲跌(+/-), 漲跌點數, 漲跌百分比(%), 特殊處理欄位]
  ///
  /// 注意：TWSE API 的 row[3]（漲跌點數）和 row[4]（漲跌百分比）為絕對值，
  /// 漲跌方向由 row[2] 的符號（`+` 或 `-`）決定。
  TwseMarketIndex? _parseMarketIndexRow(List<dynamic> row, DateTime date) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 5,
      tag: _tag,
      operation: '大盤指數',
      parser: () {
        final name = row[0]?.toString().trim() ?? '';
        if (name.isEmpty) return null;

        final close = TwParseUtils.parseFormattedDouble(row[1]);
        if (close == null) return null;

        // row[2] 為漲跌方向符號：「+」或「-」或「X」/空值
        final dirSign = row[2]?.toString().trim() ?? '';
        final rawChange = TwParseUtils.parseFormattedDouble(row[3]) ?? 0;
        final rawChangePercent = TwParseUtils.parseFormattedDouble(row[4]) ?? 0;

        // 根據方向符號套用正負號
        final change = dirSign.contains('-')
            ? -rawChange.abs()
            : dirSign.contains('+')
            ? rawChange.abs()
            : rawChange;
        final changePercent = dirSign.contains('-')
            ? -rawChangePercent.abs()
            : dirSign.contains('+')
            ? rawChangePercent.abs()
            : rawChangePercent;

        return TwseMarketIndex(
          date: date,
          name: name,
          close: close,
          change: change,
          changePercent: changePercent,
        );
      },
    );
  }

  // ==================================================
  // 三大法人買賣金額統計 API
  // ==================================================

  /// 取得三大法人買賣金額統計（市場總計）
  ///
  /// 端點: /rwd/zh/fund/BFI82U
  /// 回傳外資、投信、自營商的買賣金額（元），可用於大盤總覽顯示
  ///
  /// [date] 可選，指定日期。省略則取最新。
  Future<TwseInstitutionalAmounts?> getInstitutionalAmounts({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '法人金額統計', () async {
      final queryParams = <String, dynamic>{'response': 'json'};
      if (date != null) {
        queryParams['dayDate'] = TwParseUtils.formatDateCompact(date);
      }

      final response = await _dio.get(
        ApiEndpoints.twseInstitutionalAmounts,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) return null;

      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '法人金額統計',
      );
      if (data == null) return null;

      final rows = MarketClientMixin.validateTwseStat(data, _tag, '法人金額統計');
      if (rows == null) return null;

      // 解析日期
      final dateStr = data['date']?.toString() ?? '';
      final parsedDate = TwParseUtils.parseAdDate(dateStr);

      // data 結構:
      // [["自營商(自行買賣)", "買進", "賣出", "買賣差額"],
      //  ["自營商(避險)", ...],
      //  ["投信", ...],
      //  ["外資及陸資(不含外資自營商)", ...],
      //  ["外資自營商", ...],
      //  ["合計", ...]]
      double foreignNet = 0;
      double trustNet = 0;
      double dealerNet = 0;
      double dealerHedgeNet = 0;

      for (final row in rows) {
        if (row is! List || row.length < 4) continue;
        final name = row[0]?.toString() ?? '';
        final netAmount = TwParseUtils.parseFormattedDouble(row[3]) ?? 0;

        if (name.contains('外資及陸資') && name.contains('不含')) {
          foreignNet = netAmount;
        } else if (name == '投信') {
          trustNet = netAmount;
        } else if (name == '自營商(自行買賣)') {
          dealerNet = netAmount;
        } else if (name == '自營商(避險)') {
          dealerHedgeNet = netAmount;
        }
      }

      return TwseInstitutionalAmounts(
        date: parsedDate,
        foreignNet: foreignNet,
        trustNet: trustNet,
        dealerNet: dealerNet + dealerHedgeNet, // 合併自營商
      );
    });
  }

  // ==================================================
  // Killer Features API (注意/處置股票)
  // ==================================================

  /// 取得上市注意股票清單
  ///
  /// 端點: /rwd/zh/announcement/notice
  ///
  /// 回傳交易量異常、價格異常波動的股票清單。
  /// 2025 年後端點變更，查詢參數改為 startDate/endDate。
  Future<List<TwseTradingWarning>> getTradingWarnings({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '注意股票', () async {
      final targetDate = date ?? DateTime.now();
      final dateStr = TwParseUtils.formatDateCompact(targetDate);

      final response = await _dio.get(
        ApiEndpoints.twseTradingWarning,
        queryParameters: {
          'response': 'json',
          'startDate': dateStr,
          'endDate': dateStr,
        },
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
        '注意股票',
      );
      if (data == null) return [];

      final rows = MarketClientMixin.validateTwseStat(data, _tag, '注意股票');
      if (rows == null) return [];

      final results = <TwseTradingWarning>[];
      for (final row in rows) {
        if (row is List && row.length >= 5) {
          final parsed = _parseTradingWarningRow(row, targetDate);
          if (parsed != null) results.add(parsed);
        }
      }

      AppLogger.info(_tag, '注意股票: ${results.length} 筆');
      return results;
    });
  }

  /// 解析注意股票資料列
  ///
  /// 2025 年後新格式:
  /// [編號, 證券代號, 證券名稱, 累計次數, 注意交易資訊, 日期, 收盤價, 本益比]
  TwseTradingWarning? _parseTradingWarningRow(
    List<dynamic> row,
    DateTime date,
  ) {
    return MarketClientMixin.safeParseRow(
      row: row,
      minLength: 3,
      tag: _tag,
      operation: '注意股票',
      parser: () {
        final code = row[1]?.toString().trim() ?? '';
        if (code.isEmpty || code.length < 4) return null;
        return TwseTradingWarning(
          date: date,
          code: code,
          reasonDescription: row.length > 4 ? row[4]?.toString().trim() : null,
          warningType: 'ATTENTION',
        );
      },
    );
  }

  /// 取得上市處置股票清單
  ///
  /// 端點: /rwd/zh/announcement/punish
  ///
  /// 回傳交易受限制的股票清單。
  /// 2025 年後端點變更，回傳現行有效的處置股票清單（無需日期參數）。
  Future<List<TwseTradingWarning>> getDisposalInfo({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '處置股票', () async {
      final targetDate = date ?? DateTime.now();

      final response = await _dio.get(
        ApiEndpoints.twseDisposal,
        queryParameters: {'response': 'json'},
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
        '處置股票',
      );
      if (data == null) return [];

      final rows = MarketClientMixin.validateTwseStat(data, _tag, '處置股票');
      if (rows == null) return [];

      final results = <TwseTradingWarning>[];
      for (final row in rows) {
        if (row is List && row.length >= 7) {
          final parsed = _parseDisposalRow(row, targetDate);
          if (parsed != null) results.add(parsed);
        }
      }

      AppLogger.info(_tag, '處置股票: ${results.length} 筆');
      return results;
    });
  }

  /// 解析處置股票資料列
  ///
  /// 2025 年後新格式:
  /// [編號, 公布日期, 證券代號, 證券名稱, 累計, 處置條件, 處置起迄時間, 處置措施, 處置內容, 備註]
  TwseTradingWarning? _parseDisposalRow(List<dynamic> row, DateTime date) {
    try {
      // 新格式: index 2 是證券代號
      final code = row[2]?.toString().trim() ?? '';
      if (code.isEmpty || code.length < 4) return null;

      // 解析處置期間（格式: "115/01/29～115/02/11"）
      DateTime? startDate;
      DateTime? endDate;
      final dateRange = row.length > 6 ? row[6]?.toString().trim() : null;
      if (dateRange != null && dateRange.contains('～')) {
        final parts = dateRange.split('～');
        if (parts.length == 2) {
          startDate = TwParseUtils.parseSlashRocDate(parts[0].trim());
          endDate = TwParseUtils.parseSlashRocDate(parts[1].trim());
        }
      }

      return TwseTradingWarning(
        date: date,
        code: code,
        reasonDescription: row.length > 8 ? row[8]?.toString().trim() : null,
        disposalMeasures: row.length > 7 ? row[7]?.toString().trim() : null,
        disposalStartDate: startDate,
        disposalEndDate: endDate,
        warningType: 'DISPOSAL',
      );
    } catch (e) {
      AppLogger.debug(_tag, '解析處置股票失敗: $e');
      return null;
    }
  }

  /// 取得上市董監持股資料（彙總版）
  ///
  /// 使用 TWSE OpenData，免費無限制。
  /// 1. 從 t187ap03_L 取得已發行股數
  /// 2. 從 t187ap11_L 取得個別董監持股記錄
  /// 3. 彙總計算每家公司的董監持股比例和質押比例
  ///
  /// 回傳彙總後的董監事持股資料（每家公司一筆）。
  Future<List<TwseInsiderHolding>> getInsiderHoldings() {
    return MarketClientMixin.executeRequest(_tag, '董監持股', () async {
      // 1. 取得已發行股數
      final issuedSharesMap = await _fetchIssuedShares();

      // 2. 取得個別董監持股記錄並彙總
      final companyData = await _fetchAndAggregateInsiderRecords();

      // 3. 計算比例並建立結果
      final results = _buildInsiderHoldingResults(companyData, issuedSharesMap);

      AppLogger.info(_tag, '董監持股彙總: ${results.length} 家公司');
      return results;
    });
  }

  /// 上市公司產業別代碼（t187ap03_L，免額度）
  ///
  /// 回傳 Map<公司代號, 產業別代碼>（如 2330→'24' 半導體業）。
  /// FinMind TaiwanStockInfo 給上市電子股的分類多為泛用「電子工業」，
  /// 細分要靠官方碼——見 IndustryNames.nameForTwseCode 的說明。
  /// 僅涵蓋上市公司（無 ETF/DR），缺席者由呼叫端 fallback。
  Future<Map<String, String>> fetchIndustryCodes() {
    // executeRequest 包裹(2026-08-01 補):初版仿 _fetchIssuedShares 的裸
    // _dio.get、零重試——force 更新對 TWSE openapi 連發十餘請求,此 fetch
    // 夾在中間被暫時性限流即陣亡,fail-soft 讓整輪退回 FinMind 分類、
    // 殭屍清理被 sanity floor 跳過(floor 防護正確,但根因是缺重試)。
    // 與其餘 client 方法一致走 mixin(帶重試+統一錯誤處理)。
    return MarketClientMixin.executeRequest(_tag, '官方產業別', () async {
      // 快取(2026-08-05 複審補):t187ap03_L 同端點被本方法與
      // _fetchIssuedShares 各下載一次/輪,零快取放大 openapi 連發壓力
      // ——正是重試要防的限流成因。走與其他端點一致的 LruCache。
      const cacheKey = 'industryCodes';
      final cached = _cache.get(cacheKey) as Map<String, String>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.twseStockInfo,
        options: Options(headers: {'Accept': 'application/json'}),
      );
      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }
      final data = response.data;
      // HTML 型限流分型(2026-08-05 複審補):TWSE 家族以 200+HTML 實作
      // 限流(mixin.decodeResponseData 明文記載),此時 data 是 String
      // ——擲 ApiException 會被 executeRequest 直接 rethrow 零重試;
      // 分型成 RateLimitException 讓上游熔斷鏈正確接手。
      if (data is String &&
          (data.trimLeft().startsWith('<!DOCTYPE') ||
              data.trimLeft().startsWith('<html'))) {
        AppLogger.warning(_tag, '官方產業別: 收到 HTML 回應（疑似 API 限流）');
        throw const RateLimitException('API 回傳 HTML 而非 JSON，疑似限流');
      }
      if (data is! List) {
        throw const ApiException('TWSE OpenData API error: 非預期資料型別', null);
      }
      final map = parseIndustryCodes(data);
      _cache.put(cacheKey, map);
      AppLogger.info(_tag, '官方產業別代碼: ${map.length} 家公司');
      return map;
    });
  }

  /// t187ap03_L 列 → (公司代號, 產業別) 對照；缺欄跳過。
  @visibleForTesting
  static Map<String, String> parseIndustryCodes(List<dynamic> data) {
    final out = <String, String>{};
    for (final row in data) {
      if (row is! Map) continue;
      final code = row['公司代號']?.toString() ?? '';
      final industry = row['產業別']?.toString() ?? '';
      if (code.isEmpty || industry.isEmpty) continue;
      out[code] = industry;
    }
    return out;
  }

  /// 從 TWSE OpenData 取得已發行股數
  ///
  /// 端點: t187ap03_L
  /// 回傳 Map<公司代號, 已發行股數>
  Future<Map<String, double>> _fetchIssuedShares() async {
    final stockInfoResponse = await _dio.get(
      ApiEndpoints.twseStockInfo,
      options: Options(headers: {'Accept': 'application/json'}),
    );

    final issuedSharesMap = stockInfoResponse.statusCode == 200
        ? InsiderHoldingAggregator.parseIssuedShares(
            stockInfoResponse.data,
            codeKey: '公司代號',
            sharesKey: '已發行普通股數或TDR原股發行股數',
          )
        : <String, double>{};

    AppLogger.debug(_tag, '已發行股數: ${issuedSharesMap.length} 家公司');
    return issuedSharesMap;
  }

  /// 從 TWSE OpenData 取得個別董監持股記錄並彙總
  ///
  /// 端點: t187ap11_L
  /// 只計算董事和監察人的「本人」記錄，使用姓名去重。
  /// 回傳 Map<公司代號, InsiderAggregation>
  Future<Map<String, InsiderAggregation>>
  _fetchAndAggregateInsiderRecords() async {
    final response = await _dio.get(
      ApiEndpoints.twseInsiderHolding,
      options: Options(headers: {'Accept': 'application/json'}),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        '$_tag OpenData error: ${response.statusCode}',
        response.statusCode,
      );
    }

    // 董監持股 API 回傳 List（Dio responseType: json 會自動解析）
    final data = response.data;
    if (data is! List) {
      AppLogger.warning(_tag, '董監持股: 非預期資料型別');
      return {};
    }

    // 彙總計算每家公司的董監持股（共用 aggregator，與 TPEx 同一套業務規則）
    return InsiderHoldingAggregator.aggregateRecords(
      data,
      codeFilter: (code) => code.length >= 4,
    );
  }

  /// 計算董監持股比例和質押比例，建立最終結果
  ///
  /// [companyData] - 彙總後的各公司董監持股資料
  /// [issuedSharesMap] - 各公司已發行股數
  List<TwseInsiderHolding> _buildInsiderHoldingResults(
    Map<String, InsiderAggregation> companyData,
    Map<String, double> issuedSharesMap,
  ) {
    return InsiderHoldingAggregator.buildRatios(companyData, issuedSharesMap)
        .map(
          (r) => TwseInsiderHolding(
            date: r.date,
            code: r.code,
            insiderRatio: r.insiderRatio,
            pledgeRatio: r.pledgeRatio,
            sharesIssued: r.sharesIssued,
          ),
        )
        .toList();
  }

  /// 取得上市已宣告股利
  ///
  /// 使用 TWSE Open Data API (t187ap45_L)。
  /// 回傳所有已宣告的除權息資料，含除息交易日、股東會日期等。
  /// 一次 API 呼叫取得全市場資料。
  Future<List<TwseDeclaredDividend>> getDeclaredDividends() {
    return MarketClientMixin.executeRequest(_tag, '已宣告股利', () async {
      const cacheKey = 'declaredDividend';
      final cached = _cache.get(cacheKey) as List<TwseDeclaredDividend>?;
      if (cached != null) return cached;

      final response = await _dio.get(ApiEndpoints.twseDeclaredDividend);

      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag OpenData API error: ${response.statusCode}',
          response.statusCode,
        );
      }

      final data = response.data;
      if (data is! List) {
        AppLogger.warning(_tag, '已宣告股利: 非預期資料型別');
        return [];
      }

      final results = <TwseDeclaredDividend>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = TwseDeclaredDividend.tryFromJson(item);
        if (parsed != null) results.add(parsed);
      }

      AppLogger.info(_tag, '已宣告股利: ${results.length} 筆');
      _cache.put(cacheKey, results);
      return results;
    });
  }

  /// 釋放底層 Dio HTTP 連線資源與 LRU 回應快取。
  ///
  /// 由 Riverpod provider 的 `ref.onDispose` 呼叫；ad-hoc 流程
  /// （如 `BackgroundUpdateService`）也應在 `try/finally` 中呼叫，
  /// 避免在 isolate exit 前持有 keep-alive socket。
  void close() {
    _dio.close(force: false);
    _cache.clear();
  }
}

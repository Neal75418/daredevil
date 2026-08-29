import 'dart:convert';
import 'dart:io' show HttpException, RedirectException, SocketException;
import 'dart:math';

import 'package:dio/dio.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/tw_parse_utils.dart';

/// TWSE / TPEX client 的共用工具。
///
/// 提供統一的 Dio 建立方式、JSON 解碼、以及錯誤處理，
/// 避免兩個 market client 之間的程式碼重複。
abstract final class MarketClientMixin {
  static const _maxRetries = ApiConfig.marketClientMaxRetries;
  static const _baseDelayMs = ApiConfig.retryDelayMs;
  static final _random = Random();

  /// 建立市場 API 用的 [Dio] 實例。
  ///
  /// 兩個市場共用相同的超時、Header 與回應類型設定。
  static Dio createDio(String baseUrl) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(
          seconds: ApiConfig.twseConnectTimeoutSec,
        ),
        receiveTimeout: const Duration(
          seconds: ApiConfig.twseReceiveTimeoutSec,
        ),
        headers: {
          'Accept': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
        responseType: ResponseType.json,
      ),
    );
  }

  /// 將 response.data 統一解碼為 [Map]。
  ///
  /// iOS 平台上 Dio 偶爾會回傳 JSON String 而非已解析的 Map，
  /// 此方法統一處理兩種情況。回傳 `null` 代表解碼失敗。
  static Map<String, dynamic>? decodeResponseData(
    Object? data,
    String tag,
    String operation,
  ) {
    var decoded = data;
    if (decoded is String) {
      // 偵測 HTML 回應（TWSE/TPEX 限流時回傳 HTML 頁面而非 JSON）
      // 大小寫不敏感(2026-08-08 二次審查):`<!doctype html>` 與 `<HTML>`
      // 都是合法 HTML,原本只比對大寫會把限流頁漏判成一般解析失敗 →
      // 被上層當「這批失敗」吞掉並繼續猛打
      final head = decoded.trimLeft().toLowerCase();
      if (head.startsWith('<!doctype') || head.startsWith('<html')) {
        AppLogger.warning(tag, '$operation: 收到 HTML 回應（疑似 API 限流）');
        throw const RateLimitException('API 回傳 HTML 而非 JSON，疑似限流');
      }
      try {
        decoded = jsonDecode(decoded);
      } catch (e) {
        AppLogger.warning(tag, '$operation: JSON 解析失敗', e);
        return null;
      }
    }
    if (decoded is! Map<String, dynamic>) {
      AppLogger.warning(tag, '$operation: 非預期資料型別');
      return null;
    }
    return decoded;
  }

  /// 統一的 API 請求錯誤處理（含自動重試）。
  ///
  /// 六業別 openapi 端點的逐一取用 + per-variant 隔離。
  ///
  /// TWSE/TPEx 的季報與資產負債表都是「同一份資料切成 6 個業別 endpoint」，
  /// 骨架原本抄了四份（2026-08-29 稽核；且已現漂移——TPEx 兩個端點的
  /// Accept header 一度不一致）。語意由
  /// `test/data/remote/industry_variant_isolation_test.dart` 逐條釘住：
  ///
  /// - **單一業別失敗記 warning、其餘照收**——金融業別平日常態零星，
  ///   單端點異常不該砍掉整份清單
  /// - **全滅才拋**（拋第一個錯）——全空不得偽裝成「今天沒資料」
  /// - [RateLimitException] 一律直接 rethrow，不降級成 warning
  /// - 非 200 / 非 List 型別：記為該業別失敗，其餘照收
  ///
  /// [endpointFor] 由 suffix 產生 URL；[parseRow] 把一列 JSON 轉成 0..n
  /// 個結果（季報一列一筆、資產負債表一列多筆）。
  static Future<List<T>> fetchIndustryVariants<T>({
    required String tag,
    required String label,
    required Dio dio,
    required List<String> suffixes,
    required String Function(String suffix) endpointFor,
    required Iterable<T> Function(Map<String, dynamic> row) parseRow,
    Options? options,
  }) async {
    final results = <T>[];
    var okVariants = 0;
    Object? firstError;
    for (final suffix in suffixes) {
      try {
        final response = await dio.get(endpointFor(suffix), options: options);
        if (response.statusCode != 200) {
          throw ApiException(
            '$tag OpenData API error: ${response.statusCode}',
            response.statusCode,
          );
        }
        final data = response.data;
        if (data is! List) {
          AppLogger.warning(tag, '$label($suffix): 非預期資料型別');
          continue;
        }
        for (final item in data) {
          if (item is! Map<String, dynamic>) continue;
          results.addAll(parseRow(item));
        }
        okVariants++;
      } on RateLimitException {
        rethrow;
      } catch (e) {
        AppLogger.warning(tag, '$label($suffix)失敗，其餘業別照收', e);
        firstError ??= e;
      }
    }
    if (okVariants == 0 && firstError != null) throw firstError;
    AppLogger.info(
      tag,
      '$label: ${results.length} 筆($okVariants/${suffixes.length} 業別)',
    );
    return results;
  }

  /// 包裝 [fn] 的執行，將 [DioException] 轉換為 [NetworkException]，
  /// 並記錄錯誤日誌。[tag] 為日誌標籤（如 'TWSE'），[operation] 為操作描述。
  ///
  /// 可重試的錯誤（逾時、連線失敗、5xx）會自動重試最多 [_maxRetries] 次，
  /// 使用指數退避 + 抖動。不可重試的錯誤（4xx、解析錯誤）立即拋出。
  static Future<T> executeRequest<T>(
    String tag,
    String operation,
    Future<T> Function() fn,
  ) async {
    int attempt = 0;

    while (attempt <= _maxRetries) {
      try {
        return await fn();
      } on DioException catch (e, stack) {
        // TWSE/TPEX 透過 redirect loop 實作 rate limiting，
        // 偵測到時直接視為限流（讓上游 circuit breaker 正確觸發）
        if (_isRedirectLoop(e)) {
          AppLogger.warning(
            tag,
            '$operation: Redirect loop 偵測為 API 限流',
            e,
            stack,
          );
          throw const RateLimitException(
            'Redirect loop detected (API rate limiting)',
          );
        }

        // 不可重試的錯誤：立即拋出
        if (!_isRetryable(e)) {
          // connectionTimeout 恆可重試（_isRetryable）不會進到這裡；
          // 此分支只有 receiveTimeout 會命中
          if (e.type == DioExceptionType.receiveTimeout) {
            AppLogger.warning(tag, '$operation: 接收逾時', e, stack);
            throw NetworkException('$tag receive timeout', e);
          }
          AppLogger.warning(
            tag,
            '$operation: ${e.message ?? "網路錯誤"}',
            e,
            stack,
          );
          throw NetworkException(e.message ?? '$tag network error', e);
        }

        // 可重試的錯誤：嘗試重試
        attempt++;
        if (attempt <= _maxRetries) {
          AppLogger.info(
            tag,
            '$operation: 重試 $attempt/$_maxRetries (${_errorLabel(e)})',
          );
          await _delay(attempt);
          continue;
        }

        // 重試耗盡
        AppLogger.warning(
          tag,
          '$operation: 重試 $_maxRetries 次後仍失敗 (${_errorLabel(e)})',
          e,
          stack,
        );
        throw NetworkException(
          '$tag request failed after $_maxRetries retries',
          e,
        );
      } on AppException {
        rethrow;
      } catch (e, stack) {
        AppLogger.error(tag, '$operation: 非預期錯誤', e, stack);
        rethrow;
      }
    }

    // 理論上不會到達（while 迴圈內的每條路徑都會 return/throw/continue）
    throw NetworkException('$tag request failed unexpectedly');
  }

  /// 判斷 [DioException] 是否為 redirect loop。
  ///
  /// TWSE/TPEX 透過 HTTP redirect loop 實作 rate limiting，
  /// Dio 偵測到迴圈重導時拋出內含 `RedirectException` 的 [DioException]。
  static bool _isRedirectLoop(DioException e) {
    return e.error is RedirectException ||
        '${e.error}'.contains('Redirect loop');
  }

  /// 判斷 [DioException] 是否可重試。
  ///
  /// 連線逾時、發送逾時、連線錯誤、5xx、SocketException、HttpException 可重試。
  /// receiveTimeout 不重試：伺服器已接受連線但不回應，通常是限流，重試無意義。
  /// 4xx 等客戶端錯誤不重試。
  /// 錯誤標籤:具體型別直接用,`unknown` 補上底層原因。
  ///
  /// `DioExceptionType.unknown` 涵蓋所有「不是 timeout、不是 4xx/5xx」的
  /// 底層錯誤——socket 重置、DNS 失敗、IO 錯誤全都長這樣。2026-08-16 實機:
  /// TPEx 董監持股卡了 85 秒(前一輪同段只花 0.4 秒),日誌只留下
  /// `重試 1/2 (unknown)`,分不出是網路重置還是對方限流。原因其實就在
  /// `e.error` 裡——[_isRetryable] 的 default 分支正是靠它判斷可重試。
  ///
  /// 同 intraday「報價全滅四個字分不出 timeout/DNS/連線重置/限流」的教訓,
  /// 那邊 2026-08-12 修了、這條共用路徑沒修。
  static String _errorLabel(DioException e) {
    if (e.type != DioExceptionType.unknown) return e.type.name;
    final cause = e.error ?? e.message;
    return cause == null ? e.type.name : '${e.type.name}: $cause';
  }

  static bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        return statusCode != null && statusCode >= 500;
      default:
        // Connection reset / connection closed 等錯誤可重試
        return e.error is SocketException || e.error is HttpException;
    }
  }

  // ==================================================
  // 回應驗證與解析 Helper
  // ==================================================
  //
  // 錯誤處理慣例：
  // - 非 200 HTTP status → 呼叫端 throw ApiException
  // - stat != 'OK' / 空資料 → 回傳 null（非交易日正常情況）
  // - 個別 row 解析失敗 → 跳過，debug log

  /// 驗證 TWSE stat-based 回應。
  ///
  /// TWSE API 在 stat == 'OK' 且 data 存在時才是有效回應。
  /// 回傳 data 中的 rows，無資料時回傳 null。
  static List<dynamic>? validateTwseStat(
    Map<String, dynamic> data,
    String tag,
    String operation,
  ) {
    final stat = data['stat'];
    if (stat != 'OK' || data['data'] == null) {
      AppLogger.warning(tag, '$operation: 無資料 (stat=$stat)');
      return null;
    }
    return data['data'] as List<dynamic>;
  }

  /// 提取 TPEX tables 格式回應中的資料。
  ///
  /// TPEX API 回傳 `{ tables: [{ date: "...", data: [...] }] }` 格式。
  /// 回傳 (actualDate, rows) record，無資料時回傳 null。
  static ({DateTime date, List<dynamic> rows})? extractTpexTable(
    Map<String, dynamic> data,
    DateTime fallbackDate,
    String tag,
    String operation,
  ) {
    final tables = data['tables'] as List<dynamic>?;
    if (tables == null || tables.isEmpty) {
      AppLogger.warning(tag, '$operation: 無 tables');
      return null;
    }

    final firstTable = tables[0] as Map<String, dynamic>?;
    if (firstTable == null) {
      AppLogger.warning(tag, '$operation: 無資料表');
      return null;
    }

    final dateStr = firstTable['date'] as String?;
    final actualDate =
        (dateStr != null ? TwParseUtils.parseSlashRocDate(dateStr) : null) ??
        fallbackDate;

    final rows = firstTable['data'] as List<dynamic>?;
    if (rows == null || rows.isEmpty) {
      AppLogger.warning(tag, '$operation: 無資料');
      return null;
    }

    return (date: actualDate, rows: rows);
  }

  /// 安全解析單一資料列。
  ///
  /// 包裝 [parser] 的執行，先檢查 [row] 長度是否 >= [minLength]，
  /// 解析失敗時記錄 debug log 並回傳 null（不中斷整體解析）。
  static T? safeParseRow<T>({
    required List<dynamic> row,
    required int minLength,
    required String tag,
    required String operation,
    required T? Function() parser,
  }) {
    try {
      if (row.length < minLength) return null;
      return parser();
    } catch (e) {
      AppLogger.debug(tag, '解析$operation失敗: $e');
      return null;
    }
  }

  /// 統一解析資料 rows 並記錄結果日誌。
  ///
  /// 逐 row 套用 [parser]，跳過回傳 null 的 row。
  /// 結束後輸出 info log 含成功筆數、日期、略過筆數。
  static List<T> parseRows<T>({
    required List<dynamic> rows,
    required T? Function(List<dynamic> row) parser,
    required String tag,
    required String operation,
    required DateTime date,
  }) {
    var failedCount = 0;
    final results = <T>[];

    for (final row in rows) {
      final parsed = parser(row as List<dynamic>);
      if (parsed != null) {
        results.add(parsed);
      } else {
        failedCount++;
      }
    }

    final dateFormatted = TwParseUtils.formatDateYmd(date);
    if (failedCount > 0) {
      AppLogger.info(
        tag,
        '$operation: ${results.length} 筆 ($dateFormatted, 略過 $failedCount 筆)',
      );
    } else {
      AppLogger.info(tag, '$operation: ${results.length} 筆 ($dateFormatted)');
    }

    return results;
  }

  /// 指數退避延遲（含 ±25% 抖動）。
  static Future<void> _delay(int attempt) async {
    final exponentialDelay = _baseDelayMs * (1 << (attempt - 1));
    final jitter = (_random.nextDouble() - 0.5) * 0.5 * exponentialDelay;
    await Future.delayed(
      Duration(milliseconds: (exponentialDelay + jitter).round()),
    );
  }
}

import 'dart:math' show Random;

import 'package:dio/dio.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/lru_cache.dart';
import 'package:daredevil/data/models/finmind/models.dart';
import 'package:daredevil/data/remote/api_budget_tracker.dart';
export 'package:daredevil/data/models/finmind/models.dart';

/// FinMind API 客戶端（台股市場資料）
///
/// 流量限制:
/// - 匿名: 300 次/小時
/// - 有 token: 600 次/小時
///
/// 每位使用者應自行註冊並使用個人 token。
class FinMindClient {
  FinMindClient({
    Dio? dio,
    String? token,
    int maxRetries = 3,
    Duration baseDelay = const Duration(
      milliseconds: ApiConfig.finmindBaseDelayMs,
    ),
    Duration cacheTtl = const Duration(minutes: 30),
    ApiBudgetTracker? budgetTracker,
  }) : _dio = dio ?? _createDio(),
       _token = token,
       _maxRetries = maxRetries,
       _baseDelay = baseDelay,
       _cacheTtl = cacheTtl,
       _budgetTracker = budgetTracker;

  /// Process-local 跨 syncer API 預算追蹤；null 代表 caller 沒注入（測試
  /// 或 ad-hoc 使用），略過 budget check（保留舊行為相容性）。
  final ApiBudgetTracker? _budgetTracker;

  /// 過去 1 小時的實際 FinMind 呼叫數與該 vendor 的額度。
  ///
  /// 未注入 tracker 時回 **null 而非 0**：0 會被讀成「這輪沒打 API」，
  /// 那是把預設值當成量測結果。
  ///
  /// 存在的理由：各 syncer 過去自行「估算」呼叫數，而估算會錯得很離譜——
  /// 2026-07-26 實測一次更新報 94 calls、真實約 2 次（高報 47 倍）；
  /// 2026-07-27 追查上櫃財報覆蓋率時，靜態讀 code 又連續三次估錯誰在吃額度。
  /// 高報的方向特別有害：會讓人以為配額已緊而不敢調高上櫃相關的上限，
  /// 而那正是上櫃資料涵蓋率上不去的懷疑對象。
  ({int used, int budget})? get hourlyUsage {
    final tracker = _budgetTracker;
    if (tracker == null) return null;
    return (
      used: tracker.callsInLastHourFor(ApiVendor.finMind),
      budget: tracker.budgetFor(ApiVendor.finMind),
    );
  }

  static const String baseUrl = ApiEndpoints.finmindBaseUrl;

  /// Token 最小有效長度
  static const int _minTokenLength = 20;

  /// Token 格式正規表達式（支援 JWT 格式：英數字、底線、連字號、句點）
  static final RegExp _tokenPattern = RegExp(r'^[a-zA-Z0-9_.\-]+$');

  final Dio _dio;
  final int _maxRetries;
  final Duration _baseDelay;
  final Duration _cacheTtl;
  final Random _random = Random();

  /// API response 快取
  ///
  /// 盤後資料不常變動，快取可大幅減少 API 呼叫次數。
  /// TTL 由使用者設定決定（預設 30 分鐘）。
  late final LruCache<String, List<Map<String, dynamic>>> _responseCache =
      LruCache(
        maxSize: CacheConfig.finmindResponseCacheMaxSize,
        ttl: _cacheTtl,
      );

  /// 使用者的 FinMind API token（選用但建議設定）
  String? _token;

  /// 取得目前的 token
  String? get token => _token;

  /// 設定 token（含驗證）
  ///
  /// 若 token 格式無效則拋出 [InvalidTokenException]
  set token(String? value) {
    if (value != null && value.isNotEmpty) {
      _validateToken(value);
    }
    _token = value;
  }

  /// 驗證 token 格式
  ///
  /// 驗證失敗時拋出 [InvalidTokenException]
  static void _validateToken(String token) {
    if (token.length < _minTokenLength) {
      // 訊息使用字面值以允許 const（不能引用 _minTokenLength）
      throw const InvalidTokenException(
        'Token too short (minimum 20 characters)',
      );
    }
    if (!_tokenPattern.hasMatch(token)) {
      throw const InvalidTokenException('Token contains invalid characters');
    }
  }

  /// 驗證 token 格式但不設定
  ///
  /// 有效回傳 true，無效回傳 false
  static bool isValidTokenFormat(String? token) {
    if (token == null || token.isEmpty) return false;
    if (token.length < _minTokenLength) return false;
    return _tokenPattern.hasMatch(token);
  }

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(
          seconds: ApiConfig.finmindConnectTimeoutSec,
        ),
        receiveTimeout: const Duration(
          seconds: ApiConfig.finmindReceiveTimeoutSec,
        ),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  /// 建立查詢參數（含選用的 token）
  Map<String, dynamic> _buildParams(Map<String, dynamic> params) {
    final result = Map<String, dynamic>.from(params);
    if (_token?.isNotEmpty ?? false) {
      result['token'] = _token;
    }
    return result;
  }

  /// 產生快取鍵（依參數鍵排序以確保一致性）
  String _cacheKey(Map<String, dynamic> params) {
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => '${e.key}=${e.value}').join('&');
  }

  // 建立請求標籤供日誌使用
  String _buildRequestLabel(Map<String, dynamic> params) {
    final dataset = params['dataset']?.toString() ?? '';
    final stockId =
        params['data_id']?.toString() ?? params['stock_id']?.toString() ?? '';
    return stockId.isNotEmpty ? '$dataset($stockId)' : dataset;
  }

  // 快取查詢（回傳複本，避免呼叫端修改快取內容）
  List<Map<String, dynamic>>? _checkCache(
    Map<String, dynamic> params,
    String label,
  ) {
    final cacheKey = _cacheKey(params);
    final cached = _responseCache.get(cacheKey);
    if (cached != null) {
      AppLogger.debug('FinMind', '$label: cache hit (${cached.length} 筆)');
      return List<Map<String, dynamic>>.from(cached);
    }
    return null;
  }

  /// 處理 HTTP 200 回應：檢查 API 錯誤、快取結果、回傳資料
  List<Map<String, dynamic>> _handleSuccessResponse(
    Response<dynamic> response,
    Map<String, dynamic> params,
    String label,
  ) {
    final data = response.data;

    // 檢查 API 錯誤回應
    if (data['status'] != null && data['status'] != 200) {
      final msg = data['msg'] ?? 'Unknown API error';
      final msgStr = msg.toString();

      // 流量限制檢查
      if (msgStr.contains('limit') || msgStr.contains('quota')) {
        AppLogger.warning('FinMind', '$label: 流量限制');
        throw const RateLimitException();
      }

      // 付費功能檢查 (批次 API 需要贊助者)
      if (msgStr.contains('level is free') || msgStr.contains('Sponsor')) {
        AppLogger.debug('FinMind', '$label: 此功能需要付費會員 (贊助者)');
        throw const ApiException('批次 API 需要付費會員資格', 400);
      }

      AppLogger.warning('FinMind', '$label: $msgStr');
      throw ApiException(msgStr, data['status'] as int?);
    }

    // 回傳資料陣列
    final cacheKey = _cacheKey(params);
    final dataList = data['data'];
    if (dataList is List) {
      final result = dataList.whereType<Map<String, dynamic>>().toList();
      _responseCache.put(cacheKey, List.unmodifiable(result));
      AppLogger.debug('FinMind', '$label: ${result.length} 筆');
      return result;
    }
    // 空結果也快取，避免重複對同一參數請求 API
    _responseCache.put(cacheKey, const []);
    AppLogger.debug('FinMind', '$label: 0 筆');
    return [];
  }

  /// 將 DioException 轉換為適當的應用例外（總是拋出，不回傳）
  Never _handleDioException(DioException e, String label, int attempt) {
    // 轉換為適當的例外
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      AppLogger.warning('FinMind', '$label: 連線逾時 (重試 $attempt 次)');
      throw NetworkException('Connection timeout after $attempt attempts', e);
    }
    if (e.response?.statusCode == 429) {
      // 429 → 立即拋 RateLimitException（配額型限流不做 client 端重試，
      // 由預算 cooldown + rateLimitedAbort 承接）
      AppLogger.warning('FinMind', '$label: 429 流量限制，等待重試');
      _budgetTracker?.markRateLimited(ApiVendor.finMind);
      throw const RateLimitException();
    }
    if (e.response?.statusCode == 402) {
      // 402 Payment Required = API 額度耗盡，不重試直接拋出
      AppLogger.warning('FinMind', '$label: 402 API 額度耗盡');
      _budgetTracker?.markRateLimited(ApiVendor.finMind);
      throw const RateLimitException('API 額度已用完，請稍後再試');
    }
    AppLogger.warning('FinMind', '$label: 網路錯誤', e);
    throw NetworkException(e.message ?? 'Network error', e);
  }

  /// 通用請求處理器（含錯誤對應和重試邏輯）
  Future<List<Map<String, dynamic>>> _request(
    Map<String, dynamic> params,
  ) async {
    final label = _buildRequestLabel(params);

    final cached = _checkCache(params, label);
    if (cached != null) return cached;

    // 每次 request 前查跨 syncer 共享的預算 + cooldown；超預算/cooldown
    // 直接拋 RateLimitException、不發出網路請求。
    _budgetTracker?.checkBudget(ApiVendor.finMind);

    int attempt = 0;
    Object? lastError;

    while (attempt <= _maxRetries) {
      try {
        _budgetTracker?.recordCall(ApiVendor.finMind);
        final response = await _dio.get(
          '',
          queryParameters: _buildParams(params),
        );

        if (response.statusCode == 200) {
          return _handleSuccessResponse(response, params, label);
        }

        // 伺服器錯誤 (5xx) 可重試
        if (response.statusCode != null && response.statusCode! >= 500) {
          lastError = ApiException(
            'Server error: ${response.statusCode}',
            response.statusCode,
          );
          attempt++;
          if (attempt <= _maxRetries) {
            await _delay(attempt);
            continue;
          }
        }

        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          response.statusCode,
        );
      } on DioException catch (e) {
        lastError = e;

        // 檢查此錯誤是否可重試
        if (_isRetryable(e)) {
          attempt++;
          if (attempt <= _maxRetries) {
            await _delay(attempt);
            continue;
          }
        }

        _handleDioException(e, label, attempt);
      } on RateLimitException {
        // 巢狀呼叫的流量限制 - 達到最大重試次數後仍重新拋出
        rethrow;
      } on ApiException catch (e) {
        // 不重試客戶端錯誤（流量限制除外，已在上方處理）
        if (e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500) {
          rethrow;
        }
        lastError = e;
        attempt++;
        if (attempt <= _maxRetries) {
          await _delay(attempt);
          continue;
        }
        rethrow;
      }
    }

    // 所有重試次數已用盡
    if (lastError is Exception) {
      throw lastError;
    }
    throw NetworkException('Request failed after $_maxRetries retries');
  }

  /// 檢查 DioException 是否可重試
  bool _isRetryable(DioException e) {
    // 網路相關錯誤可重試
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        // 伺服器錯誤 (5xx) 重試，客戶端錯誤 (4xx 含 429) 不重試——
        // 429 是小時配額型限流，重試只會多燒配額（每次 retry 都會
        // recordCall），立即拋 RateLimitException 交給預算 cooldown +
        // rateLimitedAbort（2026-07-23 稽核修復，與 MarketClientMixin 對齊）
        final statusCode = e.response?.statusCode;
        return statusCode != null && statusCode >= 500;
      default:
        return false;
    }
  }

  /// 計算指數退避延遲（含抖動）
  ///
  /// 僅用於網路/5xx 類可重試錯誤。429 不在此重試——FinMind 是小時配額型
  /// 限流，秒級退避救不了配額耗盡，正確路徑是立即拋 RateLimitException
  /// → 預算 cooldown → rateLimitedAbort 止血、下次更新續傳。
  Future<void> _delay(int attempt) async {
    final baseMs = _baseDelay.inMilliseconds;
    // 指數退避: baseDelay * 2^(attempt-1)
    final exponentialDelay = baseMs * (1 << (attempt - 1));
    // 加入抖動: ±25% 延遲
    final jitter = (_random.nextDouble() - 0.5) * 0.5 * exponentialDelay;
    final totalDelay = Duration(
      milliseconds: (exponentialDelay + jitter).round(),
    );
    await Future.delayed(totalDelay);
  }

  /// 通用日期範圍查詢
  ///
  /// 用於所有「按股票代碼 + 日期範圍」查詢的 API 方法。
  /// [dataset]: FinMind 資料集名稱
  /// [stockId]: 股票代碼（選用，批次查詢可省略）
  /// [fromJson]: 反序列化函數，回傳 null 表示跳過該筆
  /// [stockIdKey]: 股票代碼參數名稱（預設 'data_id'）
  Future<List<T>> _fetchDateRange<T>({
    required String dataset,
    String? stockId,
    required String startDate,
    String? endDate,
    required T? Function(Map<String, dynamic>) fromJson,
    String stockIdKey = 'data_id',
  }) async {
    final params = <String, String>{
      'dataset': dataset,
      'start_date': startDate,
    };

    if (stockId != null) {
      params[stockIdKey] = stockId;
    }

    if (endDate != null) {
      params['end_date'] = endDate;
    }

    final data = await _request(params);
    return data.map(fromJson).whereType<T>().toList();
  }

  /// 取得台股股票清單
  ///
  /// 資料集: TaiwanStockInfo
  /// 註: 格式錯誤的記錄會被靜默跳過
  Future<List<FinMindStockInfo>> getStockList() async {
    final data = await _request({'dataset': 'TaiwanStockInfo'});

    // 使用 tryFromJson 跳過格式錯誤的記錄
    return data
        .map((json) => FinMindStockInfo.tryFromJson(json))
        .whereType<FinMindStockInfo>()
        .toList();
  }

  /// 取得每日股價
  ///
  /// 資料集: TaiwanStockPrice
  /// [stockId]: 股票代碼（例如 "2330"）
  /// [startDate]: 起始日期（YYYY-MM-DD）
  /// [endDate]: 結束日期（選用）
  Future<List<FinMindDailyPrice>> getDailyPrices({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockPrice',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindDailyPrice.tryFromJson,
  );

  /// 取得單檔當沖歷史（`TaiwanStockDayTrading`）
  ///
  /// **只給回補用**。每日同步走免費官方端點；這裡吃 FinMind 600/hr 額度，
  /// 逐檔一次呼叫可拉整段區間（實測 2024-01～2026-08 單檔 606 筆一次回完），
  /// 所以成本是「檔數」而非「檔數 × 天數」。免付費層不支援不帶 `data_id`
  /// 的全市場查詢（回 `Your level is free`），故只能逐檔。
  Future<List<FinMindDayTrading>> getDayTrading({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockDayTrading',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindDayTrading.tryFromJson,
  );

  /// 取得日期範圍內所有股票價格（批次）
  ///
  /// 用於高效批量擷取
  /// 註: 格式錯誤的記錄會被靜默跳過
  Future<List<FinMindDailyPrice>> getAllDailyPrices({
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockPrice',
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindDailyPrice.tryFromJson,
  );

  /// 取得三大法人買賣超資料
  ///
  /// 資料集: TaiwanStockInstitutionalInvestorsBuySell
  /// 註: API 每種法人類型回傳一列，此方法依日期彙整
  Future<List<FinMindInstitutional>> getInstitutionalData({
    required String stockId,
    required String startDate,
    String? endDate,
  }) async {
    final params = {
      'dataset': 'TaiwanStockInstitutionalInvestorsBuySell',
      'data_id': stockId,
      'start_date': startDate,
    };

    if (endDate != null) {
      params['end_date'] = endDate;
    }

    final data = await _request(params);

    // 解析原始資料列
    final rows = data
        .map((json) {
          try {
            return FinMindInstitutionalRow.fromJson(json);
          } catch (e) {
            AppLogger.debug('FinMind', '解析法人資料列失敗: ${json['stock_id']} ($e)');
            return null;
          }
        })
        .whereType<FinMindInstitutionalRow>()
        .toList();

    // 依日期分組並彙整
    final Map<String, List<FinMindInstitutionalRow>> byDate = {};
    for (final row in rows) {
      if (row.date.isEmpty) continue;
      byDate.putIfAbsent(row.date, () => []).add(row);
    }

    // 轉換為彙整記錄
    return byDate.entries
        .map((entry) {
          try {
            return FinMindInstitutional.aggregate(entry.value);
          } catch (e) {
            AppLogger.debug('FinMind', '彙整法人資料失敗: ${entry.key} ($e)');
            return null;
          }
        })
        .whereType<FinMindInstitutional>()
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 取得月營收資料
  ///
  /// 資料集: TaiwanStockMonthRevenue
  Future<List<FinMindRevenue>> getMonthlyRevenue({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockMonthRevenue',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindRevenue.tryFromJson,
  );

  /// 取得日期範圍內所有股票月營收（批次）
  ///
  /// 用於高效批量擷取，省略 data_id 取得全市場資料。
  /// 一次 API 呼叫可取得所有股票的營收資料。
  Future<List<FinMindRevenue>> getAllMonthlyRevenue({
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockMonthRevenue',
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindRevenue.tryFromJson,
  );

  /// 取得股利資料
  ///
  /// 資料集: TaiwanStockDividend
  Future<List<FinMindDividend>> getDividends({
    required String stockId,
    String? startDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockDividend',
    stockId: stockId,
    // 未指定時預設為 5 年前
    startDate: startDate ?? '${DateTime.now().year - 5}-01-01',
    fromJson: FinMindDividend.tryFromJson,
  );

  /// 取得本益比/股價淨值比資料
  ///
  /// 資料集: TaiwanStockPER
  Future<List<FinMindPER>> getPERData({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockPER',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindPER.tryFromJson,
  );

  /// 檢查是否已設定 token
  bool get hasToken => _token?.isNotEmpty ?? false;

  // ==================================================
  // 延伸市場資料 API
  // ==================================================

  /// 取得外資持股比例資料
  ///
  /// 資料集: TaiwanStockShareholding
  /// 回傳: 外資持股比例歷史資料
  Future<List<FinMindShareholding>> getShareholding({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockShareholding',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindShareholding.tryFromJson,
  );

  /// 取得綜合損益表資料
  ///
  /// 資料集: TaiwanStockFinancialStatements
  /// 回傳: 按季度的損益表資料
  Future<List<FinMindFinancialStatement>> getFinancialStatements({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockFinancialStatements',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindFinancialStatement.tryFromJson,
  );

  /// 取得資產負債表資料
  ///
  /// 資料集: TaiwanStockBalanceSheet
  /// 回傳: 按季度的資產負債表資料
  Future<List<FinMindBalanceSheet>> getBalanceSheet({
    required String stockId,
    required String startDate,
    String? endDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockBalanceSheet',
    stockId: stockId,
    startDate: startDate,
    endDate: endDate,
    fromJson: FinMindBalanceSheet.tryFromJson,
  );

  /// 取得含息報酬指數（加權股價指數含息版本）
  ///
  /// 資料集: TaiwanStockTotalReturnIndex
  /// stock_id 固定為 'TAIEX'
  /// 回傳: 每日含息報酬指數（反映股息再投資的累積報酬）
  Future<List<FinMindTotalReturnIndex>> getTotalReturnIndex({
    String? startDate,
  }) => _fetchDateRange(
    dataset: 'TaiwanStockTotalReturnIndex',
    stockId: 'TAIEX',
    startDate:
        startDate ??
        () {
          final d = DateTime.now().subtract(
            const Duration(days: DataFreshness.totalReturnIndexLookbackDays),
          );
          return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        }(),
    fromJson: FinMindTotalReturnIndex.tryFromJson,
  );

  /// 釋放底層 Dio HTTP 連線資源。
  ///
  /// 由 Riverpod provider 的 `ref.onDispose` 呼叫；當 `cacheDurationProvider`
  /// invalidate 重建 client 時也要呼叫此方法，避免舊 Dio 持續持有 socket。
  void close() {
    _dio.close(force: false);
    _responseCache.clear();
  }
}

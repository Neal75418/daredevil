import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';

/// 一輪報價抓取的結果:成功的報價 + 失敗批次的錯誤摘要
typedef QuoteFetchResult = ({
  Map<String, IntradayQuote> quotes,
  List<String> errors,
});

/// 一輪報價抓取的逐批明細(盤中即時報價用,2026-10-06)。
///
/// 每個送出的代號恰好落在 [respondedSymbols] 或 [failedSymbols] 其中之一:
/// - **有回應**:HTTP 200、`rtcode` 為 `0000`、`msgArray` 有列。列可能全被
///   解析丟掉(例如暫停交易),那仍算有回應——報價中心據此區分「證交所
///   今天尚無報價」與「網路斷了」。
/// - **失敗**:網路錯誤、非 200、無法解碼、`rtcode` 非 `0000`、`msgArray`
///   沒有列。
class QuoteBatchReport {
  const QuoteBatchReport({
    required this.quotes,
    required this.errors,
    required this.respondedSymbols,
    required this.failedSymbols,
  });

  final Map<String, IntradayQuote> quotes;

  /// 例外造成的批次失敗摘要(同 [QuoteFetchResult] 的 errors);`rtcode`
  /// 非 `0000`、沒有列、無法解碼不產生字串,只計入 [failedSymbols]
  final List<String> errors;
  final Set<String> respondedSymbols;
  final Set<String> failedSymbols;
}

/// 盤中即時報價 client(TWSE MIS,2026-08-08)。
///
/// **不快取**:這支的存在理由就是即時性,快取等於自我否定。
/// 分批送出(單次上限 [ApiEndpoints.misBatchSize] 檔),任何一批失敗
/// 不影響其他批——盤中提醒缺一檔比整批沒有好。
class IntradayQuoteClient {
  IntradayQuoteClient({Dio? dio, bool logBatchErrors = true})
    : _dio = dio ?? MarketClientMixin.createDio(ApiEndpoints.twseMisIntraday),
      _logBatchErrors = logBatchErrors;

  static const String _tag = 'MIS';
  final Dio _dio;

  /// 單批失敗是否記 `AppLogger.warning`。盤中即時報價每 15 秒一輪,失敗改
  /// 由報價中心統一記(一段連續失敗只記開始與恢復),所以傳 false;盤中
  /// 提醒與 CLI 維持預設。
  final bool _logBatchErrors;

  @visibleForTesting
  Dio get dio => _dio;

  @visibleForTesting
  bool get logsBatchErrors => _logBatchErrors;

  /// [markets] 為 symbol → 市場別(`TWSE`/`TPEx`),決定 `tse_`/`otc_` 前綴。
  /// 猜錯前綴會回不到報價(2026-08-07 實測:大量 3167 是上市不是上櫃)。
  ///
  /// [errors] 是失敗批次的「型別+訊息」摘要,錯誤是結果的一部分而非側信道:
  /// 批次錯誤原本只進 `AppLogger.warning`,而 launchd 跑的是 AOT 編譯 CLI
  /// ——AppLogger 靠 assert 判定 debug,AOT 下**全靜默**。結果 8/11–8/12
  /// 共 21 輪早盤失敗,日誌只有「報價全滅」,無從分辨 timeout/DNS/限流
  /// (2026-08-12 盲區調查)。
  Future<QuoteFetchResult> fetchQuotes(Map<String, String> markets) async {
    if (markets.isEmpty) {
      return (
        quotes: const <String, IntradayQuote>{},
        errors: const <String>[],
      );
    }
    final symbols = markets.keys.toList();
    final result = <String, IntradayQuote>{};
    final errors = <String>[];

    for (final batch in _batches(symbols)) {
      try {
        final data = await _requestBatch(batch, markets);
        if (data != null) result.addAll(IntradayQuote.parseResponse(data));
      } on RateLimitException {
        rethrow;
      } catch (e) {
        // 單批失敗不影響其他批:盤中缺一檔報價 > 整批沒有
        _warnBatchFailed(batch.length, e);
        errors.add(_describeError(e));
      }
    }
    AppLogger.debug(_tag, '盤中報價: ${result.length}/${symbols.length} 檔');
    return (quotes: result, errors: errors);
  }

  /// 同 [fetchQuotes],另回報每個代號所在的批次有沒有回應(見
  /// [QuoteBatchReport])。限流照樣拋 [RateLimitException]。
  ///
  /// 解析不包在 try 內:解析拋例外是程式錯誤、不是網路狀況,往上拋給報價
  /// 中心記 error;[fetchQuotes] 為維持盤中提醒的行為,仍把它當成該批失敗。
  Future<QuoteBatchReport> fetchQuotesDetailed(
    Map<String, String> markets,
  ) async {
    final quotes = <String, IntradayQuote>{};
    final errors = <String>[];
    final responded = <String>{};
    final failed = <String>{};

    for (final batch in _batches(markets.keys.toList())) {
      Map<String, dynamic>? data;
      try {
        data = await _requestBatch(batch, markets);
      } on RateLimitException {
        rethrow;
      } catch (e) {
        _warnBatchFailed(batch.length, e);
        errors.add(_describeError(e));
        failed.addAll(batch);
        continue;
      }
      final rows = data?['msgArray'];
      if (data == null ||
          data['rtcode'] != '0000' ||
          rows is! List ||
          rows.isEmpty) {
        failed.addAll(batch);
        continue;
      }
      responded.addAll(batch);
      quotes.addAll(IntradayQuote.parseResponse(data));
    }
    return QuoteBatchReport(
      quotes: quotes,
      errors: errors,
      respondedSymbols: responded,
      failedSymbols: failed,
    );
  }

  /// 送出一批(≤ [ApiEndpoints.misBatchSize] 檔)並解碼:無法解碼回 null,
  /// 限流拋 [RateLimitException],非 200 拋 [ApiException]
  Future<Map<String, dynamic>?> _requestBatch(
    List<String> batch,
    Map<String, String> markets,
  ) async {
    final exCh = batch
        .map((s) => '${markets[s] == MarketCode.twse ? 'tse' : 'otc'}_$s.tw')
        .join('|');
    final response = await _dio.get(
      ApiEndpoints.twseMisIntraday,
      queryParameters: {'ex_ch': exCh, 'json': 1, 'delay': 0},
      // 一律取原始字串自行解碼(2026-08-08 code review):讓 Dio 解析
      // 有兩個坑——①MIS 回應前綴帶空行,json 模式會解析失敗;②限流
      // 時回 HTML,若 Dio 先拋解析錯,就會被下面的 catch 吞成「這批
      // 失敗」而繼續猛打。交給 decodeResponseData 才看得出是限流。
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        '$_tag error: ${response.statusCode}',
        response.statusCode,
      );
    }
    // MIS 回應前面帶一串空行,Dio 的 responseType.json 因此解析失敗
    // 退回 String(2026-08-08 實測)——走專案既有的統一解碼 helper,
    // 它同時處理 String 情況與限流時的 HTML 回應。
    return MarketClientMixin.decodeResponseData(response.data, _tag, '盤中報價');
  }

  static Iterable<List<String>> _batches(List<String> symbols) sync* {
    for (var i = 0; i < symbols.length; i += ApiEndpoints.misBatchSize) {
      yield symbols.skip(i).take(ApiEndpoints.misBatchSize).toList();
    }
  }

  void _warnBatchFailed(int size, Object e) {
    if (_logBatchErrors) {
      AppLogger.warning(_tag, '盤中報價批次失敗($size 檔)', e);
    }
  }

  /// 錯誤 → 「型別+訊息」一行摘要(進 CLI 日誌,型別是診斷的第一線索)
  static String _describeError(Object e) {
    final s = switch (e) {
      // DioException.toString() 冗長且訊息常為 null;type.name(connectionError
      // /connectionTimeout/receiveTimeout…)才是分類 timeout vs DNS vs 重置的
      // 關鍵,再帶上底層 error(通常是 SocketException 原文)
      DioException(:final type, :final message, :final error) =>
        'DioException.${type.name}: ${message ?? error}',
      _ => '${e.runtimeType}: $e',
    };
    return s.length > 200 ? s.substring(0, 200) : s;
  }

  /// 釋放底層 HttpClient 連線池(專案其他 5 支 client 皆有,見
  /// providers.dart 的「避免每次設定變動都洩漏一個底層 socket」)
  void close() => _dio.close(force: true);
}

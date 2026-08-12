import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';

/// 盤中報價 client 的 HTTP 行為(2026-08-08 code review 補測)。
///
/// 補測理由:審查用變異測試證明,把 `tse_`/`otc_` 前綴**對調**時整個
/// 測試套件照樣全綠——而那正是 2026-08-07 踩過的坑(大量 3167 是上市
/// 不是上櫃,猜錯前綴就完全拿不到報價)。這裡直接對請求 URL 斷言。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  /// (請求序號, 完整 URL) → 回應 body;丟例外則模擬該批失敗
  final String Function(int index, String url) handler;
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requests.add(url);
    final body = handler(requests.length - 1, url);
    // 一律宣稱 JSON——這才是能鎖住 `ResponseType.plain` 的設定:
    // 若拿掉 plain,Dio 會依 content-type 嘗試 jsonDecode,HTML 就會在
    // 我們的 HTML 偵測之前先炸成 DioException 並被吞成「這批失敗」
    // (2026-08-08 二次審查 F8:原本 adapter 誠實標 text/html,導致
    // 刪掉 plain 測試照樣全綠)
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _misBody(List<String> symbols) => jsonEncode({
  'rtcode': '0000',
  'msgArray': [
    for (final s in symbols) {'c': s, 'n': '測試$s', 'z': '100.0', 'y': '99.0'},
  ],
});

void main() {
  IntradayQuoteClient clientWith(_FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return IntradayQuoteClient(dio: dio);
  }

  test('🚨 上市用 tse_ 前綴、上櫃用 otc_(對調就拿不到報價)', () async {
    final adapter = _FakeAdapter((_, __) => _misBody(['2330', '6538']));
    await clientWith(adapter).fetchQuotes({'2330': 'TWSE', '6538': 'TPEx'});

    expect(adapter.requests.length, 1);
    final url = Uri.decodeFull(adapter.requests.single);
    expect(url, contains('tse_2330.tw'), reason: '2330 是上市');
    expect(url, contains('otc_6538.tw'), reason: '6538 是上櫃');
    expect(url, isNot(contains('otc_2330')));
    expect(url, isNot(contains('tse_6538')));
  });

  test('🚨 超過 35 檔分批,不漏送不重送', () async {
    final symbols = {for (var i = 0; i < 71; i++) '${1000 + i}': 'TWSE'};
    final adapter = _FakeAdapter((_, __) => _misBody(const []));
    await clientWith(adapter).fetchQuotes(symbols);

    expect(adapter.requests.length, 3, reason: '71 = 35 + 35 + 1');
    final sent = <String>[];
    for (final r in adapter.requests) {
      final exCh = Uri.parse(r).queryParameters['ex_ch']!;
      sent.addAll(exCh.split('|'));
    }
    expect(sent.length, 71, reason: '總數相符=無漏送無重送');
    expect(sent.toSet().length, 71, reason: '無重複');
  });

  test('🚨 單批失敗不影響其他批(盤中缺一檔 > 整批沒有)', () async {
    final adapter = _FakeAdapter((i, _) {
      if (i == 0) throw const SocketException_('batch 0 down');
      return _misBody(['9999']);
    });
    final r = await clientWith(
      adapter,
    ).fetchQuotes({for (var i = 0; i < 40; i++) '${2000 + i}': 'TWSE'});

    expect(adapter.requests.length, 2, reason: '第一批炸了仍要送第二批');
    expect(r.quotes.containsKey('9999'), isTrue, reason: '第二批的結果要留著');
  });

  test('🚨 限流(回 HTML)→ 拋 RateLimitException,不吞成「這批失敗」', () async {
    // 生產路徑的限流長這樣:TWSE/TPEx 被打太兇時回 HTML 頁面而非 JSON,
    // MarketClientMixin.decodeResponseData 偵測到就拋 RateLimitException。
    // (adapter 直接拋例外不是真實路徑——Dio 會包成 DioException。)
    final adapter = _FakeAdapter(
      // 小寫 doctype:2026-08-08 二次審查指出偵測原本大小寫敏感
      (_, __) => '<!doctype html><html><body>Too many requests</body></html>',
    );
    await expectLater(
      clientWith(adapter).fetchQuotes({'2330': 'TWSE'}),
      throwsA(isA<RateLimitException>()),
      reason: '限流是全域狀態,繼續打其他批只會更慘',
    );
  });

  test('空輸入 → 不打 API', () async {
    final adapter = _FakeAdapter((_, __) => _misBody(const []));
    expect((await clientWith(adapter).fetchQuotes(const {})).quotes, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  // 錯誤浮出(2026-08-12):批次錯誤原本只進 AppLogger.warning,而 launchd
  // 跑的是 AOT 編譯 CLI——AppLogger 的 assert 判定在 AOT 下永遠 release、
  // 全靜默。結果三個交易日的早盤失敗(8/11 九輪、8/12 十二輪)日誌只有
  // 「報價全滅」四個字,無從分辨 timeout/DNS/連線重置/限流。
  group('錯誤浮出 errors', () {
    test('🚨 批次失敗時 errors 帶回錯誤型別與訊息', () async {
      final adapter = _FakeAdapter(
        (_, __) => throw const SocketException_('connection refused'),
      );
      final r = await clientWith(adapter).fetchQuotes({'2330': 'TWSE'});

      expect(r.quotes, isEmpty);
      expect(r.errors, hasLength(1));
      expect(r.errors.single, contains('DioException'), reason: '錯誤型別是診斷的第一線索');
      expect(
        r.errors.single,
        contains('connection refused'),
        reason: '原始訊息要保留',
      );
    });

    test('全部成功時 errors 為空', () async {
      final adapter = _FakeAdapter((_, __) => _misBody(['2330']));
      final r = await clientWith(adapter).fetchQuotes({'2330': 'TWSE'});
      expect(r.quotes['2330']?.price, 100.0);
      expect(r.errors, isEmpty);
    });

    test('部分批次失敗:成功批的報價與失敗批的錯誤並存', () async {
      final adapter = _FakeAdapter((i, _) {
        if (i == 0) throw const SocketException_('batch 0 down');
        return _misBody(['9999']);
      });
      final r = await clientWith(
        adapter,
      ).fetchQuotes({for (var i = 0; i < 40; i++) '${2000 + i}': 'TWSE'});

      expect(r.quotes.containsKey('9999'), isTrue);
      expect(r.errors, hasLength(1));
    });
  });

  test('MIS 回應前綴空行仍能解析(2026-08-08 實測的真實行為)', () async {
    final adapter = _FakeAdapter((_, __) => '\n\n\n\n${_misBody(['2330'])}');
    final r = await clientWith(adapter).fetchQuotes({'2330': 'TWSE'});
    expect(r.quotes['2330']?.price, 100.0);
  });
}

/// 本地例外型別:避免 import dart:io 只為了丟一個網路錯誤
class SocketException_ implements Exception {
  const SocketException_(this.message);
  final String message;
  @override
  String toString() => 'SocketException_: $message';
}

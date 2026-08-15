// 重試日誌要說出「為什麼」(2026-08-16)
//
// **實機**:03:30 的強制更新在 TPEx 董監持股卡了 85 秒(對照前一輪同一段
// 只花 0.4 秒),日誌只留下 `重試 1/2 (unknown)`。`DioExceptionType.unknown`
// 涵蓋所有「不是 timeout、不是 4xx/5xx」的底層錯誤——socket 重置、DNS
// 失敗、IO 錯誤全都長這樣,型別對了卻沒說出原因。
//
// 這與 intraday 的「報價全滅四個字分不出 timeout/DNS/連線重置/限流」是
// 同一個 bug class:那邊 2026-08-12 修了(errorKinds 進 stderr),這條
// 共用重試路徑沒修。對症才有藥,型別是第一線索——但 unknown 不是型別,
// 它是「其他」。
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/market_client_mixin.dart';

void main() {
  /// 跑一次 executeRequest 並收集 log(AppLogger 直接 print,無注入點)
  Future<List<String>> capture(Future<void> Function() body) async {
    final lines = <String>[];
    await runZoned(
      () async {
        try {
          await body();
        } catch (_) {
          // 這裡只關心日誌,最終拋出與否由別的測試涵蓋
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    return lines;
  }

  DioException unknownWith(Object? error) => DioException(
    requestOptions: RequestOptions(path: '/x'),
    type: DioExceptionType.unknown,
    error: error,
  );

  test('🚨 unknown 必須附上底層原因,否則診斷不出卡頓來源', () async {
    final logs = await capture(
      () => MarketClientMixin.executeRequest<void>(
        'TPEX',
        '董監持股',
        // 實機的 unknown 之所以可重試,正是因為 e.error 是 SocketException
        // ——資訊在那裡,只是日誌沒印(_isRetryable 的 default 分支為證)
        () async => throw unknownWith(
          const SocketException('Connection reset by peer'),
        ),
      ),
    );

    final retryLines = logs.where((l) => l.contains('重試')).toList();
    expect(retryLines, isNotEmpty, reason: 'unknown 是可重試型別');
    expect(
      retryLines.first,
      contains('Connection reset by peer'),
      reason:
          '只印 "unknown" 等於沒印——實機 85 秒卡頓就是這樣變成無法診斷的。'
          '實際印出: ${retryLines.first}',
    );
  });

  test('已經具體的型別不必附贅述', () async {
    final logs = await capture(
      () => MarketClientMixin.executeRequest<void>(
        'TWSE',
        '估值',
        () async => throw DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
    );
    final retry = logs.firstWhere((l) => l.contains('重試'));
    expect(retry, contains('connectionTimeout'));
  });

  test('🚨 重試耗盡的最終警告同樣要帶原因', () async {
    // 這行是「這輪為什麼失敗」的最後一筆紀錄,只寫「重試 2 次後仍失敗」
    // 等於把診斷線索丟掉
    final logs = await capture(
      () => MarketClientMixin.executeRequest<void>(
        'TPEX',
        '董監持股',
        () async => throw unknownWith(
          const SocketException('Connection reset by peer'),
        ),
      ),
    );
    final finalWarn = logs.where((l) => l.contains('仍失敗')).toList();
    expect(finalWarn, isNotEmpty);
    expect(finalWarn.first, contains('Connection reset by peer'));
  });
}

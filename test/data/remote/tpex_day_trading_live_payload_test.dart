// 端到端:用**未經加工的實際 payload** 跑解析
//
// 早期版本的手寫 fixture 把彙總表誤寫成 2 欄，讓「欄數 >= 6」的判別法看起來
// 可行、7 條測試全綠，但對真實回應永遠選錯表回 0 筆。本檔直接餵存檔的原始
// payload，杜絕「fixture 與現實不符」這類假綠。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/remote/tpex_client.dart';

/// 固定在 fixture 的年代——凍結守衛比對「資料日 vs 現在」，存檔的真實
/// payload 日期固定，牆鐘一走過 stale 窗（7 天）測試就整批變紅。
class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

class MockDio extends Mock implements Dio {}

void main() {
  test('🚨 真實 payload（2026-08-21，842 列）解析出逐檔資料', () async {
    final raw = File(
      'test/data/remote/fixtures/tpex_intraday_stat_20260821.json',
    ).readAsStringSync();
    final body = jsonDecode(raw) as Map<String, dynamic>;

    // 前提檢查：fixture 真的是兩張 6 欄表，否則本測試等於沒測
    final tables = body['tables'] as List;
    expect(tables.length, greaterThanOrEqualTo(2));
    expect((tables[0] as Map)['fields'], hasLength(6));
    expect((tables[1] as Map)['fields'], hasLength(6));

    final dio = MockDio();
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 200,
        data: body,
      ),
    );

    final result = await TpexClient(
      dio: dio,
      clock: _FixedClock(DateTime(2026, 8, 23)),
    ).getAllDayTradingData();

    expect(result.length, greaterThan(700), reason: '842 列扣掉帶字母債券代號');
    expect(result.first.date, DateTime(2026, 8, 21));
    final c = result.firstWhere((e) => e.code == '6104');
    expect(c.totalVolume, 185000);
    expect(c.buyVolume, 17470200);
    expect(c.sellVolume, 17517000);
  });
}

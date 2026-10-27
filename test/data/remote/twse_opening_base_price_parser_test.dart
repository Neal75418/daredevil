// 證交所「股價升降幅度」（TWT84U）→ 每檔當天的開盤競價基準（平盤價）
//
// 上市所有情況的平盤價來源（除權息漲跌修正 spec「平盤價來源」，2026-10-27
// spike：一般日 9/16 全部 1,326 檔「收盤 − 開盤競價基準」與官方漲跌相同）。
// fixture 照 `selectType=ALLBUT0999` 真實回應的形狀，代號虛構、數值取自
// 真實樣本（2330 10/27、3432 9/16、1516 10/27、00625K 10/27）。
//
// ⚠️ 欄位名「開盤競價基準」出現兩次（本日、前日），要用 `groups` 裡標
// 「本日」的那一組取——9901 的本日 2,385、前日 2,420，取錯會紅。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/remote/twse_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  final day = DateTime(2026, 10, 27);
  late Map<String, dynamic> json;

  Map<String, dynamic> load() =>
      jsonDecode(
            File('test/fixtures/remote/twse_twt84u.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  setUp(() => json = load());

  group('parseOpeningBasePrices', () {
    test('取「本日」那組的開盤競價基準；本日基準不可解析的列略過、不拒收整批', () {
      final m = TwseClient.parseOpeningBasePrices(json, day)!;
      expect(m, {'9901': 2385.0, '9902': 14.3, '9903': 24.75, '9904': 7.86});
    });

    test('🚨 用前日那組會紅（9901 前日基準 2,420）', () {
      expect(
        TwseClient.parseOpeningBasePrices(json, day)!['9901'],
        isNot(2420.0),
      );
    });

    test('日期不符 → null', () {
      expect(
        TwseClient.parseOpeningBasePrices(json, DateTime(2026, 10, 26)),
        isNull,
      );
    });

    test('stat 非 OK → null', () {
      json['stat'] = '很抱歉，沒有符合條件的資料!';
      expect(TwseClient.parseOpeningBasePrices(json, day), isNull);
    });

    test('total 與列數不符（可能被截斷）→ null', () {
      json['total'] = 6;
      expect(TwseClient.parseOpeningBasePrices(json, day), isNull);
    });

    test('沒有「本日」group → null', () {
      json['groups'] = [
        {'start': 0, 'span': 2, 'title': ''},
        {'start': 2, 'span': 3, 'title': '今日'},
      ];
      expect(TwseClient.parseOpeningBasePrices(json, day), isNull);
    });

    test('「本日」group 範圍內沒有開盤競價基準欄 → null', () {
      (json['fields'] as List)[3] = '基準';
      expect(TwseClient.parseOpeningBasePrices(json, day), isNull);
    });

    test('stat 大小寫不計', () {
      json['stat'] = 'ok';
      expect(TwseClient.parseOpeningBasePrices(json, day), isNotNull);
    });
  });

  group('getOpeningBasePrices', () {
    late MockDio dio;
    late TwseClient client;

    setUp(() {
      dio = MockDio();
      client = TwseClient(dio: dio);
    });

    Response<dynamic> respond(Object data) => Response(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: ApiEndpoints.twsePriceLimits),
    );

    test('帶 date=YYYYMMDD、selectType=ALLBUT0999、response=json', () async {
      when(
        () => dio.get<dynamic>(
          ApiEndpoints.twsePriceLimits,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => respond(json));
      final m = await client.getOpeningBasePrices(day);
      expect(m['9901'], 2385.0);
      final q =
          verify(
                () => dio.get<dynamic>(
                  ApiEndpoints.twsePriceLimits,
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(q, {
        'date': '20261027',
        'selectType': 'ALLBUT0999',
        'response': 'json',
      });
    });

    test('回應不可信（日期不符）→ 拋 ApiException，不回空 Map', () async {
      json['date'] = '20261026';
      when(
        () => dio.get<dynamic>(
          ApiEndpoints.twsePriceLimits,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => respond(json));
      expect(
        () => client.getOpeningBasePrices(day),
        throwsA(isA<ApiException>()),
      );
    });

    test('HTML 回應（限流）→ RateLimitException', () async {
      when(
        () => dio.get<dynamic>(
          ApiEndpoints.twsePriceLimits,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => respond('<!DOCTYPE html><html></html>'));
      expect(
        () => client.getOpeningBasePrices(day),
        throwsA(isA<RateLimitException>()),
      );
    });
  });
}

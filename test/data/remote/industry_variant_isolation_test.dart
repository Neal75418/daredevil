// 六業別 per-variant 隔離的 characterization test(2026-08-29)
//
// TWSE/TPEx 的季報與資產負債表各自對 6 個業別 suffix 逐一取,骨架抄了
// 四份(~45 行/份)。隔離語意——單一業別失敗記 warning 其餘照收、全滅
// 才拋、RateLimitException 一律 rethrow、非 List 型別跳過該業別——
// **在 client 層零覆蓋**(既有測試只在 syncer 層 mock 整個方法)。
//
// 這組測試是抽共用 helper 之前的安全網:抽完後行為必須逐條不變。
// 也順帶釘住已發現的漂移:TPEx 兩個端點同 host 家族,Accept header
// 必須一致。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;

  setUp(() {
    dio = MockDio();
    registerFallbackValue(RequestOptions(path: '/'));
  });

  final suffixes = ApiEndpoints.quarterlyReportIndustrySuffixes;

  Response<dynamic> ok(List<dynamic> body) => Response<dynamic>(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 200,
    data: body,
  );

  /// 一筆可被 QuarterlyReportEntry 接受的季報列
  Map<String, dynamic> reportRow(String symbol) => {
    '公司代號': symbol,
    '公司名稱': '測試$symbol',
    '年度': '115',
    '季別': '2',
    '基本每股盈餘（元）': '3.5',
    '本期淨利（淨損）': '1000',
  };

  /// 一筆可被 MarketWideFinancial.parseBalance 接受的資產負債表列
  Map<String, dynamic> balanceRow(String symbol) => {
    '公司代號': symbol,
    '年度': '115',
    '季別': '2',
    '權益總計': '299322066',
    '資產總計': '500000000',
  };

  /// 依 path 決定回應:`failing` 內的 suffix 拋 [error],其餘回 [rows]。
  void stubByPath({
    required Set<String> failing,
    required List<dynamic> Function(String suffix) rows,
    Object Function()? error,
  }) {
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((inv) async {
      final path = inv.positionalArguments[0] as String;
      final suffix = suffixes.firstWhere(
        (s) => path.endsWith('_$s'),
        orElse: () => '',
      );
      if (failing.contains(suffix)) {
        throw error?.call() ?? Exception('$suffix down');
      }
      return ok(rows(suffix));
    });
  }

  /// 四個方法共用的行為表——同一組斷言跑四遍,抽 helper 後仍須全過。
  final targets = <String, Future<List<Object>> Function()>{
    'TWSE 季報': () => TwseClient(dio: dio).getQuarterlyReports(),
    'TWSE 資產負債表': () => TwseClient(dio: dio).getAllBalanceSheets(),
    'TPEx 季報': () => TpexClient(dio: dio).getQuarterlyReports(),
    'TPEx 資產負債表': () => TpexClient(dio: dio).getAllBalanceSheets(),
  };

  List<dynamic> Function(String) rowsFor(String label) => label.contains('季報')
      ? (s) => [reportRow('2${suffixes.indexOf(s)}30')]
      : (s) => [balanceRow('2${suffixes.indexOf(s)}30')];

  for (final entry in targets.entries) {
    final label = entry.key;
    final call = entry.value;

    group('$label — per-variant 隔離', () {
      test('全部成功 → 六業別結果合併', () async {
        stubByPath(failing: const {}, rows: rowsFor(label));
        final result = await call();
        expect(result, hasLength(greaterThanOrEqualTo(suffixes.length)));
        verify(
          () => dio.get<dynamic>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).called(suffixes.length);
      });

      test('🚨 單一業別失敗 → 其餘照收,不整份丟掉', () async {
        stubByPath(failing: {suffixes.first}, rows: rowsFor(label));
        final result = await call();
        expect(result, isNotEmpty, reason: '金融業別平日常態零星,單端點異常不該砍掉整份清單');
      });

      test('🚨 全部業別失敗 → 拋出(不得回空當成「今天沒資料」)', () async {
        stubByPath(failing: suffixes.toSet(), rows: rowsFor(label));
        await expectLater(call(), throwsA(anything));
      });

      test('🚨 RateLimitException 一律直接 rethrow,不被降級成 warning', () async {
        stubByPath(
          failing: {suffixes.first},
          rows: rowsFor(label),
          error: () => RateLimitException('quota'),
        );
        await expectLater(call(), throwsA(isA<RateLimitException>()));
      });

      test('非 List 型別 → 跳過該業別,其餘照收', () async {
        when(
          () => dio.get<dynamic>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((inv) async {
          final path = inv.positionalArguments[0] as String;
          if (path.endsWith('_${suffixes.first}')) {
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              statusCode: 200,
              data: {'unexpected': 'shape'},
            );
          }
          return ok(rowsFor(label)(suffixes.last));
        });
        final result = await call();
        expect(result, isNotEmpty);
      });

      test('非 200 → 該業別記為失敗,其餘照收', () async {
        when(
          () => dio.get<dynamic>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((inv) async {
          final path = inv.positionalArguments[0] as String;
          if (path.endsWith('_${suffixes.first}')) {
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              statusCode: 500,
              data: const [],
            );
          }
          return ok(rowsFor(label)(suffixes.last));
        });
        final result = await call();
        expect(result, isNotEmpty);
      });
    });
  }

  test('🚨 TPEx 兩個端點的 Accept header 一致(已現漂移)', () async {
    // TPEx 全部 18 個 openapi 呼叫都帶 Accept: application/json,唯獨
    // getAllBalanceSheets 沒帶(2026-08-29 稽核)。同 host 家族、同
    // openapi,今天能動不代表明天能動——抄寫產生的不對稱。
    final captured = <Options?>[];
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((inv) async {
      captured.add(inv.namedArguments[#options] as Options?);
      return ok([balanceRow('6488')]);
    });
    await TpexClient(dio: dio).getAllBalanceSheets();

    expect(captured, isNotEmpty);
    for (final o in captured) {
      expect(
        o?.headers?['Accept'],
        'application/json',
        reason: '與同 client 的季報端點一致',
      );
    }
  });
}

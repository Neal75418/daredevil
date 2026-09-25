import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/remote/finmind_client.dart';

class MockDio extends Mock implements Dio {}

/// token 放在 query string 時，任何帶 uri 的錯誤字串（dio 的
/// HttpException「..., uri = ...&token=...」）都會把它帶進 Sentry、CLI 日誌與
/// update_run 表。FinMind v4 官方文件的做法是 `Authorization: Bearer`
/// header（https://finmind.github.io/login/），header 不會出現在 uri 裡。
void main() {
  const token = 'eyJhbGciOiJIUzI1NiJ9.payload_long_enough.sig';

  late MockDio dio;
  late List<Map<String, dynamic>?> queries;
  late List<Options?> options;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  setUp(() {
    dio = MockDio();
    queries = [];
    options = [];
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((inv) async {
      queries.add(
        inv.namedArguments[#queryParameters] as Map<String, dynamic>?,
      );
      options.add(inv.namedArguments[#options] as Options?);
      return Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 200,
        data: {'status': 200, 'msg': 'success', 'data': <dynamic>[]},
      );
    });
  });

  Future<void> fetch(FinMindClient client) =>
      client.getDailyPrices(stockId: '2330', startDate: '2026-09-01');

  test('🚨 token 不得出現在 query string', () async {
    await fetch(FinMindClient(dio: dio, token: token));
    expect(queries.single, isNot(contains('token')));
    expect(queries.single!.values, isNot(contains(token)));
  });

  test('token 以 Authorization: Bearer header 傳送', () async {
    await fetch(FinMindClient(dio: dio, token: token));
    expect(options.single?.headers?['Authorization'], 'Bearer $token');
  });

  test('之後才設定的 token 也要帶上（setter 路徑）', () async {
    final client = FinMindClient(dio: dio)..token = token;
    await fetch(client);
    expect(options.single?.headers?['Authorization'], 'Bearer $token');
  });

  test('沒有 token 時不送 Authorization header', () async {
    await fetch(FinMindClient(dio: dio));
    expect(options.single?.headers?['Authorization'], isNull);
  });
}

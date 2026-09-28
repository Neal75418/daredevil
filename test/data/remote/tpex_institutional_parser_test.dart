import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/remote/tpex_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late TpexClient client;

  setUp(() {
    dio = MockDio();
    client = TpexClient(dio: dio);
  });

  Response<dynamic> okResponse(Map<String, dynamic> body) => Response<dynamic>(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: 200,
    data: body,
  );

  /// 代表性 24 欄 TPEx 法人 row。
  /// [4] 外陸資(不含外資自營)淨 → foreignNet（2026-07-23 稽核修復：與
  /// TWSE T86 口徑對齊——原取 [10] 合計含外資自營，上市/上櫃同一 DB 欄
  /// 靜默兩種口徑），[13] 投信淨 → investmentTrustNet,
  /// [16] 自營(自行)淨 → dealerSelfNet, [22] 自營(合計)淨 → dealerNet,
  /// [23] 三大法人 → totalNet。
  /// 自營合計 [22]=20 = 自行 [16]=30 + 避險 [19]=-10；
  /// 外資合計 [10]=300 = 不含自營 [4]=280 + 外資自營 [7]=20。
  List<dynamic> row6488() => <dynamic>[
    '6488', // 0 代號
    '環球晶', // 1 名稱
    '10', '5', '280', // 2-4 外陸資(不含外資自營) 買/賣/淨 → foreignNet=280
    '0', '0', '20', // 5-7 外資自營 買/賣/淨
    '0', '0', '300', // 8-10 外陸資(合計) 買/賣/淨（不取）
    '0', '0', '120', // 11-13 投信 買/賣/淨 → investmentTrustNet=120
    '50', '20', '30', // 14-16 自營(自行) 買/賣/淨 → dealerSelfNet=30
    '5', '15', '-10', // 17-19 自營(避險) 買/賣/淨
    '55', '35', '20', // 20-22 自營(合計) 買/賣/淨 → dealerNet=20
    '440', // 23 三大法人買賣超 → totalNet
  ];

  void stubInstitutional(List<dynamic> dataRow) {
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => okResponse({
        'tables': [
          {
            'date': '115/06/13',
            'data': [dataRow],
          },
        ],
      }),
    );
  }

  group('TpexClient._parseInstitutionalRow (dealerSelfNet added)', () {
    test(
      'dealerSelfNet=[16]; dealerNet[22]/foreignNet[4]/trustNet[13]',
      () async {
        stubInstitutional(row6488());

        final result = await client.getAllInstitutionalData();
        expect(result, hasLength(1));
        final r = result.single;

        expect(r.code, '6488');
        // 新欄位：自行買賣淨來自 [16]
        expect(r.dealerSelfNet, 30, reason: 'dealerSelfNet 必須來自 [16] 自營自行淨');
        // 既有對照：
        expect(r.dealerNet, 20, reason: 'dealerNet 仍取 [22] 自營合計淨');
        expect(r.foreignNet, 280, reason: 'foreignNet 取 [4] 不含外資自營（與 TWSE 對齊）');
        expect(r.investmentTrustNet, 120, reason: 'investmentTrustNet 仍取 [13]');
        expect(r.totalNet, 440, reason: 'totalNet 仍取 [23]');
      },
    );

    test('invariant: dealerNet[22] == dealerSelfNet[16] + hedge[19]', () async {
      stubInstitutional(row6488());

      final r = (await client.getAllInstitutionalData()).single;
      const hedgeNet = -10.0;
      expect(r.dealerNet, r.dealerSelfNet + hedgeNet);
    });
  });
}

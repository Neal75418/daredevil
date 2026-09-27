// 上市估值讀回應日期；新增 BWIBBU_d 歷史估值
//
// parseValuationRows（OpenAPI BWIBBU_ALL）：15:30/21:30 時該端點仍回前一
// 交易日資料，舊實作用呼叫當天的日期標記——2026-07-15 起 52 個交易日裡
// 35 天整批標成隔天。日期改取每列自身的 `Date`（民國 YYYMMDD）。
//
// parseBwibbuDaily（BWIBBU_d 歷史，修復工具用）：依欄位名取值（欄序曾
// 變動），`-` 為 null，頂層 `date` 與請求日期不符即整批丟棄。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/remote/twse_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  Map<String, dynamic> row(String code, String date) => {
    'Date': date,
    'Code': code,
    'Name': code,
    'PEratio': '10.5',
    'DividendYield': '3.17',
    'PBratio': '0.82',
  };

  group('parseValuationRows（OpenAPI BWIBBU_ALL）', () {
    test('日期取回應每列的 Date（民國 YYYMMDD），不用呼叫當天', () {
      final r = TwseClient.parseValuationRows([row('1101', '1150924')])!;
      expect(r.single.date, DateTime(2026, 9, 24));
    });

    test('整批出現多個日期 → null（整批丟棄）', () {
      expect(
        TwseClient.parseValuationRows([
          row('1101', '1150924'),
          row('1102', '1150923'),
        ]),
        isNull,
      );
    });

    test('缺 Date 或無法解析 → null', () {
      expect(TwseClient.parseValuationRows([row('1101', '')]), isNull);
      expect(
        TwseClient.parseValuationRows([
          {'Code': '1101', 'PEratio': '1'},
        ]),
        isNull,
      );
    });
  });

  group('parseBwibbuDaily（BWIBBU_d 歷史）', () {
    Map<String, dynamic> body(String date) => {
      'stat': 'OK',
      'date': date,
      'fields': [
        '證券代號',
        '證券名稱',
        '收盤價',
        '殖利率(%)',
        '股利年度',
        '本益比',
        '股價淨值比',
        '財報年/季',
      ],
      'data': [
        ['1101', '台泥', '23.10', '3.17', '114', '-', '0.82', '115/2'],
      ],
    };

    test('依欄位名取值，`-` 為 null，日期用請求日', () {
      final r = TwseClient.parseBwibbuDaily(
        body('20260924'),
        DateTime(2026, 9, 24),
      );
      expect(r.single.code, '1101');
      expect(r.single.per, isNull);
      expect(r.single.pbr, 0.82);
      expect(r.single.dividendYield, 3.17);
      expect(r.single.date, DateTime(2026, 9, 24));
    });

    test('回應日期 ≠ 請求日期 → 空', () {
      expect(
        TwseClient.parseBwibbuDaily(body('20260923'), DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('欄數不足的列略過，不丟 RangeError', () {
      final b = body('20260924');
      (b['data'] as List).add(['1102', '亞泥', '30.00']);
      expect(
        TwseClient.parseBwibbuDaily(
          b,
          DateTime(2026, 9, 24),
        ).map((r) => r.code),
        ['1101'],
      );
    });

    test('回應包在 tables 內也能解析', () {
      final wrapped = {
        'stat': 'OK',
        'date': '20260924',
        'tables': [
          {
            'fields': body('20260924')['fields'],
            'data': body('20260924')['data'],
          },
        ],
      };
      expect(
        TwseClient.parseBwibbuDaily(wrapped, DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test(
      'getStockValuationForDate 打 BWIBBU_d，帶 date 與 selectType=ALL',
      () async {
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
            data: body('20260924'),
          ),
        );
        final rows = await TwseClient(
          dio: dio,
        ).getStockValuationForDate(DateTime(2026, 9, 24));
        expect(rows, hasLength(1));
        final captured = verify(
          () => dio.get<dynamic>(
            captureAny(),
            queryParameters: captureAny(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).captured;
        expect(captured[0], '/rwd/zh/afterTrading/BWIBBU_d');
        expect(captured[1], {
          'date': '20260924',
          'selectType': 'ALL',
          'response': 'json',
        });
      },
    );
  });
}

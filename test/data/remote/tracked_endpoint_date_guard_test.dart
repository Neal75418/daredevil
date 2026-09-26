// 追蹤資料集的端點：回應日期缺失或與請求不符 → 整批丟棄（fail-closed）
//
// 每個負向案例都有同 body 的正向對照；沒有對照，「回空」可能只是 body
// 本身解析不出來，測試形同虛設。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

class MockDio extends Mock implements Dio {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  late MockDio dio;

  void stub(Map<String, dynamic> body) {
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
  }

  Map<String, dynamic> withoutKey(Map<String, dynamic> m, String key) =>
      Map.of(m)..remove(key);

  group('TWSE', () {
    late TwseClient client;
    setUp(() {
      dio = MockDio();
      client = TwseClient(dio: dio);
    });

    // STOCK_DAY_ALL JSON 形狀：[代號, 名稱, 成交股數, 成交金額, 開, 高, 低, 收, 漲跌, 筆數]
    final dailyBody = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'data': [
        [
          '2330',
          '台積電',
          '1,000',
          '100,500',
          '100',
          '101',
          '99',
          '100.5',
          '0.5',
          '500',
        ],
      ],
    };

    test('每日價格：有日期 → 正常', () async {
      stub(dailyBody);
      expect(await client.getAllDailyPrices(), hasLength(1));
    });

    test('每日價格：回應沒有日期 → 整批丟棄（不退回今天）', () async {
      stub(withoutKey(dailyBody, 'date'));
      expect(await client.getAllDailyPrices(), isEmpty);
    });

    // T86 19 欄
    final t86Body = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'data': [
        [
          '2330',
          '台積電',
          '1,000',
          '500',
          '500',
          '0',
          '0',
          '0',
          '200',
          '100',
          '100',
          '20',
          '50',
          '20',
          '30',
          '5',
          '15',
          '-10',
          '620',
        ],
      ],
    };

    test('法人：回應日期 = 請求日期 → 正常', () async {
      stub(t86Body);
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test('法人：回應日期 ≠ 請求日期 → 整批丟棄', () async {
      stub(t86Body);
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 23)),
        isEmpty,
      );
    });

    test('法人：回應沒有日期 → 整批丟棄', () async {
      stub(withoutKey(t86Body, 'date'));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    // MI_MARGN：tables[1] 為個股明細（16 欄）
    final marginBody = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'tables': [
        {'title': '信用交易統計', 'data': <dynamic>[]},
        {
          'title': '融資融券彙總',
          'data': [
            [
              '2330',
              '台積電',
              '100',
              '50',
              '0',
              '900',
              '950',
              '99999',
              '10',
              '20',
              '0',
              '30',
              '40',
              '99999',
              '0',
              '',
            ],
          ],
        },
      ],
    };

    test('融資券（不帶日期）：有日期 → 正常', () async {
      stub(marginBody);
      expect(await client.getAllMarginTradingData(), hasLength(1));
    });

    test('融資券（不帶日期）：回應沒有日期 → 整批丟棄', () async {
      stub(withoutKey(marginBody, 'date'));
      expect(await client.getAllMarginTradingData(), isEmpty);
    });

    // MI_QFIIS 12 欄
    final qfiisBody = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'data': [
        [
          '2330',
          '台積電',
          'TW0002330008',
          '25,932,733,242',
          '5,000,000,000',
          '18,662,165,009',
          '19.28',
          '71.96',
          '100.00',
          '100.00',
          '',
          '',
        ],
      ],
    };

    test('外資持股：有日期 → 正常', () async {
      stub(qfiisBody);
      expect(
        await client.getAllForeignShareholding(date: DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test('外資持股：回應沒有日期 → 整批丟棄', () async {
      stub(withoutKey(qfiisBody, 'date'));
      expect(
        await client.getAllForeignShareholding(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('clearCache 後同一請求重新打 API', () async {
      stub(dailyBody);
      await client.getAllDailyPrices();
      await client.getAllDailyPrices();
      client.clearCache();
      await client.getAllDailyPrices();
      verify(
        () => dio.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).called(2);
    });
  });

  group('TPEx', () {
    late TpexClient client;
    setUp(() {
      dio = MockDio();
      client = TpexClient(
        dio: dio,
        clock: _FixedClock(DateTime(2026, 9, 24, 21)),
      );
    });

    Map<String, dynamic> tpexBody(List<dynamic> row, {String? date}) => {
      'stat': 'ok',
      'tables': [
        {
          'date': ?date,
          'data': [row],
        },
      ],
    };

    final dailyRow = [
      '3624',
      '光頡',
      '144.00',
      '+4.00',
      '144.00',
      '147.00',
      '143.00',
      '145.07',
      '1,581,074',
      '229,365,406',
      '1,902',
      '144.00',
      '13',
      '144.50',
      '3',
      '117,340,842',
      '144.00',
      '158.00',
      '130.00',
    ];

    test('每日價格：表格有日期 → 正常', () async {
      stub(tpexBody(dailyRow, date: '115/09/24'));
      expect(await client.getAllDailyPrices(), hasLength(1));
    });

    test('每日價格：表格沒有日期 → 整批丟棄（不退回請求日期）', () async {
      stub(tpexBody(dailyRow));
      expect(await client.getAllDailyPrices(), isEmpty);
    });

    final instRow = [
      '3624',
      '光頡',
      '7,797,033',
      '10,424,745',
      '-2,627,712',
      '0',
      '0',
      '0',
      '7,797,033',
      '10,424,745',
      '-2,627,712',
      '0',
      '0',
      '0',
      '5,000',
      '39,437',
      '-34,437',
      '104,231',
      '139,081',
      '-34,850',
      '109,231',
      '178,518',
      '-69,287',
      '-2,696,999',
    ];

    test('法人：回應日期 = 請求日期 → 正常', () async {
      stub(tpexBody(instRow, date: '115/09/24'));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test('法人：回應日期 ≠ 請求日期 → 整批丟棄', () async {
      stub(tpexBody(instRow, date: '115/09/23'));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('法人：回應沒有日期 → 整批丟棄', () async {
      stub(tpexBody(instRow));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('法人（不帶日期請求）：表格有日期 → 正常；沒有日期 → 整批丟棄', () async {
      stub(tpexBody(instRow, date: '115/09/24'));
      expect(await client.getAllInstitutionalData(), hasLength(1));
      client.clearCache();
      stub(tpexBody(instRow));
      expect(await client.getAllInstitutionalData(), isEmpty);
    });

    final marginRow = [
      '3624',
      '光頡',
      '11,070',
      '1,297',
      '1,201',
      '0',
      '11,166',
      '167',
      '38.06',
      '29,335',
      '832',
      '210',
      '230',
      '0',
      '812',
      '6',
      '2.76',
      '29,335',
      '52',
      '11   A',
    ];

    test('融資券（不帶日期）：有日期 → 正常', () async {
      stub(tpexBody(marginRow, date: '115/09/23'));
      expect(await client.getAllMarginTradingData(), hasLength(1));
    });

    test('融資券（不帶日期）：沒有日期 → 整批丟棄（不退回今天）', () async {
      stub(tpexBody(marginRow));
      expect(await client.getAllMarginTradingData(), isEmpty);
    });

    test('歷史價格打 afterTrading/dailyQuotes，日期格式 YYYY/MM/DD', () async {
      stub({
        'date': '20260709',
        'stat': 'ok',
        'tables': [
          {
            'date': '115/07/09',
            'data': [dailyRow],
          },
        ],
      });
      final rows = await client.getAllDailyPricesHistorical(
        DateTime(2026, 7, 9),
      );
      expect(rows, hasLength(1));
      final captured = verify(
        () => dio.get<dynamic>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).captured;
      expect(captured[0], '/www/zh-tw/afterTrading/dailyQuotes');
      expect((captured[1] as Map)['date'], '2026/07/09');
    });
  });
}

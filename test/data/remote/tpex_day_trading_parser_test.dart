// 上櫃當沖解析 — fixture 取自 2026-08-21 實際回應的形狀
//
// 五個實測陷阱（842 列全量統計）：
//   千分位逗號 716 列、全形空白 797 列、非 4 碼代號 116 列（ETF/債券）、
//   `stat` 是小寫 'ok'（上市是大寫 'OK'，照抄會整批誤判失敗）、
//   逐檔資料在 **第二張** table（第一張是全市場彙總，既有 helper 取 first）。
//
// 日期語意與上市相反：此端點無視 `date` 參數永遠回最新交易日，故寫入日期
// 必須取回應的 `date`，不可用請求日期。
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

  /// 真實回應形狀：兩張表，第二張才是逐檔
  Map<String, dynamic> body({
    String date = '20260821',
    String stat = 'ok',
    List<List<dynamic>>? rows,
  }) => {
    'date': date,
    'stat': stat,
    'tables': [
      {
        'title': '現股當沖交易統計資訊',
        'fields': ['當日沖銷交易總成交股數', '當日沖銷交易總成交股數占市場比重'],
        'data': [
          ['445,333,000', '25.90%'],
        ],
      },
      {
        'title': '',
        'fields': [
          '證券代號',
          '證券名稱',
          '暫停現股賣出後現款買進當沖註記',
          '當日沖銷交易成交股數',
          '當日沖銷交易買進成交金額',
          '當日沖銷交易賣出成交金額',
        ],
        'data':
            rows ??
            [
              // 千分位逗號 + 全形註記空白（實測形狀）
              ['6104', '創惟', ' ', '185,000', '17,470,200', '17,517,000'],
              [
                '1815',
                '富喬',
                '＊',
                '75,783,000',
                '8,300,813,500',
                '8,311,193,000',
              ],
              // ETF（合法，比照上市保留）與債券（帶字母，須過濾）
              ['006201', '元大富櫃50', ' ', '5,000', '212,120', '212,780'],
              [
                '00679B',
                '元大美債20年',
                '＊',
                '1,381,000',
                '35,690,270',
                '35,684,590',
              ],
            ],
      },
    ],
  };

  void stub(Map<String, dynamic> b) {
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
        data: b,
      ),
    );
  }

  test('解析逐檔（第二張表）並處理千分位與全形空白', () async {
    stub(body());

    final result = await client.getAllDayTradingData();

    expect(
      result.length,
      3,
      reason:
          'ETF（006201）是合法標的、與上市路徑一致（DB 裡 0050/00919 都有當沖）；'
          '只有帶字母的債券代號 00679B 被 StockPatterns.isValidCode 擋下',
    );
    expect(result.map((e) => e.code), containsAll(['6104', '1815', '006201']));
    expect(result.map((e) => e.code), isNot(contains('00679B')));
    final c = result.firstWhere((e) => e.code == '6104');
    expect(c.totalVolume, 185000);
    expect(c.buyVolume, 17470200);
    expect(c.sellVolume, 17517000);
    expect(c.name, '創惟');
  });

  test('🚨 日期取自回應，不得用請求日期', () async {
    stub(body(date: '20260819'));

    final result = await client.getAllDayTradingData();

    expect(
      result.first.date,
      DateTime(2026, 8, 19),
      reason: '端點無視 date 參數永遠回最新交易日；用請求日期會把最新資料寫成歷史日',
    );
  });

  test('🚨 stat 是小寫 ok（照抄上市的大寫比對會整批誤判失敗）', () async {
    stub(body(stat: 'ok'));
    expect(await client.getAllDayTradingData(), isNotEmpty);
  });

  test('stat 非 ok → 回空', () async {
    stub(body(stat: 'error'));
    expect(await client.getAllDayTradingData(), isEmpty);
  });

  test('缺 date 欄位 → 回空（無從驗證資料屬於哪天）', () async {
    final b = body();
    b.remove('date');
    stub(b);
    expect(await client.getAllDayTradingData(), isEmpty);
  });

  test('只有彙總表、沒有逐檔表 → 回空', () async {
    final b = body();
    (b['tables'] as List).removeAt(1);
    stub(b);
    expect(await client.getAllDayTradingData(), isEmpty);
  });

  test('數值欄位無法解析 → 該列跳過，不落 0', () async {
    stub(
      body(
        rows: [
          ['6104', '創惟', ' ', '--', '--', '--'],
          ['1815', '富喬', ' ', '1,000', '2,000', '3,000'],
        ],
      ),
    );

    final result = await client.getAllDayTradingData();
    expect(result.length, 1, reason: '哨兵值不得被當成 0 寫入');
    expect(result.single.code, '1815');
  });
}

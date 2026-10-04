import 'dart:convert';
import 'dart:io';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// 真實 API response fixture 解析測試
///
/// Fixture 錄自 2026-07-08 的實際 API 回應（`test/fixtures/remote/`），
/// 非從 parser 反推——上游格式變更（如 TWSE 2026-06 STOCK_DAY_ALL
/// JSON→CSV）是本 App 最常見的故障模式，這組測試固定「當前真實格式
/// 可被正確解析」作為 regression baseline。
class MockDio extends Mock implements Dio {}

String _fixture(String name) =>
    File('test/fixtures/remote/$name').readAsStringSync();

Response<dynamic> _response(dynamic data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: ''),
);

void main() {
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
  });

  void stubGet(dynamic data) {
    when(
      () => mockDio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _response(data));
    // OpenData 類 endpoint 不帶 queryParameters
    when(
      () => mockDio.get<dynamic>(any()),
    ).thenAnswer((_) async => _response(data));
    // TPEx OpenAPI 帶 Options(headers) 呼叫
    when(
      () => mockDio.get<dynamic>(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _response(data));
  }

  group('TwseClient 真實 fixture 解析', () {
    test('零價 sentinel:無成交股(OHLC 0.00)的價格解析為 null(2026-07-30)', () async {
      // 1472 於 2026-07-30 全日僅零股成交 17 股,STOCK_DAY_ALL 對無成交
      // 用 '0.00' 表達(MI_INDEX 用 '--')。存 0 會污染 52 週窗與漲跌
      // 計算(顯示 -100%),價格欄一律 0→null;volume 照實(17 合法)。
      const csv =
          '日期,證券代號,證券名稱,成交股數,成交金額,開盤價,最高價,最低價,收盤價,漲跌價差,成交筆數\n'
          '"1150730","1472","三洋實業","17","1511","0.00","0.00","0.00","0.00","0.0000","7"\n'
          '"1150730","2330","台積電","51372177","114098819878","2205.00","2260.00","2190.00","2205.00","5.0000","177492"\n';
      stubGet(csv);
      final client = TwseClient(dio: mockDio);

      final prices = await client.getAllDailyPrices();
      final p1472 = prices.firstWhere((p) => p.code == '1472');
      expect(p1472.close, isNull);
      expect(p1472.open, isNull);
      expect(p1472.volume, 17.0, reason: '量欄照實,0→null 僅限價格欄');
      final p2330 = prices.firstWhere((p) => p.code == '2330');
      expect(p2330.close, 2205.0);
    });

    test('STOCK_DAY 個股月線零價 sentinel(2026-08-01 審查補漏——'
        '上市個股歷史回補的實際路徑,初版 sweep 漏了這個端點)', () async {
      final json = {
        'stat': 'OK',
        'date': '20260701',
        'data': [
          // 列格式: [日期, 成交股數, 成交金額, 開, 高, 低, 收, 漲跌價差, 筆數]
          [
            '115/07/01',
            '17',
            '1,511',
            '0.00',
            '0.00',
            '0.00',
            '0.00',
            '0.00',
            '7',
          ],
          [
            '115/07/02',
            '95,900',
            '8,448,107',
            '90.00',
            '90.00',
            '86.60',
            '89.00',
            '-0.40',
            '358',
          ],
        ],
      };
      stubGet(json);
      final client = TwseClient(dio: mockDio);

      final prices = await client.getStockMonthlyPrices(
        code: '1472',
        year: 2026,
        month: 7,
      );
      expect(prices, hasLength(2));
      expect(prices[0].close, isNull, reason: '無成交日 0.00 → null');
      expect(prices[0].open, isNull);
      expect(prices[0].volume, 17.0, reason: '量欄照實');
      expect(prices[1].close, 89.0);
    });

    test('MI_INDEX 零價 sentinel 同語意(歷史回補路徑)', () {
      final json = {
        'date': '20260730',
        'tables': [
          {
            'fields': [
              '證券代號',
              '證券名稱',
              '成交股數',
              '成交筆數',
              '成交金額',
              '開盤價',
              '最高價',
              '最低價',
              '收盤價',
              '漲跌(+/-)',
              '漲跌價差',
            ],
            'data': [
              [
                '1472',
                '三洋實業',
                '17',
                '7',
                '1,511',
                '0.00',
                '0.00',
                '0.00',
                '0.00',
                '<p> </p>',
                '0.00',
              ],
              [
                '2330',
                '台積電',
                '51,372,177',
                '177,492',
                '114,098,819,878',
                '2,205.00',
                '2,260.00',
                '2,190.00',
                '2,205.00',
                '<p style= color:red>+</p>',
                '5.00',
              ],
            ],
          },
        ],
      };
      final prices = TwseClient.parseMiIndexDailyPrices(
        json,
        DateTime(2026, 7, 30),
      );
      expect(prices.firstWhere((p) => p.code == '1472').close, isNull);
      expect(prices.firstWhere((p) => p.code == '2330').close, 2205.0);
    });

    test('STOCK_DAY_ALL CSV 格式（2026-06 起）解析為每日價格', () async {
      stubGet(_fixture('twse_stock_day_all.csv'));
      final client = TwseClient(dio: mockDio);

      final prices = await client.getAllDailyPrices();

      // fixture 含 24 筆資料列（25 行 - 表頭）
      expect(prices, hasLength(24));
      final first = prices.first;
      expect(first.code, '00400A');
      expect(first.name, '主動國泰動能高息');
      expect(first.close, 14.29);
      expect(first.open, 14.41);
      expect(first.volume, 68952570);
      expect(first.change, -0.06);
      // 民國 1150708 → 2026-07-08
      expect(first.date, DateTime(2026, 7, 8));
    });

    test('T86 三大法人 JSON 解析', () async {
      stubGet(jsonDecode(_fixture('twse_t86_institutional.json')));
      final client = TwseClient(dio: mockDio);

      final rows = await client.getAllInstitutionalData(
        date: DateTime(2026, 7, 8),
      );

      expect(rows, hasLength(15));
      final first = rows.first;
      expect(first.code, '2618');
      // T86 的名稱欄位帶 TWSE 原始尾隨空白，parser 保留原樣
      expect(first.name.trim(), '長榮航');
      // 外陸資買進 75,301,046 / 賣出 13,442,621 / 買賣超 61,858,425
      expect(first.foreignBuy, 75301046);
      expect(first.foreignSell, 13442621);
      expect(first.foreignNet, 61858425);
    });
  });

  group('TpexClient 真實 fixture 解析', () {
    test('上櫃全市場日價 tables JSON 解析', () async {
      stubGet(jsonDecode(_fixture('tpex_daily_close_quotes.json')));
      final client = TpexClient(dio: mockDio);

      final prices = await client.getAllDailyPrices(date: DateTime(2026, 7, 8));

      // fixture 含 1 筆純數字上櫃 ETF（006201）+ 4 筆字母尾碼債券 ETF
      // + 10 筆一般個股。2026-07-23 稽核修復：每日 parser 放行純數字上櫃
      // ETF（stock_master 實測 14 檔全為 00 開頭 5-6 碼純數字、與歷史回補
      // 宇宙一致）；債券 ETF 不在 stock_master、續濾。
      expect(prices, hasLength(11));
      expect(prices.any((p) => p.code == '006201'), isTrue);
      expect(prices.any((p) => p.code == '00679B'), isFalse);
      final maosheng = prices.firstWhere((p) => p.code == '1240');
      expect(maosheng.name, '茂生農經');
      expect(maosheng.close, 57.80);
      expect(maosheng.change, -0.10);
      expect(maosheng.open, 58.40);
    });
  });

  group('輔助資料 endpoint 真實 fixture 解析（每日更新 pipeline 依賴）', () {
    test('TWSE 已宣告股利 OpenData 解析', () async {
      stubGet(jsonDecode(_fixture('twse_declared_dividend.json')));
      final client = TwseClient(dio: mockDio);

      final dividends = await client.getDeclaredDividends();

      expect(dividends, isNotEmpty);
      final first = dividends.first;
      expect(first.symbol, '1101');
      expect(first.companyName, '台泥');
      // 股利年度 114（民國）
      expect(first.dividendYear, greaterThanOrEqualTo(2025));
    });

    test('TPEx 內部人轉讓解析', () async {
      stubGet(jsonDecode(_fixture('tpex_insider_transfer.json')));
      final client = TpexClient(dio: mockDio);

      final transfers = await client.getInsiderTransfers();

      expect(transfers, isNotEmpty);
      final first = transfers.first;
      expect(first.symbol, '3567');
      expect(first.companyName, '逸昌');
      expect(first.identity, '法人董事代表人配偶');
      // 目前持有股數-自有持股 385000
      expect(first.currentHolding, 385000);
    });

    test('TPEx 股東會公告解析', () async {
      stubGet(jsonDecode(_fixture('tpex_shareholder_meeting.json')));
      final client = TpexClient(dio: mockDio);

      final meetings = await client.getShareholderMeetings();

      expect(meetings, isNotEmpty);
      final first = meetings.first;
      expect(first.symbol, '1240');
      expect(first.meetingType, '常會');
      expect(first.hasBoardElection, isFalse);
    });

    test('TDCC 股權分散表解析（含 BOM key 防禦）', () async {
      // fixture 保留 TDCC 真實回應的 ﻿ BOM key（「﻿資料日期」）
      stubGet(jsonDecode(_fixture('tdcc_holding_distribution.json')));
      final client = TdccClient(dio: mockDio);

      final holdings = await client.getAllHoldingDistribution();

      expect(holdings, isNotEmpty);
      expect(holdings, contains('000218'));
      final levels = holdings['000218']!;
      expect(levels, isNotEmpty);
      // BOM key 的資料日期 20260703 必須被正確解析（否則整筆被丟棄）
      expect(levels.first.date, DateTime(2026, 7, 3));
      expect(levels.first.level, isNonNegative);
    });

    test('TWSE 處置股公告解析', () async {
      stubGet(jsonDecode(_fixture('twse_punish.json')));
      final client = TwseClient(dio: mockDio);

      final disposals = await client.getDisposalInfo();

      // fixture 前 8 筆含權證與正股，至少正股應被解析
      expect(disposals, isNotEmpty);
      for (final d in disposals) {
        expect(d.code, isNotEmpty);
        expect(d.warningType, 'DISPOSAL');
      }
    });

    test('TWSE 大盤指數（MI_INDEX，漲跌欄含 HTML 標記）解析', () async {
      stubGet(jsonDecode(_fixture('twse_mi_index.json')));
      final client = TwseClient(dio: mockDio);

      final indices = await client.getMarketIndices(date: DateTime(2026, 7, 8));

      expect(indices, isNotEmpty);
      // 寶島股價指數 50,938.02、漲跌欄是 "<p style='color:red'>+</p>"
      final formosa = indices.firstWhere((i) => i.name.contains('寶島'));
      expect(formosa.close, 50938.02);
      // HTML 標記的方向欄必須被正確解讀為上漲 +280.61
      expect(formosa.change, 280.61);
    });
  });

  group('董監持股彙總（TWSE/TPEx 真實 fixture）', () {
    // 兩個 endpoint（發行股數 + 董監持股）需要 per-URL stub
    void stubInsiderPair({
      required String stockInfoUrl,
      required String stockInfoFixture,
      required String insiderUrl,
      required String insiderFixture,
    }) {
      when(
        () =>
            mockDio.get<dynamic>(stockInfoUrl, options: any(named: 'options')),
      ).thenAnswer(
        (_) async => _response(jsonDecode(_fixture(stockInfoFixture))),
      );
      when(
        () => mockDio.get<dynamic>(insiderUrl, options: any(named: 'options')),
      ).thenAnswer(
        (_) async => _response(jsonDecode(_fixture(insiderFixture))),
      );
    }

    test('TWSE：只彙總「董事/監察人本人」、姓名去重、比例正確', () async {
      stubInsiderPair(
        stockInfoUrl: ApiEndpoints.twseStockInfo,
        stockInfoFixture: 'twse_stock_info.json',
        insiderUrl: ApiEndpoints.twseInsiderHolding,
        insiderFixture: 'twse_insider_holding.json',
      );
      final client = TwseClient(dio: mockDio);

      final holdings = await client.getInsiderHoldings();

      // fixture：台泥 1101 共 54 筆內部人記錄，其中「董事/監察人本人」
      // 去重後 14 人（副總/協理/會計主管等非董監記錄必須被排除）
      expect(holdings, hasLength(1));
      final h = holdings.first;
      expect(h.code, '1101');
      expect(h.insiderRatio, closeTo(8.3527, 0.001));
      expect(h.pledgeRatio, closeTo(0.6525, 0.001));
      expect(h.sharesIssued, 7523181742);
    });

    test('TPEx：同一套業務規則產出一致口徑', () async {
      stubInsiderPair(
        stockInfoUrl: ApiEndpoints.tpexStockInfo,
        stockInfoFixture: 'tpex_stock_info.json',
        insiderUrl: ApiEndpoints.tpexInsiderHolding,
        insiderFixture: 'tpex_insider_holding.json',
      );
      final client = TpexClient(dio: mockDio);

      final holdings = await client.getInsiderHoldings();

      // fixture：康和證 6016 共 76 筆，「本人」去重後 9 人、無質押
      expect(holdings, hasLength(1));
      final h = holdings.first;
      expect(h.code, '6016');
      expect(h.insiderRatio, closeTo(7.3377, 0.001));
      expect(h.pledgeRatio, 0.0);
      expect(h.sharesIssued, 686595508);
    });
  });

  group('FinMindClient 真實 fixture 解析', () {
    test('TaiwanStockPrice JSON 解析', () async {
      stubGet(jsonDecode(_fixture('finmind_taiwan_stock_price.json')));
      final client = FinMindClient(dio: mockDio);

      final prices = await client.getDailyPrices(
        stockId: '2330',
        startDate: '2026-07-06',
        endDate: '2026-07-08',
      );

      expect(prices, hasLength(3));
      final first = prices.first;
      expect(first.stockId, '2330');
      expect(first.date, '2026-07-06');
      expect(first.close, 2460.0);
      expect(first.open, 2465.0);
      expect(first.volume, 21041918);
    });
  });
}

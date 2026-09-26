// 歷史全市場行情 parser 測試（資料缺口修復）
//
// 背景：TWSE STOCK_DAY_ALL 與 TPEx daily_close_quotes 自 2026-06 起忽略
// 歷史 date 參數（memory: afterclose_twse_stock_day_all_no_date）。
// 替代端點：
//   TWSE  MI_INDEX?date=yyyyMMdd&type=ALLBUT0999 → tables[] 內含
//         「每日收盤行情」表（fields 以 證券代號 開頭）
//   TPEx  /www/zh-tw/afterTrading/dailyQuotes?date=yyyy/MM/dd（官方口徑，
//         與每日端點 daily_close_quotes 相同；2026-09-26 起取代舊的
//         afterTrading/otc）
// fixture 取自真實回應削減版。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

void main() {
  group('TwseClient.parseMiIndexDailyPrices', () {
    final fixture = {
      'stat': 'OK',
      'date': '20240315',
      'tables': [
        {
          'title': '113年03月15日 價格指數(臺灣證券交易所)',
          'fields': ['指數', '收盤指數'],
          'data': [
            ['寶島股價指數', '22,467.27'],
          ],
        },
        {
          'title': '113年03月15日 每日收盤行情(全部(不含權證、牛熊證))',
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
            '最後揭示買價',
            '最後揭示買量',
            '最後揭示賣價',
            '最後揭示賣量',
            '本益比',
          ],
          'data': [
            [
              '2330',
              '台積電',
              '30,000,000',
              '50,000',
              '30,000,000,000',
              '1,000.00',
              '1,010.00',
              '990.00',
              '995.00',
              '<p style= color:green>-</p>',
              '5.00',
              '994.00',
              '1',
              '995.00',
              '2',
              '25.00',
            ],
            [
              '0056',
              '元大高股息',
              '28,781,228',
              '17,472',
              '1,118,671,837',
              '38.71',
              '39.03',
              '38.64',
              '39.02',
              '<p style= color:red>+</p>',
              '0.30',
              '39.01',
              '1',
              '39.02',
              '231',
              '0.00',
            ],
            // 停牌股：價格欄 '--'
            [
              '9999',
              '停牌股',
              '0',
              '0',
              '0',
              '--',
              '--',
              '--',
              '--',
              '<p> </p>',
              '0.00',
              '--',
              '0',
              '--',
              '0',
              '0.00',
            ],
          ],
        },
      ],
    };

    test('取「每日收盤行情」表、欄位對映與漲跌號正確', () {
      final prices = TwseClient.parseMiIndexDailyPrices(
        fixture,
        DateTime(2024, 3, 15),
      );
      expect(prices.length, 3);

      final tsmc = prices.firstWhere((p) => p.code == '2330');
      expect(tsmc.date, DateTime(2024, 3, 15));
      expect(tsmc.open, 1000.0);
      expect(tsmc.high, 1010.0);
      expect(tsmc.low, 990.0);
      expect(tsmc.close, 995.0);
      expect(tsmc.volume, 30000000);
      expect(tsmc.change, -5.0, reason: '漲跌號 (-) × 漲跌價差 5.00');

      final etf = prices.firstWhere((p) => p.code == '0056');
      expect(etf.change, 0.30, reason: '漲跌號 (+) × 0.30');
    });

    test('停牌股（-- 價格）→ 欄位為 null、不 crash', () {
      final prices = TwseClient.parseMiIndexDailyPrices(
        fixture,
        DateTime(2024, 3, 15),
      );
      final halted = prices.firstWhere((p) => p.code == '9999');
      expect(halted.close, isNull);
      expect(halted.open, isNull);
    });

    test('回應日期 ≠ 請求日期 → 回空（端點失效防護，同 backfill 原則）', () {
      final prices = TwseClient.parseMiIndexDailyPrices(
        fixture,
        DateTime(2024, 3, 18), // 請求 18 號、fixture 是 15 號
      );
      expect(prices, isEmpty);
    });

    test('無收盤行情表（假日 stat 異常）→ 空', () {
      final holiday = {'stat': 'OK', 'date': '20240316', 'tables': <Object>[]};
      expect(
        TwseClient.parseMiIndexDailyPrices(holiday, DateTime(2024, 3, 16)),
        isEmpty,
      );
    });
  });

  group('TpexClient.parseDailyQuotesPrices（afterTrading/dailyQuotes，官方口徑）', () {
    Map<String, dynamic> fixture() =>
        jsonDecode(
              File(
                'test/data/remote/fixtures/tpex_daily_quotes_20260709.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    test('成交股數取 index 8（含定價與零股，＝官方個股日成交資訊）', () {
      final rows = TpexClient.parseDailyQuotesPrices(
        fixture(),
        DateTime(2026, 7, 9),
      );
      final c = rows.firstWhere((r) => r.code == '3624');
      expect(
        c.volume,
        1581074,
        reason: '官方 1,581 張；afterTrading/otc 是 1,436,000',
      );
      expect(c.close, 144.0);
      expect(c.date, DateTime(2026, 7, 9));
    });

    test('權證被 isTpexPriceCode 濾掉，ETF 保留', () {
      final codes = TpexClient.parseDailyQuotesPrices(
        fixture(),
        DateTime(2026, 7, 9),
      ).map((r) => r.code);
      expect(codes, containsAll(['3624', '006201']));
      expect(codes, isNot(contains('700019')));
    });

    test('回應日期 ≠ 請求日期 → 整批丟棄', () {
      expect(
        TpexClient.parseDailyQuotesPrices(fixture(), DateTime(2026, 7, 8)),
        isEmpty,
      );
    });
  });
}

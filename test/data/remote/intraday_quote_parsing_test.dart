import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/twse/intraday_quote.dart';

/// 盤中即時報價解析(TWSE MIS,2026-08-08)。
///
/// fixture 為 2026-08-08 live 快照(收盤後取,含 2330/3231/6538 三檔)。
/// 這支 API 的價格欄位在**盤中無成交時會是 '-'**,且欄位名極短,踩過的
/// 坑要靠 fixture 鎖住。
void main() {
  final raw =
      jsonDecode(
            File('test/fixtures/twse_mis_intraday.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('🚨 fixture 全量解析,價格與昨收正確', () {
    final quotes = IntradayQuote.parseResponse(raw);
    expect(quotes.length, 3);

    final tsmc = quotes['2330']!;
    expect(tsmc.name, '台積電');
    expect(tsmc.price, 2370.0);
    expect(tsmc.previousClose, 2365.0);
    expect(tsmc.high, 2395.0);
    expect(tsmc.low, 2355.0);
  });

  test('rtcode 非 0000 → 視為失敗回空(不把錯誤當報價用)', () {
    expect(IntradayQuote.parseResponse({'rtcode': '5001'}), isEmpty);
    expect(IntradayQuote.parseResponse(const {}), isEmpty);
  });

  test('🚨 成交價為 "-" → 用買賣五檔中價,**不可**退回開盤價', () {
    // 2026-08-10 實機(盤中 12:26,單次乾淨請求):金像電 z='-'、pz='-',
    // 而 o=985(開盤)、買 916 / 賣 918。舊版退回開盤價 → app 認為現價
    // 985,實際市場在 917,**差 7.4%**。同一時刻連台積電、鴻海的 z 都是
    // '-',所以這不是罕見狀況,是 MIS 的常態。
    //
    // 後果:提醒的比價基準整天停在開盤價 → 該觸發的不觸發、不該觸發的
    // 觸發。當時使用者有 7 筆盤中提醒正在監控。
    final q = IntradayQuote.parseResponse({
      'rtcode': '0000',
      'msgArray': [
        {
          'c': '2368',
          'n': '金像電',
          'z': '-',
          'pz': '-',
          'o': '985.0',
          'y': '982.0',
          'b': '916.0000_915.0000_',
          'a': '918.0000_919.0000_',
        },
      ],
    });
    expect(q['2368']!.price, 917.0, reason: '買 916 / 賣 918 → 中價 917,而非開盤 985');
  });

  test('只有單邊報價時用該邊,仍不可退回開盤', () {
    final q = IntradayQuote.parseResponse({
      'rtcode': '0000',
      'msgArray': [
        {'c': '1', 'z': '-', 'o': '50.0', 'y': '48.0', 'b': '47.0000_'},
        {'c': '2', 'z': '-', 'o': '50.0', 'y': '48.0', 'a': '49.0000_'},
      ],
    });
    expect(q['1']!.price, 47.0, reason: '只有買價 → 用買價');
    expect(q['2']!.price, 49.0, reason: '只有賣價 → 用賣價');
  });

  test('連買賣五檔都沒有 → 視為無報價,不猜價格', () {
    // 開盤前、暫停交易等情境。與其報一個錯的價,不如不報——
    // 提醒下一輪(5 分鐘後)會再查一次,漏一輪遠比觸發錯誤安全。
    final q = IntradayQuote.parseResponse({
      'rtcode': '0000',
      'msgArray': [
        {'c': '3', 'z': '-', 'pz': '-', 'o': '50.0', 'y': '48.0'},
      ],
    });
    expect(q.containsKey('3'), isFalse, reason: '寧可沒有報價,也不要錯的報價');
  });

  test('🚨 舊行為(退回開盤/昨收)必須已移除', () {
    // 這條原本是**鎖住 bug 的測試**:它斷言「pz 也無 → 取開盤」「全無 →
    // 退回昨收」,把錯誤行為當成規格釘住。開盤價與昨收都不是「現在的
    // 市場」,拿它們比對提醒門檻,等於整天用一個過時的價格做決策。
    final q = IntradayQuote.parseResponse({
      'rtcode': '0000',
      'msgArray': [
        // pz 有值 → 仍應採用(那是試撮價,反映當下)
        {'c': '9999', 'z': '-', 'pz': '105.0', 'y': '100.0'},
        // 只有開盤價、無五檔 → 不可採用,整列丟棄
        {'c': '8888', 'z': '-', 'o': '99.0', 'y': '100.0'},
        // 只有昨收 → 同樣丟棄
        {'c': '7777', 'z': '-', 'y': '100.0'},
      ],
    });
    expect(q['9999']!.price, 105.0, reason: 'pz 是試撮價,可用');
    expect(q.containsKey('8888'), isFalse, reason: '開盤價不是現價');
    expect(q.containsKey('7777'), isFalse, reason: '昨收更不是現價');
  });

  test('代號或昨收缺失的列直接丟棄(不產生無效報價)', () {
    final dirty = {
      'rtcode': '0000',
      'msgArray': [
        {'c': '', 'z': '100.0', 'y': '99.0'},
        {'c': '1234', 'z': '-', 'y': '-'},
        {'c': '5678', 'z': '50.0', 'y': '49.0'},
      ],
    };
    final q = IntradayQuote.parseResponse(dirty);
    expect(q.keys.toList(), ['5678']);
  });

  test('漲跌幅由現價與昨收算出', () {
    final q = IntradayQuote.parseResponse(raw)['2330']!;
    expect(q.changePercent, closeTo((2370 / 2365 - 1) * 100, 1e-9));
  });

  /// 漲跌停鎖住(2026-10-05 實測)。
  ///
  /// fixture 的每一列是 2026-10-05 12:13 MIS 回應的原始資料(當天加權指數
  /// 盤中大漲逾千點);當時分三次批次請求共 58 列,這裡只收 12 列——兩個
  /// 指數、當天的漲跌停焦點股、幾檔權值股,涵蓋鎖住無成交、鎖住有成交、
  /// 一般成交、五檔中價、指數各種情況。外層 rtcode 等欄位是合併後重組的。
  /// 完整 58 列的新舊比對已於 2026-10-06 做過一次(其餘 55 列逐列相同)。
  ///
  /// 鎖漲停且當輪沒有成交時 z、pz 都是 '-',買方五檔第一格是 0(市價委託)、
  /// 第二格才是漲停價,賣方 '-'——修正前取第一格 0 判為無報價、整檔丟掉。
  ///
  /// `_legacy_prices.json` 是**修正前**的解析器(commit e82c082f)跑同一份
  /// fixture 的輸出,格式 `{代號: 價格或 null}`,2026-10-06 產出後凍結。
  /// **不可用現行程式重新產生**——那會變成自己比自己,證明不了「修正只改
  /// 鎖住的列」。
  group('漲跌停鎖住', () {
    Map<String, dynamic> load(String name) =>
        jsonDecode(File('test/fixtures/$name').readAsStringSync())
            as Map<String, dynamic>;
    final locked = load('twse_mis_intraday_limit_locked_20261005.json');
    final legacy = load(
      'twse_mis_intraday_limit_locked_20261005_legacy_prices.json',
    );

    test('🚨 鎖漲停、當輪沒有成交 → 取漲停價(修正前整檔被丟掉)', () {
      final q = IntradayQuote.parseResponse(locked);
      expect(legacy.keys.toSet(), q.keys.toSet());
      expect(
        {
          for (final e in legacy.entries)
            if (e.value == null) e.key,
        },
        {'2059', '2383', '6213'},
      );
      for (final (symbol, limit) in const [
        ('2059', 13355.0), // 川湖
        ('2383', 5700.0), // 台光電
        ('6213', 751.0), // 聯茂
      ]) {
        expect(q[symbol]?.price, limit, reason: symbol);
      }
    });

    test('🚨 其餘 9 列的價格與修正前逐列相同', () {
      final q = IntradayQuote.parseResponse(locked);
      final others = legacy.entries.where((e) => e.value != null).toList();
      expect(others, hasLength(9));
      for (final e in others) {
        expect(q[e.key]?.price, e.value, reason: e.key);
      }
      expect(q, hasLength(12));
    });

    test('鎖住標記:價格等於漲停價且沒有賣單(不論當輪有無成交)', () {
      final q = IntradayQuote.parseResponse(locked);
      final up = {
        for (final e in q.entries)
          if (e.value.isLimitUpLocked) e.key,
      };
      final down = {
        for (final e in q.entries)
          if (e.value.isLimitDownLocked) e.key,
      };
      // 南亞、萬潤、台燿當輪有成交(z = 漲停價),同樣是鎖住
      expect(up, {'1303', '2059', '2383', '6187', '6213', '6274'});
      // 倉和:成交價 = 跌停價、沒有買單
      expect(down, {'6538'});
      expect(q['2383']!.limitUp, 5700.0);
      expect(q['6538']!.limitDown, 335.5);
    });

    test('指數列沒有漲跌停價,不判鎖住', () {
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          {'c': 't00', 'z': '49647.94', 'y': '48475.74'},
        ],
      });
      expect(q['t00']!.limitUp, isNull);
      expect(q['t00']!.isLimitUpLocked, isFalse);
      expect(q['t00']!.isLimitDownLocked, isFalse);
    });

    test('鎖跌停、當輪沒有成交 → 取跌停價(合成資料:鏡像漲停實測)', () {
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          {
            'c': '6538',
            'z': '-',
            'pz': '-',
            'y': '372.5',
            'u': '409.5',
            'w': '335.5',
            'b': '-',
            'a': '0.0000_335.5000_336.0000_',
          },
        ],
      });
      expect(q['6538']?.price, 335.5);
      expect(q['6538']!.isLimitDownLocked, isTrue);
    });

    test('🚨 首格 0 但第一個正數不是漲停價 → 維持無報價,不誤當成價格', () {
      // 合成:無賣單、有市價買單、外加一筆遠低的限價買單。若把「第一個正數」
      // 一律當價格,會得到 46,掛在 47 的「跌破」提醒就被誤觸發——但市場
      // 其實是有人市價搶買
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          {
            'c': '9998',
            'z': '-',
            'pz': '-',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '0.0000_46.0000_',
            'a': '-',
          },
        ],
      });
      expect(q.containsKey('9998'), isFalse);
    });

    test('首格 0 但第一個正數不是跌停價 → 維持無報價(賣方鏡像)', () {
      // 合成:無買單、有市價賣單、外加一筆遠高的限價賣單
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          {
            'c': '9997',
            'z': '-',
            'pz': '-',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '-',
            'a': '0.0000_54.0000_',
          },
        ],
      });
      expect(q.containsKey('9997'), isFalse);
    });

    test('不算鎖住:漲跌停價上還有對手單,或價格不在漲跌停價', () {
      // 合成。每列都有成交價 z,只驗鎖住標記
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          // 成交在漲停價、但還有賣單(打開漲停)
          {
            'c': 'u1',
            'z': '55.0',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '54.9000_',
            'a': '55.0000_',
          },
          // 沒有賣單、但成交價低於漲停價
          {
            'c': 'u2',
            'z': '54.0',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '53.9000_',
            'a': '-',
          },
          // 成交在漲停價、賣方首格是市價委託 0、第二格才是正數:仍有賣單
          {
            'c': 'u3',
            'z': '55.0',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '-',
            'a': '0.0000_55.0000_',
          },
          // 成交在跌停價、但還有買單(打開跌停)
          {
            'c': 'd1',
            'z': '45.0',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '45.0000_',
            'a': '45.1000_',
          },
          // 沒有買單、但成交價高於跌停價
          {
            'c': 'd2',
            'z': '46.0',
            'y': '50.0',
            'u': '55.0',
            'w': '45.0',
            'b': '-',
            'a': '46.1000_',
          },
        ],
      });
      for (final s in const ['u1', 'u2', 'u3', 'd1', 'd2']) {
        expect(q[s]!.isLimitUpLocked, isFalse, reason: s);
        expect(q[s]!.isLimitDownLocked, isFalse, reason: s);
      }
    });
  });
}

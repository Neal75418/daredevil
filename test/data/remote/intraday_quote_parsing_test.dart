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
}

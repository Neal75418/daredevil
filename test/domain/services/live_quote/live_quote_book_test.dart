import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_book.dart';

/// 報價中心的記帳本(2026-10-06,spec §3 顯示價與閃色、§2 收盤後逐檔、
/// §8 一輪的結果)。報價一律經真的 IntradayQuote.parseResponse。
void main() {
  DateTime at(int h, int m, [int s = 0]) => DateTime(2026, 10, 6, h, m, s);

  Map<String, Object?> row(
    String c, {
    String z = '-',
    String pz = '-',
    String y = '100.0000',
    String d = '20261006',
    String t = '10:00:00',
    String b = '-',
    String a = '-',
    String? u,
    String? w,
    Map<String, String>? trade,
    Map<String, Object?> extra = const {},
  }) => {
    'c': c,
    'z': z,
    'pz': pz,
    'y': y,
    'd': d,
    't': t,
    'b': b,
    'a': a,
    'u': ?u,
    'w': ?w,
    'trade': ?trade,
    ...extra,
  };

  /// 每列所在的批次都有回應
  QuoteBatchReport responded(List<Map<String, Object?>> rows) =>
      QuoteBatchReport(
        quotes: IntradayQuote.parseResponse({
          'rtcode': '0000',
          'msgArray': rows,
        }),
        errors: const [],
        respondedSymbols: {for (final r in rows) r['c'] as String},
        failedSymbols: const <String>{},
      );

  QuoteBatchReport failed(Set<String> symbols) => QuoteBatchReport(
    quotes: const {},
    errors: const ['DioException.connectionTimeout: 模擬'],
    respondedSymbols: const <String>{},
    failedSymbols: symbols,
  );

  late LiveQuoteBook book;
  setUp(() => book = LiveQuoteBook());

  /// 盤中套一輪,回傳 A 的顯示結果
  LiveQuoteEntry? round(
    QuoteBatchReport r, {
    List<String> requested = const ['A'],
    DateTime? now,
  }) {
    book.apply(
      r,
      requested: requested,
      now: now ?? at(10, 0, 5),
      afterClose: false,
    );
    return book.entries['A'];
  }

  group('顯示價順序', () {
    test('🚨 鎖住 → 漲停價,即使 trade 記著鎖住前較低的成交', () {
      round(responded([row('A', z: '109.5000', u: '110.0000')]));
      final e = round(
        responded([
          row(
            'A',
            b: '0.0000_110.0000_',
            u: '110.0000',
            trade: const {'t': '10:00:01', 'z': '109.5000'},
          ),
        ]),
      )!;
      expect(e.price, 110.0);
      expect(e.displaySource, LiveDisplaySource.locked);
      expect(e.isLimitUpLocked, isTrue);
    });

    test('跌停鎖住鏡像 → 跌停價', () {
      final e = round(
        responded([row('A', a: '0.0000_90.0000_', w: '90.0000')]),
      )!;
      expect(e.price, 90.0);
      expect(e.displaySource, LiveDisplaySource.locked);
      expect(e.isLimitDownLocked, isTrue);
    });

    test('本輪有成交 → 成交價', () {
      final e = round(
        responded([row('A', z: '101.0000', b: '100.5000_', a: '101.5000_')]),
      )!;
      expect(e.price, 101.0);
      expect(e.displaySource, LiveDisplaySource.trade);
    });

    test('🚨 本輪 z 為 - 但有 trade.z → 最後成交價與它的時間,不用五檔中價', () {
      final e = round(
        responded([
          row(
            'A',
            b: '100.5000_',
            a: '101.5000_',
            t: '10:00:09',
            trade: const {'t': '10:00:05', 'z': '100.0000'},
          ),
        ]),
      )!;
      expect(e.price, 100.0);
      expect(e.displaySource, LiveDisplaySource.lastTrade);
      expect(e.quoteTime, '10:00:05');
    });

    test('🚨 沒有 trade 時沿用今天記住的成交價(不是五檔中價)', () {
      round(responded([row('A', z: '100.0000', t: '10:00:00')]));
      final e = round(
        responded([row('A', b: '102.0000_', a: '103.0000_', t: '10:00:20')]),
      )!;
      expect(e.price, 100.0);
      expect(e.displaySource, LiveDisplaySource.lastTrade);
      expect(e.quoteTime, '10:00:00');
    });

    test('🚨 五檔價不當成交記住:連兩輪都沒成交 → 第二輪仍顯示當輪五檔', () {
      round(responded([row('A', b: '99.0000_', a: '100.0000_')]));
      final e = round(responded([row('A', b: '102.0000_', a: '103.0000_')]))!;
      expect(e.price, 102.5);
      expect(e.displaySource, LiveDisplaySource.trialOrBook);
    });

    test('今天還沒有任何成交 → 試撮或五檔', () {
      final e = round(responded([row('A', pz: '99.5000')]))!;
      expect(e.price, 99.5);
      expect(e.displaySource, LiveDisplaySource.trialOrBook);
    });

    test('開高低、成交量(張)、昨收照搬 MIS', () {
      final e = round(
        responded([
          row(
            'A',
            z: '101.0000',
            y: '99.0000',
            extra: const {
              'o': '100.0000',
              'h': '102.0000',
              'l': '98.5000',
              'v': '12345',
            },
          ),
        ]),
      )!;
      expect(
        (e.open, e.high, e.low, e.volumeLots, e.previousClose),
        (100.0, 102.0, 98.5, 12345, 99.0),
      );
    });
  });

  group('閃色', () {
    test('🚨 連續兩輪都是成交且價格改變 → 閃,方向比上一輪', () {
      round(responded([row('A', z: '100.0000')]));
      final up = round(responded([row('A', z: '101.0000')]))!.flash;
      final down = round(responded([row('A', z: '100.5000')]))!.flash;
      expect(up?.up, isTrue);
      expect(down?.up, isFalse);
      expect(down!.id, isNot(up!.id));
    });

    test('價格沒變不閃', () {
      round(responded([row('A', z: '100.0000')]));
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNotNull);
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });

    test('閃色只活一輪:沒被請求的那檔下一輪也清掉', () {
      round(
        responded([row('A', z: '100.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      round(
        responded([row('A', z: '101.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      expect(book.entries['A']!.flash, isNotNull);
      round(responded([row('B', z: '50.0000')]), requested: const ['B']);
      expect(book.entries['A']!.flash, isNull);
    });

    test('🚨 五檔價換成成交價那一下不閃', () {
      round(responded([row('A', b: '99.0000_', a: '100.0000_')]));
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });

    test('最後成交與鎖住也算成交類', () {
      round(responded([row('A', z: '100.0000')]));
      final lastTrade = round(
        responded([
          row(
            'A',
            b: '100.0000_',
            a: '101.0000_',
            trade: const {'t': '10:00:03', 'z': '100.5000'},
          ),
        ]),
      )!;
      expect(lastTrade.flash?.up, isTrue);
      final locked = round(
        responded([row('A', b: '0.0000_110.0000_', u: '110.0000')]),
      )!;
      expect(locked.flash?.up, isTrue);
    });

    test('🚨 中間隔一輪沒抓到(批次失敗)→ 不閃', () {
      round(responded([row('A', z: '100.0000')]));
      round(failed({'A'}));
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });

    test('🚨 畫面剛恢復登記的第一輪不閃', () {
      round(
        responded([row('A', z: '100.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      round(responded([row('B', z: '50.0000')]), requested: const ['B']);
      round(
        responded([row('A', z: '101.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      expect(book.entries['A']!.flash, isNull);
    });

    test('App 重新可見(forgetLastRound)後第一輪不閃', () {
      round(responded([row('A', z: '100.0000')]));
      book.forgetLastRound();
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });
  });

  group('一輪的結果與卡片狀態', () {
    test('🚨 至少一筆今天的報價 → success;失敗批標 batchFailed、有回應沒報價標 noQuote', () {
      final outcome = book.apply(
        QuoteBatchReport(
          quotes: IntradayQuote.parseResponse({
            'rtcode': '0000',
            'msgArray': [row('A', z: '100.0000')],
          }),
          errors: const ['DioException.connectionTimeout: 模擬'],
          respondedSymbols: const {'A', 'B'},
          failedSymbols: const {'C'},
        ),
        requested: const ['A', 'B', 'C'],
        now: at(10, 0, 5),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.success);
      expect(book.symbolStatus, {
        'A': LiveSymbolStatus.ok,
        'B': LiveSymbolStatus.noQuote,
        'C': LiveSymbolStatus.batchFailed,
      });
      expect(book.latestResponseHadToday, isTrue);
    });

    test('🚨 有回應但日期全不是今天 → respondedNoToday,不顯示、卡片標無報價', () {
      final outcome = book.apply(
        responded([row('A', z: '100.0000', d: '20261005')]),
        requested: const ['A'],
        now: at(9, 0, 3),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.respondedNoToday);
      expect(book.entries, isEmpty);
      expect(book.symbolStatus['A'], LiveSymbolStatus.noQuote);
      expect(book.latestResponseHadToday, isFalse);
    });

    test('🚨 列全被解析丟掉(暫停交易)仍是 respondedNoToday', () {
      final outcome = book.apply(
        responded([row('A')]),
        requested: const ['A'],
        now: at(10, 0, 5),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.respondedNoToday);
      expect(book.symbolStatus['A'], LiveSymbolStatus.noQuote);
    });

    test('全部批次失敗 → failed;已有的價格留著(卡片標報價暫停)', () {
      round(responded([row('A', z: '100.0000')]));
      final outcome = book.apply(
        failed({'A'}),
        requested: const ['A'],
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.failed);
      expect(book.entries['A']!.price, 100.0);
      expect(book.symbolStatus['A'], LiveSymbolStatus.batchFailed);
      expect(book.latestResponseHadToday, isTrue, reason: '失敗不改「最近一次有回應」的判斷');
    });

    test('latestQuoteTime 取本輪各筆 t 的最大值,格式不符的不算', () {
      round(
        responded([
          row('A', z: '1.0000', t: '10:00:05'),
          row('B', z: '1.0000', t: '10:00:12'),
          row('C', z: '1.0000', t: '9:9'),
        ]),
        requested: const ['A', 'B', 'C'],
      );
      expect(book.latestQuoteTime, '10:00:12');
    });

    test('請求清單以外的報價不收', () {
      round(responded([row('A', z: '1.0000'), row('X', z: '2.0000')]));
      expect(book.entries.keys, ['A']);
    });
  });

  group('收盤後逐檔', () {
    QuoteBatchReport notClosing() =>
        responded([row('A', b: '99.5000_', a: '100.5000_', t: '13:29:40')]);

    test('🚨 拿到收盤報價就不再抓', () {
      book.apply(
        responded([row('A', z: '100.0000', t: '13:30:00')]),
        requested: const ['A'],
        now: at(13, 31),
        afterClose: true,
      );
      expect(book.entries['A']!.isClosingQuote, isTrue);
      expect(book.pendingAfterClose(const ['A']), isEmpty);
      expect(book.dueAfterClose(const ['A'], at(13, 40)), isEmpty);
    });

    test('🚨 有回應但不是收盤報價:每分鐘一次,第 10 次後停', () {
      var now = at(13, 31);
      for (var i = 0; i < 10; i++) {
        expect(book.dueAfterClose(const ['A'], now), [
          'A',
        ], reason: '第 ${i + 1} 次');
        book.apply(
          notClosing(),
          requested: const ['A'],
          now: now,
          afterClose: true,
        );
        expect(
          book.dueAfterClose(const ['A'], now.add(const Duration(seconds: 59))),
          isEmpty,
          reason: '未滿 1 分鐘',
        );
        now = now.add(const Duration(minutes: 1));
      }
      expect(book.dueAfterClose(const ['A'], now), isEmpty);
      expect(book.pendingAfterClose(const ['A']), isEmpty);
    });

    test('暫停交易(列被丟掉)也計入嘗試', () {
      for (var i = 0; i < 10; i++) {
        book.apply(
          responded([row('A')]),
          requested: const ['A'],
          now: at(13, 31 + i),
          afterClose: true,
        );
      }
      expect(book.pendingAfterClose(const ['A']), isEmpty);
    });

    test('🚨 網路失敗不計入 10 次', () {
      for (var i = 0; i < 12; i++) {
        book.apply(
          failed({'A'}),
          requested: const ['A'],
          now: at(13, 31 + i),
          afterClose: true,
        );
      }
      expect(book.pendingAfterClose(const ['A']), ['A']);
      expect(book.dueAfterClose(const ['A'], at(13, 43)), ['A']);
    });

    test('盤中的回合不計收盤後嘗試', () {
      for (var i = 0; i < 12; i++) {
        round(notClosing());
      }
      expect(book.pendingAfterClose(const ['A']), ['A']);
    });
  });

  group('換日', () {
    test('🚨 App 開著過夜:隔天 rollDay 清空所有記憶', () {
      book.apply(
        responded([row('A', z: '100.0000', t: '13:30:00')]),
        requested: const ['A'],
        now: at(13, 31),
        afterClose: true,
      );
      expect(book.rollDay(DateTime(2026, 10, 7, 8, 30)), isTrue);
      expect(book.entries, isEmpty);
      expect(book.symbolStatus, isEmpty);
      expect(book.latestResponseHadToday, isNull);
      expect(book.latestQuoteTime, isNull);
      expect(book.pendingAfterClose(const ['A']), ['A']);
    });

    test('🚨 前一天用滿 10 次嘗試的那檔,隔天收盤後照樣會抓', () {
      for (var i = 0; i < 10; i++) {
        book.apply(
          responded([row('A', b: '99.5000_', a: '100.5000_', t: '13:29:40')]),
          requested: const ['A'],
          now: at(13, 31 + i),
          afterClose: true,
        );
      }
      expect(book.pendingAfterClose(const ['A']), isEmpty, reason: '前一天已停');
      book.rollDay(DateTime(2026, 10, 7, 8, 30));
      expect(book.pendingAfterClose(const ['A']), ['A']);
      expect(book.dueAfterClose(const ['A'], DateTime(2026, 10, 7, 13, 31)), [
        'A',
      ]);
    });

    test('同一天 rollDay 不清', () {
      round(responded([row('A', z: '100.0000')]));
      expect(book.rollDay(at(12, 0)), isFalse);
      expect(book.entries, hasLength(1));
    });

    test('🚨 記住的成交價也清掉:隔天沒成交時顯示五檔,不沿用昨天的成交', () {
      round(responded([row('A', z: '100.0000')]));
      book.apply(
        responded([row('A', b: '102.0000_', a: '103.0000_', d: '20261007')]),
        requested: const ['A'],
        now: DateTime(2026, 10, 7, 9, 1, 5),
        afterClose: false,
      );
      expect(book.entries['A']!.displaySource, LiveDisplaySource.trialOrBook);
      expect(book.entries['A']!.price, 102.5);
    });
  });
}

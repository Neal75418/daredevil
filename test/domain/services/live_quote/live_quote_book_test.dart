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

  String two(int v) => v.toString().padLeft(2, '0');

  /// 每列所在的批次都有回應;[snapshot] 是這份回應的快照時刻(不給就沒有
  /// `queryTime`)
  QuoteBatchReport responded(
    List<Map<String, Object?>> rows, {
    DateTime? snapshot,
  }) => QuoteBatchReport(
    quotes: IntradayQuote.parseResponse({
      'rtcode': '0000',
      'msgArray': rows,
      if (snapshot != null)
        'queryTime': {
          'sysDate':
              '${snapshot.year}${two(snapshot.month)}${two(snapshot.day)}',
          'sysTime':
              '${two(snapshot.hour)}:${two(snapshot.minute)}:'
              '${two(snapshot.second)}',
        },
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

  group('收盤後已放棄的代號與時刻(closingGivenUpAt)', () {
    QuoteBatchReport notClosing() =>
        responded([row('A', b: '99.5000_', a: '100.5000_', t: '13:29:40')]);

    void attempt(QuoteBatchReport r, int minute) => book.apply(
      r,
      requested: const ['A'],
      now: at(13, 31 + minute),
      afterClose: true,
    );

    test('🚨 有回應但不是收盤報價:第 9 次不在、第 10 次在', () {
      for (var i = 0; i < 9; i++) {
        attempt(notClosing(), i);
      }
      expect(book.closingGivenUpAt, isEmpty, reason: '第 9 次');
      expect(book.pendingAfterClose(const ['A']), ['A'], reason: '前提:還要抓');

      attempt(notClosing(), 9);
      expect(book.closingGivenUpAt, {'A': at(13, 40)}, reason: '第 10 次的時刻');
      expect(book.pendingAfterClose(const ['A']), isEmpty, reason: '前提:不再抓');
    });

    test('🚨 網路失敗(批次失敗)不計', () {
      for (var i = 0; i < 12; i++) {
        attempt(failed({'A'}), i);
      }
      expect(book.closingGivenUpAt, isEmpty);
    });

    test('拿到收盤報價的不在', () {
      attempt(responded([row('A', z: '100.0000', t: '13:30:00')]), 0);
      expect(book.closingGivenUpAt, isEmpty);
    });

    test('🚨 試滿 10 次之後才拿到收盤報價:不在', () {
      for (var i = 0; i < 10; i++) {
        attempt(notClosing(), i);
      }
      expect(book.closingGivenUpAt, {'A': at(13, 40)}, reason: '前提');
      attempt(responded([row('A', z: '100.0000', t: '13:30:00')]), 10);
      expect(book.entries['A']!.isClosingQuote, isTrue, reason: '前提');
      expect(book.closingGivenUpAt, isEmpty);
    });

    test('盤中的回合不計', () {
      for (var i = 0; i < 12; i++) {
        round(notClosing());
      }
      expect(book.closingGivenUpAt, isEmpty);
    });

    test('🚨 換日清空', () {
      for (var i = 0; i < 10; i++) {
        attempt(notClosing(), i);
      }
      expect(book.closingGivenUpAt, {'A': at(13, 40)}, reason: '前提');
      expect(book.rollDay(DateTime(2026, 10, 7, 8, 30)), isTrue);
      expect(book.closingGivenUpAt, isEmpty);
    });

    test('唯讀', () {
      for (var i = 0; i < 10; i++) {
        attempt(notClosing(), i);
      }
      expect(
        () => book.closingGivenUpAt['B'] = at(13, 50),
        throwsUnsupportedError,
      );
    });

    test('🚨 列被解析丟掉(暫停交易、整天沒成交)也算:沒有 entry 照樣在', () {
      for (var i = 0; i < 10; i++) {
        attempt(responded([row('A')]), i);
      }
      expect(book.entries, isNot(contains('A')), reason: '前提:沒有 entry');
      expect(book.closingGivenUpAt, {'A': at(13, 40)});
    });
  });

  group('拿到今天報價的時刻', () {
    /// 9901 有今天的報價、9902 有回應但報價是昨天的、9903 的批次失敗
    QuoteBatchReport mixed() => QuoteBatchReport(
      quotes: IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          row('9901', z: '100.0000'),
          row('9902', z: '100.0000', d: '20261005'),
        ],
      }),
      errors: const ['DioException.connectionTimeout: 模擬'],
      respondedSymbols: const {'9901', '9902'},
      failedSymbols: const {'9903'},
    );

    const all = ['9901', '9902', '9903'];

    test('🚨 只記這一輪拿到今天報價的代號,時刻是套用時的 now', () {
      book.apply(mixed(), requested: all, now: at(10, 0, 5), afterClose: false);
      expect(book.fetchedAt, {'9901': at(10, 0, 5)});
    });

    test('🚨 下一輪沒拿到的保留舊時刻;重新拿到的換成新時刻', () {
      book.apply(mixed(), requested: all, now: at(10, 0, 5), afterClose: false);
      // 9901 這輪批次失敗、9903 有回應但沒有列、9902 拿到
      book.apply(
        QuoteBatchReport(
          quotes: IntradayQuote.parseResponse({
            'rtcode': '0000',
            'msgArray': [row('9902', z: '100.0000')],
          }),
          errors: const ['DioException.connectionTimeout: 模擬'],
          respondedSymbols: const {'9902', '9903'},
          failedSymbols: const {'9901'},
        ),
        requested: all,
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(book.fetchedAt, {'9901': at(10, 0, 5), '9902': at(10, 0, 20)});

      book.apply(
        responded([row('9901', z: '101.0000')]),
        requested: all,
        now: at(10, 0, 35),
        afterClose: false,
      );
      expect(book.fetchedAt, {'9901': at(10, 0, 35), '9902': at(10, 0, 20)});
    });

    test('請求清單以外的代號不記', () {
      book.apply(
        responded([row('9901', z: '1.0000'), row('9999', z: '2.0000')]),
        requested: const ['9901'],
        now: at(10, 0, 5),
        afterClose: false,
      );
      expect(book.fetchedAt.keys, ['9901']);
    });

    test('收盤後逐檔抓到的也記', () {
      book.apply(
        responded([row('9901', z: '100.0000', t: '13:30:00')]),
        requested: const ['9901'],
        now: at(13, 31),
        afterClose: true,
      );
      expect(book.fetchedAt, {'9901': at(13, 31)});
    });

    test('🚨 換日清空:rollDay', () {
      book.apply(mixed(), requested: all, now: at(10, 0, 5), afterClose: false);
      expect(book.rollDay(DateTime(2026, 10, 7, 8, 30)), isTrue);
      expect(book.fetchedAt, isEmpty);
    });

    test('🚨 換日清空:隔天第一輪的 apply(那一輪沒拿到報價也不帶昨天的)', () {
      book.apply(mixed(), requested: all, now: at(10, 0, 5), afterClose: false);
      book.apply(
        failed({'9901'}),
        requested: const ['9901'],
        now: DateTime(2026, 10, 7, 9, 1),
        afterClose: false,
      );
      expect(book.fetchedAt, isEmpty, reason: '昨天的時刻不帶到今天');
    });

    test('唯讀,且取到的是快照:之後再套用一輪不改動已取出的那份', () {
      book.apply(mixed(), requested: all, now: at(10, 0, 5), afterClose: false);
      final snapshot = book.fetchedAt;
      expect(() => snapshot['9999'] = at(10, 0, 6), throwsUnsupportedError);

      book.apply(
        responded([row('9901', z: '101.0000')]),
        requested: all,
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(snapshot, {'9901': at(10, 0, 5)});
      expect(book.fetchedAt, {'9901': at(10, 0, 20)});
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

  /// 證交所的快取會回比上一輪舊的快照。比畫面那筆舊、那一列自己也沒有更新
  /// 的不換上去;但它仍是今天的報價,「這一輪有拿到」的記帳照做。
  group('快照時刻:不倒退', () {
    /// 盤中套一輪(只問 A)。[receivedAt] 不給時取 [now] 前 2 秒
    RoundOutcome applyA(
      QuoteBatchReport r,
      DateTime now, {
      DateTime? receivedAt,
      bool afterClose = false,
    }) => book.apply(
      r,
      requested: const ['A'],
      now: now,
      afterClose: afterClose,
      receivedAt: {'A': receivedAt ?? now.subtract(const Duration(seconds: 2))},
    );

    test('🚨 較舊的快照、那一列的 t 也沒有比較新 → 不換價格、不閃色,其餘照記', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 0)),
        at(10, 0, 5),
      );
      final outcome = applyA(
        responded([
          row('A', z: '99.0000', t: '09:59:30'),
        ], snapshot: at(9, 59, 30)),
        at(10, 0, 20),
        receivedAt: at(10, 0, 18),
      );

      final e = book.entries['A']!;
      expect(e.price, 100.0);
      expect(e.flash, isNull);
      expect(e.snapshotAt, at(10, 0, 0));
      expect(e.rowTime, '10:00:00');
      expect(book.fetchedAt['A'], at(10, 0, 20), reason: '這一輪有拿到今天的報價');
      expect(book.symbolStatus['A'], LiveSymbolStatus.ok);
      expect(book.lastReceivedAt['A'], at(10, 0, 18));
      expect(book.lastApplyStats!.applied, 1);
      expect(book.lastApplyStats!.rejected, 1);
      expect(outcome, RoundOutcome.success);
      expect(book.latestResponseHadToday, isTrue);
    });

    test('較舊的快照、那一列的 t 與畫面那筆相同 → 不換', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 5)),
        at(10, 0, 6),
      );
      applyA(
        responded([
          row('A', z: '99.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 2)),
        at(10, 0, 21),
      );
      expect(book.entries['A']!.price, 100.0);
    });

    test('🚨 快照較舊、但那一列的 t 比畫面那筆晚 → 照換(這一檔自己有更新)', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 5)),
        at(10, 0, 6),
      );
      applyA(
        responded([
          row('A', z: '99.0000', t: '10:00:02'),
        ], snapshot: at(10, 0, 3)),
        at(10, 0, 21),
      );
      final e = book.entries['A']!;
      expect(e.price, 99.0);
      expect(e.snapshotAt, at(10, 0, 3));
      expect(e.rowTime, '10:00:02');
      expect(book.lastApplyStats!.rejected, 0);
    });

    test('🚨 畫面那筆的 t 無法解析、新的快照較舊 → 不換(無法比較不算比較新)', () {
      applyA(
        responded([row('A', z: '100.0000', t: '9:9')], snapshot: at(10, 0, 5)),
        at(10, 0, 6),
      );
      applyA(
        responded([
          row('A', z: '99.0000', t: '10:00:04'),
        ], snapshot: at(10, 0, 3)),
        at(10, 0, 21),
      );
      expect(book.entries['A']!.price, 100.0);
      expect(book.lastApplyStats!.rejected, 1);
      expect(book.entries['A']!.rowTime, '9:9', reason: '畫面那筆的列時間不動');
    });

    test('快照時刻相等 → 照換', () {
      applyA(
        responded([row('A', z: '100.0000')], snapshot: at(10, 0, 0)),
        at(10, 0, 5),
      );
      applyA(
        responded([row('A', z: '101.0000')], snapshot: at(10, 0, 0)),
        at(10, 0, 20),
      );
      expect(book.entries['A']!.price, 101.0);
    });

    test('🚨 新的沒有快照時刻 → 照換,畫面那筆的快照時刻變成 null', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 0)),
        at(10, 0, 5),
      );
      applyA(responded([row('A', z: '99.0000', t: '09:59:30')]), at(10, 0, 20));
      expect(book.entries['A']!.price, 99.0);
      expect(book.entries['A']!.snapshotAt, isNull);
      expect(book.lastApplyStats!.missingSnapshots, 1);
      expect(book.lastApplyStats!.futureSnapshots, 0);
    });

    test('畫面那筆沒有快照時刻 → 照換', () {
      applyA(responded([row('A', z: '100.0000', t: '10:00:00')]), at(10, 0, 5));
      applyA(
        responded([
          row('A', z: '99.0000', t: '09:59:30'),
        ], snapshot: at(9, 59, 30)),
        at(10, 0, 20),
      );
      expect(book.entries['A']!.price, 99.0);
      expect(book.entries['A']!.snapshotAt, at(9, 59, 30));
    });

    test('🚨 快照時刻比收到的時刻晚超過 60 秒 → 當成沒有;之後正常的快照照常換上', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 1, 21)),
        at(10, 0, 20),
      );
      expect(book.entries['A']!.price, 100.0);
      expect(book.entries['A']!.snapshotAt, isNull);
      expect(book.lastApplyStats!.futureSnapshots, 1);
      expect(book.lastApplyStats!.missingSnapshots, 1);

      applyA(
        responded([
          row('A', z: '101.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 30)),
        at(10, 0, 35),
      );
      expect(book.entries['A']!.price, 101.0, reason: '偏前的那一份不能讓這一檔停住');
      expect(book.entries['A']!.snapshotAt, at(10, 0, 30));
      expect(book.lastApplyStats!.futureSnapshots, 0);
    });

    test('快照時刻恰好比收到的時刻晚 60 秒 → 照用', () {
      applyA(
        responded([row('A', z: '100.0000')], snapshot: at(10, 1, 20)),
        at(10, 0, 25),
        receivedAt: at(10, 0, 20),
      );
      expect(book.entries['A']!.snapshotAt, at(10, 1, 20));
      expect(book.lastApplyStats!.futureSnapshots, 0);
      expect(book.lastApplyStats!.missingSnapshots, 0);
    });

    test('🚨 偏前與否比的是那一批收到的時刻,不是整輪套用的時刻', () {
      // 多批的一輪:這一批 10:00:20 收到,整輪到 10:01:00 才套用
      applyA(
        responded([row('A', z: '100.0000')], snapshot: at(10, 1, 21)),
        at(10, 1, 0),
        receivedAt: at(10, 0, 20),
      );
      expect(book.entries['A']!.snapshotAt, isNull);
      expect(book.lastApplyStats!.futureSnapshots, 1);
    });

    test('沒給收到的時刻 → 偏前與否改跟套用的時刻比', () {
      book.apply(
        responded([row('A', z: '100.0000')], snapshot: at(10, 1, 21)),
        requested: const ['A'],
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(book.entries['A']!.snapshotAt, isNull);
      expect(book.lastApplyStats!.futureSnapshots, 1);
    });

    test('🚨 快照日期不是今天 → 當成沒有(不算偏前)', () {
      applyA(
        responded([
          row('A', z: '100.0000'),
        ], snapshot: DateTime(2026, 10, 5, 13, 30)),
        at(10, 0, 5),
      );
      expect(book.entries['A']!.price, 100.0);
      expect(book.entries['A']!.snapshotAt, isNull);
      expect(book.lastApplyStats!.futureSnapshots, 0);
      expect(book.lastApplyStats!.missingSnapshots, 1);
    });

    test('🚨 剛閃過色的那一檔,下一輪收到較舊的快照 → 不換、不閃', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 0)),
        at(10, 0, 5),
      );
      applyA(
        responded([
          row('A', z: '101.0000', t: '10:00:15'),
        ], snapshot: at(10, 0, 16)),
        at(10, 0, 20),
      );
      expect(book.entries['A']!.flash?.up, isTrue);

      applyA(
        responded([
          row('A', z: '100.5000', t: '10:00:08'),
        ], snapshot: at(10, 0, 9)),
        at(10, 0, 35),
      );
      expect(book.entries['A']!.price, 101.0);
      expect(book.entries['A']!.flash, isNull);
    });

    test('🚨 擋下一輪之後,下一輪換上去的價格變動照樣閃色', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 1)),
        at(10, 0, 5),
      );
      applyA(
        responded([
          row('A', z: '99.0000', t: '09:59:40'),
        ], snapshot: at(9, 59, 41)),
        at(10, 0, 20),
      );
      expect(book.lastApplyStats!.rejected, 1);
      applyA(
        responded([
          row('A', z: '101.0000', t: '10:00:30'),
        ], snapshot: at(10, 0, 31)),
        at(10, 0, 35),
      );
      expect(book.entries['A']!.flash?.up, isTrue, reason: '比的是畫面上的 100');
    });

    test('🚨 被擋下的那一檔:上一輪批次失敗的卡片狀態回到 ok', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 1)),
        at(10, 0, 5),
      );
      book.apply(
        failed({'A'}),
        requested: const ['A'],
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(book.symbolStatus['A'], LiveSymbolStatus.batchFailed);

      applyA(
        responded([
          row('A', z: '99.0000', t: '09:59:40'),
        ], snapshot: at(9, 59, 41)),
        at(10, 0, 35),
      );
      expect(book.lastApplyStats!.rejected, 1);
      expect(book.symbolStatus['A'], LiveSymbolStatus.ok);
    });

    test('整輪都被擋下,仍算最近一次有回應的一輪有今天的報價', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:00'),
        ], snapshot: at(10, 0, 1)),
        at(10, 0, 5),
      );
      // 這一輪有回應、但列的日期是昨天
      applyA(
        responded([
          row('A', z: '100.0000', d: '20261005', t: '13:30:00'),
        ], snapshot: at(10, 0, 15)),
        at(10, 0, 20),
      );
      expect(book.latestResponseHadToday, isFalse);

      final outcome = applyA(
        responded([
          row('A', z: '99.0000', t: '09:59:40'),
        ], snapshot: at(9, 59, 41)),
        at(10, 0, 35),
      );
      expect(book.lastApplyStats!.rejected, 1);
      expect(outcome, RoundOutcome.success);
      expect(book.latestResponseHadToday, isTrue);
    });

    test('🚨 比的是那一列的 t,不是顯示用的成交時間', () {
      // 當輪沒有成交:顯示 trade 記著的 10:00:10 那筆,列的 t 是 10:00:40
      applyA(
        responded([
          row(
            'A',
            b: '100.5000_',
            a: '101.5000_',
            t: '10:00:40',
            trade: const {'t': '10:00:10', 'z': '101.0000'},
          ),
        ], snapshot: at(10, 0, 41)),
        at(10, 0, 45),
      );
      expect(book.entries['A']!.quoteTime, '10:00:10');
      expect(book.entries['A']!.rowTime, '10:00:40');

      // 較舊的快照,列的 t 10:00:29 比顯示的成交時間晚、但比畫面那一列早
      applyA(
        responded([
          row('A', z: '99.0000', t: '10:00:29'),
        ], snapshot: at(10, 0, 30)),
        at(10, 1, 0),
      );
      expect(book.entries['A']!.price, 101.0);
      expect(book.lastApplyStats!.rejected, 1);
    });

    test('withoutFlash 保留快照時刻與那一列的 t', () {
      final e = LiveQuoteEntry(
        symbol: 'A',
        date: at(0, 0),
        price: 100,
        displaySource: LiveDisplaySource.trade,
        previousClose: 99,
        quoteTime: '10:00:00',
        isClosingQuote: false,
        flash: const LiveQuoteFlash(id: 1, up: true),
        snapshotAt: at(10, 0, 1),
        rowTime: '10:00:00',
      ).withoutFlash();
      expect(e.flash, isNull);
      expect(e.snapshotAt, at(10, 0, 1));
      expect(e.rowTime, '10:00:00');
    });

    test('🚨 被擋下的那一份不更新今天記到的成交價', () {
      applyA(
        responded([
          row('A', z: '101.0000', t: '10:00:10'),
        ], snapshot: at(10, 0, 11)),
        at(10, 0, 12),
      );
      applyA(
        responded([
          row('A', z: '99.0000', t: '10:00:01'),
        ], snapshot: at(10, 0, 2)),
        at(10, 0, 27),
      );
      // 只有五檔、沒有 trade:顯示價走今天記到的成交價
      applyA(
        responded([
          row('A', b: '102.0000_', a: '103.0000_', t: '10:00:40'),
        ], snapshot: at(10, 0, 41)),
        at(10, 0, 42),
      );
      final e = book.entries['A']!;
      expect(e.displaySource, LiveDisplaySource.lastTrade);
      expect(e.price, 101.0);
    });

    test('🚨 收盤後被擋下仍計一次嘗試:試滿 10 次就不再抓', () {
      QuoteBatchReport notClosing(DateTime snapshot) => responded([
        row('A', b: '99.5000_', a: '100.5000_', t: '13:29:40'),
      ], snapshot: snapshot);

      applyA(notClosing(at(13, 30, 55)), at(13, 31), afterClose: true);
      for (var i = 1; i < 10; i++) {
        expect(book.pendingAfterClose(const ['A']), ['A'], reason: '第 $i 次後');
        applyA(notClosing(at(13, 30, 50)), at(13, 31 + i), afterClose: true);
        expect(book.lastApplyStats!.rejected, 1, reason: '第 ${i + 1} 次');
      }
      expect(book.pendingAfterClose(const ['A']), isEmpty);
    });

    test('🚨 最近一次收到:只記拿到今天報價的代號', () {
      // A 有今天的報價、B 的列被解析丟掉、C 的報價是昨天的、D 沒帶收到時刻
      book.apply(
        responded([
          row('A', z: '100.0000'),
          row('B'),
          row('C', z: '100.0000', d: '20261005'),
          row('D', z: '100.0000'),
        ]),
        requested: const ['A', 'B', 'C', 'D'],
        now: at(10, 0, 5),
        afterClose: false,
        receivedAt: {'A': at(10, 0, 3), 'B': at(10, 0, 3), 'C': at(10, 0, 3)},
      );
      expect(book.lastReceivedAt, {'A': at(10, 0, 3)});
      expect(
        () => book.lastReceivedAt['Z'] = at(10, 0, 3),
        throwsUnsupportedError,
      );
    });

    test('最近一次收到:這一輪沒拿到的保留舊時刻', () {
      applyA(responded([row('A', z: '100.0000')]), at(10, 0, 5));
      book.apply(
        failed({'A'}),
        requested: const ['A'],
        now: at(10, 0, 20),
        afterClose: false,
        receivedAt: {'A': at(10, 0, 19)},
      );
      expect(book.lastReceivedAt, {'A': at(10, 0, 3)});
    });

    test('這一次套用的統計:換上與擋下都算進總數,最舊快照只看換上去的', () {
      expect(book.lastApplyStats, isNull, reason: '還沒有套用過');
      QuoteBatchReport merged(List<QuoteBatchReport> parts) => QuoteBatchReport(
        quotes: {for (final p in parts) ...p.quotes},
        errors: const [],
        respondedSymbols: {for (final p in parts) ...p.respondedSymbols},
        failedSymbols: const <String>{},
      );
      const abc = ['A', 'B', 'C'];
      book.apply(
        merged([
          responded([row('A', z: '100.0000')], snapshot: at(10, 0, 0)),
          responded([row('B', z: '50.0000')], snapshot: at(10, 0, 2)),
          responded([row('C', z: '10.0000')], snapshot: at(10, 0, 4)),
        ]),
        requested: abc,
        now: at(10, 0, 5),
        afterClose: false,
      );
      expect(book.lastApplyStats, (
        applied: 3,
        rejected: 0,
        futureSnapshots: 0,
        missingSnapshots: 0,
        oldestSnapshot: at(10, 0, 0),
      ));

      // A 收到更舊的(擋下)、B 與 C 各換上一份較新的
      book.apply(
        merged([
          responded([row('A', z: '99.0000')], snapshot: at(9, 59, 0)),
          responded([row('B', z: '51.0000')], snapshot: at(10, 0, 18)),
          responded([row('C', z: '11.0000')], snapshot: at(10, 0, 12)),
        ]),
        requested: abc,
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(book.lastApplyStats, (
        applied: 3,
        rejected: 1,
        futureSnapshots: 0,
        missingSnapshots: 0,
        oldestSnapshot: at(10, 0, 12),
      ));

      book.apply(
        failed({'A', 'B', 'C'}),
        requested: abc,
        now: at(10, 0, 35),
        afterClose: false,
      );
      expect(book.lastApplyStats, (
        applied: 0,
        rejected: 0,
        futureSnapshots: 0,
        missingSnapshots: 0,
        oldestSnapshot: null,
      ));
    });

    test('🚨 換日清空:最近一次收到、統計', () {
      applyA(
        responded([
          row('A', z: '100.0000', t: '10:00:05'),
        ], snapshot: at(10, 0, 6)),
        at(10, 0, 7),
      );
      expect(book.lastReceivedAt, isNotEmpty);
      expect(book.rollDay(DateTime(2026, 10, 7, 8, 30)), isTrue);
      expect(book.lastReceivedAt, isEmpty);
      expect(book.lastApplyStats, isNull);
    });
  });
}

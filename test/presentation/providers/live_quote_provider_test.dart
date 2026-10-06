import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 報價中心(2026-10-06,spec §3、§8、驗證 4)。
///
/// 真的 IntradayQuoteClient 接假 HTTP adapter、假時鐘、fakeAsync:請求字串、
/// 批數、節流、暫停、退避都量在 HTTP 那一層。時鐘 = 起點 + 經過時間(+ 跳動)。
void main() {
  late List<String> crumbs; // category 為 LiveQuote 的 breadcrumb
  late List<String> misCrumbs; // category 為 MIS(client 逐批 warning)
  late List<Object> captured;

  setUp(() {
    crumbs = [];
    misCrumbs = [];
    captured = [];
    AppLogger.setSentryDelegates(
      breadcrumb: (message, category, level, data) {
        if (category == 'LiveQuote') crumbs.add(message);
        if (category == 'MIS') misCrumbs.add(message);
      },
      capture: (error, stackTrace, tag, message) => captured.add(error),
    );
  });
  tearDown(() => AppLogger.setSentryDelegates());

  const tsmc = LiveQuoteRegistration(symbol: '2330', market: MarketCode.twse);
  final weekdayMorning = DateTime(2026, 10, 6, 10, 1); // 週二 10:01:00
  final afterCloseStart = DateTime(2026, 10, 6, 13, 31);
  List<Duration> secs(List<int> s) => [for (final x in s) Duration(seconds: x)];

  test('🚨 報價中心的 client:短逾時、不逐批記 warning', () {
    final container = ProviderContainer();
    final client = container.read(liveQuoteClientProvider);
    expect(client.dio.options.connectTimeout, LiveQuoteParams.connectTimeout);
    expect(client.dio.options.receiveTimeout, LiveQuoteParams.receiveTimeout);
    expect(client.logsBatchErrors, isFalse);
    container.dispose();
  });

  group('何時抓', () {
    test('只抓登記的聯集;登記後等下一拍才發', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.center.register('B', const [
          tsmc,
          LiveQuoteRegistration(symbol: '6538', market: MarketCode.tpex),
        ]);
        async.flushMicrotasks();
        expect(h.requests, isEmpty, reason: '登記不會立刻觸發請求');

        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(1));
        expect(h.requests.single.exCh, ['tse_2330.tw', 'otc_6538.tw']);
        h.dispose();
      });
    });

    test('🚨 大盤指數硬對應市場別(不論登記時帶什麼)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('index', const [
          LiveQuoteRegistration(
            symbol: LiveQuoteParams.twseIndexSymbol,
            market: MarketCode.tpex,
          ),
          LiveQuoteRegistration(
            symbol: LiveQuoteParams.tpexIndexSymbol,
            market: MarketCode.twse,
          ),
        ]);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests.single.exCh, ['tse_t00.tw', 'otc_o00.tw']);
        h.dispose();
      });
    });

    test('沒有登記、週六、國慶補假、盤前都不發請求', () {
      for (final (label, start, register) in [
        ('沒有登記', weekdayMorning, false),
        ('週六', DateTime(2026, 10, 3, 10, 1), true),
        ('國慶補假', DateTime(2026, 10, 9, 10, 1), true),
        ('盤前', DateTime(2026, 10, 6, 8, 30), true),
      ]) {
        fakeAsync((async) {
          final h = _Harness(async, start);
          if (register) h.center.register('A', const [tsmc]);
          h.elapse(const Duration(minutes: 20));
          expect(h.requests, isEmpty, reason: label);
          h.dispose();
        });
      }
    });

    test('盤前登記 → 09:00 起抓(先讓過 CLI 的 10 秒)', () {
      fakeAsync((async) {
        final h = _Harness(async, DateTime(2026, 10, 6, 8, 59, 50));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 19)); // 到 09:00:09
        expect(h.requests, isEmpty);
        h.elapse(const Duration(seconds: 1)); // 09:00:10
        expect(h.sentAt, secs([20]));
        h.dispose();
      });
    });

    test('🚨 App 隱藏時不抓;回到可見 → 下一拍照常', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, isEmpty);
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(1));
        h.dispose();
      });
    });

    test('🚨 上一個請求還沒回來 → 跳過,不疊加(同一輪的下一批也等)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) => Future.delayed(
            const Duration(milliseconds: 29500),
            () => _tradeEach(exCh, now),
          );
        h.center.register('A', [
          for (var i = 0; i < 40; i++)
            LiveQuoteRegistration(
              symbol: '${2000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(seconds: 30));
        expect(h.sentAt, secs([1]), reason: '第一批還在路上時不發第二批');
        h.elapse(const Duration(seconds: 2));
        expect(h.sentAt, secs([1, 31]), reason: '30.5 秒回來,下一拍才送第二批');
        expect(captured, isEmpty);
        h.dispose();
      });
    });

    test('🚨 快速登記與取消(切分頁)不造成連發', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1));
        for (var i = 0; i < 5; i++) {
          h.center.unregister('A');
          h.elapse(const Duration(milliseconds: 100));
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(milliseconds: 100));
        }
        h.elapse(const Duration(milliseconds: 14500)); // 到第 16.5 秒
        expect(h.requests, hasLength(1));
        h.elapse(const Duration(milliseconds: 500)); // 第 17 秒
        expect(h.requests, hasLength(2), reason: '距上一輪滿 15 秒才發');
        h.dispose();
      });
    });
  });

  group('請求量', () {
    test('2 批:一輪內兩批隔 3 秒(時鐘只到整秒,實際至少 2 秒),15 秒一輪', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', [
          for (var i = 0; i < 40; i++)
            LiveQuoteRegistration(
              symbol: '${2000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(seconds: 20));
        expect(h.sentAt, secs([1, 4, 16, 19]));
        expect([for (final r in h.requests) r.exCh.length], [35, 5, 35, 5]);
        h.dispose();
      });
    });

    for (final batches in const [3, 4, 10]) {
      test('🚨 $batches 批:任何 60 秒內 ≤ 8 個請求、相鄰 ≥ 2 秒、每檔都輪得到', () {
        fakeAsync((async) {
          final h = _Harness(async, weekdayMorning);
          final symbols = [
            for (var i = 0; i < batches * 35; i++) '${1000 + i}',
          ];
          h.center.register('A', [
            for (final s in symbols)
              LiveQuoteRegistration(symbol: s, market: MarketCode.twse),
          ]);
          h.elapse(const Duration(minutes: 6));

          final at = h.sentAt;
          for (var i = 0; i < at.length; i++) {
            final window = at
                .where(
                  (t) => t >= at[i] && t < at[i] + const Duration(minutes: 1),
                )
                .length;
            expect(
              window,
              lessThanOrEqualTo(LiveQuoteParams.maxRequestsPerMinute),
              reason: '從 ${at[i]} 起的 60 秒',
            );
            if (i > 0) {
              expect(
                at[i] - at[i - 1],
                greaterThanOrEqualTo(LiveQuoteParams.minRequestGap),
              );
            }
          }
          expect({
            for (final r in h.requests) ...r.exCh.map(_symbolOf),
          }, symbols.toSet());
          h.dispose();
        });
      });
    }

    test('🚨 每 5 分鐘整點後 10 秒內不發請求(讓給盤中提醒 CLI)', () {
      fakeAsync((async) {
        final h = _Harness(async, DateTime(2026, 10, 6, 10, 4));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 7));
        final times = [for (final r in h.requests) r.at];
        expect(times.where((t) => t.minute % 5 == 0 && t.second < 10), isEmpty);
        expect(
          times,
          contains(DateTime(2026, 10, 6, 10, 5, 10)),
          reason: '窗口一過就補發',
        );
        h.dispose();
      });
    });
  });

  group('結果分類、暫停與退避', () {
    test('🚨 rtcode 非 0000 算失敗;距上一次有回應超過 60 秒才判暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => '{"rtcode":"5000"}';
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 61)); // 從第 1 拍起計 60 秒
        expect(h.state.stalled, isFalse);
        expect(h.state.symbolStatus['2330'], LiveSymbolStatus.batchFailed);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.stalled, isTrue);
        h.dispose();
      });
    });

    test('🚨 連續多輪日期不是今天 → 「今天尚無報價」,不變成網路暫停、不退避', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([
            for (final e in exCh) _row(_symbolOf(e), now, d: '20261005'),
          ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 3));
        expect(h.requests, hasLength(12), reason: '照 15 秒節奏,沒有退避');
        expect(h.state.stalled, isFalse);
        expect(h.state.latestResponseHadToday, isFalse);
        expect(h.state.entries, isEmpty);
        expect(h.state.symbolStatus['2330'], LiveSymbolStatus.noQuote);
        h.dispose();
      });
    });

    test('🚨 只登記一檔而那檔被解析丟掉(暫停交易)→ 卡片標無報價、不退避', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([
            {'c': '2330', 'z': '-', 'pz': '-', 'd': _ymd(now), 't': _hms(now)},
          ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, hasLength(8));
        expect(h.state.stalled, isFalse);
        expect(h.state.symbolStatus['2330'], LiveSymbolStatus.noQuote);
        h.dispose();
      });
    });

    test('🚨 暫停後每次失敗間隔加倍,最長 2 分鐘', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 420));
        // 第 61 秒那輪送出時計時剛好 60 秒,還不算暫停;第 62 秒起暫停,
        // 之後間隔 15 → 30 → 60 → 120 → 120
        expect(h.sentAt, secs([1, 16, 31, 46, 61, 76, 106, 166, 286, 406]));
        h.dispose();
      });
    });

    test('恢復後解除暫停、回到 15 秒節奏', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 63));
        expect(h.state.stalled, isTrue);
        h.respond = _tradeEach;
        h.elapse(const Duration(seconds: 29)); // 到第 92 秒
        expect(h.sentAt, secs([1, 16, 31, 46, 61, 76, 91]));
        expect(h.state.stalled, isFalse);
        expect(
          h.state.lastRespondedAt,
          weekdayMorning.add(const Duration(seconds: 91)),
        );
        h.dispose();
      });
    });

    test('🚨 限流:停 5 分鐘,之後只發 1 個試探請求;試探成功才恢復整輪', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async {
          if (h.requests.length == 1) {
            return '<!doctype html><html>Too many requests</html>';
          }
          return _tradeEach(exCh, now);
        };
        h.center.register('A', [
          for (var i = 0; i < 40; i++)
            LiveQuoteRegistration(
              symbol: '${2000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(seconds: 2));
        expect(
          h.state.rateLimitedUntil,
          weekdayMorning.add(const Duration(seconds: 301)),
        );

        h.elapse(const Duration(seconds: 298)); // 到第 300 秒
        expect(h.requests, hasLength(1));
        h.elapse(const Duration(seconds: 1)); // 第 301 秒:試探
        expect(h.requests, hasLength(2));
        expect(h.requests.last.exCh, hasLength(35), reason: '試探只送第一批');
        expect(h.state.rateLimitedUntil, isNull);

        h.elapse(const Duration(seconds: 20));
        expect(h.sentAt, secs([1, 301, 316, 319]), reason: '試探成功後恢復兩批');
        h.dispose();
      });
    });
  });

  group('收盤後', () {
    String notClosing(List<String> exCh, DateTime now) => _mis([
      for (final e in exCh)
        _row(
          _symbolOf(e),
          now,
          z: '-',
          b: '99.5000_',
          a: '100.5000_',
          t: '13:29:40',
        ),
    ]);

    test('🚨 全部拿到收盤報價、不再發請求 → 不會變成暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => _mis([
            for (final e in exCh) _row(_symbolOf(e), now, t: '13:30:00'),
          ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 5));
        expect(h.requests, hasLength(1));
        expect(h.state.entries['2330']!.isClosingQuote, isTrue);
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('14:10 才打開仍會抓(收盤後沒有時間上限)', () {
      fakeAsync((async) {
        final h = _Harness(async, DateTime(2026, 10, 6, 14, 10));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 9)); // 14:10:00–09 是 CLI 避讓窗
        expect(h.requests, isEmpty);
        h.elapse(const Duration(seconds: 1)); // 14:10:10
        expect(h.requests, hasLength(1));
        h.dispose();
      });
    });

    test('🚨 畫面已有今天正式資料就不抓;任一畫面還沒有就抓;盤後資料寫入後重新登記 → 停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => notClosing(exCh, now);
        const official = LiveQuoteRegistration(
          symbol: '2330',
          market: MarketCode.twse,
          hasOfficialToday: true,
        );
        h.center.register('A', const [official]);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, isEmpty);

        h.center.register('B', const [tsmc]);
        h.elapse(const Duration(seconds: 61));
        expect(h.requests, hasLength(2), reason: '收盤報價還沒出來:每分鐘一次');

        h.center.register('B', const [official]);
        h.elapse(const Duration(minutes: 3));
        expect(h.requests, hasLength(2));
        h.dispose();
      });
    });

    test('🚨 拿不到收盤報價:每分鐘一次,10 次後停,之後不判暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => notClosing(exCh, now);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 20));
        expect(h.requests, hasLength(LiveQuoteParams.afterCloseMaxAttempts));
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('🚨 網路失敗不計入 10 次;還要抓的期間會判暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 30));
        expect(
          h.requests.length,
          greaterThan(LiveQuoteParams.afterCloseMaxAttempts),
        );
        expect(h.state.stalled, isTrue);
        h.dispose();
      });
    });
  });

  group('顯示價與閃色(經真的解析)', () {
    test('🚨 本輪 z 為 - 但有 trade.z → 最後成交價;沒有 trade 時沿用記住的成交價', () {
      fakeAsync((async) {
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([
            switch (++round) {
              1 => _row('2330', now, z: '100.0000'),
              2 => _row(
                '2330',
                now,
                z: '-',
                b: '100.5000_',
                a: '101.5000_',
                trade: const {'t': '10:01:15', 'z': '101.0000'},
              ),
              _ => _row('2330', now, z: '-', b: '102.0000_', a: '103.0000_'),
            },
          ]);
        h.center.register('A', const [tsmc]);

        h.elapse(const Duration(seconds: 1));
        expect(h.state.entries['2330']!.price, 100.0);

        h.elapse(const Duration(seconds: 15));
        final second = h.state.entries['2330']!;
        expect(second.price, 101.0);
        expect(second.displaySource, LiveDisplaySource.lastTrade);
        expect(second.quoteTime, '10:01:15');

        h.elapse(const Duration(seconds: 15));
        expect(h.state.entries['2330']!.price, 101.0, reason: '不是五檔中價 102.5');
        h.dispose();
      });
    });

    test('🚨 閃色只在連續兩輪都是成交類且價格改變,方向比上一輪', () {
      fakeAsync((async) {
        const prices = ['100.0000', '101.0000', '101.0000', '100.5000'];
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async =>
              _mis([_row('2330', now, z: prices[round++])]);
        h.center.register('A', const [tsmc]);
        LiveQuoteFlash? flashAfter(int seconds) {
          h.elapse(Duration(seconds: seconds));
          return h.state.entries['2330']!.flash;
        }

        expect(flashAfter(1), isNull, reason: '第一輪沒有上一輪可比');
        final up = flashAfter(15);
        expect(up?.up, isTrue);
        expect(flashAfter(15), isNull, reason: '價格沒變');
        final down = flashAfter(15);
        expect(down?.up, isFalse);
        expect(down!.id, isNot(up!.id));
        h.dispose();
      });
    });

    test('🚨 切走再切回來(期間沒有任何一輪)→ 回來的第一輪不閃', () {
      fakeAsync((async) {
        const prices = ['100.0000', '101.0000', '102.0000'];
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async =>
              _mis([_row('2330', now, z: prices[round++])]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 16)); // 1、16 兩輪
        expect(h.state.entries['2330']!.flash, isNotNull);

        h.center.unregister('A'); // 切到沒有即時報價的分頁
        h.elapse(const Duration(minutes: 10));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(3));
        expect(h.state.entries['2330']!.price, 102.0);
        expect(
          h.state.entries['2330']!.flash,
          isNull,
          reason: '比較的是 10 分鐘前的價格',
        );
        h.dispose();
      });
    });

    test('🚨 限流暫停後的試探那一輪不閃', () {
      fakeAsync((async) {
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => switch (++round) {
            1 => _mis([_row('2330', now, z: '100.0000')]),
            2 => '<!doctype html><html>Too many requests</html>',
            _ => _mis([_row('2330', now, z: '101.0000')]),
          };
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 16)); // 1 成功、16 限流
        expect(h.state.rateLimitedUntil, isNotNull);
        h.elapse(const Duration(minutes: 5)); // 316 試探
        expect(h.requests, hasLength(3));
        expect(h.state.entries['2330']!.price, 101.0);
        expect(h.state.entries['2330']!.flash, isNull, reason: '比較的是 5 分鐘前的價格');
        h.dispose();
      });
    });
  });

  group('紀錄', () {
    test('🚨 一段連續失敗只在開始與恢復各記一筆;中心的 client 不逐批記', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 65)); // 1、16、31、46、61 五輪失敗
        h.respond = _tradeEach;
        h.elapse(const Duration(seconds: 15)); // 76 恢復
        expect(crumbs, hasLength(2));
        expect(crumbs.first, contains('即時報價中斷'));
        expect(crumbs.last, contains('連續失敗 5 輪'));
        expect(misCrumbs, isEmpty, reason: 'logBatchErrors: false');
        h.dispose();
      });
    });

    test('🚨 非預期錯誤送 Sentry(帶例外物件),同一段失敗只送一次', () {
      fakeAsync((async) {
        var broken = true;
        final client = _ScriptedClient((batch) async {
          if (broken) throw StateError('解析爆了');
          return QuoteBatchReport(
            quotes: const {},
            errors: const [],
            respondedSymbols: batch.keys.toSet(),
            failedSymbols: const <String>{},
          );
        });
        final h = _Harness(async, weekdayMorning, client: client);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 50)); // 1、16、31、46 四輪
        expect(captured, hasLength(1));
        expect(captured.single, isA<StateError>());

        broken = false;
        h.elapse(const Duration(seconds: 15)); // 61:有回應 → 這一段結束
        broken = true;
        h.elapse(const Duration(seconds: 15)); // 76:新的一段
        expect(captured, hasLength(2));
        h.dispose();
      });
    });
  });

  group('可見性、睡眠、換日、釋放', () {
    test('🚨 隱藏期間不計暫停時間', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 30));
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 10));
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 20));
        expect(h.state.stalled, isFalse, reason: '可見時累計約 48 秒');
        h.elapse(const Duration(seconds: 15));
        expect(h.state.stalled, isTrue);
        h.dispose();
      });
    });

    test('🚨 一輪送到一半就隱藏 → 那一輪作廢,回來後重抓,不把舊批次當新的', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', [
          for (var i = 0; i < 105; i++)
            LiveQuoteRegistration(
              symbol: '${1000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(milliseconds: 1500)); // 第 1 批已回來
        expect(h.requests, hasLength(1));
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 10));
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 10));

        expect(
          _symbolOf(h.requests[1].exCh.first),
          '1000',
          reason: '回來後從第 1 批重新開始',
        );
        expect(
          h.state.entries['1000']!.quoteTime,
          '10:11:02',
          reason: '不是隱藏前 10:01:01 那批',
        );
        h.dispose();
      });
    });

    test('🚨 一輪送到一半登記就變了 → 剩下的批次不送,依新的登記重新規劃', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', [
          for (var i = 0; i < 350; i++)
            LiveQuoteRegistration(
              symbol: '${1000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(milliseconds: 1500)); // 10 批的第 1 批已回來
        h.center.register('A', const [
          LiveQuoteRegistration(symbol: '9999', market: MarketCode.twse),
        ]);
        h.elapse(const Duration(seconds: 16));
        expect(h.requests, hasLength(2), reason: '舊清單剩下的 9 批不送');
        expect(h.requests.last.exCh, ['tse_9999.tw']);
        expect(h.state.entries['1000'], isNotNull, reason: '已拿到的第 1 批照常套用');
        expect(
          h.state.symbolStatus.containsKey('1035'),
          isFalse,
          reason: '沒送出的批次不算請求過',
        );
        h.dispose();
      });
    });

    test('畫面重建時用同一份清單再登記 → 進行中的一輪照常送完', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        final list = [
          for (var i = 0; i < 70; i++)
            LiveQuoteRegistration(
              symbol: '${1000 + i}',
              market: MarketCode.twse,
            ),
        ];
        h.center.register('A', list);
        h.elapse(const Duration(milliseconds: 1500));
        h.center.register('A', [...list]);
        h.elapse(const Duration(seconds: 3));
        expect(h.sentAt, secs([1, 4]));
        expect(_symbolOf(h.requests[1].exCh.first), '1035');
        h.dispose();
      });
    });

    test('隱藏時還在路上的請求,回來後丟棄(那一輪作廢)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) => Future.delayed(
            const Duration(seconds: 5),
            () => _tradeEach(exCh, now),
          );
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 2)); // 第 1 秒送出、第 6 秒才回來
        h.center.setAppVisible(false);
        h.elapse(const Duration(seconds: 10));
        expect(h.state.entries, isEmpty);
        h.dispose();
      });
    });

    test('🚨 電腦睡眠喚醒:時鐘跳 2 小時 → 下一拍照常抓', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 20));
        expect(h.requests, hasLength(2));
        h.jump = const Duration(hours: 2);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(3));
        expect(h.requests.last.at, DateTime(2026, 10, 6, 12, 1, 21));
        expect(h.state.stalled, isFalse, reason: '醒來那一輪有回應');
        h.dispose();
      });
    });

    test('🚨 App 開著過夜:隔天第一拍清掉昨天的報價,不當成今天', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.entries['2330']!.date, DateTime(2026, 10, 6));

        h.jump = const Duration(hours: 23); // 10/7 09:01:02
        h.respond = (_, _) async => throw const _NetworkDown();
        h.elapse(const Duration(seconds: 1));
        expect(h.state.entries, isEmpty);
        expect(h.state.latestResponseHadToday, isNull);
        expect(h.state.stalled, isFalse, reason: '過夜那段不計入暫停時間');
        h.dispose();
      });
    });

    test('🚨 請求途中 dispose → 回來後不碰 state、不留計時器', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) => Future.delayed(
            const Duration(seconds: 5),
            () => _tradeEach(exCh, now),
          );
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 2));
        h.dispose();
        h.elapse(const Duration(seconds: 10));
        expect(async.periodicTimerCount, 0);
        expect(captured, isEmpty, reason: 'dispose 後不可再讀 ref 或寫 state');
      });
    });
  });
}

class _Clock implements AppClock {
  _Clock(this._now);
  final DateTime Function() _now;

  @override
  DateTime now() => _now();
}

/// 在 fakeAsync 裡建一個報價中心
class _Harness {
  _Harness(this.async, this.t0, {IntradayQuoteClient? client}) {
    container = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(now)),
        liveQuoteClientProvider.overrideWithValue(
          client ??
              IntradayQuoteClient(
                dio: Dio()..httpClientAdapter = _MisAdapter(_serve),
                logBatchErrors: false,
              ),
        ),
      ],
    );
  }

  final FakeAsync async;
  final DateTime t0;
  late final ProviderContainer container;

  /// 時鐘跳動(模擬電腦睡眠):加在經過時間之上
  Duration jump = Duration.zero;

  /// 每個請求:送出時刻與 ex_ch 各項(例:tse_2330.tw)
  final requests = <({DateTime at, List<String> exCh})>[];

  /// 回應內容;預設每檔都回一筆當下時間的成交
  Future<String> Function(List<String> exCh, DateTime now) respond = _tradeEach;

  DateTime now() => t0.add(async.elapsed + jump);
  LiveQuoteCenter get center =>
      container.read(liveQuoteCenterProvider.notifier);
  LiveQuoteState get state => container.read(liveQuoteCenterProvider);
  List<Duration> get sentAt => [for (final r in requests) r.at.difference(t0)];

  Future<String> _serve(List<String> exCh) {
    requests.add((at: now(), exCh: exCh));
    return respond(exCh, now());
  }

  void elapse(Duration d) => async.elapse(d);
  void dispose() => container.dispose();
}

class _MisAdapter implements HttpClientAdapter {
  _MisAdapter(this.serve);

  final Future<String> Function(List<String> exCh) serve;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final exCh = options.uri.queryParameters['ex_ch']!.split('|');
    return ResponseBody.fromString(
      await serve(exCh),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ScriptedClient extends IntradayQuoteClient {
  _ScriptedClient(this.script) : super(dio: Dio(), logBatchErrors: false);

  final Future<QuoteBatchReport> Function(Map<String, String> batch) script;

  @override
  Future<QuoteBatchReport> fetchQuotesDetailed(Map<String, String> markets) =>
      script(markets);
}

class _NetworkDown implements Exception {
  const _NetworkDown();

  @override
  String toString() => 'NetworkDown: 模擬斷線';
}

String _two(int v) => v.toString().padLeft(2, '0');
String _ymd(DateTime t) => '${t.year}${_two(t.month)}${_two(t.day)}';
String _hms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// tse_2330.tw → 2330
String _symbolOf(String exCh) => exCh.substring(4, exCh.length - 3);

String _mis(List<Map<String, Object?>> rows) =>
    jsonEncode({'rtcode': '0000', 'msgArray': rows});

Map<String, Object?> _row(
  String c,
  DateTime now, {
  String z = '100.0000',
  String y = '99.0000',
  String? d,
  String? t,
  String b = '-',
  String a = '-',
  Map<String, String>? trade,
}) => {
  'c': c,
  'z': z,
  'pz': '-',
  'y': y,
  'd': d ?? _ymd(now),
  't': t ?? _hms(now),
  'b': b,
  'a': a,
  'trade': ?trade,
};

Future<String> _tradeEach(List<String> exCh, DateTime now) async =>
    _mis([for (final e in exCh) _row(_symbolOf(e), now)]);

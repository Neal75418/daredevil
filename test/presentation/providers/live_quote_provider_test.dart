import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
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

  /// 盤中 App 看不見時,兩種平台對外的行為相同:不在背景收集的停計時器,
  /// 在背景收集的計時器照跑、每一拍自己判斷不抓。[body] 兩種都跑一次
  void onBothPlatforms(
    DateTime start,
    void Function(_Harness h, FakeAsync async, String label) body, {
    Future<String> Function(List<String> exCh, DateTime now)? respond,
  }) {
    for (final collect in [false, true]) {
      fakeAsync((async) {
        final h = _Harness(async, start, collectAfterCloseWhenHidden: collect);
        if (respond != null) h.respond = respond;
        body(h, async, collect ? '在背景收集的平台' : '不在背景收集的平台');
      });
    }
  }

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
      onBothPlatforms(weekdayMorning, (h, async, label) {
        h.center.register('A', const [tsmc]);
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, isEmpty, reason: label);
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(1), reason: label);
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

    test('🚨 試滿 10 次的代號與第 10 次的時刻出現在發布的 closingGivenUpAt;拿到收盤報價的不在', () {
      fakeAsync((async) {
        const other = LiveQuoteRegistration(
          symbol: '2317',
          market: MarketCode.twse,
        );
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => _mis([
            for (final e in exCh)
              if (_symbolOf(e) == '2317')
                _row('2317', now, t: '13:30:00')
              else
                _row(
                  _symbolOf(e),
                  now,
                  z: '-',
                  b: '99.5000_',
                  a: '100.5000_',
                  t: '13:29:40',
                ),
          ]);
        expect(h.state.closingGivenUpAt, isEmpty, reason: '預設空的');
        h.center.register('A', const [tsmc, other]);
        // 每秒前進,直到第 9 個請求送出並套用(最多 20 分鐘)
        for (
          var i = 0;
          i < 1200 &&
              h.requests.length < LiveQuoteParams.afterCloseMaxAttempts - 1;
          i++
        ) {
          h.elapse(const Duration(seconds: 1));
        }
        h.elapse(const Duration(seconds: 1));
        expect(
          h.requests,
          hasLength(LiveQuoteParams.afterCloseMaxAttempts - 1),
          reason: '前提',
        );
        expect(h.state.entries['2317']!.isClosingQuote, isTrue, reason: '前提');
        expect(h.state.closingGivenUpAt, isEmpty, reason: '第 9 次');

        h.elapse(const Duration(minutes: 2));
        expect(h.requests, hasLength(LiveQuoteParams.afterCloseMaxAttempts));
        expect(h.state.closingGivenUpAt, {'2330': h.requests.last.at});
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

  group('各檔拿到今天報價的時刻', () {
    test('🚨 一輪結束後只含拿到今天報價的檔,時刻是套用那一輪的時間;換日清空', () {
      fakeAsync((async) {
        var down = false;
        final client = _ScriptedClient((batch) async {
          if (down) throw const _NetworkDown();
          // 9901 有今天的報價、9902 的報價是昨天的、9903 的批次失敗
          return QuoteBatchReport(
            quotes: IntradayQuote.parseResponse({
              'rtcode': '0000',
              'msgArray': [
                _row('9901', weekdayMorning),
                _row('9902', weekdayMorning, d: '20261005'),
              ],
            }),
            errors: const ['DioException.connectionTimeout: 模擬'],
            respondedSymbols: const {'9901', '9902'},
            failedSymbols: const {'9903'},
          );
        });
        final h = _Harness(async, weekdayMorning, client: client);
        expect(h.state.fetchedAt, isEmpty, reason: '還沒有任何一輪');
        h.center.register('A', const [
          LiveQuoteRegistration(symbol: '9901', market: MarketCode.twse),
          LiveQuoteRegistration(symbol: '9902', market: MarketCode.twse),
          LiveQuoteRegistration(symbol: '9903', market: MarketCode.twse),
        ]);
        h.elapse(const Duration(seconds: 1));
        final firstRoundAt = weekdayMorning.add(const Duration(seconds: 1));
        expect(h.state.fetchedAt, {'9901': firstRoundAt});
        expect(h.state.symbolStatus['9902'], LiveSymbolStatus.noQuote);
        expect(h.state.symbolStatus['9903'], LiveSymbolStatus.batchFailed);

        h.jump = const Duration(hours: 23); // 10/7 09:01:02
        down = true;
        h.elapse(const Duration(seconds: 1));
        expect(h.state.fetchedAt, isEmpty, reason: '昨天的時刻不帶到今天');
        h.dispose();
      });
    });
  });

  group('最近一次收到', () {
    List<LiveQuoteRegistration> stocks(int n) => [
      for (var i = 0; i < n; i++)
        LiveQuoteRegistration(symbol: '${2000 + i}', market: MarketCode.twse),
    ];
    DateTime sec(int s) => weekdayMorning.add(Duration(seconds: s));

    test('🚨 兩批的一輪:各檔記自己那一批收到的時刻,不是整輪套用的時刻', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        expect(h.state.lastReceivedAt, isEmpty, reason: '還沒有任何一輪');
        h.center.register('A', stocks(40));
        h.elapse(const Duration(seconds: 4)); // 第 1 秒送第 1 批、第 4 秒第 2 批
        final received = h.state.lastReceivedAt;
        expect(received, hasLength(40));
        expect(received['2000'], sec(1));
        expect(received['2034'], sec(1));
        expect(received['2035'], sec(4));
        expect(h.state.fetchedAt['2000'], sec(4), reason: '套用是整輪結束時');
        h.dispose();
      });
    });

    test('🚨 記的是回應回來的當下,不是送出的時刻', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) => Future.delayed(
          const Duration(seconds: 2),
          () => _tradeEach(exCh, now),
        );
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 3)); // 第 1 秒送出、第 3 秒回來
        expect(h.sentAt, secs([1]));
        expect(h.state.lastReceivedAt['2330'], sec(3));
        h.dispose();
      });
    });

    test('🚨 App 看不見而作廢的一輪:已回來的與還在路上的批次都不記', () {
      onBothPlatforms(
        weekdayMorning,
        respond: (exCh, now) {
          final body = _tradeEach(exCh, now);
          // 第 2 批(5 檔)晚 3 秒才回來
          return exCh.length == 35
              ? body
              : Future.delayed(const Duration(seconds: 3), () => body);
        },
        (h, async, label) {
          h.center.register('A', stocks(40));
          h.elapse(const Duration(seconds: 5)); // 第 2 批第 4 秒送出、還在路上
          expect(h.requests, hasLength(2), reason: label);
          h.center.setAppVisible(false);
          h.elapse(const Duration(seconds: 5)); // 第 7 秒回來
          expect(h.state.lastReceivedAt, isEmpty, reason: label);
          expect(h.state.entries, isEmpty, reason: label);
          h.dispose();
        },
      );
    });

    test('🚨 限流丟掉的一輪:先回來的那一批也不記', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async {
          if (exCh.length != 35) {
            return '<!doctype html><html>Too many requests</html>';
          }
          return _tradeEach(exCh, now);
        };
        h.center.register('A', stocks(40));
        h.elapse(const Duration(seconds: 4));
        expect(h.state.rateLimitedUntil, isNotNull);
        expect(h.state.lastReceivedAt, isEmpty);
        h.dispose();
      });
    });

    test('🚨 登記變了而截斷的一輪:已回來的那一批照記它收到的時刻', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', stocks(40));
        h.elapse(const Duration(seconds: 1)); // 第 1 批回來
        h.center.register('B', const [
          LiveQuoteRegistration(symbol: '6538', market: MarketCode.tpex),
        ]);
        h.elapse(const Duration(seconds: 1)); // 第 2 秒:截斷並套用
        expect(h.requests, hasLength(1));
        expect(h.state.lastReceivedAt, hasLength(35));
        expect(h.state.lastReceivedAt['2000'], sec(1));
        expect(h.state.fetchedAt['2000'], sec(2), reason: '套用在截斷的那一拍');
        h.dispose();
      });
    });

    test('🚨 盤中途暫停交易:那一檔停在最後有報價的那一批', () {
      fakeAsync((async) {
        var halted = false;
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async => _mis([
          for (final symbol in exCh.map(_symbolOf))
            _row(
              symbol,
              now,
              // 沒有成交也沒有五檔:列被解析丟掉
              z: halted && symbol == '2001' ? '-' : '100.0000',
            ),
        ], at: now);
        h.center.register('A', stocks(2));
        h.elapse(const Duration(seconds: 16)); // 1、16 兩輪都有報價
        halted = true;
        h.elapse(const Duration(seconds: 30)); // 31、46
        expect(h.state.symbolStatus['2001'], LiveSymbolStatus.noQuote);
        expect(h.state.lastReceivedAt['2001'], sec(16));
        expect(h.state.lastReceivedAt['2000'], sec(46));
        h.dispose();
      });
    });

    test('🚨 批次失敗:那一批的代號維持上一次收到的時刻', () {
      fakeAsync((async) {
        var down = false;
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async {
          if (down && exCh.length != 35) throw const _NetworkDown();
          return _tradeEach(exCh, now);
        };
        h.center.register('A', stocks(40));
        h.elapse(const Duration(seconds: 4)); // 1、4
        down = true;
        h.elapse(const Duration(seconds: 15)); // 16、19
        expect(h.state.symbolStatus['2035'], LiveSymbolStatus.batchFailed);
        expect(h.state.lastReceivedAt['2035'], sec(4));
        expect(h.state.lastReceivedAt['2000'], sec(16));
        h.dispose();
      });
    });

    test('換日清空', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.lastReceivedAt, isNotEmpty);
        h.jump = const Duration(hours: 23); // 10/7 09:01:02
        h.respond = (_, _) async => throw const _NetworkDown();
        h.elapse(const Duration(seconds: 1));
        expect(h.state.lastReceivedAt, isEmpty);
        h.dispose();
      });
    });
  });

  group('快照時刻的觀測', () {
    List<String> about(String keyword) => [
      for (final c in crumbs)
        if (c.contains(keyword)) c,
    ];

    test('🚨 整輪都沒有可信的快照時刻:同一天只記一次,換日後再記', () {
      fakeAsync((async) {
        var withSnapshot = false;
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async => _mis([
          for (final e in exCh) _row(_symbolOf(e), now),
        ], at: withSnapshot ? now : null);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 31)); // 1、16、31 三輪
        expect(about('沒有可信的快照時刻'), hasLength(1));

        withSnapshot = true;
        h.elapse(const Duration(seconds: 15)); // 46
        withSnapshot = false;
        h.elapse(const Duration(seconds: 15)); // 61
        expect(about('沒有可信的快照時刻'), hasLength(1), reason: '恢復後再缺,同一天不再記');
        expect(about('快照時刻偏前'), isEmpty);

        h.jump = const Duration(hours: 23); // 10/7 09:02:02
        h.elapse(const Duration(seconds: 1));
        expect(about('沒有可信的快照時刻'), hasLength(2));
        h.dispose();
      });
    });

    test('🚨 快照時刻偏前:同一天只記一次,換日後再記', () {
      fakeAsync((async) {
        var ahead = const Duration(minutes: 2);
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async => _mis([
          for (final e in exCh) _row(_symbolOf(e), now),
        ], at: now.add(ahead));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 31)); // 1、16、31 三輪
        expect(about('快照時刻偏前'), hasLength(1));
        expect(h.state.entries['2330']!.snapshotAt, isNull);

        ahead = Duration.zero;
        h.elapse(const Duration(seconds: 15)); // 46
        expect(h.state.entries['2330']!.snapshotAt, isNotNull);
        ahead = const Duration(minutes: 2);
        h.elapse(const Duration(seconds: 15)); // 61
        expect(about('快照時刻偏前'), hasLength(1), reason: '恢復後再偏前,同一天不再記');

        h.jump = const Duration(hours: 23); // 10/7 09:02:02
        h.elapse(const Duration(seconds: 1));
        expect(about('快照時刻偏前'), hasLength(2));
        h.dispose();
      });
    });

    test('🚨 整輪都偏前的那一輪不算缺失:同一天之後真的沒帶快照時刻時照記', () {
      fakeAsync((async) {
        DateTime? Function(DateTime now) snapshotOf = (now) =>
            now.add(const Duration(minutes: 2));
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async => _mis([
          for (final e in exCh) _row(_symbolOf(e), now),
        ], at: snapshotOf(now));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1)); // 第 1 輪:偏前
        expect(about('快照時刻偏前'), hasLength(1));
        expect(about('沒有可信的快照時刻'), isEmpty);

        snapshotOf = (_) => null;
        h.elapse(const Duration(seconds: 15)); // 第 2 輪:回應沒帶快照時刻
        expect(about('沒有可信的快照時刻'), hasLength(1));
        h.dispose();
      });
    });

    test('只有一部分的批次沒有快照時刻:不記(整輪都沒有才記)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async => _mis([
          for (final e in exCh) _row(_symbolOf(e), now),
        ], at: exCh.length == 35 ? now : null);
        h.center.register('A', [
          for (var i = 0; i < 40; i++)
            LiveQuoteRegistration(
              symbol: '${2000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(seconds: 4));
        expect(h.state.entries['2000']!.snapshotAt, isNotNull);
        expect(h.state.entries['2035']!.snapshotAt, isNull);
        expect(about('沒有可信的快照時刻'), isEmpty);
        h.dispose();
      });
    });

    test('🚨 有回應但沒有今天報價的一輪:不記快照時刻的 warning', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async => _mis([
          for (final e in exCh) _row(_symbolOf(e), now, d: '20261005'),
        ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 31));
        expect(h.state.latestResponseHadToday, isFalse);
        expect(about('快照時刻'), isEmpty);
        h.dispose();
      });
    });

    test('每一輪結束記一行:擋下、沒有可信快照時刻與偏前的檔數、最舊快照、App 是否可見', () {
      final lines = <String>[];
      runZoned(
        () => fakeAsync((async) {
          var shift = Duration.zero;
          var withSnapshot = true;
          final h = _Harness(async, weekdayMorning);
          h.respond = (exCh, now) async {
            // 這份回應的快照時刻與列的時間都是「現在＋shift」
            final at = now.add(shift);
            return _mis([
              for (final e in exCh) _row(_symbolOf(e), at),
            ], at: withSnapshot ? at : null);
          };
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(seconds: 1));
          shift = const Duration(minutes: -1); // 第 2 輪:1 分鐘前的快照
          h.elapse(const Duration(seconds: 15));
          shift = const Duration(minutes: 2); // 第 3 輪:偏前
          h.elapse(const Duration(seconds: 15));
          shift = Duration.zero; // 第 4 輪:回應沒帶快照時刻
          withSnapshot = false;
          h.elapse(const Duration(seconds: 15));
          h.dispose();
        }),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => lines.add(line),
        ),
      );
      final rounds = [
        for (final l in lines)
          if (l.contains('[D] [LiveQuote]') && l.contains('擋下')) l,
      ];
      expect(rounds, hasLength(4));
      expect(rounds[0], contains('擋下 0 檔'));
      expect(rounds[0], contains('沒有可信快照時刻 0 檔(其中偏前 0 檔)'));
      expect(rounds[0], contains('最舊快照 10:01:01'));
      expect(rounds[0], contains('App 可見'));
      expect(rounds[1], contains('擋下 1 檔'));
      expect(rounds[1], contains('最舊快照 無'));
      expect(rounds[2], contains('擋下 0 檔'));
      expect(rounds[2], contains('沒有可信快照時刻 1 檔(其中偏前 1 檔)'));
      expect(rounds[3], contains('沒有可信快照時刻 1 檔(其中偏前 0 檔)'));
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
      onBothPlatforms(
        weekdayMorning,
        respond: (_, _) async => throw const _NetworkDown(),
        (h, async, label) {
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(seconds: 30));
          h.center.setAppVisible(false);
          h.elapse(const Duration(minutes: 10));
          h.center.setAppVisible(true);
          h.elapse(const Duration(seconds: 20));
          expect(h.state.stalled, isFalse, reason: '$label:可見時累計約 48 秒');
          h.elapse(const Duration(seconds: 15));
          expect(h.state.stalled, isTrue, reason: label);
          h.dispose();
        },
      );
    });

    test('🚨 一輪送到一半就隱藏 → 那一輪作廢,回來後重抓,不把舊批次當新的', () {
      onBothPlatforms(weekdayMorning, (h, async, label) {
        h.center.register('A', [
          for (var i = 0; i < 105; i++)
            LiveQuoteRegistration(
              symbol: '${1000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(milliseconds: 1500)); // 第 1 批已回來
        expect(h.requests, hasLength(1), reason: label);
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 10));
        expect(h.requests, hasLength(1), reason: '$label:看不見時剩下的批次不送');
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 10));

        expect(
          _symbolOf(h.requests[1].exCh.first),
          '1000',
          reason: '$label:回來後從第 1 批重新開始',
        );
        expect(
          h.state.entries['1000']!.quoteTime,
          '10:11:02',
          reason: '$label:不是隱藏前 10:01:01 那批',
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
      onBothPlatforms(
        weekdayMorning,
        respond: (exCh, now) => Future.delayed(
          const Duration(seconds: 5),
          () => _tradeEach(exCh, now),
        ),
        (h, async, label) {
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(seconds: 2)); // 第 1 秒送出、第 6 秒才回來
          h.center.setAppVisible(false);
          h.elapse(const Duration(seconds: 10));
          expect(h.state.entries, isEmpty, reason: label);
          h.dispose();
        },
      );
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

  group('App 看不見時收盤後照樣收完(在背景收集的平台)', () {
    const rateLimitedPage = '<!doctype html><html>Too many requests</html>';
    const official = LiveQuoteRegistration(
      symbol: '2330',
      market: MarketCode.twse,
      hasOfficialToday: true,
    );

    /// 10/6(週二)與 10/7(週三)都是交易日
    DateTime at(int hour, int minute, [int second = 0, int day = 6]) =>
        DateTime(2026, 10, day, hour, minute, second);
    final beforeClose = at(13, 25);

    /// 每檔都回收盤報價(13:30:00 的成交)
    Future<String> closing(List<String> exCh, DateTime now) async => _mis([
      for (final e in exCh) _row(_symbolOf(e), now, t: '13:30:00'),
    ], at: now);

    /// 有回應但不是收盤報價(沒有成交、只有五檔)
    Future<String> notClosing(List<String> exCh, DateTime now) async => _mis([
      for (final e in exCh)
        _row(
          _symbolOf(e),
          now,
          z: '-',
          b: '99.5000_',
          a: '100.5000_',
          t: '13:29:40',
        ),
    ], at: now);

    /// 一開始就看不見的報價中心
    _Harness hidden(FakeAsync async, DateTime start, {bool collect = true}) =>
        _Harness(async, start, collectAfterCloseWhenHidden: collect)
          ..center.setAppVisible(false);

    List<DateTime> sentTimes(_Harness h) => [for (final r in h.requests) r.at];

    test('🚨 盤中不抓,計時器照跑(每一拍自己判斷)', () {
      fakeAsync((async) {
        final h = hidden(async, at(10, 0));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 10));
        expect(h.requests, isEmpty);
        expect(async.periodicTimerCount, 1);
        h.dispose();
      });
    });

    test('🚨 看不見時跨過 13:30 自己開始收;都拿到收盤報價後不再發請求', () {
      fakeAsync((async) {
        final h = hidden(async, beforeClose)..respond = closing;
        h.center.register('A', [
          for (var i = 0; i < 60; i++)
            LiveQuoteRegistration(
              symbol: '${2000 + i}',
              market: MarketCode.twse,
            ),
        ]);
        h.elapse(const Duration(minutes: 5, seconds: 9)); // 13:30:09
        expect(h.requests, isEmpty, reason: '盤中不抓;13:30:00–09 讓給 CLI');
        h.elapse(const Duration(seconds: 5)); // 13:30:14
        expect(sentTimes(h), [at(13, 30, 10), at(13, 30, 13)]);
        expect(h.state.entries, hasLength(60));
        expect(h.state.entries.values.every((e) => e.isClosingQuote), isTrue);

        h.elapse(const Duration(hours: 1)); // 14:30:14
        expect(h.requests, hasLength(2), reason: '收完就不再送');
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('🚨 看不見時收完、一直看不見到隔天:過夜與隔天盤中都不抓', () {
      fakeAsync((async) {
        final h = hidden(async, beforeClose)..respond = closing;
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(hours: 19, minutes: 46)); // 隔天 09:11
        expect(h.now(), at(9, 11, 0, 7), reason: '前提');
        expect(sentTimes(h), [at(13, 30, 10)], reason: '只有前一天收盤後那一次');
        expect(h.state.entries, isEmpty, reason: '換日清空');
        h.dispose();
      });
    });

    test('🚨 前一天收完並停、一直看不見:隔天 13:30 之後照樣開始', () {
      fakeAsync((async) {
        final h = hidden(async, beforeClose)..respond = closing;
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(days: 1, minutes: 6)); // 隔天 13:31
        expect(sentTimes(h), [at(13, 30, 10), at(13, 30, 10, 7)]);
        expect(h.state.entries['2330']!.date, DateTime(2026, 10, 7));
        h.dispose();
      });
    });

    test('🚨 收盤後一直斷線:判為暫停後不再送;重新可見的下一拍照常送', () {
      fakeAsync((async) {
        final h = hidden(async, beforeClose)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 7)); // 13:32:00
        expect(h.state.stalled, isFalse, reason: '13:30:00 起算恰好 120 秒');
        h.elapse(const Duration(seconds: 1)); // 13:32:01
        expect(h.state.stalled, isTrue);
        expect(sentTimes(h), [at(13, 30, 10), at(13, 31, 10)]);

        h.elapse(const Duration(minutes: 8, seconds: 19)); // 13:40:20
        expect(h.requests, hasLength(2), reason: '沒人看得到,不重試');
        expect(h.state.stalled, isTrue);

        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 1));
        expect(sentTimes(h).last, at(13, 40, 21));
        expect(h.requests, hasLength(3));
        h.dispose();
      });
    });

    test('🚨 判為暫停的那一拍剛好輪到重抓:那一拍也不送', () {
      fakeAsync((async) {
        // 13:30:09 第一拍起算(還在 CLI 窗口、不送),13:30:10、13:31:10 各送
        // 一次;13:32:10 滿 121 秒判為暫停,同一拍也是下一次重抓的時刻
        final h = hidden(async, at(13, 30, 8))
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 121)); // 13:32:09
        expect(h.state.stalled, isFalse, reason: '前提:恰好 120 秒');
        expect(sentTimes(h), [at(13, 30, 10), at(13, 31, 10)], reason: '前提');
        h.elapse(const Duration(seconds: 30)); // 13:32:39
        expect(h.state.stalled, isTrue);
        expect(h.requests, hasLength(2), reason: '13:32:10 那一拍判為暫停、不送');
        h.dispose();
      });
    });

    test('🚨 可見時判為暫停、隨即看不見:13:30 之後也不送(收盤後暫停門檻較長,'
        '暫停不因此自己解除);重新可見的下一拍照常送', () {
      fakeAsync((async) {
        final h = _Harness(async, at(13, 27), collectAfterCloseWhenHidden: true)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 61)); // 13:28:01
        expect(h.state.stalled, isFalse, reason: '前提:13:27:01 起算恰好 60 秒');
        h.elapse(const Duration(seconds: 1)); // 13:28:02
        expect(h.state.stalled, isTrue, reason: '前提:盤中門檻 60 秒');

        // 看不見的當下無回應約 89 秒:超過盤中的 60 秒、不到收盤後的 120 秒
        h.elapse(const Duration(seconds: 28)); // 13:28:30
        final sentWhileVisible = h.requests.length;
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 11, seconds: 50)); // 13:40:20
        expect(h.requests, hasLength(sentWhileVisible), reason: '看不見之後不送');
        expect(h.state.stalled, isTrue);

        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 1));
        expect(sentTimes(h).last, at(13, 40, 21));
        expect(h.requests, hasLength(sentWhileVisible + 1));
        h.dispose();
      });
    });

    test('🚨 兩個畫面登記同一檔、都說「已有今天正式資料」,其中一個是前一天登記的:'
        '照樣替它抓(兩種登記順序)', () {
      for (final staleFirst in [true, false]) {
        fakeAsync((async) {
          final h = hidden(async, at(14, 0))..respond = notClosing;
          // 兩個畫面都在前一天登記;staleFirst 決定哪一個排在前面
          h.center.register(staleFirst ? 'stale' : 'fresh', const [official]);
          h.center.register(staleFirst ? 'fresh' : 'stale', const [official]);
          h.elapse(const Duration(hours: 23)); // 隔天 13:00
          h.center.register('fresh', const [official]); // 這個畫面隔天重建了
          h.elapse(const Duration(minutes: 30, seconds: 30)); // 隔天 13:30:30
          expect(sentTimes(h), [
            at(13, 30, 10, 7),
          ], reason: 'staleFirst=$staleFirst:沒重建的那個畫面還沒有今天的正式資料');

          h.center.unregister('stale');
          h.elapse(const Duration(minutes: 5)); // 隔天 13:35:30
          expect(
            h.requests,
            hasLength(1),
            reason: 'staleFirst=$staleFirst:只剩今天登記的「已有」',
          );
          h.dispose();
        });
      }
    });

    test('🚨 看不見時被限流:到期也不試探;重新可見的下一拍才試探', () {
      fakeAsync((async) {
        final h = hidden(async, beforeClose);
        h.respond = (exCh, now) => h.requests.length == 1
            ? Future.value(rateLimitedPage)
            : closing(exCh, now);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 5, seconds: 11)); // 13:30:11
        expect(sentTimes(h), [at(13, 30, 10)]);
        expect(h.state.rateLimitedUntil, at(13, 35, 10));

        // 超過 2 × rateLimitPause(13:40:10),避開 13:40:00–09 的 CLI 窗口
        h.elapse(const Duration(minutes: 10, seconds: 9)); // 13:40:20
        expect(h.requests, hasLength(1), reason: '限流到期也不在看不見時試探');

        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 1));
        expect(sentTimes(h), [at(13, 30, 10), at(13, 40, 21)]);
        expect(h.state.rateLimitedUntil, isNull, reason: '試探成功');
        expect(h.state.entries['2330']!.isClosingQuote, isTrue);
        h.dispose();
      });
    });

    test('🚨 可見時被限流、隨即看不見:到期後也不試探', () {
      fakeAsync((async) {
        final h = _Harness(async, at(13, 30), collectAfterCloseWhenHidden: true)
          ..respond = (_, _) async => rateLimitedPage;
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 11)); // 13:30:10 送出、被限流
        expect(sentTimes(h), [at(13, 30, 10)]);
        expect(h.state.rateLimitedUntil, at(13, 35, 10));

        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 10, seconds: 9)); // 13:40:20
        expect(h.requests, hasLength(1));
        h.dispose();
      });
    });

    test('🚨 看不見時套用的輪次不閃色(同樣的兩輪在可見時會閃)', () {
      for (final visible in [true, false]) {
        fakeAsync((async) {
          var round = 0;
          final h =
              _Harness(async, at(13, 30), collectAfterCloseWhenHidden: true)
                ..respond = (exCh, now) async => switch (++round) {
                  // 第 1 輪:13:29:50 的成交,不是收盤報價 → 1 分鐘後再抓
                  1 => _mis([
                    _row('2330', now, z: '100.0000', t: '13:29:50'),
                  ], at: now),
                  _ => _mis([
                    _row('2330', now, z: '101.0000', t: '13:30:00'),
                  ], at: now),
                };
          h.center.setAppVisible(visible);
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(seconds: 71)); // 13:30:10、13:31:10 兩輪
          expect(sentTimes(h), [at(13, 30, 10), at(13, 31, 10)], reason: '前提');
          final entry = h.state.entries['2330']!;
          expect(entry.price, 101.0);
          expect(entry.isClosingQuote, isTrue);
          expect(
            entry.flash,
            visible ? isNotNull : isNull,
            reason: visible ? '對照:可見時價格變了會閃' : '收完後沒有下一輪,閃色會留到切回來才播',
          );
          h.dispose();
        });
      }
    });

    test('🚨 前一天以「已有今天正式資料」登記、看不見跨到隔天:收盤後照樣替它收;'
        '隔天重新登記後照新的來', () {
      fakeAsync((async) {
        final h = hidden(async, at(14, 0))..respond = notClosing;
        h.center.register('A', const [official]);
        h.elapse(const Duration(hours: 23, minutes: 30)); // 隔天 13:30:00
        expect(h.requests, isEmpty, reason: '登記當天已有正式資料;過夜、隔天盤中都不抓');

        h.elapse(const Duration(seconds: 30)); // 隔天 13:30:30
        expect(sentTimes(h), [
          at(13, 30, 10, 7),
        ], reason: '「已有今天正式資料」是前一天登記的,隔天不算數');

        // 頁面重建、以今天的狀態再登記
        h.center.register('A', const [official]);
        h.elapse(const Duration(minutes: 5)); // 隔天 13:35:30
        expect(h.requests, hasLength(1), reason: '今天登記的「已有正式資料」算數');
        h.dispose();
      });
    });

    test('不在背景收集的平台:看不見時計時器停,收盤後也不抓', () {
      fakeAsync((async) {
        final h = hidden(async, beforeClose, collect: false)..respond = closing;
        h.center.register('A', const [tsmc]);
        expect(async.periodicTimerCount, 0);
        h.elapse(const Duration(minutes: 15)); // 13:40
        expect(h.requests, isEmpty);
        h.dispose();
      });
    });

    test('🚨 沒有注入時由目標平台決定:只有 macOS 在背景收集', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          fakeAsync((async) {
            final h = _Harness(async, beforeClose)..respond = closing;
            h.center.setAppVisible(false);
            h.center.register('A', const [tsmc]);
            h.elapse(const Duration(minutes: 6)); // 13:31
            expect(
              h.requests,
              platform == TargetPlatform.macOS ? hasLength(1) : isEmpty,
              reason: '$platform',
            );
            h.dispose();
          });
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });

    group('紀錄', () {
      /// 跑 [body],回傳 LiveQuote 的 debug 行
      List<String> debugLines(void Function(FakeAsync async) body) {
        final lines = <String>[];
        runZoned(
          () => fakeAsync(body),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => lines.add(line),
          ),
        );
        return [
          for (final l in lines)
            if (l.contains('[D] [LiveQuote]')) l,
        ];
      }

      test('看不見時放行的每一拍記一行(與上一拍的間隔、無回應時間、暫停門檻);'
          '套用的那一輪標明 App 看不見', () {
        final lines = debugLines((async) {
          final h = hidden(async, at(13, 29, 58))..respond = closing;
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(seconds: 30)); // 13:30:28
          h.dispose();
        });
        final ticks = [
          for (final l in lines)
            if (l.contains('看不見時的一拍')) l,
        ];
        // 13:30:00～13:30:10 每秒一拍;之前是盤中、之後已收完,都不記
        expect(ticks, hasLength(11));
        expect(ticks.first, contains('距上一拍 1000 毫秒'));
        expect(ticks.first, contains('無回應 0 秒'));
        expect(ticks.last, contains('無回應 10 秒'));
        expect(ticks.last, contains('暫停門檻 120 秒'));
        final rounds = [
          for (final l in lines)
            if (l.contains('一輪結束')) l,
        ];
        expect(rounds, hasLength(1));
        expect(rounds.single, contains('App 看不見'));
      });

      test('計時器重新啟動後的第一拍沒有「上一拍」(不拿停掉之前的時刻來算)', () {
        final lines = debugLines((async) {
          final h = hidden(async, at(13, 20))..respond = notClosing;
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(minutes: 1)); // 計時器跑到 13:21
          h.center.unregister('A'); // 沒有登記:計時器停
          h.elapse(const Duration(minutes: 14)); // 13:35
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(seconds: 2));
          h.dispose();
        });
        final ticks = [
          for (final l in lines)
            if (l.contains('看不見時的一拍')) l,
        ];
        expect(ticks, hasLength(2));
        expect(ticks[0], contains('距上一拍 無'));
        expect(ticks[1], contains('距上一拍 1000 毫秒'));
      });

      test('🚨 看不見時判為暫停:那一拍記一行並註明,之後不再每秒一行', () {
        final lines = debugLines((async) {
          final h = hidden(async, at(13, 29, 58))
            ..respond = (_, _) async => throw const _NetworkDown();
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(minutes: 10)); // 13:39:58
          h.dispose();
        });
        final ticks = [
          for (final l in lines)
            if (l.contains('看不見時的一拍')) l,
        ];
        // 13:30:00～13:32:01 每秒一拍,最後一拍判為暫停
        expect(ticks, hasLength(122));
        expect(ticks.last, contains('無回應 121 秒'));
        expect(ticks.last, contains('判為暫停'));
        expect([
          for (final l in ticks.take(121))
            if (l.contains('判為暫停')) l,
        ], isEmpty);
      });
    });
  });

  group('頁首前置修正(第 1 段延後的 Minor)', () {
    test('🚨 換日時清掉限流時刻與最後更新時間(App 開著過夜)', () {
      fakeAsync((async) {
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async {
            round++;
            if (round == 2) return '<!doctype html><html></html>';
            if (round >= 3) {
              await Future<void>.delayed(const Duration(seconds: 5));
              throw const _NetworkDown();
            }
            return _tradeEach(exCh, now);
          };
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 16)); // 1 成功、16 限流
        expect(h.state.lastRespondedAt, isNotNull);
        expect(h.state.rateLimitedUntil, isNotNull);

        h.jump = const Duration(hours: 23); // 10/7 09:01:17
        h.elapse(const Duration(seconds: 1)); // 隔天第一輪還在路上
        expect(h.state.rateLimitedUntil, isNull, reason: '昨天的限流不帶到今天');
        expect(h.state.lastRespondedAt, isNull, reason: '「最後更新」不可是昨天');
        h.dispose();
      });
    });

    test('🚨 限流後已沒有要抓的(收盤後畫面都已有今天正式資料)→ 不對外顯示限流', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (_, _) async => '<!doctype html><html></html>';
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 2));
        expect(h.state.rateLimitedUntil, isNotNull);

        h.center.register('A', const [
          LiveQuoteRegistration(
            symbol: '2330',
            market: MarketCode.twse,
            hasOfficialToday: true,
          ),
        ]);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.rateLimitedUntil, isNull);
        h.dispose();
      });
    });

    test('🚨 限流暫停期間不判網路暫停(頁首只說限流)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => '<!doctype html><html></html>';
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 3));
        expect(h.state.rateLimitedUntil, isNotNull);
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('🚨 請求跨午夜、回應比下一拍早到 → 照樣換日,昨天的暫停計時不帶到隔天開盤', () {
      fakeAsync((async) {
        // 拍子落在每秒 .900:23:59:59.900 送出的請求在 00:00:00.100 回來,
        // 比 00:00:00.900 那一拍早——換日先發生在套用結果的時候
        final h = _Harness(async, DateTime(2026, 10, 6, 23, 58, 57, 900))
          ..respond = (_, _) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            throw const _NetworkDown();
          };
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 63));
        expect(
          [for (final r in h.requests) r.at],
          [
            DateTime(2026, 10, 6, 23, 58, 58, 900),
            DateTime(2026, 10, 6, 23, 59, 59, 900),
          ],
          reason: '前提:第 2 個請求跨午夜',
        );

        h.jump = const Duration(hours: 9, seconds: 20); // 10/7 09:00:21.9 起
        h.elapse(const Duration(seconds: 3));
        expect(h.requests.length, greaterThan(2), reason: '開盤後照常抓');
        expect(h.state.stalled, isFalse, reason: '開盤才 2 秒,不可帶著昨晚的 61 秒');
        h.dispose();
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

/// 在 fakeAsync 裡建一個報價中心。[collectAfterCloseWhenHidden] 不給就用
/// 正式的 `liveQuoteCenterProvider`(由目標平台決定)
class _Harness {
  _Harness(
    this.async,
    this.t0, {
    IntradayQuoteClient? client,
    bool? collectAfterCloseWhenHidden,
  }) {
    container = ProviderContainer(
      overrides: [
        if (collectAfterCloseWhenHidden != null)
          liveQuoteCenterProvider.overrideWith(
            () => LiveQuoteCenter(
              collectAfterCloseWhenHidden: collectAfterCloseWhenHidden,
            ),
          ),
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

/// [at] 是這份回應的快照時刻;不給就沒有 `queryTime`
String _mis(List<Map<String, Object?>> rows, {DateTime? at}) => jsonEncode({
  'rtcode': '0000',
  'msgArray': rows,
  if (at != null) 'queryTime': {'sysDate': _ymd(at), 'sysTime': _hms(at)},
});

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
    _mis([for (final e in exCh) _row(_symbolOf(e), now)], at: now);

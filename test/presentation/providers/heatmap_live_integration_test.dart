import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

import '../../helpers/heatmap_live_fixtures.dart';

/// 熱力圖 × 真的報價中心。
///
/// 真的 `LiveQuoteCenter` 接真的 `IntradayQuoteClient`（假 HTTP adapter）、
/// 隨 fakeAsync 前進的時鐘；熱力圖讀固定的正式資料（上市 1,078 檔的市場，
/// 圖上是市值最大的 30 檔，上一個交易日），登記照 `LiveQuoteScope.listen` 的
/// 做法：聽 `heatmapRegistrationsProvider`，每次通知就以新清單向中心登記。
/// 請求、時刻、進度都量在 HTTP 與 `heatmapLiveProvider` 兩端。
void main() {
  late List<Object> captured;

  setUp(() {
    captured = [];
    AppLogger.setSentryDelegates(
      capture: (error, stackTrace, tag, message) => captured.add(error),
    );
  });
  tearDown(() => AppLogger.setSentryDelegates());

  test('前提：圖上是整個市場市值最大的 30 檔，與代號排序的前 30 不同', () {
    expect(_byCap.toSet(), hasLength(_stockCount));
    expect(_tiles, _byCap.take(HeatmapParams.topTileCount).toList());
    expect([for (final t in heatmapFixtureTwse().tiles) t.symbol], _tiles);
    final bySymbol = [..._byCap]..sort();
    expect(bySymbol.take(_tiles.length).toSet(), isNot(_tiles.toSet()));
  });

  test('🚨 每檔都回收盤報價 → 第一輪就整張圖收齊；只問圖上的檔與指數、每檔只抓一次，'
      '之後不再發請求', () {
    fakeAsync((async) {
      final s = _Session(async);
      s.elapse(const Duration(seconds: 12));
      expect(s.requests, hasLength(_perRound));
      expect(
        {for (final r in s.requests) ...r.symbols},
        {LiveQuoteParams.twseIndexSymbol, ..._tiles},
      );
      expect(s.view.closing, (
        done: _tiles.length,
        unmatched: 0,
        total: _tiles.length,
      ));
      expect(_coloredOf(s.view), _tiles.toSet());
      _expectClosingColor(s.view, _tiles.toSet());
      expect(s.view.stockRegistrations, isEmpty);

      s.elapse(const Duration(minutes: 10));
      expect(s.requests, hasLength(_perRound), reason: '收齊後不再發請求');
      expect(s.requestedStocks, _tiles, reason: '依市值由大到小，每檔恰好一次');
      expect([
        for (final v in s.views) v.view.quoteStatus,
      ], everyElement(isNull));
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 盤中每一輪剛好把指數與圖上的檔問過一遍、不重複，圖上每一檔都上色', () {
    fakeAsync((async) {
      final s = _Session(async, start: _morning);
      s.respond = (_, symbols, now) async =>
          s.snapshot(symbols, now, price: 101);
      s.elapse(const Duration(seconds: 70));

      // 一輪的請求數由檔數決定；照這個數把請求一輪一輪分開
      final rounds = [
        for (final round in s.requests.slices(_perRound))
          if (round.length == _perRound) round,
      ];
      expect(rounds.length, greaterThanOrEqualTo(3));
      for (final round in rounds) {
        final asked = [for (final r in round) ...r.symbols];
        expect(
          asked,
          hasLength(_tiles.length + 1),
          reason: '${round.first.at} 那一輪沒有重複問',
        );
        expect(asked.toSet(), {LiveQuoteParams.twseIndexSymbol, ..._tiles});
      }
      for (var i = 1; i < rounds.length; i++) {
        expect(
          rounds[i].first.at.difference(rounds[i - 1].first.at),
          greaterThanOrEqualTo(LiveQuoteParams.pollInterval),
          reason: '相鄰兩輪至少隔一個輪詢間隔（${rounds[i].first.at}）',
        );
      }
      expect(_coloredOf(s.view), _tiles.toSet());
      expect(s.stalledAt, isEmpty);
      s.dispose();
    });
  });

  test('🚨 圖上 2 檔整天沒成交 → 各被請求恰好 10 次後不再請求；其餘第一輪就收齊，'
      '最近一輪只問它們（沒有今天的報價）時不退回正式資料', () {
    final noTrade = {_tiles[10], _tiles[20]};
    fakeAsync((async) {
      final s = _Session(async, noTrade: noTrade);
      s.elapse(const Duration(minutes: 25));

      final traded = _tiles.length - noTrade.length;
      final filled = s.filledAt(traded);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(s.start.add(const Duration(seconds: 5))),
        isFalse,
        reason: '收齊於 $filled',
      );
      for (final symbol in noTrade) {
        expect(
          s.requests.where((r) => r.symbols.contains(symbol)),
          hasLength(LiveQuoteParams.afterCloseMaxAttempts),
          reason: symbol,
        );
      }
      expect(
        s.requests.last.at.isBefore(
          s.now().subtract(const Duration(minutes: 5)),
        ),
        isTrue,
        reason: '試滿之後中心不再發請求（最後一個請求在 ${s.requests.last.at}）',
      );

      // 前提：最近一輪只問沒成交的那幾檔，有回應但沒有今天的報價
      expect(s.requests.last.symbols.every(noTrade.contains), isTrue);
      expect(s.centerState.latestResponseHadToday, isFalse);

      final view = s.view;
      expect(view.data!.liveMode, HeatmapLiveMode.afterClose);
      expect(view.closing, (
        done: traded,
        unmatched: noTrade.length,
        total: _tiles.length,
      ));
      expect(
        view.quoteStatus,
        isNull,
        reason: '不是 noQuotesToday（誤退回）也不是 pausedNetwork',
      );
      for (final (:at, view: v) in s.views) {
        expect(v.data?.liveMode, HeatmapLiveMode.afterClose, reason: '$at');
        expect(v.quoteStatus, isNull, reason: '$at');
      }
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      final tradedSymbols = _tiles.toSet().difference(noTrade);
      expect(_coloredOf(view), tradedSymbols);
      _expectClosingColor(view, tradedSymbols);
      for (final symbol in noTrade) {
        expect(
          _changeOf(view, symbol),
          isA<TileChangeHollow>().having(
            (c) => c.reason,
            'reason',
            HollowReason.noClosingMatch,
          ),
        );
      }
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 圖上 3 檔收盤那一盤沒撮合 → 每分鐘重試一次、各被請求恰好 10 次後放棄；'
      '其餘第一輪就收齊；格子寫收盤沒撮合、進度另計檔數', () {
    final unmatched = heatmapFixtureUnmatched3();
    expect(unmatched, hasLength(3));
    expect(unmatched.every(_tiles.contains), isTrue, reason: '前提：都在圖上');
    fakeAsync((async) {
      final s = _Session(async, unmatched: unmatched);
      s.elapse(const Duration(minutes: 20));

      final matched = _tiles.length - unmatched.length;
      final filled = s.filledAt(matched);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(s.start.add(const Duration(seconds: 5))),
        isFalse,
        reason: '收齊於 $filled',
      );
      for (final symbol in unmatched) {
        final asked = [
          for (final r in s.requests)
            if (r.symbols.contains(symbol)) r.at,
        ];
        expect(
          asked,
          hasLength(LiveQuoteParams.afterCloseMaxAttempts),
          reason: symbol,
        );
        for (var i = 1; i < asked.length; i++) {
          expect(
            asked[i].difference(asked[i - 1]),
            greaterThanOrEqualTo(LiveQuoteParams.afterCloseRetryInterval),
            reason: '$symbol 第 ${i + 1} 次在 ${asked[i]}',
          );
        }
      }
      expect(
        s.requests.last.at.difference(s.requests.first.at),
        greaterThanOrEqualTo(
          LiveQuoteParams.afterCloseRetryInterval *
              (LiveQuoteParams.afterCloseMaxAttempts - 1),
        ),
        reason: '試滿 10 次要 9 分鐘以上',
      );
      expect(
        s.requests.last.at.isBefore(
          s.now().subtract(const Duration(minutes: 5)),
        ),
        isTrue,
        reason: '都放棄或收齊之後不再發請求（最後一個請求在 ${s.requests.last.at}）',
      );

      final view = s.view;
      expect(view.data!.liveMode, HeatmapLiveMode.afterClose);
      expect(view.closing, (
        done: matched,
        unmatched: unmatched.length,
        total: _tiles.length,
      ));
      expect(view.stockRegistrations, isEmpty, reason: '放棄的代號不再登記');
      final matchedSymbols = _tiles.toSet().difference(unmatched);
      expect(_coloredOf(view), matchedSymbols);
      _expectClosingColor(view, matchedSymbols);
      for (final symbol in unmatched) {
        expect(
          _changeOf(view, symbol),
          isA<TileChangeHollow>().having(
            (c) => c.reason,
            'reason',
            HollowReason.noClosingMatch,
          ),
          reason: symbol,
        );
      }
      expect([
        for (final v in s.views) v.view.quoteStatus,
      ], everyElement(isNull));
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 收盤後只剩每分鐘重抓的幾檔、重抓碰上 CLI 避讓窗口（超過 60 秒沒有回應）'
      '→ 不報「報價暫停」', () {
    // 市值最小的 2 檔整天沒成交：其餘第一輪收齊後只剩它們每分鐘重抓一次
    final noTrade = {_tiles[28], _tiles[29]};
    fakeAsync((async) {
      // 13:31:02 開始：第一輪 13:31:03，之後每分鐘的第 3 秒重抓，13:35:03
      // 那一次落在 13:35:00 的 CLI 避讓窗口
      final s = _Session(
        async,
        start: DateTime(2026, 11, 9, 13, 31, 2),
        noTrade: noTrade,
      );
      s.elapse(const Duration(minutes: 20));

      // 前提：還有檔要抓的期間，曾經超過 stallFloor 沒有任何回應（回應都是
      // 立即的，請求間隔就是沒有回應的時間；結束那一段的請求還在問它們）
      var longest = Duration.zero;
      var gapEnd = 0;
      for (var i = 1; i < s.requests.length; i++) {
        final gap = s.requests[i].at.difference(s.requests[i - 1].at);
        if (gap > longest) {
          longest = gap;
          gapEnd = i;
        }
      }
      expect(
        longest,
        greaterThan(LiveQuoteParams.stallFloor),
        reason: '前提：最長 $longest，止於 ${s.requests[gapEnd].at}',
      );
      expect(
        s.requests[gapEnd].symbols.any(noTrade.contains),
        isTrue,
        reason: '前提：那段期間還有檔要抓',
      );

      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(
        [for (final v in s.views) v.view.quoteStatus],
        everyElement(isNull),
        reason: '不報「報價暫停」',
      );
      for (final symbol in noTrade) {
        expect(
          s.requests.where((r) => r.symbols.contains(symbol)),
          hasLength(LiveQuoteParams.afterCloseMaxAttempts),
          reason: symbol,
        );
      }
      expect(s.view.closing, (
        done: _tiles.length - noTrade.length,
        unmatched: noTrade.length,
        total: _tiles.length,
      ));
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 回應慢 7 秒（未逾時）、回來時落在 CLI 避讓窗口 → 照常套用、整張圖收齊，'
      '不重抓、不報「報價暫停」', () {
    fakeAsync((async) {
      final window = DateTime(2026, 11, 9, 13, 35);
      final windowEnd = window.add(LiveQuoteParams.cliAvoidWindow);
      const delay = Duration(seconds: 7);
      expect(delay, lessThan(LiveQuoteParams.receiveTimeout), reason: '前提：未逾時');
      // 13:34:55 開始：第一批在窗口前幾秒送出，只有它慢
      final s = _Session(async, start: DateTime(2026, 11, 9, 13, 34, 55));
      s.respond = (i, symbols, now) => i == 0
          ? Future.delayed(delay, () => s.normal(symbols, now))
          : s.normal(symbols, now);
      s.elapse(const Duration(minutes: 10));

      final slow = s.requests.first.at;
      expect(slow.isBefore(window), isTrue, reason: '前提：窗口前送出（$slow）');
      final back = slow.add(delay);
      expect(
        !back.isBefore(window) && back.isBefore(windowEnd),
        isTrue,
        reason: '前提：慢的回應在窗口內回來（$back）',
      );
      expect(s.requests, hasLength(_perRound), reason: '慢的那一批照常套用，沒有重抓');
      // 收齊的時刻：慢的那一批回來，或這一輪最後一批送出（回應是立即的），
      // 取晚的
      final lastSent = s.requests.last.at;
      expect(
        s.filledAt(_tiles.length),
        lastSent.isAfter(back) ? lastSent : back,
      );
      expect(s.requestedStocks, _tiles);
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(
        [for (final v in s.views) v.view.quoteStatus],
        everyElement(isNull),
        reason: '不報「報價暫停」',
      );
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 回應超過 receiveTimeout → 那一批失敗、1 分鐘後恰好重抓一次就收齊；'
      '全程不報「報價暫停」', () {
    fakeAsync((async) {
      const delay = Duration(seconds: 10);
      expect(
        delay,
        greaterThan(LiveQuoteParams.receiveTimeout),
        reason: '前提：逾時',
      );
      final s = _Session(async);
      final production = _productionClientTimeouts();
      final testClient = s.container.read(liveQuoteClientProvider).dio.options;
      expect(
        testClient.connectTimeout,
        production.connect,
        reason: '前提：測試 client 的連線逾時與正式 client 相同',
      );
      expect(
        testClient.receiveTimeout,
        production.receive,
        reason: '前提：測試 client 的接收逾時與正式 client 相同',
      );
      s.respond = (i, symbols, now) => i == 0
          ? Future.delayed(delay, () => s.normal(symbols, now))
          : s.normal(symbols, now);
      s.elapse(const Duration(minutes: 10));

      expect(s.requests, hasLength(_perRound + 1), reason: '第一輪之外，逾時的那一批只重抓一次');
      final timedOut = s.requests.first;
      final retry = s.requests.last;
      expect(retry.symbols, containsAll(timedOut.symbols));
      expect(
        retry.at.difference(timedOut.at),
        greaterThanOrEqualTo(
          LiveQuoteParams.receiveTimeout +
              LiveQuoteParams.afterCloseRetryInterval,
        ),
        reason: '逾時之後滿 1 分鐘才重抓（${retry.at}）',
      );
      expect(s.filledAt(_tiles.length), retry.at);
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(
        [for (final v in s.views) v.view.quoteStatus],
        everyElement(isNull),
        reason: '不報「報價暫停」',
      );
      expect(captured, isEmpty, reason: '逾時是預期中的批次失敗，不送 Sentry');
      s.dispose();
    });
  });

  for (final (label, collect) in [
    ('在背景收集的平台：App 看不見時第一輪照樣收齊', true),
    ('不在背景收集的平台：App 看不見時不發請求，回到可見才收', false),
  ]) {
    test('🚨 $label', () {
      fakeAsync((async) {
        final s = _Session(async, collectAfterCloseWhenHidden: collect);
        s.center.setAppVisible(false);
        s.elapse(const Duration(minutes: 2));
        if (collect) {
          expect(s.requests, hasLength(_perRound));
          expect(s.view.closing, (
            done: _tiles.length,
            unmatched: 0,
            total: _tiles.length,
          ));
          _expectClosingColor(s.view, _tiles.toSet());
        } else {
          expect(s.requests, isEmpty);
          expect(s.view.closing, (done: 0, unmatched: 0, total: _tiles.length));
          s.center.setAppVisible(true);
          s.elapse(const Duration(seconds: 12));
          expect(s.requests, hasLength(_perRound));
          expect(s.view.closing?.done, _tiles.length);
        }
        expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
        expect(captured, isEmpty);
        s.dispose();
      });
    });
  }

  group('證交所回較舊的快照（盤中）', () {
    test('🚨 交替回新、舊快照 20 輪 → 顯示價一直是至今最新那一份、沒有往下閃、'
        '報價時間不往回、不誤判暫停', () {
      fakeAsync((async) {
        final s = _Session(async, start: _morning);
        // 每一批（同一組代號）各自的快照：第奇數次回一份新的（價格比上一份
        // 高 1），第偶數次回前一份
        final shots = <String, List<({DateTime at, double price})>>{};
        final served = <String, int>{};
        s.respond = (_, symbols, now) async {
          final key = symbols.join('|');
          final list = shots.putIfAbsent(
            key,
            () => [(at: now.subtract(const Duration(seconds: 30)), price: 100)],
          );
          final n = served.update(key, (v) => v + 1, ifAbsent: () => 1);
          if (n.isOdd) list.add((at: now, price: list.last.price + 1));
          final shot = n.isOdd ? list.last : list[list.length - 2];
          return s.snapshot(symbols, shot.at, price: shot.price);
        };
        // 每次發布：當下各檔「至今最新那一份」的價格，與發布的狀態
        final published =
            <({LiveQuoteState state, Map<String, double> newest})>[];
        final sub = s.container.listen(liveQuoteCenterProvider, (_, next) {
          published.add((
            state: next,
            newest: {
              for (final MapEntry(key: key, value: list) in shots.entries)
                for (final symbol in key.split('|')) symbol: list.last.price,
            },
          ));
        });

        s.elapse(const Duration(minutes: 5, seconds: 30));
        expect(served, hasLength(_perRound), reason: '圖上的檔＋指數分成的批數');
        expect(served.values, everyElement(greaterThanOrEqualTo(20)));

        var upFlashes = 0;
        for (final (:state, :newest) in published) {
          for (final e in state.entries.values) {
            expect(e.price, newest[e.symbol], reason: e.symbol);
            expect(e.flash?.up, isNot(false), reason: '${e.symbol} 往下閃');
            if (e.flash != null) upFlashes++;
          }
        }
        // 頁首的報價時間不往回
        var lastQuoteSeconds = 0;
        var quoteTimes = 0;
        for (final (:at, :view) in s.views) {
          final status = view.quoteStatus;
          if (status == null) continue;
          expect(status.kind, LiveHeaderKind.quoteTime, reason: '$at');
          final seconds = LiveQuoteSchedule.secondsOfDay(status.time)!;
          expect(
            seconds,
            greaterThanOrEqualTo(lastQuoteSeconds),
            reason: '$at',
          );
          lastQuoteSeconds = seconds;
          quoteTimes++;
        }
        expect(quoteTimes, greaterThan(0));
        expect(s.centerState.entries, hasLength(_tiles.length + 1));
        expect(upFlashes, greaterThan(0), reason: '新的一份換上時照樣往上閃');
        expect(s.stalledAt, isEmpty);
        sub.close();
        s.dispose();
      });
    });

    test('🚨 連續幾輪都拿到較舊的快照，離開熱力圖再回來 → 登記的那幾檔照樣上色', () {
      fakeAsync((async) {
        final s = _Session(async, start: _morning);
        final seen = <String>{};
        // 每一批第 1 次回當下的快照（101），之後一直回開盤前的舊快照（99）
        s.respond = (_, symbols, now) async => seen.add(symbols.join('|'))
            ? s.snapshot(symbols, now, price: 101)
            : s.snapshot(
                symbols,
                _morning.subtract(const Duration(minutes: 1)),
                price: 99,
              );
        s.elapse(const Duration(seconds: 60)); // 10:01:00
        final stocks = {for (final r in s.view.stockRegistrations) r.symbol};
        expect(stocks, hasLength(_tiles.length));
        // 第 1 輪換上，之後的每一輪都被擋下
        expect(
          s.requests.length,
          greaterThanOrEqualTo(3 * _perRound),
          reason: '前提：第 1 輪之後至少又問了兩輪',
        );
        for (final symbol in stocks) {
          expect(s.centerState.entries[symbol]!.price, 101, reason: symbol);
        }

        s.closeView();
        s.elapse(Duration.zero);
        s.openView();
        expect(_coloredOf(s.view), containsAll(stocks));
        _expectClosingColor(s.view, stocks);
        s.dispose();
      });
    });

    test('🚨 別的畫面抓到比較新的報價 → 熱力圖頁首的報價時間仍是自己格子裡最新的那一筆', () {
      fakeAsync((async) {
        final s = _Session(async, start: _morning);
        // 另一個畫面登記一檔不在熱力圖裡的股票(與熱力圖的 31 檔同一批):它
        // 每次都是剛成交、列的時間是當下;熱力圖各檔的最後一筆成交停在 09:59:30
        const other = 'OTHER';
        final quiet = DateTime(2026, 11, 9, 9, 59, 30);
        s.respond = (_, symbols, now) async => s.snapshot(
          symbols,
          now,
          price: 101,
          rowAt: (symbol) => symbol == other ? now : quiet,
        );
        s.center.register('other page', const [
          LiveQuoteRegistration(symbol: other, market: MarketCode.twse),
        ]);
        s.elapse(const Duration(seconds: 40));

        expect(
          s.centerState.entries[other]!.rowTime,
          isNot('09:59:30'),
          reason: '前提:另一個畫面那一檔的時間比較新',
        );
        expect(
          s.view.quoteStatus,
          const LiveHeaderStatus(LiveHeaderKind.quoteTime, '09:59:30'),
        );
        s.dispose();
      });
    });

    test('🚨 平常的快取落後（兩份各 115 秒換新、錯開 57 秒、交替回）20 分鐘 → '
        '頁首從不寫報價延遲', () {
      fakeAsync((async) {
        final s = _Session(async, start: _morning);
        const period = Duration(seconds: 115);
        final originA = DateTime(2026, 11, 9, 9, 0);
        final originB = originA.subtract(const Duration(seconds: 57));
        // 某一份快取在 now 當下是什麼時候換新的
        DateTime refreshedAt(DateTime now, DateTime origin) => origin.add(
          period * (now.difference(origin).inSeconds ~/ period.inSeconds),
        );
        final served = <String, int>{};
        s.respond = (_, symbols, now) async {
          final n = served.update(
            symbols.join('|'),
            (v) => v + 1,
            ifAbsent: () => 1,
          );
          final shot = refreshedAt(now, n % 3 == 0 ? originB : originA);
          return s.snapshot(
            symbols,
            shot,
            price: 100 + shot.difference(originA).inSeconds / 1000,
          );
        };
        var maxDelay = Duration.zero;
        final sub = s.container.listen(liveQuoteCenterProvider, (_, next) {
          for (final e in next.entries.values) {
            final received = next.lastReceivedAt[e.symbol];
            final snapshot = e.snapshotAt;
            if (received == null || snapshot == null) continue;
            final delay = received.difference(snapshot);
            if (delay > maxDelay) maxDelay = delay;
          }
        });

        s.elapse(const Duration(minutes: 20));
        expect(
          maxDelay,
          greaterThan(const Duration(seconds: 60)),
          reason: '前提：確實落後到一分鐘以上',
        );
        expect(maxDelay, lessThan(LiveQuoteParams.delayThreshold));
        final kinds = {
          for (final v in s.views)
            if (v.view.quoteStatus case final status?) status.kind,
        };
        expect(kinds, {LiveHeaderKind.quoteTime});
        expect(s.stalledAt, isEmpty);
        sub.close();
        s.dispose();
      });
    });

    test('🚨 一直回同一份 4 分鐘前的快照 → 第一次發布起頁首就是報價延遲、'
        '時刻是那份快照的', () {
      fakeAsync((async) {
        final s = _Session(async, start: _morning);
        final stale = DateTime(2026, 11, 9, 9, 56);
        s.respond = (_, symbols, _) async =>
            s.snapshot(symbols, stale, price: 101);
        s.elapse(const Duration(minutes: 2));

        final withStatus = [
          for (final v in s.views)
            if (v.view.quoteStatus != null) v,
        ];
        expect(withStatus, isNotEmpty);
        // 10:00:00～09 讓給 CLI，第 1 輪從 10:00:10 開始；這一輪的最後一批
        // 回來（回應是立即的）頁首就有狀態
        expect(s.requests.first.at, DateTime(2026, 11, 9, 10, 0, 10));
        expect(withStatus.first.at, s.requests[_perRound - 1].at);
        for (final v in withStatus) {
          expect(
            v.view.quoteStatus,
            const LiveHeaderStatus(LiveHeaderKind.delayed, '09:56:00'),
            reason: '${v.at}',
          );
        }
        expect(s.stalledAt, isEmpty);
        s.dispose();
      });
    });
  });
}

/// 上市規模（spec「驗證」2）
const _stockCount = heatmapFixtureStockCount;

/// 正式資料是上週五；預設 13:31（週一收盤後）開始
final _start = DateTime(2026, 11, 9, 13, 31);

/// 週一盤中（「資料時間」那幾條的起點）
final _morning = DateTime(2026, 11, 9, 10, 0);

/// 整個市場，市值由大到小
final _byCap = heatmapFixtureByCap;

/// 圖上的檔（市值最大的那幾檔），由大到小
final _tiles = heatmapFixtureTiles;

/// 圖上的檔加一個指數，一輪分成幾個請求（分批無條件進位，同報價中心）
const _perRound =
    (HeatmapParams.topTileCount + 1 + ApiEndpoints.misBatchSize - 1) ~/
    ApiEndpoints.misBatchSize;

Set<String> _coloredOf(HeatmapLiveView view) => {
  for (final tile in view.data!.tiles)
    if (tile.change is TileChangeValue) tile.symbol,
};

TileChange _changeOf(HeatmapLiveView view, String symbol) =>
    view.data!.tiles.firstWhere((t) => t.symbol == symbol).change;

/// [symbols] 都以收盤報價上色：(101 − 100) ÷ 100 = +1%
void _expectClosingColor(HeatmapLiveView view, Set<String> symbols) {
  for (final symbol in symbols) {
    expect(
      _changeOf(view, symbol),
      isA<TileChangeValue>().having(
        (c) => c.percent,
        'percent',
        closeTo(1, 1e-9),
      ),
      reason: symbol,
    );
  }
}

class _Clock implements AppClock {
  _Clock(this._now);
  final DateTime Function() _now;

  @override
  DateTime now() => _now();
}

/// 大盤總覽沒有資料:指數一律還沒有今天的正式資料
class _EmptyOverview extends MarketOverviewNotifier {
  @override
  MarketOverviewState build() => const MarketOverviewState();

  @override
  Future<void> loadData() async {}
}

class _FixedHeatmap extends MarketHeatmapNotifier {
  @override
  MarketHeatmapState build() => MarketHeatmapState(
    isLoading: false,
    markets: {MarketCode.twse: heatmapFixtureTwse()},
  );
}

/// 沒有任何 override 的容器裡，正式的 `liveQuoteClientProvider` 建出的 Dio
/// 逾時
({Duration? connect, Duration? receive}) _productionClientTimeouts() {
  final container = ProviderContainer();
  try {
    final options = container.read(liveQuoteClientProvider).dio.options;
    return (connect: options.connectTimeout, receive: options.receiveTimeout);
  } finally {
    container.dispose();
  }
}

/// 開著的熱力圖頁＋真的報價中心（在 fakeAsync 裡建立）
class _Session {
  _Session(
    this.async, {
    DateTime? start,
    this.noTrade = const {},
    this.unmatched = const {},
    bool? collectAfterCloseWhenHidden,
  }) : start = start ?? _start {
    container = ProviderContainer(
      overrides: [
        // App 看不見時收不收收盤報價;不給就用正式的(由目標平台決定)
        if (collectAfterCloseWhenHidden != null)
          liveQuoteCenterProvider.overrideWith(
            () => LiveQuoteCenter(
              collectAfterCloseWhenHidden: collectAfterCloseWhenHidden,
            ),
          ),
        appClockProvider.overrideWithValue(_Clock(now)),
        // 與正式的 liveQuoteClientProvider 用相同的 createDio 參數（含逾時，
        // 與正式 client 的逾時相同由慢回應那條測試對照），只換 adapter
        liveQuoteClientProvider.overrideWithValue(
          IntradayQuoteClient(
            dio: MarketClientMixin.createDio(
              ApiEndpoints.twseMisIntraday,
              connectTimeout: LiveQuoteParams.connectTimeout,
              receiveTimeout: LiveQuoteParams.receiveTimeout,
            )..httpClientAdapter = _MisAdapter(_serve),
            logBatchErrors: false,
          ),
        ),
        marketHeatmapProvider.overrideWith(_FixedHeatmap.new),
        marketOverviewProvider.overrideWith(_EmptyOverview.new),
      ],
    );
    // 直接聽報價中心：每一次發布的 stalled 都記，不只熱力圖結果有變的那幾次
    _center = container.listen(liveQuoteCenterProvider, (_, next) {
      if (next.stalled) stalledAt.add(now());
    });
    openView();
  }

  final FakeAsync async;

  /// 時鐘起點
  final DateTime start;

  /// 整天沒成交的代號：MIS 有回應，但沒有成交價、試撮價與五檔（解析時整列
  /// 丟掉）
  final Set<String> noTrade;

  /// 收盤那一盤沒撮合的代號：MIS 回 13:30:00 的列，但沒有成交價，只有五檔
  /// （代號數字是 5 的倍數的另帶試撮價）
  final Set<String> unmatched;
  late final ProviderContainer container;
  ProviderSubscription<HeatmapLiveView>? _view;
  ProviderSubscription<List<LiveQuoteRegistration>>? _registrations;
  late final ProviderSubscription<LiveQuoteState> _center;

  /// 報價中心發布 `stalled == true` 的時刻
  final stalledAt = <DateTime>[];

  /// 每個請求：送出時刻與代號（依 ex_ch 順序）
  final requests = <({DateTime at, List<String> symbols})>[];

  /// 第 [index] 個請求（0 起算）的回應；預設 [normal]
  late Future<String> Function(int index, List<String> symbols, DateTime now)
  respond = (_, symbols, now) => normal(symbols, now);

  /// heatmapLiveProvider 每次變動的結果與時刻（含開頁當下）
  final views = <({DateTime at, HeatmapLiveView view})>[];

  DateTime now() => start.add(async.elapsed);
  LiveQuoteCenter get center =>
      container.read(liveQuoteCenterProvider.notifier);
  LiveQuoteState get centerState => container.read(liveQuoteCenterProvider);
  HeatmapLiveView get view => _view!.read();

  /// 進入熱力圖頁:記下 `heatmapLiveProvider` 每次的結果,並照
  /// `LiveQuoteScope.listen` 聽登記清單、每次通知就登記(現值先登記一次)
  void openView() {
    _view = container.listen(
      heatmapLiveProvider,
      (_, next) => views.add((at: now(), view: next)),
      fireImmediately: true,
    );
    _registrations = container.listen(
      heatmapRegistrationsProvider,
      (_, next) => center.register(this, next),
      fireImmediately: true,
    );
  }

  /// 離開熱力圖頁:照 `LiveQuoteScope` 關掉訂閱、取消登記;兩個 provider
  /// 沒人聽,下一個事件迴圈就釋放(再進入時是新的)
  void closeView() {
    _registrations?.close();
    _registrations = null;
    _view?.close();
    _view = null;
    center.unregister(this);
  }

  /// 請求過的個股依序攤平（不含指數）
  List<String> get requestedStocks => stocksExcept(const {});

  /// 同 [requestedStocks]，略過第 [skipped] 個請求（0 起算）
  List<String> stocksExcept(Set<int> skipped) => [
    for (final (i, r) in requests.indexed)
      if (!skipped.contains(i))
        for (final s in r.symbols)
          if (s != LiveQuoteParams.twseIndexSymbol) s,
  ];

  /// 收盤後進度第一次到 [done] 檔的時刻
  DateTime? filledAt(int done) {
    for (final (:at, :view) in views) {
      if (view.closing?.done == done) return at;
    }
    return null;
  }

  /// 每檔都回收盤報價（13:30:00 的成交）；整天沒成交的回一列解析時會丟掉的；
  /// 收盤沒撮合的回沒有成交價、只有五檔（或試撮價）的列
  Future<String> normal(List<String> symbols, DateTime now) async =>
      heatmapFixtureClosingResponse(
        symbols,
        now,
        noTrade: noTrade,
        unmatched: unmatched,
      );

  /// 一份快照的回應:每檔都是 [price] 的成交,快照時刻是 [at];各列的時間預設
  /// 也是 [at],[rowAt] 可以逐檔指定
  String snapshot(
    List<String> symbols,
    DateTime at, {
    required double price,
    DateTime Function(String symbol)? rowAt,
  }) => jsonEncode({
    'rtcode': '0000',
    'queryTime': {'sysDate': _ymd(at), 'sysTime': _hms(at)},
    'msgArray': [
      for (final s in symbols)
        {
          'c': s,
          'z': price.toStringAsFixed(4),
          'pz': '-',
          'y': '100.0000',
          'd': _ymd(at),
          't': _hms(rowAt?.call(s) ?? at),
          'b': '-',
          'a': '-',
        },
    ],
  });

  void elapse(Duration d) => async.elapse(d);

  /// 每次前進 1 秒，直到 [done] 成立；[limit] 內沒成立就失敗
  void elapseUntil(
    bool Function() done, {
    Duration limit = const Duration(minutes: 10),
  }) {
    final end = async.elapsed + limit;
    while (!done()) {
      if (async.elapsed >= end) fail('$limit 內沒有發生');
      async.elapse(const Duration(seconds: 1));
    }
  }

  void dispose() {
    _center.close();
    container.dispose();
  }

  Future<String> _serve(List<String> exCh) {
    final symbols = [for (final e in exCh) e.substring(4, e.length - 3)];
    final index = requests.length;
    requests.add((at: now(), symbols: symbols));
    return respond(index, symbols, now());
  }
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
    var body = serve(exCh);
    // 同 IOHttpClientAdapter：等回應超過 receiveTimeout 就放棄這個請求
    final timeout = options.receiveTimeout ?? Duration.zero;
    if (timeout > Duration.zero) {
      body = body.timeout(
        timeout,
        onTimeout: () => throw DioException.receiveTimeout(
          timeout: timeout,
          requestOptions: options,
        ),
      );
    }
    return ResponseBody.fromString(
      await body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _two(int v) => v.toString().padLeft(2, '0');
String _ymd(DateTime t) => '${t.year}${_two(t.month)}${_two(t.day)}';
String _hms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

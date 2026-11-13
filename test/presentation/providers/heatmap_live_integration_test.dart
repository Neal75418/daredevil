import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 熱力圖收盤後滾動登記 × 真的報價中心（spec「驗證」2）。
///
/// 真的 `LiveQuoteCenter` 接真的 `IntradayQuoteClient`（假 HTTP adapter）、
/// 隨 fakeAsync 前進的時鐘；熱力圖讀固定的正式資料（上市 1,078 檔，上一個
/// 交易日），結果變動時照 `LiveQuoteScope` 的做法向中心重新登記（目前市場的
/// 指數＋`view.stockRegistrations`）。請求、時刻、進度都量在 HTTP 與
/// `heatmapLiveProvider` 兩端。
void main() {
  late List<Object> captured;

  setUp(() {
    captured = [];
    AppLogger.setSentryDelegates(
      capture: (error, stackTrace, tag, message) => captured.add(error),
    );
  });
  tearDown(() => AppLogger.setSentryDelegates());

  test('前提：虛構代號各不相同；市值前 69 與代號排序的前 69 不同', () {
    expect(_byCap.toSet(), hasLength(_stockCount));
    final bySymbol = [..._byCap]..sort();
    expect(
      bySymbol.take(HeatmapParams.liveTileLimit).toSet(),
      isNot(_byCap.take(HeatmapParams.liveTileLimit).toSet()),
    );
  });

  test('🚨 每檔都回收盤報價 → 4 分 30 秒內整張圖收齊；第一輪是市值前 69、大格子先、每檔只抓一次', () {
    fakeAsync((async) {
      final s = _Session(async);
      s.elapse(const Duration(seconds: 5)); // 第一輪：第 1、4 秒兩批
      final top = _byCap.take(HeatmapParams.liveTileLimit).toSet();
      expect(s.requests, hasLength(2));
      expect(
        {for (final r in s.requests) ...r.symbols},
        {LiveQuoteParams.twseIndexSymbol, ...top},
      );
      expect(s.view.closing, (
        done: HeatmapParams.liveTileLimit,
        unmatched: 0,
        total: _stockCount,
      ));
      expect(_coloredOf(s.view), top, reason: '第一輪拿到的是市值前 69');

      s.elapse(const Duration(minutes: 10));
      final filled = s.filledAt(_stockCount);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(s.start.add(const Duration(minutes: 4, seconds: 30))),
        isFalse,
        reason: '收齊於 $filled',
      );
      expect(s.requestedStocks, _byCap, reason: '依市值由大到小，每檔恰好一次');
      expect(s.requests.last.at.isAfter(filled), isFalse, reason: '收齊後不再發請求');
      expect(_coloredOf(s.view), _byCap.toSet());
      _expectClosingColor(s.view, _byCap.toSet());
      expect([
        for (final v in s.views) v.view.quoteStatus,
      ], everyElement(isNull));
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 20 檔整天沒成交 → 各被請求恰好 10 次後不再請求；其餘 1,058 檔 6 分鐘內收齊，'
      '最近一輪只問它們（沒有今天的報價）時不退回正式資料', () {
    final noTrade = {for (var k = 0; k < 20; k++) _byCap[10 + 54 * k]};
    expect(
      noTrade.where(_byCap.take(HeatmapParams.liveTileLimit).contains),
      isNotEmpty,
      reason: '前提：有幾檔一開始就在前 69 檔、一直佔著登記名額',
    );
    fakeAsync((async) {
      final s = _Session(async, noTrade: noTrade);
      s.elapse(const Duration(minutes: 25));

      final traded = _stockCount - noTrade.length;
      final filled = s.filledAt(traded);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(s.start.add(const Duration(minutes: 6))),
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
        total: _stockCount,
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
      final tradedSymbols = _byCap.toSet().difference(noTrade);
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

  test('🚨 100 檔收盤那一盤沒撮合（多於登記上限 69）→ 各被請求恰好 10 次後讓出登記名額；'
      '其餘 978 檔 25 分鐘內收齊；格子寫收盤沒撮合、進度另計檔數', () {
    // 市值名次 3、13、…、993：散在市值各處，前 69 檔裡有 7 檔
    final unmatched = {for (var k = 0; k < 100; k++) _byCap[3 + 10 * k]};
    expect(unmatched, hasLength(greaterThan(HeatmapParams.liveTileLimit)));
    expect(
      unmatched.where(_byCap.take(HeatmapParams.liveTileLimit).contains),
      isNotEmpty,
      reason: '前提：有幾檔一開始就在前 69 檔',
    );
    fakeAsync((async) {
      final s = _Session(async, unmatched: unmatched);
      s.elapse(const Duration(minutes: 40));

      final matched = _stockCount - unmatched.length;
      final filled = s.filledAt(matched);
      expect(
        filled,
        isNotNull,
        reason: '其餘各檔要全部拿到收盤報價（最後的進度 ${s.view.closing}）',
      );
      expect(
        filled!.isAfter(s.start.add(const Duration(minutes: 25))),
        isFalse,
        reason: '收齊於 $filled',
      );
      for (final symbol in unmatched) {
        expect(
          s.requests.where((r) => r.symbols.contains(symbol)),
          hasLength(LiveQuoteParams.afterCloseMaxAttempts),
          reason: symbol,
        );
      }
      expect(
        s.requestedStocks.where((symbol) => !unmatched.contains(symbol)),
        [
          for (final symbol in _byCap)
            if (!unmatched.contains(symbol)) symbol,
        ],
        reason: '其餘依市值由大到小，每檔恰好一次',
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
        total: _stockCount,
      ));
      expect(view.stockRegistrations, isEmpty, reason: '放棄的代號不再占登記名額');
      final matchedSymbols = _byCap.toSet().difference(unmatched);
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
    // 市值最小的 20 檔整天沒成交：其餘收齊後只剩它們每分鐘重抓一次
    final noTrade = _byCap.skip(_stockCount - 20).toSet();
    fakeAsync((async) {
      // 13:30:15 開始：其餘 1,058 檔約 13:34:07 收齊，它們下一次重抓落在
      // 13:35:00 的 CLI 避讓窗口
      final s = _Session(
        async,
        start: DateTime(2026, 11, 9, 13, 30, 15),
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
        done: _stockCount - noTrade.length,
        unmatched: noTrade.length,
        total: _stockCount,
      ));
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 一輪回應慢 7 秒（未逾時）、回來時落在 CLI 避讓窗口 → 全程不報「報價暫停」，'
      '6 分鐘內收齊', () {
    fakeAsync((async) {
      final window = DateTime(2026, 11, 9, 13, 35);
      final windowEnd = window.add(LiveQuoteParams.cliAvoidWindow);
      const delay = Duration(seconds: 7);
      expect(delay, lessThan(LiveQuoteParams.receiveTimeout), reason: '前提：未逾時');
      DateTime? delayedAt;
      // 13:31:05 開始：最後一輪在窗口前幾秒送出
      final s = _Session(async, start: DateTime(2026, 11, 9, 13, 31, 5));
      s.respond = (_, symbols, now) {
        // 窗口前 15 秒內送出的第一個請求慢 7 秒
        if (delayedAt == null &&
            now.isBefore(window) &&
            !now.isBefore(window.subtract(LiveQuoteParams.pollInterval))) {
          delayedAt = now;
          return Future.delayed(delay, () => s.normal(symbols, now));
        }
        return s.normal(symbols, now);
      };
      s.elapse(const Duration(minutes: 10));

      final slow = delayedAt;
      expect(slow, isNotNull, reason: '前提：窗口前有一輪還在抓');
      final back = slow!.add(delay);
      expect(
        !back.isBefore(window) && back.isBefore(windowEnd),
        isTrue,
        reason: '前提：慢的回應在窗口內回來（$back），同一輪剩下的批次要等窗口過去',
      );
      expect(
        s.requests.where((r) => r.at.isAfter(slow) && r.at.isBefore(back)),
        isEmpty,
        reason: '慢的那一批回來前不發下一批',
      );
      expect(
        s.requests.where(
          (r) => !r.at.isBefore(window) && r.at.isBefore(windowEnd),
        ),
        isEmpty,
        reason: 'CLI 避讓窗口內不發請求',
      );
      final filled = s.filledAt(_stockCount);
      expect(filled, isNotNull);
      expect(
        filled!.isBefore(windowEnd),
        isFalse,
        reason: '前提：收齊前跨過窗口（收齊於 $filled）',
      );
      expect(
        filled.isAfter(s.start.add(const Duration(minutes: 6))),
        isFalse,
        reason: '收齊於 $filled',
      );
      expect(s.stalledAt, isEmpty, reason: '報價中心不判暫停');
      expect(
        [for (final v in s.views) v.view.quoteStatus],
        everyElement(isNull),
        reason: '不報「報價暫停」',
      );
      expect(s.requestedStocks, _byCap, reason: '慢的那一輪照常套用，沒有重抓');
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 一批回應超過 receiveTimeout → 那一批失敗、那幾檔 1 分鐘後恰好重抓一次；'
      '全程不報「報價暫停」，6 分鐘內收齊', () {
    fakeAsync((async) {
      const slowRequest = 8; // 第 5 輪的第 1 批
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
      s.respond = (i, symbols, now) => i == slowRequest
          ? Future.delayed(delay, () => s.normal(symbols, now))
          : s.normal(symbols, now);
      s.elapse(const Duration(minutes: 10));

      final timedOut = s.requests[slowRequest];
      final retries = [
        for (final (i, r) in s.requests.indexed)
          if (i > slowRequest && r.symbols.any(timedOut.symbols.contains)) r,
      ];
      expect(retries, hasLength(1), reason: '逾時的那一批只重抓一次');
      final retry = retries.single;
      expect(retry.symbols, containsAll(timedOut.symbols));
      expect(
        retry.at.difference(timedOut.at),
        greaterThanOrEqualTo(
          LiveQuoteParams.receiveTimeout +
              LiveQuoteParams.afterCloseRetryInterval,
        ),
        reason: '逾時之後滿 1 分鐘才重抓（${retry.at}）',
      );
      expect(
        s.requests.where(
          (r) => r.at.isAfter(timedOut.at) && r.at.isBefore(retry.at),
        ),
        isNotEmpty,
        reason: '等重抓的期間照常滾動',
      );
      final counts = <String, int>{};
      for (final symbol in s.requestedStocks) {
        counts[symbol] = (counts[symbol] ?? 0) + 1;
      }
      expect(counts, {
        for (final symbol in _byCap)
          symbol: timedOut.symbols.contains(symbol) ? 2 : 1,
      }, reason: '只有逾時的那一批多抓一次');
      final filled = s.filledAt(_stockCount);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(s.start.add(const Duration(minutes: 6))),
        isFalse,
        reason: '收齊於 $filled',
      );
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

  test('🚨 一輪送到一半被限流 → 只損失那一輪；rateLimitedUntil 過後從還沒拿到的繼續、'
      '再 5 分鐘內收齊', () {
    fakeAsync((async) {
      const limited = 9; // 第 5 輪的第 2 批
      final s = _Session(async);
      s.respond = (i, symbols, now) => i == limited
          ? Future.value(_rateLimitedPage)
          : s.normal(symbols, now);
      s.elapseUntil(() => s.requests.length > limited);
      final limitedAt = s.requests[limited].at;
      final until = s.centerState.rateLimitedUntil;
      expect(until, limitedAt.add(LiveQuoteParams.rateLimitPause));
      final doneBefore = s.view.closing!.done;
      expect(doneBefore, 4 * HeatmapParams.liveTileLimit, reason: '前 4 輪都收到');
      expect(s.view.quoteStatus?.kind, LiveHeaderKind.pausedRateLimit);

      s.elapse(const Duration(minutes: 15));
      final resumed = s.requests[limited + 1];
      expect(resumed.at.isBefore(until!), isFalse, reason: '暫停期間不發請求');
      expect(
        resumed.at.difference(until),
        lessThanOrEqualTo(LiveQuoteParams.tick),
        reason: '時間一到就試探',
      );
      expect(
        resumed.symbols,
        s.requests[limited - 1].symbols,
        reason: '試探從作廢那一輪的第 1 批開始',
      );
      // 全程只有暫停期間顯示限流（不會出現 pausedNetwork）；暫停期間進度不動
      for (final (:at, :view) in s.views) {
        if (at.isBefore(limitedAt) || !at.isBefore(until)) {
          expect(view.quoteStatus, isNull, reason: '$at：試探成功後不再顯示限流');
        } else {
          expect(view.quoteStatus?.kind, LiveHeaderKind.pausedRateLimit);
          expect(view.closing!.done, doneBefore, reason: '$at：作廢那一輪不套用');
        }
      }
      expect(s.stalledAt, isEmpty, reason: '限流暫停期間不判網路暫停');
      final filled = s.filledAt(_stockCount);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(until.add(const Duration(minutes: 5))),
        isFalse,
        reason: '收齊於 $filled',
      );
      expect(
        s.stocksExcept({limited - 1, limited}),
        _byCap,
        reason: '只重抓作廢的那一輪，其餘依市值各抓一次',
      );
      expect(captured, isEmpty);
      s.dispose();
    });
  });

  test('🚨 一輪送到一半 App 不可見一輪 → 只損失那一輪；回到可見後繼續，6 分鐘內收齊', () {
    fakeAsync((async) {
      const sentBeforeHiding = 9; // 第 5 輪的第 1 批
      final s = _Session(async);
      s.elapseUntil(() => s.requests.length == sentBeforeHiding);
      s.elapse(const Duration(seconds: 1)); // 第 1 批已回來，第 2 批還沒送
      final doneBefore = s.view.closing!.done;
      expect(doneBefore, 4 * HeatmapParams.liveTileLimit, reason: '前 4 輪都收到');

      s.center.setAppVisible(false);
      s.elapse(LiveQuoteParams.pollInterval);
      expect(s.requests, hasLength(sentBeforeHiding), reason: '不可見時不發請求');
      expect(s.view.closing!.done, doneBefore, reason: '送到一半的那一輪作廢、不套用');

      s.center.setAppVisible(true);
      final shownAt = s.now();
      s.elapse(const Duration(minutes: 10));
      final resumed = s.requests[sentBeforeHiding];
      expect(
        resumed.at.difference(shownAt),
        lessThanOrEqualTo(LiveQuoteParams.tick),
        reason: '回到可見後下一拍就繼續',
      );
      expect(
        resumed.symbols,
        s.requests[sentBeforeHiding - 1].symbols,
        reason: '從作廢那一輪的第 1 批重抓',
      );
      final filled = s.filledAt(_stockCount);
      expect(filled, isNotNull);
      expect(
        filled!.isAfter(s.start.add(const Duration(minutes: 6))),
        isFalse,
        reason: '收齊於 $filled',
      );
      expect(
        s.stocksExcept({sentBeforeHiding - 1}),
        _byCap,
        reason: '只重抓作廢的那一批，其餘依市值各抓一次',
      );
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
        expect(served, hasLength(2), reason: '69 檔＋指數兩批');
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
        expect(s.centerState.entries, hasLength(70));
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
        expect(stocks, hasLength(HeatmapParams.liveTileLimit));
        // 第 1 輪 10:00:13 換上，之後三輪（到 10:00:58）都被擋下
        expect(s.requests, hasLength(8));
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
        // 另一個畫面登記一檔不在熱力圖裡的股票:它每次都拿到當下的快照;
        // 熱力圖那兩批的快取還沒換新,一直是 09:59:30 那一份
        const other = 'OTHER';
        final cached = DateTime(2026, 11, 9, 9, 59, 30);
        s.respond = (_, symbols, now) async => s.snapshot(
          symbols,
          symbols.contains(other) ? now : cached,
          price: 101,
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
        // 10:00:00～09 讓給 CLI，第 1 輪兩批在 10:00:10、10:00:13
        expect(withStatus.first.at, DateTime(2026, 11, 9, 10, 0, 13));
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

/// 證交所限流時回的 HTML（client 判為限流）
const _rateLimitedPage = '<!doctype html><html>Too many requests</html>';

/// 上市規模（spec「驗證」2）
const _stockCount = 1078;

/// 正式資料是上週五；預設 13:31（週一收盤後）開始
final _friday = DateTime(2026, 11, 6);
final _start = DateTime(2026, 11, 9, 13, 31);

/// 週一盤中（「資料時間」那幾條的起點）
final _morning = DateTime(2026, 11, 9, 10, 0);

/// 市值第 [rank] 大（0 起算）的虛構代號。代號順序與市值順序刻意不同
/// （397 與 1,078 互質，乘上去取餘數是一對一）
String _symbolAt(int rank) =>
    'Z${((rank * 397) % _stockCount + 1).toString().padLeft(4, '0')}';

/// 市值由大到小
final _byCap = [for (var r = 0; r < _stockCount; r++) _symbolAt(r)];

/// 正式資料：收盤 100、漲跌 −0.8%；市值依名次遞減，名次輪流分到 8 個產業
HeatmapMarketData _twse() {
  const industryCount = 8;
  final members = [for (var k = 0; k < industryCount; k++) <HeatmapTile>[]];
  for (var r = 0; r < _stockCount; r++) {
    final cap = (_stockCount - r) * 1e9;
    members[r % industryCount].add(
      HeatmapTile(
        symbol: _byCap[r],
        name: '虛構${_byCap[r]}',
        close: 100,
        marketCap: cap,
        baseCap: cap * 100 / 99.2,
        change: const TileChangeValue(-0.8),
        isMine: false,
      ),
    );
  }
  final industries = [
    for (var k = 0; k < industryCount; k++)
      HeatmapIndustry(
        name: '虛構產業$k',
        marketCap: members[k].fold(0.0, (a, t) => a + t.marketCap),
        weightedChangePercent: -0.8,
        tiles: members[k],
      ),
  ]..sort((a, b) => b.marketCap.compareTo(a.marketCap));
  return HeatmapMarketData(
    market: MarketCode.twse,
    dataDate: _friday,
    industries: industries,
    excludedForShares: 0,
  );
}

Set<String> _coloredOf(HeatmapLiveView view) => {
  for (final industry in view.data!.industries)
    for (final tile in industry.tiles)
      if (tile.change is TileChangeValue) tile.symbol,
};

TileChange _changeOf(HeatmapLiveView view, String symbol) => view
    .data!
    .industries
    .expand((i) => i.tiles)
    .firstWhere((t) => t.symbol == symbol)
    .change;

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

class _FixedHeatmap extends MarketHeatmapNotifier {
  @override
  MarketHeatmapState build() =>
      MarketHeatmapState(isLoading: false, markets: {MarketCode.twse: _twse()});
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
  }) : start = start ?? _start {
    container = ProviderContainer(
      overrides: [
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

  List<LiveQuoteRegistration>? _registered;

  DateTime now() => start.add(async.elapsed);
  LiveQuoteCenter get center =>
      container.read(liveQuoteCenterProvider.notifier);
  LiveQuoteState get centerState => container.read(liveQuoteCenterProvider);
  HeatmapLiveView get view => _view!.read();

  /// 進入熱力圖頁:開始聽 `heatmapLiveProvider` 並登記
  void openView() => _view = container.listen(
    heatmapLiveProvider,
    (_, next) => _onView(next),
    fireImmediately: true,
  );

  /// 離開熱力圖頁:照 `LiveQuoteScope` 取消登記;`heatmapLiveProvider` 沒人聽,
  /// 下一個事件迴圈就釋放(再進入時是新的一個)
  void closeView() {
    _view?.close();
    _view = null;
    _registered = null;
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
      jsonEncode({
        'rtcode': '0000',
        'msgArray': [
          for (final s in symbols)
            {
              'c': s,
              'z': noTrade.contains(s) || unmatched.contains(s)
                  ? '-'
                  : '101.0000',
              'pz': unmatched.contains(s) && int.parse(s.substring(1)) % 5 == 0
                  ? '100.5000'
                  : '-',
              'y': '100.0000',
              'd': _ymd(now),
              't': '13:30:00',
              'b': unmatched.contains(s) ? '100.0000_' : '-',
              'a': unmatched.contains(s) ? '101.0000_' : '-',
            },
        ],
      });

  /// 一份快照的回應:每檔都是 [price] 的成交,快照時刻與各列的時間都是 [at]
  String snapshot(List<String> symbols, DateTime at, {required double price}) =>
      jsonEncode({
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
              't': _hms(at),
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

  /// 照 `LiveQuoteScope`：登記清單變了才重新登記（只登記目前市場的指數）
  void _onView(HeatmapLiveView view) {
    views.add((at: now(), view: view));
    final market = container.read(heatmapSelectionProvider).market;
    final registrations = [
      for (final r in marketIndexRegistrations(
        const MarketOverviewState(),
        now(),
      ))
        if (r.market == market) r,
      ...view.stockRegistrations,
    ];
    if (listEquals(registrations, _registered)) return;
    _registered = registrations;
    center.register(this, registrations);
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

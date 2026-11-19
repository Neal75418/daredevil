import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/presentation/providers/app_visibility_provider.dart';
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/market/market_heatmap_screen.dart';

import '../../../helpers/heatmap_live_fixtures.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

/// 收盤後 App 看不見時，真的熱力圖頁＋真的報價中心把圖上的檔收完。
///
/// 真的 `MarketHeatmapScreen`、真的 `LiveQuoteCenter`（看不見時也收）、真的
/// `IntradayQuoteClient`（假 HTTP adapter）。App 看不見時 Flutter 不畫幀：
/// 這裡確認整段在背景完成，不靠任何一幀。
void main() {
  setUpAll(() async => setupTestLocalization());

  testWidgets('🚨 13:25 起 App 看不見、熱力圖頁開著：收盤後在背景把圖上的 30 檔收完'
      '（3 檔收盤沒撮合，每分鐘重試到放棄），看不見期間不畫任何一幀', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tiles = heatmapFixtureTiles;
    final unmatched = heatmapFixtureUnmatched3();
    final matched = tiles.length - unmatched.length;
    // 沒撮合的每分鐘重試一次、滿 10 次（約 13:40）放棄；留 5 分鐘餘裕
    final deadline = DateTime(2026, 11, 9, 13, 45);

    // 時鐘＝起點＋測試推進的時間（每次 pump 之前先加）
    final start = DateTime(2026, 11, 9, 13, 25);
    var elapsed = Duration.zero;
    DateTime now() => start.add(elapsed);

    final requests = <({DateTime at, List<String> symbols})>[];
    Future<String> serve(List<String> exCh) async {
      final symbols = [for (final e in exCh) e.substring(4, e.length - 3)];
      requests.add((at: now(), symbols: symbols));
      return heatmapFixtureClosingResponse(
        symbols,
        now(),
        unmatched: unmatched,
      );
    }

    var frames = 0;
    SchedulerBinding.instance.addPersistentFrameCallback((_) => frames++);

    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketHeatmapScreen(),
        overrides: [
          marketHeatmapProvider.overrideWith(_FixedHeatmap.new),
          marketOverviewProvider.overrideWith(_FixedOverview.new),
          marketLiveIndicesProvider.overrideWithValue(
            const MarketLiveIndices(),
          ),
          appClockProvider.overrideWithValue(_Clock(now)),
          liveQuoteClientProvider.overrideWithValue(
            IntradayQuoteClient(
              dio: Dio()..httpClientAdapter = _MisAdapter(serve),
              logBatchErrors: false,
            ),
          ),
        ],
        zhTranslations: true,
        liveQuoteCenter: () =>
            LiveQuoteCenter(collectAfterCloseWhenHidden: true),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarketHeatmapScreen)),
    );
    final center = container.read(liveQuoteCenterProvider.notifier);
    expect(center.registeredMarkets.keys.toSet(), {
      LiveQuoteParams.twseIndexSymbol,
      ...tiles,
    }, reason: '前提：盤中登記指數＋圖上的 30 檔');

    // App 看不見：照 main.dart 的接線通知報價中心與可見性 provider，並讓
    // Flutter 停止排程畫面
    void setVisible(bool visible) {
      tester.binding.handleAppLifecycleStateChanged(
        visible ? AppLifecycleState.resumed : AppLifecycleState.hidden,
      );
      center.setAppVisible(visible);
      container.read(appVisibilityProvider.notifier).set(visible);
    }

    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    setVisible(false);
    await tester.pump(); // 切到 hidden 之前已經排好的那一幀
    final framesWhenHidden = frames;
    expect(framesWhenHidden, greaterThan(0), reason: '前提：看得見時幀數有在數');
    expect(tester.binding.framesEnabled, isFalse, reason: '前提：看不見時不畫幀');

    // 逐秒前進（看不見時不畫幀，計時器照跑），直到報價中心都收完或超過上限；
    // 途中記下「有撮合的都拿到收盤報價」的時刻
    int closingQuotes() => container
        .read(liveQuoteCenterProvider)
        .entries
        .values
        .where((e) => e.isClosingQuote)
        .length;
    bool collected() =>
        closingQuotes() >= matched + 1 &&
        container.read(liveQuoteCenterProvider).closingGivenUpAt.length >=
            unmatched.length;

    DateTime? matchedAt;
    while (!collected() && now().isBefore(deadline)) {
      elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
      if (matchedAt == null && closingQuotes() >= matched + 1) {
        matchedAt = now();
      }
    }
    final finishedAt = now();
    // 收完之後繼續走到上限：不再送請求、仍然不畫幀
    final requestsWhenFinished = requests.length;
    while (now().isBefore(deadline)) {
      elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      requests,
      hasLength(requestsWhenFinished),
      reason: '$finishedAt 收完之後到 $deadline 都不再送請求',
    );
    expect(frames, framesWhenHidden, reason: '前提：看不見期間沒有畫任何一幀');
    expect(
      requests.where((r) => r.at.isBefore(DateTime(2026, 11, 9, 13, 30))),
      isEmpty,
      reason: '看不見時盤中不抓',
    );
    expect(matchedAt, isNotNull);
    expect(
      matchedAt!.isBefore(DateTime(2026, 11, 9, 13, 31)),
      isTrue,
      reason: '有撮合的 $matched 檔第一輪就收到（$matchedAt）',
    );

    final view = container.read(heatmapLiveProvider);
    expect(view.closing, (
      done: matched,
      unmatched: unmatched.length,
      total: tiles.length,
    ), reason: '$finishedAt 時的進度（上限 $deadline）');
    expect(finishedAt.isBefore(deadline), isTrue, reason: '收完於 $finishedAt');
    for (final symbol in unmatched) {
      expect(
        requests.where((r) => r.symbols.contains(symbol)),
        hasLength(LiveQuoteParams.afterCloseMaxAttempts),
        reason: '$symbol 在背景重試到滿',
      );
    }
    expect(view.stockRegistrations, isEmpty);
    expect(center.registeredMarkets.keys, [
      LiveQuoteParams.twseIndexSymbol,
    ], reason: '個股都收完或放棄，只剩指數還登記著');
    expect(
      {for (final r in requests) ...r.symbols}
        ..remove(LiveQuoteParams.twseIndexSymbol),
      tiles.toSet(),
      reason: '只問圖上的檔，每一檔都在背景抓過',
    );

    // 切回來：第一幀就是收完的進度
    setVisible(true);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(MarketHeatmapScreen.statusLineKey)).data,
      '今日收盤 $matched／${tiles.length} 檔・'
      '${unmatched.length} 檔收盤沒撮合・待盤後更新',
    );
  });
}

class _Clock implements AppClock {
  _Clock(this._now);
  final DateTime Function() _now;

  @override
  DateTime now() => _now();
}

/// 固定的正式資料（上市 1,078 檔的市場、圖上 30 檔，上一個交易日）；不讀資料庫、
/// 不輪詢
class _FixedHeatmap extends MarketHeatmapNotifier {
  @override
  MarketHeatmapState build() => MarketHeatmapState(
    isLoading: false,
    markets: {MarketCode.twse: heatmapFixtureTwse()},
  );

  @override
  Future<void> reload() async {}

  @override
  void setVisible(bool visible) {}
}

/// 指數的正式資料也是上一個交易日
class _FixedOverview extends MarketOverviewNotifier {
  @override
  MarketOverviewState build() => MarketOverviewState(
    indices: [
      TwseMarketIndex(
        date: heatmapFixtureDataDate,
        name: MarketIndexNames.taiex,
        close: 22150.3,
        change: -61.2,
        changePercent: -0.28,
      ),
    ],
  );

  @override
  Future<void> loadData() async {}
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

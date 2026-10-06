import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_stock_item.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
import 'package:daredevil/presentation/widgets/stock_card.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/phone_layout_helpers.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeWatchlistNotifier extends WatchlistNotifier {
  WatchlistState initialState = WatchlistState();
  int loadDataCalls = 0;

  @override
  WatchlistState build() => initialState;

  @override
  Future<void> loadData() async => loadDataCalls++;

  @override
  void loadMore() {}

  @override
  void setSearchQuery(String query) {}

  @override
  void setSort(WatchlistSort sort) {}

  @override
  void setGroup(WatchlistGroup group) {}

  @override
  Future<bool> addStock(String symbol) async => true;

  @override
  Future<bool> removeStock(String symbol) async => true;

  @override
  Future<void> restoreStock(String symbol) async {}

  int resortCalls = 0;

  @override
  void resortWithLive() => resortCalls++;

  /// 模擬排序/搜尋/增刪後清單順序改變
  void reorder(List<WatchlistItemData> items) =>
      state = state.copyWith(items: items);
}

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 跟著 testWidgets 假時間走的時鐘:pump 推進多久,現在就晚多久
class _FakeTimeClock implements AppClock {
  _FakeTimeClock(this.base, this.tester) : _start = tester.binding.clock.now();
  final DateTime base;
  final WidgetTester tester;
  final DateTime _start;

  @override
  DateTime now() => base.add(tester.binding.clock.now().difference(_start));
}

/// 記錄登記、可推送新狀態的報價中心(不發請求)
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter(this.initial);
  final LiveQuoteState initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}

  void emit(LiveQuoteState s) => state = s;
}

class FakePortfolioNotifier extends PortfolioNotifier {
  PortfolioState initialState = const PortfolioState();

  @override
  PortfolioState build() => initialState;

  @override
  Future<void> loadPositions() async {}

  @override
  Future<void> deleteTransaction(int id, String symbol) async {}

  @override
  Future<void> addBuy({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    String? note,
  }) async {}

  @override
  Future<void> addSell({
    required String symbol,
    required DateTime date,
    required double quantity,
    required double price,
    double? fee,
    double? tax,
    String? note,
  }) async {}

  @override
  Future<void> addDividend({
    required String symbol,
    required DateTime date,
    required double amount,
    required bool isCash,
    String? note,
  }) async {}
}

class FakeSettingsNotifier extends SettingsNotifier {
  SettingsState initialState = const SettingsState();

  @override
  SettingsState build() => initialState;

  @override
  void setThemeMode(ThemeMode mode) {}

  @override
  void setShowROCYear(bool value) {}

  @override
  void setShowWarningBadges(bool value) {}

  @override
  void setInsiderNotifications(bool value) {}

  @override
  void setDisposalUrgentAlerts(bool value) {}

  @override
  void setLimitAlerts(bool value) {}

  @override
  void setCacheDurationMinutes(int minutes) {}

  @override
  void setAutoUpdateEnabled(bool value) {}
}

// ==========================================
// Tests
// ==========================================

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  FakeWatchlistNotifier? lastWatchlistNotifier;

  Widget buildTestWidget({
    WatchlistState? watchlistState,
    PortfolioState? portfolioState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
    Widget Function(Widget screen)? wrap,
    _LiveCenter? liveCenter,
    DateTime? now,
    AppClock? clock,
  }) {
    final watchlist = watchlistState ?? WatchlistState();
    final portfolio = portfolioState ?? const PortfolioState();
    final settings = settingsState ?? const SettingsState();
    const screen = WatchlistScreen();
    return buildProviderTestApp(
      wrap?.call(screen) ?? screen,
      overrides: [
        watchlistProvider.overrideWith(() {
          final n = FakeWatchlistNotifier();
          n.initialState = watchlist;
          return lastWatchlistNotifier = n;
        }),
        portfolioProvider.overrideWith(() {
          final n = FakePortfolioNotifier();
          n.initialState = portfolio;
          return n;
        }),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = settings;
          return n;
        }),
        if (clock != null)
          appClockProvider.overrideWithValue(clock)
        else if (now != null)
          appClockProvider.overrideWithValue(_Clock(now)),
      ],
      brightness: brightness,
      liveQuoteCenter: liveCenter == null ? null : () => liveCenter,
    );
  }

  WatchlistItemData createItem({
    required String symbol,
    String? stockName,
    double? latestClose,
    double? priceChange,
    double? score,
  }) {
    return WatchlistItemData(
      symbol: symbol,
      stockName: stockName ?? 'Stock $symbol',
      market: 'TWSE',
      latestClose: latestClose ?? 100.0,
      priceChange: priceChange ?? 1.5,
      score: score ?? 80,
      hasSignal: true,
      addedAt: DateTime(2026, 1, 1),
    );
  }

  group('WatchlistScreen', () {
    testWidgets('shows AppBar with title', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockListShimmer), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(error: 'Network error')),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty watchlist state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows search icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows sort icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('shows add icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows more_vert menu', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('shows portfolio in more menu', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Portfolio is no longer a SegmentedButton tab
      // It's accessible via the more_vert menu
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('shows stock count when items exist', (tester) async {
      widenViewport(tester);
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(items: items)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Stock list should be rendered (not empty state)
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('compare is accessible via more menu when 2+ stocks', (
      tester,
    ) async {
      widenViewport(tester);
      final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
      await tester.pumpWidget(
        buildTestWidget(watchlistState: WatchlistState(items: items)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Compare is now inside the more_vert menu, not directly visible
      expect(find.byIcon(Icons.compare_arrows), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('tapping search shows TextField', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      // Search icon changes to close
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });

  group('錯誤／空狀態在手機上（含底部導覽列）', () {
    final states = {
      '無資料': WatchlistState(),
      '一般錯誤': WatchlistState(error: 'Database error'),
      '網路錯誤': WatchlistState(error: 'Network error'),
    };

    for (final entry in states.entries) {
      for (final scenario in phoneScenarios) {
        testWidgets('${entry.key}：$scenario 不溢位、內容不被導覽列蓋住', (tester) async {
          applyPhoneScenario(tester, scenario);
          await tester.pumpWidget(
            buildTestWidget(watchlistState: entry.value, wrap: inPhoneShell),
          );
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          await expectAboveNavBar(
            tester,
            find
                .descendant(
                  of: find.byType(EmptyState),
                  matching: find.byType(Text),
                )
                .last,
          );
        });
      }

      testWidgets('${entry.key}：可下拉重新整理', (tester) async {
        applyPhoneScenario(tester, phoneScenarios.first);
        await tester.pumpWidget(
          buildTestWidget(watchlistState: entry.value, wrap: inPhoneShell),
        );
        await tester.pump(const Duration(seconds: 1));
        final before = lastWatchlistNotifier!.loadDataCalls;

        await tester.fling(find.byType(EmptyState), const Offset(0, 400), 1000);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(lastWatchlistNotifier!.loadDataCalls, greaterThan(before));
      });
    }
  });

  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);

    WatchlistItemData row({String symbol = '2330', DateTime? date}) =>
        WatchlistItemData(
          symbol: symbol,
          stockName: '測試$symbol',
          market: 'TWSE',
          latestClose: 100,
          priceChange: -1,
          priceDate: date ?? DateTime(2026, 10, 5),
          priceChangeAmount: -1.01,
          recentPrices: const [95, 96, 97, 98, 99, 100, 101, 100],
        );

    LiveQuoteEntry entry({
      double price = 101,
      DateTime? date,
      bool closing = false,
      String time = '10:14:50',
      bool lockedUp = false,
    }) => LiveQuoteEntry(
      symbol: '2330',
      date: date ?? DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: 100,
      quoteTime: time,
      isClosingQuote: closing,
      limitUp: 110,
      limitDown: 90,
      isLimitUpLocked: lockedUp,
    );

    testWidgets('🚨 登記自選的每一檔(市場別、是否已有今天正式資料)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [
              row(),
              row(symbol: '6538', date: DateTime(2026, 10, 6)),
            ],
          ),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final regs = center.registered.values.single;
      expect(regs, const [
        LiveQuoteRegistration(symbol: '2330', market: 'TWSE'),
        LiveQuoteRegistration(
          symbol: '6538',
          market: 'TWSE',
          hasOfficialToday: true,
        ),
      ]);
    });

    testWidgets('🚨 卡片顯示即時價與以昨收算的漲跌幅;走勢小圖最後一點接即時價', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 103)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('103.00'), findsOneWidget);
      expect(find.text('100.00'), findsNothing);
      // 驗傳給卡片的走勢資料(寬畫面是格狀、卡片窄,走勢小圖本身不顯示;
      // 小圖的繪製由 stock_card_test 驗)
      expect(
        tester.widget<StockCard>(find.byType(StockCard)).recentPrices!.last,
        103,
      );
    });

    testWidgets('🚨 App 開著過夜:隔天盤前不顯示昨天的即時價', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry(price: 103, closing: true, time: '13:30:00')},
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: DateTime(2026, 10, 7, 8, 30),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('100.00'), findsOneWidget);
      expect(find.text('103.00'), findsNothing);
      expect(find.textContaining('liveQuote.closingPending'), findsNothing);
    });

    testWidgets('鎖漲停 → 名稱列「漲停鎖」', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 110, lockedUp: true)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('price.limitUpLocked'), findsOneWidget);
    });

    testWidgets('批次失敗 → 卡片標「報價暫停」', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry()},
          symbolStatus: const {'2330': LiveSymbolStatus.batchFailed},
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('liveQuote.cardPaused'), findsOneWidget);
    });

    // 頁首兩種狀態分兩條:同一個測試裡換報價中心再 pump,ProviderScope
    // 不會重建已建立的 override,第二段會讀到第一段的報價中心
    testWidgets('頁首:盤中顯示本輪報價時間', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry()},
          latestResponseHadToday: true,
          latestQuoteTime: '10:14:58',
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('liveQuote.quoteTime'), findsOneWidget);
    });

    testWidgets('🚨 頁首:收盤後全是收盤報價 → 今日收盤・待盤後更新', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry(closing: true, time: '13:30:00')},
          latestResponseHadToday: true,
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: DateTime(2026, 10, 6, 14, 10),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('liveQuote.closingPending'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 頁首「報價暫停」灰字 $brightness:對實際底色 ≥ 4.5', (tester) async {
        widenViewport(tester);
        final center = _LiveCenter(
          LiveQuoteState(
            stalled: true,
            lastRespondedAt: DateTime(2026, 10, 6, 10, 13, 5),
          ),
        );
        await tester.pumpWidget(
          buildTestWidget(
            watchlistState: WatchlistState(items: [row()]),
            liveCenter: center,
            now: morning,
            brightness: brightness,
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        final text = find.textContaining('liveQuote.pausedNetwork');
        expect(text, findsOneWidget);
        final color = tester.widget<Text>(text).style!.color!;
        final background = Theme.of(
          tester.element(text),
        ).scaffoldBackgroundColor;
        expect(
          ColorContrast.ratio(color, background),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    // 自選畫面可見與否由 TickerMode 決定(切分頁、推頁返回)
    Widget Function(Widget) visibleBy(ValueNotifier<bool> visible) =>
        (screen) => ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, v, child) => TickerMode(enabled: v, child: child!),
          child: screen,
        );

    testWidgets('🚨 第一次進入:報價中心剛有回應也不算(可能是別的畫面登記的股票)→ 等第一輪再排', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          lastRespondedAt: morning.subtract(const Duration(seconds: 5)),
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(lastWatchlistNotifier!.resortCalls, 0);

      center.emit(
        LiveQuoteState(
          entries: {'2330': entry()},
          lastRespondedAt: morning.add(const Duration(seconds: 10)),
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1);
    });

    testWidgets('🚨 短暫離開(不超過一個輪詢間隔)再回來 → 用現有報價立刻重排', (tester) async {
      widenViewport(tester);
      final clock = _FakeTimeClock(morning, tester);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          clock: clock,
          wrap: visibleBy(visible),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      center.emit(
        LiveQuoteState(
          entries: {'2330': entry()},
          lastRespondedAt: clock.now(),
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1, reason: '前提:第一輪排過');

      visible.value = false;
      await tester.pump(); // 先讓「離開」那一幀生效,再推進時間
      await tester.pump(const Duration(seconds: 5));
      center.emit(
        LiveQuoteState(
          entries: {'2330': entry()},
          lastRespondedAt: clock.now(),
        ),
      );
      visible.value = true;
      await tester.pump();
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 2);
    });

    testWidgets('🚨 離開較久(例如在個股頁 3 分鐘)再回來 → 不用其他檔的舊報價立刻排,等下一輪', (tester) async {
      widenViewport(tester);
      final clock = _FakeTimeClock(morning, tester);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          clock: clock,
          wrap: visibleBy(visible),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      center.emit(
        LiveQuoteState(
          entries: {'2330': entry()},
          lastRespondedAt: clock.now(),
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1, reason: '前提:第一輪排過');

      visible.value = false;
      await tester.pump(); // 先讓「離開」那一幀生效,再推進時間
      await tester.pump(const Duration(minutes: 3));
      // 離開期間報價中心只抓個股頁那一檔:最後回應很新,這些自選股卻是舊的
      center.emit(
        LiveQuoteState(
          entries: {'2330': entry()},
          lastRespondedAt: clock.now().subtract(const Duration(seconds: 2)),
        ),
      );
      visible.value = true;
      await tester.pump();
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1, reason: '不可用舊報價立刻排');

      center.emit(
        LiveQuoteState(
          entries: {'2330': entry(price: 102)},
          lastRespondedAt: clock.now().add(const Duration(seconds: 13)),
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 2, reason: '下一輪到了才排');
    });

    testWidgets('🚨 進入時沒有夠新的報價 → 第一輪資料到了重排一次,之後不動', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(lastWatchlistNotifier!.resortCalls, 0);

      center.emit(
        LiveQuoteState(entries: {'2330': entry()}, lastRespondedAt: morning),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1);

      center.emit(
        LiveQuoteState(
          entries: {'2330': entry(price: 102)},
          lastRespondedAt: morning.add(const Duration(seconds: 15)),
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1, reason: '之後順序不動、只更新數字');
    });

    testWidgets('🚨 從自選開啟的長按預覽與卡片同價,下一輪更新後仍同價', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 101)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.longPress(find.text('101.00'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('101.00'), findsNWidgets(2), reason: '卡片＋預覽');

      center.emit(LiveQuoteState(entries: {'2330': entry(price: 102)}));
      await tester.pump();
      expect(find.text('102.00'), findsNWidgets(2));
      expect(find.text('101.00'), findsNothing);
    });

    testWidgets('🚨 設定頁關閉「價格閃色」→ 卡片收到不閃', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 101)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          settingsState: const SettingsState(priceFlash: false),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester.widget<StockCard>(find.byType(StockCard)).live!.flashEnabled,
        isFalse,
      );
    });

    testWidgets('🚨 格狀模式重排順序 → 帶著本輪閃色事件的卡片不重播閃色', (tester) async {
      widenViewport(tester);
      LiveQuoteEntry flashing(String symbol, int id) => LiveQuoteEntry(
        symbol: symbol,
        date: DateTime(2026, 10, 6),
        price: 101,
        displaySource: LiveDisplaySource.trade,
        previousClose: 100,
        quoteTime: '10:14:50',
        isClosingQuote: false,
        flash: LiveQuoteFlash(id: id, up: true),
      );
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': flashing('2330', 1), '2317': flashing('2317', 2)},
        ),
      );
      final a = row();
      final b = row(symbol: '2317');
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [a, b]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byType(WatchlistStockGridItem),
        findsNWidgets(2),
        reason: '前提:寬畫面是格狀模式',
      );

      lastWatchlistNotifier!.reorder([b, a]);
      await tester.pump();

      final tints = [
        for (final box in tester.widgetList<DecoratedBox>(
          find.byKey(PriceFlash.tintKey),
        ))
          (box.decoration as BoxDecoration).color,
      ];
      expect(tints, [null, null], reason: '同一個事件換了位置不是新的變動');
    });

    testWidgets('🚨 App 開著跨過午夜、畫面沒重建 → 登記改成還沒有今天正式資料(隔天收盤後才會去抓)', (
      tester,
    ) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      final clock = _FakeTimeClock(DateTime(2026, 10, 6, 23, 59, 30), tester);
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [row(date: DateTime(2026, 10, 6))],
          ),
          liveCenter: center,
          clock: clock,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        center.registered.values.single.single.hasOfficialToday,
        isTrue,
        reason: '前提:10/6 晚上,資料是 10/6',
      );

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(center.registered.values.single.single.hasOfficialToday, isFalse);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/stock_detail_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:daredevil/presentation/widgets/stock_nav_bar.dart';

import '../../../helpers/price_flash_helpers.dart';
import '../../../helpers/phone_layout_helpers.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifiers
// ==========================================

class FakeStockDetailNotifier extends StockDetailNotifier {
  FakeStockDetailNotifier(super.symbol);

  StockDetailState initialState = const StockDetailState();
  int loadDataCalls = 0;

  @override
  StockDetailState build() => initialState;

  @override
  Future<void> loadData() async => loadDataCalls++;

  @override
  Future<void> loadFundamentals() async {}

  @override
  Future<void> loadInsiderData() async {}

  @override
  Future<void> loadChipData() async {}

  @override
  Future<void> toggleWatchlist() async {}
}

class FakePriceAlertNotifier extends PriceAlertNotifier {
  PriceAlertState initialState = const PriceAlertState();

  @override
  PriceAlertState build() => initialState;

  @override
  Future<void> loadAlerts() async {}

  @override
  Future<void> deleteAlert(int id) async {}

  @override
  Future<void> toggleAlert(int id, bool isActive) async {}

  @override
  Future<bool> createAlert({
    required String symbol,
    required AlertType alertType,
    required double targetValue,
    String? note,
  }) async {
    return true;
  }
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

  FakeStockDetailNotifier? lastStockNotifier;

  Widget buildTestWidget({
    StockDetailState? stockState,
    PriceAlertState? alertState,
    SettingsState? settingsState,
    Brightness brightness = Brightness.light,
    List<String> browsingContext = const [],
    _LiveCenter? liveCenter,
    DateTime? now,
    AppClock? clock,
    List<Override> extraOverrides = const [],
  }) {
    final stock = stockState ?? const StockDetailState();
    final alert = alertState ?? const PriceAlertState();
    final settings = settingsState ?? const SettingsState();
    return buildProviderTestApp(
      const StockDetailScreen(symbol: '2330'),
      overrides: [
        stockDetailProvider.overrideWith2((symbol) {
          final n = FakeStockDetailNotifier(symbol);
          n.initialState = stock;
          return lastStockNotifier = n;
        }),
        priceAlertProvider.overrideWith(() {
          final n = FakePriceAlertNotifier();
          n.initialState = alert;
          return n;
        }),
        settingsProvider.overrideWith(() {
          final n = FakeSettingsNotifier();
          n.initialState = settings;
          return n;
        }),
        primaryRuleAccuracySummaryProvider.overrideWith(
          (ref, symbol) async => null,
        ),
        stockBrowsingContextProvider.overrideWith(
          () => _FixedBrowsingContext(browsingContext),
        ),
        if (clock != null)
          appClockProvider.overrideWithValue(clock)
        else if (now != null)
          appClockProvider.overrideWithValue(_Clock(now)),
        ...extraOverrides,
      ],
      brightness: brightness,
      liveQuoteCenter: liveCenter == null ? null : () => liveCenter,
    );
  }

  group('StockDetailScreen', () {
    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(
            loading: LoadingState(isLoading: true),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockDetailShimmer), findsOneWidget);
    });

    testWidgets('shows error state with retry', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(error: 'Network error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows SliverAppBar with symbol', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SliverAppBar), findsOneWidget);
      expect(find.text('2330'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows compare button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
    });

    testWidgets('shows watchlist star button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Not in watchlist → star_border
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });

    testWidgets('shows filled star when in watchlist', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(isInWatchlist: true),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('shows TabBar with 6 tabs', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(6));
    });

    testWidgets('新聞分頁在基本面與提醒之間', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      final labels = tester
          .widgetList<Tab>(find.byType(Tab))
          .map((t) => t.text)
          .toList();
      expect(labels.indexOf('stockDetail.tabNews'), 4);
      expect(labels.last, 'stockDetail.tabAlerts');
    });

    testWidgets('shows NestedScrollView when loaded', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NestedScrollView), findsOneWidget);
    });
  });

  group('已有內容時的重載（背景 epoch）', () {
    final withContent = StockPriceState(
      latestPrice: DailyPriceEntry(
        symbol: '2330',
        date: DateTime(2026, 2, 13),
        close: 600,
      ),
    );

    testWidgets('載入中仍顯示內容，不切成整頁 shimmer', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: withContent,
            loading: const LoadingState(isLoading: true),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StockDetailShimmer), findsNothing);
      expect(find.byType(NestedScrollView), findsOneWidget);
    });

    testWidgets('重載失敗：保留內容，以 banner 顯示錯誤與重試', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: withContent,
            error: 'Database error',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('Database error'), findsOneWidget);
    });

    testWidgets('只有股名（無價格）也算有內容', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: StockPriceState(
              stock: StockMasterEntry(
                symbol: '2330',
                name: '台積電',
                market: 'TWSE',
                isActive: true,
                updatedAt: DateTime(2026, 2, 13),
              ),
            ),
            error: 'Database error',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(MaterialBanner), findsOneWidget);
    });

    testWidgets('banner：重試呼叫 loadData、關閉清掉錯誤', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: StockDetailState(
            price: withContent,
            error: 'Database error',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final callsBefore = lastStockNotifier!.loadDataCalls;

      await tester.tap(find.text('common.retry'));
      await tester.pump();
      expect(lastStockNotifier!.loadDataCalls, callsBefore + 1);

      await tester.tap(find.text('common.dismiss'));
      await tester.pump();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.byType(NestedScrollView), findsOneWidget);
    });

    testWidgets('沒有內容時照舊顯示整頁錯誤，不顯示 banner', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState(error: 'Database error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
    });
  });

  group('錯誤頁在手機上（從清單進入、有巡檢導覽列）', () {
    for (final error in ['Database error', 'Network error']) {
      for (final scenario in phoneScenarios) {
        testWidgets('$error：$scenario 不溢位', (tester) async {
          applyPhoneScenario(tester, scenario);
          await tester.pumpWidget(
            buildTestWidget(
              stockState: StockDetailState(error: error),
              browsingContext: const ['2330', '2317'],
            ),
          );
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(StockNavBar), findsOneWidget, reason: '前提：導覽列有出現');
          expect(tester.takeException(), isNull);
          expect(find.text('common.retry'), findsOneWidget);
        });
      }
    }
  });

  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);
    final content = StockDetailState(
      price: StockPriceState(
        stock: StockMasterEntry(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
          isActive: true,
          updatedAt: DateTime(2026, 10, 5),
        ),
        latestPrice: DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 10, 5),
          close: 100,
          priceChange: -1,
        ),
      ),
      dataDate: DateTime(2026, 10, 5),
    );

    LiveQuoteEntry entry(String symbol, double price) => LiveQuoteEntry(
      symbol: symbol,
      date: DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: 100,
      quoteTime: '10:14:50',
      isClosingQuote: false,
    );

    testWidgets('🚨 登記這一檔(市場別、還沒有今天的正式資料)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(stockState: content, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(center.registered.values.single, const [
        LiveQuoteRegistration(symbol: '2330', market: 'TWSE'),
      ]);
    });

    testWidgets('🚨 有即時:上方顯示即時價,背景漸層方向跟著即時(資料庫是跌)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry('2330', 103)}),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: content, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('103.00'), findsOneWidget);
      // 背景是 LiveQuoteScope 底下的第一個 Container(上方區塊的漲跌膠囊
      // 也有漸層,不可用「第一個有漸層的 Container」找)
      final body = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(LiveQuoteScope),
              matching: find.byType(Container),
            )
            .first,
      );
      final gradient =
          (body.decoration! as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, AppTheme.upColor.withValues(alpha: 0.15));
    });

    testWidgets('🚨 鎖漲停 → 上方徽章「漲停鎖」(以交易所漲跌停價判斷)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {
            '2330': LiveQuoteEntry(
              symbol: '2330',
              date: DateTime(2026, 10, 6),
              price: 110,
              displaySource: LiveDisplaySource.locked,
              previousClose: 100,
              quoteTime: '10:14:50',
              isClosingQuote: false,
              limitUp: 110,
              limitDown: 90,
              isLimitUpLocked: true,
            ),
          },
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: content, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('price.limitUpLocked'), findsOneWidget);
    });

    testWidgets('🚨 上下滑換股 → 新代號帶著的閃色事件不閃(使用者沒看到那次變動)', (tester) async {
      widenViewport(tester);
      LiveQuoteEntry flashing(String symbol, double price, int id) =>
          LiveQuoteEntry(
            symbol: symbol,
            date: DateTime(2026, 10, 6),
            price: price,
            displaySource: LiveDisplaySource.trade,
            previousClose: 100,
            quoteTime: '10:14:50',
            isClosingQuote: false,
            flash: LiveQuoteFlash(id: id, up: true),
          );
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {
            '2330': flashing('2330', 103, 1),
            '2317': flashing('2317', 257, 2),
          },
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          stockState: content,
          liveCenter: center,
          now: morning,
          browsingContext: const ['2330', '2317'],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.pump();
      expect(find.text('257.00'), findsOneWidget, reason: '前提:已換到 2317');

      final tint = priceFlashTint(tester);
      expect(tint, isNull);
    });

    testWidgets('新聞分頁載入中原地換股：換股後只顯示新股票的新聞', (tester) async {
      widenViewport(tester);
      final pending2330 = Completer<StockNews>();
      NewsItemEntry n(String id) => NewsItemEntry(
        id: id,
        source: '鉅亨網',
        title: '標題$id',
        url: 'https://example.com/$id',
        category: 'OTHER',
        publishedAt: DateTime.now(),
        fetchedAt: DateTime.now(),
      );
      StockNews news(String id) => StockNews(
        items: [n(id)],
        otherStocksByNewsId: const {},
        nameStatus: StockNameStatus.matched,
      );
      await tester.pumpWidget(
        buildTestWidget(
          stockState: content,
          browsingContext: const ['2330', '2317'],
          extraOverrides: [
            stockNewsProvider.overrideWith(
              (ref, s) => s == '2330'
                  ? pending2330.future
                  : Future.value(news('2317-only')),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('stockDetail.tabNews'));
      await tester.pump(
        const Duration(seconds: 1),
      ); // 2330 仍在載入（shimmer，不可 pumpAndSettle）

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      pending2330.complete(news('2330-only'));
      await tester.pump();

      expect(find.text('標題2317-only'), findsOneWidget);
      expect(find.text('標題2330-only'), findsNothing);
    });

    testWidgets('🚨 App 開著跨過午夜、畫面沒重建 → 登記改成還沒有今天正式資料', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      final clock = _FakeTimeClock(DateTime(2026, 10, 6, 23, 59, 30), tester);
      final today = StockDetailState(
        price: StockPriceState(
          stock: content.price.stock,
          latestPrice: DailyPriceEntry(
            symbol: '2330',
            date: DateTime(2026, 10, 6),
            close: 100,
            priceChange: -1,
          ),
        ),
        dataDate: DateTime(2026, 10, 6),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: today, liveCenter: center, clock: clock),
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

    testWidgets('🚨 上下滑換股 → 登記與上方價格換到新的代號', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry('2330', 103), '2317': entry('2317', 257)},
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          stockState: content,
          liveCenter: center,
          now: morning,
          browsingContext: const ['2330', '2317'],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('103.00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        [for (final r in center.registered.values.single) r.symbol],
        ['2317'],
      );
      expect(find.text('257.00'), findsOneWidget);
      expect(find.text('103.00'), findsNothing);
    });
  });
}

class _FixedBrowsingContext extends StockBrowsingContext {
  _FixedBrowsingContext(this.symbols);

  final List<String> symbols;

  @override
  List<String> build() => symbols;
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

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
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
}

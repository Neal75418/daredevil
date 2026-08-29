import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_reading_line.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/sentiment_gauge_section.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  TwseMarketIndex createIndex(String name, double close, double change) {
    return TwseMarketIndex(
      date: DateTime(2026, 2, 13),
      name: name,
      close: close,
      change: change,
      changePercent: change / close * 100,
    );
  }

  /// TWSE + TPEx 皆有足夠資料觸發 `_computeSentiment` 的 state（兩側情緒儀表
  /// 都會渲染），供「parallel 檢視」情緒配對相關測試共用。
  MarketOverviewState parallelSentimentState() {
    return MarketOverviewState(
      indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
      advanceDeclineByMarket: {
        'TWSE': const AdvanceDecline(advance: 600, decline: 200),
        'TPEx': const AdvanceDecline(advance: 100, decline: 300),
      },
      historyTrends: HistoryTrends(
        turnover: {
          'TWSE': [
            (date: DateTime(2026, 2, 11), value: 1000.0),
            (date: DateTime(2026, 2, 12), value: 1200.0),
          ],
          'TPEx': [
            (date: DateTime(2026, 2, 11), value: 100.0),
            (date: DateTime(2026, 2, 12), value: 90.0),
          ],
        },
      ),
      dataDate: DateTime(2026, 2, 13),
    );
  }

  MarketOverviewState createLoadedState() {
    return MarketOverviewState(
      indices: [
        createIndex(MarketIndexNames.taiex, 22000, 150),
        createIndex(MarketIndexNames.electronics, 1200, 10),
      ],
      indexHistory: {
        MarketIndexNames.taiex: [21800, 21900, 22000],
      },
      advanceDeclineByMarket: {
        'TWSE': const AdvanceDecline(advance: 500, decline: 300, unchanged: 50),
        'TPEx': const AdvanceDecline(advance: 200, decline: 150, unchanged: 30),
      },
      institutionalByMarket: {
        'TWSE': const InstitutionalTotals(
          foreignNet: 5000000000,
          trustNet: 1000000000,
          dealerNet: -500000000,
          totalNet: 5500000000,
        ),
      },
      dataDate: DateTime(2026, 2, 13),
    );
  }

  group('MarketDashboard', () {
    testWidgets('shows loading indicator when isLoading', (tester) async {
      widenViewport(tester);
      const state = MarketOverviewState(isLoading: true);

      await tester.pumpWidget(
        buildTestApp(const MarketDashboard(state: state)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('returns SizedBox.shrink when no data', (tester) async {
      widenViewport(tester);
      const state = MarketOverviewState();

      await tester.pumpWidget(
        buildTestApp(const MarketDashboard(state: state)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byIcon(Icons.show_chart), findsNothing);
    });

    testWidgets('shows show_chart icon with valid data', (tester) async {
      widenViewport(tester);
      final state = createLoadedState();

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.show_chart), findsOneWidget);
    });

    testWidgets('displays date info from dataDate', (tester) async {
      widenViewport(tester);
      final state = createLoadedState();

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      // 02/13 date should appear
      expect(find.textContaining('02/13'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      widenViewport(tester);
      final state = createLoadedState();

      await tester.pumpWidget(
        buildTestApp(
          MarketDashboard(state: state),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.show_chart), findsOneWidget);
    });

    testWidgets('🚨 IntrinsicHeight 配對列:展開細項不得炸 intrinsic,列高要隨內容成長', (
      tester,
    ) async {
      // 守門對象:展開路徑不得重新引入 intrinsic-unsafe 的 widget(裸
      // LayoutBuilder 之類)。歷史:_SubScoresGrid 原用 LayoutBuilder 算
      // 三欄寬,收摺(預設)不 build 它——炸點只在展開路徑,收摺測試給過
      // 假安心(2026-08-13 實炸,每次展開丟 9 個例外)。
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(MarketDashboard(state: parallelSentimentState())),
      );
      await tester.pumpAndSettle();

      final collapsedH = tester
          .getSize(find.byType(VerticalDivider).first)
          .height;

      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '展開不得拋 intrinsic/layout 例外',
      );
      // 「分隔線=列高」在 stretch 下是套套邏輯(審查 3),改斷言成長:
      // 展開後列高必須大於收摺——分隔線跟著內容,不是跟著固定常數
      final expandedH = tester
          .getSize(find.byType(VerticalDivider).first)
          .height;
      expect(
        expandedH,
        greaterThan(collapsedH + 10),
        reason: '展開子指標後配對列要長高;不長=有人又釘死了高度',
      );
    });

    testWidgets('🚨 情緒配對列:分隔線高度=卡片實際高度,收摺不再殘留 50px(2026-08-13)', (
      tester,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(MarketDashboard(state: parallelSentimentState())),
      );
      await tester.pumpAndSettle();

      final gaugeHeights = tester
          .widgetList(find.byType(SentimentGaugeSection))
          .map((w) => tester.getSize(find.byWidget(w)).height)
          .toList();
      expect(gaugeHeights, isNotEmpty, reason: '前提:並排情緒卡有渲染');

      final dividerH = tester
          .getSize(find.byType(VerticalDivider).first)
          .height;
      final maxCard = gaugeHeights.reduce((a, b) => a > b ? a : b);

      expect(
        dividerH,
        closeTo(maxCard, 1.0),
        reason:
            '分隔線應隨 IntrinsicHeight 貼齊卡片;'
            '原固定 222px 在收摺(預設,實測 172px)時每次白吃 50px 垂直空間',
      );
      expect(dividerH, lessThan(200), reason: '收摺狀態的配對列不得回到 222px 時代');
    });

    testWidgets('指數平盤 + 廣度明顯偏向下跌時，市場欄位頂部顯示綜合判讀 weightSupport', (tester) async {
      widenViewport(tester);
      final state = MarketOverviewState(
        indices: [
          createIndex(MarketIndexNames.taiex, 22000, 10), // ~0.045%，平盤
        ],
        advanceDeclineByMarket: {
          'TWSE': const AdvanceDecline(advance: 200, decline: 800),
        },
        institutionalByMarket: {
          'TWSE': const InstitutionalTotals(totalNet: 100000000),
        },
        dataDate: DateTime(2026, 2, 13),
      );

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('marketOverview.reading.synthesis.weightSupport'),
        findsOneWidget,
      );
    });

    testWidgets('綜合判讀 strip 以 prominent 樣式呈現，與同欄位其餘 per-section 判讀區隔', (
      tester,
    ) async {
      widenViewport(tester);
      // 沿用 weightSupport 情境：advance=200/decline=800 同時也會觸發
      // AdvanceDeclineGauge 內建的廣度判讀行（per-section，非 prominent），
      // 一次驗證「僅 top-level 綜合判讀升層、其餘維持預設」。
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 10)],
        advanceDeclineByMarket: {
          'TWSE': const AdvanceDecline(advance: 200, decline: 800),
        },
        institutionalByMarket: {
          'TWSE': const InstitutionalTotals(totalNet: 100000000),
        },
        dataDate: DateTime(2026, 2, 13),
      );

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      final lines = tester
          .widgetList<MarketReadingLine>(find.byType(MarketReadingLine))
          .toList();
      expect(lines, isNotEmpty);
      expect(lines.where((l) => l.prominent).length, 1);
      expect(lines.any((l) => !l.prominent), isTrue);
    });

    testWidgets('綜合判讀僅在該市場有指數資料時顯示；TPEx 無指數時該欄不渲染', (tester) async {
      widenViewport(tester);
      // createLoadedState()：TWSE 有指數（漲 0.68%，非平盤）+ 法人合計同向買超
      // → neutral；TPEx 有漲跌家數但 indices 中無櫃買指數 → 綜合判讀不顯示。
      final state = createLoadedState();

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('marketOverview.reading.synthesis.neutral'),
        findsOneWidget,
      );
    });

    testWidgets('parallel 檢視在 TWSE + TPEx 皆有足夠資料時，同時渲染兩個市場情緒儀表', (
      tester,
    ) async {
      widenViewport(tester);
      final state = parallelSentimentState();

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      final gauges = tester
          .widgetList<SentimentGaugeSection>(find.byType(SentimentGaugeSection))
          .toList();
      expect(gauges, hasLength(2));
      // TWSE 上漲占比 0.75、TPEx 上漲占比 0.25 → 分數應明顯不同，證明兩側
      // 各自獨立計算（非共用或硬編碼同一值）。
      expect(
        gauges[0].sentiment.score,
        isNot(equals(gauges[1].sentiment.score)),
      );
      // 各自傳入正確且不同的 market，內建標題才能標示「上市/上櫃 市場情緒」
      // 而非兩側顯示相同、無法區分的「市場情緒」（見 SentimentGaugeSection
      // 市場標示測試驗證實際渲染文字）。
      expect(gauges[0].market, MarketCode.twse);
      expect(gauges[1].market, MarketCode.tpex);
    });

    testWidgets(
      'parallel 檢視情緒配對列在 unbounded 高度環境（今日頁 CustomScrollView 情境）下分隔線仍可見',
      (tester) async {
        widenViewport(tester);
        final state = parallelSentimentState();

        // 今日頁實際將 MarketDashboard 放在 CustomScrollView 的
        // SliverToBoxAdapter 內，對 Column 子孫的垂直方向給 unbounded
        // 高度；用 SingleChildScrollView 在測試中複現同一條件
        // （VerticalDivider 唯有在此條件下才會塌陷為 0 高度、隱形）。
        await tester.pumpWidget(
          buildTestApp(
            SingleChildScrollView(child: MarketDashboard(state: state)),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        final sentimentRow = find
            .ancestor(
              of: find.byType(SentimentGaugeSection).first,
              matching: find.byType(Row),
            )
            .first;
        final divider = find.descendant(
          of: sentimentRow,
          matching: find.byType(VerticalDivider),
        );
        expect(divider, findsOneWidget);
        expect(tester.getSize(divider).height, greaterThan(0));
      },
    );

    testWidgets('TPEx 情緒資料不足時，parallel 檢視僅渲染 TWSE 情緒儀表（優雅降級）', (tester) async {
      widenViewport(tester);
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
        advanceDeclineByMarket: {
          'TWSE': const AdvanceDecline(advance: 600, decline: 200),
          'TPEx': const AdvanceDecline(advance: 100, decline: 300),
        },
        historyTrends: HistoryTrends(
          turnover: {
            'TWSE': [
              (date: DateTime(2026, 2, 11), value: 1000.0),
              (date: DateTime(2026, 2, 12), value: 1200.0),
            ],
            // 'TPEx' 缺席 → 資料不足，_computeSentiment 應回傳 null
          },
        ),
        dataDate: DateTime(2026, 2, 13),
      );

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SentimentGaugeSection), findsOneWidget);
    });
  });
  // 籌碼槓桿判讀必須用融資那天的指數，不能用最新的
  //
  // 融資融券由 TWSE 約 21:00 發布，傍晚更新時常落後 1~3 天（區塊也標著該
  // 日期），配最新指數會讓因果陳述反轉。2026-07-27 20:39 實機：櫃買
  // 07-24 = -3.69%（融資日）、07-27 = +0.12%（畫面取的）→ 顯示「指數漲、
  // 融資減：籌碼洗清，相對健康」，正確應為「指數跌、融資減：去槓桿中」。
  //
  // 這條守的是**接線**：provider 算好了 marginIndexChangePercent，但
  // dashboard 若仍呼叫 _indexChangePercent（最新值）就是白算。
  testWidgets('🚨 融資判讀用融資日指數，不得用最新指數', (tester) async {
    widenViewport(tester);

    final state = MarketOverviewState(
      // 最新指數為「漲」——若接線錯誤會據此講成「籌碼洗清，相對健康」
      indices: [createIndex(MarketIndexNames.tpexIndex, 378.09, 0.46)],
      marginByMarket: const {
        MarketCode.tpex: MarginTradingTotals(
          marginBalance: 2220000,
          marginChange: -12000,
          shortBalance: 36000,
          shortChange: 6915,
        ),
      },
      // 融資那天（07-24）大盤是跌的
      marginIndexChangePercent: const {MarketCode.tpex: -3.69},
    );

    await tester.pumpWidget(
      buildTestApp(MarketDashboard(state: state), brightness: Brightness.dark),
    );
    await tester.pump(const Duration(seconds: 1));

    // 斷言 i18n key 而非譯文：不依賴 harness 是否載入翻譯，且直接對應
    // MarketReadingService 的分支，改文案不會讓這條假性轉紅
    expect(
      find.textContaining('marginLeverage.deleveraging'),
      findsWidgets,
      reason: '融資日指數為 -3.69%（跌）→ 應判「去槓桿中」',
    );
    expect(
      find.textContaining('marginLeverage.healthyWashout'),
      findsNothing,
      reason: '用最新的 +0.12% 會誤判成「籌碼洗清，相對健康」——方向相反且更樂觀',
    );
  });

  group('區塊載入失敗註記(2026-08-29 靜默稽核 #7)', () {
    testWidgets('🚨 有區塊失敗 → 標題上方掛「N 個區塊載入失敗」', (tester) async {
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
        failedSections: const {'warningCounts', 'institutional'},
        dataDate: DateTime(2026, 2, 13),
      );
      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('marketOverview.sectionsFailed'), findsOneWidget);
    });

    testWidgets('無區塊失敗 → 無註記(不誤報)', (tester) async {
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
        dataDate: DateTime(2026, 2, 13),
      );
      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('marketOverview.sectionsFailed'), findsNothing);
    });
  });

  group('籌碼異動失敗閘門(2026-08-29 review:閘門原本零測試)', () {
    testWidgets('🚨 零異動+有偵測失敗 → 區塊必須現身並顯示註記', (tester) async {
      // 閘門在 dashboard 層——把 || anomalyFailures 拿掉時 Row 層測試照樣
      // 全綠,而區塊在真實畫面上消失,正是原始症狀
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
        chipAnomaliesByMarket: const {},
        chipAnomalyFailedDetectors: const ['highPledge'],
        dataDate: DateTime(2026, 2, 13),
      );
      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('marketOverview.chipAnomaly.partialFail'), findsWidgets);
    });

    testWidgets('🚨 parallel 檢視(寬視口)同樣受閘門保護', (tester) async {
      // mobile 與 parallel 是兩條獨立的建構路徑(:498 vs :847)——只測
      // mobile 時 parallel 閘門的移除 mutation 存活(實測)
      widenViewport(tester);
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
        chipAnomaliesByMarket: const {},
        chipAnomalyFailedDetectors: const ['highPledge'],
        dataDate: DateTime(2026, 2, 13),
      );
      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('marketOverview.chipAnomaly.partialFail'), findsWidgets);
    });

    testWidgets('零異動零失敗 → 區塊維持隱藏(既有行為)', (tester) async {
      final state = MarketOverviewState(
        indices: [createIndex(MarketIndexNames.taiex, 22000, 150)],
        dataDate: DateTime(2026, 2, 13),
      );
      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('marketOverview.chipAnomaly.partialFail'), findsNothing);
    });
  });
}

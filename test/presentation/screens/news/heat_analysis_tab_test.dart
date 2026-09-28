import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/heat_calculator.dart';
import 'package:daredevil/presentation/providers/news_heat_provider.dart';
import 'package:daredevil/presentation/screens/news/heat_analysis_tab.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';
import '../../../helpers/phone_layout_helpers.dart';

// 註：本專案 widget 測試慣例（見 test/helpers/widget_test_helpers.dart 的
// buildTestApp／setupTestLocalization）在
// buildTestApp/buildProviderTestApp 下不接
// EasyLocalization widget，`.tr()` 因此解析不到真實翻譯、fallback 回傳
// 原始 key 字串本身。故本檔斷言比對「i18n key 原始字串」而非翻譯後文字，
// 與專案既有測試慣例一致（非本檔行為變更）。

NewsHeatAnalysis analysis() => const NewsHeatAnalysis(
  themes: [
    ThemeHeat(
      theme: '記憶體',
      articles7d: 23,
      articlesPrev21d: 6,
      isSurging: true,
      topStocks: ['2408', '2344'],
    ),
  ],
  stocks: [
    StockHeat(
      symbol: '2408',
      mentions7d: 9,
      mentionsPrev21d: 2,
      isSurging: true,
      distinctSources7d: 3,
      hasRiskNews: false,
      isNewEntrant: false,
      surgeRatio: 9.0, // 9 / max(2/3, 1.0)
    ),
    StockHeat(
      symbol: '2330',
      mentions7d: 30,
      mentionsPrev21d: 40,
      isSurging: false,
      distinctSources7d: 5,
      hasRiskNews: false,
      isNewEntrant: false,
      surgeRatio: 2.25, // 30 / (40/3)
    ),
  ],
  stockNames: {'2408': '南亞科', '2344': '華邦電', '2330': '台積電'},
  modeBySymbol: {'2408': ScoringMode.weaknessObserve},
  priceChangeBySymbol: {},
  warningBySymbol: {},
  surgeReliable: true,
);

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget build(NewsHeatAnalysis data) => buildProviderTestApp(
    const HeatAnalysisTab(),
    overrides: [newsHeatProvider.overrideWith((ref) async => data)],
  );

  testWidgets('顯示主流族群卡片與成分股', (tester) async {
    widenViewport(tester);
    await tester.pumpWidget(build(analysis()));
    await tester.pumpAndSettle();

    expect(find.text('記憶體'), findsOneWidget);
    expect(find.text('南亞科'), findsWidgets);
  });

  testWidgets('焦點股列表含爆量徽章與回檔標注', (tester) async {
    widenViewport(tester);
    await tester.pumpWidget(build(analysis()));
    await tester.pumpAndSettle();

    expect(find.text('台積電'), findsOneWidget);
    // 爆量徽章（2408）至少一個 — 'news.surgeBadge' i18n key
    expect(find.text('news.surgeBadge'), findsWidgets);
    // 回檔標注（2408 屬 weaknessObserve）— ScoringMode.displayKey i18n key
    expect(find.text('scoringMode.weaknessObserve'), findsWidgets);
  });

  testWidgets('只看回檔中過濾', (tester) async {
    widenViewport(tester);
    await tester.pumpWidget(build(analysis()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('news.pullbackOnly'));
    await tester.pumpAndSettle();

    expect(find.text('南亞科'), findsWidgets);
    expect(find.text('台積電'), findsNothing);
  });

  testWidgets('族群卡片成分股為空時不渲染 chips 區塊', (tester) async {
    widenViewport(tester);
    const data = NewsHeatAnalysis(
      themes: [
        ThemeHeat(
          theme: '軍工',
          articles7d: 8,
          articlesPrev21d: 0,
          isSurging: false,
          topStocks: [], // 政策/產業級報導無上市公司名 → 無成分股
        ),
      ],
      stocks: [],
      stockNames: {},
      modeBySymbol: {},
      priceChangeBySymbol: {},
      warningBySymbol: {},
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('軍工'), findsOneWidget);
    // 空成分股 → 整個 Wrap（chips 容器）不渲染，不留空白列
    expect(find.byType(Wrap), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('空資料顯示空狀態', (tester) async {
    widenViewport(tester);
    await tester.pumpWidget(
      build(
        const NewsHeatAnalysis(
          themes: [],
          stocks: [],
          stockNames: {},
          modeBySymbol: {},
          priceChangeBySymbol: {},
          warningBySymbol: {},
          surgeReliable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('news.heatEmpty'), findsOneWidget);
  });

  testWidgets('讀取失敗顯示錯誤狀態＋重試，不顯示原始例外文字', (tester) async {
    widenViewport(tester);
    await tester.pumpWidget(
      buildProviderTestApp(
        const HeatAnalysisTab(),
        overrides: [
          newsHeatProvider.overrideWith((ref) async => throw Exception('boom')),
        ],
      ),
    );
    // FutureProvider 的 async throw 需一次 pump 完成並重建；EmptyState 的
    // breathe 動畫是無限循環（repeat(reverse: true)），不能用 pumpAndSettle
    // 等待穩定（會逾時），改用固定時長的 pump 推進一次動畫幀即可斷言。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('Exception: boom'), findsNothing);
  });

  testWidgets('有生效警示顯示風險徽章，未列管且無風險新聞則不顯示', (tester) async {
    widenViewport(tester);
    final data = NewsHeatAnalysis(
      themes: const [],
      stocks: const [
        StockHeat(
          symbol: '2408',
          mentions7d: 9,
          mentionsPrev21d: 2,
          isSurging: false,
          distinctSources7d: 3,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
        StockHeat(
          symbol: '2330',
          mentions7d: 5,
          mentionsPrev21d: 5,
          isSurging: false,
          distinctSources7d: 2,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
      ],
      stockNames: const {'2408': '南亞科', '2330': '台積電'},
      modeBySymbol: const {},
      priceChangeBySymbol: const {},
      warningBySymbol: {
        '2408': TradingWarningEntry(
          symbol: '2408',
          date: DateTime(2026, 7, 10),
          warningType: 'ATTENTION',
          isActive: true,
        ),
      },
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    // 有效警示（2408）→ 沿用既有 warning.attention 標籤（WarningBadgeType.label）
    expect(find.text('warning.attention'), findsOneWidget);
    // 2330 無警示、無風險新聞 → 不應出現任何風險徽章文字
    expect(find.text('warning.disposal'), findsNothing);
    expect(find.text('news.riskNews'), findsNothing);
  });

  testWidgets('處置股警示走 DISPOSAL 分支顯示對應標籤', (tester) async {
    widenViewport(tester);
    final data = NewsHeatAnalysis(
      themes: const [],
      stocks: const [
        StockHeat(
          symbol: '2408',
          mentions7d: 5,
          mentionsPrev21d: 2,
          isSurging: false,
          distinctSources7d: 2,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
      ],
      stockNames: const {'2408': '南亞科'},
      modeBySymbol: const {},
      priceChangeBySymbol: const {},
      warningBySymbol: {
        '2408': TradingWarningEntry(
          symbol: '2408',
          date: DateTime(2026, 7, 10),
          warningType: 'DISPOSAL',
          isActive: true,
        ),
      },
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('warning.disposal'), findsOneWidget);
    expect(find.text('warning.attention'), findsNothing);
  });

  testWidgets('hasRiskNews 無警示表仍顯示風險徽章', (tester) async {
    widenViewport(tester);
    const data = NewsHeatAnalysis(
      themes: [],
      stocks: [
        StockHeat(
          symbol: '2408',
          mentions7d: 9,
          mentionsPrev21d: 2,
          isSurging: false,
          distinctSources7d: 3,
          hasRiskNews: true,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
      ],
      stockNames: {'2408': '南亞科'},
      modeBySymbol: {},
      priceChangeBySymbol: {},
      warningBySymbol: {},
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('news.riskNews'), findsOneWidget);
  });

  testWidgets('顯示當日漲跌幅；無資料的個股不顯示百分比文字', (tester) async {
    widenViewport(tester);
    const data = NewsHeatAnalysis(
      themes: [],
      stocks: [
        StockHeat(
          symbol: '2408',
          mentions7d: 9,
          mentionsPrev21d: 2,
          isSurging: false,
          distinctSources7d: 3,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
        StockHeat(
          symbol: '2330',
          mentions7d: 5,
          mentionsPrev21d: 5,
          isSurging: false,
          distinctSources7d: 2,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
      ],
      stockNames: {'2408': '南亞科', '2330': '台積電'},
      modeBySymbol: {},
      priceChangeBySymbol: {'2408': 2.35},
      warningBySymbol: {},
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('+2.35%'), findsOneWidget);
    // 2330 缺 key → 全畫面僅此一個百分比文字（證明 2330 沒有顯示）
    expect(find.textContaining('%'), findsOneWidget);
  });

  testWidgets('平盤（0）漲跌幅顯示 0.00%，不帶 + 號', (tester) async {
    widenViewport(tester);
    const data = NewsHeatAnalysis(
      themes: [],
      stocks: [
        StockHeat(
          symbol: '2408',
          mentions7d: 9,
          mentionsPrev21d: 2,
          isSurging: false,
          distinctSources7d: 3,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 1.0,
        ),
      ],
      stockNames: {'2408': '南亞科'},
      modeBySymbol: {},
      priceChangeBySymbol: {'2408': 0.0},
      warningBySymbol: {},
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('+0.00%'), findsNothing, reason: '平盤不得帶 +');
    expect(find.text('0.00%'), findsOneWidget);
  });

  testWidgets('surgeReliable=false 時隱藏所有爆量徽章（含主題卡）', (tester) async {
    widenViewport(tester);
    final base = analysis();
    final data = NewsHeatAnalysis(
      themes: base.themes,
      stocks: base.stocks,
      stockNames: base.stockNames,
      modeBySymbol: base.modeBySymbol,
      priceChangeBySymbol: base.priceChangeBySymbol,
      warningBySymbol: base.warningBySymbol,
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    // base 的主題與 2408 皆 isSurging: true，但 surgeReliable=false 應全數隱藏
    expect(find.text('news.surgeBadge'), findsNothing);
  });

  testWidgets('surgeReliable=true 且 isNewEntrant 顯示新進榜徽章', (tester) async {
    widenViewport(tester);
    const data = NewsHeatAnalysis(
      themes: [],
      stocks: [
        StockHeat(
          symbol: '6488',
          mentions7d: 4,
          mentionsPrev21d: 0,
          isSurging: true,
          distinctSources7d: 2,
          hasRiskNews: false,
          isNewEntrant: true,
          surgeRatio: 4.0,
        ),
      ],
      stockNames: {'6488': '環球晶'},
      modeBySymbol: {},
      priceChangeBySymbol: {},
      warningBySymbol: {},
      surgeReliable: true,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('news.newEntrant'), findsOneWidget);
  });

  testWidgets('surgeReliable=false 時排序切換隱藏', (tester) async {
    widenViewport(tester);
    final base = analysis();
    final data = NewsHeatAnalysis(
      themes: base.themes,
      stocks: base.stocks,
      stockNames: base.stockNames,
      modeBySymbol: base.modeBySymbol,
      priceChangeBySymbol: base.priceChangeBySymbol,
      warningBySymbol: base.warningBySymbol,
      surgeReliable: false,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    expect(find.text('news.sortByMentions'), findsNothing);
  });

  testWidgets('點擊爆量排序依 surgeRatio 重新排列焦點股', (tester) async {
    widenViewport(tester);
    const data = NewsHeatAnalysis(
      themes: [],
      stocks: [
        StockHeat(
          symbol: '1101',
          mentions7d: 5,
          mentionsPrev21d: 3,
          isSurging: false,
          distinctSources7d: 1,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 2.0,
        ),
        StockHeat(
          symbol: '2603',
          mentions7d: 3,
          mentionsPrev21d: 1,
          isSurging: false,
          distinctSources7d: 1,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 8.0,
        ),
      ],
      stockNames: {'1101': '甲公司', '2603': '乙公司'},
      modeBySymbol: {},
      priceChangeBySymbol: {},
      warningBySymbol: {},
      surgeReliable: true,
    );
    await tester.pumpWidget(build(data));
    await tester.pumpAndSettle();

    // 預設「篇數」序：甲（5 篇）在乙（3 篇）之上
    final beforeA = tester.getTopLeft(find.text('甲公司')).dy;
    final beforeB = tester.getTopLeft(find.text('乙公司')).dy;
    expect(beforeA, lessThan(beforeB));

    await tester.tap(find.text('news.surgeBadge'));
    await tester.pumpAndSettle();

    // 切到「爆量」序：乙（surgeRatio 8.0）換到甲（2.0）之上
    final afterA = tester.getTopLeft(find.text('甲公司')).dy;
    final afterB = tester.getTopLeft(find.text('乙公司')).dy;
    expect(afterB, lessThan(afterA));
  });

  group('錯誤頁在手機上（比照新聞頁的 AppBar + TabBar）', () {
    Widget inNewsTabs(Object error) => buildProviderTestApp(
      DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('news'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'a'),
                Tab(text: 'b'),
              ],
            ),
          ),
          body: const HeatAnalysisTab(),
        ),
      ),
      overrides: [
        newsHeatProvider.overrideWith(
          (ref) => Future<NewsHeatAnalysis>.error(error),
        ),
      ],
    );

    final errors = <String, Object>{
      'Database error': const DatabaseException('Database error'),
      'Network error': const NetworkException('Network error'),
    };
    for (final entry in errors.entries) {
      for (final scenario in phoneScenarios) {
        testWidgets('${entry.key}：$scenario 不溢位', (tester) async {
          applyPhoneScenario(tester, scenario);
          await tester.pumpWidget(inNewsTabs(entry.value));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          expect(find.text('common.retry'), findsOneWidget);
        });
      }
    }
  });
}

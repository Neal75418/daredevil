import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/heat_calculator.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_heat_provider.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/screens/news/heat_analysis_tab.dart';
import 'package:daredevil/presentation/screens/news/news_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifier
// ==========================================

class FakeNewsNotifier extends NewsNotifier {
  NewsState initialState = NewsState();
  final calls = <String>[];
  NewsFetchOutcome? outcome;
  Set<String>? mySymbolsAfterReload;

  @override
  NewsState build() => initialState;

  @override
  Future<void> loadData({int days = 7}) async => calls.add('load');

  @override
  void setFilter(NewsFilter filter) {
    calls.add('filter');
    state = state.copyWith(filter: filter);
  }

  @override
  Future<NewsFetchOutcome?> refresh({int days = 7}) async {
    calls.add('refresh');
    return outcome;
  }

  @override
  void onNewsDataChanged() => calls.add('changed');

  @override
  Future<void> reloadMySymbols() async {
    calls.add('reloadMine');
    if (mySymbolsAfterReload case final s?) {
      state = state.copyWith(mySymbols: s);
    }
  }
}

// ==========================================
// Test Helpers
// ==========================================

NewsItemEntry createNewsItem({
  String id = 'news_1',
  String title = 'TSMC Q1 Revenue Hits Record',
  String source = '鉅亨網',
  String url = 'https://example.com/news/1',
  DateTime? publishedAt,
}) {
  return NewsItemEntry(
    id: id,
    title: title,
    source: source,
    url: url,
    category: 'market',
    publishedAt: publishedAt ?? DateTime(2026, 2, 13, 10, 0),
    fetchedAt: DateTime(2026, 2, 13, 10, 0),
  );
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

  Widget buildTestWidget({
    NewsState? newsState,
    Brightness brightness = Brightness.light,
    List<Override> extraOverrides = const [],
  }) {
    final state = newsState ?? NewsState();
    return buildProviderTestApp(
      const NewsScreen(),
      overrides: [
        newsProvider.overrideWith(() {
          final n = FakeNewsNotifier();
          n.initialState = state;
          return n;
        }),
        ...extraOverrides,
      ],
      brightness: brightness,
    );
  }

  group('NewsScreen', () {
    testWidgets('shows AppBar with title', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows refresh icon button', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NewsListShimmer), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(error: 'Network error')),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty state when no news', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows news items', (tester) async {
      widenViewport(tester);
      final now = DateTime.now();
      final newsItems = [
        createNewsItem(
          id: 'n1',
          title: 'Breaking: TSMC Earnings',
          source: '鉅亨網',
          publishedAt: now,
        ),
        createNewsItem(
          id: 'n2',
          title: 'Market Update Today',
          source: 'Yahoo財經',
          publishedAt: now,
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(allNews: newsItems)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Breaking: TSMC Earnings'), findsOneWidget);
      expect(find.text('Market Update Today'), findsOneWidget);
    });

    testWidgets('shows source badges', (tester) async {
      widenViewport(tester);
      final newsItems = [
        createNewsItem(source: '鉅亨網', publishedAt: DateTime.now()),
      ];
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(allNews: newsItems)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('鉅亨網'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows source filter chips when has news', (tester) async {
      widenViewport(tester);
      final newsItems = [
        createNewsItem(source: '鉅亨網', publishedAt: DateTime.now()),
      ];
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(allNews: newsItems)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilterChip), findsAtLeastNWidgets(1));
    });

    testWidgets('hides source chips when loading', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('淺色主題選中的來源標籤文字色為 onSurface（非 onSecondaryContainer）', (
      tester,
    ) async {
      // chipTheme.selectedColor（淺色主題）是 primaryColor 疊 15% alpha
      // 於白之上的淡色，非實心 secondaryContainer；onSecondaryContainer
      // 對這個合成色對比不足（見 test/core/theme/app_theme_surfaces_test.dart
      // 的疊色守門測試），故選中標籤文字必須是 onSurface。
      widenViewport(tester);
      final newsItems = [
        createNewsItem(source: '鉅亨網', publishedAt: DateTime.now()),
      ];
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(allNews: newsItems)),
      );
      await tester.pump(const Duration(seconds: 1));

      // NewsSource.all 恆為第一個顯示的 chip，且預設為選中來源
      final allChip = tester.widget<FilterChip>(find.byType(FilterChip).first);
      final labelColor = allChip.labelStyle?.color;
      expect(labelColor, AppTheme.lightTheme.colorScheme.onSurface);
      expect(
        labelColor,
        isNot(AppTheme.lightTheme.colorScheme.onSecondaryContainer),
      );
    });

    testWidgets('refreshing with existing news keeps list, no shimmer', (
      tester,
    ) async {
      widenViewport(tester);
      final newsItems = [
        createNewsItem(title: 'Existing News', publishedAt: DateTime.now()),
      ];
      await tester.pumpWidget(
        buildTestWidget(
          newsState: NewsState(isLoading: true, allNews: newsItems),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NewsListShimmer), findsNothing);
      expect(find.text('Existing News'), findsOneWidget);
    });

    testWidgets('refreshing with existing news keeps filter chips', (
      tester,
    ) async {
      widenViewport(tester);
      final newsItems = [
        createNewsItem(source: '鉅亨網', publishedAt: DateTime.now()),
      ];
      await tester.pumpWidget(
        buildTestWidget(
          newsState: NewsState(isLoading: true, allNews: newsItems),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilterChip), findsAtLeastNWidgets(1));
    });

    testWidgets('refresh button shows spinner while loading', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows related stock chips', (tester) async {
      widenViewport(tester);
      final newsItems = [
        createNewsItem(
          id: 'n1',
          title: 'TSMC News',
          publishedAt: DateTime.now(),
        ),
      ];
      final newsStockMap = <String, List<String>>{
        'n1': ['2330', '2317'],
      };
      await tester.pumpWidget(
        buildTestWidget(
          newsState: NewsState(
            allNews: newsItems,
            relatedStocksByNewsId: newsStockMap,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2330'), findsOneWidget);
      expect(find.text('2317'), findsOneWidget);
    });

    testWidgets('shows overflow chip for many related stocks', (tester) async {
      widenViewport(tester);
      final newsItems = [
        createNewsItem(
          id: 'n1',
          title: 'Sector Report',
          publishedAt: DateTime.now(),
        ),
      ];
      final newsStockMap = <String, List<String>>{
        'n1': ['2330', '2317', '2454', '2412', '3711'],
      };
      await tester.pumpWidget(
        buildTestWidget(
          newsState: NewsState(
            allNews: newsItems,
            relatedStocksByNewsId: newsStockMap,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Shows +2 overflow chip (5 stocks - 3 visible = 2 overflow)
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('shows arrow forward icon on news items', (tester) async {
      widenViewport(tester);
      final newsItems = [createNewsItem(publishedAt: DateTime.now())];
      await tester.pumpWidget(
        buildTestWidget(newsState: NewsState(allNews: newsItems)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    });

    testWidgets('switches to heat analysis tab', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          extraOverrides: [
            newsHeatProvider.overrideWith(
              (ref) async => const NewsHeatAnalysis(
                themes: [],
                stocks: [],
                stockNames: {},
                modeBySymbol: {},
              ),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.allNewsTab'), findsOneWidget);
      expect(find.text('news.heatTab'), findsOneWidget);

      await tester.tap(find.text('news.heatTab'));
      await tester.pumpAndSettle();

      expect(find.byType(HeatAnalysisTab), findsOneWidget);
    });
    testWidgets('篩選列有「自選」與則數，排在全部之後', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        relatedStocksByNewsId: const {
          'a': ['9901'],
        },
        mySymbols: const {'9901'},
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      final labels = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .map((c) => ((c.label as Text).data ?? ''))
          .toList();
      expect(labels[0], startsWith('empty.sourceAll'));
      expect(labels[1], 'news.filterMine (1)');
    });

    testWidgets('自選 0 則也顯示「自選」', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.filterMine (0)'), findsOneWidget);
    });

    testWidgets('點「自選」只列自選相關新聞', (tester) async {
      widenViewport(tester);
      final now = DateTime.now();
      final state = NewsState(
        allNews: [
          createNewsItem(id: 'a', title: '自選那則', publishedAt: now),
          createNewsItem(id: 'b', title: '別檔那則', publishedAt: now),
        ],
        relatedStocksByNewsId: const {
          'a': ['9901'],
          'b': ['9902'],
        },
        mySymbols: const {'9901'},
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('news.filterMine (1)'));
      await tester.pump();

      expect(find.text('自選那則'), findsOneWidget);
      expect(find.text('別檔那則'), findsNothing);
    });

    testWidgets('自選篩選、沒有自選也沒有持股：顯示還沒有自選股或持股', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        filter: NewsFilter.mine,
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.mineEmptyNoStocks'), findsOneWidget);
    });

    testWidgets('自選篩選、有自選但沒新聞：顯示近 7 天沒有相關新聞', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.mineEmptyNoNews'), findsOneWidget);
    });

    testWidgets('自選篩選下，自選股的標籤排在 +N 之前看得到', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        relatedStocksByNewsId: const {
          'a': ['9902', '9903', '9904', '9901'],
        },
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('9901'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('從個股頁返回後重讀自選；移除最後一檔後自選篩選顯示空', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier()
        ..initialState = NewsState(
          allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
          relatedStocksByNewsId: const {
            'a': ['9901'],
          },
          mySymbols: const {'9901'},
          filter: NewsFilter.mine,
        )
        ..mySymbolsAfterReload = const {};
      final router = GoRouter(
        initialLocation: '/news',
        routes: [
          GoRoute(path: '/news', builder: (_, _) => const NewsScreen()),
          GoRoute(
            path: '/stock/:symbol',
            builder: (_, _) => const Scaffold(body: Text('detail')),
          ),
        ],
      );
      await tester.pumpWidget(
        buildProviderTestApp(
          const SizedBox(),
          router: router,
          overrides: [newsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('9901'));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      router.pop();
      // 空狀態圖示有循環動畫，pumpAndSettle 等不到靜止
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(notifier.calls, contains('reloadMine'));
      expect(find.text('news.mineEmptyNoStocks'), findsOneWidget);
    });

    testWidgets('從熱度分頁點進個股頁、返回後也重讀自選', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier();
      final router = GoRouter(
        initialLocation: '/news',
        routes: [
          GoRoute(path: '/news', builder: (_, _) => const NewsScreen()),
          GoRoute(
            path: '/stock/:symbol',
            builder: (_, _) => const Scaffold(body: Text('detail')),
          ),
        ],
      );
      await tester.pumpWidget(
        buildProviderTestApp(
          const SizedBox(),
          router: router,
          overrides: [
            newsProvider.overrideWith(() => notifier),
            newsHeatProvider.overrideWith(
              (ref) async => const NewsHeatAnalysis(
                themes: [],
                stocks: [
                  StockHeat(
                    symbol: '9901',
                    mentions7d: 5,
                    mentionsPrev21d: 1,
                    isSurging: false,
                    distinctSources7d: 2,
                    hasRiskNews: false,
                    isNewEntrant: false,
                    surgeRatio: 1.0,
                  ),
                ],
                stockNames: {'9901': '甲乙'},
                modeBySymbol: {},
              ),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('news.heatTab'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('甲乙')); // 焦點股列的股名
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      expect(notifier.calls, contains('reloadMine'));
    });

    testWidgets('新聞資料版本遞增時通知 notifier', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier();
      await tester.pumpWidget(
        buildProviderTestApp(
          const NewsScreen(),
          overrides: [newsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      ProviderScope.containerOf(
        tester.element(find.byType(NewsScreen)),
      ).read(newsDataVersionProvider.notifier).bump();
      await tester.pump();

      expect(notifier.calls, contains('changed'));
    });

    testWidgets('重新整理全部來源失敗時跳錯誤提示', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier()
        ..outcome = const NewsFetchOutcome(totalSources: 5, failedSources: 5);
      await tester.pumpWidget(
        buildProviderTestApp(
          const NewsScreen(),
          overrides: [newsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(find.text('news.fetchAllFailed'), findsOneWidget);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/models/news_feed.dart';
import 'package:daredevil/domain/repositories/news_repository.dart'
    show NewsSyncResult;
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/news_tab.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class MockNewsFetcher extends Mock implements NewsFetcher {}

class MockNewsRepository extends Mock implements NewsRepository {}

NewsItemEntry news(String id, {DateTime? at}) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: '標題$id',
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: at ?? DateTime.now(),
  fetchedAt: at ?? DateTime.now(),
);

StockNews data(
  List<NewsItemEntry> items, {
  StockNameStatus status = StockNameStatus.matched,
}) =>
    StockNews(items: items, otherStocksByNewsId: const {}, nameStatus: status);

void main() {
  setUpAll(() async => setupTestLocalization());

  Widget app(
    String symbol, {
    required StockNews Function(String) load,
    NewsFetcher? fetcher,
  }) => buildProviderTestApp(
    Scaffold(
      body: StockNewsTab(key: ValueKey('news-$symbol'), symbol: symbol),
    ),
    overrides: [
      stockNewsProvider.overrideWith((ref, s) async => load(s)),
      if (fetcher != null) newsFetcherProvider.overrideWithValue(fetcher),
    ],
  );

  testWidgets('列出新聞與一般說明', (tester) async {
    await tester.pumpWidget(app('9901', load: (_) => data([news('a')])));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('標題a'), findsOneWidget);
    expect(find.text('stockNews.noteMatched'), findsOneWidget);
  });

  testWidgets('簡稱被排除：常見詞版說明', (tester) async {
    await tester.pumpWidget(
      app(
        '9902',
        load: (_) => data([news('a')], status: StockNameStatus.excluded),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('stockNews.noteExcluded'), findsOneWidget);
  });

  testWidgets('不在清單：不在清單版說明', (tester) async {
    await tester.pumpWidget(
      app(
        '9999',
        load: (_) => data(const [], status: StockNameStatus.notListed),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1)); // 空狀態動畫的計時器
    expect(find.text('stockNews.noteNotListed'), findsOneWidget);
  });

  testWidgets('沒有新聞：空畫面，說明照常', (tester) async {
    await tester.pumpWidget(app('9901', load: (_) => data(const [])));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1)); // 空狀態動畫的計時器
    expect(find.text('stockNews.empty'), findsOneWidget);
    expect(find.text('stockNews.noteMatched'), findsOneWidget);
  });

  testWidgets('上百則只建構看得到的列（lazy）', (tester) async {
    final many = [
      for (var i = 0; i < 300; i++)
        news('$i', at: DateTime.now().subtract(Duration(minutes: i))),
    ];
    await tester.pumpWidget(app('9901', load: (_) => data(many)));
    await tester.pump(const Duration(seconds: 1));

    final built = tester.widgetList(find.byType(NewsListItem)).length;
    expect(built, greaterThan(0));
    expect(built, lessThan(100));
  });

  testWidgets('斷網按重新整理：提示全部失敗，重讀期間清單保留、不閃載入中', (tester) async {
    // 走真的 NewsFetcher：抓完遞增版本 → provider 重讀；第二次載入卡住，
    // 驗證 skipLoadingOnReload 讓清單留著
    final repo = MockNewsRepository();
    when(() => repo.syncNews()).thenAnswer(
      (_) async => NewsSyncResult(
        itemsAdded: 0,
        errors: [
          for (final s in NewsFeedSource.defaultSources)
            NewsFeedError(
              sourceName: s.name,
              url: s.url,
              error: 'offline',
              timestamp: DateTime(2026, 10, 6),
            ),
        ],
      ),
    );
    var builds = 0;
    final reload = Completer<StockNews>();
    await tester.pumpWidget(
      buildProviderTestApp(
        const Scaffold(body: StockNewsTab(symbol: '9901')),
        overrides: [
          newsRepositoryProvider.overrideWithValue(repo),
          stockNewsProvider.overrideWith((ref, s) {
            ref.watch(newsDataVersionProvider);
            return builds++ == 0
                ? Future.value(data([news('a')]))
                : reload.future;
          }),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('stockNews.refresh'));
    await tester.pump();
    await tester.pump();

    expect(builds, 2, reason: '前提：抓完遞增版本、清單正在重讀');
    expect(find.text('news.fetchAllFailed'), findsOneWidget);
    expect(find.text('標題a'), findsOneWidget);
    expect(find.byType(NewsListShimmer), findsNothing);

    reload.complete(data([news('a')]));
    await tester.pump();
    expect(find.text('標題a'), findsOneWidget);
  });

  testWidgets('重新整理進行中不重複觸發', (tester) async {
    final fetcher = MockNewsFetcher();
    final gate = Completer<NewsFetchOutcome>();
    when(() => fetcher.fetch()).thenAnswer((_) => gate.future);
    await tester.pumpWidget(
      app('9901', load: (_) => data([news('a')]), fetcher: fetcher),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('stockNews.refresh'));
    await tester.pump();
    await tester.tap(find.byTooltip('stockNews.refresh'), warnIfMissed: false);
    await tester.pump();
    gate.complete(const NewsFetchOutcome(totalSources: 5, failedSources: 0));
    await tester.pump();

    verify(() => fetcher.fetch()).called(1);
  });

  testWidgets('抓取期間分頁被拆掉（切走分頁或換股），失敗提示照樣出現', (tester) async {
    final fetcher = MockNewsFetcher();
    final gate = Completer<NewsFetchOutcome>();
    when(() => fetcher.fetch()).thenAnswer((_) => gate.future);
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await tester.pumpWidget(
      buildProviderTestApp(
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) =>
                visible ? const StockNewsTab(symbol: '9901') : const SizedBox(),
          ),
        ),
        overrides: [
          stockNewsProvider.overrideWith((ref, s) async => data([news('a')])),
          newsFetcherProvider.overrideWithValue(fetcher),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('stockNews.refresh'));
    await tester.pump();
    show.value = false; // 切到別的分頁
    await tester.pump();
    expect(find.byType(StockNewsTab), findsNothing, reason: '前提：分頁已拆掉');

    gate.complete(const NewsFetchOutcome(totalSources: 5, failedSources: 5));
    await tester.pump();
    await tester.pump();

    expect(find.text('news.fetchAllFailed'), findsOneWidget);
  });
}

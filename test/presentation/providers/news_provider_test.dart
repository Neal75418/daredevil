import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/models/news_feed.dart';
import 'package:daredevil/domain/repositories/news_repository.dart'
    show NewsSyncResult;
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockNewsRepository extends Mock implements NewsRepository {}

// ==========================================
// Test Helpers
// ==========================================

NewsItemEntry createNewsEntry({
  required String id,
  required String title,
  String source = '鉅亨網',
  DateTime? publishedAt,
}) {
  return NewsItemEntry(
    id: id,
    title: title,
    source: source,
    url: 'https://example.com/$id',
    category: 'OTHER',
    publishedAt: publishedAt ?? DateTime(2026, 2, 13),
    fetchedAt: DateTime(2026, 2, 13),
  );
}

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockNewsRepository mockNewsRepo;
  late ProviderContainer container;

  setUp(() {
    mockDb = MockAppDatabase();
    mockNewsRepo = MockNewsRepository();

    when(
      () => mockDb.getWatchlistAndHoldingSymbols(),
    ).thenAnswer((_) async => {});

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        newsRepositoryProvider.overrideWithValue(mockNewsRepo),
        newsLinkMatcherProvider.overrideWith(
          (ref) async => StockNameMatcher.forNewsLinks(
            [stock('9901', '甲乙'), stock('9902', '丙丁')],
            excludedNames: const {},
            nonCompanyPhrases: const {},
            extraAliases: const {},
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // ==========================================
  // NewsSource
  // ==========================================

  group('NewsSource', () {
    test('all matches every source', () {
      expect(NewsSource.all.matches('鉅亨網'), isTrue);
      expect(NewsSource.all.matches('Yahoo財經'), isTrue);
      expect(NewsSource.all.matches('anything'), isTrue);
    });

    test('announcement matches only 重大訊息', () {
      expect(NewsSource.announcement.matches('重大訊息'), isTrue);
      expect(NewsSource.announcement.matches('Yahoo財經'), isFalse);
      expect(NewsSource.announcement.matches('鉅亨網'), isFalse);
    });

    test('yahoo matches only Yahoo財經', () {
      expect(NewsSource.yahoo.matches('Yahoo財經'), isTrue);
      expect(NewsSource.yahoo.matches('鉅亨網'), isFalse);
    });

    test('cnyes matches only 鉅亨網', () {
      expect(NewsSource.cnyes.matches('鉅亨網'), isTrue);
      expect(NewsSource.cnyes.matches('Yahoo財經'), isFalse);
    });

    test('cna matches only 中央社', () {
      expect(NewsSource.cna.matches('中央社'), isTrue);
      expect(NewsSource.cna.matches('鉅亨網'), isFalse);
    });

    test('udn matches only 經濟日報', () {
      expect(NewsSource.udn.matches('經濟日報'), isTrue);
      expect(NewsSource.udn.matches('中央社'), isFalse);
    });

    test('ltn matches only 自由財經', () {
      expect(NewsSource.ltn.matches('自由財經'), isTrue);
      expect(NewsSource.ltn.matches('經濟日報'), isFalse);
    });
  });

  // ==========================================
  // NewsState
  // ==========================================

  group('NewsState', () {
    test('has correct default values', () {
      final state = NewsState();

      expect(state.allNews, isEmpty);
      expect(state.relatedStocksByNewsId, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.filter, NewsFilter.all);
    });

    test('filteredNews returns all when source is all', () {
      final news = [
        createNewsEntry(id: '1', title: 'A', source: '鉅亨網'),
        createNewsEntry(id: '2', title: 'B', source: 'Yahoo財經'),
      ];
      final state = NewsState(allNews: news);

      expect(state.filteredNews, hasLength(2));
    });

    test('filteredNews filters by selected source', () {
      final news = [
        createNewsEntry(id: '1', title: 'A', source: '鉅亨網'),
        createNewsEntry(id: '2', title: 'B', source: 'Yahoo財經'),
        createNewsEntry(id: '3', title: 'C', source: '鉅亨網'),
      ];
      final state = NewsState(
        allNews: news,
        filter: const SourceNewsFilter(NewsSource.cnyes),
      );

      expect(state.filteredNews, hasLength(2));
      expect(state.filteredNews.every((n) => n.source == '鉅亨網'), isTrue);
    });

    test('sourceCounts counts per source', () {
      final news = [
        createNewsEntry(id: '1', title: 'A', source: '鉅亨網'),
        createNewsEntry(id: '2', title: 'B', source: 'Yahoo財經'),
        createNewsEntry(id: '3', title: 'C', source: '鉅亨網'),
      ];
      final state = NewsState(allNews: news);

      expect(state.sourceCounts[NewsSource.all], 3);
      expect(state.sourceCounts[NewsSource.cnyes], 2);
      expect(state.sourceCounts[NewsSource.yahoo], 1);
      expect(state.sourceCounts[NewsSource.cna], 0);
      expect(state.sourceCounts[NewsSource.udn], 0);
      expect(state.sourceCounts[NewsSource.ltn], 0);
    });

    test('dedup merges same-day same-title across sources, keeps earliest', () {
      final news = [
        createNewsEntry(
          id: 'yahoo-copy',
          title: '台股上漲893點收45631點',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 15, 15, 30),
        ),
        createNewsEntry(
          id: 'cna-original',
          title: '台股上漲893點收45631點',
          source: '中央社',
          publishedAt: DateTime(2026, 7, 15, 14, 0),
        ),
      ];
      final state = NewsState(allNews: news);

      expect(state.filteredNews, hasLength(1));
      expect(state.filteredNews.single.id, 'cna-original');
    });

    test('dedup keeps same-title news published on different days', () {
      final news = [
        createNewsEntry(
          id: 'd1',
          title: '7月電子期金融期齊漲',
          publishedAt: DateTime(2026, 7, 14, 15, 0),
        ),
        createNewsEntry(
          id: 'd2',
          title: '7月電子期金融期齊漲',
          publishedAt: DateTime(2026, 7, 15, 15, 0),
        ),
      ];
      final state = NewsState(allNews: news);

      expect(state.filteredNews, hasLength(2));
    });

    test('dedup 剝除聚合器加掛的【…】前綴（同日同文合併）', () {
      final news = [
        createNewsEntry(
          id: 'yahoo-branded',
          title: '【台股盤中】台股暫守45000點　盤中跌勢收斂',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 16, 11, 30),
        ),
        createNewsEntry(
          id: 'cna-original',
          title: '台股暫守45000點　盤中跌勢收斂',
          source: '中央社',
          publishedAt: DateTime(2026, 7, 16, 11, 0),
        ),
      ];
      final state = NewsState(allNews: news);

      expect(state.filteredNews, hasLength(1));
      expect(state.filteredNews.single.id, 'cna-original');
    });

    test('dedup normalizes whitespace variants（含全形空白）', () {
      final news = [
        createNewsEntry(
          id: 'w1',
          title: '台積電　法說會登場',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 15, 16, 0),
        ),
        createNewsEntry(
          id: 'w2',
          title: '台積電 法說會登場',
          source: '中央社',
          publishedAt: DateTime(2026, 7, 15, 15, 0),
        ),
      ];
      final state = NewsState(allNews: news);

      expect(state.filteredNews, hasLength(1));
      expect(state.filteredNews.single.id, 'w2');
    });

    test(
      'dedup hides aggregator copy in all view but keeps it in its own source view',
      () {
        final news = [
          createNewsEntry(
            id: 'yahoo-copy',
            title: '三大法人買超台股201.92億元',
            source: 'Yahoo財經',
            publishedAt: DateTime(2026, 7, 15, 15, 30),
          ),
          createNewsEntry(
            id: 'cna-original',
            title: '三大法人買超台股201.92億元',
            source: '中央社',
            publishedAt: DateTime(2026, 7, 15, 14, 0),
          ),
        ];
        final yahooView = NewsState(
          allNews: news,
          filter: const SourceNewsFilter(NewsSource.yahoo),
        );

        expect(yahooView.filteredNews, hasLength(1));
        expect(yahooView.filteredNews.single.id, 'yahoo-copy');
      },
    );

    test('sourceCounts.all reflects deduplicated count', () {
      final news = [
        createNewsEntry(
          id: '1',
          title: '重複新聞',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 15, 15, 0),
        ),
        createNewsEntry(
          id: '2',
          title: '重複新聞',
          source: '中央社',
          publishedAt: DateTime(2026, 7, 15, 14, 0),
        ),
        createNewsEntry(
          id: '3',
          title: '獨家新聞',
          source: '鉅亨網',
          publishedAt: DateTime(2026, 7, 15, 13, 0),
        ),
      ];
      final state = NewsState(allNews: news);

      expect(state.sourceCounts[NewsSource.all], 2);
      expect(state.sourceCounts[NewsSource.yahoo], 1);
      expect(state.sourceCounts[NewsSource.cna], 1);
    });

    test('dedup merges same-source same-day duplicates', () {
      final news = [
        createNewsEntry(
          id: 's1',
          title: '同源重發',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 15, 15, 0),
        ),
        createNewsEntry(
          id: 's2',
          title: '同源重發',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 15, 14, 0),
        ),
      ];
      final state = NewsState(
        allNews: news,
        filter: const SourceNewsFilter(NewsSource.yahoo),
      );

      expect(state.filteredNews, hasLength(1));
      expect(state.filteredNews.single.id, 's2');
    });

    test('dedup result stays sorted by publishedAt desc', () {
      final news = [
        createNewsEntry(
          id: 'old-original',
          title: '重複新聞',
          source: '中央社',
          publishedAt: DateTime(2026, 7, 15, 9, 0),
        ),
        createNewsEntry(
          id: 'newer-unique',
          title: '較新的獨家',
          source: '鉅亨網',
          publishedAt: DateTime(2026, 7, 15, 12, 0),
        ),
        createNewsEntry(
          id: 'yahoo-copy',
          title: '重複新聞',
          source: 'Yahoo財經',
          publishedAt: DateTime(2026, 7, 15, 15, 0),
        ),
      ];
      final state = NewsState(allNews: news);

      expect(
        state.filteredNews.map((n) => n.id).toList(),
        equals(['newer-unique', 'old-original']),
      );
    });

    test('copyWith preserves unset values', () {
      final state = NewsState(isLoading: true);
      final copied = state.copyWith();
      expect(copied.isLoading, isTrue);
    });

    test('copyWith with sentinel handles error correctly', () {
      final state = NewsState(error: 'old error');

      final preserved = state.copyWith();
      expect(preserved.error, 'old error');

      final cleared = state.copyWith(error: null);
      expect(cleared.error, isNull);
    });
    test('自選篩選：相關股票有自選或持股的新聞，去重後計數', () {
      final news = [
        createNewsEntry(id: 'a', title: '甲乙營收', source: '鉅亨網'),
        createNewsEntry(id: 'b', title: '甲乙營收', source: 'Yahoo財經'),
        createNewsEntry(id: 'c', title: '丙丁公告'),
        createNewsEntry(id: 'd', title: '大盤收高'),
      ];
      final state = NewsState(
        allNews: news,
        relatedStocksByNewsId: const {
          'a': ['9901'],
          'b': ['9901'],
          'c': ['9902'],
        },
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );

      expect(state.filteredNews.map((n) => n.id), hasLength(1));
      expect(state.mineCount, 1);
    });

    test('自選篩選可再疊加搜尋', () {
      final state = NewsState(
        allNews: [
          createNewsEntry(id: 'a', title: '甲乙營收'),
          createNewsEntry(id: 'b', title: '甲乙法說'),
        ],
        relatedStocksByNewsId: const {
          'a': ['9901'],
          'b': ['9901'],
        },
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
        searchQuery: '法說',
      );
      expect(state.filteredNews.map((n) => n.id), ['b']);
    });

    test('自選篩選下自選與持股的標籤排前，其他篩選維持原順序', () {
      const related = {
        'a': ['9902', '9903', '9901'],
      };
      final mine = NewsState(
        relatedStocksByNewsId: related,
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );
      final all = NewsState(
        relatedStocksByNewsId: related,
        mySymbols: const {'9901'},
      );
      expect(mine.relatedStocksOf('a'), ['9901', '9902', '9903']);
      expect(all.relatedStocksOf('a'), ['9902', '9903', '9901']);
      expect(all.relatedStocksOf('zzz'), isEmpty);
    });

    test('NewsFilter 相等性（篩選列每次 build 都新建實例，選中狀態靠 ==）', () {
      // 用非 const 實例：const 會被合併成同一物件，拿掉 == 覆寫也照樣相等
      final allSource = NewsSource.values.first;
      expect(SourceNewsFilter(allSource), NewsFilter.all);
      expect(
        SourceNewsFilter(NewsSource.values[2]),
        SourceNewsFilter(NewsSource.values[2]),
      );
      expect(
        SourceNewsFilter(NewsSource.values[2]),
        isNot(SourceNewsFilter(NewsSource.values[3])),
      );
      expect(NewsFilter.mine, isNot(NewsFilter.all));
    });
  });

  // ==========================================
  // NewsNotifier
  // ==========================================

  group('NewsNotifier', () {
    test('initial state is empty', () {
      final state = container.read(newsProvider);
      expect(state.allNews, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('loadData sets news from repository', () async {
      final news = [
        createNewsEntry(id: '1', title: '新聞一'),
        createNewsEntry(id: '2', title: '新聞二'),
      ];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => news);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});

      final notifier = container.read(newsProvider.notifier);
      await notifier.loadData();

      final state = container.read(newsProvider);
      expect(state.allNews, hasLength(2));
      expect(state.isLoading, isFalse);
    });

    test('loadData sets empty when no news', () async {
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);

      final notifier = container.read(newsProvider.notifier);
      await notifier.loadData();

      final state = container.read(newsProvider);
      expect(state.allNews, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('loadData handles error gracefully', () async {
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenThrow(Exception('Network error'));

      final notifier = container.read(newsProvider.notifier);
      await notifier.loadData();

      final state = container.read(newsProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
    });

    test('setFilter changes selected filter', () {
      final notifier = container.read(newsProvider.notifier);
      notifier.setFilter(const SourceNewsFilter(NewsSource.yahoo));

      final state = container.read(newsProvider);
      expect(state.filter, const SourceNewsFilter(NewsSource.yahoo));
    });

    test('refresh syncs RSS before reloading local data', () async {
      final callOrder = <String>[];
      when(() => mockNewsRepo.syncNews()).thenAnswer((_) async {
        callOrder.add('sync');
        return const NewsSyncResult(itemsAdded: 3, errors: []);
      });
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async {
        callOrder.add('load');
        return [createNewsEntry(id: '1', title: '新聞一')];
      });
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});

      final notifier = container.read(newsProvider.notifier);
      await notifier.refresh();

      expect(callOrder, equals(['sync', 'load']));
      final state = container.read(newsProvider);
      expect(state.allNews, hasLength(1));
      expect(state.error, isNull);
    });

    test('refresh still loads local data when RSS sync throws', () async {
      when(() => mockNewsRepo.syncNews()).thenThrow(Exception('offline'));
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => [createNewsEntry(id: '1', title: '新聞一')]);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});

      final notifier = container.read(newsProvider.notifier);
      await notifier.refresh();

      final state = container.read(newsProvider);
      expect(state.allNews, hasLength(1));
      expect(state.error, isNull);
      expect(state.isLoading, isFalse);
    });

    test('refresh ignores re-entrant calls while in flight', () async {
      var syncCalls = 0;
      when(() => mockNewsRepo.syncNews()).thenAnswer((_) async {
        syncCalls++;
        await Future<void>.delayed(Duration.zero);
        return const NewsSyncResult(itemsAdded: 0, errors: []);
      });
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);

      final notifier = container.read(newsProvider.notifier);
      await Future.wait([notifier.refresh(), notifier.refresh()]);

      expect(syncCalls, 1);
    });

    test(
      'refresh resets in-flight flag so sequential calls sync again',
      () async {
        var syncCalls = 0;
        when(() => mockNewsRepo.syncNews()).thenAnswer((_) async {
          syncCalls++;
          return const NewsSyncResult(itemsAdded: 0, errors: []);
        });
        when(
          () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
        ).thenAnswer((_) async => []);

        final notifier = container.read(newsProvider.notifier);
        await notifier.refresh();
        await notifier.refresh();

        expect(syncCalls, 2);
      },
    );
    test('loadData 合併代號對應與簡稱比對、讀自選名單', () async {
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer(
        (_) async => [
          createNewsEntry(id: 'n1', title: '甲乙營收創新高'),
          createNewsEntry(id: 'n2', title: '某公司公告'),
        ],
      );
      when(() => mockDb.getNewsStockMappingsBatch(any())).thenAnswer(
        (_) async => {
          'n2': ['9930'],
        },
      );
      when(
        () => mockDb.getWatchlistAndHoldingSymbols(),
      ).thenAnswer((_) async => {'9901'});

      await container.read(newsProvider.notifier).loadData();

      final s = container.read(newsProvider);
      expect(s.relatedStocksByNewsId, {
        'n1': ['9901'],
        'n2': ['9930'],
      });
      expect(s.mySymbols, {'9901'});
    });

    test('reloadMySymbols 只重讀名單、不重抓新聞', () async {
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);
      final notifier = container.read(newsProvider.notifier);
      await notifier.loadData();
      when(
        () => mockDb.getWatchlistAndHoldingSymbols(),
      ).thenAnswer((_) async => {'9902'});
      clearInteractions(mockNewsRepo);

      await notifier.reloadMySymbols();

      expect(container.read(newsProvider).mySymbols, {'9902'});
      verifyNever(() => mockNewsRepo.getRecentNews(days: any(named: 'days')));
    });

    test('較早開始但較晚完成的載入不覆蓋較新的結果', () async {
      final first = Completer<List<NewsItemEntry>>();
      final second = Completer<List<NewsItemEntry>>();
      final answers = [first, second];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) => answers.removeAt(0).future);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      final f2 = notifier.loadData();
      second.complete([createNewsEntry(id: 'new', title: '新')]);
      await f2;
      first.complete([createNewsEntry(id: 'old', title: '舊')]);
      await f1;

      expect(container.read(newsProvider).allNews.map((n) => n.id), ['new']);
    });

    test('較舊的載入晚一步失敗，不把錯誤蓋到較新的結果上', () async {
      final first = Completer<List<NewsItemEntry>>();
      final answers = [
        first,
        Completer<List<NewsItemEntry>>()
          ..complete([createNewsEntry(id: 'new', title: '新')]),
      ];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) => answers.removeAt(0).future);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      await notifier.loadData();
      first.completeError(Exception('db locked'));
      await f1;

      final s = container.read(newsProvider);
      expect(s.allNews.map((n) => n.id), ['new']);
      expect(s.error, isNull);
    });

    test('較舊的載入回空清單也不覆蓋較新的結果', () async {
      final first = Completer<List<NewsItemEntry>>();
      final answers = [
        first,
        Completer<List<NewsItemEntry>>()
          ..complete([createNewsEntry(id: 'new', title: '新')]),
      ];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) => answers.removeAt(0).future);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      await notifier.loadData();
      first.complete([]);
      await f1;

      expect(container.read(newsProvider).allNews.map((n) => n.id), ['new']);
    });

    test('較舊的載入已過第一道檢查、卡在對應查詢時被超越，也不覆蓋', () async {
      // 第一次載入的 getNewsStockMappingsBatch 卡住，期間第二次載入完成；
      // 釋放後第一次要被第二道世代檢查擋下
      final gate = Completer<Map<String, List<String>>>();
      final mapAnswers = [
        gate,
        Completer<Map<String, List<String>>>()..complete({}),
      ];
      final newsAnswers = [
        [createNewsEntry(id: 'old', title: '舊')],
        [createNewsEntry(id: 'new', title: '新')],
      ];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => newsAnswers.removeAt(0));
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) => mapAnswers.removeAt(0).future);
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      await pumpEventQueue(); // 讓第一次走到對應查詢
      verify(() => mockDb.getNewsStockMappingsBatch(any())).called(1);
      await notifier.loadData();
      gate.complete({});
      await f1;

      expect(container.read(newsProvider).allNews.map((n) => n.id), ['new']);
    });

    test('onNewsDataChanged：自己的 refresh 進行中不重複載入，其他時候載入', () async {
      final gate = Completer<NewsSyncResult>();
      when(() => mockNewsRepo.syncNews()).thenAnswer((_) => gate.future);
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);
      final notifier = container.read(newsProvider.notifier);

      final refreshing = notifier.refresh();
      notifier.onNewsDataChanged(); // refresh 進行中：略過
      gate.complete(const NewsSyncResult(itemsAdded: 0, errors: []));
      await refreshing;
      verify(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).called(1); // 只有 refresh 自己的那次

      notifier.onNewsDataChanged();
      await pumpEventQueue();
      verify(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).called(1);
    });

    test('refresh 回傳抓取結果（部分失敗）', () async {
      when(() => mockNewsRepo.syncNews()).thenAnswer(
        (_) async => NewsSyncResult(
          itemsAdded: 1,
          errors: [
            NewsFeedError(
              sourceName: '中央社',
              url: 'https://example.com',
              error: 'timeout',
              timestamp: DateTime(2026, 10, 6),
            ),
          ],
        ),
      );
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);

      final o = await container.read(newsProvider.notifier).refresh();

      expect(o?.failedSources, 1);
      expect(o?.partiallyFailed, isTrue);
    });
  });
}

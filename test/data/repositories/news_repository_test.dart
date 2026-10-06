import 'package:daredevil/data/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:daredevil/data/remote/rss_parser.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/repositories/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/portfolio_data_builders.dart';

class MockAppDatabase extends Mock implements AppDatabase {
  @override
  Future<T> transaction<T>(Future<T> Function() action, {bool? requireNew}) {
    return action();
  }

  @override
  Future<void> batch(Function(Batch) callback) async {
    // No-op: skip actual batch operations in tests
  }
}

class MockRssParser extends Mock implements RssParser {}

class MockTwseClient extends Mock implements TwseClient {}

void main() {
  late MockAppDatabase mockDb;
  late MockRssParser mockRssParser;
  late NewsRepository repo;

  setUp(() {
    mockDb = MockAppDatabase();
    mockRssParser = MockRssParser();
    repo = NewsRepository(database: mockDb, rssParser: mockRssParser);
  });

  // ==========================================
  // syncNews
  // ==========================================
  group('syncNews', () {
    test('returns 0 items when parse result is empty', () async {
      when(
        () => mockRssParser.parseAllFeeds(any()),
      ).thenAnswer((_) async => const RssParseResult(items: [], errors: []));

      final result = await repo.syncNews();

      expect(result.itemsAdded, equals(0));
      expect(result.hasErrors, isFalse);
    });

    test('returns errors from parse result', () async {
      when(() => mockRssParser.parseAllFeeds(any())).thenAnswer(
        (_) async => RssParseResult(
          items: [],
          errors: [
            NewsFeedError(
              sourceName: 'TestFeed',
              url: 'https://example.com/rss',
              error: 'Connection timeout',
              timestamp: DateTime(2025, 1, 15),
            ),
          ],
        ),
      );

      final result = await repo.syncNews();

      expect(result.itemsAdded, equals(0));
      expect(result.hasErrors, isTrue);
      expect(result.errors.length, equals(1));
    });

    test('inserts news and stock mappings via batch', () async {
      when(() => mockRssParser.parseAllFeeds(any())).thenAnswer(
        (_) async => RssParseResult(
          items: [
            RssNewsItem(
              id: 'news-1',
              source: 'TestFeed',
              title: '台積電 2330 營收創新高',
              url: 'https://example.com/1',
              publishedAt: DateTime(2025, 1, 15),
              category: 'STOCK',
            ),
          ],
          errors: [],
        ),
      );
      when(() => mockDb.getAllActiveStocks()).thenAnswer(
        (_) async => [createTestStockMaster(symbol: '2330', name: '台積電')],
      );
      final result = await repo.syncNews();

      expect(result.itemsAdded, equals(1));
    });

    test('filters stock codes not in active stocks', () async {
      when(() => mockRssParser.parseAllFeeds(any())).thenAnswer(
        (_) async => RssParseResult(
          items: [
            RssNewsItem(
              id: 'news-1',
              source: 'TestFeed',
              title: '9999 不存在的股票',
              url: 'https://example.com/1',
              publishedAt: DateTime(2025, 1, 15),
              category: 'STOCK',
            ),
          ],
          errors: [],
        ),
      );
      when(
        () => mockDb.getAllActiveStocks(),
      ).thenAnswer((_) async => <StockMasterEntry>[]);

      final result = await repo.syncNews();

      // News item added, but stock mapping should not be created for 9999
      expect(result.itemsAdded, equals(1));
    });
  });

  // ==========================================
  // NewsSyncResult
  // ==========================================
  group('NewsSyncResult', () {
    test('hasErrors returns true when errors present', () {
      final result = NewsSyncResult(
        itemsAdded: 5,
        errors: [
          NewsFeedError(
            sourceName: 'Feed',
            url: 'https://example.com',
            error: 'Timeout',
            timestamp: DateTime(2025, 1, 15),
          ),
        ],
      );

      expect(result.hasErrors, isTrue);
    });
  });

  // ==========================================
  // RssNewsItem.extractStockCodes
  // ==========================================
  group('RssNewsItem.extractStockCodes', () {
    test('extracts 4-digit stock codes with explicit context', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '台積電(2330)營收創新高，聯電(2303-TW)跟進',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), equals(['2330', '2303']));
    });

    test('skips bare 4-digit codes without stock context（股價/點數撞代號）', () {
      // 台積電股價進入 2xxx 區間後，行情文的價格數字會撞整個 2xxx 代號空間
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '台股收漲893點收復4萬7關卡　台積電大漲95元報2505',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), isEmpty);
    });

    test('mixed title keeps only the contextualized code', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '台積電(2330)漲95元報2505　台股飆升1467點',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), equals(['2330']));
    });

    test('zero-leading 4-digit ETF codes exempt from context requirement', () {
      // 0050/0056 等 ETF 代號以 0 開頭，不會與股價/年份/點數衝突
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '0050 狂掃4500億元居冠　0056年化殖利率跌破4％',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), equals(['0050', '0056']));
    });

    test('returns empty for no stock codes', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '台股大盤走勢分析',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'MARKET',
      );

      expect(item.extractStockCodes(), isEmpty);
    });

    test('skips year-range numbers without stock context（避免 2027年 撞代號）', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '預期2027年很不一樣，看好2027大爆發',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), isEmpty);
    });

    test('keeps year-range code when in stock context（括號 / -TW）', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '大成鋼(2027-TW)目標價調升至52元',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), equals(['2027']));
    });

    test('bare code and bare year both skipped; bracketed code kept', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '台積電(2330)看好2027大爆發，目標價2415元',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), equals(['2330']));
    });

    test('5-6 digit ETF codes unaffected by year filter', () {
      final item = RssNewsItem(
        id: '1',
        source: 'Test',
        title: '00919 配息創新高',
        url: 'https://example.com',
        publishedAt: DateTime(2025, 1, 15),
        category: 'STOCK',
      );

      expect(item.extractStockCodes(), equals(['00919']));
    });
  });

  group('syncMaterialInfo', () {
    late MockTwseClient client;
    late AppDatabase db;
    late NewsRepository repo2;

    TwseMaterialInfo mat({required String code, String subject = '公告'}) {
      return TwseMaterialInfo.fromJson({
        '發言日期': '1150723',
        '發言時間': '151812',
        '公司代號': code,
        '公司名稱': 'X',
        '主旨 ': subject,
        '說明': '',
      });
    }

    setUp(() async {
      client = MockTwseClient();
      db = AppDatabase.forTesting();
      await db.upsertStocks([
        for (final s in ['9901', '9902', '9903', '9904'])
          StockMasterCompanion.insert(symbol: s, name: '測$s', market: 'TWSE'),
      ]);
      repo2 = NewsRepository(
        database: db,
        rssParser: mockRssParser,
        twseClient: client,
      );
    });

    tearDown(() => db.close());

    test('只收自選∪持股（數量 > 0）、穩定 id、寫入新聞與股票關聯', () async {
      await db.addToWatchlist('9901');
      await db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: '9902',
          quantity: const Value(1000),
        ),
      );
      await db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: '9903',
          quantity: const Value(0),
        ),
      );
      when(() => client.getMaterialInformation()).thenAnswer(
        (_) async => [
          mat(code: '9901', subject: '受邀參加法人說明會'),
          mat(code: '9902', subject: '董事會決議'),
          mat(code: '9903', subject: '已清倉的公告'),
          mat(code: '9904', subject: '非自選公告'),
        ],
      );

      final count = await repo2.syncMaterialInfo();

      expect(count, 2);
      final items = await db.select(db.newsItem).get();
      expect(items.map((n) => n.id).toSet(), {
        'mops_9901_1150723_151812',
        'mops_9902_1150723_151812',
      });
      expect(items.every((n) => n.source == '重大訊息'), isTrue);
      final maps = await db.select(db.newsStockMap).get();
      expect(maps.map((m) => m.symbol).toSet(), {'9901', '9902'});
    });

    test('沒有自選也沒有持股時不打 API、回 0', () async {
      expect(await repo2.syncMaterialInfo(), 0);
      verifyNever(() => client.getMaterialInformation());
    });

    test('未注入 client 回 0', () async {
      final bare = NewsRepository(database: db, rssParser: mockRssParser);
      expect(await bare.syncMaterialInfo(), 0);
    });
  });
}

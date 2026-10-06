import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class FixedClock implements AppClock {
  const FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

NewsItemEntry news(String id, String title, DateTime at) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: title,
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: at,
  fetchedAt: at,
);

void main() {
  late MockAppDatabase db;
  late ProviderContainer container;
  final now = DateTime(2026, 10, 6, 15);

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() {
    db = MockAppDatabase();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appClockProvider.overrideWithValue(FixedClock(now)),
        newsLinkMatcherProvider.overrideWith(
          (ref) async => StockNameMatcher.forNewsLinks(
            [
              stock('9901', '甲乙'),
              stock('9902', '常見'),
              stock('9907', '測試電子'),
              stock('9908', '測試'),
            ],
            excludedNames: const {'常見'},
            nonCompanyPhrases: const {},
            extraAliases: const {},
          ),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  void stubCandidates(
    List<NewsItemEntry> items,
    Map<String, List<String>> codeMap,
  ) {
    when(
      () => db.getNewsCandidatesForStock(
        symbol: any(named: 'symbol'),
        names: any(named: 'names'),
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => items);
    when(
      () => db.getNewsStockMappingsBatch(any()),
    ).thenAnswer((_) async => codeMap);
  }

  test('代號對應一律收；名稱候選要比對確認（測試電子不算測試）', () async {
    final t = DateTime(2026, 10, 6, 9);
    stubCandidates(
      [
        news('code', '某公司公告', t),
        news('name', '測試營收', t),
        news('longer', '測試電子營收', t),
      ],
      {
        'code': ['9908'],
      },
    );

    final r = await container.read(stockNewsProvider('9908').future);

    expect(r.items.map((n) => n.id).toSet(), {'code', 'name'});
    expect(r.nameStatus, StockNameStatus.matched);
  });

  test('簡稱被排除的股票仍列出代號對應的新聞', () async {
    final t = DateTime(2026, 10, 6, 9);
    stubCandidates(
      [news('code', '常見(9902)目標價調升', t)],
      {
        'code': ['9902'],
      },
    );

    final r = await container.read(stockNewsProvider('9902').future);

    expect(r.items.map((n) => n.id), ['code']);
    expect(r.nameStatus, StockNameStatus.excluded);
    verify(
      () => db.getNewsCandidatesForStock(
        symbol: '9902',
        names: const [],
        since: any(named: 'since'),
      ),
    ).called(1);
  });

  test('股票標籤只列其他股票；截止點是 30 天前', () async {
    final t = DateTime(2026, 10, 6, 9);
    stubCandidates([news('n', '甲乙與測試電子齊漲', t)], const {});

    final r = await container.read(stockNewsProvider('9901').future);

    expect(r.otherStocksByNewsId['n'], ['9907']);
    verify(
      () => db.getNewsCandidatesForStock(
        symbol: '9901',
        names: ['甲乙'],
        since: now.subtract(const Duration(days: 30)),
      ),
    ).called(1);
  });

  test('不在清單的股票：只靠代號、狀態 notListed', () async {
    stubCandidates(const [], const {});
    final r = await container.read(stockNewsProvider('9999').future);
    expect(r.nameStatus, StockNameStatus.notListed);
  });

  test('同日同標題去重', () async {
    stubCandidates([
      news('a', '甲乙營收', DateTime(2026, 10, 6, 10)),
      news('b', '甲乙營收', DateTime(2026, 10, 6, 9)),
    ], const {});
    final r = await container.read(stockNewsProvider('9901').future);
    expect(r.items.map((n) => n.id), ['b']);
  });

  test('新聞資料版本遞增後重讀', () async {
    stubCandidates(const [], const {});
    final sub = container.listen(stockNewsProvider('9901'), (_, _) {});
    addTearDown(sub.close);
    await container.read(stockNewsProvider('9901').future);

    container.read(newsDataVersionProvider.notifier).bump();
    await container.read(stockNewsProvider('9901').future);

    verify(
      () => db.getNewsCandidatesForStock(
        symbol: '9901',
        names: any(named: 'names'),
        since: any(named: 'since'),
      ),
    ).called(2);
  });
}

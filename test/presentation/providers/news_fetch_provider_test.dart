import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/models/news_feed.dart';
import 'package:daredevil/domain/repositories/news_repository.dart'
    show NewsSyncResult;
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class MockNewsRepository extends Mock implements NewsRepository {}

NewsFeedError feedError(String source) => NewsFeedError(
  sourceName: source,
  url: 'https://example.com/$source',
  error: 'timeout',
  timestamp: DateTime(2026, 10, 6),
);

void main() {
  late MockNewsRepository repo;
  late ProviderContainer container;
  final total = NewsFeedSource.defaultSources.length;

  setUp(() {
    repo = MockNewsRepository();
    container = ProviderContainer(
      overrides: [newsRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() => container.dispose());

  test('併發兩次只抓一次、拿到同一個結果、版本只遞增一次', () async {
    final gate = Completer<NewsSyncResult>();
    when(() => repo.syncNews()).thenAnswer((_) => gate.future);
    final fetcher = container.read(newsFetcherProvider);

    final a = fetcher.fetch();
    final b = fetcher.fetch();
    gate.complete(const NewsSyncResult(itemsAdded: 1, errors: []));

    final results = await Future.wait([a, b]);
    expect(identical(results[0], results[1]), isTrue);
    verify(() => repo.syncNews()).called(1);
    expect(container.read(newsDataVersionProvider), 1);
  });

  test('依序兩次就抓兩次、版本遞增兩次', () async {
    when(
      () => repo.syncNews(),
    ).thenAnswer((_) async => const NewsSyncResult(itemsAdded: 0, errors: []));
    final fetcher = container.read(newsFetcherProvider);

    await fetcher.fetch();
    await fetcher.fetch();

    verify(() => repo.syncNews()).called(2);
    expect(container.read(newsDataVersionProvider), 2);
  });

  test('部分來源失敗：同一來源多筆錯誤只算一個', () async {
    when(() => repo.syncNews()).thenAnswer(
      (_) async => NewsSyncResult(
        itemsAdded: 3,
        errors: [feedError('中央社'), feedError('中央社'), feedError('自由財經')],
      ),
    );

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.failedSources, 2);
    expect(o.partiallyFailed, isTrue);
    expect(o.allFailed, isFalse);
  });

  test('全部來源失敗', () async {
    when(() => repo.syncNews()).thenAnswer(
      (_) async => NewsSyncResult(
        itemsAdded: 0,
        errors: [
          for (final s in NewsFeedSource.defaultSources) feedError(s.name),
        ],
      ),
    );

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.allFailed, isTrue);
    expect(o.partiallyFailed, isFalse);
  });

  test('syncNews 拋例外：當成全部失敗，版本照樣遞增', () async {
    when(() => repo.syncNews()).thenThrow(Exception('db locked'));

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.failedSources, total);
    expect(o.allFailed, isTrue);
    expect(container.read(newsDataVersionProvider), 1);
  });

  test('全部成功：沒有失敗', () async {
    when(
      () => repo.syncNews(),
    ).thenAnswer((_) async => const NewsSyncResult(itemsAdded: 5, errors: []));

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.allFailed, isFalse);
    expect(o.partiallyFailed, isFalse);
  });
}

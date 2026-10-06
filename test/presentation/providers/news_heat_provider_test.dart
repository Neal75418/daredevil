import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_heat_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

import '../../helpers/warning_data_generators.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockNewsRepository extends Mock implements NewsRepository {}

NewsItemEntry news(String id, String title, DateTime publishedAt) =>
    NewsItemEntry(
      id: id,
      source: '鉅亨網',
      title: title,
      url: 'https://example.com/$id',
      category: 'OTHER',
      publishedAt: publishedAt,
      fetchedAt: publishedAt,
    );

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  industry: '電子工業',
  isActive: true,
  updatedAt: DateTime(2026, 7, 15),
);

ModeRecommendation rec(String symbol) => ModeRecommendation(
  symbol: symbol,
  rank: 1,
  modeScoreShort: 20,
  modeScoreLong: 20,
  reasons: const [],
);

void main() {
  late MockAppDatabase mockDb;
  late MockNewsRepository mockNewsRepo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockNewsRepo = MockNewsRepository();
    when(
      () => mockDb.getAllActiveStocks(),
    ).thenAnswer((_) async => [stock('2330', '台積電'), stock('2408', '南亞科')]);
    when(
      () => mockDb.getActiveWarningsMapBatch(any()),
    ).thenAnswer((_) async => {});
    when(() => mockDb.getLatestPricesBatch(any())).thenAnswer((_) async => {});
    when(() => mockNewsRepo.getRecentNews(days: any(named: 'days'))).thenAnswer(
      (_) async => [
        news('a', '台積電法說會', DateTime.now()),
        news('b', '記憶體漲價 南亞科受惠', DateTime.now()),
        news('c', '南亞科獲利創高', DateTime.now()),
      ],
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        newsRepositoryProvider.overrideWithValue(mockNewsRepo),
        // 三模式：南亞科在回檔（weaknessObserve）
        for (final m in ScoringMode.userFacingModes)
          modeRecommendationsProvider(m).overrideWith(
            (ref) async =>
                m == ScoringMode.weaknessObserve ? [rec('2408')] : [],
          ),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('焦點股按提及數排序並帶名稱', () async {
    final r = await container.read(newsHeatProvider.future);
    expect(r.stocks.first.symbol, '2408'); // 2 篇 > 台積電 1 篇
    expect(r.stockNames['2408'], '南亞科');
  });

  test('題材熱度與成分股', () async {
    final r = await container.read(newsHeatProvider.future);
    final memory = r.themes.firstWhere((t) => t.theme == '記憶體');
    expect(memory.articles7d, 1);
    expect(memory.topStocks, contains('2408'));
  });

  test('三模式交叉：回檔股標注 weaknessObserve', () async {
    final r = await container.read(newsHeatProvider.future);
    expect(r.modeBySymbol['2408'], ScoringMode.weaknessObserve);
    expect(r.modeBySymbol.containsKey('2330'), isFalse);
  });

  test('警示 map：有生效警示的焦點股帶出警示資料', () async {
    when(
      () => mockDb.getActiveWarningsMapBatch(any()),
    ).thenAnswer((_) async => {'2408': createAttentionWarning(symbol: '2408')});
    final r = await container.read(newsHeatProvider.future);
    expect(r.warningBySymbol['2408']?.warningType, 'ATTENTION');
    expect(r.warningBySymbol.containsKey('2330'), isFalse);
    // 只查焦點股清單（top N symbols）
    final captured =
        verify(
              () => mockDb.getActiveWarningsMapBatch(captureAny()),
            ).captured.single
            as List<String>;
    expect(captured.toSet(), {'2408', '2330'});
  });

  test('漲跌幅 map：最新價含 priceChange 時算出今日 %', () async {
    when(() => mockDb.getLatestPricesBatch(any())).thenAnswer(
      (_) async => {
        // close 110、漲跌 +10 → 前收 100 → +10%
        '2408': DailyPriceEntry(
          symbol: '2408',
          date: DateTime.now(),
          close: 110,
          priceChange: 10,
        ),
      },
    );
    final r = await container.read(newsHeatProvider.future);
    expect(r.priceChangeBySymbol['2408'], closeTo(10.0, 1e-9));
    // 無法算漲跌幅的（此處 2330 無最新價）不出現在 map，而非塞 null/0
    expect(r.priceChangeBySymbol.containsKey('2330'), isFalse);
  });

  test('風險關鍵字：標題命中的個股 hasRiskNews 為真', () async {
    when(() => mockNewsRepo.getRecentNews(days: any(named: 'days'))).thenAnswer(
      (_) async => [
        news('a', '南亞科高層涉內線交易遭調查', DateTime.now()),
        news('b', '台積電法說會', DateTime.now()),
      ],
    );
    final r = await container.read(newsHeatProvider.future);
    final nanya = r.stocks.firstWhere((s) => s.symbol == '2408');
    final tsmc = r.stocks.firstWhere((s) => s.symbol == '2330');
    expect(nanya.hasRiskNews, isTrue);
    expect(tsmc.hasRiskNews, isFalse);
  });

  test('surgeReliable passthrough：基準窗覆蓋不足為 false、足夠為 true', () async {
    // 預設 setUp 的新聞全在今天 → 基準窗 0 個覆蓋日 → false
    final sparse = await container.read(newsHeatProvider.future);
    expect(sparse.surgeReliable, isFalse);

    // 基準窗（7–27 天前）14 個相異日各 1 篇 → true
    when(() => mockNewsRepo.getRecentNews(days: any(named: 'days'))).thenAnswer(
      (_) async => [
        for (var i = 7; i <= 20; i++)
          news('d$i', '盤後速報', DateTime.now().subtract(Duration(days: i))),
      ],
    );
    container.invalidate(newsHeatProvider);
    final dense = await container.read(newsHeatProvider.future);
    expect(dense.surgeReliable, isTrue);
  });

  test('新聞資料版本遞增後重算熱度', () async {
    final sub = container.listen(newsHeatProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(newsHeatProvider.future);
    clearInteractions(mockNewsRepo);

    container.read(newsDataVersionProvider.notifier).bump();
    await container.read(newsHeatProvider.future);

    verify(
      () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
    ).called(1);
  });
}

// 回檔暫停：推薦清單用同一個分析日讀大盤判定讀數
// （設計：docs/plans/2026-11-24-pullback-regime-notice-design.md）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/database/dao/analysis_dao.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/market_regime.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

void main() {
  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late MockAnalysisRepository mockRepo;
  late ProviderContainer container;

  final analysisDate = DateTime(2026, 11, 24);

  const bear = MarketRegimeReading(
    eligibleCount: 455,
    upCount: 132,
    medianReturn: -0.1609,
    isUptrend: false,
    lookbackDays: 120,
  );
  const bull = MarketRegimeReading(
    eligibleCount: 537,
    upCount: 294,
    medianReturn: 0.0394,
    isUptrend: true,
    lookbackDays: 120,
  );

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(analysisDate);
  });

  /// 有一檔強勢觀察的推薦（走到正常回傳那一條）
  void stubOneRecommendation() {
    when(() => mockRepo.getModeStockScores(any(), any())).thenAnswer((
      invocation,
    ) async {
      final codes = invocation.positionalArguments[1] as List<String>;
      return codes.contains('VOLUME_SPIKE')
          ? const [
              ModeStockScore(
                symbol: 'AAA',
                modeScoreShort: 40,
                modeScoreLong: 40,
              ),
            ]
          : const <ModeStockScore>[];
    });
    when(
      () => mockCachedDb.loadStockListData(
        symbols: any(named: 'symbols'),
        analysisDate: any(named: 'analysisDate'),
        historyStart: any(named: 'historyStart'),
      ),
    ).thenAnswer(
      (_) async => (
        stocks: {
          'AAA': StockMasterEntry(
            symbol: 'AAA',
            name: '甲',
            market: 'TWSE',
            industry: '電子工業',
            isActive: true,
            updatedAt: analysisDate,
          ),
        },
        latestPrices: <String, DailyPriceEntry>{},
        analyses: <String, DailyAnalysisEntry>{},
        reasons: <String, List<DailyReasonEntry>>{},
        priceHistories: <String, List<DailyPriceEntry>>{},
      ),
    );
    when(
      () => mockDb.getActiveWarningsMapBatch(any()),
    ).thenAnswer((_) async => {});
  }

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();
    mockRepo = MockAnalysisRepository();
    when(
      () => mockDb.getLatestDataDate(),
    ).thenAnswer((_) async => analysisDate);
    when(
      () => mockRepo.findLatestAnalysisDate(),
    ).thenAnswer((_) async => analysisDate);
    when(
      () => mockRepo.getModeStockScores(any(), any()),
    ).thenAnswer((_) async => const <ModeStockScore>[]);
    when(() => mockRepo.getMarketRegime(any())).thenAnswer((_) async => bear);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
        analysisRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// 推薦清單算完之後同步讀（畫面只在推薦算完、分頁空白時才讀它）
  Future<MarketRegimeReading?> pause() async {
    await container.read(
      modeRecommendationsProvider(ScoringMode.weaknessObserve).future,
    );
    return container.read(pullbackPauseProvider);
  }

  test('非多頭：回傳那一天的讀數（沒有任何推薦時也一樣）', () async {
    expect(await pause(), bear);
  });

  test('讀的是推薦清單的分析日', () async {
    await pause();
    verify(() => mockRepo.getMarketRegime(analysisDate)).called(1);
  });

  test('有推薦時（正常算完）也帶讀數', () async {
    stubOneRecommendation();
    final recs = await container.read(
      modeRecommendationsProvider(ScoringMode.strengthObserve).future,
    );
    expect(recs.map((r) => r.symbol), ['AAA']);
    expect(await pause(), bear);
  });

  test('推薦重算後跟著換：看的是最新那一份', () async {
    expect(await pause(), bear);
    when(() => mockRepo.getMarketRegime(any())).thenAnswer((_) async => bull);
    container.read(dataUpdateEpochProvider.notifier).bump();
    expect(await pause(), isNull);
  });

  test('多頭：null', () async {
    when(() => mockRepo.getMarketRegime(any())).thenAnswer((_) async => bull);
    expect(await pause(), isNull);
  });

  test('那一天沒有讀數：null', () async {
    when(() => mockRepo.getMarketRegime(any())).thenAnswer((_) async => null);
    expect(await pause(), isNull);
  });

  test('沒有任何分析日：null，也不讀判定', () async {
    when(() => mockRepo.findLatestAnalysisDate()).thenAnswer((_) async => null);
    expect(await pause(), isNull);
    verifyNever(() => mockRepo.getMarketRegime(any()));
  });

  test('讀判定失敗：推薦清單照常，暫停為 null', () async {
    stubOneRecommendation();
    when(
      () => mockRepo.getMarketRegime(any()),
    ).thenAnswer((_) async => throw const DatabaseException('db locked'));
    final recs = await container.read(
      modeRecommendationsProvider(ScoringMode.strengthObserve).future,
    );
    expect(recs.map((r) => r.symbol), ['AAA']);
    expect(await pause(), isNull);
  });
}

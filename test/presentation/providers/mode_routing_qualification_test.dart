// 分頁分派：先篩出「本身合格」的模式，再依優先順序挑（2026-09-26）。
//
// 舊流程先依優先順序選模式、選完才檢查分數，造成兩個問題：
// - 弱的高優先模式擠掉強的低優先模式，整檔消失（2026-09-24 正式資料副本
//   以真實分派重放：2454 起漲短期 0 分被 floor 擋下，強勢 38 分的訊號因此
//   不在任何分頁；修正後強勢分頁候選 55 → 60 檔）
// - 選中的模式分數不到訊號門檻，卡片顯示「觀察」混進訊號分頁
//   （例：起漲 10 分、另有強勢訊號過門檻）
//
// Mock 模式沿用 mode_recommendation_neutral_drag_test.dart。價格、歷史留空
// → todayPct／biasMa20／ret60 皆 null（permissive），起漲與強勢兩個模式都合格，
// 斷言只測「分數合格」這一道。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/database/dao/analysis_dao.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

void main() {
  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late MockAnalysisRepository mockAnalysisRepo;
  late ProviderContainer container;

  final testDate = DateTime(2026, 9, 24);

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(testDate);
  });

  StockMasterEntry stock(String symbol) => StockMasterEntry(
    symbol: symbol,
    name: '測試股 $symbol',
    market: 'TWSE',
    industry: '電子工業',
    isActive: true,
    updatedAt: testDate,
  );

  /// 起漲（momentumEntry）的分數；ROE_IMPROVING 是該模式的規則代碼
  const momentum = <ModeStockScore>[
    // 2454 型態：起漲弱（8），強勢強（36）→ 應進強勢分頁
    ModeStockScore(symbol: 'DROP01', modeScoreShort: 8, modeScoreLong: 8),
    // 起漲 10（不到訊號門檻 12），強勢 20 → 應進強勢、不進起漲
    ModeStockScore(symbol: 'OBS01', modeScoreShort: 10, modeScoreLong: 10),
    // 只有長期分數：短期 5 不到 floor 10 → 維持不進任何分頁（floor 保留）
    ModeStockScore(symbol: 'LONG01', modeScoreShort: 5, modeScoreLong: 30),
    // 短期為負：不論絕對值多大都不合格（所有模式都是正分設計）
    ModeStockScore(symbol: 'NEG01', modeScoreShort: -15, modeScoreLong: 20),
    // 兩個模式都合格：維持優先順序，起漲勝出（即使強勢分數較高）
    ModeStockScore(symbol: 'BOTH01', modeScoreShort: 20, modeScoreLong: 20),
  ];

  /// 強勢（strengthObserve）的分數；VOLUME_SPIKE 是該模式的規則代碼
  const strength = <ModeStockScore>[
    ModeStockScore(symbol: 'DROP01', modeScoreShort: 36, modeScoreLong: 36),
    ModeStockScore(symbol: 'OBS01', modeScoreShort: 20, modeScoreLong: 20),
    ModeStockScore(symbol: 'BOTH01', modeScoreShort: 40, modeScoreLong: 40),
  ];

  const symbols = ['DROP01', 'OBS01', 'LONG01', 'NEG01', 'BOTH01'];

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();
    mockAnalysisRepo = MockAnalysisRepository();

    when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => testDate);
    when(
      () => mockAnalysisRepo.findLatestAnalysisDate(),
    ).thenAnswer((_) async => testDate);
    when(() => mockAnalysisRepo.getModeStockScores(any(), any())).thenAnswer((
      invocation,
    ) async {
      final codes = invocation.positionalArguments[1] as List<String>;
      if (codes.contains('ROE_IMPROVING')) return momentum;
      if (codes.contains('VOLUME_SPIKE')) return strength;
      return const <ModeStockScore>[];
    });

    when(
      () => mockCachedDb.loadStockListData(
        symbols: any(named: 'symbols'),
        analysisDate: any(named: 'analysisDate'),
        historyStart: any(named: 'historyStart'),
      ),
    ).thenAnswer(
      (_) async => (
        stocks: {for (final s in symbols) s: stock(s)},
        latestPrices: <String, DailyPriceEntry>{},
        analyses: <String, DailyAnalysisEntry>{},
        reasons: <String, List<DailyReasonEntry>>{},
        priceHistories: <String, List<DailyPriceEntry>>{},
      ),
    );
    when(
      () => mockDb.getActiveWarningsMapBatch(any()),
    ).thenAnswer((_) async => {});

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
        analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<Map<String, double>> tab(ScoringMode mode) async {
    final list = await container.read(modeRecommendationsProvider(mode).future);
    return {for (final r in list) r.symbol: r.displayScore};
  }

  test('弱的高優先模式不再擠掉強的低優先模式（2454 型態）', () async {
    expect((await tab(ScoringMode.strengthObserve))['DROP01'], 36);
    expect(await tab(ScoringMode.momentumEntry), isNot(contains('DROP01')));
  });

  test('不到訊號門檻的模式不被選中，分頁不出現觀察卡', () async {
    expect(await tab(ScoringMode.momentumEntry), isNot(contains('OBS01')));
    expect((await tab(ScoringMode.strengthObserve))['OBS01'], 20);
  });

  test('短期分數 floor 保留：只有長期分數的股票不進分頁', () async {
    for (final mode in ScoringMode.userFacingModes) {
      expect(await tab(mode), isNot(contains('LONG01')), reason: mode.name);
    }
  });

  test('短期分數為負的模式不合格（不取絕對值）', () async {
    for (final mode in ScoringMode.userFacingModes) {
      expect(await tab(mode), isNot(contains('NEG01')), reason: mode.name);
    }
  });

  test('兩個模式都合格時維持優先順序', () async {
    expect((await tab(ScoringMode.momentumEntry))['BOTH01'], 20);
    expect(await tab(ScoringMode.strengthObserve), isNot(contains('BOTH01')));
  });

  test('三個使用者模式的 routingPriority 各不相同（分派不處理平手）', () {
    final priorities = [
      for (final m in ScoringMode.userFacingModes) m.routingPriority,
    ];
    expect(priorities.toSet(), hasLength(priorities.length));
  });

  group('qualifiesForRouting 臨界值', () {
    bool q(double short, double long) => qualifiesForRouting(
      ModeStockScore(symbol: 'X', modeScoreShort: short, modeScoreLong: long),
    );

    test('較高分剛好 12 → 合格（12 是最弱主訊號的分數）', () {
      expect(q(12, 12), isTrue);
      expect(q(11, 11), isFalse);
    });

    test('短期剛好 10、較高分過 12 → 合格', () {
      expect(q(10, 30), isTrue);
      expect(q(9, 30), isFalse);
    });
  });

  test('分頁裡每張卡都達訊號門檻', () async {
    for (final mode in ScoringMode.userFacingModes) {
      for (final score in (await tab(mode)).values) {
        expect(score, greaterThanOrEqualTo(12), reason: mode.name);
      }
    }
  });
}

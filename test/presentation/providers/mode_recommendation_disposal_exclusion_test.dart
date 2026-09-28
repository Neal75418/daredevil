// Provider-level test for the assignment loop's disposal exclusion —
// `_modeAssignmentsProvider`（透過公開的 `modeRecommendationsProvider` 驗證）。
//
// 2026-07-16：處置股（分盤交易 + 預收款券）機制上非正常可交易，不該佔用任一
// 模式的「可行動候選」榜位——跟 ETF 過濾同屬宇宙定義過濾，不是分數判斷。
// 注意股風險較低、仍保留候選資格，靠卡片風險徽章提示即可。
//
// **single-assignment 架構下的測試設計**：一檔股票最終只會落在「它勝出的那個
// mode」的榜單（見 STEP 5 的 bestMode 挑選），故對「非自己主場」mode 的
// absence 斷言在架構上恆真、不構成迴歸防護。為了讓「三個 mode 都真的被獨立
// 擋下」這件事可驗證（避免誤植成只把排除邏輯塞進 isEligibleForMode 的某個
// case、導致其他 mode 完全沒擋），本測試用三檔「各自只在單一 mode 合格」的
// 處置股（DISP01→A／DISP_B→B／DISP_C→C），分別確認各自從**自己會贏的那個
// 榜單**消失。
//
// Mock 模式沿用 scan_provider_test.dart / today_provider_test.dart：
// MockAppDatabase + MockCachedDatabaseAccessor + MockAnalysisRepository 三件組
// override databaseProvider / cachedDbProvider / analysisRepositoryProvider；
// marketDataRepositoryProvider 不 override（其真實實作內部委派給
// databaseProvider，見 today_provider_test.dart 同款寫法）。警示 fixture 重用
// test/helpers/warning_data_generators.dart 的 createDisposalWarning /
// createAttentionWarning。

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

import '../../helpers/warning_data_generators.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

void main() {
  late MockAppDatabase mockDb;
  late MockCachedDatabaseAccessor mockCachedDb;
  late MockAnalysisRepository mockAnalysisRepo;
  late ProviderContainer container;

  final testDate = DateTime(2026, 7, 16);

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(testDate);
  });

  StockMasterEntry stock(String symbol) => StockMasterEntry(
    symbol: symbol,
    name: '測試股 $symbol',
    market: 'TWSE',
    industry: '紡織業', // 非 ETF，不會被 ETF 過濾誤傷
    isActive: true,
    updatedAt: testDate,
  );

  DailyAnalysisEntry analysis(
    String symbol,
    double score,
  ) => DailyAnalysisEntry(
    symbol: symbol,
    date: testDate,
    trendState: 'UP',
    reversalState: 'NONE',
    scoreShort:
        score, // 聚合分析分數（非 tier 依據；isSignalTier 改讀 getModeStockScores 的 modeScore）
    scoreLong: score,
    computedAt: testDate,
  );

  DailyReasonEntry reason(String symbol, double score, String reasonType) =>
      DailyReasonEntry(
        symbol: symbol,
        date: testDate,
        rank: 1,
        reasonType: reasonType,
        evidenceJson: '{}',
        ruleScoreShort: score,
        ruleScoreLong: score,
      );

  setUp(() {
    mockDb = MockAppDatabase();
    mockCachedDb = MockCachedDatabaseAccessor();
    mockAnalysisRepo = MockAnalysisRepository();

    when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => testDate);

    // 三個 mode 的 reasonTypeCodes 各自只回傳「該 mode 專屬」的候選：
    // ROE_IMPROVING → momentumEntry（A）；WEEK_52_HIGH → strengthObserve（B）；
    // PULLBACK_TO_MA20 → weaknessObserve（C）。確保每檔測試股都只在單一 mode
    // 合格，讓下方 absence 斷言各自對應到真正被排除的那個 mode。
    // 今日頁的日期錨是「最新有分析的日期」而非最新價格日（見
    // mode_recommendation_provider STEP 1）——價格與分析可能停在不同日，
    // 以價格日為錨會在分析缺當日時把整頁打成硬空。
    when(
      () => mockAnalysisRepo.findLatestAnalysisDate(),
    ).thenAnswer((_) async => testDate);
    when(() => mockAnalysisRepo.getModeStockScores(any(), any())).thenAnswer((
      invocation,
    ) async {
      final codes = invocation.positionalArguments[1] as List<String>;
      if (codes.contains('ROE_IMPROVING')) {
        return const [
          ModeStockScore(
            symbol: 'DISP01', // top score —— 若無 Fix 2 會排 A 榜第 1 名
            modeScoreShort: 50,
            modeScoreLong: 50,
          ),
          ModeStockScore(
            symbol: 'ATT01',
            modeScoreShort: 40,
            modeScoreLong: 40,
          ),
        ];
      }
      if (codes.contains('WEEK_52_HIGH')) {
        return const [
          ModeStockScore(
            symbol: 'DISP_B', // strengthObserve 唯一候選 —— 若無 Fix 2 會排 B 榜
            modeScoreShort: 15,
            modeScoreLong: 15,
          ),
        ];
      }
      if (codes.contains('PULLBACK_TO_MA20')) {
        return const [
          ModeStockScore(
            symbol: 'DISP_C', // weaknessObserve 唯一候選 —— 若無 Fix 2 會排 C 榜
            modeScoreShort: 20,
            modeScoreLong: 20,
          ),
        ];
      }
      return const [];
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
          'DISP01': stock('DISP01'),
          'ATT01': stock('ATT01'),
          'DISP_B': stock('DISP_B'),
          'DISP_C': stock('DISP_C'),
        },
        latestPrices:
            <String, DailyPriceEntry>{}, // 空 → todayPct null（permissive，不干擾本測試）
        analyses: {
          'DISP01': analysis('DISP01', 50),
          'ATT01': analysis('ATT01', 40),
          'DISP_B': analysis('DISP_B', 15),
          'DISP_C': analysis('DISP_C', 20),
        },
        reasons: {
          'DISP01': [reason('DISP01', 50, 'ROE_IMPROVING')],
          'ATT01': [reason('ATT01', 40, 'ROE_IMPROVING')],
          'DISP_B': [reason('DISP_B', 15, 'WEEK_52_HIGH')],
          // Mode C 必過 gate：需命中 ModeFilters.modeCRequiredAnyOf 其一
          'DISP_C': [reason('DISP_C', 20, 'PULLBACK_TO_MA20')],
        },
        priceHistories:
            <String, List<DailyPriceEntry>>{}, // 空 → biasMa20 null（permissive）
      ),
    );

    // DISP* = active DISPOSAL；ATT01 = active ATTENTION（較低風險、應保留候選資格）
    when(() => mockDb.getActiveWarningsMapBatch(any())).thenAnswer(
      (_) async => {
        'DISP01': createDisposalWarning(symbol: 'DISP01', date: testDate),
        'ATT01': createAttentionWarning(symbol: 'ATT01', date: testDate),
        'DISP_B': createDisposalWarning(symbol: 'DISP_B', date: testDate),
        'DISP_C': createDisposalWarning(symbol: 'DISP_C', date: testDate),
      },
    );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(mockCachedDb),
        analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('active DISPOSAL 股票不出現在自己會贏的榜單；active ATTENTION 股票保留候選資格', () async {
    final aList = await container.read(
      modeRecommendationsProvider(ScoringMode.momentumEntry).future,
    );
    final bList = await container.read(
      modeRecommendationsProvider(ScoringMode.strengthObserve).future,
    );
    final cList = await container.read(
      modeRecommendationsProvider(ScoringMode.weaknessObserve).future,
    );

    final aSymbols = aList.map((r) => r.symbol);
    final bSymbols = bList.map((r) => r.symbol);
    final cSymbols = cList.map((r) => r.symbol);

    // DISP01 是 A 榜兩檔候選裡分數較高的一檔（50 > 40）——若無 Fix 2，會是
    // Mode A 起漲候選榜第 1 名。
    expect(aSymbols, isNot(contains('DISP01')));
    // DISP_B / DISP_C 分別是各自 mode 的唯一候選——若無 Fix 2，會直接進榜。
    // 三檔分屬三個不同 mode，一併通過才代表排除不是只塞在單一 case 裡。
    expect(bSymbols, isNot(contains('DISP_B')));
    expect(cSymbols, isNot(contains('DISP_C')));

    // ATTENTION 風險較低，不應被路由排除——只靠卡片徽章提示（本測試不驗證徽章，
    // 徽章 wiring 由 mode_recommendation_warning_test.dart 覆蓋）。
    expect(aSymbols, contains('ATT01'));
  });
}

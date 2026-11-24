// Provider-level test for the `isSignalTier` gate — `_modeAssignmentsProvider`
// STEP 5（透過公開的 `modeRecommendationsProvider` 驗證）。
//
// 2026-07-17 audit：isSignalTier 用 daily_analysis.score_short/score_long
// （**全部**觸發 reason 的加總，含 neutral 警訊）判斷「是否成立訊號」，但
// mode 排名 / eligibility 用的是 modeScoreShort/modeScoreLong（**只**該 mode
// 的 reason 加總，neutral 不計入 — 見 ModeRecommendation.warningReasons 的
// docstring：「警訊不 route 股票、不貢獻 mode score」）。兩個分數口徑不一致：
// 一檔股票可能有真正合格的 mode 訊號（modeScoreShort ≥ minScoreThreshold），
// 但因為同時觸發 neutral 警訊（負分）把 blended 總分拖到 12 分以下，在
// STEP 5 的 isSignalTier check 就被整檔 drop（droppedObservation），連
// isEligibleForMode 都沒機會跑到。
//
// 7/17 DB replay 實際 case（VACUUM copy 唯讀重放 _modeAssignmentsProvider
// STEP1-5、含完整 eligibility：todayPct / biasMa20 / floor）：
// - 2105：INSTITUTIONAL_BUY_STREAK +20（Mode B 訊號）+ KD_DEATH_CROSS −12
//   （neutral）→ blended 8/8 < 12 → 整檔消失，即使 Mode B 自己的分數 20 遠
//   超過 eligibility 門檻（today +0.15%、floor 10）。
// - 6443：LOW_VOLUME_ACCUMULATION +12 + PATTERN_HAMMER +18 +
//   RSI_EXTREME_OVERSOLD +10 = Mode A 40 分強訊號，被 MA_ALIGNMENT_BEARISH
//   −15 + PRICE_VOLUME_BEARISH_DIVERGENCE −15 兩條 neutral 警訊拖到 blended
//   10/10 < 12 → 整檔消失。
//
// 下方用 LEAK01 複刻 6443 型態（單一 mode、大額正分訊號 + neutral 拖累）。
//
// Mock 模式沿用 mode_recommendation_disposal_exclusion_test.dart：
// MockAppDatabase + MockCachedDatabaseAccessor + MockAnalysisRepository。

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

  final testDate = DateTime(2026, 7, 17);

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(testDate);
  });

  StockMasterEntry stock(String symbol) => StockMasterEntry(
    symbol: symbol,
    name: '測試股 $symbol',
    market: 'TWSE',
    industry: '電子工業', // 非 ETF
    isActive: true,
    updatedAt: testDate,
  );

  DailyAnalysisEntry analysis(
    String symbol,
    double scoreShort,
    double scoreLong,
  ) => DailyAnalysisEntry(
    symbol: symbol,
    date: testDate,
    trendState: 'UP',
    reversalState: 'NONE',
    scoreShort: scoreShort,
    scoreLong: scoreLong,
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

    // 三檔測試股全部只在 Mode A（ROE_IMPROVING 是該 mode 的 code）合格，
    // B / C 查詢一律回空 — 確保下方斷言只測 isSignalTier 這一個 gate、
    // 不受其他 mode 的 eligibility 干擾。
    // 今日頁的日期錨是「最新有分析的日期」而非最新價格日（見
    // mode_recommendation_provider STEP 1）——價格與分析可能停在不同日，
    // 以價格日為錨會在分析缺當日時把整頁打成硬空。
    when(
      () => mockAnalysisRepo.findLatestAnalysisDate(),
    ).thenAnswer((_) async => testDate);
    // 大盤判定讀數只影響回檔分頁的空白說明，這裡不關心
    when(
      () => mockAnalysisRepo.getMarketRegime(any()),
    ).thenAnswer((_) async => null);
    when(() => mockAnalysisRepo.getModeStockScores(any(), any())).thenAnswer((
      invocation,
    ) async {
      // 日期敏感：只有 testDate 這天有分析。錨錯日期就會拿到空清單——
      // 這是「錨在分析日」守門測試的必要條件，用 any() 一律回同一份
      // 會讓該測試變成套套邏輯（實測：mutation 存活）。
      final date = invocation.positionalArguments[0] as DateTime;
      if (date != testDate) return const <ModeStockScore>[];
      final codes = invocation.positionalArguments[1] as List<String>;
      if (codes.contains('ROE_IMPROVING')) {
        return const [
          // LEAK01 = 6443 型態：mode 訊號 30 分（遠超 minScoreThreshold=12
          // 與 floor=10），但 blended 分數被 neutral 警訊拖到 5（<12）。
          ModeStockScore(
            symbol: 'LEAK01',
            modeScoreShort: 30,
            modeScoreLong: 30,
          ),
          // WEAK01 = 真的弱：無 neutral 污染，mode 分數本身就只有 7（<12）。
          // 修復後仍應排除 —— 驗證修復沒有「乾脆整個 gate 拿掉」。
          ModeStockScore(symbol: 'WEAK01', modeScoreShort: 7, modeScoreLong: 7),
          // INFLATE01 = 反向 case：mode 分數本身只有 10（<12，不該成立訊號），
          // 但 neutral 正分（HIGH_DIVIDEND_YIELD +18，「利多但與 momentum
          // 無關」— 見 reason_type.dart 對 highDividendYield 的分類註解）把
          // blended 灌到 28（≥12）。修復前 isSignalTier 會誤放行；修復後
          // 應改用 mode 分數判斷、正確排除。
          ModeStockScore(
            symbol: 'INFLATE01',
            modeScoreShort: 10,
            modeScoreLong: 10,
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
          'LEAK01': stock('LEAK01'),
          'WEAK01': stock('WEAK01'),
          'INFLATE01': stock('INFLATE01'),
        },
        latestPrices:
            <String, DailyPriceEntry>{}, // 空 → todayPct null（permissive）
        analyses: {
          'LEAK01': analysis(
            'LEAK01',
            5,
            5,
          ), // 30 (ROE_IMPROVING) − 25 (HIGH_PLEDGE_RATIO)
          'WEAK01': analysis('WEAK01', 7, 7), // 只有 ROE_IMPROVING +7
          'INFLATE01': analysis(
            'INFLATE01',
            28,
            28,
          ), // 10 + 18 (HIGH_DIVIDEND_YIELD)
        },
        reasons: {
          'LEAK01': [
            reason('LEAK01', 30, 'ROE_IMPROVING'),
            reason('LEAK01', -25, 'HIGH_PLEDGE_RATIO'), // neutral 警訊
          ],
          'WEAK01': [reason('WEAK01', 7, 'ROE_IMPROVING')],
          'INFLATE01': [
            reason('INFLATE01', 10, 'ROE_IMPROVING'),
            reason('INFLATE01', 18, 'HIGH_DIVIDEND_YIELD'), // neutral 正分
          ],
        },
        priceHistories:
            <String, List<DailyPriceEntry>>{}, // 空 → biasMa20 null（permissive）
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

  test(
    'neutral 警訊不應把有效 mode 訊號拖出 signal tier（7/17 audit 2105/6443 型態）',
    () async {
      final aList = await container.read(
        modeRecommendationsProvider(ScoringMode.momentumEntry).future,
      );
      final aSymbols = aList.map((r) => r.symbol).toSet();

      // 真訊號（30 分）+ neutral 警訊拖累 blended 分數（5）→ 不該被
      // isSignalTier 擋下，應正常出現在 Mode A 榜單、分數維持 mode 分數。
      expect(aSymbols, contains('LEAK01'));
      final leak = aList.firstWhere((r) => r.symbol == 'LEAK01');
      expect(leak.modeScoreShort, 30);
      expect(leak.modeScoreLong, 30);

      // 真的弱（mode 分數本身 <12、無 neutral 污染）→ 維持排除，非迴歸。
      expect(aSymbols, isNot(contains('WEAK01')));

      // 反向：mode 分數 <12、靠 neutral 正分灌水過 12 → 不該被誤放行。
      expect(aSymbols, isNot(contains('INFLATE01')));
    },
  );
  // ====================================================================
  // 日期錨（P1-8 (B)）
  //
  // 價格與分析可能停在不同日：價格寫入發生在任何評分決策之前，
  // HistoricalPriceSyncer 也會為 priority 股補當日 bar，所以
  // MAX(daily_price.date) 可能已跳到今日、而當日分析因資料不完整被
  // scoring_pipeline 的 staleBar 攔下。
  //
  // 舊實作以 getLatestDataDate()（價格 MAX）為錨，查無當日分析就直接
  // 回 emptyResult → 今日頁三個 tab 硬空，把「今天沒算」呈現成
  // 「今天沒有好股票」。改錨在 findLatestAnalysisDate 後乾淨退回昨日。
  // ====================================================================
  test('🚨 價格日已跳今日、分析停昨日時，仍應退回昨日榜單而非硬空', () async {
    // 分析錨仍在 testDate（= 昨日那份完整的榜），價格 MAX 已跳到隔日
    when(
      () => mockDb.getLatestDataDate(),
    ).thenAnswer((_) async => testDate.add(const Duration(days: 1)));

    final list = await container.read(
      modeRecommendationsProvider(ScoringMode.momentumEntry).future,
    );

    expect(
      list.map((r) => r.symbol),
      contains('LEAK01'),
      reason: '以價格日為錨會查無當日分析而整頁打空；必須錨在最新有分析的日期',
    );
  });
}

import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/scoring_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/price_data_generators.dart';

/// ScoringService 單元測試
///
/// 測試評分服務的流動性過濾邏輯與評分流程。
/// 使用 Mocktail 模擬依賴服務。

/// Mock 分析服務
class MockAnalysisService extends Mock implements AnalysisService {}

/// Mock 規則引擎
class MockRuleEngine extends Mock implements RuleEngine {}

/// Mock 分析資料庫
///
/// [inTransaction] 供測試斷言某呼叫是否發生在 runInTransaction callback 內
/// （清除與寫入必須同一 transaction，避免中斷留下當日分析真空）。
class MockAnalysisRepository extends Mock implements AnalysisRepository {
  bool inTransaction = false;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    inTransaction = true;
    try {
      return await action();
    } finally {
      inTransaction = false;
    }
  }
}

/// 本檔所有 scoreStocks 呼叫共用的評分日。
///
/// 價格 fixture 必須以此為最後一根 bar：scoring_pipeline 的 staleBar 檢查
/// 會比對 `prices.last.date` 與評分日，不一致者整批判為陳舊而跳過。
/// （generator 預設以 DateTime.now() 收尾，與這裡的 2025-06-15 差一年以上。）
final _scoringDate = DateTime(2025, 6, 15);

void main() {
  late ScoringService scoringService;
  late MockAnalysisService mockAnalysisService;
  late MockRuleEngine mockRuleEngine;
  late MockAnalysisRepository mockAnalysisRepository;

  setUp(() {
    mockAnalysisService = MockAnalysisService();
    mockRuleEngine = MockRuleEngine();
    mockAnalysisRepository = MockAnalysisRepository();

    scoringService = ScoringService(
      analysisService: mockAnalysisService,
      ruleEngine: mockRuleEngine,
      analysisRepository: mockAnalysisRepository,
    );

    // Default mocks
    registerFallbackValue(
      AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      ),
    );
    registerFallbackValue(const StockData(symbol: 'TEST', prices: []));
    registerFallbackValue(
      const AnalysisResult(
        trendState: TrendState.range,
        reversalState: ReversalState.none,
        supportLevel: 0,
        resistanceLevel: 0,
      ),
    );
    registerFallbackValue(<TriggeredReason>[]);
    // Stage 5b dual-horizon：calculateScore 新增 horizon + calibratedScores
    registerFallbackValue(Horizon.short);
    registerFallbackValue(CalibratedScoreContext.empty);
    registerFallbackValue(<DailyPriceEntry>[]);
    registerFallbackValue(<NewsItemEntry>[]);
    registerFallbackValue(<DailyInstitutionalEntry>[]);
    registerFallbackValue(<MonthlyRevenueEntry>[]);

    // 寫入 transaction 內的當日清除（clear-then-write 原子化）預設 no-op
    when(
      () => mockAnalysisRepository.clearReasonsForDate(any()),
    ).thenAnswer((_) async => 0);
    when(
      () => mockAnalysisRepository.clearAnalysisForDate(any()),
    ).thenAnswer((_) async => 0);

    // 基本面遞減預設無作用（空 map）——需要驗證遞減行為的測試自行 override
    when(
      () => mockRuleEngine.computeFundamentalDecayMultipliers(any()),
    ).thenReturn(const {});

    // Default mocks to prevent Null type errors
    when(() => mockRuleEngine.getTopReasons(any())).thenAnswer(
      (invocation) =>
          invocation.positionalArguments[0] as List<TriggeredReason>,
    );
    // H-1 fix: scoring_service 改成顯式呼 applyMutexGroups 在 calculateScore
    // 之前。Mock 預設行為：原樣回傳（不過濾 mutex） — 既有測試斷言的 score
    // 數值對應「不過濾」語意，保持一致。需要驗證 mutex 行為的個別測試自行
    // override。
    when(() => mockRuleEngine.applyMutexGroups(any(), any())).thenAnswer(
      (invocation) =>
          invocation.positionalArguments[0] as List<TriggeredReason>,
    );
    // Types that might be nullable in arguments but needed for any()
    registerFallbackValue(
      MonthlyRevenueEntry(
        symbol: 'TEST',
        date: _scoringDate,
        revenueYear: 2023,
        revenueMonth: 1,
        revenue: 0,
        momGrowth: 0,
        yoyGrowth: 0,
      ),
    );
    registerFallbackValue(
      StockValuationEntry(
        symbol: 'TEST',
        date: _scoringDate,
        per: 0,
        pbr: 0,
        dividendYield: 0,
      ),
    );
  });

  group('ScoringService Liquidity Filters', () {
    test('skip stocks with low turnover (small volume)', () async {
      // Arrange
      // Volume = 100K shares × price 100 = turnover 10M（Fail < 30M min）
      final prices = [
        ...generatePricesWithVolumeSpike(
          endDate: _scoringDate,
          days: 30,
          normalVolume: 1000,
          spikeVolume: 5000,
        ),
        DailyPriceEntry(
          symbol: 'LOW_VOL',
          date: _scoringDate,
          open: 100,
          high: 105,
          low: 95,
          close: 100,
          volume: 100000, // turnover 100 × 100K = 10M < 30M
        ),
      ];

      final pricesMap = {'LOW_VOL': prices};
      // Sufficient history > 20 days
      expect(prices.length, greaterThan(RuleParams.swingWindow));

      // Act
      final result = await scoringService.scoreStocks(
        candidates: ['LOW_VOL'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: pricesMap, newsMap: {}),
      );

      // Assert
      expect(result, isEmpty);
      verifyNever(() => mockAnalysisService.analyzeStock(any()));
    });

    test('skip stocks with low turnover', () async {
      // Arrange
      // Volume = 500K shares
      // Price = 5
      // Turnover = 2.5M (Fail < 30M)
      final prices = [
        ...generatePricesWithVolumeSpike(
          endDate: _scoringDate,
          days: 30,
          normalVolume: 1000,
          spikeVolume: 5000,
        ),
        DailyPriceEntry(
          symbol: 'LOW_TURN',
          date: _scoringDate,
          open: 5,
          high: 6,
          low: 4,
          close: 5,
          volume: 500000, // 500K shares, turnover = 5*500K = 2.5M < 30M
        ),
      ];

      final pricesMap = {'LOW_TURN': prices};

      // Act
      final result = await scoringService.scoreStocks(
        candidates: ['LOW_TURN'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: pricesMap, newsMap: {}),
      );

      // Assert
      expect(result, isEmpty);
      verifyNever(() => mockAnalysisService.analyzeStock(any()));
    });

    test('process stocks with high volume and turnover', () async {
      // Arrange
      // Volume = 3M shares
      // Price = 150
      // Turnover = 450M (OK > 30M)
      final prices = [
        ...generatePricesWithVolumeSpike(
          endDate: _scoringDate,
          days: 30,
          normalVolume: 1000,
          spikeVolume: 5000,
        ),
        DailyPriceEntry(
          symbol: 'GOOD',
          date: _scoringDate,
          open: 148,
          high: 152,
          low: 149,
          close: 150,
          volume: 3000000,
        ),
      ];

      final pricesMap = {'GOOD': prices};

      // Mock dependencies
      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(
        const AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 140,
          resistanceLevel: 160,
        ),
      );

      when(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 80,
          description: 'Test Breakout',
        ),
      ]);

      when(
        () => mockRuleEngine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(80);

      when(() => mockRuleEngine.getTopReasons(any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 80,
          description: 'Test Breakout',
        ),
      ]);

      when(
        () => mockAnalysisRepository.saveAnalysis(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          trendState: any(named: 'trendState'),
          reversalState: any(named: 'reversalState'),
          supportLevel: any(named: 'supportLevel'),
          resistanceLevel: any(named: 'resistanceLevel'),
          scoreShort: any(named: 'scoreShort'),
          scoreLong: any(named: 'scoreLong'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockAnalysisRepository.saveReasons(any(), any(), any()),
      ).thenAnswer((_) async {});

      // Act
      final result = await scoringService.scoreStocks(
        candidates: ['GOOD'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: pricesMap, newsMap: {}),
      );

      // Assert
      expect(result, isNotEmpty);
      expect(result.first.symbol, 'GOOD');
      expect(result.first.scoreShort, 80);
    });

    test('sort candidates by score descending', () async {
      // Arrange
      final pricesMap = {
        'HIGH_SCORE': [
          ...generatePricesWithVolumeSpike(
            endDate: _scoringDate,
            days: 30,
            normalVolume: 2000000, // 流動性只看最後一根（spike 那天），這個量不影響過濾
            spikeVolume: 5000000,
          ),
        ],
        'LOW_SCORE': [
          ...generatePricesWithVolumeSpike(
            endDate: _scoringDate,
            days: 30,
            normalVolume: 2000000,
            spikeVolume: 5000000,
          ),
        ],
      };

      const highReason = TriggeredReason(
        type: ReasonType.volumeSpike,
        score: 80, // High score reason
        description: 'High',
      );
      const lowReason = TriggeredReason(
        type: ReasonType.volumeSpike,
        score: 40, // Low score reason
        description: 'Low',
      );

      // Unified mock for evaluateStock using thenAnswer to handle dispatch
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenAnswer((
        invocation,
      ) {
        final data = invocation.positionalArguments[1] as StockData;
        final symbol = data.symbol;
        if (symbol == 'HIGH_SCORE') return [highReason];
        if (symbol == 'LOW_SCORE') return [lowReason];
        return [];
      });

      // Mock calculateScore to return score based on input reasons
      when(
        () => mockRuleEngine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenAnswer((invocation) {
        final reasons =
            invocation.positionalArguments[0] as List<TriggeredReason>;
        if (reasons.contains(highReason)) return 80;
        if (reasons.contains(lowReason)) return 40;
        return 0;
      });

      // Mock analysis service dependencies for both
      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(
        const AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 100,
          resistanceLevel: 120,
        ),
      );
      when(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );

      when(
        () => mockAnalysisRepository.saveAnalysis(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          trendState: any(named: 'trendState'),
          scoreShort: any(named: 'scoreShort'),
          scoreLong: any(named: 'scoreLong'),
          reversalState: any(named: 'reversalState'),
          supportLevel: any(named: 'supportLevel'),
          resistanceLevel: any(named: 'resistanceLevel'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockAnalysisRepository.saveReasons(any(), any(), any()),
      ).thenAnswer((_) async {});

      // Act
      // Pass in reverse order to ensure sorting works
      final result = await scoringService.scoreStocks(
        candidates: ['LOW_SCORE', 'HIGH_SCORE'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: pricesMap, newsMap: {}),
      );

      // Assert
      expect(result.length, 2);
      expect(result.first.symbol, 'HIGH_SCORE');
      expect(result.last.symbol, 'LOW_SCORE');
    });
  });

  // ==========================================
  // Group 2: 空值與早期回傳
  // ==========================================

  group('ScoringService clear-then-write 原子性', () {
    test('清除當日舊資料應發生在寫入 transaction 內', () async {
      // Arrange：一檔可通過流動性過濾並成功評分的股票
      final prices = [
        ...generatePricesWithVolumeSpike(
          endDate: _scoringDate,
          days: 30,
          normalVolume: 1000,
          spikeVolume: 5000,
        ),
        DailyPriceEntry(
          symbol: 'GOOD',
          date: _scoringDate,
          open: 148,
          high: 152,
          low: 149,
          close: 150,
          volume: 3000000,
        ),
      ];
      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(
        const AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 140,
          resistanceLevel: 160,
        ),
      );
      when(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 80,
          description: 'Test Breakout',
        ),
      ]);
      when(
        () => mockRuleEngine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(80);
      // 記錄呼叫順序與 clear 當下的 transaction 狀態
      final callOrder = <String>[];
      final clearReasonsInTx = <bool>[];
      final clearAnalysisInTx = <bool>[];
      when(
        () => mockAnalysisRepository.saveAnalysis(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          trendState: any(named: 'trendState'),
          reversalState: any(named: 'reversalState'),
          supportLevel: any(named: 'supportLevel'),
          resistanceLevel: any(named: 'resistanceLevel'),
          scoreShort: any(named: 'scoreShort'),
          scoreLong: any(named: 'scoreLong'),
        ),
      ).thenAnswer((_) async {
        callOrder.add('saveAnalysis');
      });
      when(
        () => mockAnalysisRepository.saveReasons(any(), any(), any()),
      ).thenAnswer((_) async {
        callOrder.add('saveReasons');
      });
      when(() => mockAnalysisRepository.clearReasonsForDate(any())).thenAnswer((
        _,
      ) async {
        callOrder.add('clearReasons');
        clearReasonsInTx.add(mockAnalysisRepository.inTransaction);
        return 0;
      });
      when(() => mockAnalysisRepository.clearAnalysisForDate(any())).thenAnswer(
        (_) async {
          callOrder.add('clearAnalysis');
          clearAnalysisInTx.add(mockAnalysisRepository.inTransaction);
          return 0;
        },
      );

      // Act
      await scoringService.scoreStocks(
        candidates: ['GOOD'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: {'GOOD': prices}, newsMap: {}),
      );

      // Assert：clear 必須在寫入 transaction 內執行——
      // 若在 transaction 外先 clear，評分中斷會留下當日分析真空
      expect(
        clearReasonsInTx,
        [true],
        reason: 'clearReasonsForDate 必須在 runInTransaction 內被呼叫一次',
      );
      expect(
        clearAnalysisInTx,
        [true],
        reason: 'clearAnalysisForDate 必須在 runInTransaction 內被呼叫一次',
      );
      // ordering：clear 必須發生在任何寫入之前，否則會清掉剛寫入的資料
      final firstWrite = callOrder.indexWhere(
        (c) => c == 'saveAnalysis' || c == 'saveReasons',
      );
      expect(firstWrite, greaterThan(-1), reason: '應有寫入發生');
      expect(
        callOrder.sublist(0, firstWrite),
        containsAll(['clearReasons', 'clearAnalysis']),
        reason: '兩個 clear 都必須在第一筆寫入之前',
      );
    });
  });

  group('ScoringService Empty/Null Input', () {
    test('return empty list when candidates list is empty', () async {
      final result = await scoringService.scoreStocks(
        candidates: [],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: const {}, newsMap: const {}),
      );

      expect(result, isEmpty);
      verifyNever(() => mockAnalysisService.analyzeStock(any()));
    });

    test('skip stocks with no price data in pricesMap', () async {
      final result = await scoringService.scoreStocks(
        candidates: ['MISSING'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: const {}, newsMap: const {}),
      );

      expect(result, isEmpty);
      verifyNever(() => mockAnalysisService.analyzeStock(any()));
    });

    test('skip stocks with insufficient price history', () async {
      final prices = generateConstantPrices(
        days: 5, // < RuleParams.swingWindow (20)
        basePrice: 100.0,
        volume: 3000000,
      );

      final result = await scoringService.scoreStocks(
        candidates: ['SHORT'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: {'SHORT': prices}, newsMap: {}),
      );

      expect(result, isEmpty);
      verifyNever(() => mockAnalysisService.analyzeStock(any()));
    });

    // 接線守門（P1-8 L1）：staleBar 的判斷邏輯由 scoring_pipeline_test.dart
    // 覆蓋，但純函式測試抓不到「主執行緒 caller 忘了把評分日傳下去」。
    // 把 scoring_service.dart 的 `asOf: date` 拿掉，本測試即變紅。
    test('🚨 最後一根 bar 不是評分日 → 跳過，不得進技術分析', () async {
      // fixture 收在評分日前一天：DB 缺當日資料時 prices.last 就是這個樣子
      final prices = generatePricesWithVolumeSpike(
        endDate: _scoringDate.subtract(const Duration(days: 1)),
        days: 30,
        normalVolume: 2000000,
        spikeVolume: 5000000,
        symbol: 'STALE',
      );

      final result = await scoringService.scoreStocks(
        candidates: ['STALE'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: {'STALE': prices}, newsMap: {}),
      );

      expect(result, isEmpty);
      verifyNever(() => mockAnalysisService.analyzeStock(any()));
    });
  });

  // ==========================================
  // Group 3: 分析失敗路徑
  // ==========================================

  group('ScoringService Analysis Failure Paths', () {
    /// 建立通過流動性門檻的有效價格資料
    List<DailyPriceEntry> validPrices(String symbol) {
      return generatePricesWithVolumeSpike(
        endDate: _scoringDate,
        days: 30,
        normalVolume: 2000000,
        spikeVolume: 5000000,
        symbol: symbol,
      );
    }

    test('skip stock when analyzeStock returns null', () async {
      final prices = validPrices('NULL_ANALYSIS');

      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(null);

      final result = await scoringService.scoreStocks(
        candidates: ['NULL_ANALYSIS'],
        date: _scoringDate,
        batchData: ScoringBatchData(
          pricesMap: {'NULL_ANALYSIS': prices},
          newsMap: {},
        ),
      );

      expect(result, isEmpty);
      verify(() => mockAnalysisService.analyzeStock(any())).called(1);
      verifyNever(() => mockRuleEngine.evaluateStock(any(), any()));
    });

    test('skip stock when rule engine returns empty reasons', () async {
      final prices = validPrices('EMPTY_REASONS');

      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(
        const AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 100,
          resistanceLevel: 120,
        ),
      );
      when(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn([]);

      final result = await scoringService.scoreStocks(
        candidates: ['EMPTY_REASONS'],
        date: _scoringDate,
        batchData: ScoringBatchData(
          pricesMap: {'EMPTY_REASONS': prices},
          newsMap: {},
        ),
      );

      expect(result, isEmpty);
      verifyNever(
        () => mockRuleEngine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      );
    });
  });

  // ==========================================
  // Group 4: 分數過濾
  // ==========================================

  group('ScoringService Score Filtering', () {
    /// 設定完整的 mock pipeline 讓候選通過所有檢查直到分數計算
    void setupFullPipeline({
      required int returnScore,
      String symbol = 'STOCK',
    }) {
      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(
        const AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 100,
          resistanceLevel: 120,
        ),
      );
      when(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 20,
          description: 'Test',
        ),
      ]);

      when(
        () => mockRuleEngine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(returnScore);

      when(() => mockRuleEngine.getTopReasons(any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 20,
          description: 'Test',
        ),
      ]);

      when(
        () => mockAnalysisRepository.saveAnalysis(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          trendState: any(named: 'trendState'),
          scoreShort: any(named: 'scoreShort'),
          scoreLong: any(named: 'scoreLong'),
          reversalState: any(named: 'reversalState'),
          supportLevel: any(named: 'supportLevel'),
          resistanceLevel: any(named: 'resistanceLevel'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockAnalysisRepository.saveReasons(any(), any(), any()),
      ).thenAnswer((_) async {});
    }

    List<DailyPriceEntry> validPrices(String symbol) {
      return generatePricesWithVolumeSpike(
        endDate: _scoringDate,
        days: 30,
        normalVolume: 2000000,
        spikeVolume: 5000000,
        symbol: symbol,
      );
    }

    test('skip stock when score is below observationScoreThreshold', () async {
      final prices = validPrices('NOISE');
      setupFullPipeline(returnScore: RuleParams.observationScoreThreshold - 1);

      final result = await scoringService.scoreStocks(
        candidates: ['NOISE'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: {'NOISE': prices}, newsMap: {}),
      );

      // 低於觀察門檻 = 雜訊，不持久化
      expect(result, isEmpty);
    });

    test(
      'keep stock as observation when score in [observation, signal)',
      () async {
        final prices = validPrices('OBS');
        setupFullPipeline(returnScore: RuleParams.observationScoreThreshold);

        final result = await scoringService.scoreStocks(
          candidates: ['OBS'],
          date: _scoringDate,
          batchData: ScoringBatchData(pricesMap: {'OBS': prices}, newsMap: {}),
        );

        // 8 ≥ 觀察門檻但 < 訊號門檻 12 → 保留為「觀察區」（接近觸發）
        expect(result, isNotEmpty);
        expect(result.first.scoreShort, RuleParams.observationScoreThreshold);
      },
    );

    test('include stock when score equals minScoreThreshold', () async {
      final prices = validPrices('BOUNDARY');
      setupFullPipeline(returnScore: RuleParams.minScoreThreshold);

      final result = await scoringService.scoreStocks(
        candidates: ['BOUNDARY'],
        date: _scoringDate,
        batchData: ScoringBatchData(
          pricesMap: {'BOUNDARY': prices},
          newsMap: {},
        ),
      );

      expect(result, isNotEmpty);
      expect(result.first.scoreShort, RuleParams.minScoreThreshold);
    });
  });

  // ==========================================
  // Group 5: 選用功能
  // ==========================================

  group('ScoringService Optional Features', () {
    List<DailyPriceEntry> validPrices(String symbol) {
      return generatePricesWithVolumeSpike(
        endDate: _scoringDate,
        days: 30,
        normalVolume: 2000000,
        spikeVolume: 5000000,
        symbol: symbol,
      );
    }

    test('call onProgress callback for each candidate', () async {
      final progressCalls = <(int, int)>[];
      final prices = validPrices('A');

      // analyzeStock returns null → all skipped, but onProgress still called
      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(null);

      await scoringService.scoreStocks(
        candidates: ['A', 'B', 'C'],
        date: _scoringDate,
        batchData: ScoringBatchData(
          pricesMap: {'A': prices, 'B': prices, 'C': prices},
          newsMap: {},
        ),
        onProgress: (current, total) => progressCalls.add((current, total)),
      );

      expect(progressCalls, [(1, 3), (2, 3), (3, 3)]);
    });

    test('call marketDataBuilder and pass result to buildContext', () async {
      final prices = validPrices('MKT');
      const marketData = MarketDataContext(foreignSharesRatio: 30.0);

      when(() => mockAnalysisService.analyzeStock(any())).thenReturn(
        const AnalysisResult(
          trendState: TrendState.up,
          reversalState: ReversalState.none,
          supportLevel: 100,
          resistanceLevel: 120,
        ),
      );
      when(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 30,
          description: 'Test',
        ),
      ]);
      when(
        () => mockRuleEngine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(30);
      when(() => mockRuleEngine.getTopReasons(any())).thenReturn([
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 30,
          description: 'Test',
        ),
      ]);
      when(
        () => mockAnalysisRepository.saveAnalysis(
          symbol: any(named: 'symbol'),
          date: any(named: 'date'),
          trendState: any(named: 'trendState'),
          scoreShort: any(named: 'scoreShort'),
          scoreLong: any(named: 'scoreLong'),
          reversalState: any(named: 'reversalState'),
          supportLevel: any(named: 'supportLevel'),
          resistanceLevel: any(named: 'resistanceLevel'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAnalysisRepository.saveReasons(any(), any(), any()),
      ).thenAnswer((_) async {});

      var builderCalled = false;
      await scoringService.scoreStocks(
        candidates: ['MKT'],
        date: _scoringDate,
        batchData: ScoringBatchData(pricesMap: {'MKT': prices}, newsMap: {}),
        marketDataBuilder: (symbol) async {
          builderCalled = true;
          expect(symbol, 'MKT');
          return marketData;
        },
      );

      expect(builderCalled, isTrue);
      // Verify buildContext was called with the marketData
      verify(
        () => mockAnalysisService.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: marketData,
          evaluationTime: any(named: 'evaluationTime'),
        ),
      ).called(1);
    });
  });

  // ==========================================
  // Group 6: ScoredStock.compareByWeightedScore 排序邏輯
  // ==========================================

  group('ScoredStock.compareByWeightedScore', () {
    test('rank higher score first', () {
      const a = ScoredStock(
        symbol: '2330',
        scoreShort: 60,
        scoreLong: 60,
        turnover: 100000000,
      );
      const b = ScoredStock(
        symbol: '2317',
        scoreShort: 50,
        scoreLong: 50,
        turnover: 100000000,
      );

      // a should rank first (comparator returns negative for descending)
      expect(
        ScoredStock.compareByWeightedScoreFor(Horizon.short)(a, b),
        lessThan(0),
      );
    });

    test('add liquidity bonus (2 per 100M, max 20)', () {
      // A: score=50, turnover=1B → bonus=20, total=70
      // B: score=60, turnover=50M → bonus=1, total=61
      const a = ScoredStock(
        symbol: '2330',
        scoreShort: 50,
        scoreLong: 50,
        turnover: 1000000000, // 1B
      );
      const b = ScoredStock(
        symbol: '2317',
        scoreShort: 60,
        scoreLong: 60,
        turnover: 50000000, // 50M
      );

      // A (70) should rank before B (61)
      expect(
        ScoredStock.compareByWeightedScoreFor(Horizon.short)(a, b),
        lessThan(0),
      );
    });

    test('cap liquidity bonus at 20', () {
      // A: score=50, turnover=2B → bonus=min(40,20)=20, total=70
      // B: score=50, turnover=1B → bonus=20, total=70
      // Tied on total → break by turnover (A > B)
      const a = ScoredStock(
        symbol: '2330',
        scoreShort: 50,
        scoreLong: 50,
        turnover: 2000000000, // 2B
      );
      const b = ScoredStock(
        symbol: '2317',
        scoreShort: 50,
        scoreLong: 50,
        turnover: 1000000000, // 1B
      );

      // Both total=70, A has higher turnover → A ranks first
      expect(
        ScoredStock.compareByWeightedScoreFor(Horizon.short)(a, b),
        lessThan(0),
      );
    });

    test('break ties by turnover descending', () {
      const a = ScoredStock(
        symbol: '2330',
        scoreShort: 60,
        scoreLong: 60,
        turnover: 500000000, // 500M
      );
      const b = ScoredStock(
        symbol: '2317',
        scoreShort: 60,
        scoreLong: 60,
        turnover: 300000000, // 300M
      );

      // Same score, A has higher turnover → A ranks first
      expect(
        ScoredStock.compareByWeightedScoreFor(Horizon.short)(a, b),
        lessThan(0),
      );
    });

    test('break final ties by symbol ascending', () {
      const a = ScoredStock(
        symbol: '1234',
        scoreShort: 60,
        scoreLong: 60,
        turnover: 500000000,
      );
      const b = ScoredStock(
        symbol: '5678',
        scoreShort: 60,
        scoreLong: 60,
        turnover: 500000000,
      );

      // Same score, same turnover → "1234" < "5678" → A ranks first
      expect(
        ScoredStock.compareByWeightedScoreFor(Horizon.short)(a, b),
        lessThan(0),
      );
    });
  });
}

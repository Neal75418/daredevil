// Stage 4 Commit C2 — tool/replay_calibrator.dart unit tests
//
// 使用 in-memory Drift DB + synthetic price data + mocked RuleEngine 來驗證
// ReplayCalibrator 的核心行為：
// - 正確 iterate 歷史交易日
// - Forward return 計算正確（5D + 60D）
// - Hit rate / avg return 聚合正確
// - Unbiased sampling：不因 rule 觸發頻率低就被濾掉（因為沒有 Top 20 filter）
// - rule_accuracy table 寫入兩個 period row: '5D', '60D'（'ALL' 已於 2026-04 移除）
// - min-history cutoff 正確
// - forward-window cutoff 正確（不評估無法計算 60D forward return 的日子）
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

import '../../tool/replay_calibrator.dart';

class _MockAnalysisService extends Mock implements AnalysisService {}

class _MockRuleEngine extends Mock implements RuleEngine {}

void main() {
  late AppDatabase db;
  late _MockAnalysisService mockAnalysis;
  late _MockRuleEngine mockRuleEngine;

  setUpAll(() {
    registerFallbackValue(
      AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
      ),
    );
    registerFallbackValue(const StockData(symbol: '', prices: []));
    registerFallbackValue(
      const AnalysisResult(
        trendState: TrendState.up,
        reversalState: ReversalState.none,
        supportLevel: 0,
        resistanceLevel: 0,
      ),
    );
    registerFallbackValue(<DailyPriceEntry>[]);
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    mockAnalysis = _MockAnalysisService();
    mockRuleEngine = _MockRuleEngine();

    // Default mocks — analysis always returns a valid result
    when(() => mockAnalysis.analyzeStock(any())).thenReturn(
      const AnalysisResult(
        trendState: TrendState.up,
        reversalState: ReversalState.none,
        supportLevel: 100,
        resistanceLevel: 120,
      ),
    );
    when(
      () => mockAnalysis.buildContext(
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
  });

  tearDown(() async {
    await db.close();
  });

  // ==========================================================================
  // Fixtures
  // ==========================================================================

  /// 插入一檔股票 + N 天的合成價格
  ///
  /// 價格以 linear growth 100 → 100 + days 上升（方便手算 forward return）
  Future<void> seedStock(
    String symbol, {
    required int priceDays,
    double startClose = 100.0,
    double growthPerDay = 1.0,
    DateTime? firstDate,
  }) async {
    await db.upsertStocks([
      StockMasterCompanion.insert(
        symbol: symbol,
        name: 'Test $symbol',
        market: 'TWSE',
      ),
    ]);

    final first = firstDate ?? DateTime(2024, 1, 1);
    final prices = <DailyPriceCompanion>[];
    for (var i = 0; i < priceDays; i++) {
      final date = first.add(Duration(days: i));
      final close = startClose + growthPerDay * i;
      prices.add(
        DailyPriceCompanion.insert(
          symbol: symbol,
          date: date,
          open: Value(close),
          high: Value(close * 1.01),
          low: Value(close * 0.99),
          close: Value(close),
          volume: const Value(1000000),
        ),
      );
    }
    await db.insertPrices(prices);
  }

  // ==========================================================================
  // Tests
  // ==========================================================================

  group('ReplayCalibrator — forward return math', () {
    test('linear growth 1%/day produces expected 5D + 60D returns', () async {
      // 100 days of linear growth + 5 days forward + 60 days forward = need
      // at least 80 days of price history for the first eligible day (min=20)
      // and another 60 for the final forward window. Use 200 days to be safe.
      await seedStock('TEST', priceDays: 200);

      // Mock rule engine to fire a specific rule on every day it's evaluated
      const testRuleType = ReasonType.techBreakout;
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: testRuleType,
          score: 25,
          description: 'test firing',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      expect(result.rulesObserved, 1);
      final stats = result.ruleStats[testRuleType.code];
      expect(stats, isNotNull);

      // Eligible range: i from 20 to 199-60-1 = 139 (inclusive → 120 firings)
      expect(stats!.short.triggerCount, 120);
      expect(stats.long.triggerCount, 120);

      // Linear growth: entry=100+i*1, exit_5d=100+(i+5)*1, return=5/(100+i)
      // For i=20, return ≈ 5/120 = 4.17%; for i=139, return ≈ 5/239 = 2.09%
      // avg short return should be in that range
      expect(stats.short.avgReturn, inInclusiveRange(2.0, 4.5));
      // Long return: 60/(100+i) ≈ 60/120..60/239 = 25%..25%
      // Wait: for i=20, 60/120=50%; for i=139, 60/239≈25%
      expect(stats.long.avgReturn, inInclusiveRange(24.0, 51.0));

      // Short threshold 3% — high hit rate in the first half, low in the second
      expect(stats.short.hitRate, inInclusiveRange(0.3, 1.0));
      // Long threshold 12% — ALL samples hit (min long return ≈ 25%)
      expect(stats.long.hitRate, 1.0);
    });

    test(
      'successCount uses canonical thresholds from CalibrationThresholds',
      () async {
        // 用快速成長價格序列確保 5D / 60D return 都明顯**超過**canonical
        // 門檻（5D=3.0%, 60D=12.0%），驗 replay_calibrator 確實讀到 canonical
        // 常數做 isSuccess 判定。growthPerDay=5：
        //   5D return = 25/(100 + 5i) > 3% when 100+5i < 833 (i < 146) ✓ 所有 day
        //   60D return = 300/(100+5i) > 12% when 100+5i < 2500 (i < 480) ✓ 所有 day
        await seedStock('FAST', priceDays: 150, growthPerDay: 5.0);
        when(
          () => mockRuleEngine.evaluateStock(any(), any()),
        ).thenReturn(const [
          TriggeredReason(
            type: ReasonType.volumeSpike,
            score: 22,
            description: 'fast firing',
          ),
        ]);

        final calibrator = ReplayCalibrator(
          db: db,
          config: const ReplayConfig(
            dbPath: ':memory:',
            minHistoryDays: 20,
            excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
          ),
          analysisService: mockAnalysis,
          ruleEngine: mockRuleEngine,
          logger: (_) {},
        );
        final result = await calibrator.run();

        final stats = result.ruleStats[ReasonType.volumeSpike.code]!;
        // 兩個 horizon 的 hit rate 都應該幾乎 100%（returns 都遠超門檻）
        expect(stats.short.hitRate, greaterThan(0.9));
        expect(stats.long.hitRate, greaterThan(0.9));
      },
    );
  });

  group('ReplayCalibrator — lookahead bias fix (audit finding #6)', () {
    test(
      'next-day-open entry flips a same-day-close "win" into a loss',
      () async {
        const symbol = 'GAP';
        const signalIndex = 30; // > minHistoryDays(20)
        const totalDays = signalIndex + 65; // 訊號日 + 60D forward window + margin

        await db.upsertStocks([
          StockMasterCompanion.insert(
            symbol: symbol,
            name: 'Test $symbol',
            market: 'TWSE',
          ),
        ]);

        final first = DateTime(2024, 1, 1);
        final prices = <DailyPriceCompanion>[];
        for (var i = 0; i < totalDays; i++) {
          final date = first.add(Duration(days: i));
          double value;
          if (i == signalIndex) {
            value = 100.0; // 訊號日 close：規則觸發輸入，不是進場價
          } else if (i == signalIndex + 1) {
            value = 101.6; // 隔日跳空高開 —— 真實使用者的進場價
          } else if (i == signalIndex + 5) {
            value = 101.52; // 5D 出場 close
          } else {
            value = 100.0; // 其餘天數平盤填充，避免污染這筆觀測
          }
          prices.add(
            DailyPriceCompanion.insert(
              symbol: symbol,
              date: date,
              open: Value(value),
              close: Value(value),
              // 本測試的意圖是釘 entry 價慣例;volume 缺值會被生產一致性
              // (e) 的單日閘判 noData skip(2026-08-29),給足量能讓觀測
              // 通過雙閘
              volume: const Value(2000000),
            ),
          );
        }
        await db.insertPrices(prices);

        final signalDate = first.add(const Duration(days: signalIndex));
        when(
          () => mockRuleEngine.evaluateStock(any(), any()),
        ).thenReturn(const [
          TriggeredReason(
            type: ReasonType.techBreakout,
            score: 25,
            description: 'gap test',
          ),
        ]);

        final calibrator = ReplayCalibrator(
          db: db,
          config: ReplayConfig(
            dbPath: ':memory:',
            minHistoryDays: 20,
            excessReturn: false, // 絕對模式：直接驗證 _replaySymbol 的 entry 選擇
            // dateFilter 縮到單一交易日，讓這筆精心構造的觀測是唯一 firing。
            dateFilter: (start: signalDate, end: signalDate),
          ),
          analysisService: mockAnalysis,
          ruleEngine: mockRuleEngine,
          logger: (_) {},
        );
        final result = await calibrator.run();

        final stats = result.ruleStats[ReasonType.techBreakout.code];
        expect(stats, isNotNull);
        expect(stats!.short.triggerCount, 1);
        // 同日 close entry（舊算法）：(101.52-100)/100 = +1.52% ≥ 1.5% 門檻
        // → 誤判為命中。隔日 open entry（新算法）：
        // (101.52-101.6)/101.6 ≈ -0.079% < 1.5% 門檻 → 正確判定為虧損。
        expect(
          stats.short.successCount,
          0,
          reason:
              'entry 必須用隔日 open(101.6) 而非訊號當日 close(100)；同日 '
              'close entry 算法會誤判此筆為命中，隔日 open entry 正確算出虧損',
        );
        expect(stats.short.avgReturn, closeTo(-0.0787, 0.01));
      },
    );
  });

  group('ReplayCalibrator — zero-price guard (blocking review finding, '
      'sibling of audit finding #6)', () {
    // Exit 端同型 bug：`_replaySymbol` 的 exit guard 舊版只查
    // `shortExit == null || longExit == null`，一個停牌/異常列 close=0.0
    // （非缺值 null）會被當成合法出場價，算出 (0/entry-1)*100 = -100%，把
    // 資料缺陷誤記為真實最大虧損。entry 端（line ~465）已在 lookahead bias
    // fix 時一併補上 `<= 0`，此處補上 exit 端讓兩者一致。
    test('exit close of exactly 0.0 (halted/bad row) excludes the observation, '
        'not recorded as a -100% loss', () async {
      const symbol = 'HALT';
      const signalIndex = 30; // > minHistoryDays(20)
      const totalDays = signalIndex + 65; // 訊號日 + 60D forward + margin

      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: symbol,
          name: 'Test $symbol',
          market: 'TWSE',
        ),
      ]);

      final first = DateTime(2024, 1, 1);
      final prices = <DailyPriceCompanion>[];
      for (var i = 0; i < totalDays; i++) {
        final date = first.add(Duration(days: i));
        // 5D 出場日（signalIndex + 5）：停牌/異常列，close=0.0（非缺值）。
        // 其餘天數（含訊號日、隔日進場、60D 出場）平盤 100 填充。
        final value = i == signalIndex + 5 ? 0.0 : 100.0;
        prices.add(
          DailyPriceCompanion.insert(
            symbol: symbol,
            date: date,
            open: Value(value),
            close: Value(value),
          ),
        );
      }
      await db.insertPrices(prices);

      final signalDate = first.add(const Duration(days: signalIndex));
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'halt test',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
          // dateFilter 縮到單一交易日，讓這筆精心構造的觀測是唯一 firing。
          dateFilter: (start: signalDate, end: signalDate),
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      expect(
        result.ruleStats[ReasonType.techBreakout.code],
        isNull,
        reason:
            'exit close=0.0（停牌/異常列，非缺值 null）必須視為無效排除；'
            '未修前只查 null，會把 (0/100-1)*100 = -100% 記為真實最大虧損',
      );
      expect(result.totalFirings, 0);
    });
  });

  group('ReplayCalibrator — survivorship bias fix: stale symbol excluded '
      '(audit finding #7a)', () {
    test('symbol whose latest price is stale (>30 calendar days behind '
        'dataset max) is excluded entirely from the universe', () async {
      // STALE：100 天從 2024-01-01 開始 → 最新價格約 2024-04-09（模擬
      // 下市 / 長停，之後再無新資料）。
      await seedStock('STALE', priceDays: 100);
      // FRESH：100 天從 2024-06-01 開始（與 STALE 最新價格差距遠超過
      // 30 天門檻）→ 把 dataset 的 max date 推到夠新。
      await seedStock('FRESH', priceDays: 100, firstDate: DateTime(2024, 6, 1));

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      expect(
        result.symbolsProcessed,
        1,
        reason:
            'STALE 最新價格遠早於 dataset max date（模擬下市/長停）→ '
            '整股排除，universe 只剩 FRESH',
      );
      expect(
        result.ruleStats[ReasonType.techBreakout.code]!.short.triggerCount,
        greaterThan(0),
        reason: 'FRESH 仍是有效樣本，不該被 stale 過濾誤傷',
      );
    });
  });

  group('ReplayCalibrator — unbiased sampling', () {
    test('records ALL firings without Top-20 filter', () async {
      // Two stocks, both trigger the SAME negative-signal rule
      // A real Top-20 filter would exclude both (negative total score)
      // ReplayCalibrator should count both firings.
      await seedStock('A', priceDays: 150);
      await seedStock('B', priceDays: 150, firstDate: DateTime(2024, 1, 1));

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakdown,
          score: -20,
          description: 'negative signal',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      final stats = result.ruleStats[ReasonType.techBreakdown.code]!;
      // 150 days, min=20, forward=60 → eligible = 150-20-60 = 70 per stock
      // 2 stocks × 70 = 140 firings
      expect(stats.short.triggerCount, 140);
      expect(stats.long.triggerCount, 140);
    });
  });

  group('ReplayCalibrator — history cutoff', () {
    test('skips days below min-history', () async {
      await seedStock('SHORT_HISTORY', priceDays: 85);
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      // 85 days, min=20, forward=60 → eligible from i=20..85-60-1=24 → 5 firings
      final stats = result.ruleStats[ReasonType.techBreakout.code];
      expect(stats, isNotNull);
      expect(stats!.short.triggerCount, 5);
    });

    test(
      'stock with insufficient forward window produces zero firings',
      () async {
        // 70 days of price - cannot compute 60D forward (need 60 days after
        // the earliest eligible day = day 20, so need 20 + 60 + 1 = 81 days)
        await seedStock('NO_FORWARD', priceDays: 70);
        when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(
          const [
            TriggeredReason(
              type: ReasonType.techBreakout,
              score: 25,
              description: 'x',
            ),
          ],
        );

        final calibrator = ReplayCalibrator(
          db: db,
          config: const ReplayConfig(
            dbPath: ':memory:',
            minHistoryDays: 20,
            excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
          ),
          analysisService: mockAnalysis,
          ruleEngine: mockRuleEngine,
          logger: (_) {},
        );
        final result = await calibrator.run();

        expect(result.ruleStats, isEmpty);
        expect(result.totalFirings, 0);
      },
    );
  });

  group('ReplayCalibrator — rule_accuracy writes', () {
    test('writes 5D + 60D rows per rule (ALL removed 2026-04)', () async {
      await seedStock('WRITE_TEST', priceDays: 150);
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      await calibrator.run();

      final rows = await db.select(db.ruleAccuracy).get();
      // 1 rule × 2 periods = 2 rows. 'ALL' was removed 2026-04 (mixing
      // 1D / 60D thresholds produced a meaningless aggregate hit_rate).
      expect(rows.length, 2);
      expect(rows.map((r) => r.period).toSet(), {'5D', '60D'});
    });

    test('second run replaces previous rule_accuracy rows', () async {
      await seedStock('IDEM', priceDays: 150);
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      await calibrator.run();
      final firstCount = (await db.select(db.ruleAccuracy).get()).length;

      // Second run — switch to a different rule
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'y',
        ),
      ]);
      await calibrator.run();
      final secondRows = await db.select(db.ruleAccuracy).get();

      // Second run should have purged first run's rows and written new ones
      expect(secondRows.length, firstCount); // still 2 rows (new rule)
      expect(secondRows.map((r) => r.ruleId).toSet(), {
        ReasonType.volumeSpike.code,
      });
    });
  });

  group('ReplayCalibrator — multi-rule aggregation', () {
    test('different rules get separate stats', () async {
      await seedStock('MULTI', priceDays: 150);
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'a',
        ),
        TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'b',
        ),
        TriggeredReason(
          type: ReasonType.kdGoldenCross,
          score: 10,
          description: 'c',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false, // 既有測試驗證絕對報酬機制；超額另有專測
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      expect(result.rulesObserved, 3);
      // All three rules have identical trigger count (same mock fires all
      // three on every eligible day)
      final counts = result.ruleStats.values
          .map((s) => s.short.triggerCount)
          .toSet();
      expect(counts.length, 1); // all equal
      expect(counts.first, 70); // 150-20-60 = 70
    });
  });

  group('ReplayCalibrator — dry run', () {
    test('does not write rule_accuracy and returns empty stats', () async {
      await seedStock('DRY', priceDays: 150);
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          dryRun: true,
          excessReturn: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await calibrator.run();

      expect(result.rulesObserved, 0);
      expect(result.totalFirings, 0);

      final rows = await db.select(db.ruleAccuracy).get();
      expect(rows, isEmpty);
      verifyNever(() => mockRuleEngine.evaluateStock(any(), any()));
    });
  });

  group('ReplayCalibrator — cross-sectional excess return', () {
    test('excess mode: 橫斷面加總 ≈ 0（去 beta），絕對模式則明顯為正', () async {
      // 3 檔不同成長率、同日期 → 構成每日橫斷面。rule 在每檔每天都觸發，
      // 故超額報酬（個股 − 當日均值）橫斷面加總為 0。
      await seedStock('SLOW', priceDays: 200, growthPerDay: 0.5);
      await seedStock('MED', priceDays: 200);
      await seedStock('FAST', priceDays: 200, growthPerDay: 1.5);

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final excess = await ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          minUniverseSymbols: 2, // 3 檔 universe 通過門檻
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      ).run();

      final stats = excess.ruleStats[ReasonType.techBreakout.code]!;
      expect(stats.short.triggerCount, greaterThan(0));
      expect(
        stats.short.avgReturn,
        closeTo(0.0, 0.01),
        reason: '5D 超額橫斷面加總應 ≈ 0（多空 beta 被扣除）',
      );
      expect(stats.long.avgReturn, closeTo(0.0, 0.01), reason: '60D 同理');

      // 對照組：同一份上漲資料，絕對模式 avgReturn 明顯為正（beta 未扣）。
      // 這正是超額模式要消除的「多頭把一切墊高」假象。
      final absolute = await ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      ).run();
      final absStats = absolute.ruleStats[ReasonType.techBreakout.code]!;
      expect(
        absStats.short.avgReturn,
        greaterThan(1.0),
        reason: '絕對模式含 beta → 明顯為正（與超額的 ≈0 對比）',
      );
      expect(absStats.long.avgReturn, greaterThan(1.0));
    });

    test('guard: 當日 universe < minUniverseSymbols → 跳過所有 firing', () async {
      await seedStock('A', priceDays: 200);
      await seedStock('B', priceDays: 200);

      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      final result = await ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          minUniverseSymbols: 5, // 2 檔 universe 不足 → 全跳過
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      ).run();

      expect(
        result.totalFirings,
        0,
        reason: 'universe 覆蓋不足（半套日語意）→ 該日均值不可靠、跳過',
      );
    });
  });

  group('ReplayCalibrator — look-ahead 修正（公布日 lag）', () {
    test('月營收公布日 = 次月 10 號（不偷看當月）', () {
      // 3 月營收（DB 存 3/1）→ 4/10 才可見；3 月內的訊號看不到
      expect(
        ReplayCalibrator.revenueVisibleDate(DateTime(2026, 3, 1)),
        DateTime(2026, 4, 10),
      );
      // 12 月營收 → 次年 1/10（跨年）
      expect(
        ReplayCalibrator.revenueVisibleDate(DateTime(2026, 12, 1)),
        DateTime(2027, 1, 10),
      );
      // 公布日嚴格晚於營收月底 → 無 look-ahead
      expect(
        ReplayCalibrator.revenueVisibleDate(
          DateTime(2026, 5, 1),
        ).isAfter(DateTime(2026, 5, 31)),
        isTrue,
      );
    });

    test('季財報公布日：Q1≈5/15 / Q2≈8/14 / Q3≈11/14 / 年報次年 3/31', () {
      // 季底輸入（calibration.db 實際存的語意）
      expect(
        ReplayCalibrator.financialVisibleDate(DateTime(2026, 3, 31)),
        DateTime(2026, 5, 15),
      );
      expect(
        ReplayCalibrator.financialVisibleDate(DateTime(2026, 6, 30)),
        DateTime(2026, 8, 14),
      );
      expect(
        ReplayCalibrator.financialVisibleDate(DateTime(2026, 9, 30)),
        DateTime(2026, 11, 14),
      );
      expect(
        ReplayCalibrator.financialVisibleDate(DateTime(2026, 12, 31)),
        DateTime(2027, 3, 31),
      );
    });

    test('財報公布日對「季初 vs 季底」輸入皆給同一日（消除 date 語意歧義）', () {
      // codebase 內財報 date 語意不一致（季初 1/4/7/10 vs 季底 3/6/9/12）。
      // 季正規化後，同一季的任一輸入日都對應同一公布日 → 兩種語意都正確。
      for (final pair in [
        (DateTime(2026, 1, 1), DateTime(2026, 3, 31)), // Q1 季初/季底
        (DateTime(2026, 4, 1), DateTime(2026, 6, 30)), // Q2
        (DateTime(2026, 7, 1), DateTime(2026, 9, 30)), // Q3
        (DateTime(2026, 10, 1), DateTime(2026, 12, 31)), // Q4
      ]) {
        expect(
          ReplayCalibrator.financialVisibleDate(pair.$1),
          ReplayCalibrator.financialVisibleDate(pair.$2),
          reason: '季初與季底輸入應給同一公布日',
        );
      }
      // 無 look-ahead：公布日晚於整季（連季初輸入也晚於季底）
      expect(
        ReplayCalibrator.financialVisibleDate(
          DateTime(2026, 1, 1),
        ).isAfter(DateTime(2026, 3, 31)),
        isTrue,
      );
    });
  });

  group('ReplayCalibrator — dateFilter（walk-forward 校準窗）', () {
    test('只把窗內 entry 當 firing；universe 仍用全資料', () async {
      // 單檔 + 絕對模式（隔離 dateFilter；超額模式的 universe guard 會干擾）。
      // seedStock 用 calendar days：2024-01-01 起，i 天 → 2024-01-01 + i。
      await seedStock('WF', priceDays: 200);
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'x',
        ),
      ]);

      // 無 filter：i=20..139 → 120 firings
      final full = await ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      ).run();
      expect(
        full.ruleStats[ReasonType.techBreakout.code]!.short.triggerCount,
        120,
      );

      // 窗 [2024-02-01, 2024-03-01]（calendar i=31..60）→ ~30 firings
      final windowed = await ReplayCalibrator(
        db: db,
        config: ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
          dateFilter: (start: DateTime(2024, 2, 1), end: DateTime(2024, 3, 1)),
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      ).run();
      final n =
          windowed.ruleStats[ReasonType.techBreakout.code]!.short.triggerCount;
      expect(n, lessThan(120), reason: 'dateFilter 應限制 firing 在窗內');
      expect(
        n,
        inInclusiveRange(28, 32),
        reason: '窗 2/1-3/1 約 30 個 calendar-day entry',
      );
    });
  });
}

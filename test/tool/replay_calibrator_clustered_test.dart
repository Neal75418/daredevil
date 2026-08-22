// 資料層測試 — per-date 聚類統計 + universe baseline + 持久化
// (docs/plans/2026-07-10-excess-decision-layer-clustered-tstat.md)
//
// 驗證：
//   1. RuleHorizonStats per-date 累加（dailyMeans / distinctDates）
//   2. excess replay 計算 universe baseline hit（P(excess ≥ threshold)）
//   3. rule_daily_stats / calibration_run_meta 寫入 + 冪等（重跑覆寫）
import 'package:drift/drift.dart' show Value, Variable;
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
    ).thenAnswer((inv) {
      // 轉傳 marketData:stub 若丟掉它,測到的就是 mock 而非 replay 的接線
      return AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.up,
        marketData: inv.namedArguments[#marketData] as MarketDataContext?,
      );
    });
    when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
      TriggeredReason(
        type: ReasonType.techBreakout,
        score: 25,
        description: 'x',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedStock(
    String symbol, {
    required int priceDays,
    double startClose = 100.0,
    double growthPerDay = 1.0,
  }) async {
    await db.upsertStocks([
      StockMasterCompanion.insert(
        symbol: symbol,
        name: 'Test $symbol',
        market: 'TWSE',
      ),
    ]);
    final first = DateTime(2024, 1, 1);
    final prices = <DailyPriceCompanion>[];
    for (var i = 0; i < priceDays; i++) {
      final close = startClose + growthPerDay * i;
      prices.add(
        DailyPriceCompanion.insert(
          symbol: symbol,
          date: first.add(Duration(days: i)),
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

  ReplayCalibrator excessCalibrator({int minUniverseSymbols = 2}) {
    return ReplayCalibrator(
      db: db,
      config: ReplayConfig(
        dbPath: ':memory:',
        minHistoryDays: 20,
        minUniverseSymbols: minUniverseSymbols,
      ),
      analysisService: mockAnalysis,
      ruleEngine: mockRuleEngine,
      logger: (_) {},
    );
  }

  // ==========================================================================
  // 1. RuleHorizonStats — per-date 累加（純單元）
  // ==========================================================================

  group('RuleHorizonStats — per-date 累加', () {
    test('同日多筆取均值、跨日各自一格', () {
      final s = RuleHorizonStats();
      final d1 = DateTime(2025, 1, 1);
      final d2 = DateTime(2025, 1, 2);
      s.addSample(1.0, 0, date: d1);
      s.addSample(3.0, 0, date: d1);
      s.addSample(5.0, 0, date: d2);

      expect(s.distinctDates, 2);
      // 日均值序列依日期升序：d1 → (1+3)/2 = 2.0；d2 → 5.0
      expect(s.dailyMeans, [2.0, 5.0]);
      // pooled 統計不受影響
      expect(s.triggerCount, 3);
      expect(s.avgReturn, closeTo(3.0, 1e-9));
    });

    test('不帶 date（舊 caller）→ 不進 per-date 統計、pooled 照常', () {
      final s = RuleHorizonStats();
      s.addSample(2.0, 0);
      expect(s.triggerCount, 1);
      expect(s.distinctDates, 0);
      expect(s.dailyMeans, isEmpty);
    });
  });

  // ==========================================================================
  // 2. Universe baseline hit
  // ==========================================================================

  group('ReplayCalibrator — universe baseline hit', () {
    test('excess 模式：baseline ∈ (0,1) 且非 null；絕對模式 → null', () async {
      await seedStock('SLOW', priceDays: 200, growthPerDay: 0.5);
      await seedStock('MED', priceDays: 200);
      await seedStock('FAST', priceDays: 200, growthPerDay: 1.5);

      final excess = await excessCalibrator().run();
      expect(excess.universeBaselineHit5, isNotNull);
      expect(excess.universeBaselineHit60, isNotNull);
      // 三檔固定強弱序：FAST 恆贏均值、SLOW 恆輸 → baseline 落在中段
      expect(excess.universeBaselineHit5!, inExclusiveRange(0.2, 0.8));
      expect(excess.universeBaselineHit60!, inExclusiveRange(0.2, 0.8));

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
      expect(absolute.universeBaselineHit5, isNull);
      expect(absolute.universeBaselineHit60, isNull);
    });
  });

  // ==========================================================================
  // 3. 持久化 — rule_daily_stats + calibration_run_meta
  // ==========================================================================

  group('ReplayCalibrator — clustered 持久化', () {
    test('rule_daily_stats：每 rule × period × 觸發日一列、n 正確', () async {
      await seedStock('SLOW', priceDays: 200, growthPerDay: 0.5);
      await seedStock('MED', priceDays: 200);
      await seedStock('FAST', priceDays: 200, growthPerDay: 1.5);

      final result = await excessCalibrator().run();
      final stats = result.ruleStats[ReasonType.techBreakout.code]!;

      final rows = await db
          .customSelect(
            'SELECT period, date, n, mean_return FROM rule_daily_stats '
            'WHERE rule_id = ? ORDER BY period, date',
            variables: [Variable(ReasonType.techBreakout.code)],
          )
          .get();
      final shortRows = rows.where((r) => r.data['period'] == '5D').toList();
      final longRows = rows.where((r) => r.data['period'] == '60D').toList();

      // 每個觸發日一列，與 in-memory distinctDates 一致
      expect(shortRows.length, stats.short.distinctDates);
      expect(longRows.length, stats.long.distinctDates);
      // 三檔同日全觸發 → 每日 n = 3
      expect(shortRows.map((r) => r.data['n'] as int).toSet(), {3});
      // DB 的日均值序列 == in-memory dailyMeans（同為日期升序）
      expect(
        shortRows
            .map((r) => (r.data['mean_return'] as num).toDouble())
            .toList(),
        stats.short.dailyMeans.map((m) => closeTo(m, 1e-6)).toList(),
      );
    });

    test('calibration_run_meta：mode/threshold/baseline 落檔且重跑覆寫', () async {
      await seedStock('SLOW', priceDays: 200, growthPerDay: 0.5);
      await seedStock('MED', priceDays: 200);
      await seedStock('FAST', priceDays: 200, growthPerDay: 1.5);

      final result = await excessCalibrator().run();

      Future<Map<String, String>> readMeta() async {
        final rows = await db
            .customSelect('SELECT key, value FROM calibration_run_meta')
            .get();
        return {
          for (final r in rows)
            r.data['key'] as String: r.data['value'] as String,
        };
      }

      final meta = await readMeta();
      expect(meta['return_mode'], 'excess');
      expect(double.parse(meta['excess_success_threshold']!), 0.0);
      expect(
        double.parse(meta['universe_baseline_hit_5d']!),
        closeTo(result.universeBaselineHit5!, 1e-9),
      );
      expect(
        double.parse(meta['universe_baseline_hit_60d']!),
        closeTo(result.universeBaselineHit60!, 1e-9),
      );

      // 重跑（絕對模式）→ meta 覆寫、mode 翻轉、baseline 鍵移除
      await ReplayCalibrator(
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
      final meta2 = await readMeta();
      expect(meta2['return_mode'], 'absolute');
      expect(meta2.containsKey('universe_baseline_hit_5d'), isFalse);

      // rule_daily_stats 也是整批覆寫（無殘留跨 run 混料）
      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM rule_daily_stats')
          .getSingle();
      final stats = (await excessCalibrator().run())
          .ruleStats[ReasonType.techBreakout.code]!;
      // 絕對模式 run 的列數 = 其自身觸發日數（非累加三個 run）
      expect(
        count.data['c'] as int,
        lessThanOrEqualTo(stats.short.distinctDates + stats.long.distinctDates),
      );
    });
  });
  // ── persist:false（2026-08-22）─────────────────────────────────────
  //
  // **為什麼需要**：`run()` 無條件把 rule_accuracy / rule_daily_stats /
  // calibration_run_meta 寫進傳入的 `db`。walkforward 為了每折的 train/test
  // 各跑一次 replay，5 折共 10 次，於是**把正式的校準結果整個蓋掉**——
  // config 的 `dbPath: ':memory:'` 是幌子，寫入用的是傳進去的 db handle。
  //
  // 2026-08-22 實測：跑完 walkforward 後，DB 的 rule_daily_stats 只剩
  // 2026-01-02～2026-05-27 共 93 天（原本 1498 個交易日），firings 從
  // 3,089,775 掉到 48,738。之後任何 recalibrate 都會拿這份殘骸產 candidate，
  // 而且三個訊號全部正常：exit 0、JSON 照常寫出、無錯誤訊息。
  //
  // `dryRun` 不能用——它早退且回空 stats，walkforward 需要真的算完。
  group('persist:false — 只算不落檔', () {
    test('🚨 前提：預設會落檔（否則這組測試沒在驗東西）', () async {
      await seedStock('SLOW', priceDays: 200, growthPerDay: 0.5);
      await seedStock('MED', priceDays: 200);
      await seedStock('FAST', priceDays: 200, growthPerDay: 1.5);
      await excessCalibrator().run();

      final rows = await db
          .customSelect('SELECT COUNT(*) c FROM rule_accuracy')
          .getSingle();
      expect(rows.read<int>('c'), greaterThan(0), reason: '預設 persist 應寫入');
    });

    test('🚨 persist:false 不得覆寫既有的 rule_accuracy', () async {
      await seedStock('SLOW', priceDays: 200, growthPerDay: 0.5);
      await seedStock('MED', priceDays: 200);
      await seedStock('FAST', priceDays: 200, growthPerDay: 1.5);
      await excessCalibrator().run();
      final before = await db
          .customSelect('SELECT COUNT(*) c FROM rule_accuracy')
          .getSingle();
      final metaBefore = await db
          .customSelect(
            "SELECT value v FROM calibration_run_meta WHERE key='generated_at'",
          )
          .getSingleOrNull();

      final result = await ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          minUniverseSymbols: 2,
          persist: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      ).run();

      expect(
        result.ruleStats,
        isNotEmpty,
        reason: 'persist:false 只跳過落檔，運算結果照樣回傳（不同於 dryRun）',
      );

      final after = await db
          .customSelect('SELECT COUNT(*) c FROM rule_accuracy')
          .getSingle();
      expect(after.read<int>('c'), before.read<int>('c'));

      final metaAfter = await db
          .customSelect(
            "SELECT value v FROM calibration_run_meta WHERE key='generated_at'",
          )
          .getSingleOrNull();
      expect(
        metaAfter?.read<String>('v'),
        metaBefore?.read<String>('v'),
        reason: 'generated_at 不得被覆寫——它是判斷 replay 新舊的依據',
      );
    });
  });
  // ── marketData 接線（2026-08-22）──────────────────────────────────
  //
  // replay 原本把 `marketData` 一律傳 null，註解寫「非 backfillable」。那句
  // 話寫的時候是真的，現在不是了——backfill 早就有 `day_trading` phase
  // （甚至有 `--only-day-trading` 模式），calibration.db 存著 155 萬列、
  // 補到 2026-08-21。
  //
  // 後果：`DAY_TRADING_HIGH` / `DAY_TRADING_EXTREME` 兩條規則在 replay 期間
  // 永遠 no-fire，於是 rule_accuracy 沒有它們的樣本、永遠拿不到校準分——
  // 而且原因不是「資料抓不到」，是「抓到了沒接上」。
  group('marketData 接線', () {
    test('🚨 有當沖資料時,規則收到的 context 帶得到 dayTradingRatio', () async {
      await seedStock('DT01', priceDays: 200);
      await seedStock('DT02', priceDays: 200);
      await seedStock('DT03', priceDays: 200);

      // 為 DT01 塞當沖資料（比例落在 DAY_TRADING_HIGH 區間）
      final first = DateTime(2024, 1, 1);
      await db.insertDayTradingData([
        for (var i = 0; i < 200; i++)
          DayTradingCompanion.insert(
            symbol: 'DT01',
            date: first.add(Duration(days: i)),
            buyVolume: const Value(600000),
            sellVolume: const Value(600000),
            dayTradingRatio: const Value(60),
            tradeVolume: const Value(1000000),
          ),
      ]);

      final seen = <double?>[];
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenAnswer((inv) {
        final ctx = inv.positionalArguments[0] as AnalysisContext;
        final sd = inv.positionalArguments[1] as StockData;
        if (sd.symbol == 'DT01') seen.add(ctx.marketData?.dayTradingRatio);
        return const [];
      });

      await excessCalibrator().run();

      expect(seen, isNotEmpty, reason: '前提:DT01 應被 replay 評估過');
      expect(
        seen.where((r) => r == 60).length,
        greaterThan(0),
        reason: 'marketData 未接線時全是 null——那正是兩條當沖規則拿不到樣本的原因',
      );
    });

    test('無當沖資料的股票 marketData 仍為 null(不得偽造)', () async {
      await seedStock('NO01', priceDays: 200);
      await seedStock('NO02', priceDays: 200);
      await seedStock('NO03', priceDays: 200);

      final seen = <MarketDataContext?>[];
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenAnswer((inv) {
        seen.add((inv.positionalArguments[0] as AnalysisContext).marketData);
        return const [];
      });

      await excessCalibrator().run();
      expect(seen, isNotEmpty);
      expect(
        seen.every((m) => m?.dayTradingRatio == null),
        isTrue,
        reason: '沒資料就是沒有,不得補 0 或預設值',
      );
    });
  });
}

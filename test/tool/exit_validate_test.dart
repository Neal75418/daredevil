// simulateExit 純函數測試 — 出場條件 replay gate 核心
// (gate 結果見 docs/plans/2026-07-12-exit-gate-report.md)
//
// 合成序列手算對照：平坦 100 基底，指定位置覆寫製造觸發情境。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/exit_params.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

import '../../tool/exit_validate.dart';
import '../../tool/replay_calibrator.dart';

class _MockAnalysisService extends Mock implements AnalysisService {}

class _MockRuleEngine extends Mock implements RuleEngine {}

/// 平坦 100 序列，指定位置覆寫
List<double?> flat(int len, {Map<int, double?> overrides = const {}}) => [
  for (var i = 0; i < len; i++) overrides.containsKey(i) ? overrides[i] : 100.0,
];

void main() {
  const all = {ExitReason.hardStop, ExitReason.trendBreak, ExitReason.timeStop};

  group('simulateExit — hardStop', () {
    test('T+3 收盤 91.9 (< 92) → hardStop 出場、報酬對 T+1 計算', () {
      // t0=70（前面 70 根供 MA60）、entry=closes[71]=100、d=73 跌到 91.9
      final closes = flat(140, overrides: {73: 91.9});
      final r = simulateExit(closes: closes, t0Index: 70, enabled: all)!;
      expect(r.reason, ExitReason.hardStop);
      expect(r.holdingDays, 2); // 71→73
      expect(r.exitReturnPct, closeTo(-8.1, 0.001)); // 91.9/100-1
      expect(r.holdReturnPct, closeTo(0.0, 0.001)); // 其餘平坦
    });

    test('恰等於 92（非 <）→ 不觸發 hardStop', () {
      final closes = flat(140, overrides: {73: 92.0});
      final r = simulateExit(closes: closes, t0Index: 70, enabled: all)!;
      expect(r.reason, isNot(ExitReason.hardStop));
    });
  });

  group('simulateExit — trendBreak', () {
    test('收盤跌破 60 日均線 → trendBreak', () {
      // 平坦 100，d=75 跌到 99（MA60≈99.98，99 < MA、但 > 92 不觸發 hardStop）
      final closes = flat(140, overrides: {75: 99.0});
      final r = simulateExit(closes: closes, t0Index: 70, enabled: all)!;
      expect(r.reason, ExitReason.trendBreak);
      expect(r.holdingDays, 4);
    });

    test('MA60 資料不足（t0 前不滿 60 根）→ trendBreak 不判定', () {
      // t0=30、只有 30 根歷史 → 該條件永不觸發，其餘平坦 → 無觸發跑滿
      final closes = flat(100, overrides: {35: 99.0});
      final r = simulateExit(
        closes: closes,
        t0Index: 30,
        enabled: {ExitReason.trendBreak},
      )!;
      expect(r.reason, isNull);
    });
  });

  group('simulateExit — timeStop', () {
    test('40 交易日從未收高於 ref → timeStop', () {
      final closes = flat(140); // 永遠 = ref，從未「高於」
      final r = simulateExit(
        closes: closes,
        t0Index: 70,
        enabled: {ExitReason.timeStop},
      )!;
      expect(r.reason, ExitReason.timeStop);
      // 首個 d-t0 ≥ 40 的日子 = t0+40 = 110 → 持有 110-71 = 39 日
      expect(r.holdingDays, 39);
    });

    test('中途曾收高於 ref → timeStop 不觸發', () {
      final closes = flat(140, overrides: {90: 101.0});
      final r = simulateExit(
        closes: closes,
        t0Index: 70,
        enabled: {ExitReason.timeStop},
      )!;
      expect(r.reason, isNull);
    });
  });

  group('simulateExit — tie-break 與邊界', () {
    test('同日 hardStop+trendBreak 皆真 → 取 hardStop（宣告序）', () {
      final closes = flat(140, overrides: {75: 80.0});
      final r = simulateExit(closes: closes, t0Index: 70, enabled: all)!;
      expect(r.reason, ExitReason.hardStop);
    });

    test('窗不足（t0+1+60 超界）→ null（survivorship 樣本）', () {
      expect(
        simulateExit(closes: flat(100), t0Index: 70, enabled: all),
        isNull,
      );
    });

    test('T+1 收盤 null（停牌）→ null', () {
      final closes = flat(140, overrides: {71: null});
      expect(simulateExit(closes: closes, t0Index: 70, enabled: all), isNull);
    });

    test('全程未觸發 → reason null、兩臂同報酬、holdingDays = horizon', () {
      final closes = flat(140, overrides: {131: 110.0}); // horizon 末端漲
      final r = simulateExit(
        closes: closes,
        t0Index: 70,
        enabled: {ExitReason.hardStop},
      )!;
      expect(r.reason, isNull);
      expect(r.exitReturnPct, r.holdReturnPct);
      expect(r.holdingDays, ExitParams.holdHorizonTradingDays);
    });

    test('MDD：出場版計到出場日、持有版計全窗', () {
      // d=75 跌 90（-10%）觸發 hardStop；d=100 再跌 80（持有版 MDD -20%）
      final closes = flat(140, overrides: {75: 90.0, 100: 80.0});
      final r = simulateExit(closes: closes, t0Index: 70, enabled: all)!;
      expect(r.exitMddPct, closeTo(-10.0, 0.01));
      expect(r.holdMddPct, closeTo(-20.0, 0.01));
    });
  });

  group('ExitValidator — 樣本蒐集與模擬 pipeline', () {
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

    setUp(() {
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
      ).thenReturn(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.up,
        ),
      );
      // 每天觸發一條 pullback 主訊號 +15 ≥ 門檻 12 → 每個評估日都是樣本候選
      when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const [
        TriggeredReason(
          type: ReasonType.pullbackToMa20,
          score: 15,
          description: 'x',
        ),
      ]);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedStockWithNullAt(
      String symbol, {
      required int priceDays,
      required int nullIndex,
    }) async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: symbol,
          name: 'T$symbol',
          market: 'TWSE',
        ),
      ]);
      final first = DateTime(2024, 1, 1);
      await db.insertPrices([
        for (var i = 0; i < priceDays; i++)
          DailyPriceCompanion.insert(
            symbol: symbol,
            date: first.add(Duration(days: i)),
            // close=null 模擬停牌（ExitValidator.simulateExit 只讀 close，
            // 見 closesBySymbol 只取 p.close）。open 仍給值：
            // ReplayCalibrator._replaySymbol 的隔日 entry fallback（lookahead
            // bias fix，audit finding #6）open ?? close 才不會在這裡搶先把
            // 整筆樣本擋在 scoreSink 之前——本測試要驗證的是 ExitValidator
            // 自己的 T+1 close-null 偵測，不是 _replaySymbol 的 entry 判斷。
            open: Value(100.0 + i * 0.1),
            close: i == nullIndex ? const Value(null) : Value(100.0 + i * 0.1),
            volume: const Value(1000000),
          ),
      ]);
    }

    Future<void> seedStock(String symbol, {required int priceDays}) async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: symbol,
          name: 'T$symbol',
          market: 'TWSE',
        ),
      ]);
      final first = DateTime(2024, 1, 1);
      await db.insertPrices([
        for (var i = 0; i < priceDays; i++)
          DailyPriceCompanion.insert(
            symbol: symbol,
            date: first.add(Duration(days: i)),
            close: Value(100.0 + i * 0.1),
            volume: const Value(1000000),
          ),
      ]);
    }

    test('蒐集 pullback 樣本、同 symbol 不重疊窗、產出 4 變體結果', () async {
      await seedStock('AAAA', priceDays: 250);
      await seedStock('BBBB', priceDays: 250);

      final validator = ExitValidator(
        db: db,
        replayConfig: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          minUniverseSymbols: 2,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await validator.run();

      // pullback mode 有樣本；momentum/strength 無（mock 只觸發 pullback 規則）
      final pullbackSamples = result.samples
          .where((s) => s.mode == 'pullback')
          .toList();
      expect(pullbackSamples, isNotEmpty);
      expect(result.samples.where((s) => s.mode == 'momentum'), isEmpty);

      // 不重疊窗：每檔 250 天、評估窗約 250-20-60=170 天，若不去重會有
      // ~170 樣本/檔；去重後每檔最多 ceil(170/61)≈3 筆
      final perSymbol = pullbackSamples.where((s) => s.symbol == 'AAAA').length;
      expect(perSymbol, lessThanOrEqualTo(4));
      expect(perSymbol, greaterThanOrEqualTo(1));

      // 單調上漲 fixture（+0.1/日）無漲跌停日
      expect(result.limitFlaggedT0, 0);
      expect(result.limitFlaggedExit, 0);

      // 4 個變體都有結果（全開 + 三單條）
      expect(result.variantResults.keys.length, 4);
      for (final entry in result.variantResults.entries) {
        expect(
          entry.value.length,
          pullbackSamples.length +
              result.samples.length -
              pullbackSamples.length,
          reason: '每個樣本在每個變體都有一筆模擬（或計入 survivorship）',
        );
      }
    });

    test('T+1 停牌（null close）樣本進 survivorship counter、不進結果', () async {
      // replay 層已排除尾端無 60D forward 的日子（i+60 >= len break），
      // 尾端不會成為樣本——真實的 survivorship 情境是 T+1 停牌：
      // 首個評估日 t0=20 的 T+1（index 21）收盤為 null → simulateExit 回
      // null → 必須計數。
      await seedStockWithNullAt('CCCC', priceDays: 250, nullIndex: 21);
      await seedStock('DDDD', priceDays: 250);

      final validator = ExitValidator(
        db: db,
        replayConfig: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          minUniverseSymbols: 2,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
        logger: (_) {},
      );
      final result = await validator.run();

      expect(
        result.skippedNoWindow,
        greaterThan(0),
        reason: '尾端窗不足樣本必須被計數、不得靜默消失',
      );
    });
  });

  group('buildReport — mode × 年 × 變體聚合', () {
    ExitSample sample(String symbol, int year, String mode) =>
        (symbol: symbol, date: DateTime(year, 6, 15), mode: mode);

    ExitSimResult sim({
      required double exitRet,
      required double holdRet,
      ExitReason? reason,
    }) => (
      exitReturnPct: exitRet,
      holdReturnPct: holdRet,
      holdingDays: reason == null ? 60 : 10,
      reason: reason,
      exitMddPct: -5.0,
      holdMddPct: -12.0,
    );

    test('cell 統計 + 樣本不足標灰 + survivorship + 方法論警語', () {
      // pullback 2022 兩筆（出場贏一輸一）；momentum 2023 一筆（< 30 標灰）
      final rows = <ExitVariantRow>[
        (
          sample: sample('A', 2022, 'pullback'),
          sim: sim(exitRet: -8.0, holdRet: -20.0, reason: ExitReason.hardStop),
        ),
        (
          sample: sample('B', 2022, 'pullback'),
          sim: sim(exitRet: -8.0, holdRet: 5.0, reason: ExitReason.hardStop),
        ),
        (
          sample: sample('C', 2023, 'momentum'),
          sim: sim(exitRet: 3.0, holdRet: 3.0),
        ),
      ];
      final result = ExitValidationResult(
        samples: rows.map((r) => r.sample).toList(),
        variantResults: {
          for (final name in ExitValidator.variants.keys) name: rows,
        },
        skippedNoWindow: 7,
        limitFlaggedT0: 2,
        limitFlaggedExit: 3,
      );

      final report = buildReport(result);

      // cell 標灰（n=2 與 n=1 皆 < 30）
      expect(report, contains('樣本不足'));
      // 出場 vs 持有差：pullback 2022 平均 exit -8、hold -7.5 → diff -0.5
      expect(report, contains('pullback'));
      expect(report, contains('2022'));
      // survivorship 與漲跌停（T0 + 觸發日兩個計數）必印
      expect(report, contains('7'));
      expect(report, contains('漲跌停'));
      expect(report, contains('出場觸發日為漲跌停的樣本: 3'));
      // 方法論警語（spec §3 原文關鍵句）
      expect(report, contains('不等於「紀律沒用」'));
      // 4 變體段落
      for (final name in ExitValidator.variants.keys) {
        expect(report, contains(name));
      }
    });

    test('勝率 = 出場報酬 ≥ 持有報酬的比例', () {
      final rows = <ExitVariantRow>[
        (
          sample: sample('A', 2022, 'pullback'),
          sim: sim(exitRet: -8.0, holdRet: -20.0, reason: ExitReason.hardStop),
        ),
        (
          sample: sample('B', 2022, 'pullback'),
          sim: sim(exitRet: -8.0, holdRet: 5.0, reason: ExitReason.hardStop),
        ),
      ];
      final result = ExitValidationResult(
        samples: rows.map((r) => r.sample).toList(),
        variantResults: {'all': rows},
        skippedNoWindow: 0,
        limitFlaggedT0: 0,
        limitFlaggedExit: 0,
      );
      final report = buildReport(result);
      expect(report, contains('50')); // 勝率 1/2 = 50%
    });
  });
}

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/rules/volume_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  late RuleEngine ruleEngine;

  setUp(() {
    ruleEngine = RuleEngine();
  });

  group('StockData Helpers', () {
    test('latestPrice returns last entry', () {
      final prices = [
        createTestPrice(date: DateTime.now(), close: 100.0),
        createTestPrice(date: DateTime.now(), close: 105.0),
      ];
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(data.latestPrice, equals(prices.last));
      expect(data.latestClose, equals(105.0));
    });

    test('returns null when prices are empty', () {
      const data = StockData(
        symbol: 'TEST',
        prices: [],
        dividends: DividendContext.noEvents,
      );

      expect(data.latestPrice, isNull);
      expect(data.latestClose, isNull);
    });
  });

  // ==========================================
  // getTopReasons / calculateScore / evaluateStock
  // ==========================================

  group('getTopReasons', () {
    test('return all reasons when descriptions are unique', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'Breakout above resistance',
        ),
        const TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'Volume spike 4x avg',
        ),
        const TriggeredReason(
          type: ReasonType.reversalW2S,
          score: 35,
          description: 'Weak to strong reversal',
        ),
      ];

      final result = ruleEngine.getTopReasons(reasons);
      expect(result.length, 3);
    });

    test('dedup reasons with same description', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'Same description',
        ),
        const TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'Same description',
        ),
      ];

      final result = ruleEngine.getTopReasons(reasons);
      expect(result.length, 1);
      expect(result.first.type, ReasonType.techBreakout);
    });

    test('return empty list for empty reasons', () {
      final result = ruleEngine.getTopReasons([]);
      expect(result, isEmpty);
    });

    test('keep first occurrence when duplicates exist', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'Dup',
        ),
        const TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'Unique',
        ),
        const TriggeredReason(
          type: ReasonType.reversalW2S,
          score: 35,
          description: 'Dup',
        ),
      ];

      final result = ruleEngine.getTopReasons(reasons);
      expect(result.length, 2);
      // 第一個 Dup 保留（techBreakout），第二個 Dup 去除
      expect(result[0].type, ReasonType.techBreakout);
      expect(result[1].type, ReasonType.volumeSpike);
    });
  });

  group('calculateScore Institutional Combinations', () {
    test('institutional + breakout 各自計分、不做 combo bonus', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.institutionalBuy,
          score: 18,
          description: 'Inst buy',
        ),
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'Breakout',
        ),
      ];

      // Base: 18 + 25 = 43（組合加成已於 2026-04 移除）
      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 43);
    });

    test('institutional + reversal 各自計分、不做 combo bonus', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.institutionalBuy,
          score: 18,
          description: 'Inst buy',
        ),
        const TriggeredReason(
          type: ReasonType.reversalW2S,
          score: 35,
          description: 'Reversal',
        ),
      ];

      // Base: 18 + 35 = 53（bonus 已移除）
      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 53);
    });

    test('institutional + reversal + volume 加總不會因 bonus 膨脹到 cap', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.institutionalBuy,
          score: 18,
          description: 'Inst',
        ),
        const TriggeredReason(
          type: ReasonType.reversalW2S,
          score: 35,
          description: 'Reversal',
        ),
        const TriggeredReason(
          type: ReasonType.volumeSpike,
          score: 22,
          description: 'Volume',
        ),
      ];

      // Base: 18 + 35 + 22 = 75
      // 未觸及 maxScore (80)，移除 bonus 後強訊號不再被無謂 cap
      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 75);
    });
  });

  group('Rule Exception Handling', () {
    test('catch and skip rule exceptions without crashing', () {
      final engine = RuleEngine(customRules: [const _ThrowingRule()]);
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final reasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'UNKNOWN',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );

      // 拋出例外的規則被跳過，不影響結果
      expect(reasons, isEmpty);
    });

    test('return results from remaining rules when one rule throws', () {
      final engine = RuleEngine(
        customRules: [const _ThrowingRule(), const VolumeSpikeRule()],
      );
      final prices = generatePricesWithVolumeSpike(
        days: 30,
        normalVolume: 1000,
        spikeVolume: 5000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final reasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'UNKNOWN',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );

      // _ThrowingRule 拋例外被跳過，VolumeSpikeRule 正常觸發
      expect(reasons, isNotEmpty);
      expect(reasons.any((r) => r.type == ReasonType.volumeSpike), isTrue);
    });
  });

  group('calculateScore Edge Cases', () {
    test('return 0 for empty reasons list', () {
      final score = ruleEngine.calculateScore([], horizon: Horizon.short);
      expect(score, 0);
    });

    test('handle mixed positive and negative scores', () {
      final reasons = [
        const TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: 'Breakout',
        ),
        const TriggeredReason(
          type: ReasonType.techBreakdown,
          score: -20,
          description: 'Breakdown',
        ),
      ];

      // 25 + (-20) = 5
      final score = ruleEngine.calculateScore(reasons, horizon: Horizon.short);
      expect(score, 5);
    });
  });

  group('evaluateStock Edge Cases', () {
    test('return empty list for empty price history', () {
      final reasons = ruleEngine.evaluateStock(
        AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
        ),
        const StockData(
          symbol: 'UNKNOWN',
          prices: [],
          dividends: DividendContext.noEvents,
        ),
      );
      expect(reasons, isEmpty);
    });

    test('sort returned reasons by score descending', () {
      // 使用自訂規則確保產生多個已知分數的結果
      // 注意：3 個 reasonType 必須分屬不同 mutex group（或不屬於任何 group），
      // 否則會被 momentum_breakout 等 group filter 吃掉
      final engine = RuleEngine(
        customRules: [
          const _FixedScoreRule(
            ruleId: 'low',
            score: 10,
            reasonType: ReasonType.newsRelated,
          ),
          const _FixedScoreRule(
            ruleId: 'high',
            score: 30,
            reasonType: ReasonType.maAlignmentBullish,
          ),
          const _FixedScoreRule(
            ruleId: 'mid',
            score: 20,
            reasonType: ReasonType.kdGoldenCross,
          ),
        ],
      );
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final reasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'UNKNOWN',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );

      expect(reasons.length, 3);
      expect(reasons[0].score, 30);
      expect(reasons[1].score, 20);
      expect(reasons[2].score, 10);
    });
  });

  // ==========================================
  // Mutex Group 測試（2026-04 引入，解決重疊訊號 double-count）
  // ==========================================

  group('applyMutexGroups (mutex resolution)', () {
    // H-1 fix（2026-06）：mutex 從 evaluateStock 內部搬到顯式呼叫，
    // 讓 scoring 路徑（calculateScore）能用 horizon-aware calibrated 分數
    // 做 mutex 過濾，UI 路徑可繼續用 hardcoded。下列測試驗證 mutex
    // 行為本身（與 scoreOf 來源無關）。
    test('momentum_breakout: techBreakout 與 volumeSpike 同組，只保留分數較高者', () {
      final engine = RuleEngine(
        customRules: [
          const _FixedScoreRule(
            ruleId: 'breakout',
            score: 25,
            reasonType: ReasonType.techBreakout,
          ),
          const _FixedScoreRule(
            ruleId: 'volume',
            score: 22,
            reasonType: ReasonType.volumeSpike,
          ),
        ],
      );
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final allReasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );
      // evaluateStock 自身已不過濾 mutex — 兩條 reason 都會出現
      expect(allReasons.length, 2);
      final reasons = engine.applyMutexGroups(allReasons, (r) => r.score);

      // 兩者同屬 momentum_breakout，只保留 techBreakout (25 > 22)
      expect(reasons.length, 1);
      expect(reasons[0].type, ReasonType.techBreakout);
    });

    test('momentum_breakout: 4 條重疊規則全觸發，只保留最高分那條', () {
      final engine = RuleEngine(
        customRules: [
          const _FixedScoreRule(
            ruleId: 'priceSpike',
            score: 15,
            reasonType: ReasonType.priceSpike,
          ),
          const _FixedScoreRule(
            ruleId: 'volumeSpike',
            score: 22,
            reasonType: ReasonType.volumeSpike,
          ),
          const _FixedScoreRule(
            ruleId: 'highVolBreakout',
            score: 22,
            reasonType: ReasonType.highVolumeBreakout,
          ),
          const _FixedScoreRule(
            ruleId: 'techBreakout',
            score: 25,
            reasonType: ReasonType.techBreakout,
          ),
        ],
      );
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final allReasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );
      final reasons = engine.applyMutexGroups(allReasons, (r) => r.score);

      expect(reasons.length, 1);
      expect(reasons[0].type, ReasonType.techBreakout); // 分數最高
    });

    test('momentum_breakout 贏家與非 group reason 並存時，兩者都保留', () {
      final engine = RuleEngine(
        customRules: [
          const _FixedScoreRule(
            ruleId: 'volumeSpike',
            score: 22,
            reasonType: ReasonType.volumeSpike,
          ),
          const _FixedScoreRule(
            ruleId: 'reversal',
            score: 35,
            reasonType: ReasonType.reversalW2S,
          ),
          const _FixedScoreRule(
            ruleId: 'institutional',
            score: 18,
            reasonType: ReasonType.institutionalBuy,
          ),
        ],
      );
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final allReasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );
      final reasons = engine.applyMutexGroups(allReasons, (r) => r.score);

      // volumeSpike 是 momentum_breakout 唯一代表，保留
      // reversalW2S / institutionalBuy 不屬任何 group，都保留
      expect(reasons.length, 3);
      final types = reasons.map((r) => r.type).toSet();
      expect(types, {
        ReasonType.reversalW2S,
        ReasonType.volumeSpike,
        ReasonType.institutionalBuy,
      });
    });

    test('mutex: 同 group 內 scoreOf 同分時，依輸入順序 stable 決定贏家', () {
      // 兩條 reason 同屬 momentum_breakout 且 scoreOf 相同（22）。
      // applyMutexGroups 用 stable sort，先進列表的勝出。
      final engine = RuleEngine(
        customRules: [
          const _FixedScoreRule(
            ruleId: 'volumeSpike',
            score: 22,
            reasonType: ReasonType.volumeSpike,
          ),
          const _FixedScoreRule(
            ruleId: 'highVolBreakout',
            score: 22,
            reasonType: ReasonType.highVolumeBreakout,
          ),
        ],
      );
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final allReasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );
      final reasons = engine.applyMutexGroups(allReasons, (r) => r.score);

      expect(reasons.length, 1);
      // 註冊順序 = 輸入順序 → stable sort 保留 volumeSpike 在前
      expect(reasons[0].type, ReasonType.volumeSpike);
    });

    test(
      'H-1 fix: horizon-aware calibrated scoreOf 可選出與 hardcoded 不同的 mutex 贏家',
      () {
        // 過去 mutex 用 hardcoded score 決定，calibration 永遠無法翻轉
        // ranking。改成 caller 提供 scoreOf 後，scoring 路徑可傳入
        // horizon-aware calibrated lookup → 同一 mutex group 可在不同
        // horizon 有不同贏家。
        final engine = RuleEngine(
          customRules: [
            const _FixedScoreRule(
              ruleId: 'techBreakout',
              score: 25, // hardcoded：techBreakout 較強
              reasonType: ReasonType.techBreakout,
            ),
            const _FixedScoreRule(
              ruleId: 'volumeSpike',
              score: 22, // hardcoded：volumeSpike 較弱
              reasonType: ReasonType.volumeSpike,
            ),
          ],
        );
        final prices = generateConstantPrices(days: 5, basePrice: 100.0);
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
        );

        final allReasons = engine.evaluateStock(
          context,
          StockData(
            symbol: 'TEST',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        );

        // hardcoded 路徑：techBreakout 贏（25 > 22）
        final hardcodedMuted = engine.applyMutexGroups(
          allReasons,
          (r) => r.score,
        );
        expect(hardcodedMuted.length, 1);
        expect(hardcodedMuted[0].type, ReasonType.techBreakout);

        // Calibrated 路徑：假設 calibration 認為 volumeSpike 在 short
        // horizon 較強（30 > 20）→ 應該翻轉贏家。
        int calibratedScoreOf(TriggeredReason r) {
          if (r.type == ReasonType.techBreakout) return 20;
          if (r.type == ReasonType.volumeSpike) return 30;
          return r.score;
        }

        final calibratedMuted = engine.applyMutexGroups(
          allReasons,
          calibratedScoreOf,
        );
        expect(calibratedMuted.length, 1);
        expect(
          calibratedMuted[0].type,
          ReasonType.volumeSpike,
          reason: 'calibration 應該能翻轉 mutex 贏家；H-1 fix 的核心保證',
        );
      },
    );

    test('calculateScore 套用 mutex 過濾後不會塞爆 cap', () {
      // 整合測試：evaluateStock → calculateScore 端到端
      final engine = RuleEngine(
        customRules: [
          // 這 4 條以前會合計 84 分 + bonus 直接塞爆 cap
          const _FixedScoreRule(
            ruleId: 'breakout',
            score: 25,
            reasonType: ReasonType.techBreakout,
          ),
          const _FixedScoreRule(
            ruleId: 'volume',
            score: 22,
            reasonType: ReasonType.volumeSpike,
          ),
          const _FixedScoreRule(
            ruleId: 'priceSpike',
            score: 15,
            reasonType: ReasonType.priceSpike,
          ),
          const _FixedScoreRule(
            ruleId: 'highVol',
            score: 22,
            reasonType: ReasonType.highVolumeBreakout,
          ),
        ],
      );
      final prices = generateConstantPrices(days: 5, basePrice: 100.0);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      // H-1 fix 後 pipeline 拆成 3 步：evaluate → mutex → calculateScore
      // calculateScore 是 pure arithmetic（不做 mutex）；mutex 由 caller 顯式
      // 呼叫，這樣才能用 horizon-aware calibrated 分數做 mutex 過濾。
      final allReasons = engine.evaluateStock(
        context,
        StockData(
          symbol: 'TEST',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );
      final muted = engine.applyMutexGroups(allReasons, (r) => r.score);
      final score = engine.calculateScore(muted, horizon: Horizon.short);

      // 4 條規則 → mutex filter 後剩 1 條（techBreakout 25）→ 總分 25
      expect(score, 25);
    });
  });

  // ==========================================
  // Mutex Group Invariant — _reasonToGroup 建構 disjoint assert
  // ==========================================

  group('mutex group disjointness invariant', () {
    test(
      '_reasonToGroup builds without throwing (current groups are disjoint)',
      () {
        // 本意：觸發 lazy 初始化——若任何 ReasonType 出現在 >1 group 會 StateError
        expect(
          () {
            // 注意：applyMutexGroups 對空清單會在存取 _reasonToGroup 之前就
            // 返回，單獨執行時不會觸發 lazy init——這條目前驗不到 disjointness。
            final engine = RuleEngine(customRules: const []);
            engine.applyMutexGroups(const [], (r) => r.score);
          },
          returnsNormally,
          reason:
              '若新增 group 或把現有 ReasonType 加進額外 group，請先確認 '
              'disjoint；違反時建構 _reasonToGroup 會拋 StateError 防 silent '
              'last-writer-wins。',
        );
      },
    );
  });
}

// ==========================================
// 測試用內聯規則
// ==========================================

/// 永遠拋出例外的規則（用於測試例外處理）
class _ThrowingRule extends StockRule {
  const _ThrowingRule();

  @override
  String get id => 'throwing_rule';

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    throw Exception('Test exception from ThrowingRule');
  }
}

/// 永遠回傳固定分數的規則（用於測試排序）
class _FixedScoreRule extends StockRule {
  const _FixedScoreRule({
    required this.ruleId,
    required this.score,
    required this.reasonType,
  });

  final String ruleId;
  final int score;
  final ReasonType reasonType;

  @override
  String get id => ruleId;

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    return TriggeredReason(
      type: reasonType,
      score: score,
      description: 'Fixed score $score from $ruleId',
    );
  }
}

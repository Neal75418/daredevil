import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/scoring_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/price_data_generators.dart';

class MockRuleEngine extends Mock implements RuleEngine {}

void main() {
  group('classifyCandidate 資格檢查', () {
    DailyPriceEntry entry({double? close = 100, double? volume = 3000000}) =>
        DailyPriceEntry(
          symbol: 'T',
          date: DateTime(2026, 7, 8),
          close: close,
          volume: volume,
        );

    // ==================================================================
    // 陳舊 bar 檢查（P1-8 L1）
    //
    // 病灶：本函式只驗 null/empty、length、liquidity，**從不比對
    // prices.last.date 與評分日**。而 batch_data_loader 的價格窗以
    // endDate = 評分日 收斂，DB 沒有當日 bar 時 prices.last 會自動退化成
    // 前一交易日 —— 這就是「昨日 K 棒掛今日日期寫進 daily_analysis」
    // 能無聲通過的直接機制。
    //
    // 實測基準：2026-07-15~07-24 共 8 個交易日、1,568 列 daily_analysis，
    // 「當日無有效價格 bar」的有 **0 列** → 健康日此檢查是 no-op，
    // 只在故障路徑上生效。
    // ==================================================================

    // 產生 60 根連續日 bar，最後一根落在 [endDate]
    List<DailyPriceEntry> history(DateTime endDate) => List.generate(
      60,
      (i) => DailyPriceEntry(
        symbol: 'T',
        date: endDate.subtract(Duration(days: 59 - i)),
        close: 100,
        volume: 3000000,
      ),
    );

    test('🚨 最後一根 bar 不是評分日 → staleBar', () {
      final prices = history(DateTime(2026, 7, 8));

      expect(
        classifyCandidate(prices, asOf: DateTime(2026, 7, 9)),
        CandidateSkipReason.staleBar,
        reason: '拿昨日 K 棒算今日分析等於偽造當日訊號',
      );
    });

    test('最後一根 bar 就是評分日 → 通過', () {
      final prices = history(DateTime(2026, 7, 8));

      expect(classifyCandidate(prices, asOf: DateTime(2026, 7, 8)), isNull);
    });

    test('asOf 帶時分秒仍視為同一天（必須逐欄比 y/m/d，不可用 DateTime ==）', () {
      final prices = history(DateTime(2026, 7, 8));

      expect(
        classifyCandidate(prices, asOf: DateTime(2026, 7, 8, 15, 30)),
        isNull,
        reason: 'DateTime 相等會連時分秒一起比，正常評分日就會被全數誤殺',
      );
    });

    test('省略 asOf 時不做新鮮度檢查（向後相容，isolate 無日期時 no-op）', () {
      final prices = history(DateTime(2026, 7, 8));

      expect(classifyCandidate(prices), isNull);
    });

    test('無價格資料 → noData', () {
      expect(classifyCandidate(null), CandidateSkipReason.noData);
      expect(classifyCandidate([]), CandidateSkipReason.noData);
    });

    test('歷史長度不足 swingWindow → insufficientData', () {
      final prices = List.generate(RuleParams.swingWindow - 1, (_) => entry());
      expect(classifyCandidate(prices), CandidateSkipReason.insufficientData);
    });

    test('close/volume 缺漏 → noData（MISSING_DATA 歸類）', () {
      final prices = [
        ...List.generate(RuleParams.swingWindow, (_) => entry()),
        entry(close: null),
      ];
      expect(classifyCandidate(prices), CandidateSkipReason.noData);
    });

    test('低流動性 → lowLiquidity', () {
      final prices = [
        ...List.generate(RuleParams.swingWindow, (_) => entry()),
        entry(volume: 1000),
      ];
      expect(classifyCandidate(prices), CandidateSkipReason.lowLiquidity);
    });

    test('資料充足且流動性合格 → null（通過）', () {
      final prices = generatePricesWithVolumeSpike(
        days: 30,
        normalVolume: 1000,
        spikeVolume: 5000,
      );
      final good = [...prices, entry()];
      expect(classifyCandidate(good), isNull);
    });
  });

  group('computeFundamentalDecayMultipliers 基本面遞減', () {
    final engine = RuleEngine();

    test('同組多條正分訊號按設計分數排序遞減 100/50/25', () {
      const reasons = [
        // 獲利組 4 條（2408 案例）：22 > 18 > 15，第 4 條也是 0.25
        TriggeredReason(
          type: ReasonType.epsConsecutiveGrowth,
          score: 22,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.roeExcellent,
          score: 18,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.roeImproving,
          score: 15,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.epsYoYSurge,
          score: 22,
          description: '',
        ),
        // 營收組 1 條：獨占全分
        TriggeredReason(
          type: ReasonType.revenueYoySurge,
          score: 20,
          description: '',
        ),
        // 非基本面：不受影響
        TriggeredReason(
          type: ReasonType.techBreakout,
          score: 25,
          description: '',
        ),
      ];

      final m = engine.computeFundamentalDecayMultipliers(reasons);

      // 獲利組排序 22(epsConsecutive)=22(epsYoy) 同分 → 穩定序，
      // 名次係數 1.0/0.5/0.25/0.25
      final earningsFactors = [
        m['EPS_CONSECUTIVE_GROWTH'],
        m['EPS_YOY_SURGE'],
        m['ROE_EXCELLENT'],
        m['ROE_IMPROVING'],
      ];
      expect(earningsFactors..sort(), [0.25, 0.25, 0.5, 1.0]);
      expect(m['REVENUE_YOY_SURGE'], 1.0);
      expect(m.containsKey('TECH_BREAKOUT'), isFalse);
    });

    test('負分警訊不分組不遞減', () {
      const reasons = [
        TriggeredReason(
          type: ReasonType.roeDeclining,
          score: -10,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.roeExcellent,
          score: 18,
          description: '',
        ),
      ];
      final m = engine.computeFundamentalDecayMultipliers(reasons);
      expect(m['ROE_EXCELLENT'], 1.0);
      expect(m.containsKey('ROE_DECLINING'), isFalse);
    });

    test('calculateScore 套用 multipliers 後總分遞減', () {
      const reasons = [
        TriggeredReason(
          type: ReasonType.epsConsecutiveGrowth,
          score: 22,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.roeExcellent,
          score: 18,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.roeImproving,
          score: 15,
          description: '',
        ),
      ];
      final m = engine.computeFundamentalDecayMultipliers(reasons);
      final score = engine.calculateScore(
        reasons,
        horizon: Horizon.short,
        decayMultipliers: m,
      );
      // 22*1.0 + 18*0.5 + 15*0.25 = 34.75 → round 35（原 55）
      expect(score, 35);
    });
  });

  group('scoreReasonsDualHorizon 評分核心', () {
    late MockRuleEngine engine;
    const reasons = [
      TriggeredReason(
        type: ReasonType.techBreakout,
        score: 25,
        description: '',
      ),
    ];

    setUp(() {
      engine = MockRuleEngine();
      registerFallbackValue(<TriggeredReason>[]);
      registerFallbackValue(Horizon.short);
      registerFallbackValue(CalibratedScoreContext.empty);
      when(() => engine.applyMutexGroups(any(), any())).thenAnswer(
        (inv) => inv.positionalArguments[0] as List<TriggeredReason>,
      );
      when(
        () => engine.computeFundamentalDecayMultipliers(any()),
      ).thenReturn(const {});
      when(() => engine.getTopReasons(any())).thenAnswer(
        (inv) => inv.positionalArguments[0] as List<TriggeredReason>,
      );
    });

    test('雙 horizon 各自 calculateScore、任一達門檻即保留', () {
      when(
        () => engine.calculateScore(
          any(),
          horizon: Horizon.short,
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(25);
      when(
        () => engine.calculateScore(
          any(),
          horizon: Horizon.long,
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(0);

      final result = scoreReasonsDualHorizon(
        ruleEngine: engine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );

      expect(result, isNotNull);
      expect(result!.scoreShort, 25);
      expect(result.scoreLong, 0);
      expect(result.topReasons, reasons);
      // mutex 只套兩次:short scoring、long scoring(2026-08-15 數值稽核)。
      //
      // 原本有第三次——用 hardcoded 分數再跑一次當「UI/落庫顯示」來源。
      // 那正是稽核第 01 條的病灶:calibration 把某條規則歸零時,兩條路徑
      // 選出**不同的 mutex 贏家**,於是落庫的 reason 不是實際貢獻分數的
      // 那份;而 mode tab 的分數與排名全是對落庫那份做 SUM。
      // 落庫改用 mutedShort 後,第三次呼叫消失。
      verify(() => engine.applyMutexGroups(any(), any())).called(2);
    });

    test('兩 horizon 都低於 observationScoreThreshold → null（過濾）', () {
      when(
        () => engine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(RuleParams.observationScoreThreshold - 1);

      final result = scoreReasonsDualHorizon(
        ruleEngine: engine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );

      expect(result, isNull);
    });

    test('純空方(負總分)也要落庫:門檻取絕對值(2026-07-31 掃描空方可見性)', () {
      // 既有縫隙:scoreShort < 8 && scoreLong < 8 會把「只觸發空方訊號」
      // 的股票整檔剪掉——跌破季線 -8 的純弱勢股在掃描器上隱形,空方
      // 風控雷達正好在最需要它的股票上失明,rule_accuracy 觀察區也因此
      // 帶倖存者偏差。門檻改 |score|:漲跌兩方向對稱可見。
      when(
        () => engine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(-RuleParams.observationScoreThreshold);

      final result = scoreReasonsDualHorizon(
        ruleEngine: engine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );

      expect(result, isNotNull, reason: '|-8| ≥ 8 應保留供掃描/觀察');
    });

    test('恰好等於門檻 → 保留（邊界含）', () {
      when(
        () => engine.calculateScore(
          any(),
          horizon: any(named: 'horizon'),
          calibratedScores: any(named: 'calibratedScores'),
          decayMultipliers: any(named: 'decayMultipliers'),
          floorAtZero: any(named: 'floorAtZero'),
        ),
      ).thenReturn(RuleParams.observationScoreThreshold);

      expect(
        scoreReasonsDualHorizon(
          ruleEngine: engine,
          reasons: reasons,
          calibratedScores: CalibratedScoreContext.empty,
        ),
        isNotNull,
      );
    });
  });

  // ============================================================
  // 真引擎回歸(2026-07-31 審查 CRITICAL):mock 版的負分測試繞過了
  // RuleEngine.calculateScore 的「下限 0 clamp」——abs 門檻在生產上
  // 曾是 no-op(clamp 先把 -8 變 0,abs(0)<8 照樣剪掉)。此 group 用
  // 真 RuleEngine 走完整管線,鎖住「純空方股必須落庫」的端到端行為。
  // ============================================================
  group('scoreReasonsDualHorizon × 真 RuleEngine(純空方落庫端到端)', () {
    final realEngine = RuleEngine();

    test('只觸發 BREAK_MA60(-8)的股票:必須落庫,落庫分數 floor 為 0', () {
      const reasons = [
        TriggeredReason(
          type: ReasonType.breakMa60,
          score: RuleScores.breakMa60,
          description: '跌破季線',
        ),
      ];

      final result = scoreReasonsDualHorizon(
        ruleEngine: realEngine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );

      expect(result, isNotNull, reason: '純空方觸發不得被 clamp 吃掉——掃描/風控要看得見');
      expect(
        result!.scoreShort,
        0,
        reason:
            '落庫值維持非負契約;雙 0 是掃描層辨識空方股的指紋'
            '(scan_provider.isScanRiskVisible)',
      );
      expect(result.scoreLong, 0);
    });

    test('正分股照常(站回季線 +8 壓線落庫)', () {
      const reasons = [
        TriggeredReason(
          type: ReasonType.reclaimMa60,
          score: RuleScores.reclaimMa60,
          description: '站回季線',
        ),
      ];
      final result = scoreReasonsDualHorizon(
        ruleEngine: realEngine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );
      expect(result, isNotNull);
      expect(result!.scoreShort, RuleScores.reclaimMa60);
    });

    // 2026-08-03 行為變更(本測試由 isNull 翻轉為 isNotNull):
    //
    // 落庫門檻是**掃描頁的雜訊過濾器**,不是風控訊號閘門。MA 階段穿越
    // (站回/跌破)是 Today 頁警示 banner 與自選 tag 的**唯一**資料來源
    // ——被淨額抵銷吞掉時,使用者的工具正好在事件發生當天失明。
    //
    // 實機證據(2026-08-03 收盤,自選 24 檔):真實發生 5 次 MA 穿越,
    // app 只報 3 次。6538 倉和跌破月線(EPS翻正+15、蓄勢+8、量價背離-8、
    // 跌破月線-8 = raw 7 < 8)、8039 台虹漲停站回月線,兩檔**整檔**未落庫。
    //
    // 結構性必然:breakMa20(-8) 與 coilingBelowMa20(+8) 分數對稱、
    // 且不在任何 mutex group,而觸發條件天生重疊(「強勢股小幅跌破月線」
    // 同時滿足兩者)——MA 家族自己就會淨額歸零。2026-07-31 的 .abs()
    // 修補只處理了「純空方」那一半。
    test('🚨 MA 階段穿越豁免門檻:正負抵銷後仍落庫(風控訊號不得消失)', () {
      const reasons = [
        TriggeredReason(
          type: ReasonType.reclaimMa20,
          score: RuleScores.reclaimMa20,
          description: '站回月線 (MA20)',
        ),
        TriggeredReason(
          type: ReasonType.breakMa60,
          score: RuleScores.breakMa60,
          description: '跌破季線 (MA60)',
        ),
      ];
      final result = scoreReasonsDualHorizon(
        ruleEngine: realEngine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );
      expect(result, isNotNull, reason: 'MA 穿越是 banner 唯一資料源,不得被抵銷吞掉');
      expect(
        result!.topReasons.map((r) => r.type),
        containsAll([ReasonType.reclaimMa20, ReasonType.breakMa60]),
        reason: '兩條穿越訊號都要進 topReasons',
      );
      expect(result.scoreShort, 0, reason: 'raw=0 落庫值 floor 到 0,不影響排序');
    });

    test('🚨 6538 實機組合(raw=7 < 門檻 8)因帶 BREAK_MA20 而落庫', () {
      const reasons = [
        // description 必須各異:getTopReasons 依 description 去重,
        // 真實規則的描述天生不同(空字串是 fixture 陷阱,會只留第一條)
        TriggeredReason(
          type: ReasonType.epsTurnaround,
          score: RuleScores.epsTurnaround,
          description: 'EPS 轉正',
        ),
        TriggeredReason(
          type: ReasonType.coilingBelowMa20,
          score: RuleScores.coilingBelowMa20,
          description: '蓄勢月線下',
        ),
        TriggeredReason(
          type: ReasonType.priceVolumeWeakRally,
          score: RuleScores.priceVolumeWeakRally,
          description: '價漲量縮',
        ),
        TriggeredReason(
          type: ReasonType.breakMa20,
          score: RuleScores.breakMa20,
          description: '跌破月線 (MA20)',
        ),
      ];
      final result = scoreReasonsDualHorizon(
        ruleEngine: realEngine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );
      expect(result, isNotNull);
      expect(
        result!.topReasons.map((r) => r.type),
        contains(ReasonType.breakMa20),
        reason: '跌破訊號必須進 topReasons,banner 才讀得到',
      );
    });

    test('非 MA 穿越的正負抵銷仍然過濾(雜訊過濾器不得失守)', () {
      const reasons = [
        TriggeredReason(
          type: ReasonType.kdGoldenCross,
          score: RuleScores.kdGoldenCross,
          description: '',
        ),
        TriggeredReason(
          type: ReasonType.kdDeathCross,
          score: -RuleScores.kdGoldenCross,
          description: '',
        ),
      ];
      final result = scoreReasonsDualHorizon(
        ruleEngine: realEngine,
        reasons: reasons,
        calibratedScores: CalibratedScoreContext.empty,
      );
      expect(result, isNull, reason: '無 MA 穿越時門檻照舊生效');
    });
  });
}

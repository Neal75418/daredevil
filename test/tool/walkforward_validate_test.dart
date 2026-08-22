// tool/walkforward_validate.dart 單元測試 — 驗純邏輯（指標 + gate + JSON 載入）。
// 完整 run() 走真實 DB + RuleEngine，待 backfill 完成後以實資料端對端驗。
import 'package:flutter_test/flutter_test.dart';

import '../../tool/replay_calibrator.dart' show RuleStats;
import '../../tool/walkforward_validate.dart';

/// 建一個帶指定樣本的 replay RuleStats（短/長各加 sample）。
RuleStats statsWith({
  List<double> short = const [],
  List<double> long = const [],
}) {
  final s = RuleStats();
  for (final r in short) {
    s.short.addSample(r, 0);
  }
  for (final r in long) {
    s.long.addSample(r, 0);
  }
  return s;
}

FoldResult fold(
  int year, {
  required double shortMarginNewSwe,
  required double shortOld,
  required double longNew,
  required double longOld,
}) {
  return FoldResult(
    testYear: year,
    short: HorizonComparison(
      newSwe: shortMarginNewSwe,
      oldSwe: shortOld,
      newActiveRules: 1,
    ),
    long: HorizonComparison(
      newSwe: longNew,
      oldSwe: longOld,
      newActiveRules: 1,
    ),
    testFirings: 100,
  );
}

void main() {
  group('scoreWeightedExcess', () {
    final testStats = {
      'A': statsWith(short: [10, 10], long: [20, 20]),
      'B': statsWith(short: [2, 2], long: [4, 4]),
    };

    test('以「分數×頻率」加權各 rule 的樣本外超額', () {
      // {A:30,B:10}: (30·2·10 + 10·2·2)/(30·2 + 10·2) = 640/80 = 8
      expect(
        WalkForwardValidator.scoreWeightedExcess(
          {'A': 30, 'B': 10},
          testStats,
          WfHorizon.short,
        ),
        closeTo(8.0, 1e-9),
      );
      // 反向 {A:10,B:30}: 偏重低報酬 rule → 較低 = 4
      expect(
        WalkForwardValidator.scoreWeightedExcess(
          {'A': 10, 'B': 30},
          testStats,
          WfHorizon.short,
        ),
        closeTo(4.0, 1e-9),
      );
    });

    test('score=0（被 cut）與不在校準的 rule 都不計', () {
      // {A:30,B:0} → 只剩 A → 10
      expect(
        WalkForwardValidator.scoreWeightedExcess(
          {'A': 30, 'B': 0},
          testStats,
          WfHorizon.short,
        ),
        closeTo(10.0, 1e-9),
      );
      // 空校準 → 0
      expect(
        WalkForwardValidator.scoreWeightedExcess(
          const {},
          testStats,
          WfHorizon.short,
        ),
        0.0,
      );
    });
  });

  group('evaluateGate（多準則）', () {
    test('PASS：多數折 NEW 不輸且有勝 + 平均勝幅 > 折間噪音', () {
      final folds = [
        for (final y in [2022, 2023, 2024, 2025, 2026])
          fold(y, shortMarginNewSwe: 5, shortOld: 3, longNew: 5, longOld: 3),
      ];
      final v = WalkForwardValidator.evaluateGate(folds);
      expect(v.passed, isTrue);
    });

    test('FAIL：NEW 沒贏（margin = 0）', () {
      final folds = [
        for (final y in [2022, 2023, 2024])
          fold(y, shortMarginNewSwe: 3, shortOld: 3, longNew: 3, longOld: 3),
      ];
      expect(WalkForwardValidator.evaluateGate(folds).passed, isFalse);
    });

    test('FAIL：單折暴衝、勝幅被噪音淹沒 + 不一致', () {
      final folds = [
        fold(2022, shortMarginNewSwe: 20, shortOld: 0, longNew: 20, longOld: 0),
        fold(2023, shortMarginNewSwe: -1, shortOld: 0, longNew: -1, longOld: 0),
        fold(2024, shortMarginNewSwe: -1, shortOld: 0, longNew: -1, longOld: 0),
      ];
      expect(WalkForwardValidator.evaluateGate(folds).passed, isFalse);
    });

    // 🚨 2026-08-23 改語意：空 folds 不再是「FAIL」而是 setup 錯誤。
    //
    // 原本回 `passed: false`，於是最終輸出是
    // 「FAIL：不建議 ship — 現行校準在樣本外已足夠（有效結論）」——那句話在
    // 一個樣本都沒有時是憑空斷言，而「（有效結論）」正好叫讀者不要追查。
    // 現在改拋例外 → CLI 回 4 → `expect(code, lessThan(2))` 失敗 → Stage 4
    // 看得見。
    test('🚨 空 folds → setup 錯誤，不得偽裝成 gate FAIL', () {
      expect(
        () => WalkForwardValidator.evaluateGate(const []),
        throwsA(isA<Exception>()),
      );
    });

    test('🚨 每折樣本外觸發皆為 0 → 同樣是 setup 錯誤', () {
      final empty = [
        FoldResult(
          testYear: 2024,
          short: const HorizonComparison(
            newSwe: 0,
            oldSwe: 0,
            newActiveRules: 0,
          ),
          long: const HorizonComparison(
            newSwe: 0,
            oldSwe: 0,
            newActiveRules: 0,
          ),
          testFirings: 0,
        ),
      ];
      expect(
        () => WalkForwardValidator.evaluateGate(empty),
        throwsA(isA<Exception>()),
        reason: '沒量到與量到沒優勢不是同一件事',
      );
    });
  });
  // ── gate 必須量「會上線的評分」（2026-08-22）─────────────────────
  //
  // **發現**：`parseCalibratedScores` 只取 raw `score`，被 cut 或不在 JSON
  // 裡的規則一律當 0。但 App 走 `CalibratedScoresTable.lookup`：cut／缺席
  // → null → 呼叫端 fallback 到 hardcoded 分；負證據規則才真的歸零。
  //
  // 後果是 OLD arm 被嚴重低估。2026-08-22 實測長線：walkforward 眼中 OLD
  // 只有 `{EPS_CONSECUTIVE_GROWTH: 22}` 一條，而 App 同時還有
  // INSTITUTIONAL_BUY=18、WEEK_52_HIGH=28 兩條手調分在跑。於是
  // 「18 → 校準 10」被記成 +10 的收益（實際是 −8），「28 → 27」被記成
  // +27（實際是 −1）——三條變動有兩條方向相反，gate 的 5/5 折全正因此
  // 不能當作 promote 依據。
  group('有效分數（gate 與 App 必須一致）', () {
    const hardcoded = {'BULL': 20, 'BEAR': -8, 'CAL': 99};

    // parseJson 缺 schema_version 會整份拒載、ruleCount=0，於是每條都
    // fallback 到 hardcoded——測試會「通過」卻什麼都沒驗到。這條擋住那種
    // 假測試（2026-08-22 實際踩到）。
    test('🚨 前提：測試 JSON 真的被載入（否則整組測試是空的）', () {
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"CAL":{"score":30,"active":true}}}',
        hardcodedScores: hardcoded,
        horizon: WfHorizon.short,
      );
      expect(
        eff['CAL'],
        isNot(99),
        reason: '若等於 hardcoded 99，代表 JSON 被拒載、後續斷言全部無效',
      );
    });

    test('🚨 對照：cut/缺席若被當成 0（已刪除的舊行為）會是什麼樣', () {
      // parseCalibratedScores 於 2026-08-23 刪除(唯一殘存消費者
      // regime_calibrate 已遷移)。這裡用手算的方式保留對照,說明差別:
      // 舊行為 BULL(cut) → 0、BEAR(缺席) → 不在 map;
      // 正確行為見下一條測試。
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"CAL":{"score":30,"active":true},'
        '"BULL":{"score":0,"active":false,"cut_reason":"t",'
        '"avg_return":1.0,"t_stat":0.5}}}',
        hardcodedScores: hardcoded,
        horizon: WfHorizon.short,
      );
      expect(eff['BULL'], isNot(0), reason: '舊行為會給 0,正確行為給 hardcoded');
      expect(eff['BEAR'], isNot(null), reason: '缺席不得從 map 消失');
    });

    test('🚨 cut 的規則要回 hardcoded，不是 0', () {
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"CAL":{"score":30,"active":true},'
        '"BULL":{"score":0,"active":false,"cut_reason":"t_stat_below_threshold",'
        '"avg_return":1.0,"t_stat":0.5}}}',
        hardcodedScores: hardcoded,
        horizon: WfHorizon.short,
      );
      expect(eff['BULL'], 20, reason: 'cut 但無負證據 → fallback 手調 20');
      expect(eff['CAL'], 30, reason: 'active → 用校準分');
    });

    test('🚨 完全不在 JSON 的規則也要回 hardcoded', () {
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"CAL":{"score":30,"active":true}}}',
        hardcodedScores: hardcoded,
        horizon: WfHorizon.short,
      );
      expect(eff['BULL'], 20);
      expect(eff['BEAR'], -8);
    });

    test('🚨 負證據（多方宣稱 + avg<0 + t≤−1.5）才歸零', () {
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"BULL":{"score":0,"active":false,'
        '"cut_reason":"t_stat_below_threshold","avg_return":-0.5,"t_stat":-6.0}}}',
        hardcodedScores: hardcoded,
        applyZeroing: true,
        horizon: WfHorizon.short,
      );
      expect(eff['BULL'], 0, reason: '多方規則被負證據判死 → 歸零');
    });

    test('空方規則有負證據也不歸零（方向 gate）', () {
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"BEAR":{"score":0,"active":false,'
        '"cut_reason":"t_stat_below_threshold","avg_return":-0.5,"t_stat":-6.0}}}',
        hardcodedScores: hardcoded,
        applyZeroing: true,
        horizon: WfHorizon.short,
      );
      expect(eff['BEAR'], -8, reason: '空方觸發後下跌是命題成立，拔防護才是錯的');
    });

    test('歸零不套用時（長線）維持 hardcoded', () {
      final eff = effectiveScores(
        '{"schema_version":1,"rules":{"BULL":{"score":0,"active":false,'
        '"cut_reason":"t_stat_below_threshold","avg_return":-0.5,"t_stat":-6.0}}}',
        hardcodedScores: hardcoded,
        applyZeroing: false,
        horizon: WfHorizon.long,
      );
      expect(eff['BULL'], 20);
    });
  });
}

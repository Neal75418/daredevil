// tool/walkforward_validate.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// A3：walk-forward 樣本外驗證 gate。
//
// 回答唯一的核心問題：「用修正後方法論重新校準（橫斷面超額報酬 + look-ahead 修正）
// 產生的 rule scores，在『沒看過的年份』上是否真的不輸現行 production 校準？」
//
// ## 做法（leave-one-year-out）
//
// 對每個 fold 年 Y（預設 2022-2026）：
//   1. TRAIN：replay 排除 Y 的所有其他年 → 每條 rule 的超額報酬統計
//      → Calibrator.calibrateAll → NEW 校準（rule → score）。
//   2. TEST：replay 只跑 Y → 每條 rule 在 Y 的「樣本外」超額報酬統計。
//   3. 指標 score-weighted OOS excess（rule-level proxy for pick quality）：
//        SWE(C) = Σ C[rule]·testTrigger[rule]·testExcess[rule]
//               / Σ C[rule]·testTrigger[rule]
//      = 「以校準分數為權重，樣本外能拿到的超額報酬」。
//   4. 比 NEW vs OLD（現行 assets/*.json）的 SWE。
//
// ## Gate（多準則，全部要過才建議 ship）
//   - 平均勝幅 > 0 且 > 折間離散度（贏過噪音）
//   - 多數折 NEW ≥ OLD（一致性，非單折暴衝）
//   - 2022 空頭折單獨報告（user 最在意「跨空頭撐不撐得住」）
//
// ⚠️ rule-level proxy：以「分數×頻率」加權各 rule 的樣本外超額，近似 pick 品質。
//    逐股 pick-level 回測（combination of rules per stock）列為後續 refinement。
//    詳見 docs/plans/2026-06-22-rule-score-recalibration-design.md §5。
//
// ## 使用方式（flutter test wrapper；dart run 亦可——drift_flutter 已拆離）
//   見 scripts；env: CALIBRATION_DB, WF_FOLD_YEARS（CSV，預設 2022,2023,2024,2025,2026）

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:daredevil/data/database/app_database.dart';

import 'recalibrate.dart' as recal;
import 'replay_calibrator.dart';

// ============================================================================
// Public data models (importable by tests)
// ============================================================================

/// 單一 horizon 的新舊 SWE 對比
class HorizonComparison {
  const HorizonComparison({
    required this.newSwe,
    required this.oldSwe,
    required this.newActiveRules,
  });

  final double newSwe;
  final double oldSwe;
  final int newActiveRules;

  double get margin => newSwe - oldSwe;
}

/// 單一 fold（測試年）的結果
class FoldResult {
  const FoldResult({
    required this.testYear,
    required this.short,
    required this.long,
    required this.testFirings,
  });

  final int testYear;
  final HorizonComparison short;
  final HorizonComparison long;
  final int testFirings;
}

/// 整體 walk-forward 判定
class WalkForwardVerdict {
  const WalkForwardVerdict({
    required this.folds,
    required this.passed,
    required this.reasons,
  });

  final List<FoldResult> folds;
  final bool passed;
  final List<String> reasons;
}

// ============================================================================
// Core validator (testable via dep injection)
// ============================================================================

class WalkForwardValidator {
  WalkForwardValidator({
    required this.db,
    required this.oldShortScores,
    required this.oldLongScores,
    required this.foldYears,
    this.symbolsWhitelist,
    this.minUniverseSymbols = 100,
    void Function(String)? logger,
  }) : _log = logger ?? print;

  final AppDatabase db;

  /// 現行 production 校準（rule → score），由 assets/*.json 載入。
  final Map<String, int> oldShortScores;
  final Map<String, int> oldLongScores;

  /// 要當測試年的 fold（leave-one-year-out）。
  final List<int> foldYears;

  /// 限定 universe 的 symbol 樣本（流動性前 N 檔）。full-market 全期 replay
  /// 運算量太大（~千萬次 eval × 10 replays），故 walk-forward 跑流動性樣本。
  /// null = 全市場（測試/小資料用）。
  final List<String>? symbolsWhitelist;
  final int minUniverseSymbols;
  final void Function(String) _log;

  Future<WalkForwardVerdict> run() async {
    final folds = <FoldResult>[];

    for (final year in foldYears) {
      _log('');
      _log('═══ Fold: test year $year（train = 其餘所有年）═══');

      final yearStart = DateTime(year);
      final yearEnd = DateTime(year, 12, 31);

      // 1. TRAIN：排除測試年 → calibrate
      _log('  ▶️  train replay（排除 $year）...');
      final trainStats = await ReplayCalibrator(
        db: db,
        config: ReplayConfig(
          dbPath: ':memory:',
          minUniverseSymbols: minUniverseSymbols,
          symbolsWhitelist: symbolsWhitelist,
          excludeFilter: (start: yearStart, end: yearEnd),
          // 折內 replay 是評估用的子窗口,不得覆寫正式校準結果——
          // dbPath 的 ':memory:' 不會讓寫入轉向,落檔用的是傳進來的 db。
          persist: false,
        ),
        logger: (_) {},
      ).run();
      final newShort = _calibrateFromReplay(
        trainStats.ruleStats,
        WfHorizon.short,
        baselineHit: trainStats.universeBaselineHit5,
      );
      final newLong = _calibrateFromReplay(
        trainStats.ruleStats,
        WfHorizon.long,
        baselineHit: trainStats.universeBaselineHit60,
      );

      // 2. TEST：只跑測試年 → 樣本外 rule 統計
      _log('  ▶️  test replay（只 $year）...');
      final testStats = await ReplayCalibrator(
        db: db,
        config: ReplayConfig(
          dbPath: ':memory:',
          minUniverseSymbols: minUniverseSymbols,
          symbolsWhitelist: symbolsWhitelist,
          dateFilter: (start: yearStart, end: yearEnd),
          // 折內 replay 是評估用的子窗口,不得覆寫正式校準結果——
          // dbPath 的 ':memory:' 不會讓寫入轉向,落檔用的是傳進來的 db。
          persist: false,
        ),
        logger: (_) {},
      ).run();

      // 3. SWE 新 vs 舊
      final shortCmp = HorizonComparison(
        newSwe: scoreWeightedExcess(
          newShort,
          testStats.ruleStats,
          WfHorizon.short,
        ),
        oldSwe: scoreWeightedExcess(
          oldShortScores,
          testStats.ruleStats,
          WfHorizon.short,
        ),
        newActiveRules: newShort.values.where((s) => s > 0).length,
      );
      final longCmp = HorizonComparison(
        newSwe: scoreWeightedExcess(
          newLong,
          testStats.ruleStats,
          WfHorizon.long,
        ),
        oldSwe: scoreWeightedExcess(
          oldLongScores,
          testStats.ruleStats,
          WfHorizon.long,
        ),
        newActiveRules: newLong.values.where((s) => s > 0).length,
      );

      _log(
        '  📊 $year  短: NEW ${shortCmp.newSwe.toStringAsFixed(2)} vs '
        'OLD ${shortCmp.oldSwe.toStringAsFixed(2)} (Δ ${shortCmp.margin.toStringAsFixed(2)})'
        '  長: NEW ${longCmp.newSwe.toStringAsFixed(2)} vs '
        'OLD ${longCmp.oldSwe.toStringAsFixed(2)} (Δ ${longCmp.margin.toStringAsFixed(2)})',
      );

      folds.add(
        FoldResult(
          testYear: year,
          short: shortCmp,
          long: longCmp,
          testFirings: testStats.totalFirings,
        ),
      );
    }

    return evaluateGate(folds);
  }

  /// 從 replay 的 in-memory ruleStats 校準出 NEW 分數（rule → score）。
  ///
  /// 走 **clustered 決策層**（與 CLI recalibrate 同一條路，消除先前
  /// 「walkforward 用 0.5、CLI 用絕對 baseline」的雙路 drift）：
  /// [baselineHit] 取自 train replay 對全 universe 實測的
  /// P(excess ≥ threshold)；null（極小樣本測試情境）fallback 0.5。
  Map<String, int> _calibrateFromReplay(
    Map<String, RuleStats> replayStats,
    WfHorizon horizon, {
    double? baselineHit,
  }) {
    final list = <recal.RuleStats>[];
    for (final entry in replayStats.entries) {
      final h = horizon == WfHorizon.short
          ? entry.value.short
          : entry.value.long;
      list.add(
        recal.RuleStats(
          ruleId: entry.key,
          hitRate: h.hitRate,
          avgReturn: h.avgReturn,
          triggerCount: h.triggerCount,
          dailyMeans: h.dailyMeans,
        ),
      );
    }
    final calibrated = recal.Calibrator.calibrateAllClustered(
      list,
      baselineHit: baselineHit ?? 0.5,
    );
    // 走 App 的三態 lookup（cut/缺席 → hardcoded、負證據 → 0），否則
    // NEW arm 與 OLD arm 量的不是同一個評分函式。序列化成
    // `recalibrate` 寫檔用的同一個形狀，讓 parseJson 原樣消費。
    return effectiveScores(
      jsonEncode({
        'schema_version': 1,
        'rules': {for (final e in calibrated.entries) e.key: e.value.toJson()},
      }),
      applyZeroing: horizon == WfHorizon.short,
    );
  }

  /// score-weighted out-of-sample excess：以校準分數×樣本外頻率為權重，
  /// 加權各 rule 在測試年的樣本外超額報酬。score=0（被 cut）不計。
  static double scoreWeightedExcess(
    Map<String, int> calibration,
    Map<String, RuleStats> testStats,
    WfHorizon horizon,
  ) {
    var numerator = 0.0;
    var denominator = 0.0;
    for (final entry in testStats.entries) {
      final score = calibration[entry.key] ?? 0;
      if (score <= 0) continue;
      final h = horizon == WfHorizon.short
          ? entry.value.short
          : entry.value.long;
      if (h.triggerCount == 0) continue;
      final weight = score * h.triggerCount;
      numerator += weight * h.avgReturn;
      denominator += weight;
    }
    return denominator > 0 ? numerator / denominator : 0.0;
  }

  /// 多準則 gate 判定（短+長 horizon 各算，合併判斷）。public static 供測試。
  static WalkForwardVerdict evaluateGate(List<FoldResult> folds) {
    final reasons = <String>[];
    if (folds.isEmpty) {
      return WalkForwardVerdict(
        folds: folds,
        passed: false,
        reasons: const ['無 fold 結果（資料不足？）'],
      );
    }

    // 合併短+長 margin 當「整體勝幅」樣本
    final margins = <double>[];
    var newWinFolds = 0;
    for (final f in folds) {
      margins
        ..add(f.short.margin)
        ..add(f.long.margin);
      // 一折算「NEW 贏」：短長都不輸 + 至少一邊嚴格贏
      final notWorse = f.short.margin >= 0 && f.long.margin >= 0;
      final someBetter = f.short.margin > 0 || f.long.margin > 0;
      if (notWorse && someBetter) newWinFolds++;
    }

    final meanMargin = margins.reduce((a, b) => a + b) / margins.length;
    final stdMargin = _stdDev(margins, meanMargin);

    // 準則 1：平均勝幅 > 0 且 > 折間離散度（贏過噪音）
    final beatsNoise = meanMargin > 0 && meanMargin > stdMargin;
    // 準則 2：多數折 NEW 贏
    final consistent = newWinFolds * 2 > folds.length;
    // 2022 空頭折（若有）單獨報告
    final bearFold = folds.where((f) => f.testYear == 2022).toList();

    reasons.add(
      '平均勝幅 ${meanMargin.toStringAsFixed(2)}（折間 std ${stdMargin.toStringAsFixed(2)}）'
      '${beatsNoise ? " ✓贏過噪音" : " ✗未贏過噪音"}',
    );
    reasons.add(
      '$newWinFolds/${folds.length} 折 NEW 不輸且有勝'
      '${consistent ? " ✓一致" : " ✗不一致"}',
    );
    if (bearFold.isNotEmpty) {
      final b = bearFold.first;
      reasons.add(
        '2022 空頭折：短 Δ ${b.short.margin.toStringAsFixed(2)}、'
        '長 Δ ${b.long.margin.toStringAsFixed(2)}'
        '${(b.short.margin >= 0 && b.long.margin >= 0) ? " ✓空頭不輸" : " ⚠️空頭輸"}',
      );
    }

    final passed = beatsNoise && consistent;
    reasons.add(
      passed
          ? '➡️  PASS：建議可考慮 ship（仍須人工 review 分數變動）'
          : '➡️  FAIL：不建議 ship — 現行校準在樣本外已足夠（有效結論）',
    );

    return WalkForwardVerdict(folds: folds, passed: passed, reasons: reasons);
  }

  static double _stdDev(List<double> xs, double mean) {
    if (xs.length < 2) return 0.0;
    final variance =
        xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
        (xs.length - 1);
    return variance <= 0 ? 0.0 : math.sqrt(variance);
  }
}

enum WfHorizon { short, long }

// ============================================================================
// JSON loading
// ============================================================================

/// 從 calibrated scores JSON（assets/rule_scores_calibrated_*.json）載入
/// rule → score。檔案 shape 見 recalibrate.dart `_processHorizon`。
Map<String, int> parseCalibratedScores(String jsonStr) {
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
  final rules = decoded['rules'] as Map<String, dynamic>? ?? const {};
  final result = <String, int>{};
  for (final entry in rules.entries) {
    final rule = entry.value as Map<String, dynamic>;
    final score = (rule['score'] as num?)?.toInt() ?? 0;
    result[entry.key] = score;
  }
  return result;
}

/// gate 的兩個 arm 共用 `recalibrate` 的 [recal.effectiveScores]。
///
/// **刻意不在此重寫一份**（2026-08-22）：今天最大的那個 bug 正是
/// walkforward 用自己的 `parseCalibratedScores` 重寫了 App 的 lookup 語意
/// （cut／缺席當 0，而非 fallback 到 hardcoded），使 OLD arm 被低估、長線
/// 平均勝幅虛報成 +5.60（實際 −0.048）。同一段語意存兩份，遲早再分岔一次。
Map<String, int> effectiveScores(
  String jsonStr, {
  Map<String, int>? hardcodedScores,
  bool applyZeroing = false,
}) => recal.effectiveScores(
  jsonStr,
  hardcodedScores: hardcodedScores,
  applyZeroing: applyZeroing,
);

// ============================================================================
// CLI entry
// ============================================================================

Future<void> main(List<String> args) async {
  final code = await runWalkForwardCli(args);
  exit(code);
}

Future<int> runWalkForwardCli(List<String> args) async {
  final dbPath =
      Platform.environment['CALIBRATION_DB'] ?? 'tool/calibration.db';
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 不存在: $dbPath（先跑 backfill）');
    return 2;
  }

  final shortFile = File('assets/rule_scores_calibrated_short.json');
  final longFile = File('assets/rule_scores_calibrated_long.json');
  if (!shortFile.existsSync() || !longFile.existsSync()) {
    stderr.writeln(
      '❌ 找不到現行 calibrated scores（assets/rule_scores_calibrated_*.json）',
    );
    return 3;
  }

  final foldYears =
      (Platform.environment['WF_FOLD_YEARS'] ?? '2022,2023,2024,2025,2026')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();

  // 流動性樣本：full-market 全期 replay × 10 運算量太大，故跑 top-N 流動股。
  // ⚠️ top-by-volume 含存活者偏誤（已知限制，見 design §9）；對「方法論方向性
  // 驗證」足夠。WF_SAMPLE_SIZE=0 → 全市場（小資料/測試用）。
  final sampleSize =
      int.tryParse(Platform.environment['WF_SAMPLE_SIZE'] ?? '400') ?? 400;

  print('📂 DB: $dbPath');
  print('📅 Fold years: ${foldYears.join(", ")}');

  final db = AppDatabase.forToolFile(dbPath);
  try {
    List<String>? sample;
    if (sampleSize > 0) {
      final rows = await db
          .customSelect(
            'SELECT symbol FROM daily_price '
            "WHERE date >= '2021-01-01' "
            'GROUP BY symbol HAVING COUNT(*) > 400 '
            'ORDER BY AVG(volume) DESC LIMIT $sampleSize',
          )
          .get();
      sample = rows.map((r) => r.read<String>('symbol')).toList();
      print('🎯 流動性樣本: ${sample.length} 檔（avg volume top-$sampleSize）');
    }

    final validator = WalkForwardValidator(
      db: db,
      // App 的有效分數，不是 raw score——見 [effectiveScores] 的說明
      oldShortScores: effectiveScores(
        shortFile.readAsStringSync(),
        applyZeroing: true,
      ),
      oldLongScores: effectiveScores(
        longFile.readAsStringSync(),
        applyZeroing: false,
      ),
      foldYears: foldYears,
      symbolsWhitelist: sample,
    );
    final verdict = await validator.run();

    print('');
    print('═' * 60);
    print('WALK-FORWARD 驗證結果');
    print('═' * 60);
    for (final r in verdict.reasons) {
      print('  $r');
    }
    return verdict.passed ? 0 : 1;
  } finally {
    await db.close();
  }
}

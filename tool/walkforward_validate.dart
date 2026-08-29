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

import 'tool_db.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart' as cal;

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

/// setup 問題(非 gate 判準)——資料或參數讓驗證根本跑不成立。
///
/// 與 gate FAIL 嚴格區分:FAIL 是有效結論,setup 錯誤是「這次沒量到東西」。
/// 對應 `runWalkForwardCli` 的 exit code >= 2,`run_walkforward.dart` 的
/// `expect(code, lessThan(2))` 會因此失敗,Stage 4 才看得見。
class _WalkForwardSetupError implements Exception {
  _WalkForwardSetupError(this.message);
  final String message;
  @override
  String toString() => 'WalkForwardSetupError: $message';
}

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
    if (baselineHit == null) {
      throw _WalkForwardSetupError(
        'universe baseline 為 null'
        '(${horizon == WfHorizon.short ? "5D" : "60D"})'
        '——沒有任何一天達到 minUniverseSymbols。'
        '常見成因:WF_SAMPLE_SIZE 小於 minUniverseSymbols(預設 100)。',
      );
    }
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
      // 🚨 不再 `?? 0.5`(2026-08-23)。0.5 正是 CalibrationThresholds 記載
      // 「會系統性低估 alpha、幾乎全 cut」的值,而 baseline 為 null 完全是
      // setup 問題(沒有任何一天達到 minUniverseSymbols)。折內 replay 用靜音
      // logger,退回 0.5 會連唯一的證據都吞掉。
      baselineHit: baselineHit,
    );
    // 走 App 的三態 lookup（cut/缺席 → hardcoded、負證據 → 0），否則
    // NEW arm 與 OLD arm 量的不是同一個評分函式。序列化成
    // `recalibrate` 寫檔用的同一個形狀，讓 parseJson 原樣消費。
    return effectiveScores(
      horizon: horizon,
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
    // 🚨 「沒量到」與「量到但沒優勢」必須分開(2026-08-23)。兩者都會讓所有
    // margin 為 0 → beatsNoise false → 印出「FAIL:現行校準在樣本外已足夠
    // (有效結論)」。那句話在沒有任何樣本時是憑空斷言,而且「(有效結論)」
    // 正好叫讀者不要追查。testFirings 一直有收集,只是從沒被讀過。
    if (folds.isEmpty) {
      throw _WalkForwardSetupError(
        '無 fold 結果——WF_FOLD_YEARS 解析後為空,或該區間沒有可用資料。',
      );
    }
    if (folds.every((f) => f.testFirings == 0)) {
      throw _WalkForwardSetupError(
        '每一折的樣本外觸發數都是 0——測試年沒有任何規則觸發。'
        '常見成因:DB 的資料區間與 WF_FOLD_YEARS 不重疊,或 symbolsWhitelist 為空。',
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

/// gate 的兩個 arm 共用 `recalibrate` 的 [recal.effectiveScores]。
///
/// **刻意不在此重寫一份**（2026-08-22）：當時最大的那個 bug 正是
/// walkforward 用自己的 `parseCalibratedScores` 重寫了 App 的 lookup 語意
/// （cut／缺席當 0，而非 fallback 到 hardcoded），使 OLD arm 被低估、長線
/// 平均勝幅虛報成 +5.60（實際 −0.048）。
///
/// 2026-08-23：`parseCalibratedScores` 已刪除——它當時只從 walkforward 拿掉，
/// 卻仍被 `regime_calibrate.dart` 用來建 OLD arm，同一個 bug 在另一支工具裡
/// 活了一整天。留著一份「看起來能用但語意錯」的函式，遲早有人再用它。
Map<String, int> effectiveScores(
  String jsonStr, {
  required WfHorizon horizon,
  Map<String, int>? hardcodedScores,
  bool applyZeroing = false,
}) => recal.effectiveScores(
  jsonStr,
  horizon: horizon == WfHorizon.short ? cal.Horizon.short : cal.Horizon.long,
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

  final AppDatabase db;
  try {
    db = openToolDatabase(dbPath);
  } on SchemaFingerprintMismatch catch (e) {
    stderr.writeln(e.message);
    return 6;
  }
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

    // 🚨 OLD arm 的載入也要在 setup 錯誤的傘下(2026-08-23)。
    // `effectiveScores` 在 production JSON 被拒載時會拋 StateError——先前它
    // 落在 try 之外,例外會直接逃出 runWalkForwardCli 變成未捕捉錯誤,而
    // calibrate.sh 只會報一句沒有這個成因的「setup 失敗」。
    final WalkForwardVerdict verdict;
    try {
      final validator = WalkForwardValidator(
        db: db,
        // App 的有效分數，不是 raw score——見 [effectiveScores] 的說明
        oldShortScores: effectiveScores(
          shortFile.readAsStringSync(),
          horizon: WfHorizon.short,
          applyZeroing: true,
        ),
        oldLongScores: effectiveScores(
          longFile.readAsStringSync(),
          horizon: WfHorizon.long,
          applyZeroing: false,
        ),
        foldYears: foldYears,
        symbolsWhitelist: sample,
      );
      verdict = await validator.run();
    } on StateError catch (e) {
      // 現行 calibrated JSON 被拒載(壞 JSON／schema_version 不對／drift guard
      // 不過)——那是 setup 問題,不是 gate 判準。
      stderr.writeln('');
      stderr.writeln('❌ WALK-FORWARD 無法完成:現行 calibrated JSON 無法載入');
      stderr.writeln('   $e');
      stderr.writeln('   檢查 assets/rule_scores_calibrated_{short,long}.json');
      return 4;
    } on _WalkForwardSetupError catch (e) {
      // setup 錯誤不是 gate FAIL:什麼都沒量到,不能宣稱「現行校準已足夠」。
      stderr.writeln('');
      stderr.writeln('❌ WALK-FORWARD 無法完成(setup 問題,非 gate 判準)');
      stderr.writeln('   ${e.message}');
      return 4;
    }

    print('');
    print('═' * 60);
    print('WALK-FORWARD 驗證結果');
    print('═' * 60);
    for (final r in verdict.reasons) {
      print('  $r');
    }
    // 🚨 機器可讀的判準(2026-08-23)。先前 PASS/FAIL 只存在於這段文字裡,
    // 而 Stage 4 拿到的是 `flutter test` 的 exit code——gate FAIL 與 PASS
    // 都是 0,於是管線一律印 `✅ PIPELINE COMPLETE`。
    print('WALKFORWARD_VERDICT=${verdict.passed ? "PASS" : "FAIL"}');
    return verdict.passed ? 0 : 1;
  } finally {
    await db.close();
  }
}

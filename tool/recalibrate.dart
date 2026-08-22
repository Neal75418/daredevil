// tool/recalibrate.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 從歷史 `rule_accuracy` 統計產出 candidate calibrated rule scores JSON 檔。
//
// Stage 2 LEAN Commit 3: pipeline build-only。此工具產出 `*_candidate.json`，
// 使用者 review 後手動 rename 成 production filename 才真正生效。Stage 5 的
// runtime loader 才會讀取 production filename。
//
// 使用方式：
//
//   dart run tool/recalibrate.dart                          # 兩個 horizon 都跑
//   dart run tool/recalibrate.dart --db <path>              # 自訂 DB 位置
//   dart run tool/recalibrate.dart --horizon short          # 只跑 5D
//   dart run tool/recalibrate.dart --horizon long           # 只跑 60D
//   dart run tool/recalibrate.dart --dry-run                # 印出但不寫檔
//
// 輸出：
//   assets/rule_scores_calibrated_short_candidate.json
//   assets/rule_scores_calibrated_long_candidate.json
//
// Review workflow：
//   1. 跑完這個工具 → 產出 `*_candidate.json`
//   2. `git diff assets/rule_scores_calibrated_*.json` 看分數變動
//   3. 決定 approve → 手動 rename：
//      mv assets/rule_scores_calibrated_short_candidate.json \
//         assets/rule_scores_calibrated_short.json
//   4. Commit + push
//
// 詳細設計見 docs/plans/2026-04-11-scoring-stage2-design.md 和 docs/CALIBRATION.md

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:daredevil/core/constants/calibration_thresholds.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_table.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart' as cal;
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';

// ============================================================================
// Public data models (importable by tests)
// ============================================================================

/// 單一規則的歷史統計輸入（從 `rule_accuracy` 表讀取）
class RuleStats {
  const RuleStats({
    required this.ruleId,
    required this.hitRate,
    required this.avgReturn,
    required this.triggerCount,
    this.dailyMeans = const [],
  });

  final String ruleId;

  /// 命中率 [0.0, 1.0]
  final double hitRate;

  /// 平均報酬率（%），如 2.5 表示 2.5%
  final double avgReturn;

  /// 總觸發次數
  final int triggerCount;

  /// 每個「觸發日」的橫斷面平均超額報酬（%）序列 — clustered 決策層的
  /// 統計基礎（[Calibrator.clusteredTStat] / [Calibrator.rawWeightClustered]）。
  /// 舊絕對路徑不填（空 list）。
  final List<double> dailyMeans;
}

/// 單一規則的 calibration 結果
class CalibratedRule {
  const CalibratedRule({
    required this.score,
    required this.hitRate,
    required this.avgReturn,
    required this.samples,
    required this.tStat,
    required this.active,
    this.cutReason,
  });

  /// 校準後的分數；cut 規則為 0
  final int score;
  final double hitRate;
  final double avgReturn;
  final int samples;
  final double tStat;
  final bool active;
  final String? cutReason;

  factory CalibratedRule.activeRule({
    required RuleStats stats,
    required double tStat,
    required int score,
  }) {
    return CalibratedRule(
      score: score,
      hitRate: stats.hitRate,
      avgReturn: stats.avgReturn,
      samples: stats.triggerCount,
      tStat: tStat,
      active: true,
    );
  }

  factory CalibratedRule.cutRule({
    required RuleStats stats,
    required double tStat,
    required String reason,
  }) {
    return CalibratedRule(
      score: 0,
      hitRate: stats.hitRate,
      avgReturn: stats.avgReturn,
      samples: stats.triggerCount,
      tStat: tStat,
      active: false,
      cutReason: reason,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'hit_rate': double.parse(hitRate.toStringAsFixed(4)),
      'avg_return': double.parse(avgReturn.toStringAsFixed(4)),
      'samples': samples,
      't_stat': double.parse(tStat.toStringAsFixed(4)),
      'active': active,
      if (cutReason != null) 'cut_reason': cutReason,
    };
  }
}

// ============================================================================
// Calibrator — linear_map_v1 公式 + cut thresholds
// ============================================================================

/// linear_map_v1 校準器
///
/// 流程：
/// 1. Compute z-stat 透過 baseline-aware proportion z-test:
///    `(p - p_baseline) / sqrt(p_baseline(1-p_baseline)/n)`（baseline 依
///    period 查 [CalibrationThresholds.successProbabilityBaselines]）
/// 2. Cut 過濾：`samples < 30` / `z_stat < 1.5`（有號）/ `hit_rate < 0.55`
///    （門檻來源：[CalibrationThresholds]，與 RuleAccuracyService /
///    replay_calibrator 共用同一份常數）
/// 3. 倖存者的 raw weight = `hit_rate × avg_return × sqrt(n)`
/// 4. Min-max normalize 到 [10, 35] 分數區間
abstract final class Calibrator {
  static const double tStatCutThreshold =
      CalibrationThresholds.tStatCutThreshold;
  static const double hitRateCutThreshold =
      CalibrationThresholds.hitRateCutThreshold;
  static const int sampleSizeCutThreshold =
      CalibrationThresholds.sampleSizeCutThreshold;
  static const int minScore = 10;
  static const int maxScore = 35;

  /// Proportion z-test: `z = (p - p_baseline) / sqrt(p_baseline * (1 - p_baseline) / n)`
  ///
  /// **2026-06-18 修正**：之前 null hypothesis 寫死 `0.5`（隨機 50%），
  /// 但台股實證 baseline 跟 (horizon, threshold) 強相關 — 例如 5D ≥ 1.5%
  /// 真實 baseline 是 ~34.6%。用 0.5 算 t-stat 系統性低估 alpha，導致
  /// calibrated JSON 幾乎全 cut（dev DB 觀察 short horizon 0 active rule
  /// 就是這個 bug）。改為從 [CalibrationThresholds.successProbabilityBaselines]
  /// 查表，[baseline] 預設 [CalibrationThresholds.defaultBaselineProbability]
  /// （0.5）保 backward compat 給未列出的 period。
  ///
  /// Variance 公式跟著改：分母用 `baseline * (1 - baseline)` 而非
  /// `hitRate * (1 - hitRate)`。在 null hypothesis 下兩者差異不大、
  /// 但理論上應該用 null hypothesis 的 variance。
  ///
  /// Degenerate case（n=0 或 baseline ∈ {0, 1}）回傳 0.0。
  static double computeTStat(double hitRate, int n, {double baseline = 0.5}) {
    if (n <= 0) return 0.0;
    final variance = baseline * (1 - baseline);
    if (variance <= 0) return 0.0;
    final standardError = sqrt(variance / n);
    if (standardError == 0) return 0.0;
    return (hitRate - baseline) / standardError;
  }

  /// Linear map v1 raw weight before normalization
  static double rawWeight(RuleStats stats) {
    return stats.hitRate * stats.avgReturn * sqrt(stats.triggerCount);
  }

  /// Min-max normalize `raw` into `[minScore, maxScore]` integer.
  ///
  /// 當 `maxRaw == minRaw`（所有 active 規則 raw 相同）時回傳中點避免 division by 0。
  static int linearMapScore(double raw, double minRaw, double maxRaw) {
    if (maxRaw <= minRaw) return (minScore + maxScore) ~/ 2;
    final normalized = (raw - minRaw) / (maxRaw - minRaw);
    final clamped = normalized.clamp(0.0, 1.0);
    return (minScore + clamped * (maxScore - minScore)).round();
  }

  /// Calibrate 單一規則。需要傳入 `minRaw` / `maxRaw`（應從所有 active 規則算出）
  /// 作為 normalization context。
  ///
  /// Cut order (first match wins)：
  /// 1. `sample_too_small` — triggerCount < 30
  /// 2. `t_stat_below_threshold` — z-stat < 1.5
  /// 3. `hit_rate_below_threshold` — hit_rate < 0.55
  static CalibratedRule calibrate(
    RuleStats stats, {
    required double minRaw,
    required double maxRaw,
    double baseline = 0.5,
  }) {
    final tStat = computeTStat(
      stats.hitRate,
      stats.triggerCount,
      baseline: baseline,
    );

    if (stats.triggerCount < sampleSizeCutThreshold) {
      return CalibratedRule.cutRule(
        stats: stats,
        tStat: tStat,
        reason: 'sample_too_small',
      );
    }
    if (tStat < tStatCutThreshold) {
      return CalibratedRule.cutRule(
        stats: stats,
        tStat: tStat,
        reason: 't_stat_below_threshold',
      );
    }
    if (stats.hitRate < hitRateCutThreshold) {
      return CalibratedRule.cutRule(
        stats: stats,
        tStat: tStat,
        reason: 'hit_rate_below_threshold',
      );
    }

    final raw = rawWeight(stats);
    final score = linearMapScore(raw, minRaw, maxRaw);
    return CalibratedRule.activeRule(stats: stats, tStat: tStat, score: score);
  }

  // ==========================================================================
  // 超額模式 clustered 決策層 — 見
  // docs/plans/2026-07-10-excess-decision-layer-clustered-tstat.md
  // ==========================================================================

  /// Date-clustered one-sample t（Fama-MacBeth 式）。
  ///
  /// 對「日均值序列」計 t = mean / (sd / sqrt(D))，sd 用樣本標準差（÷(D−1)）。
  /// 消除 pooled 統計的偽重複（同日橫斷面相關 + 持有窗重疊讓名目 n 遠大於
  /// 有效樣本，|t| 動輒 >200 毫無意義）。
  ///
  /// Degenerate（D < 2 或 sd = 0）回 0.0（無法估變異 → 視為不顯著）。
  static double clusteredTStat(List<double> dailyMeans) {
    final d = dailyMeans.length;
    if (d < 2) return 0.0;
    final mean = dailyMeans.reduce((a, b) => a + b) / d;
    var sq = 0.0;
    for (final x in dailyMeans) {
      sq += (x - mean) * (x - mean);
    }
    final sd = sqrt(sq / (d - 1));
    if (sd <= 0) return 0.0;
    return mean / (sd / sqrt(d));
  }

  /// Clustered raw weight：`hitRate × mean(dailyMeans) × sqrt(distinctDates)`。
  ///
  /// linear_map_v1 形狀不變，但輸入換聚類量 —— 頻繁觸發規則不再靠偽重複的
  /// `sqrt(pooled n)` 撐權重，`sqrt(日數)` 才反映有效樣本規模。
  static double rawWeightClustered(RuleStats stats) {
    final d = stats.dailyMeans.length;
    if (d == 0) return 0.0;
    final mean = stats.dailyMeans.reduce((a, b) => a + b) / d;
    return stats.hitRate * mean * sqrt(d);
  }

  /// 超額模式 cut predicate（與 [calibrateClustered] 共用，防 drift）。
  ///
  /// Cut order (first match wins)：
  /// 1. `sample_too_small` — triggerCount < 30（沿用）
  /// 2. `dates_too_few` — 觸發日數 < [CalibrationThresholds.minDistinctDates]
  /// 3. `t_stat_below_threshold` — clustered t < 1.5
  /// 4. `hit_rate_below_threshold` — hitRate < baseline + lift
  static String? _clusteredCutReason(
    RuleStats stats, {
    required double baselineHit,
  }) {
    if (stats.triggerCount < sampleSizeCutThreshold) {
      return 'sample_too_small';
    }
    if (stats.dailyMeans.length < CalibrationThresholds.minDistinctDates) {
      return 'dates_too_few';
    }
    if (clusteredTStat(stats.dailyMeans) < tStatCutThreshold) {
      return 't_stat_below_threshold';
    }
    if (stats.hitRate <
        baselineHit + CalibrationThresholds.hitRateLiftThreshold) {
      return 'hit_rate_below_threshold';
    }
    return null;
  }

  /// Calibrate 單一規則（clustered 路徑）。tStat 欄位記 clustered t。
  static CalibratedRule calibrateClustered(
    RuleStats stats, {
    required double minRaw,
    required double maxRaw,
    required double baselineHit,
  }) {
    final tStat = clusteredTStat(stats.dailyMeans);
    final cutReason = _clusteredCutReason(stats, baselineHit: baselineHit);
    if (cutReason != null) {
      return CalibratedRule.cutRule(
        stats: stats,
        tStat: tStat,
        reason: cutReason,
      );
    }
    final raw = rawWeightClustered(stats);
    final score = linearMapScore(raw, minRaw, maxRaw);
    return CalibratedRule.activeRule(stats: stats, tStat: tStat, score: score);
  }

  /// Calibrate 整組規則（clustered 路徑）。與 [calibrateAll] 同樣只用
  /// **倖存者**算 normalization range。[baselineHit] 是同一次 replay 對全
  /// universe stock-day 實測的 P(excess ≥ threshold)。
  static Map<String, CalibratedRule> calibrateAllClustered(
    List<RuleStats> allStats, {
    required double baselineHit,
  }) {
    if (allStats.isEmpty) return {};

    final survivors = allStats
        .where((s) => _clusteredCutReason(s, baselineHit: baselineHit) == null)
        .toList();

    var minRaw = 0.0;
    var maxRaw = 1.0;
    if (survivors.isNotEmpty) {
      final rawWeights = survivors.map(rawWeightClustered).toList();
      minRaw = rawWeights.reduce(min);
      maxRaw = rawWeights.reduce(max);
    }

    return {
      for (final stats in allStats)
        stats.ruleId: calibrateClustered(
          stats,
          minRaw: minRaw,
          maxRaw: maxRaw,
          baselineHit: baselineHit,
        ),
    };
  }

  /// 規則是否通過所有 cut thresholds（倖存者判定 predicate）
  ///
  /// 2026-04 Stage 2 code review followup：抽出共享 predicate 給 Pass 1 使用，
  /// 避免 Pass 1（survivor filter）和 Pass 2 （`calibrate()` 內部檢查）hand-inlining
  /// 邏輯造成 drift。新增 cut 條件時只需改 [calibrate] 的 branch 跟這個 predicate。
  static bool _passesCuts(RuleStats stats, {double baseline = 0.5}) {
    if (stats.triggerCount < sampleSizeCutThreshold) return false;
    if (stats.hitRate < hitRateCutThreshold) return false;
    final tStat = computeTStat(
      stats.hitRate,
      stats.triggerCount,
      baseline: baseline,
    );
    if (tStat < tStatCutThreshold) return false;
    return true;
  }

  /// Calibrate 整組規則。normalization range 只用**倖存者**（未被 cut 的規則）算
  /// minRaw/maxRaw，避免 cut 規則（通常是 outlier 小樣本）扭曲 active 規則的
  /// 分數分布。
  ///
  /// [baseline] 是 proportion z-test 的 null hypothesis 機率（market baseline
  /// 命中率）。caller 應從 [CalibrationThresholds.successProbabilityBaselines]
  /// 查 (period → baseline)；未列出 period fallback 至 0.5（行為等同
  /// pre-2026-06-18）。
  static Map<String, CalibratedRule> calibrateAll(
    List<RuleStats> allStats, {
    double baseline = 0.5,
  }) {
    if (allStats.isEmpty) return {};

    // Pass 1: 找出倖存者（共享 predicate，見 [_passesCuts] 設計註解）
    final survivors = allStats
        .where((s) => _passesCuts(s, baseline: baseline))
        .toList();

    // 計算 normalization range
    var minRaw = 0.0;
    var maxRaw = 1.0;
    if (survivors.isNotEmpty) {
      final rawWeights = survivors.map(rawWeight).toList();
      minRaw = rawWeights.reduce(min);
      maxRaw = rawWeights.reduce(max);
    }

    // Pass 2: Calibrate 每一條（包含被 cut 的，要存 cut_reason 到 JSON）
    final result = <String, CalibratedRule>{};
    for (final stats in allStats) {
      result[stats.ruleId] = calibrate(
        stats,
        minRaw: minRaw,
        maxRaw: maxRaw,
        baseline: baseline,
      );
    }
    return result;
  }
}

// ============================================================================
// Clustered 分流 loaders（public 供測試）
// ============================================================================

/// 一次 replay run 的持久化 metadata（`calibration_run_meta` 表）。
class RunMeta {
  const RunMeta({
    required this.returnMode,
    required this.excessThreshold,
    this.baselineHit5,
    this.baselineHit60,
    this.generatedAt,
  });

  final String returnMode;
  final double excessThreshold;
  final double? baselineHit5;
  final double? baselineHit60;

  /// replay 落檔時間（UTC）。舊 DB 或格式壞掉 → null，此時不做陳舊判定。
  final DateTime? generatedAt;

  bool get isExcess => returnMode == 'excess';
}

/// replay 樣本相對於 [now] 的天數。[generatedAt] 為 null → null。
///
/// **刻意不判斷「過期」**：量測顯示時間是錯的軸——1468 個交易日的 DB 多等
/// 一個月只增 1.4% 樣本、t-stat 改善 0.71%，而 73 個 cut 裡 61 個是 t-stat
/// 不足、僅 4 個是樣本不足。天數只當背景資訊印出，判斷交給
/// [compareRuleCoverage]（規則集變動才是真的會讓 replay 樣本失效的事）。
///
/// 未來時間戳（時鐘偏移）得到負數，呼叫端照原樣印出即可。
int? replayAgeInDays(DateTime? generatedAt, DateTime now) => generatedAt == null
    ? null
    : now.toUtc().difference(generatedAt.toUtc()).inDays;

/// 註冊表與 replay 樣本的規則涵蓋差集。
///
/// - [uncalibrated]：註冊表有、replay 樣本沒有——新規則在舊 replay 裡一筆
///   觸發都沒有，只能吃手調分。這是唯一需要重跑完整管線的理由。
/// - [orphaned]：replay 有、註冊表已無——改名或刪除留下的死列，會在
///   candidate JSON 佔位卻永遠查不到。
///
/// 兩邊 id 大小寫不同（`rule_accuracy` 存大寫、`StockRule.id` 是小寫），
/// 一律正規化成大寫再比，否則會整組誤判成差異。輸出排序固定，避免同一份
/// 輸入每次印出不同順序。
({List<String> uncalibrated, List<String> orphaned, int registrySize})
compareRuleCoverage(Set<String> registryIds, Set<String> replayedIds) {
  final registry = registryIds.map((e) => e.toUpperCase()).toSet();
  final replayed = replayedIds.map((e) => e.toUpperCase()).toSet();
  return (
    uncalibrated: registry.difference(replayed).toList()..sort(),
    orphaned: replayed.difference(registry).toList()..sort(),
    registrySize: registry.length,
  );
}

/// 涵蓋檢查的參照集合:**ReasonType code**,不是 `StockRule.id`。
///
/// **兩者是不同命名空間**(2026-08-22 首版比錯):
/// - `StockRule.id`:`pattern_doji`、`institutional_shift`——規則自己的識別碼
/// - `ReasonType.code`:`PATTERN_DOJI_BEARISH`、`INSTITUTIONAL_BUY`——
///   replay 依它記錄觸發,`rule_accuracy.rule_id` 存的就是這個
///
/// 一條規則可依情境發出不同 ReasonType(`pattern_doji` 會發 `patternDoji`
/// 或 `patternDojiBearish`),不是一對一。拿 rule.id 去比會把 3 個正常運作
/// 的 ReasonType 誤報成「已不在註冊表的死列」,未校準數也多算 1 條。
Set<String> coverageReferenceIds() =>
    ReasonType.values.map((r) => r.code.toUpperCase()).toSet();

/// 讀 `rule_accuracy` 裡出現過的所有 rule id。表不存在 → 空集合。
Set<String> readReplayedRuleIds(Database db) {
  try {
    return db
        .select('SELECT DISTINCT rule_id FROM rule_accuracy')
        .map((r) => r['rule_id'] as String)
        .toSet();
  } on SqliteException {
    return const {};
  }
}

/// 讀 `calibration_run_meta`。表不存在（舊 DB、replay 未重跑）→ null。
RunMeta? readRunMeta(Database db) {
  final ResultSet rows;
  try {
    rows = db.select('SELECT key, value FROM calibration_run_meta');
  } on SqliteException {
    return null;
  }
  final map = {for (final r in rows) r['key'] as String: r['value'] as String};
  final mode = map['return_mode'];
  if (mode == null) return null;
  return RunMeta(
    returnMode: mode,
    excessThreshold:
        double.tryParse(map['excess_success_threshold'] ?? '') ?? 0.0,
    baselineHit5: double.tryParse(map['universe_baseline_hit_5d'] ?? ''),
    baselineHit60: double.tryParse(map['universe_baseline_hit_60d'] ?? ''),
    // 一律轉 UTC：落庫是 UTC ISO8601，若被當成本地時間比較會差 8 小時。
    generatedAt: DateTime.tryParse(map['generated_at'] ?? '')?.toUtc(),
  );
}

/// 讀 `rule_daily_stats` 還原每 rule 的日均值序列（依日期升序）。
/// 表不存在 → 空 map（caller 應 fallback 舊路徑）。
Map<String, List<double>> loadDailyMeans(Database db, String period) {
  final ResultSet rows;
  try {
    rows = db.select(
      'SELECT rule_id, mean_return FROM rule_daily_stats '
      'WHERE period = ? ORDER BY rule_id, date',
      [period],
    );
  } on SqliteException {
    return {};
  }
  final result = <String, List<double>>{};
  for (final r in rows) {
    result
        .putIfAbsent(r['rule_id'] as String, () => [])
        .add((r['mean_return'] as num).toDouble());
  }
  return result;
}

// ============================================================================
// CLI main
// ============================================================================

const _horizonShort = 'short';
const _horizonLong = 'long';
const _horizonBoth = 'both';

const _periodShort = '5D';
const _periodLong = '60D';

// Canonical thresholds — 不要在這邊重新寫死數字。三個 writer
// （rule_accuracy_service / replay_calibrator / recalibrate）都讀同一份
// 常數，避免 drift 又寫 rule_accuracy 表造成 calibration 不可重現。
final _thresholdShort =
    CalibrationThresholds.successThresholds[5] ??
    CalibrationThresholds.defaultSuccessThreshold;
final _thresholdLong =
    CalibrationThresholds.successThresholds[60] ??
    CalibrationThresholds.defaultSuccessThreshold;

const _formulaVersion = 'linear_map_v1';

/// 一條規則在 promote 前後的有效分數。
typedef EffectiveScoreChange = ({String ruleId, int before, int after});

/// App 實際使用的「規則 → 有效分數」。
///
/// **不要改成比 `active`／`score`**（2026-08-22 實際踩到）：`active:false,
/// score:0` 與「規則根本不在 JSON 裡」在 App 眼中是兩回事——前者可能被負
/// 證據歸零（lookup 回 0），後者 fallback 到 hardcoded 分。同日寫進
/// `docs/CALIBRATION.md` 的 jq 摘要正是這樣比，短線報「無變動」而實際有 9
/// 條改變；walk-forward gate 也栽在同一個坑。一律走
/// [CalibratedScoresTable.lookup]，不重寫語意。
///
/// [applyZeroing] 對應 `calibrated_scores_registry.dart` 的
/// `horizon == Horizon.short`。
Map<String, int> effectiveScores(
  String jsonStr, {
  Map<String, int>? hardcodedScores,
  bool applyZeroing = false,
}) {
  final hard =
      hardcodedScores ?? {for (final r in ReasonType.values) r.code: r.score};
  final table = CalibratedScoresTable.parseJson(
    jsonStr,
    horizon: applyZeroing ? cal.Horizon.short : cal.Horizon.long,
    knownRuleIds: hard.keys.toSet(),
    hardcodedScores: hard,
    applyNegativeEvidenceZeroing: applyZeroing,
    structuralExemptions: ModeFilters.modeCRequiredAnyOf,
  ).table;
  return {for (final id in hard.keys) id: table.lookup(id) ?? hard[id] ?? 0};
}

/// production 與 candidate 的有效分數差異，依 ruleId 排序。
List<EffectiveScoreChange> diffEffectiveScores(
  String productionJson,
  String candidateJson, {
  Map<String, int>? hardcodedScores,
  bool applyZeroing = false,
}) {
  final a = effectiveScores(
    productionJson,
    hardcodedScores: hardcodedScores,
    applyZeroing: applyZeroing,
  );
  final b = effectiveScores(
    candidateJson,
    hardcodedScores: hardcodedScores,
    applyZeroing: applyZeroing,
  );
  final ids = ({...a.keys, ...b.keys}.toList())..sort();
  return [
    for (final id in ids)
      if ((a[id] ?? 0) != (b[id] ?? 0))
        (ruleId: id, before: a[id] ?? 0, after: b[id] ?? 0),
  ];
}

/// 印出「promote 這份 candidate 之後,App 的有效分數會怎麼變」。
///
/// review gate 的主要判讀面。`git diff` 對 candidate 永遠是空的(它們在
/// .gitignore 內),而比對 `active`/`score` 會漏掉「缺席 → 被 cut」這類
/// 變動——那正是負證據歸零生效的地方。這裡走 App 的三態 lookup,印出的
/// 就是實際會發生的事。
///
/// 檔案缺失時安靜跳過:單 horizon 執行或首次產出都可能沒有對應檔。
void _printPromoteImpact() {
  print('');
  print('═══ Promote 影響(App 有效分數)═══');
  for (final (name, zeroing) in [
    (_horizonShort, true),
    (_horizonLong, false),
  ]) {
    final prod = File('assets/rule_scores_calibrated_$name.json');
    final cand = File('assets/rule_scores_calibrated_${name}_candidate.json');
    if (!prod.existsSync() || !cand.existsSync()) continue;

    final changes = diffEffectiveScores(
      prod.readAsStringSync(),
      cand.readAsStringSync(),
      applyZeroing: zeroing,
    );
    final tag = zeroing ? '負證據歸零生效' : '負證據歸零不套用';
    if (changes.isEmpty) {
      print('  $name($tag):有效分數無變化');
      continue;
    }
    print('  $name($tag):${changes.length} 條有效分數變動');
    for (final c in changes) {
      print('    ${c.ruleId.padRight(30)} ${c.before} → ${c.after}');
    }
  }
}

/// 印出這份 DB 的 replay 背景資訊與規則涵蓋落差。
///
/// 只跑本工具（＝三階段的最後一段）會沿用既有 replay 樣本重算，而 exit code
/// 0、candidate JSON 照常產出、無任何異常——與 launchd CLI 產物落後同屬
/// 「過期但三個訊號全正常」，同樣靠把事實印出來解決。
///
/// 印涵蓋差集而非「距今幾天」的判決：差集直接說出是**哪幾條**規則沒有統計
/// 基礎，天數說不出來。刻意不擋——只重算末段是合法用法（調統計方法或閾值
/// 時），這裡只負責讓它成為有意識的選擇。
void _printReplayContext(Database db) {
  final generatedAt = readRunMeta(db)?.generatedAt;
  final age = replayAgeInDays(generatedAt, DateTime.now().toUtc());
  if (generatedAt == null) {
    print('📅 replay 落檔時間：未知（舊 DB 無 generated_at）');
  } else {
    print('📅 replay 落檔於 ${generatedAt.toIso8601String()}（$age 天前）');
  }

  final coverage = compareRuleCoverage(
    coverageReferenceIds(),
    readReplayedRuleIds(db),
  );
  if (coverage.uncalibrated.isEmpty && coverage.orphaned.isEmpty) {
    print('🔎 規則涵蓋：${coverage.registrySize} 條全部都有 replay 樣本');
    return;
  }

  print('🔎 規則涵蓋：${coverage.registrySize} 條註冊規則');
  if (coverage.uncalibrated.isNotEmpty) {
    // 分兩群給不同建議:對「這條管線抓不到」的規則說「重跑完整管線」是
    // 無效建議,會讓人以為問題出在沒跑夠。
    final fixable = coverage.uncalibrated
        .where(
          (id) => !CalibrationThresholds.notBackfillableReasons.contains(id),
        )
        .toList();
    final unfixable = coverage.uncalibrated
        .where(
          (id) => CalibrationThresholds.notBackfillableReasons.contains(id),
        )
        .toList();

    if (fixable.isNotEmpty) {
      print('   ⚠️  ${fixable.length} 條無 replay 樣本,本次只會拿到手調分:');
      print('      ${_previewIds(fixable)}');
      print('      → 這些補得到,但基本面需約 7,100 次 FinMind 呼叫(額度 600/hr):');
      print(
        '        BACKFILL_SKIP_FUNDAMENTALS=0 ./scripts/calibrate-retry.sh',
      );
    }
    if (unfixable.isNotEmpty) {
      print(
        '   ℹ️  ${unfixable.length} 條這條管線抓不到資料'
        '(集保/內部人/警示股/新聞無 backfill phase),永遠是手調分:',
      );
      print('      ${_previewIds(unfixable)}');
      print('      → 重跑管線無效。要校準它們得先為這些來源加 backfill phase。');
    }
  }
  if (coverage.orphaned.isNotEmpty) {
    print(
      '   ℹ️  ${coverage.orphaned.length} 條樣本中的規則已不在註冊表'
      '（改名或刪除，candidate JSON 會留下查不到的死列）：',
    );
    print('      ${_previewIds(coverage.orphaned)}');
  }
}

/// 最多列 6 條，其餘以數量帶過——避免 31 條把畫面洗掉。
String _previewIds(List<String> ids) {
  const limit = 6;
  if (ids.length <= limit) return ids.join(', ');
  return '${ids.take(limit).join(', ')} …（另 ${ids.length - limit} 條）';
}

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  if (config == null) {
    _printUsage(stderr);
    exit(1);
  }

  final dbPath = config.dbPath ?? _autoDetectDb();
  if (dbPath == null) {
    stderr.writeln('❌ DB file 找不到。用 --db <path> 手動指定。');
    stderr.writeln('');
    stderr.writeln('💡 找 DB 指令：');
    stderr.writeln('   find ~/Library -name "afterclose*.sqlite" 2>/dev/null');
    exit(1);
  }
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 檔案不存在: $dbPath');
    exit(1);
  }

  // 驗證 repo root 的 assets/ 存在（避免寫錯位置）
  if (!config.dryRun && !Directory('assets').existsSync()) {
    stderr.writeln('❌ assets/ 目錄不存在 — 請從 repo root 執行。');
    exit(1);
  }

  print('📂 DB: $dbPath');
  if (config.dryRun) {
    print('🔍 DRY RUN — 只印不寫');
  }

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  _printReplayContext(db);
  final horizonResults = <String, HorizonOutput>{};
  try {
    for (final horizon in _horizonsToProcess(config.horizon)) {
      print('');
      print('═══ Horizon: $horizon ═══');
      final result = _processHorizon(
        db,
        horizon: horizon,
        dryRun: config.dryRun,
      );
      if (result != null) {
        horizonResults[horizon] = result;
      }
    }
  } finally {
    db.dispose(); // ignore: deprecated_member_use
  }

  // OTA manifest — 只有在「兩個 horizon 都成功寫出 candidate JSON」時才產生。
  // 若 --horizon=short 或 --horizon=long 只跑單一 horizon，manifest 缺角會
  // 讓 OTA client 看到 half-state，寧可不產。
  final shouldWriteManifest =
      !config.dryRun &&
      horizonResults.containsKey(_horizonShort) &&
      horizonResults.containsKey(_horizonLong);

  if (shouldWriteManifest) {
    print('');
    print('═══ OTA manifest ═══');
    final manifestPath = _writeManifest(
      short: horizonResults[_horizonShort]!,
      long: horizonResults[_horizonLong]!,
    );
    print('  ✅ Wrote $manifestPath');
  }

  print('');
  if (!config.dryRun) _printPromoteImpact();
  print('✅ 完成');
  if (!config.dryRun) {
    print('');
    print('👉 Review 流程：');
    print('   1. 看上方「Promote 影響」——candidate 在 .gitignore 內,git diff 永遠是空的');
    print('   2. 判斷分數變動是否合理');
    print('   3. Approve: mv *_candidate.json → production filename');
    print(
      '      另外別忘了 mv calibration_manifest_candidate.json → calibration_manifest.json',
    );
    print('   4. Commit + push（同 commit 內推 manifest + 兩支 JSON）');
  }
}

/// 單一 horizon 處理完後的輸出資訊，供 manifest 生成使用
class HorizonOutput {
  const HorizonOutput({
    required this.filename,
    required this.jsonStr,
    required this.sha256Hex,
    required this.ruleCount,
  });

  /// 相對 repo root 的 candidate 檔名
  final String filename;

  /// Raw JSON 字串（與檔案內容完全一致）
  final String jsonStr;

  /// SHA-256 of `utf8.encode(jsonStr)`，hex string
  final String sha256Hex;

  /// Calibrated rules 數量（cut + active 加總）
  final int ruleCount;
}

HorizonOutput? _processHorizon(
  Database db, {
  required String horizon,
  required bool dryRun,
}) {
  final period = horizon == _horizonShort ? _periodShort : _periodLong;
  final threshold = horizon == _horizonShort ? _thresholdShort : _thresholdLong;

  // Clustered 分流：replay 落檔的 run meta 決定決策層走哪條路（不再盲猜
  // rule_accuracy 是哪個模式產的）。excess → clustered t + baseline-relative
  // hit cut；meta 缺失或 absolute → 舊 proportion z-test 路徑。
  final runMeta = readRunMeta(db);
  final isExcess = runMeta?.isExcess ?? false;
  final baselineHit = horizon == _horizonShort
      ? runMeta?.baselineHit5
      : runMeta?.baselineHit60;

  // 舊路徑的 H0 baseline（2026-06-18 修正：查實證表、非 0.5）。
  final tradingDays = horizon == _horizonShort ? 5 : 60;
  final legacyBaseline =
      CalibrationThresholds.successProbabilityBaselines[tradingDays] ??
      CalibrationThresholds.defaultBaselineProbability;

  final rows = db.select(
    'SELECT rule_id, trigger_count, success_count, avg_return '
    'FROM rule_accuracy WHERE period = ?',
    [period],
  );

  if (rows.isEmpty) {
    print('  ⚠️  rule_accuracy 沒有 $period 的統計資料 — skip');
    print('     (可能原因：app 還沒跑過歷史資料驗證，或 daily_reason 沒資料)');
    return null;
  }

  final dailyMeansByRule = isExcess
      ? loadDailyMeans(db, period)
      : const <String, List<double>>{};

  final allStats = <RuleStats>[];
  for (final row in rows) {
    final triggerCount = row['trigger_count'] as int;
    final successCount = row['success_count'] as int;
    final avgReturn = (row['avg_return'] as num).toDouble();
    final hitRate = triggerCount > 0 ? successCount / triggerCount : 0.0;
    allStats.add(
      RuleStats(
        ruleId: row['rule_id'] as String,
        hitRate: hitRate,
        avgReturn: avgReturn,
        triggerCount: triggerCount,
        dailyMeans: dailyMeansByRule[row['rule_id'] as String] ?? const [],
      ),
    );
  }

  final Map<String, CalibratedRule> calibrated;
  if (isExcess && baselineHit != null) {
    print(
      '  🧮 clustered 決策層（excess）：baseline hit '
      '${baselineHit.toStringAsFixed(4)} + ${CalibrationThresholds.hitRateLiftThreshold} lift',
    );
    calibrated = Calibrator.calibrateAllClustered(
      allStats,
      baselineHit: baselineHit,
    );
  } else {
    if (isExcess) {
      print('  ⚠️  excess run 但 meta 缺 baseline — fallback 舊決策層');
    } else {
      print('  🧮 舊決策層（absolute / meta 缺失）：baseline $legacyBaseline');
    }
    calibrated = Calibrator.calibrateAll(allStats, baseline: legacyBaseline);
  }

  final activeCount = calibrated.values.where((r) => r.active).length;
  final cutCount = calibrated.values.where((r) => !r.active).length;
  print('  ${calibrated.length} 條規則：$activeCount active，$cutCount cut');

  final usedClustered = isExcess && baselineHit != null;
  final payload = <String, dynamic>{
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'horizon': horizon == _horizonShort ? '5d' : '60d',
    'backtest': {
      // window_days/train_ratio 已移除（2026-07-23 稽核：宣稱 2 年窗/0.7
      // split 與實際 pipeline 脫節——replay 吃全庫 ~9 年、split 在獨立的
      // walkforward_validate）
      // 誠實 metadata：超額模式記實際超額門檻（0.0），不再誤標絕對 8.0。
      'success_threshold_pct': usedClustered
          ? runMeta!.excessThreshold
          : threshold,
      'formula': _formulaVersion,
      'return_mode': usedClustered ? 'excess' : 'absolute',
      if (usedClustered) 'stats_method': 'date_clustered_t_v1',
      if (usedClustered)
        'baseline_hit_rate': double.parse(baselineHit.toStringAsFixed(4)),
    },
    'rules': {
      for (final entry in calibrated.entries) entry.key: entry.value.toJson(),
    },
  };

  final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
  final sha256Hex = computeJsonSha256(jsonStr);

  if (dryRun) {
    print('  --dry-run: candidate JSON 預覽：');
    print(jsonStr);
    print('  (dry-run SHA-256: $sha256Hex)');
    return null;
  }

  final filename = horizon == _horizonShort
      ? 'assets/rule_scores_calibrated_short_candidate.json'
      : 'assets/rule_scores_calibrated_long_candidate.json';

  // Atomic write: temp → rename
  final tempFile = File('$filename.tmp');
  tempFile.writeAsStringSync(jsonStr);
  tempFile.renameSync(filename);
  print('  ✅ Wrote $filename (${jsonStr.length} bytes)');
  print('     SHA-256: $sha256Hex');

  return HorizonOutput(
    filename: filename,
    jsonStr: jsonStr,
    sha256Hex: sha256Hex,
    ruleCount: calibrated.length,
  );
}

/// 計算 JSON 字串的 SHA-256（hex string）
///
/// 以 `utf8.encode` 轉 byte 後跑 SHA-256，輸出小寫 hex（64 字元）。
/// OTA client 會用同樣方式對下載到的 JSON byte 計算 hash 並比對 manifest。
String computeJsonSha256(String jsonStr) {
  final digest = sha256.convert(utf8.encode(jsonStr));
  return digest.toString();
}

// ============================================================================
// OTA manifest writer
// ============================================================================

/// jsDelivr 上的 manifest 基底 URL（repo + branch）
///
/// Client 端的 `CalibrationUpdater` 會 fetch `${_manifestBaseUrl}/calibration_manifest.json`。
/// 這個常數只影響寫進 manifest 的 JSON URL 欄位本身，不影響 manifest 檔案的位置。
const _manifestBaseUrl =
    'https://cdn.jsdelivr.net/gh/Neal75418/daredevil@main/assets';

/// Manifest schema version — 若未來 client 新增強制欄位會遞增
const _manifestSchemaVersion = 1;

/// 目前 app 的最低支援版本
///
/// 未來若某次 recalibrate 依賴新 rule 定義（例如 ReasonType 新增），
/// 手動改大此值讓舊版 app skip fetch。應 ≤ pubspec.yaml 的 `version`
/// 值（否則 OTA gate 會把當前 release 自己鎖在外面，blast radius 包含
/// production CDN）。0.5.x release line：`0.5.0`。
const _manifestMinimumAppVersion = '0.5.0';

/// 產出 `assets/calibration_manifest_candidate.json`
///
/// Shape（同步 design doc §3.3）：
///
/// ```json
/// {
///   "schema_version": 1,
///   "version": "YYYY-MM-DD",
///   "generated_at": "ISO8601 with tz",
///   "short": { "url": "...", "sha256": "...", "rule_count": N, "filename": "..." },
///   "long":  { "url": "...", "sha256": "...", "rule_count": N, "filename": "..." },
///   "minimum_app_version": "1.0.0"
/// }
/// ```
///
/// - `version` 用當天日期（UTC），純標籤，client 比對走 hash 不走 version
/// - `generated_at` 含時區的 ISO 8601，給 human debug 用
/// - `short.url` / `long.url` 是 jsDelivr 絕對 URL，client 不用組
/// - `short.sha256` / `long.sha256` 是 SHA-256 hex，client 驗證 integrity 用
/// - `short.filename` / `long.filename` 是 review rename 時要 mv 的目標檔名，
///   讓 reviewer 不用猜
///
/// 回傳 manifest 檔案路徑。
String _writeManifest({
  required HorizonOutput short,
  required HorizonOutput long,
}) {
  final now = DateTime.now().toUtc();
  final versionTag =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  // Production filenames 用於 review 後 mv 目標 + jsDelivr URL
  const shortProdFilename = 'rule_scores_calibrated_short.json';
  const longProdFilename = 'rule_scores_calibrated_long.json';

  final payload = <String, dynamic>{
    'schema_version': _manifestSchemaVersion,
    'version': versionTag,
    'generated_at': now.toIso8601String(),
    'short': {
      'url': '$_manifestBaseUrl/$shortProdFilename',
      'sha256': short.sha256Hex,
      'rule_count': short.ruleCount,
      'filename': shortProdFilename,
    },
    'long': {
      'url': '$_manifestBaseUrl/$longProdFilename',
      'sha256': long.sha256Hex,
      'rule_count': long.ruleCount,
      'filename': longProdFilename,
    },
    'minimum_app_version': _manifestMinimumAppVersion,
  };

  final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
  const manifestPath = 'assets/calibration_manifest_candidate.json';

  // Atomic write: temp → rename（跟 horizon JSON 一致）
  final tempFile = File('$manifestPath.tmp');
  tempFile.writeAsStringSync(jsonStr);
  tempFile.renameSync(manifestPath);

  return manifestPath;
}

class _Config {
  const _Config({
    required this.dbPath,
    required this.horizon,
    required this.dryRun,
  });

  final String? dbPath;
  final String horizon;
  final bool dryRun;
}

_Config? _parseArgs(List<String> args) {
  String? dbPath;
  var horizon = _horizonBoth;
  var dryRun = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--db':
        if (i + 1 >= args.length) return null;
        dbPath = args[++i];
      case '--horizon':
        if (i + 1 >= args.length) return null;
        horizon = args[++i];
        if (horizon != _horizonShort &&
            horizon != _horizonLong &&
            horizon != _horizonBoth) {
          stderr.writeln('❌ Invalid --horizon: $horizon (use short|long|both)');
          return null;
        }
      case '--dry-run':
        dryRun = true;
      case '--help' || '-h':
        return null;
      default:
        stderr.writeln('❌ Unknown arg: $arg');
        return null;
    }
  }

  return _Config(dbPath: dbPath, horizon: horizon, dryRun: dryRun);
}

void _printUsage(IOSink sink) {
  sink.writeln(
    'Usage: dart run tool/recalibrate.dart '
    '[--db <path>] [--horizon <short|long|both>] [--dry-run]',
  );
  sink.writeln('');
  sink.writeln('Generates candidate calibrated rule scores JSON files');
  sink.writeln('from the rule_accuracy DB table using linear_map_v1 formula.');
}

List<String> _horizonsToProcess(String horizon) {
  switch (horizon) {
    case _horizonShort:
      return [_horizonShort];
    case _horizonLong:
      return [_horizonLong];
    case _horizonBoth:
      return [_horizonShort, _horizonLong];
    default:
      throw StateError('unreachable');
  }
}

String? _autoDetectDb() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  // 已知 macOS Flutter container 位置（check_db_range.dart Stage 0 findings）
  final candidate = File(
    '$home/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite',
  );
  if (candidate.existsSync()) return candidate.path;
  return null;
}

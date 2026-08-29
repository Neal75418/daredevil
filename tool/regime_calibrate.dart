// tool/regime_calibrate.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 用 regime report 的「同行情內相對 skill」重算 rule 分數，並用 2022 空頭做
// 樣本外驗證。
//
// ## 為什麼這樣校準
// 現行 production 分數是用「絕對報酬」算 → 被多頭 beta 灌水（regime_report 證實）。
// 改用「相對 skill（跨多空贏過平均股多少）」當尺：真貨加重、空頭反指標（法人類）
// 被砍。
//
// ## 流程
//   1. 跑 RegimeReporter → 每條規則 × 各年的相對 skill
//   2. 衍生分數：**只用 2021/2023/2024/2025/2026（排除 2022）** → train 相對 > 0
//      才留、按相對 linear-map 到 [10,35]
//   3. 樣本外驗證：在「沒參與衍生的 2022 空頭」上，比 NEW vs OLD 校準的
//      score-weighted 相對。NEW 不輸 OLD = 新校準在沒看過的空頭也成立
//   4. 輸出 candidate JSON（人工 review + walk-forward 過了才 mv 成 production）
//
// ⚠️ 邊界同 regime_report（存活者偏誤、流動樣本、規則層級、過去非未來）。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:daredevil/data/database/app_database.dart';

import 'tool_db.dart';

import 'recalibrate.dart' show Calibrator;
import 'regime_report.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart' as cal;

import 'recalibrate.dart' show effectiveScores;

// ============================================================================
// Pure calibration logic (testable)
// ============================================================================

/// 一條規則在 [years] 的「樣本數加權平均相對 skill」(useShort=5D，否則 60D)。
double trainRelative(
  Map<int, RuleYearCells> byYear,
  List<int> years, {
  required bool useShort,
}) {
  var weighted = 0.0;
  var totalN = 0.0;
  for (final y in years) {
    final cells = byYear[y];
    if (cells == null) continue;
    final cell = useShort ? cells.short : cells.long;
    if (cell.n == 0) continue;
    weighted += cell.relative * cell.n;
    totalN += cell.n;
  }
  return totalN > 0 ? weighted / totalN : 0.0;
}

/// 一條規則在 [years] 的總樣本數。
int totalSamples(
  Map<int, RuleYearCells> byYear,
  List<int> years, {
  required bool useShort,
}) {
  var n = 0;
  for (final y in years) {
    final cells = byYear[y];
    if (cells == null) continue;
    n += (useShort ? cells.short : cells.long).n;
  }
  return n;
}

/// 衍生「穩健相對」校準分數（rule → score）。
///
/// 倖存者：train 樣本數 ≥ [minSamples] 且 train 相對 > 0（平均贏過平均股）。
/// 倖存者按相對 linear-map 到 [Calibrator.minScore, maxScore]；其餘 0。
Map<String, int> deriveScores(
  Map<String, Map<int, RuleYearCells>> data,
  List<int> trainYears, {
  required bool useShort,
  int minSamples = 100,
  int? requireCoverageYear,
}) {
  final rel = <String, double>{};
  final survivors = <String>[];
  for (final entry in data.entries) {
    final r = trainRelative(entry.value, trainYears, useShort: useShort);
    final n = totalSamples(entry.value, trainYears, useShort: useShort);
    rel[entry.key] = r;
    // requireCoverageYear：規則須在該年（空頭）有資料才有資格 — 用「覆蓋度」
    // 非「績效」當門檻（不算偷看 holdout），排除無法做 regime 驗證的規則
    // （如基本面類 2021-2023 資料跳過 → 無空頭資料）。
    final hasCoverage =
        requireCoverageYear == null ||
        totalSamples(entry.value, [requireCoverageYear], useShort: useShort) >
            0;
    if (n >= minSamples && r > 0 && hasCoverage) survivors.add(entry.key);
  }

  final scores = {for (final k in data.keys) k: 0};
  if (survivors.isEmpty) return scores;

  final relVals = survivors.map((r) => rel[r]!).toList();
  final minR = relVals.reduce(math.min);
  final maxR = relVals.reduce(math.max);
  for (final r in survivors) {
    scores[r] = Calibrator.linearMapScore(rel[r]!, minR, maxR);
  }
  return scores;
}

/// 驗證指標：以「分數 × 該年樣本數」為權重，加權 [year] 的相對 skill。
/// = 「照這份校準選股，在該年能拿到的相對超額」。score ≤ 0 不計。
double scoreWeightedRelative(
  Map<String, int> scores,
  Map<String, Map<int, RuleYearCells>> data,
  int year, {
  required bool useShort,
}) {
  var numerator = 0.0;
  var denominator = 0.0;
  for (final entry in data.entries) {
    final s = scores[entry.key] ?? 0;
    if (s <= 0) continue;
    final cells = entry.value[year];
    if (cells == null) continue;
    final cell = useShort ? cells.short : cells.long;
    if (cell.n == 0) continue;
    numerator += s * cell.n * cell.relative;
    denominator += s * cell.n;
  }
  return denominator > 0 ? numerator / denominator : 0.0;
}

// ============================================================================
// CLI
// ============================================================================

Future<void> main(List<String> args) async {
  final code = await runRegimeCalibrateCli(args);
  exit(code);
}

Future<int> runRegimeCalibrateCli(List<String> args) async {
  final dbPath =
      Platform.environment['CALIBRATION_DB'] ?? 'tool/calibration.db';
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 不存在: $dbPath');
    return 2;
  }
  const bearYear = 2022;
  final allYears = [2021, 2022, 2023, 2024, 2025, 2026];
  final trainYears = allYears.where((y) => y != bearYear).toList();
  final sampleSize =
      int.tryParse(Platform.environment['REGIME_SAMPLE_SIZE'] ?? '400') ?? 400;

  final AppDatabase db;
  try {
    db = openToolDatabase(dbPath);
  } on SchemaFingerprintMismatch catch (e) {
    stderr.writeln(e.message);
    return 6;
  }
  try {
    List<String>? sample;
    final rows = await db
        .customSelect(
          'SELECT symbol FROM daily_price '
          "WHERE date >= '2021-01-01' "
          'GROUP BY symbol HAVING COUNT(*) > 400 '
          'ORDER BY AVG(volume) DESC LIMIT $sampleSize',
        )
        .get();
    sample = rows.map((r) => r.read<String>('symbol')).toList();
    print('🎯 流動性樣本: ${sample.length} 檔');

    print('▶️  跑 regime report（6 年 × abs/excess）...');
    final data = await RegimeReporter(
      db: db,
      years: allYears,
      symbolsWhitelist: sample,
      minUniverseSymbols: 50,
      logger: (m) => print('   $m'),
    ).run();

    // 衍生 NEW（排除 2022 績效；但要求 2022 有「資料覆蓋」才有資格，砍掉
    // 無法做空頭驗證的規則如基本面類）
    final newShort = deriveScores(
      data,
      trainYears,
      useShort: true,
      requireCoverageYear: bearYear,
    );
    final newLong = deriveScores(
      data,
      trainYears,
      useShort: false,
      requireCoverageYear: bearYear,
    );
    // OLD（現行 production）
    final oldShort = _loadOld(
      'assets/rule_scores_calibrated_short.json',
      cal.Horizon.short,
    );
    final oldLong = _loadOld(
      'assets/rule_scores_calibrated_long.json',
      cal.Horizon.long,
    );

    print('');
    print('═' * 64);
    print('樣本外驗證（2022 空頭 — 沒參與 NEW 衍生）：score-weighted 相對');
    print('═' * 64);
    for (final h in [(true, '短 5D'), (false, '長 60D')]) {
      final us = h.$1;
      final newSwe = scoreWeightedRelative(
        us ? newShort : newLong,
        data,
        bearYear,
        useShort: us,
      );
      final oldSwe = scoreWeightedRelative(
        us ? oldShort : oldLong,
        data,
        bearYear,
        useShort: us,
      );
      final newActive = (us ? newShort : newLong).values
          .where((s) => s > 0)
          .length;
      final oldActive = (us ? oldShort : oldLong).values
          .where((s) => s > 0)
          .length;
      final verdict = newSwe >= oldSwe ? '✅ NEW 不輸' : '⚠️ NEW 較差';
      print(
        '  ${h.$2}: NEW ${newSwe.toStringAsFixed(2)} ($newActive 條) '
        'vs OLD ${oldSwe.toStringAsFixed(2)} ($oldActive 條)  $verdict',
      );
    }

    print('');
    print('NEW 校準的「真貨」(分數高、空頭也撐)：');
    _printTop(newLong, data, bearYear);

    _writeCandidate(newShort, 'short');
    _writeCandidate(newLong, 'long');
    print('');
    print(
      '✅ 候選 JSON 已寫 ${regimeCandidatePath('short')} / '
      '${regimeCandidatePath('long')}',
    );
    print('   ⚠️ 這**不是** recalibrate 的產物:本檔每條規則只有 score +');
    print('   active,沒有 avg_return / t_stat,promote 進 production 檔名會');
    print('   讓負證據歸零失效(生產檔現有 28/44 條靠它壓著)且無任何警告。');
    print('   （人工 review + 上面驗證認可後才決定怎麼用）');
    // 稽核 #12:零樣本 / 零規則不是「跑完了沒事」——原本一律 exit 0,
    // harness 的 expect(code, 0) 照過,而報告是空的。呼叫端必須分得出
    // 「這輪什麼都沒量到」與「量到了、結論是沒差異」。
    // 這支還會**寫檔**:degenerate 輸入下 deriveScores 的 survivors 為空
    // → 全 52 條 score 0 的 all-cut candidate 落到 assets/,然後印 ✅。
    if (newShort.values.every((v) => v == 0) &&
        newLong.values.every((v) => v == 0)) {
      stderr.writeln(
        '❌ 兩個 horizon 的衍生分數全為 0(樣本不足或資料退化)——'
        '已寫出的 candidate 是全 cut,不得用於任何決策',
      );
      return 5;
    }
    return 0;
  } finally {
    await db.close();
  }
}

/// 讀現行 production 校準,回傳 **App 實際使用的有效分數**。
///
/// 🚨 **不可用 `parseCalibratedScores`**(2026-08-23):那個只取 raw
/// `score`,被 cut 或不在 JSON 裡的規則一律當 0。但 App 走
/// `CalibratedScoresTable.lookup` 的三態——cut／缺席 fallback 到 hardcoded,
/// 只有負證據規則才真的歸零。本工具拿 OLD 與 NEW 做樣本外比較後會寫出
/// candidate JSON,OLD arm 被低估等於系統性高估 NEW:2026-08-22 在
/// walkforward 實測,同一個錯誤讓長線平均勝幅虛報成 +5.60(實際 −0.048),
/// 三條變動中兩條方向相反。
Map<String, int> _loadOld(String path, cal.Horizon horizon) {
  final f = File(path);
  // 缺檔不得當成「OLD 全 0」(2026-08-29 tool 稽核 #11):空 map 會讓
  // scoreWeightedRelative 的分母為 0 → 回 0.0 → 判準 `newSwe >= oldSwe`
  // 對任何非負的 NEW 都印「✅ NEW 不輸」。這正是上方註解花九行警告的
  // 那個錯誤(2026-08-22 實測虛報 +5.60、實際 −0.048),只是換一條路
  // 進來。walkforward_validate 對同一個前置條件是硬錯誤(return 3),
  // 兩支工具不該對此有兩種立場。
  if (!f.existsSync()) {
    throw StateError(
      '找不到現行 production 校準:$path——沒有 OLD 基準就沒有比較,'
      '不得以「NEW 不輸」收場。請先確認 assets 下有已 promote 的校準檔',
    );
  }
  return effectiveScores(
    f.readAsStringSync(),
    horizon: horizon,
    // 與 calibrated_scores_registry.dart 的 `horizon == Horizon.short` 一致
    applyZeroing: horizon == cal.Horizon.short,
  );
}

void _printTop(
  Map<String, int> scores,
  Map<String, Map<int, RuleYearCells>> data,
  int bearYear,
) {
  final active = scores.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in active.take(8)) {
    final bear = data[e.key]?[bearYear]?.long;
    print(
      '   ${e.key.padRight(30)} score=${e.value.toString().padLeft(2)}  '
      '2022相對=${bear == null ? "n/a" : bear.relative.toStringAsFixed(1)}',
    );
  }
}

/// 本工具的候選檔名——**刻意與 recalibrate 的產物分開**
/// (2026-08-29 tool 稽核 #6)。
///
/// 兩支曾經寫同一個 `rule_scores_calibrated_{horizon}_candidate.json`,
/// 但 schema 不同:本工具每條規則只有 `score` + `active`,沒有
/// `avg_return` / `t_stat` / `backtest`。CalibratedScoresTable.parseJson
/// **不會抱怨**(drift guard 只在 backtest 存在時才比對),於是檔案乾淨
/// 載入——但負證據歸零需要 avg_return 與 t_stat 才成立(實測生產檔
/// 28/44 條規則靠它壓著),promote 進去等於把那 28 條無聲彈回手調正分,
/// 正是三態 lookup 當初要修的那個 bug,而且全鏈路零診斷輸出。
String regimeCandidatePath(String horizon) =>
    'assets/rule_scores_calibrated_${horizon}_regime_candidate.json';

void _writeCandidate(Map<String, int> scores, String horizon) {
  final rules = <String, dynamic>{
    for (final e in scores.entries)
      e.key: {'score': e.value, 'active': e.value > 0},
  };
  final payload = {
    'schema_version': 1,
    'horizon': horizon == 'short' ? '5d' : '60d',
    'method': 'regime_robust_relative_v1',
    'rules': rules,
  };
  const encoder = JsonEncoder.withIndent('  ');
  // 原子寫入(同 recalibrate:1051):中途被 kill 會留下截斷的 JSON,
  // 而 parseJson 對壞檔是整份拒收 → 全部規則 fallback 到 hardcoded,
  // 同樣無聲。
  final target = regimeCandidatePath(horizon);
  final tmp = File('$target.tmp')..writeAsStringSync(encoder.convert(payload));
  tmp.renameSync(target);
}

// tool/score_validate.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 驗證「手調 composite 評分」的實際選股力 —— 回答使用者真正在意的問題：
// 「我的系統打的分數越高，股票真的越會漲嗎?在空頭也成立嗎?」
//
// ## 這支跟 regime_report / regime_calibrate 不同在哪
// 那兩支是「規則層」(每條 rule 各自的表現)。這支是「分數層」(整套手調分數
// 加總後選出來的股) —— 也就是 app 實際輸出的東西。這才直接答「我的選股準不準」。
//
// ## 做法
// 透過 ReplayCalibrator 的 scoreSink hook，對歷史每個「有訊號」的股票日，
// 拿到 (手調 composite 分, 5D/60D forward return)。把分數切桶 [0-20/20-40/
// 40-60/60-80]，看每桶的勝率 + 平均報酬。
//   - 絕對報酬(主)：你要的「會不會漲」。高分桶報酬 > 低分桶 = 分數有鑑別力
//   - 同行情內相對 excess(輔)：高分股有沒有贏過當期平均(skill 還是 beta)
//   - 分年(2022 空頭)：鑑別力在空頭撐不撐得住
//
// ## 誠實邊界
//   - 只看「有訊號」的股票日(= app 的 pick 母體)，不含完全無訊號的日子
//   - 固定持有 5D/60D、無停損；存活者偏誤(FinMind 無下市股) → 偏樂觀
//   - 流動樣本(top volume)；過去多空的證據，非未來保證
//   - 用 reason.score 基礎分近似 app 行為(僅 3 筆 calibrated override/2 條 rule)

import 'dart:io';

import 'package:daredevil/core/constants/exit_params.dart';
import 'package:daredevil/data/database/app_database.dart';

import 'tool_db.dart';

import 'replay_calibrator.dart';

// ============================================================================
// Pure bucketing logic (testable)
// ============================================================================

const List<String> kBucketLabels = ['0-20', '20-40', '40-60', '60-80'];

/// 分數 → 桶 index（0..3）。score clamp 過 [0,80]，邊界歸右桶。
int bucketIndex(double score) {
  final i = (score / 20).floor();
  return i < 0 ? 0 : (i > 3 ? 3 : i);
}

/// 單一桶的累加器
class BucketSummary {
  int count = 0;
  int wins = 0;
  double sumReturn = 0;

  void add(double ret) {
    count++;
    if (ret > 0) wins++;
    sumReturn += ret;
  }

  double get winRate => count == 0 ? 0 : wins / count;
  double get avgReturn => count == 0 ? 0 : sumReturn / count;
}

/// 把 (score, return) 樣本切成 4 桶。
List<BucketSummary> summarize(Iterable<({double score, double ret})> samples) {
  final buckets = List.generate(4, (_) => BucketSummary());
  for (final s in samples) {
    buckets[bucketIndex(s.score)].add(s.ret);
  }
  return buckets;
}

/// 桶報酬是否「單調遞增」(分數越高報酬越高)。只比有樣本的桶。
/// 回傳 (monotonic, 最高桶avg − 最低桶avg)。
({bool monotonic, double spread}) monotonicity(List<BucketSummary> buckets) {
  final nonEmpty = buckets.where((b) => b.count > 0).toList();
  if (nonEmpty.length < 2) return (monotonic: false, spread: 0);
  var mono = true;
  for (var i = 1; i < nonEmpty.length; i++) {
    if (nonEmpty[i].avgReturn < nonEmpty[i - 1].avgReturn) mono = false;
  }
  return (
    monotonic: mono,
    spread: nonEmpty.last.avgReturn - nonEmpty.first.avgReturn,
  );
}

/// 依「上界陣列」把樣本分組（band i = 第一個滿足 value < upperBounds[i]；
/// 超過所有上界 → 最後一組）。供「天花板內部用未封頂原始分」分析。
/// 例：upperBounds [100,120,150] → 4 組：<100 / 100-120 / 120-150 / ≥150。
List<BucketSummary> summarizeByBands(
  Iterable<({double value, double ret})> samples,
  List<double> upperBounds,
) {
  final buckets = List.generate(upperBounds.length + 1, (_) => BucketSummary());
  for (final s in samples) {
    var idx = upperBounds.length;
    for (var i = 0; i < upperBounds.length; i++) {
      if (s.value < upperBounds[i]) {
        idx = i;
        break;
      }
    }
    buckets[idx].add(s.ret);
  }
  return buckets;
}

/// 把一組報酬聚成 [BucketSummary]（n / 勝率 / 平均報酬）。
BucketSummary statsOf(Iterable<double> rets) {
  final b = BucketSummary();
  for (final r in rets) {
    b.add(r);
  }
  return b;
}

// ============================================================================
// Sample collection
// ============================================================================

typedef ScoreRow = ({
  double score,
  double raw,
  double vol,
  double trend,
  double modeMom,
  double modeStr,
  double modePul,
  double sret,
  double lret,
  int year,
});

/// 跑一次 replay，把每個有訊號股票日的 (clamped 分, 未封頂原始分, 5D/60D報酬,
/// 年) 收集起來。
Future<List<ScoreRow>> _collect(
  AppDatabase db, {
  required bool excess,
  List<String>? sample,
  required void Function(String) log,
}) async {
  final rows = <ScoreRow>[];
  await ReplayCalibrator(
    db: db,
    config: ReplayConfig(
      dbPath: ':memory:',
      excessReturn: excess,
      minUniverseSymbols: 50,
      symbolsWhitelist: sample,
    ),
    scoreSink: (s) => rows.add((
      score: s.score,
      raw: s.rawScore,
      vol: s.volatility,
      trend: s.trendPct,
      modeMom: s.modeMomentum,
      modeStr: s.modeStrength,
      modePul: s.modePullback,
      sret: s.shortReturn,
      lret: s.longReturn,
      year: s.date.year,
    )),
    logger: log,
  ).run();
  return rows;
}

// ============================================================================
// Formatting
// ============================================================================

void _printTable(String title, List<BucketSummary> buckets) {
  final mono = monotonicity(buckets);
  print('  $title');
  print('    分數桶      n      勝率     平均報酬');
  for (var i = 0; i < buckets.length; i++) {
    final b = buckets[i];
    if (b.count == 0) {
      print('    ${kBucketLabels[i].padRight(8)} ${"0".padLeft(7)}     —');
      continue;
    }
    print(
      '    ${kBucketLabels[i].padRight(8)} '
      '${b.count.toString().padLeft(7)}  '
      '${(b.winRate * 100).toStringAsFixed(0).padLeft(3)}%  '
      '${(b.avgReturn >= 0 ? "+" : "")}${b.avgReturn.toStringAsFixed(1).padLeft(6)}%',
    );
  }
  final verdict = mono.monotonic
      ? '✅ 單調遞增（分數越高越會漲）'
      : (mono.spread > 0 ? '⚠️ 大致正相關但非嚴格單調' : '❌ 沒有鑑別力');
  print(
    '    → 最高桶−最低桶 spread=${mono.spread >= 0 ? "+" : ""}'
    '${mono.spread.toStringAsFixed(1)}%  $verdict',
  );
}

// ============================================================================
// CLI
// ============================================================================

Future<void> main(List<String> args) async {
  exit(await runScoreValidateCli(args));
}

Future<int> runScoreValidateCli(List<String> args) async {
  final dbPath =
      Platform.environment['CALIBRATION_DB'] ?? 'tool/calibration.db';
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 不存在: $dbPath');
    return 2;
  }
  final sampleSize =
      int.tryParse(Platform.environment['SCORE_SAMPLE_SIZE'] ?? '400') ?? 400;
  final years = [2021, 2022, 2023, 2024, 2025, 2026];

  final AppDatabase db;
  try {
    db = openToolDatabase(dbPath);
  } on SchemaFingerprintMismatch catch (e) {
    stderr.writeln(e.message);
    return 6;
  }
  try {
    final r = await db
        .customSelect(
          'SELECT symbol FROM daily_price '
          "WHERE date >= '2021-01-01' "
          'GROUP BY symbol HAVING COUNT(*) > 400 '
          'ORDER BY AVG(volume) DESC LIMIT $sampleSize',
        )
        .get();
    final sample = r.map((row) => row.read<String>('symbol')).toList();
    print('🎯 流動樣本: ${sample.length} 檔');

    print('▶️  收集絕對報酬樣本...');
    final abs = await _collect(db, excess: false, sample: sample, log: (_) {});
    print('▶️  收集超額報酬樣本...');
    final exc = await _collect(db, excess: true, sample: sample, log: (_) {});
    print('✅ 樣本: 絕對 ${abs.length}, 超額 ${exc.length}');

    print('');
    print('═' * 60);
    print('絕對報酬（你要的「會不會漲」）');
    print('═' * 60);
    _printTable(
      '60D 全期',
      summarize(abs.map((s) => (score: s.score, ret: s.lret))),
    );
    print('');
    _printTable(
      '5D 全期',
      summarize(abs.map((s) => (score: s.score, ret: s.sret))),
    );

    print('');
    print('分年（60D 絕對，看 2022 空頭撐不撐）：');
    for (final y in years) {
      final yr = abs.where((s) => s.year == y);
      if (yr.isEmpty) continue;
      _printTable(
        '$y',
        summarize(yr.map((s) => (score: s.score, ret: s.lret))),
      );
    }

    print('');
    print('═' * 60);
    print('同行情內相對 / excess（高分股是 skill 還是 beta）');
    print('═' * 60);
    _printTable(
      '60D 全期',
      summarize(exc.map((s) => (score: s.score, ret: s.lret))),
    );

    // 🔑 A 驗證：天花板(clamped=80)內部，改用「未封頂原始分」排序有沒有用?
    print('');
    print('═' * 60);
    print('🔑 A 驗證：天花板內部(clamped=80)用「未封頂原始分」還分得出報酬嗎?');
    print('═' * 60);
    final ceiling = abs.where((s) => s.score >= 80).toList();
    print('  撞到 80 上限的樣本: ${ceiling.length}（現況排序只能用股號裂解）');
    const bands = [100.0, 120.0, 150.0];
    const bandLabels = ['80-100', '100-120', '120-150', '150+'];
    final cb = summarizeByBands(
      ceiling.map((s) => (value: s.raw, ret: s.lret)),
      bands,
    );
    print('    原始分      n      勝率     平均60D報酬');
    for (var i = 0; i < cb.length; i++) {
      final b = cb[i];
      if (b.count == 0) {
        print('    ${bandLabels[i].padRight(8)}  (無)');
        continue;
      }
      print(
        '    ${bandLabels[i].padRight(8)} '
        '${b.count.toString().padLeft(6)}  '
        '${(b.winRate * 100).toStringAsFixed(0).padLeft(3)}%  '
        '${b.avgReturn >= 0 ? "+" : ""}${b.avgReturn.toStringAsFixed(1)}%',
      );
    }
    final cm = monotonicity(cb);
    final cVerdict = cm.monotonic
        ? '✅ 原始分在天花板內仍有鑑別力 → 改用原始分當排序鍵【有效】'
        : (cm.spread > 0
              ? '🟡 大致正相關但非嚴格單調 → 原始分排序略優於股號'
              : '❌ 天花板內原始分無鑑別力 → 改排序鍵幫助有限，需另尋 tiebreaker');
    print(
      '    → spread=${cm.spread >= 0 ? "+" : ""}'
      '${cm.spread.toStringAsFixed(1)}%  $cVerdict',
    );

    // 🔑 C 驗證：高分股裡，按波動度分組 — 低波動的勝率/報酬會比較好嗎?
    print('');
    print('═' * 60);
    print('🔑 C 驗證：高分股(score≥40)按波動度分組 — 低波動勝率更高嗎?');
    print('═' * 60);
    final picks = abs.where((s) => s.score >= 40 && s.vol > 0).toList();
    print('  高分樣本(score≥40、有波動度): ${picks.length}');
    const volBands = [2.0, 3.0, 4.0];
    const volLabels = ['<2% 低波', '2-3%', '3-4%', '>4% 高波'];
    final vb = summarizeByBands(
      picks.map((s) => (value: s.vol, ret: s.lret)),
      volBands,
    );
    print('    日波動度    n      勝率     平均60D報酬');
    for (var i = 0; i < vb.length; i++) {
      final b = vb[i];
      if (b.count == 0) {
        print('    ${volLabels[i].padRight(9)} (無)');
        continue;
      }
      print(
        '    ${volLabels[i].padRight(9)} '
        '${b.count.toString().padLeft(6)}  '
        '${(b.winRate * 100).toStringAsFixed(0).padLeft(3)}%  '
        '${b.avgReturn >= 0 ? "+" : ""}${b.avgReturn.toStringAsFixed(1)}%',
      );
    }
    final lowVol = vb.first;
    final highVol = vb.last;
    if (lowVol.count > 0 && highVol.count > 0) {
      final winGain = (lowVol.winRate - highVol.winRate) * 100;
      final retCost = lowVol.avgReturn - highVol.avgReturn;
      print(
        '    → 低波 vs 高波：勝率 ${winGain >= 0 ? "+" : ""}'
        '${winGain.toStringAsFixed(0)}pp、報酬 ${retCost >= 0 ? "+" : ""}'
        '${retCost.toStringAsFixed(1)}%',
      );
      final verdict = winGain > 3
          ? '✅ 低波勝率明顯較高 → 風險調整能升勝率（報酬差=tradeoff 代價）'
          : '🟡 低波勝率優勢有限 → 風險調整效益不明顯';
      print('    $verdict');
    }

    // 🔑 B-trend 驗證：高分股裡，下跌趨勢(close<MA60)的勝率/報酬是不是更差?
    print('');
    print('═' * 60);
    print('🔑 B-趨勢驗證：高分股(score≥40)按「相對60日均線」分組 — 下跌股更差嗎?');
    print('═' * 60);
    final tpicks = abs.where((s) => s.score >= 40 && s.trend != 0).toList();
    print('  高分樣本(score≥40、有趨勢): ${tpicks.length}');
    const trendBands = [-5.0, 0.0, 10.0];
    const trendLabels = ['<-5% 深跌', '-5~0% 偏跌', '0~10% 偏漲', '>10% 強漲'];
    final tb = summarizeByBands(
      tpicks.map((s) => (value: s.trend, ret: s.lret)),
      trendBands,
    );
    print('    相對MA60    n      勝率     平均60D報酬');
    for (var i = 0; i < tb.length; i++) {
      final b = tb[i];
      if (b.count == 0) {
        print('    ${trendLabels[i].padRight(9)} (無)');
        continue;
      }
      print(
        '    ${trendLabels[i].padRight(9)} '
        '${b.count.toString().padLeft(6)}  '
        '${(b.winRate * 100).toStringAsFixed(0).padLeft(3)}%  '
        '${b.avgReturn >= 0 ? "+" : ""}${b.avgReturn.toStringAsFixed(1)}%',
      );
    }
    // 2 分法：下跌(<0) vs 多頭(≥0)
    final twoWay = summarizeByBands(
      tpicks.map((s) => (value: s.trend, ret: s.lret)),
      [0.0],
    );
    final down = twoWay[0];
    final up = twoWay[1];
    if (down.count > 0 && up.count > 0) {
      final winGap = (down.winRate - up.winRate) * 100;
      final retGap = down.avgReturn - up.avgReturn;
      print(
        '    → 下跌 vs 多頭：勝率 ${winGap >= 0 ? "+" : ""}'
        '${winGap.toStringAsFixed(0)}pp、報酬 ${retGap >= 0 ? "+" : ""}'
        '${retGap.toStringAsFixed(1)}%',
      );
      final verdict = retGap < -2
          ? '✅ 下跌趨勢高分股明顯更差 → 排除/降權下跌股【有效】'
          : (retGap < -0.5
                ? '🟡 下跌股略差 → 降權效益有限'
                : '❌ 下跌股沒更差（甚至更好=反轉股）→ 排除下跌股會誤殺');
      print('    $verdict');
    }

    // 🔑 分模式驗證：各模式「訊號 vs 同池基準」（公平比較）
    // Mode A「起漲」本就在下跌池撈，比它跟 Mode B 不公平；要問的是「同池裡，
    // 有訊號的有沒有贏過沒訊號的」= 該模式訊號到底有沒有 skill。
    print('');
    print('═' * 60);
    print('🔑 分模式驗證：訊號 vs「同池基準」(lift>0 = 該模式真能挑出贏家)');
    print('═' * 60);
    void modeCheck(
      String name,
      String poolDesc,
      List<ScoreRow> pool,
      bool Function(ScoreRow) hasSignal,
    ) {
      final sig = statsOf(pool.where(hasSignal).map((s) => s.lret));
      final base = statsOf(pool.where((s) => !hasSignal(s)).map((s) => s.lret));
      if (sig.count == 0 || base.count == 0) {
        print('  ▶ $name：樣本不足');
        return;
      }
      final lift = sig.avgReturn - base.avgReturn;
      final winLift = (sig.winRate - base.winRate) * 100;
      print('  ▶ $name（池=$poolDesc）');
      print(
        '     訊號組  n=${sig.count.toString().padLeft(5)}  '
        '勝率 ${(sig.winRate * 100).toStringAsFixed(0)}%  '
        '報酬 ${sig.avgReturn >= 0 ? "+" : ""}${sig.avgReturn.toStringAsFixed(1)}%',
      );
      print(
        '     基準組  n=${base.count.toString().padLeft(5)}  '
        '勝率 ${(base.winRate * 100).toStringAsFixed(0)}%  '
        '報酬 ${base.avgReturn >= 0 ? "+" : ""}${base.avgReturn.toStringAsFixed(1)}%',
      );
      final verdict = lift > 1
          ? '✅ 訊號有 skill（贏同池）'
          : (lift > -1 ? '🟡 訊號中性（跟同池差不多）' : '❌ 訊號反而更差（接刀）');
      print(
        '     → lift 報酬 ${lift >= 0 ? "+" : ""}${lift.toStringAsFixed(1)}%、'
        '勝率 ${winLift >= 0 ? "+" : ""}${winLift.toStringAsFixed(0)}pp  $verdict',
      );
    }

    modeCheck(
      'Mode A 起漲',
      '下跌 trend<0',
      abs.where((s) => s.trend < 0).toList(),
      (s) => s.modeMom >= ExitParams.modeSignalScoreThreshold,
    );
    modeCheck(
      'Mode B 強勢',
      '多頭 trend>0',
      abs.where((s) => s.trend > 0).toList(),
      (s) => s.modeStr >= ExitParams.modeSignalScoreThreshold,
    );
    modeCheck(
      'Mode C 回檔',
      '多頭 trend>0',
      abs.where((s) => s.trend > 0).toList(),
      (s) => s.modePul >= ExitParams.modeSignalScoreThreshold,
    );
    // 稽核 #12:零樣本 / 零規則不是「跑完了沒事」——原本一律 exit 0,
    // harness 的 expect(code, 0) 照過,而報告是空的。呼叫端必須分得出
    // 「這輪什麼都沒量到」與「量到了、結論是沒差異」。
    if (abs.isEmpty) {
      stderr.writeln('❌ 零樣本——本輪未量到任何 stock-day,結論不可用');
      return 5;
    }
    return 0;
  } finally {
    await db.close();
  }
}

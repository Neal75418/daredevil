// tool/regime_report.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 分析師版「訊號體檢報告」：每條規則 × 各年(行情) 的真實表現。
//
// 回答使用者真正要的：「我那些訊號的高勝率，是真的、還是只是多頭把一切墊高？
// 換到 2022 空頭還成立嗎？」
//
// ## 兩把尺（各答不同問題）
//   1. 絕對（你的實戰問題）：跟著訊號買，這行情會賺/賠多少？
//      - 期望值 = 平均報酬（= 勝率×平均賺 − 敗率×平均賠 的淨值）
//      - 勝率（報酬 > 0）、平均賺、平均賠（看「假高勝率但賠很大」）
//   2. 同行情內相對（本事 vs beta）：同一行情下，這訊號選的股有沒有比「平均股」好？
//      - = 橫斷面超額平均（excess）；2022 空頭那欄 ≥ 0 = 空頭也有選股本事
//
// ## 做法
//   對每個年份 Y：跑 ReplayCalibrator 兩次（absolute + excess，dateFilter=Y），
//   收集每條規則的 short(5D)/long(60D) 統計 → 算出上述指標。不改既有 pipeline。
//
// ## 誠實邊界（報告會標）
//   - 規則層級，非投資組合層級
//   - 固定持有期 5D/60D，非含停損的完整策略
//   - 存活者偏誤（FinMind 無下市股）→ 偏樂觀
//   - 法人/基本面類規則 2021-2023 資料不全 → 標「資料不足、僅參考」
//   - 過去多空的證據，非未來保證

import 'dart:io';

import 'package:daredevil/data/database/app_database.dart';

import 'tool_db.dart';

import 'replay_calibrator.dart';

// ============================================================================
// Public data models (testable)
// ============================================================================

/// 單一 (rule, year, horizon) 的分析師指標
class RegimeCell {
  const RegimeCell({
    required this.n,
    required this.expectancy,
    required this.winRate,
    required this.avgWin,
    required this.avgLoss,
    required this.relative,
  });

  /// 觸發次數（絕對 run）
  final int n;

  /// 期望值 = 平均絕對報酬（%）
  final double expectancy;

  /// 勝率（報酬 > 0 的比例）
  final double winRate;

  /// 賺的那些的平均報酬（%）
  final double avgWin;

  /// 賠的那些的平均報酬（%，負值）
  final double avgLoss;

  /// 同行情內相對 = 橫斷面超額平均（%）。> 0 表示贏過當期平均股。
  final double relative;
}

/// 從 absolute + excess 的 [RuleHorizonStats] 算出 [RegimeCell]（pure，可測）。
RegimeCell computeCell(RuleHorizonStats abs, RuleHorizonStats excess) {
  final rs = abs.returns;
  final wins = rs.where((r) => r > 0).toList();
  final losses = rs.where((r) => r < 0).toList();
  double mean(List<double> xs) =>
      xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;
  return RegimeCell(
    n: abs.triggerCount,
    expectancy: abs.avgReturn,
    winRate: rs.isEmpty ? 0.0 : wins.length / rs.length,
    avgWin: mean(wins),
    avgLoss: mean(losses),
    relative: excess.avgReturn,
  );
}

typedef RuleYearCells = ({RegimeCell short, RegimeCell long});

// ============================================================================
// Core reporter
// ============================================================================

class RegimeReporter {
  RegimeReporter({
    required this.db,
    required this.years,
    this.symbolsWhitelist,
    this.minUniverseSymbols = 100,
    void Function(String)? logger,
  }) : _log = logger ?? print;

  final AppDatabase db;
  final List<int> years;
  final List<String>? symbolsWhitelist;
  final int minUniverseSymbols;
  final void Function(String) _log;

  /// 回傳 {ruleId: {year: (short, long)}}
  Future<Map<String, Map<int, RuleYearCells>>> run() async {
    final result = <String, Map<int, RuleYearCells>>{};

    for (final year in years) {
      _log('▶️  $year：absolute + excess replay...');
      final yStart = DateTime(year);
      final yEnd = DateTime(year, 12, 31);

      // 絕對 run（你的實戰尺）：無 universe guard，全部 year-Y firing
      final abs = await ReplayCalibrator(
        db: db,
        config: ReplayConfig(
          dbPath: ':memory:',
          excessReturn: false,
          symbolsWhitelist: symbolsWhitelist,
          dateFilter: (start: yStart, end: yEnd),
        ),
        logger: (_) {},
      ).run();

      // 超額 run（本事尺）：同行情內相對
      final exc = await ReplayCalibrator(
        db: db,
        config: ReplayConfig(
          dbPath: ':memory:',
          minUniverseSymbols: minUniverseSymbols,
          symbolsWhitelist: symbolsWhitelist,
          dateFilter: (start: yStart, end: yEnd),
        ),
        logger: (_) {},
      ).run();

      final empty = RuleHorizonStats();
      final allRules = <String>{...abs.ruleStats.keys, ...exc.ruleStats.keys};
      for (final rule in allRules) {
        final a = abs.ruleStats[rule];
        final e = exc.ruleStats[rule];
        final cells = (
          short: computeCell(a?.short ?? empty, e?.short ?? empty),
          long: computeCell(a?.long ?? empty, e?.long ?? empty),
        );
        (result[rule] ??= {})[year] = cells;
      }
    }
    return result;
  }
}

// ============================================================================
// Report formatting
// ============================================================================

/// 把結果排版成可讀報告（long 60D horizon 為主 — 訊號多為部位型）。
/// 依「2022 空頭的同行情內相對」排序：真有本事的（空頭仍 ≥ 0）浮到上面。
String formatReport(
  Map<String, Map<int, RuleYearCells>> data,
  List<int> years, {
  int bearYear = 2022,
  int minSamples = 30,
}) {
  final buf = StringBuffer();
  buf.writeln('規則 × 各年體檢（60D 持有；E=期望值%, 勝=勝率, 相對=同行情內超額%）');
  buf.writeln('排序：依 $bearYear 空頭的「同行情內相對」（真有本事的在上）');
  buf.writeln('=' * 100);

  double bearRel(MapEntry<String, Map<int, RuleYearCells>> e) =>
      e.value[bearYear]?.long.relative ?? -999;
  final sorted = data.entries.toList()
    ..sort((a, b) => bearRel(b).compareTo(bearRel(a)));

  for (final entry in sorted) {
    final rule = entry.key;
    final byYear = entry.value;
    // 樣本太少（多為法人/基本面類資料不全）標註
    final maxN = years
        .map((y) => byYear[y]?.long.n ?? 0)
        .fold(0, (m, n) => n > m ? n : m);
    final lowData = maxN < minSamples;
    buf.writeln('');
    buf.writeln('▶ $rule${lowData ? "  ⚠️(樣本不足、僅參考)" : ""}');
    for (final y in years) {
      final c = byYear[y]?.long;
      if (c == null || c.n == 0) {
        buf.writeln('   $y: （無觸發）');
        continue;
      }
      buf.writeln(
        '   $y: n=${c.n.toString().padLeft(5)}  '
        'E=${_pct(c.expectancy)}  '
        '勝=${(c.winRate * 100).toStringAsFixed(0).padLeft(2)}%  '
        '(賺${_pct(c.avgWin)}/賠${_pct(c.avgLoss)})  '
        '相對=${_pct(c.relative)}',
      );
    }
  }
  return buf.toString();
}

String _pct(double v) {
  final s = v >= 0 ? '+' : '';
  return '$s${v.toStringAsFixed(1)}'.padLeft(6);
}

// ============================================================================
// CLI entry
// ============================================================================

Future<void> main(List<String> args) async {
  final code = await runRegimeReportCli(args);
  exit(code);
}

Future<int> runRegimeReportCli(List<String> args) async {
  final dbPath =
      Platform.environment['CALIBRATION_DB'] ?? 'tool/calibration.db';
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 不存在: $dbPath');
    return 2;
  }

  final years =
      (Platform.environment['REGIME_YEARS'] ?? '2021,2022,2023,2024,2025,2026')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
  final sampleSize =
      int.tryParse(Platform.environment['REGIME_SAMPLE_SIZE'] ?? '400') ?? 400;
  final minUniverse =
      int.tryParse(Platform.environment['REGIME_MIN_UNIVERSE'] ?? '50') ?? 50;

  print('📂 DB: $dbPath');
  print('📅 Years: ${years.join(", ")}');

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

    final reporter = RegimeReporter(
      db: db,
      years: years,
      symbolsWhitelist: sample,
      minUniverseSymbols: minUniverse,
    );
    final data = await reporter.run();

    print('');
    print(formatReport(data, years));
    // 稽核 #12:零樣本 / 零規則不是「跑完了沒事」——原本一律 exit 0,
    // harness 的 expect(code, 0) 照過,而報告是空的。呼叫端必須分得出
    // 「這輪什麼都沒量到」與「量到了、結論是沒差異」。
    if (data.isEmpty) {
      stderr.writeln('❌ 零規則——本輪未量到任何 regime cell,報告是空的');
      return 5;
    }
    return 0;
  } finally {
    await db.close();
  }
}

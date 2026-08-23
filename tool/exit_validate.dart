// tool/exit_validate.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 出場條件 replay gate（評分改進 #3 Phase 1）。
//
// 驗證三個出場/失效條件（hardStop / trendBreak / timeStop）在歷史資料上
// 「觸發出場 vs 持有滿 60 交易日」是否有 edge，產出按 mode × 年切分的
// gate 報告供人工決定哪些條件上線。**沒 edge 的條件不進 app。**
//
// 設計：docs/plans/2026-07-11-exit-thesis-invalidation-design.md §2-§3
// 結果：docs/plans/2026-07-12-exit-gate-report.md（81,989 樣本；hardStop/trendBreak 全負不上線）
//
// ## 關鍵原則
//
// - 進場模擬 = 訊號日**次一交易日收盤**（T+1）——盤後 app 買不到訊號日
//   收盤（與 calibration look-ahead 修正同一原則）。
// - 觸發判斷基準 = 訊號日收盤（T0 referencePrice）。兩者不可互換。
// - 出場後以 0% 報酬計（不含資金再部署效益）→ gate 系統性低估出場紀律
//   的實務價值；「沒 edge」= 單筆訊號品質無差異，不等於「紀律沒用」。

import 'dart:io';

import 'package:daredevil/core/constants/exit_params.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';

import 'replay_calibrator.dart';

// ============================================================================
// 純函數出場模擬（importable by tests）
// ============================================================================

/// 單一樣本的出場模擬結果
typedef ExitSimResult = ({
  double exitReturnPct, // 出場版總報酬（%），出場後 0
  double holdReturnPct, // 持有滿 horizon 總報酬（%）
  int holdingDays, // 出場版實際持有交易日數（未觸發 = horizon）
  ExitReason? reason, // null = 全程未觸發
  double exitMddPct, // 出場版最大回檔（%，負值）
  double holdMddPct, // 持有版最大回檔
});

/// 對單一樣本（訊號日 [t0Index]）模擬「條件出場 vs 持有」。
///
/// [closes]：該股收盤序列（升序、可含 null＝停牌日）。
/// [enabled]：本次模擬啟用的條件集（單條變體用）。
///
/// 回 null 的情況（caller 應計入 survivorship counter、不得靜默丟棄）：
/// - referencePrice（T0 收盤）為 null
/// - T+1 進場價不存在 / null / ≤ 0
/// - T+1 + horizon 超出序列（60 日窗不完整——下市/資料尾端）
ExitSimResult? simulateExit({
  required List<double?> closes,
  required int t0Index,
  required Set<ExitReason> enabled,
}) {
  final ref = closes[t0Index];
  final entryIndex = t0Index + 1;
  final endIndex = entryIndex + ExitParams.holdHorizonTradingDays;
  if (ref == null || ref <= 0 || endIndex >= closes.length) return null;
  final entry = closes[entryIndex];
  if (entry == null || entry <= 0) return null;

  // 該日往前（含該日）60 根非 null 收盤的平均；不足 60 根回 null（不判定）
  double? ma60At(int d) {
    var sum = 0.0;
    var n = 0;
    for (var k = d; k >= 0 && n < ExitParams.ma60Window; k--) {
      final c = closes[k];
      if (c != null) {
        sum += c;
        n++;
      }
    }
    return n < ExitParams.ma60Window ? null : sum / n;
  }

  var everAboveRef = false;
  ExitReason? reason;
  var exitIndex = endIndex; // 未觸發 = 持有到 horizon 末
  for (var d = entryIndex; d <= endIndex; d++) {
    final c = closes[d];
    // 停牌 null 列跳過判定。timeStop 以 index 差（=價格列數）計數，與
    // spec §2「以價格列數計」一致；TWSE 停牌通常為缺列 → 倒數自然凍結，
    // 若資料含 null-close 列則該列仍計入 40 日窗（已知資料語意相依）。
    if (c == null) continue;
    if (c > ref) everAboveRef = true;

    // 同日 tie-break：照 ExitReason 宣告序（hardStop > trendBreak > timeStop）
    ExitReason? hit;
    if (enabled.contains(ExitReason.hardStop) &&
        c < ref * (1 - ExitParams.hardStopPct)) {
      hit = ExitReason.hardStop;
    } else if (enabled.contains(ExitReason.trendBreak)) {
      final ma = ma60At(d);
      if (ma != null && c < ma) hit = ExitReason.trendBreak;
    }
    if (hit == null &&
        enabled.contains(ExitReason.timeStop) &&
        d - t0Index >= ExitParams.timeStopTradingDays &&
        !everAboveRef) {
      hit = ExitReason.timeStop;
    }
    if (hit != null) {
      reason = hit;
      exitIndex = d;
      break;
    }
  }

  double retPct(int d) => (closes[d]! / entry - 1) * 100;

  // 出場日/窗末若為 null（停牌），往前找最近非 null 收盤當結算價
  int settleIndex(int from) {
    var d = from;
    while (d > entryIndex && closes[d] == null) {
      d--;
    }
    return d;
  }

  var exitMdd = 0.0;
  var holdMdd = 0.0;
  for (var d = entryIndex; d <= endIndex; d++) {
    if (closes[d] == null) continue;
    final r = retPct(d);
    if (d <= exitIndex && r < exitMdd) exitMdd = r;
    if (r < holdMdd) holdMdd = r;
  }

  return (
    exitReturnPct: retPct(settleIndex(exitIndex)),
    holdReturnPct: retPct(settleIndex(endIndex)),
    holdingDays: reason == null
        ? ExitParams.holdHorizonTradingDays
        : exitIndex - entryIndex,
    reason: reason,
    exitMddPct: exitMdd,
    holdMddPct: holdMdd,
  );
}

// ============================================================================
// 樣本蒐集與 4 變體模擬 pipeline
// ============================================================================

/// mode 訊號日樣本（釘選模擬的近似：該日該 mode 規則分數加總過訊號門檻）
typedef ExitSample = ({String symbol, DateTime date, String mode});

/// 單一樣本在單一變體下的模擬結果
typedef ExitVariantRow = ({ExitSample sample, ExitSimResult sim});

/// gate 驗證總結果
class ExitValidationResult {
  const ExitValidationResult({
    required this.samples,
    required this.variantResults,
    required this.skippedNoWindow,
    required this.limitFlaggedT0,
    required this.limitFlaggedExit,
  });

  /// 通過去重與窗檢查、實際進入模擬的樣本
  final List<ExitSample> samples;

  /// 變體名（all / hardStop / trendBreak / timeStop）→ 每樣本模擬結果
  final Map<String, List<ExitVariantRow>> variantResults;

  /// Survivorship counter：T+1+60 窗不完整（下市/資料尾端/停牌斷點）
  /// 而被排除的樣本數——報告必印、不得靜默（spec §3）。
  final int skippedNoWindow;

  /// T0 為漲/跌停的樣本數（v1 只觀察不特殊處理，spec §3）
  final int limitFlaggedT0;

  /// 出場觸發日為漲/跌停的樣本數（all 變體）。跌停鎖死日的收盤價實務上
  /// 常無法成交——此計數揭露「多少出場價可能樂觀不可成交」，供 gate
  /// 決策保守解讀（spec §3：釘選日**或觸發日**皆須標記）。
  final int limitFlaggedExit;
}

/// 出場條件 gate 驗證器
///
/// pipeline：ReplayCalibrator（scoreSink 蒐樣本）→ 載入樣本股價格序列
/// → 對每樣本跑 4 個條件變體的 [simulateExit] → 聚合。
class ExitValidator {
  ExitValidator({
    required this.db,
    required this.replayConfig,
    AnalysisService? analysisService,
    RuleEngine? ruleEngine,
    void Function(String)? logger,
  }) : _analysisService = analysisService,
       _ruleEngine = ruleEngine,
       _log = logger ?? print;

  final AppDatabase db;
  final ReplayConfig replayConfig;
  final AnalysisService? _analysisService;
  final RuleEngine? _ruleEngine;
  final void Function(String) _log;

  /// 4 個條件變體（報告各自 vs 持有）
  static const Map<String, Set<ExitReason>> variants = {
    'all': {ExitReason.hardStop, ExitReason.trendBreak, ExitReason.timeStop},
    'hardStop': {ExitReason.hardStop},
    'trendBreak': {ExitReason.trendBreak},
    'timeStop': {ExitReason.timeStop},
  };

  static DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<ExitValidationResult> run() async {
    // 1. Replay + sink 蒐集 raw 樣本（mode 分數加總 ≥ 訊號門檻）
    _log('▶️  Replay 蒐集 mode 訊號日樣本...');
    final raw = <ExitSample>[];
    void sink(ScoreSample s) {
      if (s.modeMomentum >= ExitParams.modeSignalScoreThreshold) {
        raw.add((symbol: s.symbol, date: s.date, mode: 'momentum'));
      }
      if (s.modeStrength >= ExitParams.modeSignalScoreThreshold) {
        raw.add((symbol: s.symbol, date: s.date, mode: 'strength'));
      }
      if (s.modePullback >= ExitParams.modeSignalScoreThreshold) {
        raw.add((symbol: s.symbol, date: s.date, mode: 'pullback'));
      }
    }

    await ReplayCalibrator(
      db: db,
      config: replayConfig,
      analysisService: _analysisService,
      ruleEngine: _ruleEngine,
      scoreSink: sink,
      logger: (_) {},
    ).run();
    _log('✅ raw 樣本 ${raw.length} 筆');

    // 2. 載入樣本股價格序列（升序）+ date→index 對照
    final symbols = raw.map((s) => s.symbol).toSet();
    final closesBySymbol = <String, List<double?>>{};
    final indexBySymbol = <String, Map<DateTime, int>>{};
    for (final symbol in symbols) {
      final prices = await db.getPriceHistory(
        symbol,
        startDate: DateTime(2000),
        endDate: DateTime(2100),
      );
      prices.sort((a, b) => a.date.compareTo(b.date));
      closesBySymbol[symbol] = [for (final p in prices) p.close];
      indexBySymbol[symbol] = {
        for (var i = 0; i < prices.length; i++) _dateKey(prices[i].date): i,
      };
    }

    // 3. 去重（同 symbol×mode 不重疊窗）+ 窗檢查 + 4 變體模擬
    //    非重疊：下一筆 T0 必須 > 前一筆的窗末 index（T0+1+horizon）。
    //    simulateExit 回 null 的判準與 enabled 無關 → survivorship 只數一次。
    raw.sort((a, b) {
      final s = a.symbol.compareTo(b.symbol);
      if (s != 0) return s;
      final m = a.mode.compareTo(b.mode);
      if (m != 0) return m;
      return a.date.compareTo(b.date);
    });

    final samples = <ExitSample>[];
    final variantResults = <String, List<ExitVariantRow>>{
      for (final name in variants.keys) name: [],
    };
    var skippedNoWindow = 0;
    var limitFlaggedT0 = 0;
    var limitFlaggedExit = 0;
    final lastWindowEnd = <String, int>{}; // '$symbol|$mode' → 窗末 index

    for (final sample in raw) {
      final closes = closesBySymbol[sample.symbol];
      final t0 = indexBySymbol[sample.symbol]?[_dateKey(sample.date)];
      if (closes == null || t0 == null) {
        skippedNoWindow++;
        continue;
      }

      final key = '${sample.symbol}|${sample.mode}';
      final prevEnd = lastWindowEnd[key];
      if (prevEnd != null && t0 <= prevEnd) continue; // 重疊窗、非 survivorship

      final allSim = simulateExit(
        closes: closes,
        t0Index: t0,
        enabled: variants['all']!,
      );
      if (allSim == null) {
        skippedNoWindow++;
        continue;
      }

      lastWindowEnd[key] = t0 + 1 + ExitParams.holdHorizonTradingDays;
      samples.add(sample);
      variantResults['all']!.add((sample: sample, sim: allSim));
      for (final name in variants.keys) {
        if (name == 'all') continue;
        final sim = simulateExit(
          closes: closes,
          t0Index: t0,
          enabled: variants[name]!,
        );
        // null 判準與 enabled 無關，all 已過 → 此處必非 null
        variantResults[name]!.add((sample: sample, sim: sim!));
      }

      // 漲跌停 flag（v1 只觀察）：以前一非 null 收盤推漲跌幅
      bool isLimitDay(int idx) {
        final cur = closes[idx];
        if (cur == null) return false;
        var p = idx - 1;
        while (p >= 0 && closes[p] == null) {
          p--;
        }
        final prev = p >= 0 ? closes[p] : null;
        if (prev == null || prev <= 0) return false;
        final changePct = (cur / prev - 1) * 100;
        return PriceLimit.isLimitUp(changePct) ||
            PriceLimit.isLimitDown(changePct);
      }

      if (isLimitDay(t0)) limitFlaggedT0++;
      // 觸發日（僅 all 變體有觸發時）：exitIndex = entry + holdingDays
      if (allSim.reason != null && isLimitDay(t0 + 1 + allSim.holdingDays)) {
        limitFlaggedExit++;
      }
    }

    _log(
      '✅ 樣本 ${samples.length} 筆（去重後）、'
      'survivorship 排除 $skippedNoWindow、'
      'T0 漲跌停 $limitFlaggedT0、觸發日漲跌停 $limitFlaggedExit',
    );

    return ExitValidationResult(
      samples: samples,
      variantResults: variantResults,
      skippedNoWindow: skippedNoWindow,
      limitFlaggedT0: limitFlaggedT0,
      limitFlaggedExit: limitFlaggedExit,
    );
  }
}

// ============================================================================
// 報告聚合（mode × 年 × 變體）
// ============================================================================

/// 產出 gate 報告（markdown 文字）。
///
/// 每個變體一段，段內按 (mode × 年) cell 列：n、出場/持有平均報酬與差、
/// 勝率（出場 ≥ 持有比例）、平均持有日、兩臂平均 MDD。
/// n < [ExitParams.minCellSample] 的 cell 標「(樣本不足)」不計入結論。
String buildReport(ExitValidationResult result) {
  final buf = StringBuffer();
  buf.writeln('# 出場條件 Replay Gate 報告');
  buf.writeln();
  buf.writeln('- 樣本（去重後）: ${result.samples.length}');
  buf.writeln(
    '- Survivorship 排除（T+1 停牌 / 窗不完整）: ${result.skippedNoWindow} — '
    '這些樣本無 exit price，若比例高則報酬有存活者偏差、結論須保守解讀',
  );
  buf.writeln('- T0 為漲跌停的樣本: ${result.limitFlaggedT0}（v1 只觀察不特殊處理）');
  buf.writeln(
    '- 出場觸發日為漲跌停的樣本: ${result.limitFlaggedExit} — '
    '鎖死日收盤價可能不可成交，比例高則出場報酬偏樂觀',
  );
  buf.writeln();
  buf.writeln('> **方法論限制**：出場後以 0% 報酬計＝不含資金再部署效益，');
  buf.writeln('> gate 系統性低估出場紀律的實務價值——「沒 edge」應解讀為');
  buf.writeln('> 「單筆訊號品質無差異」，不等於「紀律沒用」。');
  buf.writeln();

  for (final entry in result.variantResults.entries) {
    final variant = entry.key;
    final rows = entry.value;
    buf.writeln('## 變體: $variant');
    buf.writeln();
    buf.writeln(
      '| mode | 年 | n | 出場均報酬% | 持有均報酬% | 差(出場-持有) | 勝率% | 均持有日 | 出場MDD% | 持有MDD% | 觸發率% |',
    );
    buf.writeln('|---|---|---|---|---|---|---|---|---|---|---|');

    // (mode, year) 分組
    final cells = <String, List<ExitVariantRow>>{};
    for (final row in rows) {
      final key = '${row.sample.mode}|${row.sample.date.year}';
      cells.putIfAbsent(key, () => []).add(row);
    }
    final keys = cells.keys.toList()..sort();
    for (final key in keys) {
      final cellRows = cells[key]!;
      final parts = key.split('|');
      final n = cellRows.length;
      double avg(Iterable<double> xs) =>
          xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
      final exitAvg = avg(cellRows.map((r) => r.sim.exitReturnPct));
      final holdAvg = avg(cellRows.map((r) => r.sim.holdReturnPct));
      final winRate =
          cellRows
              .where((r) => r.sim.exitReturnPct >= r.sim.holdReturnPct)
              .length /
          n *
          100;
      final avgDays = avg(cellRows.map((r) => r.sim.holdingDays.toDouble()));
      final exitMdd = avg(cellRows.map((r) => r.sim.exitMddPct));
      final holdMdd = avg(cellRows.map((r) => r.sim.holdMddPct));
      final triggerRate =
          cellRows.where((r) => r.sim.reason != null).length / n * 100;
      final grey = n < ExitParams.minCellSample ? ' (樣本不足)' : '';
      buf.writeln(
        '| ${parts[0]} | ${parts[1]} | $n$grey '
        '| ${exitAvg.toStringAsFixed(2)} | ${holdAvg.toStringAsFixed(2)} '
        '| ${(exitAvg - holdAvg).toStringAsFixed(2)} '
        '| ${winRate.toStringAsFixed(0)} | ${avgDays.toStringAsFixed(0)} '
        '| ${exitMdd.toStringAsFixed(2)} | ${holdMdd.toStringAsFixed(2)} '
        '| ${triggerRate.toStringAsFixed(0)} |',
      );
    }
    buf.writeln();
  }
  return buf.toString();
}

// ============================================================================
// CLI entry（經 flutter test wrapper 執行，見 test/tool/run_exit_validate.dart）
// ============================================================================

/// 不呼叫 exit() 的入口。exit codes：0 = 成功、2 = DB 不存在。
Future<int> runExitValidateCli(List<String> args) async {
  var dbPath = 'tool/calibration.db';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--db' && i + 1 < args.length) dbPath = args[++i];
  }
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 檔案不存在: $dbPath（先跑 backfill）');
    return 2;
  }

  print('📦 開啟 calibration DB: $dbPath');
  final db = AppDatabase.forToolFile(dbPath);
  try {
    final validator = ExitValidator(
      db: db,
      replayConfig: ReplayConfig(dbPath: dbPath),
    );
    final result = await validator.run();
    final report = buildReport(result);
    print(report);
    const outPath = 'tool/exit-validate-report.md';
    File(outPath).writeAsStringSync(report);
    print('📄 報告已寫入 $outPath');
    return 0;
  } finally {
    await db.close();
  }
}

Future<void> main(List<String> args) async {
  exit(await runExitValidateCli(args));
}

// 評分快照工具(2026-08-15 建立)——改動評分邏輯前後的逐檔對照
//
// **不是測試檔**(檔名不含 `_test`),`flutter test` 全套不會跑到。
// 用法:
//   flutter test test/tools/scoring_snapshot.dart          # 產生快照
//   SNAPSHOT_OUT=/tmp/after.json flutter test test/tools/scoring_snapshot.dart
//
// 為什麼需要它:改評分邏輯一定會改變輸出,而「測試綠」只證明我想得到的
// 情況沒壞。真正的保證是**對同一批真實資料跑前後兩次,逐檔解釋每個差異**
// ——解釋不通的就是改壞了。
//
// 它讀 production DB 的**唯讀副本**,不碰正式資料。
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_table.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/rules/indicator_rules.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/scoring_pipeline.dart';
import 'package:daredevil/domain/services/update/batch_data_builder.dart';

/// 預設讀這個副本;請先自行 cp 一份 production DB 過去
const _defaultDb =
    '/private/tmp/claude-501/-Users-nealchen-IdeaProjects/'
    '258545d2-6182-4324-b5ef-772b670483b6/scratchpad/snapshot_src.sqlite';

void main() {
  test('產生評分快照', () async {
    final dbPath = Platform.environment['SNAPSHOT_DB'] ?? _defaultDb;
    final outPath =
        Platform.environment['SNAPSHOT_OUT'] ?? '/tmp/scoring_snapshot.json';
    final limit =
        int.tryParse(Platform.environment['SNAPSHOT_LIMIT'] ?? '') ?? 0;

    final db = AppDatabase(NativeDatabase(File(dbPath)));

    // 評分日 = DB 最新交易日
    final dateRow = await db
        .customSelect('SELECT MAX(date) d FROM daily_price')
        .getSingle();
    final dateStr = dateRow.read<String>('d');
    final date = DateTime.parse(dateStr.substring(0, 10));

    // universe:當日有分析結果的股票(與 production 的候選集一致)
    var symbols =
        (await db
                .customSelect(
                  'SELECT DISTINCT symbol FROM daily_analysis WHERE date = ?',
                  variables: [Variable.withString(dateStr)],
                )
                .get())
            .map((r) => r.read<String>('symbol'))
            .toList()
          ..sort();
    if (limit > 0 && symbols.length > limit) {
      symbols = symbols.sublist(0, limit);
    }

    // ── 組 batch data(直接查 DB,不走 BatchDataLoader 以免牽動網路 client)
    final start = date.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    );
    final pricesMap = await db.getPriceHistoryBatch(
      symbols,
      startDate: start,
      endDate: date,
    );
    final revenueHistoryMap = await db.getRecentMonthlyRevenueBatch(symbols);
    final epsHistoryMap = await db.getEPSHistoryBatch(symbols);
    final roeHistoryMap = await db.getROEHistoryBatch(symbols);
    // 52 週規則的股利情境：與 production（BatchDataLoader）同一個 builder
    final dividendContexts = BatchDataBuilder.buildDividendContexts(
      pricesMap: pricesMap,
      completeness: await loadDividendCompleteness(db, now: date),
      events: await db.getDividendEventsBatch(symbols, from: start, to: date),
      date: date,
    );
    final valuationMap = await db.getLatestValuationsBatch(symbols);
    final revenueMap = <String, MonthlyRevenueEntry>{
      for (final e in revenueHistoryMap.entries)
        if (e.value.isNotEmpty) e.key: e.value.first,
    };

    // ⚠️ 沒有 marketData 的話,籌碼類規則(外資/集中度/警示/內部人)**全部
    // 跑不到**——2026-08-15 用已知會產生 8 檔差異的變異校準工具時抓到:
    // 工具報 0 檔差異,不是「沒差異」而是「這條路徑根本沒執行」。
    // 窗口與 builder 皆對齊 batch_data_loader 的 production 路徑。
    final shareholdingEntries = await db.getLatestShareholdingsBatch(
      symbols,
      asOf: date,
    );
    final prevShareholdingEntries = await db.getShareholdingsBeforeDateBatch(
      symbols,
      beforeDate: date.subtract(
        const Duration(
          days: InstitutionalParams.foreignShareholdingLookbackDays,
        ),
      ),
    );
    // 集中度走真正的 repository(CONCENTRATION_HIGH 是最高頻規則,
    // 3,166 次;略過它會讓快照嚴重失真)。FinMindClient 只在建構子被要求,
    // 這條路徑純查 DB、不打網路。
    final shareholdingRepo = ShareholdingRepository(
      database: db,
      finMindClient: FinMindClient(),
      twseClient: TwseClient(),
    );
    final concentrationMap = await shareholdingRepo.getConcentrationRatioBatch(
      symbols,
    );
    final shareholdingMap = BatchDataBuilder.buildShareholdingMap(
      shareholdingEntries,
      prevShareholdingEntries,
      concentrationMap,
      evaluationDate: date,
    );

    final batch = ScoringBatchData(
      pricesMap: pricesMap,
      newsMap: const {},
      revenueMap: revenueMap,
      valuationMap: valuationMap,
      revenueHistoryMap: revenueHistoryMap,
      epsHistoryMap: epsHistoryMap,
      roeHistoryMap: roeHistoryMap,
      shareholdingMap: shareholdingMap,
      dividendContexts: dividendContexts,
    );

    // 載入真實校準值——**必要**:CalibratedScoreContext.empty 會讓
    // calibrated == hardcoded,兩條 mutex 路徑選出同一個贏家,落庫不一致
    // 的 bug 就測不出來(2026-08-15 建工具時踩到的第二個坑)。
    // 走 production 的 calibrated JSON + snapshotForIsolate();但這裡的 parseJson
    // 沒帶 structuralExemptions(短線 Mode C 規則的歸零豁免),與 production
    // registry 在短線仍有差異。
    final hardcoded = {for (final r in ReasonType.values) r.code: r.score};
    final knownIds = ReasonType.values.map((r) => r.code).toSet();
    final registry = CalibratedScoresRegistry.instance;
    registry.bindForTesting(
      short: CalibratedScoresTable.parseJson(
        File('assets/rule_scores_calibrated_short.json').readAsStringSync(),
        horizon: Horizon.short,
        knownRuleIds: knownIds,
        hardcodedScores: hardcoded,
        applyNegativeEvidenceZeroing: true,
      ).table,
      long: CalibratedScoresTable.parseJson(
        File('assets/rule_scores_calibrated_long.json').readAsStringSync(),
        horizon: Horizon.long,
        knownRuleIds: knownIds,
        hardcodedScores: hardcoded,
      ).table,
    );
    final calibrated = registry.snapshotForIsolate();
    // ignore: avoid_print
    print(
      'CALIB short非零=${calibrated.shortScores.values.where((v) => v != 0).length} '
      'zeroed=${calibrated.zeroedShortRules.length} '
      'long非零=${calibrated.longScores.values.where((v) => v != 0).length}',
    );

    final analysis = AnalysisService();
    final engine = RuleEngine();
    final out = <String, dynamic>{};
    var skipped = 0;

    for (final symbol in symbols) {
      final prices = batch.pricesMap[symbol];
      if (prices == null || prices.length < RuleParams.swingWindow) {
        skipped++;
        continue;
      }
      final result = analysis.analyzeStock(prices);
      if (result == null) {
        skipped++;
        continue;
      }
      final sh = batch.institutional.shareholdingMap?[symbol];
      final context = analysis.buildContext(
        result,
        priceHistory: prices,
        evaluationTime: date,
        marketData: sh == null
            ? null
            : MarketDataContext(
                foreignSharesRatio: sh.foreignSharesRatio,
                foreignSharesRatioChange: sh.foreignSharesRatioChange,
                concentrationRatio: sh.concentrationRatio,
              ),
      );
      final data = StockData(
        symbol: symbol,
        prices: prices,
        dividends:
            batch.dividendContexts[symbol] ??
            const DividendContext.incomplete(),
        latestRevenue: batch.fundamental.revenueMap?[symbol],
        latestValuation: batch.fundamental.valuationMap?[symbol],
        revenueHistory: batch.fundamental.revenueHistoryMap?[symbol],
        epsHistory: batch.financialHealth.epsHistoryMap?[symbol],
        roeHistory: batch.financialHealth.roeHistoryMap?[symbol],
      );
      final reasons = engine.evaluateStock(context, data);
      if (reasons.isEmpty) continue;

      final scored = scoreReasonsDualHorizon(
        ruleEngine: engine,
        reasons: reasons,
        calibratedScores: calibrated,
      );
      if (scored == null) continue;

      // **落庫的是 topReasons(經 mutex 過濾),不是原始 reasons**——
      // 稽核第 01 條正是「落庫那份與計分那份選出不同贏家」,輸出原始
      // reasons 會讓這個差異隱形。
      out[symbol] = {
        'short': scored.scoreShort,
        'long': scored.scoreLong,
        'persisted': [for (final r in scored.topReasons) r.type.code]..sort(),
        // 與 calculateScore 同一算式:(calibrated ?? hardcoded) × decay,
        // 累加後 round。少了 decay 會讓所有含基本面規則的股票假性不一致。
        'persistedSum': scored.topReasons
            .fold<double>(
              0,
              (sum, r) =>
                  sum +
                  (calibrated.lookup(Horizon.short, r.type.code) ?? r.score) *
                      (scored.decayMultipliers[r.type.code] ?? 1.0),
            )
            .round(),
      };
    }

    File(outPath).writeAsStringSync(jsonEncode(out));
    // ignore: avoid_print
    print(
      'SNAPSHOT date=${date.toIso8601String().substring(0, 10)} '
      'universe=${symbols.length} scored=${out.length} skipped=$skipped '
      '→ $outPath',
    );
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 20)));

  // ── 52 週新舊對照回放（3-2 提交前的量測，spec「驗證」3-2）─────────────
  //
  //   WEEK52_REPLAY=1 SNAPSHOT_DB=<副本> WEEK52_OUT=<輸出.json> \
  //     flutter test test/tools/scoring_snapshot.dart --plain-name '52 週新舊對照回放'
  //
  // 逐日回放最近 WEEK52_DAYS（預設 62）個交易日；母體＝當日通過候選分類
  // （classifyCandidate）的全部在市股票，不只 daily_analysis 內者。只跑新舊
  // 兩版 52 週規則：
  // - 舊版＝3-2 之前的實作（_legacyWeek52，凍結副本）
  // - 新版＝現行規則，股利情境與 production 同一個判斷（priceContext）；事件
  //   只取除權息日 ≤ 當日。完整度用的是副本當下的事實（現況），不是當時的
  // 回放終點＝兩市場連續列過的最後一天（DividendCompleteness.displayEnd）：
  // 之後的日子新版一律判不完整，比了沒有意義。
  // 自我檢查：落庫的 WEEK_52_*（daily_reason）都應由舊版重現。
  test(
    '52 週新舊對照回放',
    () async {
      final dbPath = Platform.environment['SNAPSHOT_DB'] ?? _defaultDb;
      final outPath =
          Platform.environment['WEEK52_OUT'] ?? '/tmp/week52_replay.json';
      final dayCount =
          int.tryParse(Platform.environment['WEEK52_DAYS'] ?? '') ?? 62;
      // ⚠️ 開 DB 會跑 beforeOpen：只能對副本跑
      final db = AppDatabase(NativeDatabase(File(dbPath)));

      final latestRow = await db
          .customSelect('SELECT MAX(date) d FROM daily_price')
          .getSingle();
      final latest = DateTime.parse(
        latestRow.read<String>('d').substring(0, 10),
      );
      final completeness = await loadDividendCompleteness(db, now: latest);
      final end = completeness.displayEnd;
      if (end == null) fail('任一市場連回補起點的月份都沒列過，無從量測');

      String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
      final days = [
        for (final r
            in await db
                .customSelect(
                  'SELECT DISTINCT substr(date, 1, 10) d FROM daily_price '
                  'ORDER BY d DESC',
                )
                .get())
          DateContext.normalize(DateTime.parse(r.read<String>('d'))),
      ].where((d) => !d.isAfter(end)).take(dayCount).toList()..sort();

      const window = Duration(days: RuleParams.historyRequiredDays);
      final symbols = [for (final s in await db.getAllActiveStocks()) s.symbol]
        ..sort();
      final watchlist = {for (final w in await db.getWatchlist()) w.symbol};
      final pricesAll = await db.getPriceHistoryBatch(
        symbols,
        startDate: days.first.subtract(window),
        endDate: days.last,
      );
      final eventsAll = await db.getDividendEventsBatch(
        symbols,
        from: days.first.subtract(window),
        to: days.last,
      );
      final legacyDividends = await db.getDividendHistoryBatch(symbols);
      final persisted = <String, Set<String>>{};
      for (final r
          in await db
              .customSelect(
                'SELECT symbol, substr(date, 1, 10) d, reason_type t '
                'FROM daily_reason '
                "WHERE reason_type IN ('WEEK_52_HIGH', 'WEEK_52_LOW')",
              )
              .get()) {
        persisted
            .putIfAbsent(
              '${r.read<String>('d')} ${r.read<String>('symbol')}',
              () => {},
            )
            .add(r.read<String>('t'));
      }

      final analysis = AnalysisService();
      final rules = <(String, StockRule, bool)>[
        ('WEEK_52_HIGH', const Week52HighRule(), true),
        ('WEEK_52_LOW', const Week52LowRule(), false),
      ];
      final counts = {
        for (final (type, _, _) in rules)
          type: {
            'old': 0,
            'new': 0,
            'disappeared': 0,
            'added': 0,
            'persisted': 0,
            'persistedReproduced': 0,
            'persistedDisappeared': 0,
          },
      };
      void bump(String type, String key) =>
          counts[type]![key] = counts[type]![key]! + 1;
      final examples = <String, List<Map<String, Object?>>>{};
      final unreproduced = <String>[];
      final perDay = <Map<String, Object?>>[];

      for (final day in days) {
        final from = day.subtract(window);
        var evaluated = 0;
        var incomplete = 0;
        var discontinuity = 0;
        for (final symbol in symbols) {
          final prices = [
            for (final p in pricesAll[symbol] ?? const <DailyPriceEntry>[])
              if (!p.date.isBefore(from) && !p.date.isAfter(day)) p,
          ];
          if (classifyCandidate(
                prices,
                asOf: day,
                exemptFromLiquidity: watchlist.contains(symbol),
              ) !=
              null) {
            continue;
          }
          final result = analysis.analyzeStock(prices);
          if (result == null) continue;
          evaluated++;
          final context = analysis.buildContext(
            result,
            priceHistory: prices,
            evaluationTime: day,
          );
          final data = StockData(
            symbol: symbol,
            prices: prices,
            dividends: completeness.priceContext(
              symbol,
              from: prices.first.date,
              asOf: day,
              rows: eventsAll[symbol] ?? const [],
            ),
          );
          final block = week52AdjustedPrices(data).block;
          if (block == Week52Block.incomplete) incomplete++;
          if (block == Week52Block.discontinuity) discontinuity++;

          for (final (type, rule, isHigh) in rules) {
            final before = _legacyWeek52(
              context,
              prices,
              legacyDividends[symbol],
              isHigh: isHigh,
            );
            final after = rule.evaluate(context, data);
            if (before != null) bump(type, 'old');
            if (after != null) bump(type, 'new');
            final wasPersisted =
                persisted['${ymd(day)} $symbol']?.contains(type) ?? false;
            if (wasPersisted) {
              bump(type, 'persisted');
              if (before != null) {
                bump(type, 'persistedReproduced');
              } else {
                unreproduced.add('${ymd(day)} $symbol $type');
              }
              if (before != null && after == null) {
                bump(type, 'persistedDisappeared');
              }
            }
            if ((before == null) == (after == null)) continue;
            final kind = before != null ? 'disappeared' : 'added';
            bump(type, kind);
            (examples['$type $kind'] ??= []).add({
              'day': ymd(day),
              'symbol': symbol,
              'persisted': wasPersisted,
              'close': prices.last.close,
              'old': before == null
                  ? null
                  : {
                      'extreme': before.extreme,
                      'adjusted': before.adjusted,
                      'isNew': before.isNew,
                    },
              'new': after?.evidence,
              'block': block?.name,
              'events': [
                if (data.dividends case DividendComplete(:final events))
                  for (final e in events)
                    '${ymd(e.exDate)} ×${e.factor.toStringAsFixed(4)}',
              ],
            });
          }
        }
        perDay.add({
          'day': ymd(day),
          'evaluated': evaluated,
          'incomplete': incomplete,
          'discontinuity': discontinuity,
        });
      }

      final report = {
        'range': '${ymd(days.first)}～${ymd(days.last)}',
        'days': days.length,
        'displayEnd': ymd(end),
        'note':
            '完整度用的是 DB 副本當下的事實（現況），不是當時的事實；'
            '舊版的股利扣除照 3-2 前的實作（含其前視）',
        'counts': counts,
        'unreproducedPersisted': unreproduced.take(30).toList(),
        'perDay': perDay,
        'examples': {
          for (final e in examples.entries) e.key: e.value.take(15).toList(),
        },
      };
      File(
        outPath,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      // ignore: avoid_print
      print(
        'WEEK52 ${report['range']}（${days.length} 天，顯示終點 '
        '${report['displayEnd']}）→ $outPath',
      );
      for (final e in counts.entries) {
        // ignore: avoid_print
        print('${e.key} ${e.value}');
      }
      await db.close();
    },
    skip: Platform.environment['WEEK52_REPLAY'] == null
        ? '設 WEEK52_REPLAY=1 才跑（讀 DB 副本、數分鐘）'
        : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

/// 3-2 之前的 52 週規則（凍結副本，只供量測對照，不得修改）：原始極值扣掉
/// dividend_history 的窗內現金股利；新低以 context.indicators 的均線過濾
({bool isNew, double extreme, double adjusted})? _legacyWeek52(
  AnalysisContext context,
  List<DailyPriceEntry> prices,
  List<DividendHistoryEntry>? dividends, {
  required bool isHigh,
}) {
  if (prices.length < IndicatorParams.week52Days) return null;
  final close = prices.last.close;
  if (close == null) return null;

  double extreme = isHigh ? 0 : double.infinity;
  var validCount = 0;
  for (var i = 0; i < prices.length - 1; i++) {
    final p = prices[i];
    final value = isHigh ? (p.high ?? p.close) : (p.low ?? p.close);
    if (value == null || value <= 0) continue;
    validCount++;
    if (isHigh ? value > extreme : value < extreme) extreme = value;
  }
  final invalid = isHigh
      ? extreme <= 0
      : (extreme == double.infinity || extreme <= 0);
  if (invalid || validCount < IndicatorParams.week52MinValidBars) return null;

  var totalDividend = 0.0;
  if (dividends != null && dividends.isNotEmpty) {
    final lookbackStart = prices.first.date;
    for (final div in dividends) {
      if (div.exDividendDate == null) continue;
      final exDate = DateTime.tryParse(div.exDividendDate!);
      if (exDate != null && exDate.isAfter(lookbackStart)) {
        totalDividend += div.cashDividend;
      }
    }
  }
  final adjusted = extreme - totalDividend;
  if (adjusted <= 0) return null;

  final threshold = isHigh
      ? IndicatorParams.week52HighThreshold
      : IndicatorParams.week52LowThreshold;
  final thresholdPrice = isHigh
      ? adjusted * (1 - threshold)
      : adjusted * (1 + threshold);
  if (isHigh ? close < thresholdPrice : close > thresholdPrice) return null;
  if (!isHigh) {
    final ma20 = context.indicators?.ma20;
    final ma60 = context.indicators?.ma60;
    if (ma20 != null && ma60 != null && (close >= ma20 || ma20 >= ma60)) {
      return null;
    }
  }
  return (
    isNew: isHigh ? close >= adjusted : close <= adjusted,
    extreme: extreme,
    adjusted: adjusted,
  );
}

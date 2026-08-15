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

import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_table.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/constants/rule_params_institutional.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
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
    final dividendHistoryMap = await db.getDividendHistoryBatch(symbols);
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
      dividendHistoryMap: dividendHistoryMap,
      shareholdingMap: shareholdingMap,
    );

    // 載入真實校準值——**必要**:CalibratedScoreContext.empty 會讓
    // calibrated == hardcoded,兩條 mutex 路徑選出同一個贏家,落庫不一致
    // 的 bug 就測不出來(2026-08-15 建工具時踩到的第二個坑)。
    // 走 production 自己的 registry + snapshotForIsolate(),零近似。
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
        latestRevenue: batch.fundamental.revenueMap?[symbol],
        latestValuation: batch.fundamental.valuationMap?[symbol],
        revenueHistory: batch.fundamental.revenueHistoryMap?[symbol],
        epsHistory: batch.financialHealth.epsHistoryMap?[symbol],
        roeHistory: batch.financialHealth.roeHistoryMap?[symbol],
        dividendHistory: batch.financialHealth.dividendHistoryMap?[symbol],
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
}

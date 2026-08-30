import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/price_continuity.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/models/scoring_data_groups.dart';
import 'package:daredevil/domain/services/update/batch_data_builder.dart';

/// 評分用批次資料載入器
///
/// 平行載入 14+ 個 DB 查詢，組裝為 [ScoringBatchData]
/// 供 Isolate 評分使用。從 UpdateService 提取以降低複雜度。
class BatchDataLoader {
  BatchDataLoader({
    required AppDatabase database,
    required NewsRepository newsRepository,
    InstitutionalRepository? institutionalRepository,
    ShareholdingRepository? shareholdingRepository,
    InsiderRepository? insiderRepository,
  }) : _db = database,
       _newsRepo = newsRepository,
       _institutionalRepo = institutionalRepository,
       _shareholdingRepo = shareholdingRepository,
       _insiderRepo = insiderRepository;

  final AppDatabase _db;
  final NewsRepository _newsRepo;
  final InstitutionalRepository? _institutionalRepo;
  final ShareholdingRepository? _shareholdingRepo;
  final InsiderRepository? _insiderRepo;

  /// 平行載入所有評分所需的批次資料
  ///
  /// 同時啟動 14+ 個 DB 查詢，使用 Dart 3 Record 解構等待，
  /// 再將原始資料轉換為 Isolate 可用的 Map 格式。
  Future<ScoringBatchData> loadBatchData(
    DateTime date,
    List<String> candidates,
  ) async {
    // 與 HistoricalPriceSyncer 的充足性判斷窗（historyRequiredDays）同源。
    // 舊值 lookbackPrice + 10（380 日曆日）比判斷窗（400）窄 20 天：
    // syncer 在 400 天窗數到 ≥250 個交易日判定「夠、不回補」，本窗卻只
    // 切出 ~247 個給規則 → 52 週新高/新低對幾乎全市場長期「資料不足
    // (247/250)」。兩窗同源後縫隙不再存在（2026-06 修 syncer 早退條件
    // 只治了一半，症狀從 221 變 247，根因在此）。
    final startDate = date.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    );
    // 用 streak 專用窗而非顯示窗：連續買賣超規則會掃到窗邊界為止，窗太窄
    // 會把長 streak 截斷成「剛好等於窗長」（見 institutionalStreakLookbackDays）。
    final instStartDate = date.subtract(
      const Duration(days: InstitutionalParams.institutionalStreakLookbackDays),
    );

    final instRepo = _institutionalRepo;

    // per-query 完成耗時（並行下 = 該查詢從啟動到完成的牆鐘，含排隊；
    // debug log 用於定位載入熱點——更新裡最大的本機區塊之一 ~9-12s）
    final timings = <String, int>{};
    final totalTimer = Stopwatch()..start();
    Future<T> timed<T>(String label, Future<T> future) async {
      final result = await future;
      timings[label] = totalTimer.elapsedMilliseconds;
      return result;
    }

    // 同時啟動所有批次查詢（所有 Future 在建立時即開始並行執行）
    final pricesFuture = timed(
      'prices',
      _db.getPriceHistoryBatch(candidates, startDate: startDate, endDate: date),
    );
    final newsFuture = timed(
      'news',
      _newsRepo.getNewsForStocksBatch(candidates, days: 2),
    );
    final instFuture = timed(
      'institutional',
      instRepo != null
          ? _db.getInstitutionalHistoryBatch(
              candidates,
              startDate: instStartDate,
              endDate: date,
            )
          : Future.value(<String, List<DailyInstitutionalEntry>>{}),
    );
    final revenueFuture = timed(
      'revenue',
      _db.getLatestMonthlyRevenuesBatch(candidates, asOf: date),
    );
    final valuationFuture = timed(
      'valuation',
      _db.getLatestValuationsBatch(candidates, asOf: date),
    );
    final revenueHistoryFuture = timed(
      'revenueHistory',
      _db.getRecentMonthlyRevenueBatch(
        candidates,
        months: DataFreshness.revenueDisplayMonths,
      ),
    );
    final dayTradingFuture = timed(
      'dayTrading',
      _db.getDayTradingMapForDate(date),
    );
    final shareholdingFuture = timed(
      'shareholding',
      _db.getLatestShareholdingsBatch(candidates, asOf: date),
    );
    final prevShareholdingFuture = timed(
      'prevShareholding',
      _db.getShareholdingsBeforeDateBatch(
        candidates,
        beforeDate: date.subtract(
          const Duration(
            days: InstitutionalParams.foreignShareholdingLookbackDays,
          ),
        ),
      ),
    );
    final symbolMarketsFuture = timed(
      'symbolMarkets',
      _db.getMarketsForSymbolsBatch(candidates),
    );
    final warningFuture = timed(
      'warning',
      _db.getActiveWarningsMapBatch(candidates),
    );
    final insiderFuture = timed(
      'insider',
      _db.getLatestInsiderHoldingsBatch(candidates, asOf: date),
    );
    final epsFuture = timed('eps', _db.getEPSHistoryBatch(candidates));
    final roeFuture = timed('roe', _db.getROEHistoryBatch(candidates));
    final dividendFuture = timed(
      'dividend',
      _db.getDividendHistoryBatch(candidates),
    );
    final maxRevenueFuture = timed(
      'maxRevenue',
      _db.getMaxRevenueBatch(candidates),
    );

    // 型別安全的並行等待（Dart 3 Record 解構）
    final (rawPricesMap, newsMap, rawInstitutionalMap) = await (
      pricesFuture,
      newsFuture,
      instFuture,
    ).wait;

    // 只用最後一個**價格水位斷點**之後的歷史（2026-08-30 稽核 C3）。
    //
    // `daily_price` 存交易所原始收盤價、**未還原除權息／減資／分割**，跨越
    // 位移的長窗指標會產出物理上不可能的值：5904 寶雅 2026-08-27 的
    // `daily_reason` 存著 `ma60: 506.18`，而當天股價 74.10。實測 2026-08-28
    // 有 14 檔「當日有落庫評分、且 MA60 窗內含斷點」——其中 2603 長榮在自選
    // 清單裡，當天以 `ma60: 209.79`（跨 6/17 除息 −12.0% 缺口）觸發
    // `PULLBACK_TO_MA20` 的 +15 分買進訊號。
    //
    // **這是評分鏈的單一入口**：`ScoringBatchData.pricesMap` 同時餵給
    // isolate 路徑與主執行緒 fallback（守門見
    // `price_continuity_entry_guard_test.dart`）。刻意放在
    // `fillNoActivityDays` **之前**——那支以價格列為 ground truth 補法人淨額
    // 0 的日子，兩者必須看同一個區間。
    final pricesMap = {
      for (final e in rawPricesMap.entries) e.key: e.value.contiguousSuffix(),
    };

    // 截斷後歷史不足分析門檻的股票會由 `classifyCandidate` 以
    // insufficientData 擋下並計數，但那個計數混著「新上市」與「剛除權息」
    // 兩種成因。這裡單獨報告後者——實測自選清單 43 檔中僅 2603 有斷點且
    // 截斷後仍有 51 列（不受影響），但除息旺季會有股票落進「不足 21 根」
    // 的約一個月視窗，屆時卡片會少掉趨勢與評分，需要看得見。
    final truncated = <String, int>{};
    for (final e in rawPricesMap.entries) {
      final after = pricesMap[e.key]!.length;
      if (after < e.value.length) truncated[e.key] = after;
    }
    if (truncated.isNotEmpty) {
      final belowGate = truncated.entries
          .where((e) => e.value < RuleParams.swingWindow + 1)
          .map((e) => '${e.key}(${e.value})')
          .toList();
      AppLogger.info(
        'BatchDataLoader',
        '價格水位斷點：${truncated.length} 檔截斷歷史'
            '${belowGate.isEmpty ? '' : '，其中 ${belowGate.length} 檔因此不足分析門檻：'
                      '${belowGate.join(", ")}'}',
      );
    }

    // 交易所對「當日無法人進出」的股票不發列，缺列會被規則迴圈直接跳過、
    // 把不相鄰的兩天接成連續。以價格列為 ground truth 補回淨額 0 的日子，
    // 讓規則既有的門檻檢查自然中斷 streak（見 fillNoActivityDays）。
    final institutionalMap = BatchDataBuilder.fillNoActivityDays(
      rawInstitutionalMap,
      pricesMap,
    );
    final (
      revenueMap,
      valuationMap,
      revenueHistoryMap,
      dayTradingMap,
      shareholdingEntries,
    ) = await (
      revenueFuture,
      valuationFuture,
      revenueHistoryFuture,
      dayTradingFuture,
      shareholdingFuture,
    ).wait;
    final (
      prevShareholdingEntries,
      warningEntries,
      insiderEntries,
      epsHistoryMap,
      roeHistoryMap,
      dividendHistoryMap,
      maxHistoricalRevenueMap,
    ) = await (
      prevShareholdingFuture,
      warningFuture,
      insiderFuture,
      epsFuture,
      roeFuture,
      dividendFuture,
      maxRevenueFuture,
    ).wait;

    // 批次載入籌碼集中度（TDCC 股權分散表）
    final concentrationMap = _shareholdingRepo != null
        ? await timed(
            'concentration',
            _shareholdingRepo.getConcentrationRatioBatch(candidates),
          )
        : <String, double>{};

    final slowest = timings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    AppLogger.debug(
      'BatchDataLoader',
      '批次載入計時: total=${totalTimer.elapsedMilliseconds}ms, '
          '${slowest.map((e) => '${e.key}=${e.value}ms').join(', ')}',
    );

    // 轉換為 Isolate 可用的 Map 格式
    final shareholdingMap = BatchDataBuilder.buildShareholdingMap(
      shareholdingEntries,
      prevShareholdingEntries,
      concentrationMap,
      evaluationDate: date,
      symbolMarkets: await symbolMarketsFuture,
    );

    final warningMap = warningEntries.map(
      (k, v) => MapEntry(
        k,
        WarningDataContext(
          isAttention: v.warningType == 'ATTENTION',
          isDisposal: v.warningType == 'DISPOSAL',
          warningType: v.warningType,
          reasonDescription: v.reasonDescription,
          disposalMeasures: v.disposalMeasures,
          disposalEndDate: v.disposalEndDate,
        ),
      ),
    );

    final insiderMap = await BatchDataBuilder.buildInsiderMap(
      insiderEntries,
      candidates,
      _insiderRepo,
    );

    return ScoringBatchData.grouped(
      pricesMap: pricesMap,
      newsMap: newsMap,
      dayTradingMap: dayTradingMap,
      institutional: InstitutionalIntelligence(
        institutionalMap: institutionalMap,
        shareholdingMap: shareholdingMap,
        warningMap: warningMap,
        insiderMap: insiderMap,
      ),
      fundamental: FundamentalDataGroup(
        revenueMap: revenueMap,
        valuationMap: valuationMap,
        revenueHistoryMap: revenueHistoryMap,
        maxHistoricalRevenueMap: maxHistoricalRevenueMap,
      ),
      financialHealth: FinancialHealthGroup(
        epsHistoryMap: epsHistoryMap,
        roeHistoryMap: roeHistoryMap,
        dividendHistoryMap: dividendHistoryMap,
      ),
    );
  }
}

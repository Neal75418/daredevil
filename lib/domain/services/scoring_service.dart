import 'dart:convert';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:daredevil/domain/services/scoring_pipeline.dart';

/// 股票候選評分服務
///
/// 從 UpdateService 抽離以改善關注點分離
/// 處理：
/// - 對候選股票執行分析
/// - 套用規則引擎
/// - 計算分數
/// - 儲存分析結果
class ScoringService {
  const ScoringService({
    required AnalysisService analysisService,
    required RuleEngine ruleEngine,
    required IAnalysisRepository analysisRepository,
  }) : _analysisService = analysisService,
       _ruleEngine = ruleEngine,
       _analysisRepo = analysisRepository;

  final AnalysisService _analysisService;
  final RuleEngine _ruleEngine;
  final IAnalysisRepository _analysisRepo;

  /// 對股票候選清單評分
  ///
  /// 使用預先載入的批次資料以避免 N+1 查詢問題
  /// 回傳依分數由高至低排序的 [ScoredStock] 清單
  Future<List<ScoredStock>> scoreStocks({
    required List<String> candidates,
    required DateTime date,
    required ScoringBatchData batchData,
    Future<MarketDataContext?> Function(String)? marketDataBuilder,
    void Function(int current, int total)? onProgress,
    List<String> watchlistSymbols = const [],
  }) async {
    if (candidates.isEmpty) return [];

    final scoredStocks = <ScoredStock>[];
    final instMap =
        batchData.institutionalMap ?? <String, List<DailyInstitutionalEntry>>{};

    // Dual-horizon: 從 registry 抓 calibrated context。
    // Pre-launch placeholder JSON 為空 → 兩 horizon 都走 fallback。
    final calibratedScores = CalibratedScoresRegistry.instance
        .snapshotForIsolate();

    // 大盤 regime（供回檔類規則 gate）：候選池 120 交易日平均報酬。
    // 有效股 < 50（fresh DB / 歷史不足）視為未知 → null、規則不擋。
    final marketUptrend = PriceCalculator.marketUptrendOrNull(
      batchData.pricesMap,
      SectorParams.regimeLookbackDays,
      // 只用當日 bar：半市場日不得把昨日的另一半混進 regime 平均
      asOf: date,
    );

    // 暫存待寫入的分析結果，於迴圈後以單一 transaction 批次寫入
    final pendingPersists =
        <
          ({
            String symbol,
            String trendState,
            String reversalState,
            double? supportLevel,
            double? resistanceLevel,
            double scoreShort,
            double scoreLong,
            List<ReasonData> reasons,
          })
        >[];

    // 使用預載資料處理每個候選
    var skippedNoData = 0;
    var skippedInsufficientData = 0;
    var skippedLowLiquidity = 0;
    var skippedStaleBar = 0;
    var skippedNoAnalysis = 0;
    var skippedNoReasons = 0;
    var skippedLowScore = 0;
    var stocksWithSufficientData = 0;
    final watchlistSet = watchlistSymbols.toSet();

    for (var i = 0; i < candidates.length; i++) {
      final symbol = candidates[i];
      onProgress?.call(i + 1, candidates.length);

      // 資格檢查（共用 pipeline，與 isolate 路徑同一實作）
      final prices = batchData.pricesMap[symbol];
      final skipReason = classifyCandidate(
        prices,
        asOf: date,
        // 與 isolate 路徑逐字對應
        exemptFromLiquidity: watchlistSet.contains(symbol),
      );
      if (skipReason != null) {
        switch (skipReason) {
          case CandidateSkipReason.noData:
            skippedNoData++;
          case CandidateSkipReason.insufficientData:
            skippedInsufficientData++;
          case CandidateSkipReason.lowLiquidity:
            skippedLowLiquidity++;
          case CandidateSkipReason.staleBar:
            skippedStaleBar++;
        }
        continue;
      }
      prices!;
      stocksWithSufficientData++;
      // classifyCandidate 通過保證 close/volume 非 null
      final latest = prices.last;
      final turnover = latest.close! * latest.volume!;

      // 執行分析
      // 回 null 屬異常（資格檢查已保證資料量），必須計數避免無聲消失。
      //
      // ⚠️ **目前不可達**：`analyzeStock` 唯一的 null 路徑是
      // `priceHistory.length < RuleParams.swingWindow`
      // （analysis_coordinator_service.dart:44），而 `classifyCandidate`
      // 上游已用**同一個常數**檢查過（scoring_pipeline.dart:27）。故此計數器
      // 是 defense-in-depth：若日後有人調整任一側門檻、或 analyzeStock 新增
      // 別的 null 路徑，這裡是唯一的偵測手段。不可達也代表**無法從公開 API
      // 建構觸發情境**，計數器語意改由 DTO 層測試把關。
      final analysisResult = _analysisService.analyzeStock(prices);
      if (analysisResult == null) {
        skippedNoAnalysis++;
        continue;
      }

      // 為第 4 階段訊號建立市場資料上下文（可選）
      MarketDataContext? marketData;
      if (marketDataBuilder != null) {
        marketData = await marketDataBuilder(symbol);
      }

      // 為規則引擎建立上下文
      final context = _analysisService.buildContext(
        analysisResult,
        priceHistory: prices,
        marketData: marketData,
        evaluationTime: date,
        isMarketUptrend: marketUptrend,
      );

      // 從批次載入的 map 取得可選資料
      final institutionalHistory = instMap[symbol];
      final recentNews = batchData.newsMap[symbol];

      // 執行規則引擎
      final stockData = StockData(
        symbol: symbol,
        prices: prices,
        institutional: institutionalHistory,
        news: recentNews,
        latestRevenue: batchData.revenueMap?[symbol],
        latestValuation: batchData.valuationMap?[symbol],
        revenueHistory: batchData.revenueHistoryMap?[symbol],
        epsHistory: batchData.epsHistoryMap?[symbol],
        roeHistory: batchData.roeHistoryMap?[symbol],
        dividendHistory: batchData.dividendHistoryMap?[symbol],
        maxHistoricalRevenue: batchData.maxHistoricalRevenueMap?[symbol],
      );
      final reasons = _ruleEngine.evaluateStock(context, stockData);

      // 無訊號是正常結果，但仍須計數讓帳目平。
      //
      // 例外：自選股即使零訊號也要落庫（與 isolate 路徑逐字對應，見
      // [ScoringIsolateInput.watchlistSymbols]）。**刻意不進 scoredStocks**
      // ——那份清單的語意是「有訊號、有分數的股票」，補這一列是為了畫面不
      // 空白，不是為了讓它出現在排行裡。
      if (reasons.isEmpty) {
        if (!watchlistSet.contains(symbol)) {
          skippedNoReasons++;
          continue;
        }
        pendingPersists.add((
          symbol: symbol,
          trendState: analysisResult.trendState.code,
          reversalState: analysisResult.reversalState.code,
          supportLevel: analysisResult.supportLevel,
          resistanceLevel: analysisResult.resistanceLevel,
          scoreShort: 0.0,
          scoreLong: 0.0,
          reasons: const <ReasonData>[],
        ));
        continue;
      }

      // 雙 horizon 評分核心（共用 pipeline，與 isolate 路徑同一實作）
      final scored = scoreReasonsDualHorizon(
        ruleEngine: _ruleEngine,
        reasons: reasons,
        calibratedScores: calibratedScores,
      );
      if (scored == null) {
        // 分數低於觀察門檻的自選股也要落庫(與 isolate 路徑逐字對應,
        // 理由見該處)。同樣不進 scoredStocks——「評分 N 檔」語意不變。
        if (!watchlistSet.contains(symbol)) {
          skippedLowScore++;
          continue;
        }
        pendingPersists.add((
          symbol: symbol,
          trendState: analysisResult.trendState.code,
          reversalState: analysisResult.reversalState.code,
          supportLevel: analysisResult.supportLevel,
          resistanceLevel: analysisResult.resistanceLevel,
          scoreShort: 0.0,
          scoreLong: 0.0,
          reasons: const <ReasonData>[],
        ));
        continue;
      }
      final (:scoreShort, :scoreLong, :topReasons, :decayMultipliers) = scored;

      // 轉換為 dual-horizon ReasonData（每條 rule 都查兩個 horizon 的分數；
      // 乘上基本面遞減係數 — 保持「總分 = reasons 加總」invariant，
      // UI 顯示的即該訊號實際貢獻）
      final reasonDataList = topReasons.map((r) {
        final code = r.type.code;
        final multiplier = decayMultipliers[code] ?? 1.0;
        return ReasonData(
          type: code,
          evidenceJson: r.evidenceJson != null
              ? jsonEncode(r.evidenceJson)
              : '{}',
          scoreShort:
              ((calibratedScores.lookup(Horizon.short, code) ?? r.score) *
                      multiplier)
                  .round(),
          scoreLong:
              ((calibratedScores.lookup(Horizon.long, code) ?? r.score) *
                      multiplier)
                  .round(),
        );
      }).toList();

      pendingPersists.add((
        symbol: symbol,
        trendState: analysisResult.trendState.code,
        reversalState: analysisResult.reversalState.code,
        supportLevel: analysisResult.supportLevel,
        resistanceLevel: analysisResult.resistanceLevel,
        scoreShort: scoreShort.toDouble(),
        scoreLong: scoreLong.toDouble(),
        reasons: reasonDataList,
      ));

      scoredStocks.add(
        ScoredStock(
          symbol: symbol,
          scoreShort: scoreShort,
          scoreLong: scoreLong,
          turnover: turnover,
        ),
      );
    }

    // 批次寫入（單一 transaction，與 Isolate 路徑對齊）。
    // 清除當日舊資料必須與寫入同一 transaction：先清後寫若跨 transaction，
    // 評分中斷（OS 殺程序、isolate 失敗）會留下當日分析真空。
    await _analysisRepo.runInTransaction(() async {
      await _analysisRepo.clearReasonsForDate(date);
      await _analysisRepo.clearAnalysisForDate(date);
      for (final p in pendingPersists) {
        await _persistAnalysisResult(
          symbol: p.symbol,
          date: date,
          trendState: p.trendState,
          reversalState: p.reversalState,
          supportLevel: p.supportLevel,
          resistanceLevel: p.resistanceLevel,
          scoreShort: p.scoreShort,
          scoreLong: p.scoreLong,
          reasons: p.reasons,
        );
      }
    });

    AppLogger.debug(
      'ScoringService',
      '候選 ${candidates.length} 檔，資料充足 $stocksWithSufficientData 檔',
    );

    // 記錄分析統計
    _logScoringResults(
      scoredStocks,
      skippedNoData,
      skippedInsufficientData,
      skippedLowLiquidity,
      skippedStaleBar,
      skippedNoAnalysis,
      skippedNoReasons,
      skippedLowScore,
      candidateCount: candidates.length,
    );

    // 依流動性加權分數（短線 horizon）排序
    //
    // 回傳一個穩定的 short-sorted 預設清單給 caller；caller 若需要 long
    // 版本的排序自行重排即可。
    scoredStocks.sort(ScoredStock.compareByWeightedScoreFor(Horizon.short));

    return scoredStocks;
  }

  /// 在背景 Isolate 中對股票候選清單評分
  ///
  /// 此方法將運算移至背景執行緒，避免阻塞 UI。
  /// 使用預先載入的 dayTradingMap 支援當沖相關規則。
  ///
  /// 適用於：批量掃描、每日更新等場景
  Future<List<ScoredStock>> scoreStocksInIsolate({
    required List<String> candidates,
    required DateTime date,
    required ScoringBatchData batchData,
    List<String> watchlistSymbols = const [],
  }) async {
    if (candidates.isEmpty) return [];

    // 記錄價格資料統計
    _logCandidateStats(candidates, batchData.pricesMap, suffix: ' (Isolate)');

    // Dual-horizon: 快照 calibrated context 塞進 input，
    // 讓 scoring isolate 內不需要存取 main-isolate 的 registry singleton。
    final calibratedScores = CalibratedScoresRegistry.instance
        .snapshotForIsolate();

    // 直接傳入 typed DTO
    final input = ScoringIsolateInput(
      candidates: candidates,
      pricesMap: batchData.pricesMap,
      newsMap: batchData.newsMap,
      institutionalMap:
          batchData.institutionalMap ??
          <String, List<DailyInstitutionalEntry>>{},
      revenueMap: batchData.revenueMap,
      valuationMap: batchData.valuationMap,
      revenueHistoryMap: batchData.revenueHistoryMap,
      date: date,
      dayTradingMap: batchData.dayTradingMap,
      shareholdingMap: batchData.shareholdingMap,
      warningMap: batchData.warningMap,
      insiderMap: batchData.insiderMap,
      epsHistoryMap: batchData.epsHistoryMap,
      roeHistoryMap: batchData.roeHistoryMap,
      dividendHistoryMap: batchData.dividendHistoryMap,
      maxHistoricalRevenueMap: batchData.maxHistoricalRevenueMap,
      calibratedScores: calibratedScores,
      watchlistSymbols: watchlistSymbols,
    );

    // 在背景 Isolate 執行運算（含回退機制）
    ScoringBatchResult result;
    try {
      result = await evaluateStocksInIsolate(input);
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.warning(
        'ScoringService',
        'Isolate 執行失敗，回退至主執行緒',
        e,
        stackTrace,
      );

      // 回退：在主執行緒執行評分，並傳入 marketDataBuilder 以確保市場資料一致性
      return await scoreStocks(
        candidates: candidates,
        date: date,
        batchData: batchData,
        // 回退路徑也必須帶上——漏了這行,isolate 失敗那天自選股就悄悄少了
        // 分析列,而三個訊號(exit code、update_run、日誌)全都正常
        watchlistSymbols: watchlistSymbols,
        marketDataBuilder: (symbol) async {
          return _buildMarketDataFromMaps(
            symbol: symbol,
            dayTradingMap: batchData.dayTradingMap,
            shareholdingMap: batchData.shareholdingMap,
            warningMap: batchData.warningMap,
            insiderMap: batchData.insiderMap,
          );
        },
      );
    }

    // 記錄分析統計
    _logScoringResultsFromIsolate(result);

    // 批次儲存分析結果（單一 transaction 減少 I/O）。
    // 清除當日舊資料必須與寫入同一 transaction（與主執行緒路徑對齊），
    // 避免評分中斷留下當日分析真空。
    await _analysisRepo.runInTransaction(() async {
      await _analysisRepo.clearReasonsForDate(date);
      await _analysisRepo.clearAnalysisForDate(date);
      for (final output in result.outputs) {
        final reasonDataList = output.reasons
            .map(
              (r) => ReasonData(
                type: r.type,
                evidenceJson: r.evidenceJson,
                scoreShort: r.scoreShort,
                scoreLong: r.scoreLong,
              ),
            )
            .toList();

        await _persistAnalysisResult(
          symbol: output.symbol,
          date: date,
          trendState: output.trendState,
          reversalState: output.reversalState,
          supportLevel: output.supportLevel,
          resistanceLevel: output.resistanceLevel,
          scoreShort: output.scoreShort.toDouble(),
          scoreLong: output.scoreLong.toDouble(),
          reasons: reasonDataList,
        );
      }
    });

    // 轉換為 ScoredStock 並排序（短線 horizon 當預設）
    // 零訊號的自選股只補分析列,不列入「評分 N 檔」——那份清單的語意是
    // 「有訊號、有分數的股票」(與主執行緒路徑對應)
    final scoredStocks = result.outputs
        .where((o) => o.reasons.isNotEmpty)
        .map(
          (o) => ScoredStock(
            symbol: o.symbol,
            scoreShort: o.scoreShort,
            scoreLong: o.scoreLong,
            turnover: o.turnover,
          ),
        )
        .toList();

    scoredStocks.sort(ScoredStock.compareByWeightedScoreFor(Horizon.short));

    return scoredStocks;
  }

  // ==================================================
  // 日誌輔助方法
  // ==================================================

  /// 記錄候選股票的價格資料統計
  void _logCandidateStats(
    List<String> candidates,
    Map<String, List<DailyPriceEntry>> pricesMap, {
    String suffix = '',
  }) {
    var stocksWithSufficientData = 0;
    for (final symbol in candidates) {
      final prices = pricesMap[symbol];
      if (prices != null && prices.length >= RuleParams.swingWindow) {
        stocksWithSufficientData++;
      }
    }
    AppLogger.debug(
      'ScoringService',
      '候選 ${candidates.length} 檔，資料充足 $stocksWithSufficientData 檔$suffix',
    );
  }

  /// 記錄主執行緒評分結果統計
  ///
  /// log 顯示短線 horizon 最高分當代表值（UI horizon 切換後
  /// 可改為顯示兩個 horizon 的最高分）。
  void _logScoringResults(
    List<ScoredStock> scored,
    int skippedNoData,
    int skippedInsufficient,
    int skippedLiquidity,
    int skippedStaleBar,
    int skippedNoAnalysis,
    int skippedNoReasons,
    int skippedLowScore, {
    required int candidateCount,
    String suffix = '',
  }) {
    final maxScoreShort = scored.isEmpty
        ? 0
        : scored.map((s) => s.scoreShort).reduce((a, b) => a > b ? a : b);
    final skippedTotal =
        skippedNoData +
        skippedInsufficient +
        skippedLiquidity +
        skippedStaleBar +
        skippedNoAnalysis +
        skippedNoReasons +
        skippedLowScore;
    AppLogger.info(
      'ScoringService',
      '評分完成: ${scored.length} 檔 (short max $maxScoreShort 分), '
          '跳過 $skippedTotal 檔 '
          '(無資料 $skippedNoData, 資料不足 $skippedInsufficient, '
          '低流動 $skippedLiquidity, 非當日 bar $skippedStaleBar, '
          '無訊號 $skippedNoReasons, 分數不足 $skippedLowScore)$suffix',
    );

    // 與 isolate 路徑同一診斷契約（見 _logScoringResultsFromIsolate）
    if (skippedNoAnalysis > 0) {
      AppLogger.warning(
        'ScoringService',
        '技術分析失敗 $skippedNoAnalysis 檔（資格檢查已過仍回 null，'
            '可能為價格資料異常）',
      );
    }
    if (scored.length + skippedTotal != candidateCount) {
      AppLogger.warning(
        'ScoringService',
        '評分帳目不平: 候選 $candidateCount != 輸出 ${scored.length} + '
            '跳過 $skippedTotal（有候選股未被分類，請檢查是否新增未計數分支）',
      );
    }
  }

  /// 記錄 Isolate 評分結果統計
  void _logScoringResultsFromIsolate(ScoringBatchResult result) {
    final maxShort = result.outputs.isEmpty
        ? 0
        : result.outputs
              .map((o) => o.scoreShort)
              .reduce((a, b) => a > b ? a : b);
    AppLogger.info(
      'ScoringService',
      '評分完成: ${result.outputs.length} 檔 (short max $maxShort 分), '
          '跳過 ${result.skippedTotal} 檔 '
          '(無資料 ${result.skippedNoData}, 資料不足 '
          '${result.skippedInsufficientData}, 低流動 '
          '${result.skippedLowLiquidity}, 非當日 bar '
          '${result.skippedStaleBar}, 無訊號 ${result.skippedNoReasons}, '
          '分數不足 ${result.skippedLowScore}) (Isolate)',
    );

    // 技術分析回 null 屬異常路徑：資格檢查已保證資料量，仍失敗代表資料有問題。
    // 過去此路徑無聲 continue，股票在帳目上消失且無跡可循。
    if (result.skippedNoAnalysis > 0) {
      AppLogger.warning(
        'ScoringService',
        '技術分析失敗 ${result.skippedNoAnalysis} 檔（資格檢查已過仍回 null，'
            '可能為價格資料異常）',
      );
    }

    // 帳目不平＝有候選股未被任何分類認領，屬程式缺陷而非資料問題
    if (!result.accountingBalances) {
      AppLogger.warning(
        'ScoringService',
        '評分帳目不平: 候選 ${result.candidateCount} != 輸出 '
            '${result.outputs.length} + 跳過 ${result.skippedTotal}'
            '（有候選股未被分類，請檢查 scoring_isolate 是否新增未計數分支）',
      );
    }
    // 反序列化失敗在 M8 fix 後直接 throw FormatException，scoring 整批 abort，
    // 不再 silent skip — 改在 try/catch 處 surface 給 UI / Sentry。
  }

  // ==================================================
  // 資料儲存輔助方法
  // ==================================================

  /// 儲存股票分析結果與觸發原因
  ///
  /// 統一 [scoreStocks] 和 [scoreStocksInIsolate] 的儲存邏輯。
  /// Dual-horizon：pipeline 已經產生 `scoreShort` 與 `scoreLong`，
  /// 這裡直接把兩值寫入 DB。
  Future<void> _persistAnalysisResult({
    required String symbol,
    required DateTime date,
    required String trendState,
    required String reversalState,
    required double? supportLevel,
    required double? resistanceLevel,
    required double scoreShort,
    required double scoreLong,
    required List<ReasonData> reasons,
  }) async {
    await _analysisRepo.saveAnalysis(
      symbol: symbol,
      date: date,
      trendState: trendState,
      reversalState: reversalState,
      supportLevel: supportLevel,
      resistanceLevel: resistanceLevel,
      scoreShort: scoreShort,
      scoreLong: scoreLong,
    );
    await _analysisRepo.saveReasons(symbol, date, reasons);
  }

  // ==================================================
  // 市場資料建構輔助方法（Isolate 回退時使用）
  // ==================================================

  /// 從 typed DTO 建構 MarketDataContext
  ///
  /// 用於 Isolate 回退時，確保市場資料一致性
  MarketDataContext? _buildMarketDataFromMaps({
    required String symbol,
    Map<String, double>? dayTradingMap,
    Map<String, ShareholdingData>? shareholdingMap,
    Map<String, WarningDataContext>? warningMap,
    Map<String, InsiderDataContext>? insiderMap,
  }) {
    return MarketDataContext.fromComponents(
      dayTradingRatio: dayTradingMap?[symbol],
      shareholding: shareholdingMap?[symbol],
      warning: warningMap?[symbol],
      insider: insiderMap?[symbol],
    );
  }
}

/// 已計算分數的股票
///
/// Dual-horizon: 每支股票同時攜帶短線與長線分數，供 3-mode tab 的雙 score 顯示。
/// （pre-2026-06-21：曾由已退役的 daily_recommendation 產生流程依 horizon 各取 Top N。）
class ScoredStock {
  const ScoredStock({
    required this.symbol,
    required this.scoreShort,
    required this.scoreLong,
    required this.turnover,
  });

  final String symbol;
  final int scoreShort;
  final int scoreLong;
  final double turnover;

  /// 依流動性加權分數排序的比較函數（horizon-aware）
  ///
  /// 取代靜態 `compareByWeightedScore`。呼叫端指定要用哪個
  /// horizon 的分數當主鍵，例如：
  ///
  /// ```dart
  /// stocks.sort(ScoredStock.compareByWeightedScoreFor(Horizon.short));
  /// ```
  ///
  /// 策略：基礎分數 + 流動性加成
  /// 流動性加成：每 1 億成交金額 +2 分（上限 20 分）
  /// 這使高成交量股票（10 億成交、60 分）能與低成交量股票（3000 萬成交、80 分）競爭
  ///
  /// 排序優先順序：
  /// 1. 主要：所選 horizon 的分數 + 流動性加成（由高至低）
  /// 2. 次要：成交金額（由高至低）
  /// 3. 第三：股票代碼（由低至高，確保 deterministic）
  static int Function(ScoredStock, ScoredStock) compareByWeightedScoreFor(
    Horizon horizon,
  ) {
    return (a, b) {
      final scoreA = horizon == Horizon.short ? a.scoreShort : a.scoreLong;
      final scoreB = horizon == Horizon.short ? b.scoreShort : b.scoreLong;

      // 全部乘以 100 轉整數比較，完全消除浮點精度問題
      final totalA = scoreA * 100 + _liquidityBonus100(a.turnover);
      final totalB = scoreB * 100 + _liquidityBonus100(b.turnover);

      final scoreCmp = totalB.compareTo(totalA);
      if (scoreCmp != 0) return scoreCmp;

      final turnoverCmp = b.turnover.compareTo(a.turnover);
      if (turnoverCmp != 0) return turnoverCmp;

      return a.symbol.compareTo(b.symbol);
    };
  }

  /// 計算流動性加成（放大 100 倍取整數）
  static int _liquidityBonus100(double turnover) {
    final raw =
        (turnover /
                RuleParams.liquidityTurnoverUnit *
                RuleParams.liquidityBonusPerUnit *
                100)
            .round();
    final max = (RuleParams.liquidityBonusMax * 100).toInt();
    return raw > max ? max : raw;
  }
}

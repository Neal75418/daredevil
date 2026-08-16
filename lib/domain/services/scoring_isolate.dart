import 'dart:convert';
import 'dart:isolate';

// meta 而非 flutter/foundation:本檔在 CLI 的 import 閉包內,不可引入 dart:ui
import 'package:meta/meta.dart' show visibleForTesting;

import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params_sector.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/isolate_map_extensions.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/scoring_pipeline.dart';

/// Isolate 評分輸入資料
///
/// 包含評分所需的所有批次載入資料
class ScoringIsolateInput {
  const ScoringIsolateInput({
    required this.candidates,
    required this.pricesMap,
    required this.newsMap,
    required this.institutionalMap,
    this.revenueMap,
    this.valuationMap,
    this.revenueHistoryMap,
    this.date,
    this.dayTradingMap,
    this.shareholdingMap,
    this.warningMap,
    this.insiderMap,
    this.epsHistoryMap,
    this.roeHistoryMap,
    this.dividendHistoryMap,
    this.maxHistoricalRevenueMap,
    this.calibratedScores = CalibratedScoreContext.empty,
    this.watchlistSymbols = const [],
  });

  final List<String> candidates;
  final Map<String, List<DailyPriceEntry>> pricesMap;
  final Map<String, List<NewsItemEntry>> newsMap;
  final Map<String, List<DailyInstitutionalEntry>> institutionalMap;
  final Map<String, MonthlyRevenueEntry>? revenueMap;
  final Map<String, StockValuationEntry>? valuationMap;
  final Map<String, List<MonthlyRevenueEntry>>? revenueHistoryMap;

  /// 評估目標日期（供規則判斷資料新鮮度）
  final DateTime? date;

  /// 當沖資料 Map（symbol -> dayTradingRatio）
  final Map<String, double>? dayTradingMap;

  /// 外資持股資料（symbol → 持股資料）
  final Map<String, ShareholdingData>? shareholdingMap;

  /// 警示資料（symbol → 警示上下文）
  final Map<String, WarningDataContext>? warningMap;

  /// 董監持股資料（symbol → 董監上下文）
  final Map<String, InsiderDataContext>? insiderMap;

  /// EPS 歷史資料 Map（symbol -> 最近 8 季 EPS，降序）
  final Map<String, List<FinancialDataEntry>>? epsHistoryMap;

  /// ROE 歷史資料 Map（symbol -> 最近 8 季 ROE，降序）
  final Map<String, List<FinancialDataEntry>>? roeHistoryMap;

  /// 股利歷史資料 Map（symbol -> 歷年股利，降序）
  final Map<String, List<DividendHistoryEntry>>? dividendHistoryMap;

  /// 歷史最高月營收 Map（symbol -> maxRevenue）
  final Map<String, double>? maxHistoricalRevenueMap;

  /// Calibrated scores for both horizons
  ///
  /// 主 isolate 從 `CalibratedScoresRegistry.instance.snapshotForIsolate()`
  /// 取出後塞入此欄位，scoring isolate 在 `calculateScore` 中查詢。
  /// 預設為 [CalibratedScoreContext.empty]，查詢都會回 null，fallback 到
  /// `TriggeredReason.score`（Stage 5a 等效行為）。
  final CalibratedScoreContext calibratedScores;

  /// 使用者自選股——**即使當日零訊號也要留下 `daily_analysis` 列**
  ///
  /// 為什麼特殊對待：自選股在畫面上一定看得到那張卡，沒有分析列就整張空白
  /// （無評分、無標籤、無趨勢箭頭），使用者分不出「今日沒訊號」與「壞掉／
  /// 沒被分析」。實機：2059 川湖 8/11 起零訊號，卡片連續四天全空，而資料量
  /// 與有分析的對照組 3081 完全相同。
  ///
  /// 為什麼不對全市場開放：候選股是全市場可分析且流動的股票（見
  /// `CandidateSelector` 步驟 4），全開會多寫上千列／日；自選股是 ≤36 檔。
  /// 與該檔步驟 1「自選清單優先、豁免流動性過濾——使用者主動追蹤」同一原則。
  final List<String> watchlistSymbols;

  Map<String, dynamic> toMap() => {
    'candidates': candidates,
    'pricesMap': pricesMap.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'newsMap': newsMap.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'institutionalMap': institutionalMap.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'revenueMap': revenueMap?.map((k, v) => MapEntry(k, v.toIsolateMap())),
    'valuationMap': valuationMap?.map((k, v) => MapEntry(k, v.toIsolateMap())),
    'revenueHistoryMap': revenueHistoryMap?.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'date': date?.millisecondsSinceEpoch,
    'dayTradingMap': dayTradingMap,
    'shareholdingMap': shareholdingMap?.map((k, v) => MapEntry(k, v.toMap())),
    'warningMap': warningMap?.map((k, v) => MapEntry(k, v.toMap())),
    'insiderMap': insiderMap?.map((k, v) => MapEntry(k, v.toMap())),
    'epsHistoryMap': epsHistoryMap?.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'roeHistoryMap': roeHistoryMap?.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'dividendHistoryMap': dividendHistoryMap?.map(
      (k, v) => MapEntry(k, v.map((e) => e.toIsolateMap()).toList()),
    ),
    'maxHistoricalRevenueMap': maxHistoricalRevenueMap,
    'calibratedScores': calibratedScores.toMap(),
    'watchlistSymbols': watchlistSymbols,
  };

  factory ScoringIsolateInput.fromMap(Map<String, dynamic> map) {
    return ScoringIsolateInput(
      candidates: List<String>.from(map['candidates']),
      pricesMap: _deserializeListMap(
        map,
        'pricesMap',
        IsolateMappers.dailyPrice,
      ),
      newsMap: _deserializeListMap(map, 'newsMap', IsolateMappers.newsItem),
      institutionalMap: _deserializeListMap(
        map,
        'institutionalMap',
        IsolateMappers.dailyInstitutional,
      ),
      revenueMap: _deserializeSingleMap(
        map,
        'revenueMap',
        IsolateMappers.monthlyRevenue,
      ),
      valuationMap: _deserializeSingleMap(
        map,
        'valuationMap',
        IsolateMappers.stockValuation,
      ),
      revenueHistoryMap: _deserializeListMap<MonthlyRevenueEntry>(
        map,
        'revenueHistoryMap',
        IsolateMappers.monthlyRevenue,
      ).ifEmpty(null),
      date: map['date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['date'] as int)
          : null,
      dayTradingMap: map['dayTradingMap'] != null
          ? Map<String, double>.from(map['dayTradingMap'])
          : null,
      shareholdingMap: map['shareholdingMap'] != null
          ? _castTypedMap(
              map['shareholdingMap'],
              (m) => ShareholdingData.fromMap(m),
            )
          : null,
      warningMap: map['warningMap'] != null
          ? _castTypedMap(
              map['warningMap'],
              (m) => WarningDataContext.fromMap(m),
            )
          : null,
      insiderMap: map['insiderMap'] != null
          ? _castTypedMap(
              map['insiderMap'],
              (m) => InsiderDataContext.fromMap(m),
            )
          : null,
      epsHistoryMap: _deserializeListMap<FinancialDataEntry>(
        map,
        'epsHistoryMap',
        IsolateMappers.financialData,
      ).ifEmpty(null),
      roeHistoryMap: _deserializeListMap<FinancialDataEntry>(
        map,
        'roeHistoryMap',
        IsolateMappers.financialData,
      ).ifEmpty(null),
      dividendHistoryMap: _deserializeListMap<DividendHistoryEntry>(
        map,
        'dividendHistoryMap',
        IsolateMappers.dividendHistory,
      ).ifEmpty(null),
      maxHistoricalRevenueMap: map['maxHistoricalRevenueMap'] != null
          ? Map<String, double>.from(map['maxHistoricalRevenueMap'])
          : null,
      calibratedScores: map['calibratedScores'] != null
          ? CalibratedScoreContext.fromMap(
              Map<String, dynamic>.from(map['calibratedScores'] as Map),
            )
          : CalibratedScoreContext.empty,
      // 缺鍵時降級為「無自選股」而非爆炸——與 calibratedScores 同策略
      watchlistSymbols: map['watchlistSymbols'] != null
          ? List<String>.from(map['watchlistSymbols'] as List)
          : const [],
    );
  }

  /// Isolate 邊界反序列化：symbol → typed List
  ///
  /// Isolate 傳輸會遺失泛型資訊，需逐層手動轉型後透過 [mapper] 建立 typed DTO。
  ///
  /// **Fail-loud（M8 fix）**：per-entry mapper 拋例外時直接 wrap 成
  /// [FormatException] 上拋。之前的 silent counter 會讓 schema drift 時
  /// scoring isolate 收到漏 stock 的 input 但無 warning，使用者看到
  /// 短少推薦無從追責。fail-loud 後寧可整批 abort 也不要靜默漏資料。
  /// 若 [map] 中 key 不存在或為 null，回傳空 Map。
  static Map<String, List<T>> _deserializeListMap<T>(
    Map<String, dynamic> map,
    String key,
    T Function(Map<String, dynamic>) mapper,
  ) {
    final raw = map[key];
    if (raw == null) return {};
    final result = <String, List<T>>{};
    for (final entry in (raw as Map).entries) {
      final list = <T>[];
      for (final item in entry.value as List) {
        try {
          list.add(mapper(Map<String, dynamic>.from(item as Map)));
        } catch (e) {
          throw FormatException(
            'Failed to deserialize entry in "$key" '
            '(symbol="${entry.key}"): $e',
          );
        }
      }
      result[entry.key.toString()] = list;
    }
    return result;
  }

  /// Isolate 邊界反序列化：symbol → T
  ///
  /// 同 [_deserializeListMap]：mapper fail 直接拋 [FormatException]。
  /// 若 [map] 中 key 不存在或為 null，回傳 null。
  static Map<String, T>? _deserializeSingleMap<T>(
    Map<String, dynamic> map,
    String key,
    T Function(Map<String, dynamic>) mapper,
  ) {
    final raw = map[key];
    if (raw == null) return null;
    final result = <String, T>{};
    for (final entry in (raw as Map).entries) {
      try {
        result[entry.key.toString()] = mapper(
          Map<String, dynamic>.from(entry.value as Map),
        );
      } catch (e) {
        throw FormatException(
          'Failed to deserialize entry in "$key" '
          '(symbol="${entry.key}"): $e',
        );
      }
    }
    return result;
  }

  /// Isolate 邊界型別轉換：symbol → typed DTO
  ///
  /// 同 [_deserializeListMap]：mapper fail 直接拋 [FormatException]。
  /// `map` 非 [Map] 時也拋（不再 fallback 空 Map silently）。
  static Map<String, T> _castTypedMap<T>(
    dynamic map,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    if (map is! Map) {
      throw FormatException(
        'Expected Map for typed cast, got ${map.runtimeType}',
      );
    }
    final result = <String, T>{};
    for (final entry in map.entries) {
      try {
        result[entry.key as String] = fromMap(
          Map<String, dynamic>.from(entry.value as Map),
        );
      } catch (e) {
        throw FormatException(
          'Failed to cast typed entry (symbol="${entry.key}"): $e',
        );
      }
    }
    return result;
  }
}

/// Isolate 通訊邊界的 reason 型別安全封裝
///
/// Dual-horizon: 攜帶兩個 horizon 的 per-rule 分數，供主 isolate
/// 寫入 `daily_reason.rule_score_short` / `rule_score_long`。
class IsolateReasonOutput {
  const IsolateReasonOutput({
    required this.type,
    required this.scoreShort,
    required this.scoreLong,
    required this.description,
    required this.evidenceJson,
  });

  final String type;
  final int scoreShort;
  final int scoreLong;
  final String description;
  final String evidenceJson;

  Map<String, dynamic> toMap() => {
    'type': type,
    'scoreShort': scoreShort,
    'scoreLong': scoreLong,
    'description': description,
    'evidenceJson': evidenceJson,
  };

  factory IsolateReasonOutput.fromMap(Map<String, dynamic> map) {
    return IsolateReasonOutput(
      type: map['type'] as String,
      scoreShort: map['scoreShort'] as int,
      scoreLong: map['scoreLong'] as int,
      description: map['description'] as String,
      evidenceJson: map['evidenceJson'] as String,
    );
  }
}

/// Isolate 評分輸出結果
///
/// Dual-horizon: 每支股票攜帶 short / long 兩個 horizon 的分數，供主 isolate
/// 寫入 `daily_analysis`（再依分數分層：訊號 / 觀察區）。
class ScoringIsolateOutput {
  const ScoringIsolateOutput({
    required this.symbol,
    required this.scoreShort,
    required this.scoreLong,
    required this.turnover,
    required this.trendState,
    required this.reversalState,
    this.supportLevel,
    this.resistanceLevel,
    required this.reasons,
  });

  final String symbol;
  final int scoreShort;
  final int scoreLong;
  final double turnover;
  final String trendState;
  final String reversalState;
  final double? supportLevel;
  final double? resistanceLevel;
  final List<IsolateReasonOutput> reasons;

  Map<String, dynamic> toMap() => {
    'symbol': symbol,
    'scoreShort': scoreShort,
    'scoreLong': scoreLong,
    'turnover': turnover,
    'trendState': trendState,
    'reversalState': reversalState,
    'supportLevel': supportLevel,
    'resistanceLevel': resistanceLevel,
    'reasons': reasons.map((r) => r.toMap()).toList(),
  };

  factory ScoringIsolateOutput.fromMap(Map<String, dynamic> map) {
    return ScoringIsolateOutput(
      symbol: map['symbol'] as String,
      scoreShort: map['scoreShort'] as int,
      scoreLong: map['scoreLong'] as int,
      turnover: map['turnover'] as double,
      trendState: map['trendState'] as String,
      reversalState: map['reversalState'] as String,
      supportLevel: map['supportLevel'] as double?,
      resistanceLevel: map['resistanceLevel'] as double?,
      reasons: (map['reasons'] as List)
          .map((e) => IsolateReasonOutput.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// 批次評分結果
///
/// **帳目不變量**：`outputs.length + skippedTotal == candidateCount`。
/// 每個候選股都必須有歸屬，不得無聲消失——否則「評分變少」時無從追查。
class ScoringBatchResult {
  const ScoringBatchResult({
    required this.outputs,
    required this.candidateCount,
    required this.skippedNoData,
    required this.skippedInsufficientData,
    required this.skippedLowLiquidity,
    this.skippedStaleBar = 0,
    required this.skippedNoAnalysis,
    required this.skippedNoReasons,
    required this.skippedLowScore,
  });

  final List<ScoringIsolateOutput> outputs;

  /// 進入評分的候選股總數（帳目分母）
  final int candidateCount;
  final int skippedNoData;
  final int skippedInsufficientData;
  final int skippedLowLiquidity;

  /// 最後一根 bar 不是評分日——DB 缺當日資料，不得拿昨日 K 棒算今日訊號
  final int skippedStaleBar;

  /// 技術分析回傳 null——異常路徑，非預期結果
  final int skippedNoAnalysis;

  /// 規則引擎未觸發任何訊號——正常結果（多數股票屬此類）
  final int skippedNoReasons;
  final int skippedLowScore;

  int get skippedTotal =>
      skippedNoData +
      skippedInsufficientData +
      skippedLowLiquidity +
      skippedStaleBar +
      skippedNoAnalysis +
      skippedNoReasons +
      skippedLowScore;

  /// 帳目是否平——false 代表有候選股未被任何分類認領（程式缺陷）
  bool get accountingBalances =>
      outputs.length + skippedTotal == candidateCount;

  Map<String, dynamic> toMap() => {
    'outputs': outputs.map((o) => o.toMap()).toList(),
    'candidateCount': candidateCount,
    'skippedNoData': skippedNoData,
    'skippedInsufficientData': skippedInsufficientData,
    'skippedLowLiquidity': skippedLowLiquidity,
    'skippedStaleBar': skippedStaleBar,
    'skippedNoAnalysis': skippedNoAnalysis,
    'skippedNoReasons': skippedNoReasons,
    'skippedLowScore': skippedLowScore,
  };

  factory ScoringBatchResult.fromMap(Map<String, dynamic> map) {
    return ScoringBatchResult(
      outputs: (map['outputs'] as List)
          .map(
            (e) => ScoringIsolateOutput.fromMap(Map<String, dynamic>.from(e)),
          )
          .toList(),
      // 新欄位對舊 map 容錯（跨版本 isolate payload）
      candidateCount: map['candidateCount'] as int? ?? 0,
      skippedNoData: map['skippedNoData'] as int,
      skippedInsufficientData: map['skippedInsufficientData'] as int,
      skippedLowLiquidity: map['skippedLowLiquidity'] as int,
      skippedStaleBar: map['skippedStaleBar'] as int? ?? 0,
      skippedNoAnalysis: map['skippedNoAnalysis'] as int? ?? 0,
      skippedNoReasons: map['skippedNoReasons'] as int? ?? 0,
      skippedLowScore: map['skippedLowScore'] as int,
    );
  }
}

/// 在背景 Isolate 中執行批量評分
///
/// 所有運算（分析、規則評估、分數計算）都在背景執行，
/// 不會阻塞 UI 執行緒
Future<ScoringBatchResult> evaluateStocksInIsolate(
  ScoringIsolateInput input,
) async {
  // static 是 **per-isolate** 的:主 isolate 設的 AppLogger.forceOutput 不會
  // 跟著過去,於是規則/評分裡所有 warning 與 error 在 AOT CLI 中完全沉默
  // ——那正是 2026-08-15 那個「運維可見性」修復想解決的問題,當時只修到
  // 主 isolate 那一半(2026-08-16 code review 發現)。closure 捕捉的值會被
  // 複製過去,所以在 isolate 內重設一次即可。
  final forceOutput = AppLogger.forceOutput;
  final resultMap = await Isolate.run(() {
    AppLogger.forceOutput = forceOutput;
    return evaluateStocksIsolated(input.toMap());
  });
  return ScoringBatchResult.fromMap(resultMap);
}

/// 在 Isolate 中執行的純運算函數
///
/// 此函數不能存取資料庫或 Provider，只能使用傳入的資料。
///
/// **公開給測試**：評分有此路徑與 [ScoringService.scoreStocks] 主執行緒
/// fallback 兩份實作，本專案有複本分岔的前科。直接呼叫這個純函數（不 spawn
/// isolate）才能用**同一份輸入**斷言兩條路徑結果相同——見
/// `scoring_watchlist_zero_reason_test.dart`。
@visibleForTesting
Map<String, dynamic> evaluateStocksIsolated(Map<String, dynamic> inputMap) {
  final input = ScoringIsolateInput.fromMap(inputMap);

  // 在 Isolate 中建立服務（它們是無狀態的）
  final analysisService = AnalysisService();
  final ruleEngine = RuleEngine();

  // 大盤 regime（供回檔類規則 gate）：與主執行緒路徑同一計算，
  // 對已跨界的 pricesMap 在 isolate 內算一次。有效股 < 50 → null 不擋。
  final marketUptrend = PriceCalculator.marketUptrendOrNull(
    input.pricesMap,
    SectorParams.regimeLookbackDays,
    // 只用當日 bar：半市場日不得把昨日的另一半混進 regime 平均
    asOf: input.date,
  );

  final outputs = <ScoringIsolateOutput>[];
  var skippedNoData = 0;
  var skippedInsufficientData = 0;
  var skippedLowLiquidity = 0;
  var skippedStaleBar = 0;
  var skippedNoAnalysis = 0;
  var skippedNoReasons = 0;
  var skippedLowScore = 0;
  final watchlist = input.watchlistSymbols.toSet();

  for (final symbol in input.candidates) {
    // 1-2. 資格檢查（共用 pipeline，與主執行緒路徑同一實作）
    final prices = input.pricesMap[symbol];
    // asOf 為 nullable：input.date 缺席時新鮮度檢查自動 no-op
    final skipReason = classifyCandidate(prices, asOf: input.date);
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
    // classifyCandidate 通過保證 close/volume 非 null
    final latest = prices.last;
    final turnover = latest.close! * latest.volume!;

    // 3. 技術分析
    // 回 null 屬異常（資格檢查已保證資料量），必須計數避免無聲消失。
    //
    // ⚠️ **目前不可達**：`analyzeStock` 唯一的 null 路徑是
    // `priceHistory.length < RuleParams.swingWindow`
    // （analysis_coordinator_service.dart:44），而 `classifyCandidate`
    // 上游已用**同一個常數**檢查過（scoring_pipeline.dart:27）。故此計數器
    // 是 defense-in-depth：若日後有人調整任一側門檻、或 analyzeStock 新增
    // 別的 null 路徑，這裡是唯一的偵測手段。不可達也代表**無法從公開 API
    // 建構觸發情境**，計數器語意改由 DTO 層測試把關。
    final analysisResult = analysisService.analyzeStock(prices);
    if (analysisResult == null) {
      skippedNoAnalysis++;
      continue;
    }

    // 4. 建立市場資料上下文
    final marketData = _buildMarketDataContext(input, symbol);

    // 5. 建立分析上下文
    // M13：evaluationTime 在 AnalysisContext 改 required；scoring caller
    // (scoring_service.scoreStocksInIsolate / scoreStocks) 都帶 required
    // DateTime 進來，input.date 不該為 null。若為 null 屬於 contract 違反、
    // fail-loud 比 silent DateTime.now() fallback 更安全。
    final inputDate = input.date;
    if (inputDate == null) {
      throw StateError(
        'ScoringIsolateInput.date must not be null when evaluating "$symbol"',
      );
    }
    final context = analysisService.buildContext(
      analysisResult,
      priceHistory: prices,
      marketData: marketData,
      evaluationTime: inputDate,
      isMarketUptrend: marketUptrend,
    );

    // 6. 轉換批次資料並執行規則引擎
    final batchData = _convertBatchData(input, symbol);
    final stockData = StockData(
      symbol: symbol,
      prices: prices,
      institutional: batchData.institutionalHistory,
      news: batchData.recentNews,
      latestRevenue: batchData.latestRevenue,
      latestValuation: batchData.latestValuation,
      revenueHistory: batchData.revenueHistory,
      epsHistory: batchData.epsHistory,
      roeHistory: batchData.roeHistory,
      dividendHistory: batchData.dividendHistory,
      maxHistoricalRevenue: batchData.maxHistoricalRevenue,
    );
    final reasons = ruleEngine.evaluateStock(context, stockData);

    // 無訊號是正常結果（多數股票屬此類），但仍須計數讓帳目平。
    //
    // 例外：自選股即使零訊號也要留下分析列。畫面上一定看得到那張卡，沒有列
    // 就整張空白（無評分、無標籤、無趨勢），使用者分不出「今日沒訊號」與
    // 「壞掉」。實機 2059 川湖連續四天全空。理由與範圍見
    // [ScoringIsolateInput.watchlistSymbols]。
    if (reasons.isEmpty) {
      if (!watchlist.contains(symbol)) {
        skippedNoReasons++;
        continue;
      }
      outputs.add(
        ScoringIsolateOutput(
          symbol: symbol,
          scoreShort: 0,
          scoreLong: 0,
          turnover: turnover,
          trendState: analysisResult.trendState.code,
          reversalState: analysisResult.reversalState.code,
          supportLevel: analysisResult.supportLevel,
          resistanceLevel: analysisResult.resistanceLevel,
          // 沒有訊號就是沒有，不得偽造
          reasons: const [],
        ),
      );
      continue;
    }

    // 7. 雙 horizon 評分核心（共用 pipeline，與主執行緒路徑同一實作；
    //    mutex 策略、門檻語意與設計決議見 scoring_pipeline.dart）
    final scored = scoreReasonsDualHorizon(
      ruleEngine: ruleEngine,
      reasons: reasons,
      calibratedScores: input.calibratedScores,
    );
    if (scored == null) {
      skippedLowScore++;
      continue;
    }
    outputs.add(
      ScoringIsolateOutput(
        symbol: symbol,
        scoreShort: scored.scoreShort,
        scoreLong: scored.scoreLong,
        turnover: turnover,
        trendState: analysisResult.trendState.code,
        reversalState: analysisResult.reversalState.code,
        supportLevel: analysisResult.supportLevel,
        resistanceLevel: analysisResult.resistanceLevel,
        reasons: scored.topReasons
            .map(
              (r) => _reasonToOutput(
                r,
                input.calibratedScores,
                scored.decayMultipliers,
              ),
            )
            .toList(),
      ),
    );
  }

  return ScoringBatchResult(
    outputs: outputs,
    candidateCount: input.candidates.length,
    skippedNoData: skippedNoData,
    skippedInsufficientData: skippedInsufficientData,
    skippedLowLiquidity: skippedLowLiquidity,
    skippedStaleBar: skippedStaleBar,
    skippedNoAnalysis: skippedNoAnalysis,
    skippedNoReasons: skippedNoReasons,
    skippedLowScore: skippedLowScore,
  ).toMap();
}

/// 從 input 建立市場資料上下文（警示、董監、外資、當沖）
MarketDataContext? _buildMarketDataContext(
  ScoringIsolateInput input,
  String symbol,
) {
  return MarketDataContext.fromComponents(
    dayTradingRatio: input.dayTradingMap?[symbol],
    shareholding: input.shareholdingMap?[symbol],
    warning: input.warningMap?[symbol],
    insider: input.insiderMap?[symbol],
  );
}

/// 轉換各項批次資料（法人、新聞、營收、估值、EPS、ROE、股利）
({
  List<DailyInstitutionalEntry>? institutionalHistory,
  List<NewsItemEntry>? recentNews,
  MonthlyRevenueEntry? latestRevenue,
  StockValuationEntry? latestValuation,
  List<MonthlyRevenueEntry>? revenueHistory,
  List<FinancialDataEntry>? epsHistory,
  List<FinancialDataEntry>? roeHistory,
  List<DividendHistoryEntry>? dividendHistory,
  double? maxHistoricalRevenue,
})
_convertBatchData(ScoringIsolateInput input, String symbol) {
  final institutional = input.institutionalMap[symbol];
  final news = input.newsMap[symbol];
  final revenueHistory = input.revenueHistoryMap?[symbol];
  final epsHistory = input.epsHistoryMap?[symbol];
  final roeHistory = input.roeHistoryMap?[symbol];
  final dividendHistory = input.dividendHistoryMap?[symbol];

  return (
    institutionalHistory: institutional != null && institutional.isNotEmpty
        ? institutional
        : null,
    recentNews: news != null && news.isNotEmpty ? news : null,
    latestRevenue: input.revenueMap?[symbol],
    latestValuation: input.valuationMap?[symbol],
    revenueHistory: revenueHistory != null && revenueHistory.isNotEmpty
        ? revenueHistory
        : null,
    epsHistory: epsHistory != null && epsHistory.isNotEmpty ? epsHistory : null,
    roeHistory: roeHistory != null && roeHistory.isNotEmpty ? roeHistory : null,
    dividendHistory: dividendHistory != null && dividendHistory.isNotEmpty
        ? dividendHistory
        : null,
    maxHistoricalRevenue: input.maxHistoricalRevenueMap?[symbol],
  );
}

/// 空 Map → null 轉換，用於 nullable 欄位的反序列化
extension _MapIfEmpty<K, V> on Map<K, V> {
  Map<K, V>? ifEmpty(Map<K, V>? fallback) => isEmpty ? fallback : this;
}

/// 建立 [IsolateReasonOutput]，為兩個 horizon 各自查 calibrated 後 fallback。
///
/// 在 isolate 邊界落入 DTO 前就決定 per-rule 分數，這樣主 isolate 寫庫時
/// 可以直接把 `scoreShort` / `scoreLong` 塞進 `DailyReason` 的雙欄位。
IsolateReasonOutput _reasonToOutput(
  TriggeredReason reason,
  CalibratedScoreContext ctx,
  Map<String, double> decayMultipliers,
) {
  final code = reason.type.code;
  // 乘上基本面遞減係數（與主執行緒路徑一致、保持總分=SUM invariant）
  final multiplier = decayMultipliers[code] ?? 1.0;
  return IsolateReasonOutput(
    type: code,
    scoreShort: ((ctx.lookup(Horizon.short, code) ?? reason.score) * multiplier)
        .round(),
    scoreLong: ((ctx.lookup(Horizon.long, code) ?? reason.score) * multiplier)
        .round(),
    description: reason.description,
    evidenceJson: reason.evidenceJson != null
        ? jsonEncode(reason.evidenceJson)
        : '{}',
  );
}

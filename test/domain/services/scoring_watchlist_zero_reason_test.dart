// 自選股零訊號也要留下分析列(2026-08-16 實機)
//
// **現象**:2059 川湖在自選股頁連續四天是一張空白卡——沒有評分、沒有標籤、
// 沒有趨勢箭頭。資料完全正常(287 筆價格、近兩月 43 筆、最新到 8/14),對照
// 組 3081 聯亞資料量一模一樣卻有分析。
//
// **根因**:`reasons.isEmpty` 直接 `continue`,連 `daily_analysis` 都不寫。
// 於是趨勢狀態、支撐壓力這些算得出來的東西一起丟掉,而畫面上「沒有列」與
// 「沒被分析/壞掉」長得一模一樣。
//
// **為什麼只對自選股豁免**:候選股是全市場可分析且流動的股票(見
// `CandidateSelector` 步驟 4),全開會多寫上千列/日;自選股是 ≤36 檔。
// 這與該檔步驟 1「自選清單優先、豁免流動性過濾——使用者主動追蹤」是同一
// 條原則。
//
// **為什麼同一組資料要跑兩條路徑**:評分有 isolate 與主執行緒 fallback
// 兩份實作,本專案有複本分岔的前科(2026-07-23 圖示 switch、2026-08-16
// 顏色 switch)。各測各的會讓其中一條悄悄退化,所以這裡用**同一份輸入**
// 斷言兩條路徑的結果相同。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:daredevil/domain/services/scoring_service.dart';

import '../../helpers/price_data_generators.dart';

/// 手寫 fake 而非 mocktail stub:`runInTransaction<T>` 是泛型方法,stub 不易
/// 對上型別(既有 scoring_service_test 也是直接 override)。
class FakeAnalysisRepository extends Mock implements IAnalysisRepository {
  /// 落庫過的 symbol——本測試唯一關心的觀察點
  final persisted = <String>[];

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();

  @override
  Future<int> clearReasonsForDate(DateTime date) async => 0;

  @override
  Future<int> clearAnalysisForDate(DateTime date) async => 0;

  @override
  Future<void> saveReasons(
    String symbol,
    DateTime date,
    List<ReasonData> reasons,
  ) async {}

  @override
  Future<void> saveAnalysis({
    required String symbol,
    required DateTime date,
    required String trendState,
    required String reversalState,
    double? supportLevel,
    double? resistanceLevel,
    required double scoreShort,
    required double scoreLong,
  }) async {
    persisted.add(symbol);
  }
}

void main() {
  final today = DateTime.now();

  /// 60 天完全持平的價格——刻意選「什麼規則都不會觸發」的資料
  ///
  /// 量與額必須過得了單檔流動性門檻（`minCandidateVolumeShares` 100 萬股、
  /// `minCandidateTurnover` 3000 萬元），否則會停在 lowLiquidity 而根本走不到
  /// 「零訊號」那一步——本檔第一條「前提」測試就是為了擋住這種假測試。
  List<DailyPriceEntry> flat(String symbol) => generateConstantPrices(
    days: 60,
    basePrice: 100,
    volume: 2000000,
    symbol: symbol,
  );

  /// 大量版:當沖規則有 `minDayTradingVolumeShares`(1000 萬股)的量門檻,
  /// 低於它規則整個不觸發——分數不足的合成必須先過這道(前提測試會抓)。
  List<DailyPriceEntry> flatHeavy(String symbol) => generateConstantPrices(
    days: 60,
    basePrice: 100,
    volume: 20000000,
    symbol: symbol,
  );

  group('Isolate 路徑', () {
    ScoringBatchResult run({
      required List<String> watchlist,
      Map<String, double>? dayTradingMap,
      bool heavyVolume = false,
    }) {
      List<DailyPriceEntry> gen(String sym) =>
          heavyVolume ? flatHeavy(sym) : flat(sym);
      final input = ScoringIsolateInput(
        candidates: const ['1111', '2222'],
        pricesMap: {'1111': gen('1111'), '2222': gen('2222')},
        newsMap: const {},
        institutionalMap: const {},
        dayTradingMap: dayTradingMap,
        watchlistSymbols: watchlist,
        // date 不可為 null:isolate 對此 fail-loud(比 silent now() fallback
        // 安全)。用今天是因為 generateConstantPrices 的最後一根就是今天,
        // 否則會停在 staleBar 而走不到零訊號那一步。
        date: today,
      );
      // 直接呼叫純函數,不 spawn isolate(確定性 + 快)
      return evaluateStocksIsolated(input);
    }

    test('🚨 前提:這組資料確實零訊號(否則整個測試是空的)', () {
      final result = run(watchlist: const []);
      expect(
        result.skippedNoReasons,
        2,
        reason: '兩檔都該因零訊號被跳過;若不是,測試資料需要改成真的不觸發任何規則',
      );
      expect(result.outputs, isEmpty);
    });

    test('🚨 自選股零訊號仍產出分析列,非自選的照舊跳過', () {
      final result = run(watchlist: const ['1111']);

      expect(result.outputs, hasLength(1));
      expect(result.outputs.single.symbol, '1111');
      expect(result.skippedNoReasons, 1, reason: '2222 不是自選股,維持跳過');
    });

    test('產出的列帶著趨勢與支撐壓力——那正是空白卡缺的東西', () {
      final out = run(watchlist: const ['1111']).outputs.single;
      expect(out.trendState, isNotEmpty);
      expect(out.reversalState, isNotEmpty);
      expect(out.reasons, isEmpty, reason: '沒有訊號就是沒有,不得偽造');
      expect(out.scoreShort, 0);
      expect(out.scoreLong, 0);
    });

    test('🚨 帳目仍然平(輸出 + 跳過 == 候選)', () {
      final result = run(watchlist: const ['1111']);
      expect(
        result.accountingBalances,
        isTrue,
        reason: '從 skippedNoReasons 移到 outputs,總數必須守恆',
      );
    });

    // ── 分數不足(scored == null):同症狀的第二道閘門 ──────────────
    //
    // 2026-08-19 實機:3711 日月光投控/3234 光環/4931 新盛力/6538 倉和在
    // 8/17 都有分析、8/18 全部消失成空白卡——資料完整、量過門檻。8/16 修
    // reasons.isEmpty 時只堵了一道閘門:訊號存在但 |raw| <
    // observationScoreThreshold(8)時 scoreReasonsDualHorizon 回 null,
    // 一樣整列不寫。這正是記憶裡「診斷要逐一走過每道閘門」的教訓再現。
    //
    // 合成法:當沖比例 50–70% 觸發 DayTradingHighRule(score **0**),
    // 平盤價格保證它是唯一訊號 → raw 0 < 8 → 走進 scored == null。
    test('🚨 前提:當沖 60% + 平盤價格確實落入「分數不足」', () {
      final result = run(
        watchlist: const [],
        dayTradingMap: const {'1111': 60.0, '2222': 60.0},
        heavyVolume: true,
      );
      expect(
        result.skippedLowScore,
        2,
        reason: '兩檔都該因分數不足被跳過;若不是,合成訊號沒觸發或門檻變了',
      );
      expect(result.skippedNoReasons, 0, reason: '訊號存在,不是零訊號');
      expect(result.outputs, isEmpty);
    });

    test('🚨 分數不足的自選股也要留分析列(3711 的空白卡)', () {
      final result = run(
        watchlist: const ['1111'],
        dayTradingMap: const {'1111': 60.0, '2222': 60.0},
        heavyVolume: true,
      );
      expect(result.outputs, hasLength(1));
      expect(result.outputs.single.symbol, '1111');
      expect(
        result.outputs.single.scoreShort,
        0,
        reason: '低於觀察門檻對卡片而言等同無可觀察訊號,落庫 0 分',
      );
      expect(
        result.outputs.single.reasons,
        isEmpty,
        reason: '不寫 daily_reason,掃描頁與三模式聚合的語意不變',
      );
      expect(result.skippedLowScore, 1, reason: '2222 非自選,維持跳過');
      expect(result.accountingBalances, isTrue);
    });

    test('🚨 sendability:真 spawn isolate,全欄位滿載的 typed input 可跨界', () async {
      // Map roundtrip 移除後(2026-08-29 效能稽核 #2,benchmark ~1.2s/次),
      // 「可跨界性」是唯一只有真 Isolate.run 才驗得到的性質——純函數測試
      // 不 spawn,欄位混入不可傳型別(closure/ReceivePort)只會在生產炸。
      // 這條把所有 optional 欄位都填滿,任何欄位變不可傳當場紅。
      final input = ScoringIsolateInput(
        candidates: const ['1111'],
        pricesMap: {'1111': flatHeavy('1111')},
        newsMap: const {'1111': []},
        institutionalMap: const {'1111': []},
        revenueMap: const {},
        valuationMap: const {},
        revenueHistoryMap: const {'1111': []},
        date: today,
        dayTradingMap: const {'1111': 5.0},
        shareholdingMap: const {},
        warningMap: const {},
        insiderMap: const {},
        epsHistoryMap: const {'1111': []},
        roeHistoryMap: const {'1111': []},
        dividendHistoryMap: const {'1111': []},
        maxHistoricalRevenueMap: const {'1111': 1.0},
        calibratedScores: CalibratedScoreContext.empty,
        watchlistSymbols: const ['1111', '2330'],
      );
      final result = await evaluateStocksInIsolate(input);
      expect(result.candidateCount, 1, reason: 'typed 輸入輸出雙向跨界成功');
      expect(result.accountingBalances, isTrue);
    });
  });

  group('主執行緒 fallback 路徑（必須與 isolate 行為一致）', () {
    late FakeAnalysisRepository repo;
    late ScoringService service;

    setUp(() {
      repo = FakeAnalysisRepository();
      service = ScoringService(
        analysisService: AnalysisService(),
        ruleEngine: RuleEngine(),
        analysisRepository: repo,
      );
    });

    Future<List<ScoredStock>> run({
      required List<String> watchlist,
      double? dayTradingRatio,
    }) {
      List<DailyPriceEntry> gen(String sym) =>
          dayTradingRatio != null ? flatHeavy(sym) : flat(sym);
      return service.scoreStocks(
        candidates: const ['1111', '2222'],
        date: today,
        batchData: ScoringBatchData(
          pricesMap: {'1111': gen('1111'), '2222': gen('2222')},
          newsMap: const {},
          institutionalMap: const {},
        ),
        marketDataBuilder: dayTradingRatio == null
            ? null
            : (_) async => MarketDataContext(dayTradingRatio: dayTradingRatio),
        watchlistSymbols: watchlist,
      );
    }

    test('🚨 自選股零訊號仍落庫,非自選的不落庫（與 isolate 同結論）', () async {
      await run(watchlist: const ['1111']);
      expect(repo.persisted, ['1111']);
    });

    test('沒有自選股時兩檔都不落庫（前提:資料確實零訊號）', () async {
      await run(watchlist: const []);
      expect(repo.persisted, isEmpty);
    });

    test('🚨 分數不足的自選股也落庫(與 isolate 同結論)', () async {
      final scored = await run(watchlist: const ['1111'], dayTradingRatio: 60);
      expect(repo.persisted, ['1111']);
      expect(scored, isEmpty, reason: '低於門檻不得混進「評分 N 檔」');
    });

    test('🚨 零訊號股不得混進「評分 N 檔」的回傳清單', () async {
      // scoredStocks 的語意是「有訊號、有分數的股票」,補這一列是為了畫面
      // 不空白,不是為了讓它出現在排行裡。
      final scored = await run(watchlist: const ['1111']);
      expect(scored, isEmpty);
    });
  });
}

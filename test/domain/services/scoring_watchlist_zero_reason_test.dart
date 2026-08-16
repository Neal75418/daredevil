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
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
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

  group('Isolate 路徑', () {
    ScoringBatchResult run({required List<String> watchlist}) {
      final input = ScoringIsolateInput(
        candidates: const ['1111', '2222'],
        pricesMap: {'1111': flat('1111'), '2222': flat('2222')},
        newsMap: const {},
        institutionalMap: const {},
        watchlistSymbols: watchlist,
        // date 不可為 null:isolate 對此 fail-loud(比 silent now() fallback
        // 安全)。用今天是因為 generateConstantPrices 的最後一根就是今天,
        // 否則會停在 staleBar 而走不到零訊號那一步。
        date: today,
      );
      // 直接呼叫純函數,不 spawn isolate(確定性 + 快)
      return ScoringBatchResult.fromMap(evaluateStocksIsolated(input.toMap()));
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

    test('watchlistSymbols 跨 isolate 邊界序列化', () {
      const input = ScoringIsolateInput(
        candidates: ['1111'],
        pricesMap: {},
        newsMap: {},
        institutionalMap: {},
        watchlistSymbols: ['1111', '2330'],
      );
      final restored = ScoringIsolateInput.fromMap(input.toMap());
      expect(restored.watchlistSymbols, ['1111', '2330']);
    });

    test('舊版 map 缺此欄位時降級為「無自選股」而非爆炸', () {
      const input = ScoringIsolateInput(
        candidates: ['1111'],
        pricesMap: {},
        newsMap: {},
        institutionalMap: {},
      );
      final map = input.toMap()..remove('watchlistSymbols');
      expect(ScoringIsolateInput.fromMap(map).watchlistSymbols, isEmpty);
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

    Future<List<ScoredStock>> run({required List<String> watchlist}) {
      return service.scoreStocks(
        candidates: const ['1111', '2222'],
        date: today,
        batchData: ScoringBatchData(
          pricesMap: {'1111': flat('1111'), '2222': flat('2222')},
          newsMap: const {},
          institutionalMap: const {},
        ),
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

    test('🚨 零訊號股不得混進「評分 N 檔」的回傳清單', () async {
      // scoredStocks 的語意是「有訊號、有分數的股票」,補這一列是為了畫面
      // 不空白,不是為了讓它出現在排行裡。
      final scored = await run(watchlist: const ['1111']);
      expect(scored, isEmpty);
    });
  });
}

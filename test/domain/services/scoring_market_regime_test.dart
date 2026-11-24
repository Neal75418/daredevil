// 評分把大盤判定讀數帶回來，並與當天分析寫在同一個 transaction 裡
// （設計：docs/plans/2026-11-24-pullback-regime-notice-design.md）
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/rule_params_sector.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:daredevil/domain/services/scoring_service.dart';

/// 記下大盤判定的寫入，以及寫入時在第幾個 transaction 裡（null＝不在
/// transaction 裡）。和「清當天分析」比對流水號，才分得出「同一個」
/// transaction 與「另開一個」
class _RegimeRecordingRepo extends Mock implements IAnalysisRepository {
  var _txSeq = 0;
  int? _currentTx;
  final regimeWrites = <(DateTime, MarketRegimeReading?, int?)>[];
  final clearAnalysisTx = <int?>[];
  final reasonTypes = <String, List<String>>{};

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    _currentTx = ++_txSeq;
    try {
      return await action();
    } finally {
      _currentTx = null;
    }
  }

  @override
  Future<int> clearReasonsForDate(DateTime date) async => 0;

  @override
  Future<int> clearAnalysisForDate(DateTime date) async {
    clearAnalysisTx.add(_currentTx);
    return 0;
  }

  @override
  Future<void> saveReasons(
    String symbol,
    DateTime date,
    List<ReasonData> reasons,
  ) async {
    reasonTypes[symbol] = [for (final r in reasons) r.type];
  }

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
  }) async {}

  @override
  Future<void> replaceMarketRegimeForDate(
    DateTime date,
    MarketRegimeReading? reading,
  ) async {
    regimeWrites.add((date, reading, _currentTx));
  }
}

void main() {
  final day = DateTime(2026, 11, 24);

  /// 121 根、最後一根是評分日，對 120 根前漲 [retPct]%
  List<DailyPriceEntry> stock(String symbol, double retPct) => [
    for (var d = 0; d < 121; d++)
      DailyPriceEntry(
        symbol: symbol,
        date: day.subtract(Duration(days: 120 - d)),
        open: 100,
        high: 100,
        low: 100,
        close: d == 120 ? 100 * (1 + retPct / 100) : 100,
        volume: 2000000,
      ),
  ];

  /// [up] 檔漲 10%、[down] 檔跌 10%
  Map<String, List<DailyPriceEntry>> market({
    required int up,
    required int down,
  }) => {
    for (var i = 0; i < up; i++) 'u$i': stock('u$i', 10),
    for (var i = 0; i < down; i++) 'd$i': stock('d$i', -10),
  };

  ScoringIsolateInput input(Map<String, List<DailyPriceEntry>> prices) =>
      ScoringIsolateInput(
        candidates: prices.keys.take(2).toList(),
        pricesMap: prices,
        newsMap: const {},
        institutionalMap: const {},
        dividendContexts: const {},
        date: day,
      );

  ScoringBatchData batch(Map<String, List<DailyPriceEntry>> prices) =>
      ScoringBatchData(
        pricesMap: prices,
        newsMap: const {},
        institutionalMap: const {},
        dividendContexts: const {},
      );

  final prices = market(up: 25, down: 35);
  final expected = PriceCalculator.marketRegimeReading(
    prices,
    SectorParams.regimeLookbackDays,
    asOf: day,
  );

  test('前提：這組資料算得出非多頭的讀數', () {
    expect(expected, isNotNull);
    expect(expected!.eligibleCount, 60);
    expect(expected.isUptrend, isFalse);
  });

  test('純函數路徑：批次結果帶回讀數，與 PriceCalculator 同一份', () {
    expect(evaluateStocksIsolated(input(prices)).marketRegime, expected);
  });

  test('真的 spawn isolate：讀數跨界傳回', () async {
    final result = await evaluateStocksInIsolate(input(prices));
    expect(result.marketRegime, expected);
  });

  group('回檔規則的大盤閘門吃的是這份讀數', () {
    /// 連漲 120 天後今天收黑、剛好拉回月線、量縮：多頭時觸發「強勢回檔到 MA20」
    List<DailyPriceEntry> pullbackStock() {
      double close(int i) => i == 120 ? 106 : 40 + 0.6 * i;
      return [
        for (var i = 0; i < 121; i++)
          DailyPriceEntry(
            symbol: 'PB',
            date: day.subtract(Duration(days: 120 - i)),
            open: i == 120 ? 108 : close(i) - 0.3,
            high: i == 120 ? 108 : close(i) + 0.2,
            low: i == 120 ? 105.5 : close(i) - 0.5,
            close: close(i),
            volume: i == 120 ? 1000000 : 3000000,
          ),
      ];
    }

    Map<String, List<DailyPriceEntry>> universe({required bool bull}) => {
      'PB': pullbackStock(),
      ...market(up: bull ? 59 : 0, down: bull ? 0 : 59),
    };

    ScoringIsolateInput pbInput(bool bull) => ScoringIsolateInput(
      candidates: const ['PB'],
      pricesMap: universe(bull: bull),
      newsMap: const {},
      institutionalMap: const {},
      dividendContexts: const {},
      date: day,
      watchlistSymbols: const ['PB'],
    );

    List<String> isolatedReasons(bool bull) => [
      for (final o in evaluateStocksIsolated(pbInput(bull)).outputs)
        if (o.symbol == 'PB') ...o.reasons.map((r) => r.type),
    ];

    test('純函數路徑：多頭觸發、非多頭不觸發', () {
      expect(isolatedReasons(true), contains('PULLBACK_TO_MA20'));
      expect(isolatedReasons(false), isNot(contains('PULLBACK_TO_MA20')));
    });

    test('主執行緒路徑：多頭觸發、非多頭不觸發', () async {
      Future<List<String>> run(bool bull) async {
        final repo = _RegimeRecordingRepo();
        await ScoringService(
          analysisService: AnalysisService(),
          ruleEngine: RuleEngine(),
          analysisRepository: repo,
        ).scoreStocks(
          candidates: const ['PB'],
          date: day,
          batchData: batch(universe(bull: bull)),
          watchlistSymbols: const ['PB'],
        );
        return repo.reasonTypes['PB'] ?? const [];
      }

      expect(await run(true), contains('PULLBACK_TO_MA20'));
      expect(await run(false), isNot(contains('PULLBACK_TO_MA20')));
    });
  });

  group('寫入', () {
    late _RegimeRecordingRepo repo;
    late ScoringService service;

    setUp(() {
      repo = _RegimeRecordingRepo();
      service = ScoringService(
        analysisService: AnalysisService(),
        ruleEngine: RuleEngine(),
        analysisRepository: repo,
      );
    });

    test('背景路徑：與當天分析在同一個 transaction 裡寫入讀數', () async {
      await service.scoreStocksInIsolate(
        candidates: prices.keys.take(2).toList(),
        date: day,
        batchData: batch(prices),
      );
      expect(repo.clearAnalysisTx, hasLength(1));
      expect(repo.clearAnalysisTx.single, isNotNull);
      expect(repo.regimeWrites, [(day, expected, repo.clearAnalysisTx.single)]);
    });

    test('主執行緒路徑：與當天分析在同一個 transaction 裡寫入同一份讀數', () async {
      await service.scoreStocks(
        candidates: prices.keys.take(2).toList(),
        date: day,
        batchData: batch(prices),
      );
      expect(repo.clearAnalysisTx, hasLength(1));
      expect(repo.clearAnalysisTx.single, isNotNull);
      expect(repo.regimeWrites, [(day, expected, repo.clearAnalysisTx.single)]);
    });

    test('有效股不足：寫入 null，刪掉當天原本的讀數', () async {
      final few = market(up: 5, down: 5);
      await service.scoreStocksInIsolate(
        candidates: few.keys.take(2).toList(),
        date: day,
        batchData: batch(few),
      );
      expect(repo.regimeWrites, [(day, null, repo.clearAnalysisTx.single)]);
    });
  });

  group('回滾（真的記憶體 DB）', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: 'u0', name: '甲', market: 'TWSE'),
      ]);
    });

    tearDown(() => db.close());

    const old = MarketRegimeReading(
      eligibleCount: 500,
      upCount: 300,
      medianReturn: 0.05,
      isUptrend: true,
      lookbackDays: 120,
    );

    for (final (name, isolate) in [('背景路徑', true), ('主執行緒路徑', false)]) {
      test('$name：分析寫到一半失敗，讀數也回到原本的', () async {
        final repo = _FailingSaveRepo(db);
        await repo.replaceMarketRegimeForDate(day, old);
        final service = ScoringService(
          analysisService: AnalysisService(),
          ruleEngine: RuleEngine(),
          analysisRepository: repo,
        );
        final run = isolate
            ? service.scoreStocksInIsolate(
                candidates: const ['u0'],
                date: day,
                batchData: batch(prices),
                watchlistSymbols: const ['u0'],
              )
            : service.scoreStocks(
                candidates: const ['u0'],
                date: day,
                batchData: batch(prices),
                watchlistSymbols: const ['u0'],
              );
        await expectLater(run, throwsA(isA<StateError>()));
        expect(repo.saveAttempts, greaterThan(0), reason: '前提：真的寫到分析');
        expect(await repo.getMarketRegime(day), old);
      });
    }
  });
}

/// 真的 repository，但寫入分析後丟例外（模擬寫到一半磁碟滿）
class _FailingSaveRepo extends AnalysisRepository {
  _FailingSaveRepo(AppDatabase db) : super(database: db);

  var saveAttempts = 0;

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
    saveAttempts++;
    await super.saveAnalysis(
      symbol: symbol,
      date: date,
      trendState: trendState,
      reversalState: reversalState,
      supportLevel: supportLevel,
      resistanceLevel: resistanceLevel,
      scoreShort: scoreShort,
      scoreLong: scoreLong,
    );
    throw StateError('磁碟滿');
  }
}

// 52 週規則在兩條評分路徑（isolate、主執行緒回退）結果一致，且各自記錄
// 每輪觀測（完整度不足、斷點）
//
// 同一份 ScoringBatchData 分別走 scoreStocksInIsolate（真的開 isolate，含
// batch data → isolate 輸入的轉交）與 scoreStocks（回退），比對落庫的
// reasons。資料刻意設計成「原始價格不觸發、還原後才觸發」：任一條路徑沒把
// 股利情境帶進 StockData，都會少一筆 WEEK_52_HIGH。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:daredevil/domain/services/scoring_service.dart';

import '../../helpers/price_data_generators.dart';

/// 記錄每檔落庫的 reason 代碼（只記非空的清單）
class _RecordingRepo extends Mock implements IAnalysisRepository {
  final reasons = <String, List<String>>{};

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
    List<ReasonData> list,
  ) async {
    if (list.isNotEmpty) {
      reasons[symbol] = [for (final r in list) r.type]..sort();
    }
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
}

/// 從 2025-01-01 起逐日一根、每根 200 萬股（過得了單檔流動性門檻）
List<DailyPriceEntry> _daily(String symbol, List<double> closes) => [
  for (var i = 0; i < closes.length; i++)
    createTestPrice(
      symbol: symbol,
      date: DateTime(2025, 1, 1).add(Duration(days: i)),
      close: closes[i],
      volume: 2000000,
    ),
];

List<double> _flat(int n, double value) => List.filled(n, value);

/// 原始價格不觸發、還原後創新高（見 indicator_rules_test 的同名資料）
List<double> _adjustOnlyHighCloses() =>
    [..._flat(200, 100), ..._flat(59, 95), 99.0]
      ..[50] = 104
      ..[230] = 97;

Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  // 第 259 根（今天）的日期：候選資格要求最後一根就是評分日
  final date = DateTime(2025, 9, 17);
  const symbols = ['ADJ', 'INC', 'NOMAP', 'GAP'];

  final pricesMap = {
    'ADJ': _daily('ADJ', _adjustOnlyHighCloses()),
    'INC': _daily('INC', _adjustOnlyHighCloses()),
    'NOMAP': _daily('NOMAP', _adjustOnlyHighCloses()),
    // 第 200 根起從 50 跳到 100（不在除權除息列表）：還原後仍有斷點
    'GAP': _daily('GAP', [..._flat(200, 50), ..._flat(59, 100), 101.5]),
  };
  final contexts = <String, DividendContext>{
    'ADJ': DividendContext.complete([
      DividendPriceEvent(
        exDate: DateTime(2025, 1, 1).add(const Duration(days: 200)),
        closeBefore: 100,
        referencePrice: 90,
      ),
    ]),
    'INC': const DividendContext.incomplete(),
    'GAP': DividendContext.noEvents,
    // NOMAP 刻意不放：找不到情境要視為不完整
  };

  ScoringBatchData batch() => ScoringBatchData(
    pricesMap: pricesMap,
    newsMap: const {},
    institutionalMap: const {},
    dividendContexts: contexts,
  );

  ScoringService service(_RecordingRepo repo) => ScoringService(
    analysisService: AnalysisService(),
    ruleEngine: RuleEngine(),
    analysisRepository: repo,
  );

  test('🚨 兩條路徑落庫的 reasons 相同；還原後才觸發的那檔兩邊都有 WEEK_52_HIGH', () async {
    final viaIsolate = _RecordingRepo();
    final viaFallback = _RecordingRepo();

    await service(viaIsolate).scoreStocksInIsolate(
      candidates: symbols,
      date: date,
      batchData: batch(),
      watchlistSymbols: symbols,
    );
    await service(viaFallback).scoreStocks(
      candidates: symbols,
      date: date,
      batchData: batch(),
      watchlistSymbols: symbols,
    );

    expect(viaIsolate.reasons, viaFallback.reasons);
    expect(viaIsolate.reasons['ADJ'], contains('WEEK_52_HIGH'));
    for (final s in ['INC', 'NOMAP', 'GAP']) {
      expect(
        viaIsolate.reasons[s] ?? const <String>[],
        isNot(contains('WEEK_52_HIGH')),
        reason: s,
      );
    }
  });

  test('🚨 isolate 結果帶 52 週觀測：完整度不足 2 檔（含找不到情境的）、斷點 1 檔；帳目仍平', () {
    final result = evaluateStocksIsolated(
      ScoringIsolateInput(
        candidates: symbols,
        pricesMap: pricesMap,
        newsMap: const {},
        institutionalMap: const {},
        dividendContexts: contexts,
        date: date,
      ),
    );

    expect((result.week52Incomplete, result.week52Discontinuity), (2, 1));
    expect(result.accountingBalances, isTrue);
  });

  for (final (name, run) in [
    (
      'isolate',
      (ScoringService s) => s.scoreStocksInIsolate(
        candidates: symbols,
        date: date,
        batchData: batch(),
      ),
    ),
    (
      '主執行緒回退',
      (ScoringService s) =>
          s.scoreStocks(candidates: symbols, date: date, batchData: batch()),
    ),
  ]) {
    test('🚨 $name 路徑每輪記一行 52 週觀測', () async {
      final lines = await _capturePrints(() => run(service(_RecordingRepo())));

      expect(
        lines.where((l) => l.contains('52 週：完整度不足 2 檔、斷點 1 檔')),
        hasLength(1),
      );
    });
  }
}

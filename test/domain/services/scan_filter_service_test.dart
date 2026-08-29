import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/scan_models.dart';
import 'package:daredevil/domain/services/scan_filter_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ScanFilterService();

  // Helper: create a DailyAnalysisEntry。[scoreLong] 省略時等於 [score]（短=長），
  // 需測 horizon 分歧時才顯式給不同值。
  DailyAnalysisEntry createAnalysis({
    required String symbol,
    double score = 50.0,
    double? scoreLong,
    String trendState = 'UP',
  }) {
    return DailyAnalysisEntry(
      symbol: symbol,
      date: DateTime(2025, 1, 15),
      trendState: trendState,
      reversalState: 'NONE',
      scoreShort: score,
      scoreLong: scoreLong ?? score,
      computedAt: DateTime(2025, 1, 15),
    );
  }

  // Helper: create a DailyReasonEntry
  DailyReasonEntry createReason({
    required String symbol,
    required String reasonType,
    int rank = 1,
  }) {
    return DailyReasonEntry(
      symbol: symbol,
      date: DateTime(2025, 1, 15),
      rank: rank,
      reasonType: reasonType,
      evidenceJson: '{}',
      ruleScoreShort: 10.0,
      ruleScoreLong: 10.0,
    );
  }

  // ==========================================
  // applyFilter
  // ==========================================
  group('applyFilter', () {
    test('returns all analyses when filter is ScanFilter.all', () {
      final analyses = [
        createAnalysis(symbol: 'A'),
        createAnalysis(symbol: 'B'),
      ];

      final result = service.applyFilter(
        allAnalyses: analyses,
        filter: ScanFilter.all,
        allReasons: {},
      );

      expect(result.length, equals(2));
    });

    test('filters by industry symbols', () {
      final analyses = [
        createAnalysis(symbol: 'A'),
        createAnalysis(symbol: 'B'),
        createAnalysis(symbol: 'C'),
      ];

      final result = service.applyFilter(
        allAnalyses: analyses,
        filter: ScanFilter.all,
        allReasons: {},
        industrySymbols: {'A', 'C'},
      );

      expect(result.length, equals(2));
      expect(result.map((a) => a.symbol), containsAll(['A', 'C']));
    });

    test('filters by reasonCode', () {
      final analyses = [
        createAnalysis(symbol: 'A'),
        createAnalysis(symbol: 'B'),
      ];
      final reasons = {
        'A': [createReason(symbol: 'A', reasonType: 'REVERSAL_W2S')],
        'B': [createReason(symbol: 'B', reasonType: 'TECH_BREAKOUT')],
      };

      final result = service.applyFilter(
        allAnalyses: analyses,
        filter: ScanFilter.reversalW2S,
        allReasons: reasons,
      );

      expect(result.length, equals(1));
      expect(result.first.symbol, equals('A'));
    });

    test('excludes entries with no reasons when filter has reasonCode', () {
      final analyses = [
        createAnalysis(symbol: 'A'),
        createAnalysis(symbol: 'B'),
      ];
      final reasons = <String, List<DailyReasonEntry>>{
        'A': [createReason(symbol: 'A', reasonType: 'REVERSAL_W2S')],
        // B has no reasons
      };

      final result = service.applyFilter(
        allAnalyses: analyses,
        filter: ScanFilter.reversalW2S,
        allReasons: reasons,
      );

      expect(result.length, equals(1));
      expect(result.first.symbol, equals('A'));
    });

    test('combines industry and reason filters', () {
      final analyses = [
        createAnalysis(symbol: 'A'),
        createAnalysis(symbol: 'B'),
        createAnalysis(symbol: 'C'),
      ];
      final reasons = {
        'A': [createReason(symbol: 'A', reasonType: 'REVERSAL_W2S')],
        'B': [createReason(symbol: 'B', reasonType: 'REVERSAL_W2S')],
        'C': [createReason(symbol: 'C', reasonType: 'TECH_BREAKOUT')],
      };

      final result = service.applyFilter(
        allAnalyses: analyses,
        filter: ScanFilter.reversalW2S,
        allReasons: reasons,
        industrySymbols: {'A', 'C'}, // B excluded by industry
      );

      expect(result.length, equals(1));
      expect(result.first.symbol, equals('A'));
    });

    test('returns copy, not reference to original list', () {
      final analyses = [createAnalysis(symbol: 'A')];

      final result = service.applyFilter(
        allAnalyses: analyses,
        filter: ScanFilter.all,
        allReasons: {},
      );

      expect(result, isNot(same(analyses)));
    });
  });

  // ==========================================
  // applySort
  // ==========================================
  group('applySort', () {
    test('sorts by score descending (default)', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 30),
        createAnalysis(symbol: 'B', score: 80),
        createAnalysis(symbol: 'C', score: 50),
      ];

      service.applySort(analyses, ScanSort.scoreDesc);

      expect(analyses[0].symbol, equals('B'));
      expect(analyses[1].symbol, equals('C'));
      expect(analyses[2].symbol, equals('A'));
    });

    test('rs60Desc 按 60D 報酬降冪、null 排最後、tiebreak scoreLong', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 80), // ret60 缺 → 排最後
        createAnalysis(symbol: 'B', score: 30),
        createAnalysis(symbol: 'C', score: 50),
        createAnalysis(symbol: 'D', score: 90), // ret60 缺、分數高於 A
      ];

      service.applySort(
        analyses,
        ScanSort.rs60Desc,
        ret60: {'B': 12.5, 'C': 40.0},
      );

      // C(40%) > B(12.5%) > 無 ret60 者按 scoreLong DESC: D(90) > A(80)
      expect(analyses.map((a) => a.symbol).toList(), ['C', 'B', 'D', 'A']);
    });

    test('priceChangeDesc/Asc 按漲跌幅排序（修復原 fallback 到 score 的死選項）', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 80),
        createAnalysis(symbol: 'B', score: 30),
        createAnalysis(symbol: 'C', score: 50),
      ];
      final changes = {'A': -2.0, 'B': 5.0, 'C': 1.0};

      service.applySort(
        analyses,
        ScanSort.priceChangeDesc,
        priceChanges: changes,
      );
      expect(analyses.map((a) => a.symbol).toList(), ['B', 'C', 'A']);

      service.applySort(
        analyses,
        ScanSort.priceChangeAsc,
        priceChanges: changes,
      );
      expect(analyses.map((a) => a.symbol).toList(), ['A', 'C', 'B']);
    });

    test('sorts by score ascending', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 30),
        createAnalysis(symbol: 'B', score: 80),
        createAnalysis(symbol: 'C', score: 50),
      ];

      service.applySort(analyses, ScanSort.scoreAsc);

      expect(analyses[0].symbol, equals('A'));
      expect(analyses[1].symbol, equals('C'));
      expect(analyses[2].symbol, equals('B'));
    });

    test('🚨 同分時以 symbol ASC 決勝——與輸入順序無關(稽核 M6)', () {
      // 原測試斷言「Dart's sort is stable, so order should be preserved」,
      // **那個註解是錯的**:List.sort 沒有穩定性保證,只是 n<32 時走插入
      // 排序才碰巧成立。2026-08-28 的 422 檔掃描主清單只有 63 個相異
      // scoreLong,最大同分群 146 檔(全是雙 0 的風控可見層)——遠超過那個
      // 門檻,tied block 會被打散。
      //
      // 而 setSort 是就地重排已排過的 list,所以 desc→asc→desc 來回切
      // 會讓同分群每次落在不同位置,第一頁的成員跟著變。
      // rs60Desc 與 priceChange 兩個手足分支都有 symbol tiebreak,
      // 只有 score 這兩支漏掉。
      List<DailyAnalysisEntry> tied() => [
        for (var i = 0; i < 40; i++)
          createAnalysis(symbol: 'T${i.toString().padLeft(2, '0')}', score: 50),
      ];

      final ascending = tied();
      final descending = tied().reversed.toList();

      service.applySort(ascending, ScanSort.scoreDesc);
      service.applySort(descending, ScanSort.scoreDesc);

      expect(
        ascending.map((a) => a.symbol).toList(),
        descending.map((a) => a.symbol).toList(),
        reason: '同一組資料、不同輸入順序,排序結果必須一致',
      );
      expect(ascending.first.symbol, 'T00');
      expect(ascending.last.symbol, 'T39');
    });

    test('🚨 scoreAsc 同分同樣以 symbol ASC 決勝(稽核 M6)', () {
      List<DailyAnalysisEntry> tied() => [
        for (var i = 0; i < 40; i++)
          createAnalysis(symbol: 'T${i.toString().padLeft(2, '0')}', score: 50),
      ];

      final ascending = tied();
      final descending = tied().reversed.toList();

      service.applySort(ascending, ScanSort.scoreAsc);
      service.applySort(descending, ScanSort.scoreAsc);

      expect(
        ascending.map((a) => a.symbol).toList(),
        descending.map((a) => a.symbol).toList(),
      );
      expect(ascending.first.symbol, 'T00');
    });

    test('default horizon (short) 仍依 scoreShort 排序（回歸保護）', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 80, scoreLong: 10),
        createAnalysis(symbol: 'B', score: 10, scoreLong: 80),
      ];

      service.applySort(analyses, ScanSort.scoreDesc); // 不傳 horizon = short

      // 依 scoreShort 降冪：A(80) > B(10)
      expect(analyses[0].symbol, equals('A'));
      expect(analyses[1].symbol, equals('B'));
    });

    test('horizon=long 時依 scoreLong 排序（新行為）', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 80, scoreLong: 10),
        createAnalysis(symbol: 'B', score: 10, scoreLong: 80),
        createAnalysis(symbol: 'C', score: 50, scoreLong: 50),
      ];

      service.applySort(analyses, ScanSort.scoreDesc, horizon: Horizon.long);

      // 依 scoreLong 降冪：B(80) > C(50) > A(10)
      expect(analyses[0].symbol, equals('B'));
      expect(analyses[1].symbol, equals('C'));
      expect(analyses[2].symbol, equals('A'));
    });

    test('horizon=long + scoreAsc 依 scoreLong 升冪', () {
      final analyses = [
        createAnalysis(symbol: 'A', score: 80, scoreLong: 10),
        createAnalysis(symbol: 'B', score: 10, scoreLong: 80),
      ];

      service.applySort(analyses, ScanSort.scoreAsc, horizon: Horizon.long);

      // 依 scoreLong 升冪：A(10) < B(80)
      expect(analyses[0].symbol, equals('A'));
      expect(analyses[1].symbol, equals('B'));
    });
  });
}

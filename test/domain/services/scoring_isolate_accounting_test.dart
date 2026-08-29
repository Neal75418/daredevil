// 評分帳目完整性 — 每個候選股都必須有歸屬（輸出或某個 skip 分類）
//
// 2026-07-25 實測：日誌「候選 897 檔 → 評分 142 + 跳過 701」少了 54 檔，
// 根因是 scoring_isolate 兩個 continue 未計數（analysisResult == null、
// reasons.isEmpty）。前者更是靜默失敗——技術分析失敗的股票直接消失，
// 無 log 無計數，與同檔案「fail-loud 比 silent fallback 更安全」的既定
// 原則矛盾。此測試釘住「帳目必須平」的不變量。
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScoringBatchResult 帳目不變量', () {
    test('skippedTotal 涵蓋全部 skip 分類（含 NoAnalysis / NoReasons）', () {
      const result = ScoringBatchResult(
        outputs: [],
        candidateCount: 21,
        skippedNoData: 1,
        skippedInsufficientData: 2,
        skippedLowLiquidity: 3,
        skippedNoAnalysis: 4,
        skippedNoReasons: 5,
        skippedLowScore: 6,
      );

      expect(result.skippedTotal, 21);
      expect(result.accountingBalances, isTrue);
    });

    test('帳目不平時 accountingBalances 為 false（可據此告警）', () {
      const result = ScoringBatchResult(
        outputs: [],
        candidateCount: 100,
        skippedNoData: 1,
        skippedInsufficientData: 0,
        skippedLowLiquidity: 0,
        skippedNoAnalysis: 0,
        skippedNoReasons: 0,
        skippedLowScore: 0,
      );

      expect(result.accountingBalances, isFalse);
    });
  });

  group('evaluateStocksInIsolate 實跑帳目', () {
    test('資格不符的候選全部有歸屬，帳目平', () async {
      // 兩檔都無價格資料 → classifyCandidate 判 noData，不進技術分析
      const input = ScoringIsolateInput(
        candidates: ['9991', '9992'],
        pricesMap: {'9991': [], '9992': []},
        newsMap: {'9991': [], '9992': []},
        institutionalMap: {'9991': [], '9992': []},
      );

      final result = await evaluateStocksInIsolate(input);

      expect(result.candidateCount, 2);
      expect(result.outputs, isEmpty);
      expect(
        result.accountingBalances,
        isTrue,
        reason: '每個候選股都必須落在某個 skip 分類，不得無聲消失',
      );
    });

    test('🚨 通過資格檢查但零規則觸發 → 計入 skippedNoReasons（實跑迴圈）', () async {
      // 對抗審查（mutation testing）指出：原本唯一的實跑案例餵空 pricesMap，
      // 被 classifyCandidate 的 noData 提早攔截，迴圈根本到不了規則引擎——
      // 把 `skippedNoReasons++` 整行刪掉測試仍全綠。
      //
      // 本案例造出「資格通過但無訊號」：完全平盤 30 日（長度 ≥ swingWindow=20、
      // 量 200 萬股 ≥ 100 萬、成交額 1 億 ≥ 3000 萬），走勢平淡不觸發任何規則。
      final flat = List.generate(
        30,
        (i) => DailyPriceEntry(
          symbol: 'FLAT',
          date: DateTime(2026, 6, 1).add(Duration(days: i)),
          open: 50.0,
          high: 50.0,
          low: 50.0,
          close: 50.0,
          volume: 2000000,
        ),
      );

      final input = ScoringIsolateInput(
        candidates: const ['FLAT'],
        pricesMap: {'FLAT': flat},
        newsMap: const {'FLAT': []},
        institutionalMap: const {'FLAT': []},
        date: DateTime(2026, 6, 30),
      );

      final result = await evaluateStocksInIsolate(input);

      expect(result.skippedNoReasons, 1, reason: '無訊號是正常結果，但必須計數否則帳目對不上');
      expect(result.outputs, isEmpty);
      expect(result.accountingBalances, isTrue);
    });

    // ==================================================================
    // 陳舊 bar（P1-8 L1）— 此測試釘住的是「接線」而非純函式邏輯
    //
    // classifyCandidate 本身的行為由 scoring_pipeline_test.dart 覆蓋；
    // 但純函式測試抓不到「caller 忘了把評分日傳下去」。本測試實跑
    // evaluateStocksInIsolate，把 asOf 從 scoring_isolate.dart 的
    // classifyCandidate 呼叫拿掉就會變紅。
    // ==================================================================
    test('🚨 最後一根 bar 不是評分日 → 計入 skippedStaleBar，不得產出分析', () async {
      // 30 根平盤 bar，最後一根停在 6/30；評分日卻是 7/1
      final stale = List.generate(
        30,
        (i) => DailyPriceEntry(
          symbol: 'STALE',
          date: DateTime(2026, 6, 1).add(Duration(days: i)),
          open: 50.0,
          high: 50.0,
          low: 50.0,
          close: 50.0,
          volume: 2000000,
        ),
      );

      final result = await evaluateStocksInIsolate(
        ScoringIsolateInput(
          candidates: const ['STALE'],
          pricesMap: {'STALE': stale},
          newsMap: const {'STALE': []},
          institutionalMap: const {'STALE': []},
          date: DateTime(2026, 7, 1),
        ),
      );

      expect(result.skippedStaleBar, 1, reason: '拿昨日 K 棒算今日分析等於偽造當日訊號，必須攔下並計數');
      expect(result.outputs, isEmpty);
      expect(result.accountingBalances, isTrue, reason: '新分類必須進 skippedTotal');
    });

    test('bar 就是評分日時不得被誤判為 staleBar', () async {
      final fresh = List.generate(
        30,
        (i) => DailyPriceEntry(
          symbol: 'FRESH',
          date: DateTime(2026, 6, 1).add(Duration(days: i)),
          open: 50.0,
          high: 50.0,
          low: 50.0,
          close: 50.0,
          volume: 2000000,
        ),
      );

      final result = await evaluateStocksInIsolate(
        ScoringIsolateInput(
          candidates: const ['FRESH'],
          pricesMap: {'FRESH': fresh},
          newsMap: const {'FRESH': []},
          institutionalMap: const {'FRESH': []},
          date: DateTime(2026, 6, 30), // = fresh.last.date
        ),
      );

      expect(result.skippedStaleBar, 0);
      expect(result.accountingBalances, isTrue);
    });
  });
}

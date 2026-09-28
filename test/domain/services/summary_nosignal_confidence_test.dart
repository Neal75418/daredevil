// 零訊號的股票不得顯示「佐證中等」
//
// 修正前，`AnalysisSummaryService.generate` 在 analysis == null && reasons.isEmpty
// 時 early-return 一個只帶 overallParts 與 sentiment 的 SummaryData：
//
//   return const SummaryData(
//     overallParts: [LocalizableString('summary.noSignals')],
//     sentiment: SummarySentiment.neutral,
//   );
//
// 沒帶 confidence，於是吃到 SummaryData 建構子的預設值
// `AnalysisConfidence.medium`（stock_summary.dart:28）。畫面上那顆徽章就寫
// 「佐證中等」，進度條也照 medium 的 0.25 基底畫出來——對一檔連一條訊號都
// 沒有的股票。
//
// 這是預設值洩漏成使用者可見評級：預設值的用途是讓呼叫端少寫參數，不是
// 對外宣告一個沒算過的結論。零訊號的正確描述是「佐證有限」（low），這也
// 與 _calculateConfidence 的走向一致（points = 0 時本來就回 low）。
//
// 對照組：正常路徑必須仍然算得出 high，證明這個修法沒有把整條 confidence
// 鏈路一起壓成 low。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';

void main() {
  const service = AnalysisSummaryService();

  test('🚨 無 analysis 且無 reasons 時 confidence 須為 low，不得洩漏預設的 medium', () {
    final result = service.generate(
      analysis: null,
      reasons: [],
      latestPrice: null,
      priceChange: null,
      institutionalHistory: [],
      revenueHistory: [],
      latestPER: null,
      horizon: Horizon.short,
    );

    expect(result.overallParts.single.key, 'summary.noSignals');
    expect(
      result.confidence,
      AnalysisConfidence.low,
      reason:
          '一條訊號都沒有卻標「佐證中等」，是把建構子預設值當成算出來的結論。'
          'medium 會讓這張卡看起來和真的有中等佐證的股票沒兩樣。',
    );
  });

  test('對照組：正常路徑仍算得出 high（修法沒把整條鏈路壓成 low）', () {
    final result = service.generate(
      analysis: createTestAnalysis(trendState: 'UP', score: 60),
      reasons: [
        createTestReason(reasonType: 'TECH_BREAKOUT', ruleScore: 20),
        createTestReason(reasonType: 'ROE_EXCELLENT', ruleScore: 18),
        createTestReason(reasonType: 'INSTITUTIONAL_BUY', ruleScore: 16),
      ],
      latestPrice: null,
      priceChange: null,
      institutionalHistory: [createTestInstitutional(foreignNet: 1000)],
      revenueHistory: [],
      latestPER: null,
      horizon: Horizon.short,
    );

    expect(result.confidence, AnalysisConfidence.high);
  });
}

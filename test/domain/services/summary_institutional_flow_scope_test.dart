// 「近期法人動向」顯示的是單日，不是一段期間
//
// analysis_summary_service.dart:443-449
//   // DAO 回傳 ascending order，.last 才是最新一天
//   final latest = institutionalHistory.last;
//   final foreign = _formatNetLocalizable(latest.foreignNet);
// 載入的是 institutionalLookbackDays（10 日）的歷史，但只取**最後一天**，
// 文案卻是「近期法人動向：外資 {foreign}、投信 {trust}。」
//
// 實測 2026-07-27 截圖（資料日 07-24），緯創 3231：
//   畫面「近期法人動向：外資 買超 32435 張、投信 買超 10843 張。」
//   DB：32,435 張是 **07-24 單日**；同期 10 日合計是 **167,055 張**（5.1 倍）
//   07-23 單日更高達 79,017 張。
// 也就是說「近期」這兩個字讓使用者把單日誤讀成一段期間的累積，而在法人
// 大量進出的個股上，兩者差一個量級。
//
// 這與本輪 chip anomaly 面板那條（標題宣稱「今日」、實際混合三種時間窗）
// 是同一個病：**文案宣稱的時間範圍與資料的時間範圍不符**。
//
// 修法只動文案不動行為——個股頁顯示「最新交易日法人買賣超」本來就合理，
// 錯的是把它叫成「近期」。下方行為測試把「單日」這件事釘住：日後若真要
// 改成區間加總，該測試會紅，屆時文案必須一起改回去。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';
import 'package:daredevil/core/constants/rule_params.dart';

void main() {
  const service = AnalysisSummaryService();

  test('🚨 文案不得把單日值說成「近期」', () {
    // 直接讀 i18n 實檔，避免「改了 key 但文案照舊」的假綠
    const periodWords = <String, List<String>>{
      'zh-TW': ['近期', '近日', '累計'],
      'en': ['recent', 'cumulative'],
    };
    for (final entry in periodWords.entries) {
      final copy = summaryCopyFor(entry.key)['institutionalFlow'] as String;
      final hits = [
        for (final w in entry.value)
          if (copy.toLowerCase().contains(w.toLowerCase())) w,
      ];
      expect(
        hits,
        isEmpty,
        reason:
            '${entry.key} 的文案「$copy」宣稱期間，但值取自 institutionalHistory.last '
            '（單日）。實測緯創 3231：單日 32,435 張 vs 10 日合計 167,055 張',
      );
    }
  });

  test('行為：值確實取自最新一天，不是區間加總（文案據此而定）', () {
    // 10 天遞增的假資料；若改成加總，foreign 會是 5500 而非最後一天的 1000
    final history = [
      for (var i = 0; i < 10; i++)
        createTestInstitutional(
          date: DateTime(2026, 7, 10).add(Duration(days: i)),
          foreignNet: (i + 1) * 100000, // 100~1000 張
          investmentTrustNet: -(i + 1) * 1000,
        ),
    ];

    final result = service.generate(
      analysis: createTestAnalysis(trendState: 'UP', score: 40),
      reasons: [createTestReason(reasonType: 'ROE_EXCELLENT', ruleScore: 12)],
      latestPrice: null,
      priceChange: 1.0,
      institutionalHistory: history,
      revenueHistory: [],
      latestPER: null,
      horizon: Horizon.short,
    );

    final flow = result.supportingData.firstWhere(
      (d) => d.key == 'summary.institutionalFlow',
    );

    expect(
      flow.nestedArgs['foreign']!.namedArgs['lots'],
      '1000',
      reason: '最後一天是 1,000 張；若為 10 日加總會是 5,500 張',
    );
    expect(flow.nestedArgs['trust']!.key, 'summary.netSell');
  });

  test('對照組：載入窗確實是多日（否則「單日」是巧合而非設計）', () {
    expect(
      InstitutionalParams.institutionalLookbackDays,
      greaterThan(1),
      reason: '若窗本來就是 1 天，「近期」只是措辭問題；窗有 10 天才凸顯落差',
    );
  });
}

/// 讀 i18n 實檔的 summary 區塊。
Map<String, dynamic> summaryCopyFor(String locale) {
  final file = File('assets/translations/$locale.json');
  return (json.decode(file.readAsStringSync())
          as Map<String, dynamic>)['summary']
      as Map<String, dynamic>;
}

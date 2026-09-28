// 營收年增率取到「兩年前那個月」——升冪清單卻用 .first
//
// 修正前，analysis_summary_service.dart 兩處：
//   final latest = revenueHistory.first;   ← 變數叫 latest，取到的是最舊
//   final yoy = revenueHistory.first.yoyGrowth;
//
// 而同一個檔案的法人那段寫著：
//   // DAO 回傳 ascending order，.last 才是最新一天
//   final latest = institutionalHistory.last;
// 同一個檔案、同一個陷阱，一個踩了一個沒踩。
//
// 來源確認：getMonthlyRevenueHistory `query.orderBy([(t) => OrderingTerm.asc(t.date)])`
// —— 升冪，最舊在前。取數窗是 StockFundamentalsLoader.loadAll
// `DateTime(today.year - 2, today.month, 1)`，也就是 **.first 取到的是兩年前**。
//
// 實機 2026-07-27（資料日 07-24）2425 承啟，同一張卡：
//   關鍵訊號「營收年增率達 375.6%，基本面強勁。」← 規則 evidence，2026/6，正確
//   輔助數據「營收年增率為 -40.1%，基本面轉弱。」← .first，2024/7，兩年前
// 兩個相反的數字描述同一個指標。
//
// 影響面（DB 實查，2 年窗內 |yoy| >= 20 才會顯示這句）：
//   1,330 檔有營收資料 → **692 檔會顯示**，全部顯示的是兩年前的數字；
//   其中 5 檔正負號相反（像承啟這樣一眼看得出矛盾）、9 檔差 50pp 以上。
//
// **第二處（`final yoy = revenueHistory.first.yoyGrowth`）更嚴重**：它不只是顯示，而是進 `fundamentalBias`，直接影響
// 情緒判定（偏多／中性／偏空標籤）。兩年前的營收在替今天的多空傾向加減分。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/data/models/finmind/revenue.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';

void main() {
  const service = AnalysisSummaryService();

  /// 依 DAO 慣例回傳**升冪**（最舊在前）的營收歷史。
  /// 舊月大幅衰退、最新月大幅成長——兩者結論相反，才能分辨取到哪一筆。
  List<FinMindRevenue> ascendingRevenue({
    required double oldestYoy,
    required double latestYoy,
  }) => [
    FinMindRevenue(
      stockId: '2425',
      date: '2024-07-01',
      revenue: 1000000,
      revenueYear: 2024,
      revenueMonth: 7,
      yoyGrowth: oldestYoy,
    ),
    for (var i = 1; i <= 4; i++)
      FinMindRevenue(
        stockId: '2425',
        date: '2025-0$i-01',
        revenue: 1200000,
        revenueYear: 2025,
        revenueMonth: i,
        yoyGrowth: 5.0,
      ),
    FinMindRevenue(
      stockId: '2425',
      date: '2026-06-01',
      revenue: 2408356,
      revenueYear: 2026,
      revenueMonth: 6,
      yoyGrowth: latestYoy,
    ),
  ];

  SummaryData summaryWith(List<FinMindRevenue> revenue) => service.generate(
    analysis: createTestAnalysis(trendState: 'UP', score: 40),
    // ruleScore 刻意壓低到 7：fundamentalBias 是 ±5，正向權重太大時
    // 兩組都會落在 bullish、分不出取錯與否（12 分時實測皆為 index 1）。
    reasons: [createTestReason(reasonType: 'ROE_EXCELLENT', ruleScore: 7)],
    latestPrice: null,
    priceChange: 1.0,
    institutionalHistory: [],
    revenueHistory: revenue,
    latestPER: null,
    horizon: Horizon.short,
  );

  test('🚨 顯示的營收年增率須取最新一筆，不是升冪清單的第一筆（最舊）', () {
    // 實機 2425 承啟：最舊 2024/7 = -40.1%、最新 2026/6 = +375.6%
    final result = summaryWith(
      ascendingRevenue(oldestYoy: -40.1, latestYoy: 375.6),
    );

    final revenueLines = result.supportingData
        .where((d) => d.key.startsWith('summary.revenueYoy'))
        .toList();

    expect(revenueLines, hasLength(1));
    expect(
      revenueLines.single.key,
      'summary.revenueYoySurge',
      reason:
          '最新月是 +375.6%（成長），取成最舊月的 -40.1% 會說成「基本面轉弱」——'
          '而同一張卡的關鍵訊號（走規則 evidence）說的是 +375.6%',
    );
    expect(revenueLines.single.namedArgs['growth'], '375.6');
  });

  test('🚨 情緒判定的基本面修正同樣須用最新一筆（兩年前的營收不得影響今天的多空）', () {
    // 只留營收差異：舊月大跌 → 若取錯會扣分；新月大漲 → 取對會加分
    final wrongWouldPenalise = summaryWith(
      ascendingRevenue(
        oldestYoy: AnalysisParams.revenueSignificantDeclineThreshold - 10,
        latestYoy: AnalysisParams.revenueStrongGrowthThreshold + 50,
      ),
    );

    // 對照：最新月也衰退 → 應真的偏空
    final genuinelyWeak = summaryWith(
      ascendingRevenue(
        oldestYoy: AnalysisParams.revenueStrongGrowthThreshold + 50,
        latestYoy: AnalysisParams.revenueSignificantDeclineThreshold - 10,
      ),
    );

    // SummarySentiment 宣告順序是 strongBullish, bullish, neutral, ...
    // → **index 越小越偏多**
    expect(
      wrongWouldPenalise.sentiment.index,
      lessThan(genuinelyWeak.sentiment.index),
      reason:
          '最新月大成長者的情緒必須比最新月大衰退者更偏多。'
          '兩組的最舊月剛好相反，取錯就會把兩者判反',
    );
  });

  test('對照組：只有一筆時 first == last，行為不變', () {
    final single = [
      FinMindRevenue(
        stockId: '2425',
        date: '2026-06-01',
        revenue: 2408356,
        revenueYear: 2026,
        revenueMonth: 6,
        yoyGrowth: 375.6,
      ),
    ];

    final lines = summaryWith(
      single,
    ).supportingData.where((d) => d.key.startsWith('summary.revenueYoy'));

    expect(lines.single.namedArgs['growth'], '375.6');
  });
}

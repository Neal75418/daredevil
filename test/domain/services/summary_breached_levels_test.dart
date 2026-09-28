// 支撐/壓力距離被 .abs() 剝掉方向 —— 已跌破的支撐講成「還有緩衝」
//
// 修正前 AnalysisSummaryService 的支撐／壓力距離：
//   final supportDist = ((closeVal - support) / closeVal * 100).abs();
//   final resistanceDist = ((resistance - closeVal) / closeVal * 100).abs();
//
// 實測正式 DB（2026-07-24）：
//   1504 close 66.2、支撐 67.0（**已跌破**）→ 畫面「支撐 67.0（距 1.2%）」
//   讀起來是「離支撐還有 1.2% 緩衝」，方向剛好相反 —— 而且是誘導續抱那一側。
//   8081 close 262.0、壓力 253.0（**已站上**）→「壓力 253.0（距 3.4%）」
//   讀起來是「上方還有 3.4% 壓力空間」，實際上壓力早就在下方了。
//
// 這**不是資料髒**，是設計中的一級狀態：
// AnalysisCoordinatorService 刻意把當日排除在支撐壓力
// 計算之外（`priceHistory.sublist(0, length - 1)`），註解明寫「若計算支撐/
// 壓力時包含『今日』，則『今日』永遠無法突破，因為『今日』會成為新的高點」。
// 也就是說「今日突破昨日算出的壓力」正是這個設計要捕捉的事件，摘要層卻沒處理。
//
// 影響面（daily_analysis ⋈ daily_price，兩個 level 與 close 皆非 null，754 列）：
//   正常（支撐下、壓力上）578／壓力已突破 133／支撐已跌破 43／兩者皆異常 0
// 四種組合只有三種存在，所以只需要兩個新文案。
//
// **這是 sibling sweep 的漏網**：同一個檔案 _buildOverallAssessment 的註解是
// 2026-07-26 修 priceChange 時寫下的——「曾用 .abs() 剝掉符號，再由句子的
// 用詞表達方向」——同一個 bug class、同一個方法，當時沒掃到這裡。
//
// 不動風險報酬比那段（`if (downside > 0 && upside > 0)`）：它的方向守衛
// 本來就正確，關卡被突破時 RR 會正確地不輸出。那個守衛也反證了「支撐在下、
// 壓力在上」才是這段的語意前提。
//
// **頁首徽章不在此修法範圍**（stock_detail_header.dart 的 `_LevelChip`）：
// 它渲染的是 `'$label ${value.toStringAsFixed(1)}'`，即「壓力 69.5」——
// 只標名價位，**不宣稱距離也不宣稱方向**，而收盤價就並列在同一個 header。
// 本修法治的是「距 X%」那個暗示「還沒到」的措辭，徽章沒有這個問題。
//
// 若日後想把已跨越者標成「前壓力／前支撐」，那是用詞精確度的增強，不是
// 這個 bug 的殘留；且要考慮價格在關卡上下來回時徽章文字會反覆切換。
// 實測影響面：754 列中壓力已突破 133、支撐已跌破 43。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';
import '../../helpers/price_data_generators.dart';

void main() {
  const service = AnalysisSummaryService();
  final date = DateTime(2026, 7, 24);

  SummaryData summaryFor({
    required double close,
    required double support,
    required double resistance,
  }) => service.generate(
    analysis: createTestAnalysis(
      trendState: 'UP',
      score: 40,
      supportLevel: support,
      resistanceLevel: resistance,
    ),
    reasons: [createTestReason(reasonType: 'ROE_EXCELLENT', ruleScore: 12)],
    latestPrice: createTestPrice(date: date, close: close),
    priceChange: 1.0,
    institutionalHistory: [],
    revenueHistory: [],
    latestPER: null,
    horizon: Horizon.short,
  );

  LocalizableString? levelPart(SummaryData d) {
    for (final p in d.overallParts) {
      if (p.key.startsWith('summary.supportResistance')) return p;
    }
    return null;
  }

  group('關卡已被突破時不得沿用「距 X%」的正常文案', () {
    test('🚨 壓力已被站上（實測 8081：close 262.0 / 壓力 253.0）', () {
      final part = levelPart(
        summaryFor(close: 262.0, support: 224.2, resistance: 253.0),
      );

      expect(part, isNotNull);
      expect(
        part!.key,
        isNot('summary.supportResistanceWithDist'),
        reason: '價格已在壓力之上 3.4%，卻與「上方還有 3.4% 壓力空間」在畫面上完全無法區分',
      );
    });

    test('🚨 支撐已被跌破（實測 1504：close 66.2 / 支撐 67.0）', () {
      final part = levelPart(
        summaryFor(close: 66.2, support: 67.0, resistance: 74.9),
      );

      expect(part, isNotNull);
      expect(
        part!.key,
        isNot('summary.supportResistanceWithDist'),
        reason: '把「已破線」講成「離支撐還有 1.2% 緩衝」，方向相反且偏向誘導續抱',
      );
    });

    test('對照組：正常擺法維持原 key 與原數字（實測 2377 微星）', () {
      final part = levelPart(
        summaryFor(close: 146.5, support: 139.5, resistance: 153.0),
      );

      expect(part!.key, 'summary.supportResistanceWithDist');
      // 與實機截圖逐字吻合：支撐 139.5（距 4.8%）、壓力 153.0（距 4.4%）
      expect(part.namedArgs['supportDist'], '4.8');
      expect(part.namedArgs['resistanceDist'], '4.4');
    });

    test('對照組：關卡被突破時風險報酬比仍正確地不輸出（守衛不得被動到）', () {
      final breached = summaryFor(
        close: 262.0,
        support: 224.2,
        resistance: 253.0,
      );
      final normal = summaryFor(
        close: 146.5,
        support: 139.5,
        resistance: 153.0,
      );

      expect(
        breached.overallParts.any((p) => p.key == 'summary.riskReward'),
        isFalse,
        reason: 'upside <= 0，RR 無意義',
      );
      expect(
        normal.overallParts.any((p) => p.key == 'summary.riskReward'),
        isTrue,
        reason: '正常情況仍須輸出，證明上一條不是把整段關掉',
      );
    });

    // 兩側邊界都要測：只測一側時，把另一側的判準從 `< 0` 改成 `<= 0`
    // （等於關卡即誤判為跨越）不會有任何測試轉紅。
    test('邊界：價格恰好等於壓力時不算突破（距 0.0%，維持正常文案）', () {
      final part = levelPart(
        summaryFor(close: 153.0, support: 139.5, resistance: 153.0),
      );

      expect(part!.key, 'summary.supportResistanceWithDist');
      expect(part.namedArgs['resistanceDist'], '0.0');
    });

    test('邊界：價格恰好等於支撐時不算跌破（距 0.0%，維持正常文案）', () {
      final part = levelPart(
        summaryFor(close: 139.5, support: 139.5, resistance: 153.0),
      );

      expect(part!.key, 'summary.supportResistanceWithDist');
      expect(part.namedArgs['supportDist'], '0.0');
    });
  });
}

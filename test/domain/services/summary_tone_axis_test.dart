// 情緒標籤與分數評語的軸線分工 —— 內文不得替 chip 講方向
//
// 實機（2026-07-26，2357 華碩）：AI 智慧分析卡標題列的標籤寫「偏多」，
// 同一張卡的內文卻寫「綜合評分 30 分，訊號中性」。同一檔股票、同一個
// 分數，兩處給出相反結論。
//
// 兩把梯子量的是不同的東西，卻共用「中性」這個詞：
//   • 標籤 = **方向**，看 bullRatio + score（bullScoreThreshold = 30）
//   • 內文 = **強度**，只看 score（scoreNeutralThreshold 15 ≤ x < scoreWatchThreshold 35）
// 於是 score 30–34 且多方訊號佔比高 → 標籤偏多 + 內文中性；
// score 15–19 且空方佔比高 → 標籤偏空 + 內文中性。多空兩側都會撞。
//
// 對齊門檻治不好，因為兩把梯子本來就該量不同的軸。真正的錯是分數梯度
// 六階裡只有 scoreNeutral 跑去講方向——其餘五階（訊號高度集中／技術面
// 強勢／具備一定技術面支撐／值得持續關注／建議觀望）講的都是強度。
// 把這一階拉回強度軸即可，且不動任何分類行為。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';

void main() {
  const scoreLadderKeys = [
    'scoreExceptional',
    'scoreStrong',
    'scoreWorthwatching',
    'scoreWatch',
    'scoreNeutral',
    'scoreCaution',
  ];

  const sentimentKeys = [
    'sentimentStrongBullish',
    'sentimentBullish',
    'sentimentNeutral',
    'sentimentBearish',
  ];

  // 「方向詞」= 標籤那把梯子的專屬詞彙。en 用 bull/bear 而非 bullish/bearish，
  // 因為 sentimentStrongBullish 的字面是 "Strong Bull Bias"。
  const directionWords = <String, List<String>>{
    'zh-TW': ['偏多', '偏空', '中性', '看多', '看空'],
    'en': ['bull', 'bear', 'neutral'],
  };

  Map<String, dynamic> summaryCopy(String locale) =>
      (json.decode(File('assets/translations/$locale.json').readAsStringSync())
              as Map<String, dynamic>)['summary']
          as Map<String, dynamic>;

  group('分數評語只講強度、不講方向', () {
    for (final locale in directionWords.keys) {
      test('🚨 $locale：分數梯度文案不得出現方向詞', () {
        final copy = summaryCopy(locale);
        final offenders = <String>[
          for (final key in scoreLadderKeys)
            for (final word in directionWords[locale]!)
              if ((copy[key] as String).toLowerCase().contains(
                word.toLowerCase(),
              ))
                '$key「$word」→ ${copy[key]}',
        ];

        expect(
          offenders,
          isEmpty,
          reason:
              '方向是情緒標籤的職責，分數梯度只表達強度。'
              '兩者共用方向詞時，score 30–34（多）或 15–19（空）會讓'
              '同一張卡同時出現「偏多」與「中性」。',
        );
      });

      test('$locale：情緒標籤仍須含方向詞（控制組——證明禁詞清單抓得到東西）', () {
        final copy = summaryCopy(locale);
        for (final key in sentimentKeys) {
          expect(
            directionWords[locale]!.any(
              (w) =>
                  (copy[key] as String).toLowerCase().contains(w.toLowerCase()),
            ),
            isTrue,
            reason: '$key 是方向標籤；若這裡也抓不到，代表禁詞清單本身失效、上面那條測試是假綠',
          );
        }
      });
    }
  });

  // 頁首每個標籤各自代表一個軸，其字面不得漏進內文的分數梯度。
  //
  // 這條是上面那條禁詞測試的補強，起因是它沒擋住的一次迴歸：commit 6ee6f29
  // 把 scoreNeutral 從「訊號中性」改成「訊號強度偏弱」以避開方向詞，結果撞上
  // 進度條的標籤「訊號強度」——同一張卡上進度條寫「訊號強度 60%」、內文寫
  // 「訊號強度偏弱」。躲掉一個碰撞換來另一個。
  //
  // 手寫禁詞清單擋不住這種事，因為要先想得到才寫得進去。改成**拿實際的標籤
  // 字串本身**去比對：任何一個頁首標籤的字面出現在分數梯度裡就是撞了，不必
  // 事先預測會撞哪個詞。
  const headerLabelKeys = [
    'confidenceHigh',
    'confidenceMedium',
    'confidenceLow',
    'sentimentStrongBullish',
    'sentimentBullish',
    'sentimentNeutral',
    'sentimentBearish',
  ];

  group('頁首標籤與內文不得共用字面', () {
    for (final locale in directionWords.keys) {
      test('🚨 $locale：分數梯度不得含任何頁首標籤的字面', () {
        final copy = summaryCopy(locale);
        final offenders = <String>[
          for (final labelKey in headerLabelKeys)
            for (final scoreKey in scoreLadderKeys)
              if ((copy[scoreKey] as String).toLowerCase().contains(
                (copy[labelKey] as String).toLowerCase(),
              ))
                '$scoreKey 含 $labelKey「${copy[labelKey]}」→ ${copy[scoreKey]}',
        ];

        expect(
          offenders,
          isEmpty,
          reason:
              '頁首標籤與內文各自代表不同的軸（方向／佐證／評分）。'
              '共用字面時，使用者會把兩個獨立的量讀成同一件事的兩種說法，'
              '而它們的值往往不一致（例如進度條 60% vs 內文「偏弱」）。',
        );
      });
    }
  });

  group('矛盾組合在正式流程中確實可達（不是紙上推導）', () {
    const service = AnalysisSummaryService();

    SummaryData summaryAt(int score, {required bool bullish}) =>
        service.generate(
          analysis: createTestAnalysis(
            trendState: 'UP',
            score: score.toDouble(),
          ),
          reasons: [
            // 多空由 ruleScore 正負決定（非 reasonType），見 _determineSentiment
            createTestReason(
              reasonType: bullish ? 'TECH_BREAKOUT' : 'TECH_BREAKDOWN',
              ruleScore: bullish ? 20 : -20,
            ),
          ],
          latestPrice: null,
          priceChange: null,
          institutionalHistory: [],
          revenueHistory: [],
          latestPER: null,
          horizon: Horizon.short,
        );

    test('score 30 + 全多方訊號 → 標籤 bullish，內文卻落在 scoreNeutral 那一階', () {
      final result = summaryAt(
        AnalysisParams.bullScoreThreshold,
        bullish: true,
      );

      expect(result.sentiment, SummarySentiment.bullish);
      expect(
        result.overallParts.any((p) => p.key == 'summary.scoreNeutral'),
        isTrue,
        reason:
            'bullScoreThreshold(${AnalysisParams.bullScoreThreshold}) < '
            'scoreWatchThreshold(${AnalysisParams.scoreWatchThreshold})，'
            '兩把梯子的重疊區真實存在——所以文案必須各守各的軸',
      );
    });

    test('score 15 + 全空方訊號 → 標籤 bearish，內文同樣落在 scoreNeutral', () {
      final result = summaryAt(
        AnalysisParams.scoreNeutralThreshold,
        bullish: false,
      );

      expect(result.sentiment, SummarySentiment.bearish);
      expect(
        result.overallParts.any((p) => p.key == 'summary.scoreNeutral'),
        isTrue,
        reason: '空方側同樣有重疊區，不是只有多方會撞',
      );
    });
  });
}

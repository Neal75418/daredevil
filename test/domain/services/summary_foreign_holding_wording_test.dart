// 「外資持股比例持續增加」——實際是兩點比較，三分之一情況最新一天在減少
//
// 規則（ForeignShareholdingIncreasingRule）判的是
//   change = 今日持股比 − N 日前持股比（BatchDataBuilder.buildShareholdingMap），
//   change >= foreignShareholdingIncreaseThreshold(0.5) 即觸發（減持規則對稱：
//   change <= -0.5，但 ≤ -2.0 改由 ForeignExodusRule 代表）。
// 那是**淨變化的門檻測試**，不是連續性檢查。
//
// 實機 2026-07-27（資料日 07-24）3006 晶豪科：卡片寫「外資持股比例持續
// 增加，持續看好。」而 DB 的實際序列是
//   07-17 34.60 → 07-20 34.47 → 07-21 34.52 → 07-22 35.97
//        → 07-23 35.89 → 07-24 35.46
// 上下震盪、**最後兩天連跌**；同卡的輔助數據也寫著「外資 賣超 1259 張」。
// 淨變化 +0.86pp 過門檻沒錯，但「持續」是假的。
//
// 影響面（DB 實查 2026-07-24）：觸發 33 檔中
//   **11 檔（33%）最新一天其實在減少**、7 檔（21%）最近兩天連減。
//
// 規則自己的 description 寫的是「外資持股比例減少 {x}%」——沒有「持續」。
// 又是規則層準確、摘要層加油添醋，與先前修掉的「營收連續 1 個月月增成長」
// （規則早已特判單月、摘要沒沿用）同型。
//
// 修法：文案改為陳述實際變化量（evidence 已有 change），不宣稱連續性，
// 也不寫死回看窗——窗是 5 個日曆天但實際落點取決於交易日，寫「近 5 日」
// 同樣不準（07-24 比到的是 07-17，隔了 7 個日曆天）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';

void main() {
  const service = AnalysisSummaryService();

  Map<String, dynamic> sectionCopy(String locale, String section) =>
      (json.decode(File('assets/translations/$locale.json').readAsStringSync())
              as Map<String, dynamic>)[section]
          as Map<String, dynamic>;

  Map<String, dynamic> summaryCopy(String locale) =>
      sectionCopy(locale, 'summary');

  group('文案不得宣稱連續性', () {
    const monotonicWords = <String, List<String>>{
      'zh-TW': ['持續增加', '持續減少', '連續增加', '連續減少'],
      'en': ['continuously', 'consecutive'],
    };

    for (final locale in monotonicWords.keys) {
      // 同型掃描：reasonTip 區塊有一份**一字不差**的複本，經
      // ReasonType.i18nTooltipKey 餵給規則標籤的 tooltip（ReasonTags）。
      // 只修 summary 會留下同一句錯的話在另一個消費點。
      // 該處走 `key.tr()` 無 namedArgs，故只去除連續性宣稱、不帶入數值。
      test('🚨 $locale：外資持股文案不得說「持續增加／減少」（含 reasonTip 複本）', () {
        final offenders = <String>[
          for (final section in ['summary', 'reasonTip'])
            for (final key in ['foreignIncreasing', 'foreignDecreasing'])
              for (final w in monotonicWords[locale]!)
                if ((sectionCopy(locale, section)[key] as String)
                    .toLowerCase()
                    .contains(w.toLowerCase()))
                  '$section.$key「$w」→ ${sectionCopy(locale, section)[key]}',
        ];

        expect(
          offenders,
          isEmpty,
          reason:
              '規則判的是兩點淨變化過門檻，不是單調遞增。實測 33 檔觸發中'
              '11 檔最新一天其實在減少（3006 晶豪科最後兩天連跌）',
        );
      });
    }
  });

  group('改陳述實際變化量', () {
    LocalizableString foreignLine(String reasonType, double change) {
      final result = service.generate(
        analysis: createTestAnalysis(trendState: 'DOWN', score: 10),
        reasons: [
          createTestReason(
            reasonType: reasonType,
            ruleScore: reasonType.contains('INCREASING') ? 8 : -8,
            evidenceJson: '{"change":$change,"ratio":35.46}',
          ),
        ],
        latestPrice: null,
        priceChange: -3.06,
        institutionalHistory: [],
        revenueHistory: [],
        latestPER: null,
        horizon: Horizon.short,
      );
      return [
        ...result.keySignals,
        ...result.riskFactors,
      ].firstWhere((ls) => ls.key.startsWith('summary.foreign'));
    }

    test('🚨 增持：帶出實際百分點（實測 3006 晶豪科 +0.86pp）', () {
      final line = foreignLine('FOREIGN_SHAREHOLDING_INCREASING', 0.86);

      expect(line.key, 'summary.foreignIncreasing');
      expect(
        line.namedArgs['change'],
        '0.86',
        reason: '數字讓使用者能自行核對，光說「增加」無從判斷幅度是 0.5 還是 5',
      );
    });

    test('🚨 減持：同樣帶出實際百分點（取絕對值，方向由用詞承載）', () {
      final line = foreignLine('FOREIGN_SHAREHOLDING_DECREASING', -1.89);

      expect(line.key, 'summary.foreignDecreasing');
      expect(line.namedArgs['change'], '1.89');
    });

    test('對照組：文案模板須含 {change} 佔位符，否則代入值會被靜默丟棄', () {
      for (final locale in ['zh-TW', 'en']) {
        final copy = summaryCopy(locale);
        for (final key in ['foreignIncreasing', 'foreignDecreasing']) {
          expect(
            copy[key],
            contains('{change}'),
            reason:
                'easy_localization 對模板缺少的 key 是 no-op：'
                '傳了 args 但模板沒佔位符 → 畫面看不出差別、測試也抓不到',
          );
        }
      }
    });
  });
}

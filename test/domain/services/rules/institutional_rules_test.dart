import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/institutional_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// 建構法人買超連續資料
List<DailyInstitutionalEntry> _generateBuyStreak({
  required int days,
  double foreignNet = 400000,
  double trustNet = 200000,
  String symbol = 'TEST',
}) {
  final now = DateTime(2025, 6, 15);
  return List.generate(days, (i) {
    return DailyInstitutionalEntry(
      symbol: symbol,
      date: now.subtract(Duration(days: days - i - 1)),
      foreignNet: foreignNet,
      investmentTrustNet: trustNet,
      dealerNet: 0,
    );
  });
}

/// 建構法人賣超連續資料
List<DailyInstitutionalEntry> _generateSellStreak({
  required int days,
  double foreignNet = -400000,
  double trustNet = -200000,
  String symbol = 'TEST',
}) {
  final now = DateTime(2025, 6, 15);
  return List.generate(days, (i) {
    return DailyInstitutionalEntry(
      symbol: symbol,
      date: now.subtract(Duration(days: days - i - 1)),
      foreignNet: foreignNet,
      investmentTrustNet: trustNet,
      dealerNet: 0,
    );
  });
}

void main() {
  // ==========================================
  // InstitutionalBuyStreakRule
  // ==========================================
  group('InstitutionalBuyStreakRule', () {
    const rule = InstitutionalBuyStreakRule();

    test('triggers with consecutive buy days meeting all thresholds', () {
      // 5 days, each: foreign 400000 + trust 200000 = 600000 > 50000 (min)
      // totalNet = 600000 * 5 = 3000000 > 1500000 (totalThreshold)
      // dailyAvg = 600000 > 200000 (dailyAvgThreshold)
      // significantDays: 600000 > 150000 → all 5 days significant (5 >= 5/2)
      final institutional = _generateBuyStreak(days: 5);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.institutionalBuyStreak));
      expect(result.evidence!['streakDays'], equals(5));
    });

    // ======================================================================
    // 連續天數截斷揭露（P1-6 子問題 C）
    //
    // 修正前 batch_data_loader 用 `institutionalLookbackDays = 10`（日曆天）載入法人
    // 歷史 → 7/24 往回 10 天只含 9 個交易日。DB 實證 streakDays 分布
    // 4:82 / 5:58 / 6:49 / 7:41 / 8:39 / 9:17、**10 以上 0 筆**——與窗大小
    // 完全吻合的硬牆，不是自然分布。
    //
    // 同型 bug 已在市場總覽徽章修過（`kStreakLookbackDays = 90` 的 docstring
    // 自承「dealer 曾連 47 日淨買卻顯示連30日」），但評分規則當時沒跟上
    // （現已改用 `institutionalStreakLookbackDays`）。
    //
    // 「連買 9 日」與「連買 25 日」是完全不同等級的籌碼訊號——前者可能只是
    // 短打、後者是主力鎖碼，決定部位大小與持有期。畫面上長得一樣就是誤導。
    // ======================================================================

    test('🚨 streak 吃光整個資料窗時必須揭露可能被截斷', () {
      // 全部 6 天都是買超 → 迴圈從未 break，代表真實連續天數可能更長
      final institutional = _generateBuyStreak(days: 6);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(
        result!.evidence!['streakTruncated'],
        isTrue,
        reason: '消耗完整個窗代表真實 streak 可能更長，必須標記',
      );
      expect(
        result.description,
        contains('以上'),
        reason: '描述必須誠實反映「至少 N 日」而非斷言剛好 N 日',
      );
    });

    test('streak 未觸頂時不得誤標截斷', () {
      // 8 天資料，但只有最後 5 天是買超 → 迴圈在第 6 天 break
      final institutional = [
        ..._generateBuyStreak(days: 3, foreignNet: -400000, trustNet: -200000),
        ..._generateBuyStreak(days: 5),
      ];
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.evidence!['streakTruncated'], isFalse);
      expect(result.description, isNot(contains('以上')));
    });

    test('applies trust-dominant bonus when trust > foreign', () {
      // trust 400000 > foreign 200000 → isTrustDominant = true
      final institutional = _generateBuyStreak(
        days: 5,
        foreignNet: 200000,
        trustNet: 400000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.score, equals(RuleScores.institutionalBuyStreak + 5));
      expect(result.evidence!['trustDominant'], isTrue);
    });

    test('does not trigger when total net is below threshold', () {
      // Each day combined = 80000, 5 days total = 400000 < 1500000
      final institutional = _generateBuyStreak(
        days: 5,
        foreignNet: 50000,
        trustNet: 30000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when daily avg is below threshold', () {
      // 10 days, each 180000 combined → total 1800000 > 1500000
      // dailyAvg = 180000 < 200000
      final institutional = _generateBuyStreak(
        days: 10,
        foreignNet: 110000,
        trustNet: 70000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when significant days are too few', () {
      // 6 days with combined between 50000-150000 (streak continues but not significant)
      // Only last 2 days are significant (combined > 150000)
      final now = DateTime(2025, 6, 15);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );

      final institutional = List.generate(6, (i) {
        final isSignificant = i >= 4; // Only last 2 are significant
        return DailyInstitutionalEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 5 - i)),
          foreignNet: isSignificant ? 600000 : 70000,
          investmentTrustNet: isSignificant ? 300000 : 30000,
          dealerNet: 0,
        );
      });
      // non-sig combined = 100000 > 50000 (streak continues)
      // but 100000 < 150000 (not significant)
      // significant days: 2 of 6 → 2 < 3 → fails
      // total = 4*100000 + 2*900000 = 2200000 > 1500000
      // dailyAvg = 366666 > 200000
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger with insufficient history', () {
      final institutional = _generateBuyStreak(days: 2);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger at exactly minStreakDays - 1 (boundary)', () {
      // streakDays must be >= InstitutionalParams.institutionalStreakDays (4)
      // 3 days = boundary - 1, should NOT trigger
      final institutional = _generateBuyStreak(days: 3);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when institutional data is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      const data = StockData(symbol: 'TEST', prices: []);

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // InstitutionalSellStreakRule
  // ==========================================
  group('InstitutionalSellStreakRule', () {
    const rule = InstitutionalSellStreakRule();

    // 賣超規則與買超規則是同一 bug class（同樣的 `for (i = length-1)` 迴圈
    // 無視窗邊界），依「修 bug class 要 sweep siblings」原則一併釘住。
    test('🚨 賣超 streak 吃光整個資料窗時必須揭露可能被截斷', () {
      final institutional = _generateSellStreak(days: 6);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.evidence!['streakTruncated'], isTrue);
      expect(result.description, contains('以上'));
    });

    test('賣超 streak 未觸頂時不得誤標截斷', () {
      final institutional = [
        ..._generateSellStreak(days: 3, foreignNet: 400000, trustNet: 200000),
        ..._generateSellStreak(days: 5),
      ];
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.evidence!['streakTruncated'], isFalse);
      expect(result.description, isNot(contains('以上')));
    });

    test('triggers with consecutive sell days meeting all thresholds', () {
      // 5 days, each: foreign -400000 + trust -200000 = -600000 < -50000
      // totalNet = -3000000 < -1500000
      // dailyAvg = -600000 < -200000
      // significantDays: |-600000| > 150000 → all 5 significant
      final institutional = _generateSellStreak(days: 5);
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      final result = rule.evaluate(context, data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.institutionalSellStreak));
      expect(result.evidence!['streakDays'], equals(5));
    });

    test(
      'applies trust-dominant penalty when trust sells more than foreign',
      () {
        final institutional = _generateSellStreak(
          days: 5,
          foreignNet: -200000,
          trustNet: -400000,
        );
        final context = AnalysisContext(
          evaluationTime: DateTime(2025, 6, 1),
          trendState: TrendState.range,
        );
        final data = StockData(
          symbol: 'TEST',
          prices: [],
          institutional: institutional,
        );

        final result = rule.evaluate(context, data);

        expect(result, isNotNull);
        expect(result!.score, equals(RuleScores.institutionalSellStreak - 5));
        expect(result.evidence!['trustDominant'], isTrue);
      },
    );

    test('does not trigger when total net is above threshold', () {
      // Small sells: combined = -80000 per day, 5 days = -400000 > -1500000
      final institutional = _generateSellStreak(
        days: 5,
        foreignNet: -50000,
        trustNet: -30000,
      );
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      expect(rule.evaluate(context, data), isNull);
    });

    test('does not trigger when institutional data is null', () {
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      const data = StockData(symbol: 'TEST', prices: []);

      expect(rule.evaluate(context, data), isNull);
    });

    test('streak breaks on non-sell day', () {
      // 5 days of sell, then 1 buy day, then 2 sells at end
      // Streak from end: only 2 days < 4 minimum
      final now = DateTime(2025, 6, 15);
      final institutional = List.generate(8, (i) {
        final isBuyDay = i == 5; // Day 5 is a buy (breaks streak)
        return DailyInstitutionalEntry(
          symbol: 'TEST',
          date: now.subtract(Duration(days: 7 - i)),
          foreignNet: isBuyDay ? 200000 : -400000,
          investmentTrustNet: isBuyDay ? 100000 : -200000,
          dealerNet: 0,
        );
      });
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: [],
        institutional: institutional,
      );

      // From end: day 7(-600k), day 6(-600k), day 5(+300k → breaks)
      // Streak = 2 < 4 → no trigger
      expect(rule.evaluate(context, data), isNull);
    });
  });
}

// Unit tests for 第 9 階段 強股回檔進場 rules (Mode C v2)。
//
// 2026-06-20 早期體檢 (workflow wf_9ac59f2a) 後補：原 commit 51e5e8a 3 條新 rule
// 零 evaluate() 覆蓋，0-fire 無法區分「過嚴」vs「bug」。這份 test 鎖定**修正後**
// 的閾值：
// - KD_HIGH_PULLBACK 窗口 [60,80) + prevKdK≥78 + drop≤30（修數學矛盾）
// - HAMMER_AT_SUPPORT touch ±4% + close≤ma20*1.06（修過嚴）
// - PATTERN_HAMMER 已移回 Mode A（不在此檔測）

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/technical_indicators.dart';
import 'package:daredevil/domain/services/rules/pullback_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

void main() {
  // --- fixtures ---

  /// 建 [count] 根日 K，baseline close=[baseClose]。overrides 用 index→entry 覆寫。
  /// index 0 = 最舊、count-1 = 今日。
  List<DailyPriceEntry> buildPrices({
    required int count,
    double baseClose = 100,
    Map<int, DailyPriceEntry> overrides = const {},
  }) {
    return [
      for (var i = 0; i < count; i++)
        overrides[i] ??
            DailyPriceEntry(
              symbol: 'TEST',
              date: DateTime(2026, 1, 1).add(Duration(days: i)),
              open: baseClose,
              high: baseClose + 1,
              low: baseClose - 1,
              close: baseClose,
              volume: 1000,
            ),
    ];
  }

  DailyPriceEntry candle({
    required int dayIdx,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
  }) => DailyPriceEntry(
    symbol: 'TEST',
    date: DateTime(2026, 1, 1).add(Duration(days: dayIdx)),
    open: open,
    high: high,
    low: low,
    close: close,
    volume: volume,
  );

  AnalysisContext ctx(TechnicalIndicators ind) => AnalysisContext(
    trendState: TrendState.up,
    evaluationTime: DateTime(2026, 1, 22),
    indicators: ind,
  );

  StockData stock(List<DailyPriceEntry> prices) =>
      StockData(symbol: 'TEST', prices: prices);

  // ============================================================
  // HealthyPullbackToMa20Rule
  // ============================================================
  group('HealthyPullbackToMa20Rule', () {
    const rule = HealthyPullbackToMa20Rule();
    // 黃金路徑：bull stack 105>100>95、past20=90 (ma20 100>94.5)、今日收黑、量縮、
    // 距 MA20 0%、過去 5 日有紅 K
    const goldenInd = TechnicalIndicators(
      ma5: 105,
      ma20: 100,
      ma60: 95,
      volumeMA20: 1000,
    );
    List<DailyPriceEntry> goldenPrices() => buildPrices(
      count: 21,
      overrides: {
        0: candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90), // past20
        15: candle(
          dayIdx: 15,
          open: 98,
          high: 100,
          low: 97,
          close: 99,
        ), // 紅 K（past 5 內）
        19: candle(
          dayIdx: 19,
          open: 102,
          high: 103,
          low: 101,
          close: 102,
        ), // yesterday
        20: candle(
          dayIdx: 20,
          open: 101,
          high: 101,
          low: 99,
          close: 100,
          volume: 800,
        ), // today 收黑 + 量縮
      },
    );

    test('fires on ideal pullback setup', () {
      final r = rule.evaluate(ctx(goldenInd), stock(goldenPrices()));
      expect(r, isNotNull);
      expect(r!.type, ReasonType.pullbackToMa20);
      expect(r.score, 15);
    });

    test('returns null when ma20 unavailable', () {
      const ind = TechnicalIndicators(ma5: 105, ma60: 95, volumeMA20: 1000);
      expect(rule.evaluate(ctx(ind), stock(goldenPrices())), isNull);
    });

    test('returns null when history < 21', () {
      final prices = goldenPrices().sublist(0, 20);
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('returns null when not bull stack (ma5 < ma20)', () {
      const ind = TechnicalIndicators(
        ma5: 95,
        ma20: 100,
        ma60: 95,
        volumeMA20: 1000,
      );
      expect(rule.evaluate(ctx(ind), stock(goldenPrices())), isNull);
    });

    test('returns null when not strong over past 20d', () {
      // past20Close = 99, ma20=100 not > 99*1.05=103.95
      final prices = goldenPrices();
      prices[0] = candle(dayIdx: 0, open: 99, high: 100, low: 98, close: 99);
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('returns null when today is up (close >= yesterday)', () {
      final prices = goldenPrices();
      prices[20] = candle(
        dayIdx: 20,
        open: 101,
        high: 104,
        low: 100,
        close: 103,
        volume: 800,
      );
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('returns null when volume not shrunk', () {
      final prices = goldenPrices();
      prices[20] = candle(
        dayIdx: 20,
        open: 101,
        high: 101,
        low: 99,
        close: 100,
        volume: 1000, // >= volumeMA20*0.85
      );
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('returns null on limit-down day', () {
      final prices = goldenPrices();
      // yesterday 102 → today 92 = -9.8% 跌停
      prices[20] = candle(
        dayIdx: 20,
        open: 95,
        high: 95,
        low: 91,
        close: 92,
        volume: 800,
      );
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('returns null on cascading decline (no red K in past 5)', () {
      final prices = goldenPrices();
      // 15 改黑 K
      prices[15] = candle(dayIdx: 15, open: 100, high: 100, low: 97, close: 98);
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });
  });

  // ============================================================
  // HealthyPullbackToMa10Rule — 2026-06-20 B2 淺回檔（close > ma20 與 MA20 互斥）
  // ============================================================
  group('HealthyPullbackToMa10Rule', () {
    const rule = HealthyPullbackToMa10Rule();
    // 黃金路徑：ma10 100 > ma20 95 > ma60 90、close 100 距 ma10 0%、close > ma20、
    // past20=90 (ma10 100>94.5)、今日收黑、量縮、過去 5 日有紅 K
    const goldenInd = TechnicalIndicators(
      ma10: 100,
      ma20: 95,
      ma60: 90,
      volumeMA20: 1000,
    );
    List<DailyPriceEntry> goldenPrices() => buildPrices(
      count: 21,
      overrides: {
        0: candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90), // past20
        15: candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99), // 紅 K
        19: candle(dayIdx: 19, open: 102, high: 103, low: 101, close: 102), // 昨
        20: candle(
          dayIdx: 20,
          open: 101,
          high: 101,
          low: 99,
          close: 100,
          volume: 800,
        ), // 今日收黑 + 量縮
      },
    );

    test('fires on ideal shallow pullback to MA10', () {
      final r = rule.evaluate(ctx(goldenInd), stock(goldenPrices()));
      expect(r, isNotNull);
      expect(r!.type, ReasonType.pullbackToMa10);
      expect(r.score, 12);
    });

    test('null when close <= ma20 (deep — let MA20 rule handle)', () {
      // close=94 <= ma20=95 × 1.03（MA20 拉回帶上緣）=97.85 → 不算淺回檔
      final prices = goldenPrices();
      prices[20] = candle(
        dayIdx: 20,
        open: 95,
        high: 95,
        low: 93,
        close: 94,
        volume: 800,
      );
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    // Fix 3（High audit #3）：close 在 ma20 與「MA20 拉回帶上緣」之間（此例
    // 97 ∈ (95, 97.85]）舊版會誤放行（close > ma20 即可）、與 MA20 規則的
    // 拉回帶重疊，是 symbol 6179 2026-07-16 雙 fire 的同型態。修後應 null。
    test(
      'null when close between ma20 and MA20 band ceiling '
      '(Fix 3: was wrongly allowed pre-fix, overlapped with MA20 rule band)',
      () {
        final prices = goldenPrices();
        prices[20] = candle(
          dayIdx: 20,
          open: 98,
          high: 98,
          low: 96,
          close: 97,
          volume: 800,
        );
        expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
      },
    );

    test('null when not mid-term bull stack (ma10 <= ma20)', () {
      const ind = TechnicalIndicators(
        ma10: 95,
        ma20: 100,
        ma60: 90,
        volumeMA20: 1000,
      );
      expect(rule.evaluate(ctx(ind), stock(goldenPrices())), isNull);
    });

    test('null when too far above MA10 (> +2.5%)', () {
      // close=103 距 ma10 100 = +3% > 2.5%
      final prices = goldenPrices();
      prices[20] = candle(
        dayIdx: 20,
        open: 104,
        high: 104,
        low: 102,
        close: 103,
        volume: 800,
      );
      // close 103 > ma20 95、今日 103 < 昨 102? no → 也擋。改昨日更高確保只測距離
      prices[19] = candle(
        dayIdx: 19,
        open: 105,
        high: 106,
        low: 104,
        close: 105,
      );
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('null when today up', () {
      final prices = goldenPrices();
      prices[20] = candle(
        dayIdx: 20,
        open: 100,
        high: 101,
        low: 99,
        close: 100.5,
        volume: 800,
      );
      // 昨日 102 → 今 100.5 收黑... 改昨日 100 讓今日漲
      prices[19] = candle(dayIdx: 19, open: 99, high: 100, low: 98, close: 99);
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('null when volume not shrunk', () {
      final prices = goldenPrices();
      prices[20] = candle(
        dayIdx: 20,
        open: 101,
        high: 101,
        low: 99,
        close: 100,
        volume: 1000,
      );
      expect(rule.evaluate(ctx(goldenInd), stock(prices)), isNull);
    });

    test('null when ma10 unavailable', () {
      const ind = TechnicalIndicators(ma20: 95, ma60: 90, volumeMA20: 1000);
      expect(rule.evaluate(ctx(ind), stock(goldenPrices())), isNull);
    });
  });

  // ============================================================
  // Fix 3（High audit #3）：MA20 vs MA10 互斥性
  //
  // 審計實測：symbol 6179 於 2026-07-16 同時觸發 PULLBACK_TO_MA20（+15）與
  // PULLBACK_TO_MA10（+12），單一次回檔事件被雙重計分 +27。原因：MA10 rule
  // 舊版只要求 close > ma20，但 MA20 rule 的拉回帶上緣可達 +3%——當 ma10 與
  // ma20 僅相距 ~0-1.8%（趨勢趨緩/盤整）時，兩規則的 proximity band 在
  // close-vs-ma20 軸上會重疊，同一個 close 可以同時落入兩帶。
  // ============================================================
  group('Mutual exclusivity: MA20 vs MA10（Fix 3 — 6179 案例）', () {
    const ma20Rule = HealthyPullbackToMa20Rule();
    const ma10Rule = HealthyPullbackToMa10Rule();

    // 共用 fixture：day0=90（兩規則的過去強勢錨點皆過關）、day15 紅 K（非瀑布
    // 跌）、day19=昨收、day20=今日（依 todayClose/yesterdayClose 覆寫）。
    TechnicalIndicators sharedInd({
      required double ma5,
      required double ma10,
      required double ma20,
      required double ma60,
    }) => TechnicalIndicators(
      ma5: ma5,
      ma10: ma10,
      ma20: ma20,
      ma60: ma60,
      volumeMA20: 1000,
    );

    List<DailyPriceEntry> sharedPrices({
      required double yesterdayClose,
      required double todayClose,
    }) => buildPrices(
      count: 21,
      overrides: {
        0: candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90),
        15: candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99),
        19: candle(
          dayIdx: 19,
          open: yesterdayClose,
          high: yesterdayClose + 1,
          low: yesterdayClose - 1,
          close: yesterdayClose,
        ),
        20: candle(
          dayIdx: 20,
          open: todayClose,
          high: todayClose + 1,
          low: todayClose - 1,
          close: todayClose,
          volume: 800,
        ),
      },
    );

    test('6179 形狀：ma10 僅高於 ma20 1%、close 落在兩規則拉回帶重疊區 → 只 fire 一條', () {
      // ma20=100、ma10=101（審計「0~1.8%」重疊帶內）、close=101：
      // 距 MA20 +1%（在 [-1.5%,+3%] 帶內）、距 MA10 0%（在 [-1.5%,+2.5%] 帶
      // 內）——修前 close(101) > ma20(100) 即放行，MA10 規則會誤跟著 fire。
      final ind = sharedInd(ma5: 105, ma10: 101, ma20: 100, ma60: 95);
      final prices = sharedPrices(yesterdayClose: 103, todayClose: 101);
      final ma20Result = ma20Rule.evaluate(ctx(ind), stock(prices));
      final ma10Result = ma10Rule.evaluate(ctx(ind), stock(prices));
      expect(ma20Result, isNotNull, reason: 'MA20 規則應 fire（距 MA20 +1% 在拉回帶內）');
      expect(
        ma10Result,
        isNull,
        reason: 'MA10 規則應被排除（close 未突破 MA20 拉回帶上緣 +3%）',
      );
    });

    test('clear MA20-only：距 MA20 -1%（深回檔）→ 只 MA20 fire', () {
      final ind = sharedInd(ma5: 105, ma10: 104, ma20: 100, ma60: 95);
      final prices = sharedPrices(yesterdayClose: 100.5, todayClose: 99);
      expect(ma20Rule.evaluate(ctx(ind), stock(prices)), isNotNull);
      expect(ma10Rule.evaluate(ctx(ind), stock(prices)), isNull);
    });

    test('clear MA10-only：距 MA20 +6%（遠超帶上緣）但貼 MA10 → 只 MA10 fire', () {
      final ind = sharedInd(ma5: 110, ma10: 106, ma20: 100, ma60: 95);
      final prices = sharedPrices(yesterdayClose: 108, todayClose: 106);
      expect(ma20Rule.evaluate(ctx(ind), stock(prices)), isNull);
      expect(ma10Rule.evaluate(ctx(ind), stock(prices)), isNotNull);
    });
  });

  // ============================================================
  // KdHighLevelPullbackRule — 修正後窗口 [60,80) + prevKdK>=78 + drop<=30
  // ============================================================
  group('KdHighLevelPullbackRule (fixed window)', () {
    const rule = KdHighLevelPullbackRule();
    AnalysisContext kdCtx({
      double? kdK,
      double? kdD,
      double? prevKdK,
      double ma20 = 100,
      double ma60 = 95,
      double close = 100,
    }) => AnalysisContext(
      trendState: TrendState.up,
      evaluationTime: DateTime(2026, 1, 22),
      indicators: TechnicalIndicators(
        kdK: kdK,
        kdD: kdD,
        prevKdK: prevKdK,
        ma20: ma20,
        ma60: ma60,
      ),
    );
    List<DailyPriceEntry> closeAt(double c) {
      final p = buildPrices(count: 21);
      // Fix 1: 過去強勢 baseline（past close=90、ma20 預設 100 → 100>90*1.05=94.5）
      p[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // Fix 2: 過去 5 日內至少 1 根紅 K（非瀑布跌）
      p[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      p[20] = candle(dayIdx: 20, open: c, high: c + 1, low: c - 1, close: c);
      return p;
    }

    test('fires on ideal KD pullback (prevK=85, K=70, K>D)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 70, kdD: 65, prevKdK: 85),
        stock(closeAt(100)),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.kdHighPullback);
      expect(r.score, 12);
    });

    // 2026-08-15 審計後修:KD 是四胞胎中唯一漏抄 minHistoryDays guard 的,
    // 但實測被 Step 4 完全遮蔽(wasStrongOverPeriod 需 21 根、20 根必 false)
    // ——無行為後果。本測試是**特徵化測試**:釘住「短歷史必拒絕」契約,
    // 無論哪一步在擋;prologue 抽共用時這條保證重構不破壞拒絕行為
    test('null when history < minHistoryDays (特徵化:短歷史必拒絕)', () {
      final p = buildPrices(count: PullbackParams.minHistoryDays - 1);
      p[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      p[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      p[19] = candle(dayIdx: 19, open: 100, high: 101, low: 99, close: 100);
      final r = rule.evaluate(kdCtx(kdK: 70, kdD: 65, prevKdK: 85), stock(p));
      expect(r, isNull, reason: '20 根 < minHistoryDays 21,必須拒絕評估');
    });

    // Fix 1（Critical audit #1）：KD 規則是四條 pullback rule 中唯一沒 call
    // wasStrongOverPeriod 的——手足 MA20/MA10/Hammer 都強制這關。實測 13 檔真
    // 實 KD_HIGH_PULLBACK fire 中 9 檔（2006/2845/2867/5871/9921/3005/2637/
    // 2520/5351，~70-77%）過去 20 日根本不算強勢，只有 2332 明確過關。
    test('null when NOT strong over past 20d '
        '(audit: KD rule was missing wasStrongOverPeriod gate)', () {
      // KD 條件全數合格，但 past close=99、ma20=100 → 100 !> 99*1.05=103.95
      // → 過去 20 日不算強勢，理應 null（修前會誤 fire）。
      final p = buildPrices(count: 21);
      p[0] = candle(dayIdx: 0, open: 99, high: 100, low: 98, close: 99);
      p[20] = candle(dayIdx: 20, open: 100, high: 101, low: 99, close: 100);
      final r = rule.evaluate(kdCtx(kdK: 70, kdD: 65, prevKdK: 85), stock(p));
      expect(r, isNull);
    });

    test(
      'fires when genuinely strong over past 20d (was-strong gate passes)',
      () {
        // past close=90、ma20=100 → 100 > 90*1.05=94.5 → 過去 20 日確實強勢。
        final p = buildPrices(count: 21);
        p[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
        p[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
        p[20] = candle(dayIdx: 20, open: 100, high: 101, low: 99, close: 100);
        final r = rule.evaluate(kdCtx(kdK: 70, kdD: 65, prevKdK: 85), stock(p));
        expect(r, isNotNull);
        expect(r!.type, ReasonType.kdHighPullback);
      },
    );

    // Fix 2（Critical audit #2）：KdHighLevelPullbackRule 也沒 call
    // hasRecentBullishCandle——只有 MA20/MA10 兩條 rule 有這關。KD 條件全數
    // 合格但過去 5 日連續收黑（瀑布跌）時理應 null，修前會誤 fire。
    test('null on cascading decline (no bullish candle in past 5d)', () {
      final p = closeAt(100);
      p[15] = candle(dayIdx: 15, open: 113, high: 113, low: 110, close: 110);
      p[16] = candle(dayIdx: 16, open: 110, high: 110, low: 107, close: 107);
      p[17] = candle(dayIdx: 17, open: 107, high: 107, low: 104, close: 104);
      p[18] = candle(dayIdx: 18, open: 104, high: 104, low: 101, close: 101);
      p[19] = candle(dayIdx: 19, open: 101, high: 101, low: 99, close: 99);
      final r = rule.evaluate(kdCtx(kdK: 70, kdD: 65, prevKdK: 85), stock(p));
      expect(r, isNull);
    });

    test('fires at window low boundary K=60 (inclusive)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 60, kdD: 55, prevKdK: 85),
        stock(closeAt(100)),
      );
      expect(r, isNotNull);
    });

    test('null below window K=59.9', () {
      final r = rule.evaluate(
        kdCtx(kdK: 59.9, kdD: 55, prevKdK: 85),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('null at/above window high K=80 (exclusive)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 80, kdD: 70, prevKdK: 90),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('fires just below window high K=79.9', () {
      final r = rule.evaluate(
        kdCtx(kdK: 79.9, kdD: 70, prevKdK: 90),
        stock(closeAt(100)),
      );
      expect(r, isNotNull);
    });

    test('null when dead cross (K <= D)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 65, kdD: 70, prevKdK: 85),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('fires at prevKdK=78 boundary (inclusive)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 70, kdD: 65, prevKdK: 78),
        stock(closeAt(100)),
      );
      expect(r, isNotNull);
    });

    test('null when prevKdK=77 (below 78)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 70, kdD: 65, prevKdK: 77),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('null when bearish MA stack (ma20 <= ma60)', () {
      final r = rule.evaluate(
        kdCtx(kdK: 70, kdD: 65, prevKdK: 85, ma20: 95, ma60: 100),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('null when close below ma20*0.99', () {
      final r = rule.evaluate(
        kdCtx(kdK: 70, kdD: 65, prevKdK: 85, ma20: 100),
        stock(closeAt(98)), // 98 < 99
      );
      expect(r, isNull);
    });

    test('null when single-day drop > 30 (panic)', () {
      // prevK=100 → K=65, drop=35 > 30
      final r = rule.evaluate(
        kdCtx(kdK: 65, kdD: 60, prevKdK: 100),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('fires at drop=30 boundary (inclusive)', () {
      // prevK=95 → K=65, drop=30
      final r = rule.evaluate(
        kdCtx(kdK: 65, kdD: 60, prevKdK: 95),
        stock(closeAt(100)),
      );
      expect(r, isNotNull);
    });

    // Extra（低風險，audit「回落」缺口）：Step 9 舊版只檢查跌幅上限
    // （<=30），未要求 kdKDailyDrop > 0——3/13 真實 KD_HIGH_PULLBACK fire
    // 樣本當日 K 其實還在上升（非回落），語意上不該算「KD 高檔回落」。
    test('null when K did not actually drop (still rising, not a pullback) '
        '(audit: 3/13 real fires had K still rising)', () {
      // prevK=78（剛達高檔門檻）、今日 K=79 反而上升：drop=78-79=-1<=0。
      final r = rule.evaluate(
        kdCtx(kdK: 79, kdD: 70, prevKdK: 78),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });

    test('fires at drop just above 0 (genuine small pullback)', () {
      // prevK=78 → K=77.9, drop=0.1 > 0
      final r = rule.evaluate(
        kdCtx(kdK: 77.9, kdD: 70, prevKdK: 78),
        stock(closeAt(100)),
      );
      expect(r, isNotNull);
    });

    test('null when KD missing', () {
      final r = rule.evaluate(
        kdCtx(kdK: null, kdD: 65, prevKdK: 85),
        stock(closeAt(100)),
      );
      expect(r, isNull);
    });
  });

  // ============================================================
  // HammerAtSupportRule — 修正後 touch ±4% + close <= ma20*1.06
  // ============================================================
  group('HammerAtSupportRule (widened)', () {
    const rule = HammerAtSupportRule();
    const indGolden = TechnicalIndicators(ma20: 100, ma60: 95);

    // hammer: open=101 close=100.5 high=101 low=97（下影線 3.5 >= body 0.5*2、
    // 上影線 0 <= body 0.5*0.5、body 0.5 >= range 4*0.05）。
    // low 97 距 ma20 100 = 3% ≤ 4%；close 100.5 ≤ ma20*1.06=106；過去強勢 past20=90。
    List<DailyPriceEntry> hammerPrices({
      double low = 97,
      double close = 100.5,
    }) {
      final p = buildPrices(count: 21);
      p[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // Fix 2: 過去 5 日內至少 1 根紅 K（非瀑布跌）
      p[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      p[20] = candle(
        dayIdx: 20,
        open: 101,
        high: 101,
        low: low,
        close: close,
        volume: 1000,
      );
      return p;
    }

    test('fires hammer at MA20 support within ±4%', () {
      final r = rule.evaluate(ctx(indGolden), stock(hammerPrices()));
      expect(r, isNotNull);
      expect(r!.type, ReasonType.hammerAtSupport);
      expect(r.score, 18);
    });

    // Fix 2（Critical audit #2）：HammerAtSupportRule 沒 call
    // hasRecentBullishCandle——只有 MA20/MA10 兩條 rule 有這關。實測案例：
    // symbol 1310 2026-07-15 在連 5 黑（累積 -12.3%）瀑布跌後仍觸發
    // HAMMER_AT_SUPPORT，正是這個 guard 的 doc 明文要擋的情境。
    test(
      'null on cascading decline (no bullish candle in past 5d) '
      '(audit: symbol 1310 2026-07-15 fired after -12.3% waterfall decline)',
      () {
        final p = hammerPrices();
        // 模擬瀑布跌：過去 5 日連續收黑、累積跌幅 ~-12%
        p[15] = candle(dayIdx: 15, open: 113, high: 113, low: 110, close: 110);
        p[16] = candle(dayIdx: 16, open: 110, high: 110, low: 107, close: 107);
        p[17] = candle(dayIdx: 17, open: 107, high: 107, low: 104, close: 104);
        p[18] = candle(dayIdx: 18, open: 104, high: 104, low: 101, close: 101);
        p[19] = candle(dayIdx: 19, open: 101, high: 101, low: 99, close: 99);
        expect(rule.evaluate(ctx(indGolden), stock(p)), isNull);
      },
    );

    test('null when low away from support (> 4%)', () {
      // low=94 距 ma20 100 = 6% > 4%；同時也離 ma60 95 = 1.05% ≤4% → 改 ma60 也遠
      final p = hammerPrices(low: 80); // 遠離 MA20(100) 與 MA60(95)
      // 重建 hammer 形狀但 low 太遠：open=101 close=100.5 high=101 low=80
      expect(rule.evaluate(ctx(indGolden), stock(p)), isNull);
    });

    test('null when bearish MA stack (ma20 <= ma60)', () {
      const ind = TechnicalIndicators(ma20: 95, ma60: 100);
      expect(rule.evaluate(ctx(ind), stock(hammerPrices())), isNull);
    });

    test('null when not strong over past 20d', () {
      final p = hammerPrices();
      p[0] = candle(dayIdx: 0, open: 99, high: 100, low: 98, close: 99);
      expect(rule.evaluate(ctx(indGolden), stock(p)), isNull);
    });

    test('null when not hammer shape (long upper shadow)', () {
      final p = buildPrices(count: 21);
      p[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // 倒錘子：上影線長
      p[20] = candle(
        dayIdx: 20,
        open: 100,
        high: 105,
        low: 99.5,
        close: 100.5,
        volume: 1000,
      );
      expect(rule.evaluate(ctx(indGolden), stock(p)), isNull);
    });

    test('null when close in high zone (> ma20*1.06)', () {
      // close=107 > 106；但要維持 hammer 形狀
      final p = buildPrices(count: 21);
      p[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      p[20] = candle(
        dayIdx: 20,
        open: 107.5,
        high: 107.5,
        low: 103,
        close: 107,
        volume: 1000,
      );
      expect(rule.evaluate(ctx(indGolden), stock(p)), isNull);
    });

    test('null on limit-down day', () {
      final p = hammerPrices();
      // yesterday=100 (baseline) → today close 89 = -11%
      p[19] = candle(dayIdx: 19, open: 100, high: 101, low: 99, close: 100);
      p[20] = candle(
        dayIdx: 20,
        open: 92,
        high: 92,
        low: 88,
        close: 89,
        volume: 1000,
      );
      expect(rule.evaluate(ctx(indGolden), stock(p)), isNull);
    });
  });

  // ============================================================
  // ETF guard — 四條回檔規則對 ETF（00 開頭）一律不觸發
  //
  // 2026-06-20 mode tab 全濾 ETF 的判斷（「ETF 走勢平滑、淺回檔幾乎
  // 天天成立 = 雜訊」）下放到 rule 層源頭：假訊號不再灌分數（掃描頁
  // 訊號區曾有 9 檔 ETF 靠 pullback 訊號進入）、校準樣本不再被污染。
  // ============================================================
  group('Regime gate（大盤非上升趨勢一律 null）', () {
    // 2026-07-10 回放分段實證：回檔進場 edge 幾乎全來自多頭 regime
    // （MA20 60D 均報酬 多頭 +6.47% vs 空頭 -0.65%、各 ~4K 樣本）。
    AnalysisContext regimeCtx(TechnicalIndicators ind, bool? uptrend) =>
        AnalysisContext(
          trendState: TrendState.up,
          evaluationTime: DateTime(2026, 1, 22),
          indicators: ind,
          isMarketUptrend: uptrend,
        );

    const ma20Ind = TechnicalIndicators(
      ma5: 105,
      ma20: 100,
      ma60: 95,
      volumeMA20: 1000,
    );
    List<DailyPriceEntry> ma20Golden() => buildPrices(
      count: 21,
      overrides: {
        0: candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90),
        15: candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99),
        19: candle(dayIdx: 19, open: 102, high: 103, low: 101, close: 102),
        20: candle(
          dayIdx: 20,
          open: 101,
          high: 101,
          low: 99,
          close: 100,
          volume: 800,
        ),
      },
    );

    test('空頭 regime 時四條回檔規則不觸發', () {
      const rule = HealthyPullbackToMa20Rule();
      // sanity：多頭 regime 同 setup 會 fire
      expect(
        rule.evaluate(regimeCtx(ma20Ind, true), stock(ma20Golden())),
        isNotNull,
      );
      expect(
        rule.evaluate(regimeCtx(ma20Ind, false), stock(ma20Golden())),
        isNull,
      );
    });

    test('regime 未知（null）不擋——permissive 語意', () {
      const rule = HealthyPullbackToMa20Rule();
      expect(
        rule.evaluate(regimeCtx(ma20Ind, null), stock(ma20Golden())),
        isNotNull,
      );
    });

    test('MA10/Hammer/KD 三條同樣被空頭 regime 擋下', () {
      // MA10
      const ma10Rule = HealthyPullbackToMa10Rule();
      const ma10Ind = TechnicalIndicators(
        ma10: 100,
        ma20: 95,
        ma60: 90,
        volumeMA20: 1000,
      );
      expect(
        ma10Rule.evaluate(regimeCtx(ma10Ind, false), stock(ma20Golden())),
        isNull,
      );
      // Hammer
      const hammerRule = HammerAtSupportRule();
      const hammerInd = TechnicalIndicators(ma20: 100, ma60: 95);
      final hp = buildPrices(count: 21);
      hp[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // Fix 2: 過去 5 日內至少 1 根紅 K（非瀑布跌）
      hp[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      hp[20] = candle(
        dayIdx: 20,
        open: 101,
        high: 101,
        low: 97,
        close: 100.5,
        volume: 1000,
      );
      expect(
        hammerRule.evaluate(regimeCtx(hammerInd, true), stock(hp)),
        isNotNull,
      );
      expect(
        hammerRule.evaluate(regimeCtx(hammerInd, false), stock(hp)),
        isNull,
      );
      // KD
      const kdRule = KdHighLevelPullbackRule();
      const kdInd = TechnicalIndicators(
        kdK: 70,
        kdD: 65,
        prevKdK: 85,
        ma20: 100,
        ma60: 95,
      );
      final kp = buildPrices(count: 21);
      // Fix 1: 過去強勢 baseline，見 KdHighLevelPullbackRule group 內 closeAt()
      kp[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // Fix 2: 過去 5 日內至少 1 根紅 K（非瀑布跌）
      kp[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      kp[20] = candle(dayIdx: 20, open: 100, high: 101, low: 99, close: 100);
      expect(kdRule.evaluate(regimeCtx(kdInd, true), stock(kp)), isNotNull);
      expect(kdRule.evaluate(regimeCtx(kdInd, false), stock(kp)), isNull);
    });
  });

  group('ETF guard（00 開頭代碼一律 null）', () {
    StockData etf(List<DailyPriceEntry> prices) =>
        StockData(symbol: '00878', prices: prices);

    test('HealthyPullbackToMa20Rule 對 ETF 不觸發（同 setup 個股會 fire）', () {
      const rule = HealthyPullbackToMa20Rule();
      const ind = TechnicalIndicators(
        ma5: 105,
        ma20: 100,
        ma60: 95,
        volumeMA20: 1000,
      );
      final prices = buildPrices(
        count: 21,
        overrides: {
          0: candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90),
          15: candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99),
          19: candle(dayIdx: 19, open: 102, high: 103, low: 101, close: 102),
          20: candle(
            dayIdx: 20,
            open: 101,
            high: 101,
            low: 99,
            close: 100,
            volume: 800,
          ),
        },
      );
      // sanity：同 setup 個股確實 fire（測試有區分力）
      expect(rule.evaluate(ctx(ind), stock(prices)), isNotNull);
      expect(rule.evaluate(ctx(ind), etf(prices)), isNull);
    });

    test('HealthyPullbackToMa10Rule 對 ETF 不觸發', () {
      const rule = HealthyPullbackToMa10Rule();
      const ind = TechnicalIndicators(
        ma10: 100,
        ma20: 95,
        ma60: 90,
        volumeMA20: 1000,
      );
      final prices = buildPrices(
        count: 21,
        overrides: {
          0: candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90),
          15: candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99),
          19: candle(dayIdx: 19, open: 102, high: 103, low: 101, close: 102),
          20: candle(
            dayIdx: 20,
            open: 101,
            high: 101,
            low: 99,
            close: 100,
            volume: 800,
          ),
        },
      );
      expect(rule.evaluate(ctx(ind), stock(prices)), isNotNull);
      expect(rule.evaluate(ctx(ind), etf(prices)), isNull);
    });

    test('HammerAtSupportRule 對 ETF 不觸發', () {
      const rule = HammerAtSupportRule();
      const ind = TechnicalIndicators(ma20: 100, ma60: 95);
      final prices = buildPrices(count: 21);
      prices[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // Fix 2: 過去 5 日內至少 1 根紅 K（非瀑布跌）
      prices[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      prices[20] = candle(
        dayIdx: 20,
        open: 101,
        high: 101,
        low: 97,
        close: 100.5,
        volume: 1000,
      );
      expect(rule.evaluate(ctx(ind), stock(prices)), isNotNull);
      expect(rule.evaluate(ctx(ind), etf(prices)), isNull);
    });

    test('KdHighLevelPullbackRule 對 ETF 不觸發', () {
      const rule = KdHighLevelPullbackRule();
      final kdCtx = AnalysisContext(
        trendState: TrendState.up,
        evaluationTime: DateTime(2026, 1, 22),
        indicators: const TechnicalIndicators(
          kdK: 70,
          kdD: 65,
          prevKdK: 85,
          ma20: 100,
          ma60: 95,
        ),
      );
      final prices = buildPrices(count: 21);
      // Fix 1: 過去強勢 baseline，見 KdHighLevelPullbackRule group 內 closeAt()
      prices[0] = candle(dayIdx: 0, open: 90, high: 91, low: 89, close: 90);
      // Fix 2: 過去 5 日內至少 1 根紅 K（非瀑布跌）
      prices[15] = candle(dayIdx: 15, open: 98, high: 100, low: 97, close: 99);
      prices[20] = candle(
        dayIdx: 20,
        open: 100,
        high: 101,
        low: 99,
        close: 100,
      );
      expect(rule.evaluate(kdCtx, stock(prices)), isNotNull);
      expect(rule.evaluate(kdCtx, etf(prices)), isNull);
    });
  });
}

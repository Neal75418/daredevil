// 重複計分修正(2026-08-15 數值稽核)
//
// 三對規則讀同一個量測、門檻是包含關係,必然同時觸發 → 同一件事被算兩次。
// DB 實證共現率:FOREIGN_EXODUS×DECREASING 52/52=100%、
// PATTERN_DOJI×RSI_EXTREME_OVERSOLD 37/37=100%、
// HAMMER_AT_SUPPORT×PULLBACK_TO_MA20 3/13=23%。
//
// 修法**刻意分兩種**:
// - 負分對(外資)走**條件互斥**——mutex 取「分數最高」,對負分會選中扣得
//   最少的那條(−12 勝過 −20),方向相反;且沿用專案 2026-07-18 修
//   PULLBACK_MA10×MA20 的既有慣例。
// - 正分對走 **mutex group**——取分數最高即為「保留最強證據」,語意正確。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/triggered_reason.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/extended_market_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

AnalysisContext ctxWithForeignChange(double change) => AnalysisContext(
  trendState: TrendState.up,
  evaluationTime: DateTime(2026, 8, 14),
  marketData: MarketDataContext(foreignSharesRatioChange: change),
);

StockData get emptyStock =>
    const StockData(symbol: '1111', prices: <DailyPriceEntry>[]);

void main() {
  group('外資減持:EXODUS 與 DECREASING 不得同時觸發(負分→條件互斥)', () {
    const decreasing = ForeignShareholdingDecreasingRule();

    test('🚨 跌破 EXODUS 門檻時,DECREASING 必須讓位(否則同一量測扣兩次)', () {
      // −2.5% 同時滿足 EXODUS(≤−2.0)與舊 DECREASING(≤−0.5)
      final r = decreasing.evaluate(ctxWithForeignChange(-2.5), emptyStock);
      expect(r, isNull, reason: '該區間由 EXODUS(−20)代表;兩條都觸發等於扣 −32');
    });

    test('EXODUS 門檻以內仍由 DECREASING 負責(不留空窗)', () {
      final r = decreasing.evaluate(ctxWithForeignChange(-1.0), emptyStock);
      expect(r, isNotNull, reason: '−0.5 ~ −2.0 這段必須有人守,否則修出漏洞');
      expect(r!.type, ReasonType.foreignShareholdingDecreasing);
    });

    test('邊界:恰在 EXODUS 門檻上由 EXODUS 接手', () {
      final atThreshold = FundamentalParams.foreignExodusThreshold; // -2.0
      expect(
        decreasing.evaluate(ctxWithForeignChange(atThreshold), emptyStock),
        isNull,
      );
      // 略高於門檻(未達 EXODUS)仍歸 DECREASING
      expect(
        decreasing.evaluate(
          ctxWithForeignChange(atThreshold + 0.1),
          emptyStock,
        ),
        isNotNull,
      );
    });
  });

  group('正分對:mutex group 保留最強證據', () {
    final engine = RuleEngine();

    TriggeredReason reason(ReasonType t, int score) => TriggeredReason(
      type: t,
      score: score,
      description: 'x',
      evidence: const {},
    );

    test('🚨 十字線與極度超賣同時觸發 → 只計一次(同一現象)', () {
      // DojiRule 的多方分支本身要求 rsi <= 30,是 RSI_EXTREME_OVERSOLD 的子集
      final kept = engine.applyMutexGroups([
        reason(ReasonType.patternDoji, 10),
        reason(ReasonType.rsiExtremeOversold, 10),
      ], (r) => r.score);
      expect(kept, hasLength(1), reason: '「RSI≤30+小十字線」不該貢獻 +20');
    });

    test('🚨 錘子支撐與回檔 MA20 同時觸發 → 只計最強那條', () {
      final kept = engine.applyMutexGroups([
        reason(ReasonType.hammerAtSupport, 18),
        reason(ReasonType.pullbackToMa20, 15),
      ], (r) => r.score);
      expect(kept, hasLength(1));
      expect(kept.first.type, ReasonType.hammerAtSupport, reason: '保留較強證據');
    });

    test('不同家族不得被誤併(mutex 只收語意重疊者)', () {
      final kept = engine.applyMutexGroups([
        reason(ReasonType.patternDoji, 10),
        reason(ReasonType.kdGoldenCross, 12),
      ], (r) => r.score);
      expect(kept, hasLength(2), reason: 'KD 與 K 線形態是不同訊號家族');
    });
  });
}

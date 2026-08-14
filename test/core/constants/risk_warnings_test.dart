import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/risk_warnings.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';

void main() {
  group('RiskWarnings 集合界定', () {
    test('severe / moderate 無交集', () {
      expect(
        RiskWarnings.severe.intersection(RiskWarnings.moderate),
        isEmpty,
        reason: '同一警訊不能既嚴重又中度',
      );
    });

    test('severe 7 條、moderate 20 條、all = 聯集 27 條', () {
      expect(RiskWarnings.severe, hasLength(7));
      expect(RiskWarnings.moderate, hasLength(20));
      expect(RiskWarnings.all, hasLength(27));
      expect(
        RiskWarnings.all,
        equals({...RiskWarnings.severe, ...RiskWarnings.moderate}),
      );
    });

    test('INVARIANT: 所有 warning-class 訊號都必須是 neutral（不可從 A/B/C route）', () {
      for (final w in RiskWarnings.all) {
        expect(
          w.scoringMode,
          ScoringMode.neutral,
          reason:
              '$w 是警訊徽章成員、但 scoringMode 非 neutral — 會造成它'
              '同時 route 股票又當警訊、語意矛盾',
        );
      }
    });
  });

  group('severityOf — 代表性分級', () {
    test('嚴重類回 severe', () {
      for (final w in [
        ReasonType.tradingWarningDisposal,
        ReasonType.highPledgeRatio,
        ReasonType.maAlignmentBearish,
        ReasonType.techBreakdown,
        ReasonType.foreignExodus,
      ]) {
        expect(RiskWarnings.severityOf(w), RiskSeverity.severe, reason: '$w');
      }
    });

    test('中度類回 moderate', () {
      for (final w in [
        ReasonType.kdDeathCross,
        ReasonType.patternThreeBlackCrows,
        ReasonType.rsiExtremeOverbought,
      ]) {
        expect(RiskWarnings.severityOf(w), RiskSeverity.moderate, reason: '$w');
      }
    });

    test('注意股降級 → moderate（非 severe，避免紅海稀釋）', () {
      // 注意股是最輕監管旗標、單日 fire 53 檔；當 severe 會淹沒稀有的處置股
      expect(
        RiskWarnings.severityOf(ReasonType.tradingWarningAttention),
        RiskSeverity.moderate,
      );
    });

    test('dayTradingHigh 非負分、但語意警訊 → 強制 moderate', () {
      // 守護「不能用負分界定」的鐵律。
      // 2026-07-18 由 +12 demote 至 0（實證：50-70% 是 1D 最差 bucket、
      // excess −0.495%、勝率 37.4%），但「非負分卻是警訊」的前提不變 —— 0 分
      // 同樣選不到，仍必須靠 allowlist 強制納入。
      expect(ReasonType.dayTradingHigh.score, greaterThanOrEqualTo(0));
      expect(
        RiskWarnings.severityOf(ReasonType.dayTradingHigh),
        RiskSeverity.moderate,
      );
    });

    test('patternDojiBearish（報告漏列、補進）→ moderate', () {
      expect(
        RiskWarnings.severityOf(ReasonType.patternDojiBearish),
        RiskSeverity.moderate,
      );
    });

    test('利多 / noise / 灰色地帶 neutral 訊號不是警訊 → null', () {
      for (final notWarning in [
        ReasonType.revenueYoySurge, // 利多 +20
        ReasonType.epsYoYSurge, // 利多 +22
        ReasonType.highDividendYield, // 利多 +18
        ReasonType.peUndervalued, // 利多 +15
        ReasonType.epsConsecutiveGrowth, // 利多 +18
        ReasonType.peOvervalued, // 灰色：強股常態、易誤殺
        ReasonType.concentrationHigh, // noise
        ReasonType.revenueNewHigh, // noise
        ReasonType.week52Low, // noise（0 fire）
      ]) {
        expect(
          RiskWarnings.severityOf(notWarning),
          isNull,
          reason: '$notWarning 不該被當風險徽章',
        );
      }
    });

    test('非 neutral 的 mode 訊號（如多頭排列 / 弱轉強）→ null', () {
      expect(RiskWarnings.severityOf(ReasonType.maAlignmentBullish), isNull);
      expect(RiskWarnings.severityOf(ReasonType.reversalW2S), isNull);
    });
  });

  group('topSeverity — 取最高嚴重度', () {
    test('含任一 severe → severe', () {
      expect(
        RiskWarnings.topSeverity([
          ReasonType.dayTradingHigh, // moderate
          ReasonType.tradingWarningDisposal, // severe
        ]),
        RiskSeverity.severe,
      );
    });

    test('只有 moderate → moderate', () {
      expect(
        RiskWarnings.topSeverity([
          ReasonType.kdDeathCross,
          ReasonType.rsiExtremeOverbought,
        ]),
        RiskSeverity.moderate,
      );
    });

    test('空集合 → null', () {
      expect(RiskWarnings.topSeverity(const []), isNull);
    });

    test('全是非警訊 → null', () {
      expect(
        RiskWarnings.topSeverity([
          ReasonType.maAlignmentBullish,
          ReasonType.week52High,
        ]),
        isNull,
      );
    });
  });
}

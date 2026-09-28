import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/services/market_reading_service.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart'
    show MarketStage;

void main() {
  group('MarketReadingService.interpretVolumePrice', () {
    // turnoverDeltaPct = (today - avg5d) / avg5d * 100；門檻 kVolumeSurgePct = 10

    test('UP & 量增 (>+10%) → positive healthyUp', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 130,
        avg5dTurnover: 100, // delta = +30%
        indexChangePercent: 1.0,
      );
      expect(r.tone, InterpretationTone.positive);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.healthyUp');
    });

    test('UP & 量縮 (<-10%) → warning weakUp', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 80,
        avg5dTurnover: 100, // delta = -20%
        indexChangePercent: 0.5,
      );
      expect(r.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.weakUp');
    });

    test('DOWN & 量增 (>+10%) → negative heavySelloff', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 150,
        avg5dTurnover: 100, // delta = +50%
        indexChangePercent: -1.2,
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.heavySelloff');
    });

    test('DOWN & 量縮 (<-10%) → neutral quietConsolidation', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 70,
        avg5dTurnover: 100, // delta = -30%
        indexChangePercent: -0.4,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(
        r.messageKey,
        'marketOverview.reading.volumePrice.quietConsolidation',
      );
    });

    test('|delta| 在門檻內 → neutral flat (UP side)', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 105,
        avg5dTurnover: 100, // delta = +5%
        indexChangePercent: 0.3,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.flat');
    });

    test('|delta| 在門檻內 → neutral flat (DOWN side)', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 95,
        avg5dTurnover: 100, // delta = -5%
        indexChangePercent: -0.3,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.flat');
    });

    test('恰在門檻 (+10%) 視為持平 (非 strictly > threshold)', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 110,
        avg5dTurnover: 100, // delta = +10% (boundary)
        indexChangePercent: 1.0,
      );
      expect(r.messageKey, 'marketOverview.reading.volumePrice.flat');
    });

    test('indexChangePercent == 0 視為非 UP (走 DOWN 分支)', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 150,
        avg5dTurnover: 100, // delta = +50%
        indexChangePercent: 0.0,
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.heavySelloff');
    });

    test('guard: avg5d == 0 → delta=0 → flat', () {
      final r = MarketReadingService.interpretVolumePrice(
        todayTurnover: 9999,
        avg5dTurnover: 0,
        indexChangePercent: 2.0,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.volumePrice.flat');
    });
  });

  group('MarketReadingService.interpretMarginLeverage', () {
    test('融資增 & UP → warning overheating', () {
      final r = MarketReadingService.interpretMarginLeverage(
        marginChange: 500,
        indexChangePercent: 1.0,
      );
      expect(r.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.marginLeverage.overheating');
    });

    test('融資減 & UP → positive healthyWashout', () {
      final r = MarketReadingService.interpretMarginLeverage(
        marginChange: -500,
        indexChangePercent: 1.0,
      );
      expect(r.tone, InterpretationTone.positive);
      expect(
        r.messageKey,
        'marketOverview.reading.marginLeverage.healthyWashout',
      );
    });

    test('融資增 & DOWN → negative trapped', () {
      final r = MarketReadingService.interpretMarginLeverage(
        marginChange: 500,
        indexChangePercent: -1.0,
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.marginLeverage.trapped');
    });

    test('融資減 & DOWN → neutral deleveraging', () {
      final r = MarketReadingService.interpretMarginLeverage(
        marginChange: -500,
        indexChangePercent: -1.0,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(
        r.messageKey,
        'marketOverview.reading.marginLeverage.deleveraging',
      );
    });

    test('融資變動 == 0 → neutral stable (不論指數方向)', () {
      final up = MarketReadingService.interpretMarginLeverage(
        marginChange: 0,
        indexChangePercent: 2.0,
      );
      expect(up.tone, InterpretationTone.neutral);
      expect(up.messageKey, 'marketOverview.reading.marginLeverage.stable');

      final down = MarketReadingService.interpretMarginLeverage(
        marginChange: 0,
        indexChangePercent: -2.0,
      );
      expect(down.messageKey, 'marketOverview.reading.marginLeverage.stable');
    });

    test('indexChangePercent == 0 視為非 UP (融資增 → trapped)', () {
      final r = MarketReadingService.interpretMarginLeverage(
        marginChange: 100,
        indexChangePercent: 0.0,
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.marginLeverage.trapped');
    });
  });

  group('MarketReadingService.interpretBreadth', () {
    // ratio = advance / (advance + decline)；門檻 0.60 / 0.40

    test('ratio > 0.60 → positive broadUp', () {
      final r = MarketReadingService.interpretBreadth(advance: 70, decline: 30);
      expect(r.tone, InterpretationTone.positive);
      expect(r.messageKey, 'marketOverview.reading.breadth.broadUp');
    });

    test('ratio < 0.40 → negative broadDown', () {
      final r = MarketReadingService.interpretBreadth(advance: 30, decline: 70);
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.breadth.broadDown');
    });

    test('0.40 <= ratio <= 0.60 → neutral mixed', () {
      final r = MarketReadingService.interpretBreadth(advance: 50, decline: 50);
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.breadth.mixed');
    });

    test('恰在 0.60 邊界 → mixed (非 strictly >)', () {
      // 60/(60+40) = 0.60
      final r = MarketReadingService.interpretBreadth(advance: 60, decline: 40);
      expect(r.messageKey, 'marketOverview.reading.breadth.mixed');
    });

    test('恰在 0.40 邊界 → mixed (非 strictly <)', () {
      // 40/(40+60) = 0.40
      final r = MarketReadingService.interpretBreadth(advance: 40, decline: 60);
      expect(r.messageKey, 'marketOverview.reading.breadth.mixed');
    });

    test('guard: denom == 0 → ratio=0.5 → mixed', () {
      final r = MarketReadingService.interpretBreadth(advance: 0, decline: 0);
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.breadth.mixed');
    });
  });

  group('MarketReadingService.interpretBreadthTrend', () {
    // threshold-free：純比較 newHighs vs newLows + 指數方向

    test('指數漲 & 新高 > 新低 → positive confirmUp', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 156,
        newLows: 29,
        indexChangePercent: 0.8,
      );
      expect(r.tone, InterpretationTone.positive);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.confirmUp');
    });

    test('指數漲 & 新低 > 新高 → warning divergence', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 20,
        newLows: 80,
        indexChangePercent: 0.5,
      );
      expect(r.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.divergence');
    });

    test('指數漲 & 新低 == 新高 → warning divergence (新低未縮)', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 40,
        newLows: 40,
        indexChangePercent: 0.3,
      );
      expect(r.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.divergence');
    });

    test('指數跌 & 新低 > 新高 → negative weakDown', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 15,
        newLows: 90,
        indexChangePercent: -1.1,
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.weakDown');
    });

    test('指數跌 & 新高 >= 新低 → neutral (else 分支)', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 60,
        newLows: 30,
        indexChangePercent: -0.4,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.neutral');
    });

    test('指數跌 & 新高 == 新低 → neutral (else 分支)', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 30,
        newLows: 30,
        indexChangePercent: -0.7,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.neutral');
    });

    test('indexChangePercent == 0 視為非 UP（新高多→走 else neutral）', () {
      final r = MarketReadingService.interpretBreadthTrend(
        newHighs: 100,
        newLows: 10,
        indexChangePercent: 0.0,
      );
      // isUp=false、newLows(10) > newHighs(100) 為 false → else neutral
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.breadthTrend.neutral');
    });
  });

  group('MarketReadingService.interpretStageBias', () {
    // 門檻 kBiasOverheatPct = 15

    test('bullish & biasMa60 > 15 → warning overheated', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bullish,
        biasMa60: 20,
      );
      expect(r, isNotNull);
      expect(r!.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.stageBias.overheated');
    });

    test('bearish & biasMa60 < -15 → positive oversold', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bearish,
        biasMa60: -20,
      );
      expect(r, isNotNull);
      expect(r!.tone, InterpretationTone.positive);
      expect(r.messageKey, 'marketOverview.reading.stageBias.oversold');
    });

    test('bullish 但乖離未達門檻 → null', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bullish,
        biasMa60: 10,
      );
      expect(r, isNull);
    });

    test('bearish 但乖離未達門檻 → null', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bearish,
        biasMa60: -10,
      );
      expect(r, isNull);
    });

    test('neutral 不論乖離大小 → null', () {
      expect(
        MarketReadingService.interpretStageBias(
          stage: MarketStage.neutral,
          biasMa60: 30,
        ),
        isNull,
      );
      expect(
        MarketReadingService.interpretStageBias(
          stage: MarketStage.neutral,
          biasMa60: -30,
        ),
        isNull,
      );
    });

    test('恰在門檻 (bullish +15) → null (非 strictly >)', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bullish,
        biasMa60: 15,
      );
      expect(r, isNull);
    });

    test('恰在門檻 (bearish -15) → null (非 strictly <)', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bearish,
        biasMa60: -15,
      );
      expect(r, isNull);
    });

    test('bullish 但負乖離 → null (方向不符)', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.bullish,
        biasMa60: -20,
      );
      expect(r, isNull);
    });

    test('insufficient stage → null', () {
      final r = MarketReadingService.interpretStageBias(
        stage: MarketStage.insufficient,
        biasMa60: 30,
      );
      expect(r, isNull);
    });
  });

  group('MarketReadingService.interpretCompositeSynthesis', () {
    // Rule 1：|index%| < kSynthesisFlatIndexPct(0.3) 且偏向家數佔比 >= kSynthesisInternalSkewRatio(0.55)
    // Rule 2：index 方向與法人合計方向相反，且 |合計| >= 市場門檻（TWSE 200億 / TPEx 30億）
    // Rule 3：其餘 → neutral

    test('指數平盤 + 下跌家數佔比 >= 55% → negative weightSupport', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.1,
        advance: 30,
        decline: 70,
        unchanged: 0,
        institutionalTotalNet: 0,
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.synthesis.weightSupport');
    });

    test('指數平盤 + 上漲家數佔比 >= 55% → positive weightPressure', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: -0.2,
        advance: 70,
        decline: 30,
        unchanged: 0,
        institutionalTotalNet: 0,
      );
      expect(r.tone, InterpretationTone.positive);
      expect(r.messageKey, 'marketOverview.reading.synthesis.weightPressure');
    });

    test('偏向佔比恰在 55% 邊界 → 觸發（inclusive >=）', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.0,
        advance: 45,
        decline: 55,
        unchanged: 0,
        institutionalTotalNet: 0,
      );
      expect(r.messageKey, 'marketOverview.reading.synthesis.weightSupport');
    });

    test('偏向佔比 54% 未達 55% 門檻 → 不觸發 rule1（無背離 → neutral）', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.1,
        advance: 46,
        decline: 54,
        unchanged: 0,
        institutionalTotalNet: 0,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });

    test('指數恰為 0.3（非 < 0.3）→ 不視為平盤，rule1 不觸發', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.3,
        advance: 30,
        decline: 70,
        unchanged: 0,
        institutionalTotalNet: 0,
      );
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });

    test('guard: advance/decline 皆為 0 → ratio 預設 0.5，不觸發 rule1', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.1,
        advance: 0,
        decline: 0,
        unchanged: 0,
        institutionalTotalNet: 0,
      );
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });

    test('指數漲 + 法人合計賣超顯著（TWSE >= 200億）→ warning divergenceSell', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 1.0,
        advance: 500,
        decline: 400,
        unchanged: 0,
        institutionalTotalNet: -25000000000, // 250億賣超
      );
      expect(r.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.synthesis.divergenceSell');
    });

    test('指數跌 + 法人合計買超顯著（TWSE >= 200億）→ warning divergenceBuy', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: -1.0,
        advance: 400,
        decline: 500,
        unchanged: 0,
        institutionalTotalNet: 25000000000, // 250億買超
      );
      expect(r.tone, InterpretationTone.warning);
      expect(r.messageKey, 'marketOverview.reading.synthesis.divergenceBuy');
    });

    test('TPEx 使用較低門檻（30億）：35億賣超即觸發背離', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.tpex,
        indexChangePercent: 1.0,
        advance: 200,
        decline: 150,
        // 35億：低於 TWSE 門檻(200億)但高於 TPEx 門檻(30億)，驗證市場別門檻
        unchanged: 0,
        institutionalTotalNet: -3500000000,
      );
      expect(r.messageKey, 'marketOverview.reading.synthesis.divergenceSell');
    });

    test('金額恰在 TWSE 門檻（200億）→ 觸發（inclusive >=）', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 1.0,
        advance: 500,
        decline: 400,
        unchanged: 0,
        institutionalTotalNet: -20000000000,
      );
      expect(r.messageKey, 'marketOverview.reading.synthesis.divergenceSell');
    });

    test('金額差 1 元未達 TWSE 門檻 → 不觸發（neutral）', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 1.0,
        advance: 500,
        decline: 400,
        unchanged: 0,
        institutionalTotalNet: -19999999999,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });

    test('方向一致（不背離）：指數漲 + 法人也買超巨額 → neutral', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 1.0,
        advance: 500,
        decline: 400,
        unchanged: 0,
        institutionalTotalNet: 25000000000,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });

    test('indexChangePercent == 0 時無方向可背離，法人巨額也不觸發 rule2', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.0,
        advance: 50,
        decline: 50,
        unchanged: 0,
        institutionalTotalNet: 99000000000,
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });

    test('rule1 優先於 rule2：兩者條件同時成立時取 rule1', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.2, // flat（< 0.3）且為正
        advance: 30,
        decline: 70, // 下跌佔比 70% >= 55%
        unchanged: 0,
        institutionalTotalNet: -25000000000, // 亦滿足 rule2 背離金額
      );
      expect(r.tone, InterpretationTone.negative);
      expect(r.messageKey, 'marketOverview.reading.synthesis.weightSupport');
    });

    test('背離方向正確但金額不顯著 → neutral（非佔比不足，是金額不足）', () {
      final r = MarketReadingService.interpretCompositeSynthesis(
        market: MarketCode.twse,
        indexChangePercent: 0.5,
        advance: 520,
        decline: 480,
        unchanged: 0,
        institutionalTotalNet: -1000000000, // 方向背離但僅 10 億，遠低於門檻
      );
      expect(r.tone, InterpretationTone.neutral);
      expect(r.messageKey, 'marketOverview.reading.synthesis.neutral');
    });
  });

  group(
    'MarketReadingService.interpretCompositeSynthesis — 極端日 Rule 0（最高優先）',
    () {
      // Rule 0：|index%| >= kSynthesisExtremeDayPct(3.0) → 最高優先，蓋過 rule 1/2/3。
      // 若同時符合既有 rule2 法人背離條件（方向相反 + 金額達市場門檻），附加背離附註。

      test('(a) -6.47% 崩盤 + 55% 個股下跌 + 法人同向賣超 → extremeDown（無背離附註）', () {
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: -6.47,
          advance: 45,
          decline: 55,
          unchanged: 0,
          institutionalTotalNet: -8000000000, // 80億賣超，與指數同向（非背離）
        );
        expect(r.tone, InterpretationTone.negative);
        expect(r.messageKey, 'marketOverview.reading.synthesis.extremeDown');
        expect(r.args, {'pct': '6.47', 'breadthPct': '55'});
      });

      test(
        '(b) -7.02% 崩盤 + 法人逆向買超達 TPEx 門檻 → extremeDownDivergence（附背離附註）',
        () {
          final r = MarketReadingService.interpretCompositeSynthesis(
            market: MarketCode.tpex,
            indexChangePercent: -7.02,
            advance: 30,
            decline: 70,
            unchanged: 0,
            institutionalTotalNet: 3500000000, // 35億買超，>= TPEx 門檻(30億)，與指數反向
          );
          expect(r.tone, InterpretationTone.negative);
          expect(
            r.messageKey,
            'marketOverview.reading.synthesis.extremeDownDivergence',
          );
          expect(r.args, {'pct': '7.02', 'breadthPct': '70'});
          expect(r.amountArgs, {'netAmount': 3500000000});
        },
      );

      test('(c) +3.5% 暴漲（對稱）→ extremeUp（無背離附註）', () {
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: 3.5,
          advance: 70,
          decline: 30,
          unchanged: 0,
          institutionalTotalNet: 0,
        );
        expect(r.tone, InterpretationTone.warning);
        expect(r.messageKey, 'marketOverview.reading.synthesis.extremeUp');
        expect(r.args, {'pct': '3.50', 'breadthPct': '70'});
      });

      test('(d) 邊界 -2.99%（未達 3% 門檻）→ 不觸發 rule0，落回既有 rule2 divergenceBuy', () {
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: -2.99,
          advance: 400,
          decline: 500,
          unchanged: 0,
          institutionalTotalNet: 25000000000, // 250億買超 >= TWSE 門檻(200億)
        );
        expect(r.tone, InterpretationTone.warning);
        expect(r.messageKey, 'marketOverview.reading.synthesis.divergenceBuy');
      });

      test('(e) 恰為 -3.00%（inclusive >=）→ 觸發 extremeDown', () {
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: -3.00,
          advance: 45,
          decline: 55,
          unchanged: 0,
          institutionalTotalNet: 0,
        );
        expect(r.tone, InterpretationTone.negative);
        expect(r.messageKey, 'marketOverview.reading.synthesis.extremeDown');
        expect(r.args, {'pct': '3.00', 'breadthPct': '55'});
      });

      test('(f) +5.5% 暴漲 + 法人逆向賣超達 TWSE 門檻 → extremeUpDivergence（對稱覆蓋）', () {
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: 5.5,
          advance: 600,
          decline: 200,
          unchanged: 0,
          institutionalTotalNet: -22000000000, // 220億賣超，>= TWSE 門檻(200億)，與指數反向
        );
        expect(r.tone, InterpretationTone.warning);
        expect(
          r.messageKey,
          'marketOverview.reading.synthesis.extremeUpDivergence',
        );
        expect(r.args, {'pct': '5.50', 'breadthPct': '75'});
        expect(r.amountArgs, {'netAmount': 22000000000});
      });
    },
  );

  group(
    'MarketReadingService.interpretCompositeSynthesis — 顯示口徑含持平（對齊漲跌家數區）',
    () {
      // Rule 0 顯示口徑（breadthPct）：分母改含持平，對齊 AdvanceDeclineGauge
      // 的 declPct = decline/(advance+decline+unchanged)。
      // Rule 1 門檻判定（55% skew ratio）：分母維持排除持平（見下一測試），
      // 兩者刻意不同口徑，各自獨立驗證。

      test('97漲/32平/1095跌 → extreme-day breadthPct 含持平為 89%（非排除持平的 92%）', () {
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: -6.00,
          advance: 97,
          decline: 1095,
          unchanged: 32,
          institutionalTotalNet: 0,
        );
        expect(r.tone, InterpretationTone.negative);
        expect(r.messageKey, 'marketOverview.reading.synthesis.extremeDown');
        expect(r.args, {'pct': '6.00', 'breadthPct': '89'});
      });

      test('rule 1 的 55% 門檻判定分母不受 unchanged 影響（與顯示口徑各自獨立）', () {
        // 與既有「指數平盤 + 下跌家數佔比 >= 55% → weightSupport」案例相同
        // advance/decline，額外帶入大量 unchanged（900）驗證 rule 1 的門檻判定
        // 不受影響（其分母定義刻意排除持平，常數已依此口徑校準）。
        final r = MarketReadingService.interpretCompositeSynthesis(
          market: MarketCode.twse,
          indexChangePercent: 0.1,
          advance: 30,
          decline: 70,
          unchanged: 900,
          institutionalTotalNet: 0,
        );
        expect(r.tone, InterpretationTone.negative);
        expect(r.messageKey, 'marketOverview.reading.synthesis.weightSupport');
      });
    },
  );
}

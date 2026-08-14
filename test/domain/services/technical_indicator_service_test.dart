import 'dart:math';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/ohlcv_data.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  late TechnicalIndicatorService service;

  setUp(() {
    service = TechnicalIndicatorService();
  });

  // ==========================================
  // calculateSMA
  // ==========================================

  group('calculateSMA', () {
    test('calculates correct SMA values', () {
      final prices = [10.0, 20.0, 30.0, 40.0, 50.0];
      final result = service.calculateSMA(prices, 3);

      expect(result.length, equals(5));
      expect(result[0], isNull);
      expect(result[1], isNull);
      expect(result[2], closeTo(20.0, 0.001)); // (10+20+30)/3
      expect(result[3], closeTo(30.0, 0.001)); // (20+30+40)/3
      expect(result[4], closeTo(40.0, 0.001)); // (30+40+50)/3
    });

    test('returns empty list for empty input', () {
      expect(service.calculateSMA([], 3), isEmpty);
    });

    test('returns empty list for period <= 0', () {
      expect(service.calculateSMA([1.0, 2.0], 0), isEmpty);
      expect(service.calculateSMA([1.0, 2.0], -1), isEmpty);
    });

    test('returns all null when period > data length', () {
      final result = service.calculateSMA([1.0, 2.0], 5);
      expect(result.length, equals(2));
      expect(result[0], isNull);
      expect(result[1], isNull);
    });

    test('period = 1 returns each price', () {
      final prices = [5.0, 10.0, 15.0];
      final result = service.calculateSMA(prices, 1);
      expect(result, equals([5.0, 10.0, 15.0]));
    });

    test('period equals data length returns single value', () {
      final prices = [10.0, 20.0, 30.0];
      final result = service.calculateSMA(prices, 3);
      expect(result[0], isNull);
      expect(result[1], isNull);
      expect(result[2], closeTo(20.0, 0.001));
    });

    test('handles constant prices correctly', () {
      final prices = List.filled(10, 50.0);
      final result = service.calculateSMA(prices, 5);
      for (int i = 4; i < 10; i++) {
        expect(result[i], closeTo(50.0, 0.001));
      }
    });
  });

  // ==========================================
  // calculateMarketStage
  // ==========================================

  group('calculateMarketStage', () {
    test('returns insufficient when fewer than 60 valid closes', () {
      final closes = List.generate(59, (i) => 100.0 + i);
      final result = service.calculateMarketStage(closes);

      expect(result.stage, equals(MarketStage.insufficient));
      expect(result.ma60, isNull);
      expect(result.biasMa20, isNull);
    });

    test('detects bullish alignment (close > MA20 > MA60)', () {
      // 持續上升：最新收盤 > MA20 > MA60
      final closes = List.generate(80, (i) => 100.0 + i.toDouble());
      final result = service.calculateMarketStage(closes);

      expect(result.stage, equals(MarketStage.bullish));
      expect(result.ma20, isNotNull);
      expect(result.ma60, isNotNull);
      expect(result.ma20! > result.ma60!, isTrue);
      expect(result.latestClose! > result.ma20!, isTrue);
      // 上升趨勢中收盤在均線之上 → 正乖離
      expect(result.biasMa20! > 0, isTrue);
      expect(result.biasMa60! > 0, isTrue);
    });

    // 均線糾結拆狀態(2026-08-12):neutral 一律顯示「糾結」誤導——
    // 8/12 實況:TAIEX 收盤站上雙均線(+4.4%/+2.3%)但 20MA 仍在 60MA 下
    // (崩跌後修復、待黃金交叉),被標成「糾結」讀起來像盤整。
    // 拆四個子狀態,全部由既有三值(close/ma20/ma60)的相對位置決定,
    // **不引入新閾值**。
    group('neutralDetail 子狀態', () {
      test('🚨 收盤站上雙均線但 20MA<60MA → 站回均線待交叉(8/12 TAIEX 實況)', () {
        // 前 30 天 120 → 崩跌 25 天 80 → 最後 5 天 V 轉 130
        final closes = [
          ...List.filled(30, 120.0),
          ...List.filled(25, 80.0),
          ...List.filled(5, 130.0),
        ];
        final r = service.calculateMarketStage(closes);
        expect(r.stage, MarketStage.neutral);
        expect(r.latestClose! > r.ma20! && r.latestClose! > r.ma60!, isTrue);
        expect(r.ma20! < r.ma60!, isTrue, reason: '前提:20MA 尚未上穿');
        expect(r.neutralDetail, NeutralStageDetail.reclaimAwaitCross);
      });

      test('收盤跌破雙均線但 20MA>60MA → 跌破均線趨勢轉弱', () {
        final closes = [
          ...List.filled(30, 80.0),
          ...List.filled(25, 120.0),
          ...List.filled(5, 70.0),
        ];
        final r = service.calculateMarketStage(closes);
        expect(r.stage, MarketStage.neutral);
        expect(r.neutralDetail, NeutralStageDetail.breakdownWeakening);
      });

      test('🚨 收盤夾在 20MA 與 60MA 之間(20MA 在下)→ 60MA 壓力未過(8/12 櫃買實況)', () {
        // 櫃買:距 20MA +6.9%、距 60MA −2.2%
        final closes = [
          ...List.filled(30, 130.0),
          ...List.filled(25, 80.0),
          ...List.filled(5, 100.0),
        ];
        final r = service.calculateMarketStage(closes);
        expect(r.stage, MarketStage.neutral);
        expect(r.ma20! < 100 && 100 < r.ma60!, isTrue, reason: '前提:夾層');
        expect(r.neutralDetail, NeutralStageDetail.aboveShortBelowLong);
      });

      test('收盤夾在兩均線之間(20MA 在上)→ 跌破20MA、60MA 支撐之上', () {
        final closes = [
          ...List.filled(30, 70.0),
          ...List.filled(25, 120.0),
          ...List.filled(5, 100.0),
        ];
        final r = service.calculateMarketStage(closes);
        expect(r.stage, MarketStage.neutral);
        expect(r.neutralDetail, NeutralStageDetail.belowShortAboveLong);
      });

      test('🚨 等值邊界不得亂宣稱交叉:死平盤與 20MA 已在 60MA 上的 tie 案', () {
        // 審查實測抓到的兩個洞:
        // ① 死平盤 c==ma20==ma60 → 原本標「站回均線·待黃金交叉」,
        //    但「均線糾結」才是字面正確 → 應回 null 落回糾結
        final flat = service.calculateMarketStage(List.filled(60, 100.0));
        expect(flat.stage, MarketStage.neutral);
        expect(flat.neutralDetail, isNull, reason: '正在交叉點上,回 null 顯示糾結');

        // ② c==ma20 且 ma20>ma60 → 原本標「待黃金交叉」但交叉早發生了;
        //    修後不得再進 reclaimAwaitCross
        final tie = service.calculateMarketStage([
          ...List.filled(40, 90.0),
          ...List.filled(20, 110.0),
        ]);
        expect(tie.stage, MarketStage.neutral);
        expect(tie.ma20! > tie.ma60!, isTrue, reason: '前提:20MA 已在上');
        expect(
          tie.neutralDetail,
          isNot(NeutralStageDetail.reclaimAwaitCross),
          reason: '20MA 已在 60MA 上,「待黃金交叉」是錯的宣稱',
        );
      });

      test('多空排列與資料不足時為 null', () {
        final bull = service.calculateMarketStage(
          List.generate(80, (i) => 100.0 + i),
        );
        expect(bull.neutralDetail, isNull);
        final short = service.calculateMarketStage(
          List.generate(10, (i) => 100.0 + i),
        );
        expect(short.neutralDetail, isNull);
      });
    });

    test('detects bearish alignment (close < MA20 < MA60)', () {
      // 持續下降：最新收盤 < MA20 < MA60
      final closes = List.generate(80, (i) => 200.0 - i.toDouble());
      final result = service.calculateMarketStage(closes);

      expect(result.stage, equals(MarketStage.bearish));
      expect(result.ma20! < result.ma60!, isTrue);
      expect(result.latestClose! < result.ma20!, isTrue);
      // 下降趨勢中收盤在均線之下 → 負乖離
      expect(result.biasMa20! < 0, isTrue);
      expect(result.biasMa60! < 0, isTrue);
    });

    test('detects neutral when not a full alignment', () {
      // 上升後最新一根急殺，破 MA20 但 MA20 仍 > MA60 → 既非多頭也非空頭
      final closes = [
        ...List.generate(79, (i) => 100.0 + i.toDouble()),
        80.0, // 最新收盤跌破短均
      ];
      final result = service.calculateMarketStage(closes);

      expect(result.stage, equals(MarketStage.neutral));
      // MA20 > MA60（仍是上升結構）但收盤已跌破 MA20
      expect(result.ma20! > result.ma60!, isTrue);
      expect(result.latestClose! < result.ma20!, isTrue);
    });

    test('bias sign is correct for close above and below MA', () {
      // 全部相同價 → 收盤等於均線 → 乖離率為 0
      final flat = List.filled(70, 150.0);
      final flatResult = service.calculateMarketStage(flat);
      expect(flatResult.biasMa20, closeTo(0.0, 0.001));
      expect(flatResult.biasMa60, closeTo(0.0, 0.001));
    });
  });

  // ==========================================
  // calculateEMA
  // ==========================================

  group('calculateEMA', () {
    test('first EMA equals SMA', () {
      final prices = [10.0, 20.0, 30.0, 40.0, 50.0];
      final ema = service.calculateEMA(prices, 3);
      final sma = service.calculateSMA(prices, 3);

      // First non-null value should equal SMA
      expect(ema[2], closeTo(sma[2]!, 0.001));
    });

    test('returns empty list for empty input', () {
      expect(service.calculateEMA([], 3), isEmpty);
    });

    test('returns empty list for period <= 0', () {
      expect(service.calculateEMA([1.0], 0), isEmpty);
    });

    test('EMA reacts faster to recent prices', () {
      // After a jump, EMA should be closer to the new price than SMA
      final prices = [10.0, 10.0, 10.0, 10.0, 10.0, 50.0];
      final sma = service.calculateSMA(prices, 5);
      final ema = service.calculateEMA(prices, 5);

      // At index 5 (after the jump), EMA should be closer to 50 than SMA
      expect(ema[5]!, greaterThan(sma[5]!));
    });

    test('period = 1 tracks price exactly', () {
      final prices = [5.0, 10.0, 15.0];
      final result = service.calculateEMA(prices, 1);
      expect(result[0], closeTo(5.0, 0.001));
      expect(result[1], closeTo(10.0, 0.001));
      expect(result[2], closeTo(15.0, 0.001));
    });

    test('all null when period > data length', () {
      final result = service.calculateEMA([1.0, 2.0], 5);
      expect(result.length, equals(2));
      expect(result.every((v) => v == null), isTrue);
    });

    test('applies correct multiplier', () {
      final prices = [10.0, 20.0, 30.0, 40.0];
      final result = service.calculateEMA(prices, 3);
      // multiplier = 2 / (3+1) = 0.5
      // EMA[2] = SMA = (10+20+30)/3 = 20
      // EMA[3] = (40 - 20) * 0.5 + 20 = 30
      expect(result[2], closeTo(20.0, 0.001));
      expect(result[3], closeTo(30.0, 0.001));
    });
  });

  // ==========================================
  // calculateRSI
  // ==========================================

  group('calculateRSI', () {
    test('monotonically increasing prices → RSI near 100', () {
      final prices = List.generate(20, (i) => 100.0 + i * 1.0);
      final result = service.calculateRSI(prices, period: 14);

      final lastRsi = result.whereType<double>().last;
      expect(lastRsi, closeTo(100.0, 0.01));
    });

    test('monotonically decreasing prices → RSI near 0', () {
      final prices = List.generate(20, (i) => 100.0 - i * 1.0);
      final result = service.calculateRSI(prices, period: 14);

      final lastRsi = result.whereType<double>().last;
      expect(lastRsi, closeTo(0.0, 0.01));
    });

    test('flat prices → RSI = 50', () {
      final prices = List.filled(20, 100.0);
      final result = service.calculateRSI(prices, period: 14);

      final lastRsi = result.whereType<double>().last;
      // 0/0 division guard → 回傳中性 RSI 50，tolerance 放寬避免浮點誤差
      expect(lastRsi, closeTo(50.0, 0.5));
    });

    test('insufficient data returns all null', () {
      // Need period + 1 = 15 data points
      final prices = List.filled(14, 100.0);
      final result = service.calculateRSI(prices, period: 14);
      expect(result.every((v) => v == null), isTrue);
    });

    test('first period values are null', () {
      final prices = List.generate(20, (i) => 100.0 + i * 0.5);
      final result = service.calculateRSI(prices, period: 14);

      for (int i = 0; i < 14; i++) {
        expect(result[i], isNull);
      }
      expect(result[14], isNotNull);
    });

    test('custom period works correctly', () {
      final prices = List.generate(10, (i) => 100.0 + i * 1.0);
      final result = service.calculateRSI(prices, period: 5);

      // First 5 should be null
      for (int i = 0; i < 5; i++) {
        expect(result[i], isNull);
      }
      expect(result[5], isNotNull);
    });

    test('RSI stays between 0 and 100', () {
      // Random-ish prices with big swings
      final prices = [
        100.0,
        110.0,
        95.0,
        120.0,
        80.0,
        115.0,
        90.0,
        130.0,
        75.0,
        100.0,
        105.0,
        88.0,
        112.0,
        97.0,
        108.0,
        92.0,
      ];
      final result = service.calculateRSI(prices, period: 6);

      for (final rsi in result) {
        if (rsi != null) {
          expect(rsi, greaterThanOrEqualTo(0.0));
          expect(rsi, lessThanOrEqualTo(100.0));
        }
      }
    });

    test('result length matches input length', () {
      final prices = List.generate(30, (i) => 100.0 + i * 0.1);
      final result = service.calculateRSI(prices, period: 14);
      expect(result.length, equals(30));
    });

    // ----------------------------------------------------------------
    // Gap-bridging root cause: 停牌列被 extractOhlcv() 丟棄後，若不帶
    // gapBefore，相鄰陣列元素的價差會被當成單一交易日變動計算，產生
    // 虛假極端值。以下驗證 gapBefore 讓計算與 latestRSI 的缺口語意一致。
    // ----------------------------------------------------------------

    test('without gapBefore, a mid-series gap fabricates a phantom extreme RSI '
        '(documents the bug being fixed)', () {
      final oscillating = List.generate(
        20,
        (i) => 100.0 + (i.isEven ? 0.3 : -0.3),
      );
      // 停牌數日後爆量反彈（實務上是「跨數個交易日的真實累積漲幅」，
      // 但因停牌列已被丟棄，陣列上與前一筆緊鄰）
      final withJump = [...oscillating, 250.0];

      final bridged = service.calculateRSI(withJump, period: 14);

      expect(bridged.last, greaterThan(90.0));
    });

    test('gapBefore skips the delta across the gap instead of fabricating it '
        '(frozen at the pre-gap value, not the bridged spike)', () {
      final oscillating = List.generate(
        20,
        (i) => 100.0 + (i.isEven ? 0.3 : -0.3),
      );
      final withJump = [...oscillating, 250.0];
      final gapBefore = List<bool>.filled(withJump.length, false);
      gapBefore[20] = true; // 缺口在最後一筆之前

      final bridged = service.calculateRSI(withJump, period: 14);
      final gapAware = service.calculateRSI(
        withJump,
        period: 14,
        gapBefore: gapBefore,
      );

      // 跨缺口那步凍結：與缺口前一筆完全相同（未套用平滑衰減，未採計價差）
      expect(gapAware.last, equals(gapAware[19]));
      // 遠低於未修正（跨缺口誤採計）算出的虛假極端值
      expect(gapAware.last, lessThan(60.0));
      expect(gapAware.last, lessThan(bridged.last!));
    });

    test('calculateRSI(gapBefore:) matches latestRSI when replayed over the '
        'same raw DailyPriceEntry series with a mid-series gap', () {
      final now = DateTime(2026, 6, 1);
      DailyPriceEntry entryAt(int i, {double? close}) => createTestPrice(
        date: now.add(Duration(days: i)),
        close: close,
      );

      final entries = <DailyPriceEntry>[
        // 前 20 筆完整（涵蓋 seed window period=14），確保 calculateRSI
        // 的 valid-close-index seed window 與 latestRSI 的 raw-index seed
        // window 落在同一段資料上，兩者理論上應算出相同結果
        for (int i = 0; i < 20; i++)
          entryAt(i, close: 100.0 + (i.isEven ? 0.3 : -0.3)),
        // 缺口發生在 seed window 之後：兩日停牌（無成交）
        entryAt(20, close: null),
        entryAt(21, close: null),
        // 復牌後續漲
        for (int i = 22; i < 30; i++) entryAt(i, close: 100.0 + (i - 21) * 1.5),
      ];

      final ohlcv = entries.extractOhlcv();
      final gapAwareSeries = service.calculateRSI(
        ohlcv.closes,
        period: 14,
        gapBefore: ohlcv.gapBefore,
      );
      final reference = TechnicalIndicatorService.latestRSI(entries);

      expect(reference, isNotNull);
      expect(gapAwareSeries.last, closeTo(reference!, 0.0001));
    });
  });

  // ==========================================
  // calculateKD
  // ==========================================

  group('calculateKD', () {
    test('close at high → K converges toward 100 (slow stochastic)', () {
      // 使用更多資料讓 EMA 有足夠時間收斂
      final highs = List.filled(30, 110.0);
      final lows = List.filled(30, 90.0);
      final closes = List.filled(30, 110.0); // close = high → RSV = 100
      final result = service.calculateKD(highs, lows, closes, kPeriod: 9);

      // Slow stochastic 從 K₀=50 開始 EMA 平滑，RSV 持續為 100 時 K 會收斂
      final lastK = result.k.whereType<double>().last;
      expect(lastK, greaterThan(95.0)); // 充分收斂但不會精確到 100
    });

    test('close at low → K converges toward 0 (slow stochastic)', () {
      final highs = List.filled(30, 110.0);
      final lows = List.filled(30, 90.0);
      final closes = List.filled(30, 90.0); // close = low → RSV = 0
      final result = service.calculateKD(highs, lows, closes, kPeriod: 9);

      final lastK = result.k.whereType<double>().last;
      expect(lastK, lessThan(5.0)); // 充分收斂但不會精確到 0
    });

    test('range = 0 → K = 50', () {
      final prices = List.filled(12, 100.0);
      final result = service.calculateKD(prices, prices, prices, kPeriod: 9);

      final lastK = result.k.whereType<double>().last;
      expect(lastK, closeTo(50.0, 0.001));
    });

    test('D is EMA-smoothed from K (slow stochastic)', () {
      final highs = List.generate(15, (i) => 100.0 + i * 2.0);
      final lows = List.generate(15, (i) => 90.0 + i * 2.0);
      final closes = List.generate(15, (i) => 95.0 + i * 2.0);
      final result = service.calculateKD(
        highs,
        lows,
        closes,
        kPeriod: 9,
        dPeriod: 3,
      );

      // Slow stochastic: K 和 D 同時從 kPeriod-1 開始計算
      final firstKIdx = result.k.indexWhere((v) => v != null);
      final firstDIdx = result.d.indexWhere((v) => v != null);
      expect(firstKIdx, equals(firstDIdx)); // 同時開始
      // D 是 K 的 EMA，D 應落後於 K（D 較平滑）
      final lastK = result.k.whereType<double>().last;
      final lastD = result.d.whereType<double>().last;
      expect(lastD, isNotNull);
      // D 不會與 K 完全相同（除非 K 恆定）
      expect((lastK - lastD).abs(), greaterThan(0));
    });

    test('returns empty on length mismatch', () {
      final result = service.calculateKD([100.0, 110.0], [90.0], [95.0, 100.0]);
      expect(result.k, isEmpty);
      expect(result.d, isEmpty);
    });

    test('first kPeriod-1 values are null', () {
      final prices = List.filled(15, 100.0);
      final result = service.calculateKD(prices, prices, prices, kPeriod: 9);

      for (int i = 0; i < 8; i++) {
        expect(result.k[i], isNull);
      }
      expect(result.k[8], isNotNull);
    });
  });

  // ==========================================
  // calculateMACD
  // ==========================================

  group('calculateMACD', () {
    test('MACD = fastEMA - slowEMA', () {
      final prices = List.generate(40, (i) => 100.0 + i * 0.5);
      final result = service.calculateMACD(prices);
      final fastEMA = service.calculateEMA(prices, 12);
      final slowEMA = service.calculateEMA(prices, 26);

      // Check a point where both EMAs exist
      for (int i = 25; i < 40; i++) {
        if (fastEMA[i] != null &&
            slowEMA[i] != null &&
            result.macd[i] != null) {
          expect(result.macd[i], closeTo(fastEMA[i]! - slowEMA[i]!, 0.001));
        }
      }
    });

    test('insufficient data produces nulls', () {
      final prices = [10.0, 20.0, 30.0];
      final result = service.calculateMACD(prices);
      expect(result.macd.every((v) => v == null), isTrue);
    });

    test('histogram = MACD - signal', () {
      final prices = List.generate(50, (i) => 100.0 + sin(i * 0.3) * 10);
      final result = service.calculateMACD(prices);

      for (int i = 0; i < prices.length; i++) {
        if (result.macd[i] != null &&
            result.signal[i] != null &&
            result.histogram[i] != null) {
          expect(
            result.histogram[i],
            closeTo(result.macd[i]! - result.signal[i]!, 0.001),
          );
        }
      }
    });

    test('result lists have same length as input', () {
      final prices = List.generate(50, (i) => 100.0 + i * 0.1);
      final result = service.calculateMACD(prices);
      expect(result.macd.length, equals(50));
      expect(result.signal.length, equals(50));
      expect(result.histogram.length, equals(50));
    });

    test('custom periods work', () {
      final prices = List.generate(30, (i) => 100.0 + i * 0.5);
      final result = service.calculateMACD(
        prices,
        fastPeriod: 5,
        slowPeriod: 10,
        signalPeriod: 3,
      );

      // Should have non-null values earlier with shorter periods
      final firstNonNull = result.macd.indexWhere((v) => v != null);
      expect(firstNonNull, lessThan(15));
    });
  });

  // ==========================================
  // calculateBollingerBands
  // ==========================================

  group('calculateBollingerBands', () {
    test('middle band equals SMA', () {
      final prices = List.generate(25, (i) => 100.0 + i * 0.5);
      final bb = service.calculateBollingerBands(prices, period: 20);
      final sma = service.calculateSMA(prices, 20);

      for (int i = 0; i < prices.length; i++) {
        if (bb.middle[i] != null && sma[i] != null) {
          expect(bb.middle[i], closeTo(sma[i]!, 0.001));
        }
      }
    });

    test('bands are symmetric around middle', () {
      final prices = List.generate(25, (i) => 100.0 + i * 0.5);
      final bb = service.calculateBollingerBands(prices, period: 20);

      for (int i = 0; i < prices.length; i++) {
        if (bb.upper[i] != null &&
            bb.lower[i] != null &&
            bb.middle[i] != null) {
          final upperDist = bb.upper[i]! - bb.middle[i]!;
          final lowerDist = bb.middle[i]! - bb.lower[i]!;
          expect(upperDist, closeTo(lowerDist, 0.001));
        }
      }
    });

    test('flat prices → upper = lower = middle', () {
      final prices = List.filled(25, 100.0);
      final bb = service.calculateBollingerBands(prices, period: 20);

      for (int i = 19; i < 25; i++) {
        expect(bb.upper[i], closeTo(100.0, 0.001));
        expect(bb.middle[i], closeTo(100.0, 0.001));
        expect(bb.lower[i], closeTo(100.0, 0.001));
      }
    });

    test('higher volatility → wider bands', () {
      final lowVol = List.generate(
        25,
        (i) => 100.0 + (i % 2 == 0 ? 0.1 : -0.1),
      );
      final highVol = List.generate(
        25,
        (i) => 100.0 + (i % 2 == 0 ? 5.0 : -5.0),
      );

      final bbLow = service.calculateBollingerBands(lowVol, period: 20);
      final bbHigh = service.calculateBollingerBands(highVol, period: 20);

      final lowWidth = bbLow.upper[24]! - bbLow.lower[24]!;
      final highWidth = bbHigh.upper[24]! - bbHigh.lower[24]!;
      expect(highWidth, greaterThan(lowWidth));
    });

    test('insufficient data returns nulls', () {
      final prices = [10.0, 20.0, 30.0];
      final bb = service.calculateBollingerBands(prices, period: 20);
      expect(bb.upper.every((v) => v == null), isTrue);
      expect(bb.lower.every((v) => v == null), isTrue);
    });
  });

  // ==========================================
  // calculateOBV
  // ==========================================

  group('calculateOBV', () {
    test('price up → OBV increases', () {
      final closes = [100.0, 105.0];
      final volumes = [1000.0, 2000.0];
      final result = service.calculateOBV(closes, volumes);
      expect(result[1], equals(2000.0));
    });

    test('price down → OBV decreases', () {
      final closes = [100.0, 95.0];
      final volumes = [1000.0, 2000.0];
      final result = service.calculateOBV(closes, volumes);
      expect(result[1], equals(-2000.0));
    });

    test('flat price → OBV unchanged', () {
      final closes = [100.0, 100.0];
      final volumes = [1000.0, 2000.0];
      final result = service.calculateOBV(closes, volumes);
      expect(result[1], equals(0.0));
    });

    test('returns empty for empty input', () {
      expect(service.calculateOBV([], []), isEmpty);
    });

    test('returns empty on length mismatch', () {
      expect(service.calculateOBV([100.0], [1000.0, 2000.0]), isEmpty);
    });
  });

  // ==========================================
  // calculateATR
  // ==========================================

  group('calculateATR', () {
    test('first ATR is simple average of True Range', () {
      // Simple case: constant spreads
      final highs = List.filled(15, 105.0);
      final lows = List.filled(15, 95.0);
      final closes = List.filled(15, 100.0);
      final result = service.calculateATR(highs, lows, closes, period: 14);

      // TR = high - low = 10 for all days
      // First ATR = simple avg of 14 TRs = 10
      expect(result[13], closeTo(10.0, 0.001));
    });

    test('uses Wilder smoothing after first value', () {
      final highs = List.filled(20, 105.0);
      final lows = List.filled(20, 95.0);
      final closes = List.filled(20, 100.0);

      // Change the last day to have wider range
      highs[19] = 120.0;
      lows[19] = 80.0;

      final result = service.calculateATR(
        highs.toList(),
        lows.toList(),
        closes.toList(),
        period: 14,
      );

      // Last ATR should be influenced by the wider range
      // but smoothed (not equal to the raw TR of 40)
      expect(result.last!, greaterThan(10.0));
      expect(result.last!, lessThan(40.0));
    });

    test('returns empty on length mismatch', () {
      expect(service.calculateATR([100.0], [90.0, 85.0], [95.0]), isEmpty);
    });

    test('returns all null for insufficient data', () {
      final result = service.calculateATR([105.0], [95.0], [100.0], period: 14);
      expect(result.every((v) => v == null), isTrue);
    });

    test('True Range considers gap from previous close', () {
      // Day 0: close=100, Day 1: gap up, high=120, low=110, close=115
      final highs = [105.0, 120.0];
      final lows = [95.0, 110.0];
      final closes = [100.0, 115.0];

      // Can't test ATR directly with just 2 points (need period=14)
      // But we can test with period=1
      final result = service.calculateATR(highs, lows, closes, period: 1);

      // Day 0: TR = 105 - 95 = 10
      // Day 1: TR = max(120-110, |120-100|, |110-100|) = max(10, 20, 10) = 20
      expect(result[0], closeTo(10.0, 0.001));
      // Day 1 ATR = Wilder((10 * 0 + 20) / 1) but simplified with period=1:
      // first ATR = 10 (period=1, just day 0 TR)
      // Actually with period=1, index 0 is the first ATR
      // index 1 uses Wilder: (10 * 0 + 20) / 1 = 20
      expect(result[1], closeTo(20.0, 0.001));
    });
  });

  // ==========================================
  // Static methods
  // ==========================================

  group('latestSMA', () {
    test('returns correct value from DailyPriceEntry list', () {
      final prices = generateConstantPrices(days: 25, basePrice: 100.0);
      final result = TechnicalIndicatorService.latestSMA(prices, 20);
      expect(result, closeTo(100.0, 0.001));
    });

    test('returns null when insufficient data', () {
      final prices = generateFlatPrices(days: 5, basePrice: 100.0);
      expect(TechnicalIndicatorService.latestSMA(prices, 20), isNull);
    });
  });

  group('latestRSI', () {
    test('returns value for sufficient data', () {
      final prices = generateUptrendPrices(days: 30, startPrice: 100.0);
      final result = TechnicalIndicatorService.latestRSI(prices);
      expect(result, isNotNull);
      expect(result!, greaterThan(50.0)); // uptrend → RSI > 50
    });

    test('returns null when insufficient data', () {
      final prices = generateFlatPrices(days: 10, basePrice: 100.0);
      expect(TechnicalIndicatorService.latestRSI(prices), isNull);
    });
  });

  group('latestVolumeMA', () {
    test('returns correct volumeMA and todayVolume', () {
      final prices = generateConstantPrices(
        days: 25,
        basePrice: 100.0,
        volume: 500.0,
      );
      final result = TechnicalIndicatorService.latestVolumeMA(prices, 20);
      expect(result.volumeMA, closeTo(500.0, 0.001));
      expect(result.todayVolume, closeTo(500.0, 0.001));
    });

    test('returns null volumeMA when insufficient data', () {
      final prices = generateFlatPrices(days: 5, basePrice: 100.0);
      final result = TechnicalIndicatorService.latestVolumeMA(prices, 20);
      expect(result.volumeMA, isNull);
    });

    test('returns null for empty list', () {
      final result = TechnicalIndicatorService.latestVolumeMA([], 20);
      expect(result.volumeMA, isNull);
      expect(result.todayVolume, isNull);
    });

    // ----------------------------------------------------------------
    // Gap-bridging root cause: 停牌列 volume=0.0（非 null），舊邏輯僅濾
    // null 會把停牌日當成 0 成交量的有效觀測值計入分母，稀釋均量。
    // 口徑須與 volume_rules.dart 的均量計算（濾 0 + volMaMinValidDayRatio
    // 下限）一致。
    // ----------------------------------------------------------------

    test(
      'excludes zero-volume halt days from the average (fair average, not diluted)',
      () {
        final now = DateTime.now();
        // 20 筆窗口：3 筆停牌（volume=0），17 筆正常成交（volume=1000）
        // 17/20 = 85% ≥ volMaMinValidDayRatio(80%) 下限，聚焦驗證「排除 0」
        // 本身而不同時觸發下限 null（下限另有專屬測試）
        final haltIndexes = {0, 7, 14};
        final prices = List.generate(20, (i) {
          return createTestPrice(
            date: now.subtract(Duration(days: 20 - i)),
            close: 100.0,
            volume: haltIndexes.contains(i) ? 0.0 : 1000.0,
          );
        });

        final result = TechnicalIndicatorService.latestVolumeMA(prices, 20);

        // 稀釋算法會得到 17000/20 = 850；正確口徑應為 17000/17 = 1000
        expect(result.volumeMA, closeTo(1000.0, 0.001));
      },
    );

    test(
      'returns null when valid (non-zero) days fall below volMaMinValidDayRatio floor',
      () {
        final now = DateTime.now();
        // 20 筆窗口只有 10 筆有效成交（10 < 20*0.8=16 下限）
        final prices = List.generate(20, (i) {
          return createTestPrice(
            date: now.subtract(Duration(days: 20 - i)),
            close: 100.0,
            volume: i < 10 ? 0.0 : 1000.0,
          );
        });

        final result = TechnicalIndicatorService.latestVolumeMA(prices, 20);

        expect(result.volumeMA, isNull);
      },
    );

    test('returns a value when valid days exactly meet the floor ratio', () {
      final now = DateTime.now();
      // 20 筆窗口恰好 16 筆有效成交（= 20*0.8 下限，含）
      final prices = List.generate(20, (i) {
        return createTestPrice(
          date: now.subtract(Duration(days: 20 - i)),
          close: 100.0,
          volume: i < 4 ? 0.0 : 1000.0,
        );
      });

      final result = TechnicalIndicatorService.latestVolumeMA(prices, 20);

      expect(result.volumeMA, closeTo(1000.0, 0.001));
    });
  });
}

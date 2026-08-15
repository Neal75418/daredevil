import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/analysis/trend_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';

/// 45 天平盤價格，近 20 天量能為前期的 2 倍 → 通過 1.5x 量能確認
/// （前 25 天量 1000、近 20 天量 2000；close 平盤使 higherLow/lowerHigh 不獨立觸發）
List<DailyPriceEntry> volumeConfirmedPrices({double basePrice = 100}) {
  final now = DateTime.now();
  return List.generate(45, (i) {
    final recent = i >= 25;
    return createTestPrice(
      date: now.subtract(Duration(days: 45 - i - 1)),
      close: basePrice,
      volume: recent ? 2000 : 1000,
    );
  });
}

void main() {
  final service = TrendDetectionService();

  // ==========================================
  // detectTrendState
  // ==========================================
  group('detectTrendState', () {
    test('returns range when insufficient data', () {
      final prices = generateFlatPrices(
        days: RuleParams.swingWindow - 1,
        basePrice: 100,
      );
      expect(service.detectTrendState(prices), TrendState.range);
    });

    test('detects uptrend from rising prices', () {
      // 每天漲 1%，20 天 → normalizedSlope 應 > 0.08
      final prices = generateUptrendPrices(
        days: 30,
        startPrice: 100,
        dailyGain: 1.0,
      );
      expect(service.detectTrendState(prices), TrendState.up);
    });

    test('detects downtrend from falling prices', () {
      final prices = generateDowntrendPrices(
        days: 30,
        startPrice: 100,
        dailyLoss: 1.0,
      );
      expect(service.detectTrendState(prices), TrendState.down);
    });

    test('detects range for flat prices', () {
      final prices = generateFlatPrices(days: 30, basePrice: 100);
      expect(service.detectTrendState(prices), TrendState.range);
    });

    test('detects range for constant prices', () {
      // 完全固定價格，斜率為零
      final prices = generateConstantPrices(days: 30, basePrice: 100);
      expect(service.detectTrendState(prices), TrendState.range);
    });
  });

  // ==========================================
  // checkWeakToStrong
  // ==========================================
  group('checkWeakToStrong', () {
    test('returns false when trend is up', () {
      final prices = generateFlatPrices(days: 50, basePrice: 100);
      final result = service.checkWeakToStrong(
        prices,
        110.0,
        trendState: TrendState.up,
        rangeTop: 105.0,
      );
      expect(result, isFalse);
    });

    test('triggers on breakout above range top in down trend (量能確認)', () {
      final prices = volumeConfirmedPrices();
      // rangeTop=100, breakoutLevel = 100 * 1.03 = 103
      // todayClose=104 > 103 且近期量能達前期 1.5x → true
      final result = service.checkWeakToStrong(
        prices,
        104.0,
        trendState: TrendState.down,
        rangeTop: 100.0,
      );
      expect(result, isTrue);
    });

    test(
      'does not trigger breakout without volume confirmation (audit signal #4)',
      () {
        // 平盤量能（近期 == 前期）→ 未達 1.5x 量能確認 → 無量假突破不觸發
        final prices = generateFlatPrices(days: 50, basePrice: 100);
        final result = service.checkWeakToStrong(
          prices,
          104.0,
          trendState: TrendState.down,
          rangeTop: 100.0,
        );
        expect(result, isFalse);
      },
    );

    test('does not trigger when close is below breakout level', () {
      final prices = generateFlatPrices(days: 50, basePrice: 100);
      // rangeTop=100, breakoutLevel = 103, todayClose=102 < 103
      final result = service.checkWeakToStrong(
        prices,
        102.0,
        trendState: TrendState.down,
        rangeTop: 100.0,
      );
      // 仍可能因 higherLow 觸發，但 flat prices 不會
      expect(result, isFalse);
    });

    test('does not trigger higher low with insufficient data', () {
      // 需要 40 天資料才能做 higherLow 判斷
      final prices = generateFlatPrices(days: 30, basePrice: 100);
      final result = service.checkWeakToStrong(
        prices,
        100.0,
        trendState: TrendState.range,
      );
      expect(result, isFalse);
    });
  });

  // ==========================================
  // checkStrongToWeak
  // ==========================================
  group('checkStrongToWeak', () {
    test('triggers on breakdown below support (量能確認)', () {
      final prices = volumeConfirmedPrices();
      // support=100, breakdownLevel = 100 * 0.97 = 97
      // todayClose=96 < 97 且量能達 1.5x → true
      final result = service.checkStrongToWeak(
        prices,
        96.0,
        trendState: TrendState.up,
        support: 100.0,
      );
      expect(result, isTrue);
    });

    test('triggers on breakdown below range bottom (量能確認)', () {
      final prices = volumeConfirmedPrices();
      // rangeBottom=100, breakdownLevel = 97, todayClose=96
      final result = service.checkStrongToWeak(
        prices,
        96.0,
        trendState: TrendState.range,
        rangeBottom: 100.0,
      );
      expect(result, isTrue);
    });

    test(
      'does not trigger breakdown without volume confirmation (audit signal #4)',
      () {
        // 平盤量能 → 未達 1.5x 量能確認 → 無量假跌破不觸發
        final prices = generateFlatPrices(days: 50, basePrice: 100);
        final result = service.checkStrongToWeak(
          prices,
          96.0,
          trendState: TrendState.up,
          support: 100.0,
        );
        expect(result, isFalse);
      },
    );

    test(
      'does not trigger support breakdown in down trend (需原本強勢, audit signal #4)',
      () {
        // 已在下跌趨勢 → 本就弱勢、跌破支撐屬延續而非強轉弱；即使量能確認也不觸發
        final prices = volumeConfirmedPrices();
        final result = service.checkStrongToWeak(
          prices,
          96.0,
          trendState: TrendState.down,
          support: 100.0,
        );
        expect(result, isFalse);
      },
    );

    test(
      'does not trigger range bottom breakdown in down trend (audit signal #4)',
      () {
        final prices = volumeConfirmedPrices();
        final result = service.checkStrongToWeak(
          prices,
          96.0,
          trendState: TrendState.down,
          rangeBottom: 100.0,
        );
        expect(result, isFalse);
      },
    );

    test('does not trigger above breakdown level', () {
      final prices = generateFlatPrices(days: 50, basePrice: 100);
      // support=100, breakdownLevel = 97, todayClose=98 > 97
      final result = service.checkStrongToWeak(
        prices,
        98.0,
        trendState: TrendState.up,
        support: 100.0,
      );
      // 可能因 lowerHigh 觸發，但 flat prices 不會
      expect(result, isFalse);
    });

    test('does not check lower high in down trend', () {
      final prices = generateFlatPrices(days: 50, basePrice: 100);
      final result = service.checkStrongToWeak(
        prices,
        99.0,
        trendState: TrendState.down,
      );
      // down trend 不檢查 lowerHigh，且無 support/rangeBottom
      expect(result, isFalse);
    });
  });

  // ==========================================
  // x 軸壓縮(2026-08-15 數值稽核)
  // ==========================================
  //
  // 舊實作 `closes = prices.map(close).whereType<double>()` 把停牌日
  // (close=null)整個剔除,再用**陣列位置**當迴歸的 x —— 於是 20 天裡
  // 有 8 天停牌時,剩下的 12 個點被當成「連續 12 天」,斜率被放大約
  // 20/12 ≈ 1.67 倍;資料點下限 5 時可放大 4 倍。
  //
  // 而趨勢門檻是每日 0.08%,放大後會被輕易穿越 → TrendState 誤判 →
  // 連鎖影響所有讀 trendState 的規則與弱轉強/強轉弱的前置 gate。
  group('停牌日不得壓縮迴歸 x 軸', () {
    /// 20 天窗口漲 [totalPct]%,其中 [gapCount] 天停牌(close=null)。
    ///
    /// 數字刻意落在門檻兩側:trendUpThreshold = 0.08%/交易日。
    /// 20 天漲 1.0% → 每交易日 1.0/19 = 0.053% < 0.08% → 應判 range。
    /// 若 x 軸被壓縮成 12 個點 → 1.0/11 = 0.091% > 0.08% → 誤判 up。
    List<DailyPriceEntry> gapped({
      required int gapCount,
      double totalPct = 1.0,
    }) {
      final now = DateTime.now();
      return List.generate(20, (i) {
        final isGap = i > 0 && i <= gapCount;
        return createTestPrice(
          date: now.subtract(Duration(days: 20 - i)),
          close: isGap ? null : 100 * (1 + totalPct / 100 * i / 19),
          volume: 1000,
        );
      });
    }

    test('🚨 停牌天數不得改變趨勢判定(實際漲幅相同)', () {
      final noGap = service.detectTrendState(gapped(gapCount: 0));
      // gapCount=12(剩 8 個有效點)是實測的臨界:1.0/7 = 0.143% 跨過
      // 0.08% 門檻;gap≤8 時壓縮幅度還不足以改判
      final withGap = service.detectTrendState(gapped(gapCount: 12));
      expect(withGap, noGap, reason: '真實漲幅相同、只因停牌天數不同就改判 = 迴歸的 x 軸被壓縮');
    });

    test('🚨 停牌不得把「盤整」放大成「上升」', () {
      // 20 天僅漲 1.0%(每交易日 0.053%,低於 0.08% 門檻)
      expect(
        service.detectTrendState(gapped(gapCount: 12, totalPct: 1.0)),
        isNot(TrendState.up),
        reason: '壓縮後 8 個點涵蓋 20 天的漲幅,斜率被放大 2.7 倍',
      );
    });

    test('真實的上升趨勢仍要判得出來(確認不是把功能關掉)', () {
      // 20 天漲 5%(每交易日 0.26%,遠超門檻)
      expect(
        service.detectTrendState(gapped(gapCount: 0, totalPct: 5.0)),
        TrendState.up,
      );
    });
  });
}

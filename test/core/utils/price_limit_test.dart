import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/price_limit.dart';

void main() {
  group('PriceLimit', () {
    group('isLimitUp', () {
      test('return true for +10%', () {
        expect(PriceLimit.isLimitUp(10.0), isTrue);
      });

      test('return true for value within tolerance (+9.86%)', () {
        expect(PriceLimit.isLimitUp(9.86), isTrue);
      });

      test('return true at exact tolerance boundary (9.85%)', () {
        // threshold = limitPercent - _tolerance = 10.0 - 0.15 = 9.85
        expect(PriceLimit.isLimitUp(9.85), isTrue);
      });

      test('return false just below tolerance boundary (9.84%)', () {
        expect(PriceLimit.isLimitUp(9.84), isFalse);
      });

      test('return false for +9.5%', () {
        expect(PriceLimit.isLimitUp(9.5), isFalse);
      });

      test('return false for negative change', () {
        expect(PriceLimit.isLimitUp(-10.0), isFalse);
      });

      test('return false for null', () {
        expect(PriceLimit.isLimitUp(null), isFalse);
      });

      test('return true for value exceeding 10%', () {
        // 理論上不會超過 10%，但防禦性檢查
        expect(PriceLimit.isLimitUp(10.5), isTrue);
      });
    });

    group('isLimitDown', () {
      test('return true for -10%', () {
        expect(PriceLimit.isLimitDown(-10.0), isTrue);
      });

      test('return true for value within tolerance (-9.86%)', () {
        expect(PriceLimit.isLimitDown(-9.86), isTrue);
      });

      test('return true at exact tolerance boundary (-9.85%)', () {
        expect(PriceLimit.isLimitDown(-9.85), isTrue);
      });

      test('return false just below tolerance boundary (-9.84%)', () {
        expect(PriceLimit.isLimitDown(-9.84), isFalse);
      });

      test('return false for -9.5%', () {
        expect(PriceLimit.isLimitDown(-9.5), isFalse);
      });

      test('return false for positive change', () {
        expect(PriceLimit.isLimitDown(10.0), isFalse);
      });

      test('return false for null', () {
        expect(PriceLimit.isLimitDown(null), isFalse);
      });
    });
  });

  group('statusOf(畫面上所有漲跌停標示的唯一判斷)', () {
    test('盤後:以漲跌幅推算,推算不出鎖住', () {
      expect(
        PriceLimit.statusOf(changePercent: 9.85),
        PriceLimitStatus.limitUp,
      );
      expect(
        PriceLimit.statusOf(changePercent: -9.85),
        PriceLimitStatus.limitDown,
      );
      expect(PriceLimit.statusOf(changePercent: 9.84), PriceLimitStatus.none);
      expect(PriceLimit.statusOf(changePercent: null), PriceLimitStatus.none);
    });

    test('🚨 盤中有交易所漲跌停價:低價股差一檔(40→43.95,+9.875%)不判漲停', () {
      expect(
        PriceLimit.statusOf(
          changePercent: 9.875,
          price: 43.95,
          limitUp: 44.0,
          limitDown: 36.0,
        ),
        PriceLimitStatus.none,
        reason: '推算會誤判成漲停',
      );
      expect(
        PriceLimit.statusOf(
          changePercent: 10.0,
          price: 44.0,
          limitUp: 44.0,
          limitDown: 36.0,
        ),
        PriceLimitStatus.limitUp,
      );
    });

    test('🚨 鎖住加「鎖」;跌停鏡像', () {
      expect(
        PriceLimit.statusOf(
          changePercent: 10.0,
          price: 44.0,
          limitUp: 44.0,
          limitDown: 36.0,
          limitUpLocked: true,
        ),
        PriceLimitStatus.limitUpLocked,
      );
      expect(
        PriceLimit.statusOf(
          changePercent: -10.0,
          price: 36.0,
          limitUp: 44.0,
          limitDown: 36.0,
          limitDownLocked: true,
        ),
        PriceLimitStatus.limitDownLocked,
      );
      expect(PriceLimitStatus.limitUpLocked.isUp, isTrue);
      expect(PriceLimitStatus.limitDownLocked.isDown, isTrue);
      expect(PriceLimitStatus.limitUp.isLocked, isFalse);
    });
  });
}

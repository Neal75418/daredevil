// 候選流動性門檻（2026-08-29 領域稽核 C1）
//
// 曾經有兩道門檻:成交額 ≥ 3,000 萬 **且** 成交量 ≥ 100 萬股。兩者同時
// 要求,等於對股價 p 的股票要求 `量 ≥ max(100萬, 3000萬/p)`——p 超過 30 元
// 之後綁定的永遠是股數那條,於是實際的成交額門檻變成 `p × 100 萬`:
//
//      30 元 →  3,000 萬        1,000 元 → 10 億
//  15,630 元 →  156 億(信驊)
//
// 同一個「流動性」概念,門檻在不同價位差 500 倍——那不是流動性標準,是把
// 成交額門檻偷偷變成與股價成正比。實測它擋掉全庫 68.9% 的 stock-day,其中
// 25.7% 是**已經通過成交額門檻**的(2026-08-28: 2059 川湖 62 億、3653 健策
// 54 億、5274 信驊 54 億全被判 LOW_VOLUME)。
//
// 兩條成交額門檻都有實測依據寫在常數旁邊（P50、砍掉多少無效運算、誤傷多少
// 訊號股）;股數那條只有一行「1000 張」,沒有任何依據。
//
// 要不要留股數地板:實測通過 3,000 萬成交額的 236,105 筆 stock-day 裡,
// **最小成交量是 33,000 股**,10 張的地板會擋掉 0 筆——地板可證明是惰性的,
// 所以整條移除而不是調低。
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/services/liquidity_checker.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();

  DailyPriceEntry makePrice({double? close, double? volume}) {
    return DailyPriceEntry(
      symbol: 'TEST',
      date: now,
      open: close,
      high: close,
      low: close,
      close: close,
      volume: volume,
      priceChange: null,
    );
  }

  group('LiquidityChecker.checkCandidateLiquidity', () {
    test('returns null when all checks pass', () {
      // close=100, volume=2000000 → turnover=200M > 30M
      final entry = makePrice(close: 100.0, volume: 2000000);
      expect(LiquidityChecker.checkCandidateLiquidity(entry), isNull);
    });

    test('returns MISSING_DATA when close is null', () {
      final entry = makePrice(close: null, volume: 2000000);
      expect(
        LiquidityChecker.checkCandidateLiquidity(entry),
        equals('MISSING_DATA'),
      );
    });

    test('returns MISSING_DATA when volume is null', () {
      final entry = makePrice(close: 100.0, volume: null);
      expect(
        LiquidityChecker.checkCandidateLiquidity(entry),
        equals('MISSING_DATA'),
      );
    });

    test('returns MISSING_DATA when both close and volume are null', () {
      final entry = makePrice(close: null, volume: null);
      expect(
        LiquidityChecker.checkCandidateLiquidity(entry),
        equals('MISSING_DATA'),
      );
    });

    test('🚨 高價股不得因股數少而被判低流動性', () {
      // 5274 信驊 2026-08-28 實測:收 15,630、量 345,184 股 → 成交額 53.95 億
      final entry = makePrice(close: 15630.0, volume: 345184);
      expect(
        LiquidityChecker.checkCandidateLiquidity(entry),
        isNull,
        reason: '53.95 億的日成交額不是低流動性',
      );
    });

    test('🚨 成交量少但成交額足夠 → 通過（股數不再是門檻）', () {
      // 舊碼:500,000 < 1,000,000 → LOW_VOLUME
      // 實際:100 × 500,000 = 5,000 萬 ≥ 3,000 萬,流動性合格
      final entry = makePrice(close: 100.0, volume: 500000);
      expect(LiquidityChecker.checkCandidateLiquidity(entry), isNull);
    });

    test('全庫實測最小的合格量(33 張)也要通過', () {
      // 7734 高得 2026-07-01:收 3,085、量 35,000 股 → 1.08 億
      final entry = makePrice(close: 3085.0, volume: 35000);
      expect(LiquidityChecker.checkCandidateLiquidity(entry), isNull);
    });

    test('returns LOW_TURNOVER when turnover below threshold', () {
      // volume passes (1,500,000 >= 1,000,000)
      // but turnover = 10 * 1,500,000 = 15M < 30M
      final entry = makePrice(close: 10.0, volume: 1500000);
      expect(
        LiquidityChecker.checkCandidateLiquidity(entry),
        equals('LOW_TURNOVER'),
      );
    });

    test('🚨 成交額門檻與股價無關——同一成交額,任何價位都該同判', () {
      // 這條釘住移除股數門檻的**性質**:成交額固定 5,000 萬,價位從 1 元
      // 掃到 50,000 元,結論必須一致。舊碼在 p > 50 之後全部改判 LOW_VOLUME。
      for (final price in [1.0, 10.0, 50.0, 500.0, 5000.0, 50000.0]) {
        final entry = makePrice(close: price, volume: 50000000 / price);
        expect(
          LiquidityChecker.checkCandidateLiquidity(entry),
          isNull,
          reason: '收 $price 元、成交額 5,000 萬,不該被判低流動性',
        );
      }
    });

    test('passes at exact turnover threshold', () {
      // volume = 1,500,000 (passes)
      // turnover = 20 * 1,500,000 = 30M = minCandidateTurnover
      final entry = makePrice(
        close: RuleParams.minCandidateTurnover / 1500000,
        volume: 1500000,
      );
      expect(LiquidityChecker.checkCandidateLiquidity(entry), isNull);
    });

    test('真正的低流動性仍要擋下', () {
      // 收 1 元、量 100 股 → 成交額 100 元
      final entry = makePrice(close: 1.0, volume: 100);
      expect(
        LiquidityChecker.checkCandidateLiquidity(entry),
        equals('LOW_TURNOVER'),
      );
    });

    test('🚨 LOW_VOLUME 這個判定不該再出現', () {
      // 掃過整個價位 × 成交量的網格,確認沒有任何輸入會得到 LOW_VOLUME。
      // 若日後有人把股數門檻加回來,這條會轉紅。
      for (final price in [0.5, 1.0, 30.0, 100.0, 1000.0, 20000.0]) {
        for (final vol in [1.0, 1000.0, 100000.0, 999999.0, 5000000.0]) {
          expect(
            LiquidityChecker.checkCandidateLiquidity(
              makePrice(close: price, volume: vol),
            ),
            isNot('LOW_VOLUME'),
            reason: 'close=$price volume=$vol',
          );
        }
      }
    });
  });
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/localized_number_format.dart';

/// LocalizedNumberFormat.compact 的語系分級測試。
///
/// 分級與單位字都取自 CLDR(intl `NumberFormat.compact`):中文 萬/億/兆
/// (1e4/1e8/1e12)、英文 K/M/B/T(1e3/1e6/1e9/1e12)。兩種語系的進位
/// 倍數不同,只換單位字、不換倍數,英文金額就會差 10 倍(2026-09 修正前
/// 的實況:153,000,000 顯示成 1.5B)。
void main() {
  const zh = Locale('zh', 'TW');
  const en = Locale('en');

  group('LocalizedNumberFormat.compact — 中文(萬/億/兆)', () {
    test('≥1e8 用億,一位小數', () {
      expect(LocalizedNumberFormat.compact(153_000_000, zh), '1.5億');
      expect(LocalizedNumberFormat.compact(100_000_000, zh), '1.0億');
    });

    test('四捨五入跨級時進到下一級(99,999,999 → 1.0億,不是 10000.0萬)', () {
      expect(LocalizedNumberFormat.compact(99_999_999, zh), '1.0億');
    });

    test('≥1e4 用萬', () {
      expect(LocalizedNumberFormat.compact(25_000, zh), '2.5萬');
      expect(LocalizedNumberFormat.compact(10_000, zh), '1.0萬');
    });

    test('≥1e12 用兆', () {
      expect(LocalizedNumberFormat.compact(1.2e12, zh), '1.2兆');
    });

    test('<1e4 千分位整數', () {
      expect(LocalizedNumberFormat.compact(9_999, zh), '9,999');
      expect(LocalizedNumberFormat.compact(0, zh), '0');
    });

    test('負值依絕對值選單位、保留負號', () {
      expect(LocalizedNumberFormat.compact(-250_000_000, zh), '-2.5億');
      expect(LocalizedNumberFormat.compact(-25_000, zh), '-2.5萬');
      expect(LocalizedNumberFormat.compact(-999, zh), '-999');
    });
  });

  group('LocalizedNumberFormat.compact — 英文(K/M/B/T)', () {
    test('1.53 億 = 153 million,不是 1.5 billion', () {
      expect(LocalizedNumberFormat.compact(153_000_000, en), '153.0M');
    });

    test('2.5 萬 = 25 thousand,不是 2.5 thousand', () {
      expect(LocalizedNumberFormat.compact(25_000, en), '25.0K');
    });

    test('≥1e9 用 B、≥1e12 用 T', () {
      expect(LocalizedNumberFormat.compact(1_500_000_000, en), '1.5B');
      expect(LocalizedNumberFormat.compact(1.2e12, en), '1.2T');
    });

    test('K 從 1e3 起算;<1e3 整數', () {
      expect(LocalizedNumberFormat.compact(1_000, en), '1.0K');
      expect(LocalizedNumberFormat.compact(999, en), '999');
    });

    test('負值保留負號', () {
      expect(LocalizedNumberFormat.compact(-3_400_000_000, en), '-3.4B');
    });
  });

  group('LocalizedNumberFormat.compact — 非有限值', () {
    test('NaN／Infinity 顯示 --，不拋例外（intl compact 對非有限值會拋）', () {
      for (final locale in [zh, en]) {
        expect(LocalizedNumberFormat.compact(double.nan, locale), '--');
        expect(LocalizedNumberFormat.compact(double.infinity, locale), '--');
        expect(
          LocalizedNumberFormat.compact(double.negativeInfinity, locale),
          '--',
        );
      }
    });
  });

  group('LocalizedNumberFormat.compactFromThousands（財報欄位以千元儲存）', () {
    test('千元值換成元再分級:1,353,387 千元 → 13.5億 / 1.4B', () {
      // 上櫃產業 EPS、季報、月營收的金額欄位都是千元（見各 model 欄位註解）
      expect(
        LocalizedNumberFormat.compactFromThousands(1_353_387, zh),
        '13.5億',
      );
      expect(LocalizedNumberFormat.compactFromThousands(1_353_387, en), '1.4B');
    });

    test('小金額:25 千元 → 2.5萬 / 25.0K', () {
      expect(LocalizedNumberFormat.compactFromThousands(25, zh), '2.5萬');
      expect(LocalizedNumberFormat.compactFromThousands(25, en), '25.0K');
    });

    test('虧損保留負號', () {
      expect(
        LocalizedNumberFormat.compactFromThousands(-1_353_387, zh),
        '-13.5億',
      );
    });
  });
}

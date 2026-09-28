import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/localized_number_format.dart';

/// LocalizedNumberFormat.compact 的邊界測試(2026-08-01 審查補課)。
///
/// launchd 斷更修復時從 AppNumberFormat 拆出(.tr() 依賴不可進 tool
/// 純 Dart 鏈),拆檔後五個財務顯示畫面(空券排行/投組摘要/股利分析/
/// 產業 EPS/董監 tab)共用此函式卻零測試——1e8/1e4 換檔邊界錯一位,
/// 金額單位就靜默錯一級。
///
/// 測試環境未初始化 easy_localization,`.tr()` 回 key 本身
/// (unit.billion/unit.tenThousand)——斷言數字部分與單位 key,
/// 翻譯文字由 assets json 守(zh-TW=億/萬、en=B/K)。
void main() {
  group('LocalizedNumberFormat.compact', () {
    test('≥1e8 用億級單位,取一位小數', () {
      expect(LocalizedNumberFormat.compact(153_000_000), '1.5unit.billion');
      expect(LocalizedNumberFormat.compact(100_000_000), '1.0unit.billion');
    });

    test('1e8 邊界下緣(99,999,999)落萬級', () {
      expect(
        LocalizedNumberFormat.compact(99_999_999),
        '10000.0unit.tenThousand',
      );
    });

    test('≥1e4 用萬級單位', () {
      expect(LocalizedNumberFormat.compact(25_000), '2.5unit.tenThousand');
      expect(LocalizedNumberFormat.compact(10_000), '1.0unit.tenThousand');
    });

    test('<1e4 千分位整數', () {
      expect(LocalizedNumberFormat.compact(9_999), '9,999');
      expect(LocalizedNumberFormat.compact(0), '0');
    });

    test('負值依絕對值選單位、保留負號', () {
      expect(LocalizedNumberFormat.compact(-250_000_000), '-2.5unit.billion');
      expect(LocalizedNumberFormat.compact(-25_000), '-2.5unit.tenThousand');
      expect(LocalizedNumberFormat.compact(-999), '-999');
    });
  });

  group('LocalizedNumberFormat.compactFromThousands（財報欄位以千元儲存）', () {
    test('千元值換成元再分級：1,353,387 千元 → 13.5 億', () {
      // 上櫃產業 EPS、季報、月營收的金額欄位都是千元（見各 model 欄位註解）
      expect(
        LocalizedNumberFormat.compactFromThousands(1_353_387),
        '13.5unit.billion',
      );
    });

    test('小金額落萬級：25 千元 → 2.5 萬', () {
      expect(
        LocalizedNumberFormat.compactFromThousands(25),
        '2.5unit.tenThousand',
      );
    });

    test('虧損保留負號', () {
      expect(
        LocalizedNumberFormat.compactFromThousands(-1_353_387),
        '-13.5unit.billion',
      );
    });
  });
}

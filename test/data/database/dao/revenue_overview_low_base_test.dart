// 低基期識別規則(2026-08-13 一魚三吃的核心)
//
// 「單月年增極端 + 累計年增平庸」= 基期效應/一次性認列的定義本身
// (聯上 2026-07 實例:單月 +1,096,390%——去年同月 53 萬 vs 今年 5.8 億,
// 建設交屋認列)。用資料關係識別,不裁列(尊重 2026-08-05「清單完整、
// 不被策展裁剪」定稿),UI 淡化+標記。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/revenue_overview_params.dart';
import 'package:daredevil/data/database/dao/revenue_dao.dart';

RevenueOverviewRow row({double? yoy, double? ytd}) => RevenueOverviewRow(
  symbol: '4113',
  name: '聯上',
  market: 'TWSE',
  revenue: 580000,
  momGrowth: 250.1,
  yoyGrowth: yoy,
  ytdYoyGrowth: ytd,
  isNewHigh: false,
);

void main() {
  test('🚨 聯上形狀:單月 +1,096,390%、累計平庸 → 低基期', () {
    expect(row(yoy: 1096390.6, ytd: 48.0).isLowBase, isTrue);
  });

  test('正常成長股(單月 +30%、累計 +25%)→ 非低基期', () {
    expect(row(yoy: 30.0, ytd: 25.0).isLowBase, isFalse);
  });

  test('🚨 高成長但一致(單月 +150%、累計 +140%)→ 非低基期', () {
    // 真主升段:單月與累計同步爆發,不可誤傷
    expect(row(yoy: 150.0, ytd: 140.0).isLowBase, isFalse);
  });

  test('單月未達門檻(+80%)→ 不標,無論累計多低', () {
    expect(row(yoy: 80.0, ytd: 2.0).isLowBase, isFalse);
  });

  test('🚨 累計缺值 → 不標(資料缺不是證據)', () {
    expect(row(yoy: 500.0, ytd: null).isLowBase, isFalse);
  });

  test('累計為負+單月爆量 → 低基期(典型一次性)', () {
    expect(row(yoy: 150.0, ytd: -10.0).isLowBase, isTrue);
  });

  test('邊界:單月恰為門檻值(100)→ 可標;累計恰為 yoy/5 → 不標(嚴格小於)', () {
    // 這兩個值是未來調參最可能動的地方,行為釘死
    expect(row(yoy: 100.0, ytd: 10.0).isLowBase, isTrue);
    expect(
      row(yoy: 100.0, ytd: 20.0).isLowBase,
      isFalse,
      reason: '20 == 100/5,嚴格小於才標',
    );
  });

  test('門檻常數存在且有據可查', () {
    expect(RevenueOverviewParams.lowBaseMinYoyPct, greaterThan(0));
    expect(RevenueOverviewParams.lowBaseDivergenceRatio, greaterThan(1));
  });
}

// openapi 月營收模型的累計年增解析(2026-08-13 一魚三吃)
//
// TWSE t187ap05_L 與 TPEX mopsfin_t187ap05_O 同 schema,自帶
// 「累計營業收入-前期比較增減(%)」——低基期怪物(聯上單月 +1,096,390%)
// 的解藥就在同一支 API 裡,先前抓了沒存。
//
// 檢核政策與 MOPS CSV 一致:累計增減與「當月累計/去年累計」重算失配
// → ytd 設 null,單月欄不受影響。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/tpex/tpex_monthly_revenue.dart';
import 'package:daredevil/data/models/twse/twse_monthly_revenue.dart';

Map<String, dynamic> twseJson({
  String? ytdPct,
  String? ytdCur,
  String? ytdPrior,
}) => {
  '資料年月': '11507',
  '公司代號': '2330',
  '公司名稱': '台積電',
  '營業收入-當月營收': '250000000',
  '營業收入-上月營收': '240000000',
  '營業收入-去年當月營收': '200000000',
  '營業收入-上月比較增減(%)': '4.17',
  '營業收入-去年同月增減(%)': '25.0',
  if (ytdCur != null) '累計營業收入-當月累計營收': ytdCur,
  if (ytdPrior != null) '累計營業收入-去年累計營收': ytdPrior,
  if (ytdPct != null) '累計營業收入-前期比較增減(%)': ytdPct,
};

void main() {
  group('TwseMonthlyRevenue 累計年增', () {
    test('🚨 三欄齊備且自洽 → ytdYoyGrowth 解析', () {
      final m = TwseMonthlyRevenue.fromJson(
        twseJson(ytdCur: '1500000000', ytdPrior: '1200000000', ytdPct: '25.0'),
      );
      expect(m.ytdYoyGrowth, closeTo(25.0, 0.01));
    });

    test('🚨 累計增減與重算失配 → null(壞資料不落庫)', () {
      // 重算 (15-12)/12 = +25%,給的卻是 +80% → 拒收
      final m = TwseMonthlyRevenue.fromJson(
        twseJson(ytdCur: '1500000000', ytdPrior: '1200000000', ytdPct: '80.0'),
      );
      expect(m.ytdYoyGrowth, isNull);
    });

    test('缺累計欄(舊回應)→ null,單月欄不受影響', () {
      final m = TwseMonthlyRevenue.fromJson(twseJson());
      expect(m.ytdYoyGrowth, isNull);
      expect(m.yoyGrowth, closeTo(25.0, 0.01));
    });

    test('去年累計為 0(新掛牌滿年前)→ null 不除零', () {
      final m = TwseMonthlyRevenue.fromJson(
        twseJson(ytdCur: '1500000000', ytdPrior: '0', ytdPct: '999'),
      );
      expect(m.ytdYoyGrowth, isNull);
    });
  });

  group('TpexMonthlyRevenue 累計年增(同 schema 同政策)', () {
    test('🚨 自洽 → 解析;失配 → null', () {
      final base = {
        '資料年月': '11507',
        '公司代號': '8069',
        '公司名稱': '元太',
        '營業收入-當月營收': '3000000',
        '營業收入-上月營收': '2900000',
        '營業收入-去年當月營收': '2500000',
        '營業收入-上月比較增減(%)': '3.45',
        '營業收入-去年同月增減(%)': '20.0',
        '累計營業收入-當月累計營收': '21000000',
        '累計營業收入-去年累計營收': '20000000',
        '累計營業收入-前期比較增減(%)': '5.0',
      };
      expect(
        TpexMonthlyRevenue.fromJson(base)!.ytdYoyGrowth,
        closeTo(5.0, 0.01),
      );
      expect(
        TpexMonthlyRevenue.fromJson({
          ...base,
          '累計營業收入-前期比較增減(%)': '55.0',
        })!.ytdYoyGrowth,
        isNull,
      );
    });
  });
}

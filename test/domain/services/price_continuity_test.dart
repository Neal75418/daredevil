// 價格水位斷點的偵測與截斷(2026-08-29 領域稽核 C3)
//
// daily_price 存原始收盤價、未還原除權息/減資/分割。跨越水位位移的長窗
// 指標會產出物理上不可能的數字——實測 5904 寶雅 2026-08-27 的 daily_reason
// 存著 `ma60: 506.18`,而當天股價 74.10;同檔的 RSI_EXTREME_OVERSOLD
// (rsi 17.4)連續 12 個交易日發出 +10 的買進理由。
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/price_continuity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  final base = DateTime(2026, 1, 1);

  /// 依 closes 造序列;null 代表停牌列
  List<DailyPriceEntry> series(List<double?> closes) => [
    for (var i = 0; i < closes.length; i++)
      createTestPrice(
        date: base.add(Duration(days: i)),
        close: closes[i],
        volume: closes[i] == null ? 0 : 1000,
      ),
  ];

  List<double?> closesOf(List<DailyPriceEntry> p) =>
      p.map((e) => e.close).toList();

  test('沒有斷點 → 原樣回傳', () {
    final p = series([100, 101, 99, 103, 102]);
    expect(identical(p.contiguousSuffix(), p), isTrue);
  });

  test('漲停跌停(±10%)不得判為斷點', () {
    // 連續三根漲停 + 一根跌停,全在交易所允許範圍內
    final p = series([100, 110, 121, 133.1, 119.79]);
    expect(closesOf(p.contiguousSuffix()), closesOf(p));
  });

  test('11% 仍在跳動單位四捨五入的容許帶內,不判斷點', () {
    final p = series([100, 111, 112, 113]);
    expect(closesOf(p.contiguousSuffix()), closesOf(p));
  });

  test('🚨 減資型的水位位移 → 只保留斷點之後', () {
    // 5904 寶雅的形狀:720 → 79.2(約 9.1 倍)
    final p = series([700, 710, 720, 79.2, 82.5, 78.0, 74.2]);
    expect(closesOf(p.contiguousSuffix()), [79.2, 82.5, 78.0, 74.2]);
  });

  test('🚨 除權息型(不停牌、幅度較小)同樣要抓到', () {
    // 1436 實測形狀:116.00 → 80.20(−30.9%),連續兩個交易日、無停牌
    final p = series([118, 117, 116, 80.2, 81.0, 79.5]);
    expect(closesOf(p.contiguousSuffix()), [80.2, 81.0, 79.5]);
  });

  test('🚨 停牌列不得被誤判為斷點——比較的是相鄰的有效收盤', () {
    // 中間三天停牌,價格本身連續
    final p = series([100, null, null, null, 101, 102]);
    expect(closesOf(p.contiguousSuffix()), closesOf(p));
  });

  test('🚨 跨停牌的水位位移仍要抓到(停牌 + 位移同時發生)', () {
    // 5904 真實形狀:停牌 12 天之後才出現新水位
    final p = series([720, null, null, 79.2, 80.0]);
    expect(closesOf(p.contiguousSuffix()), [79.2, 80.0]);
  });

  test('多個斷點 → 取**最近**的那一個', () {
    final p = series([1000, 100, 101, 102, 10.5, 10.8, 11.0]);
    expect(closesOf(p.contiguousSuffix()), [10.5, 10.8, 11.0]);
  });

  test('斷點在最後一根 → 只剩那一根(下游會以資料不足擋下)', () {
    final p = series([100, 101, 102, 20]);
    expect(closesOf(p.contiguousSuffix()), [20.0]);
  });

  test('全部停牌／空清單不得爆炸', () {
    expect(series([null, null]).contiguousSuffix().length, 2);
    expect(<DailyPriceEntry>[].contiguousSuffix(), isEmpty);
  });

  test('close <= 0 的異常列跳過,不參與比較', () {
    final p = series([100, 0, 101, 102]);
    expect(closesOf(p.contiguousSuffix()), closesOf(p));
  });

  test('門檻常數與交易所規則一致(±10% 之外)', () {
    expect(RuleParams.priceDiscontinuityRatio, greaterThan(0.11));
    expect(RuleParams.priceDiscontinuityRatio, lessThan(0.15));
  });
}

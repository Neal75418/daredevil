// 風險報酬比：顯示四捨五入、判讀用原值，邊界上互相矛盾
//
// analysis_summary_service.dart:294-305
//   final rr = upside / downside;
//   ... 'ratio': rr.toStringAsFixed(1)          ← 四捨五入
//   if (rr >= riskRewardFavorableThreshold) ... ← 用原值
//   else if (rr < 1) ...                        ← 用原值
//
// 實機 2026-07-27（資料日 07-24）三張並排才看得出來：
//   光寶科 2301 支撐 201.0／壓力 241.0／收盤 214.5
//     → rr = 26.5 / 13.5 = **1.9630**，顯示「1:2.0」卻**不給**「賠率相對有利」
//   晶豪科 3006 rr = 17.5 / 7.5 = 2.3333，顯示「1:2.3」**有**給
//   使用者看到 2.0 沒有、2.3 有，判準看起來是隨機的。
//
// 另一側更直白：rr ∈ [0.95, 1.0) 顯示「1:1.0」（上下檔相當），文字卻寫
// 「下檔風險已大於上檔空間，賠率相對不利」——同一句話裡自相矛盾。
//
// 影響面（DB 實查，support < close < resistance 的 578 列）：
//   rr ∈ [1.95, 2.0) → 顯示 2.0 卻不算有利：**2 列**
//   rr ∈ [0.95, 1.0) → 顯示 1.0 卻判不利：**10 列**
//   合計 12/578 = 2.1%
//
// **修法：顯示改無條件捨去，門檻完全不動。**
// 捨去後的值恆 ≤ 原值，於是
//   原值 >= 2.0 → 顯示值仍 >= 2.0（不會漏掉「有利」）
//   原值 <  1.0 → 顯示值仍 <  1.0（不會漏掉「不利」）
//   1.0 <= 原值 < 2.0 → 顯示值仍落在中間段
// 三個條件都封閉，矛盾在數學上不可能發生——不是把 12 筆特例調對。
//
// 不採「讓判定跟著四捨五入後的值」：那會讓**顯示精度決定分析判斷**
// （1.963 因為印成 2.0 就改判有利）。門檻現在雖無回測來源（docstring 只寫
// 「上檔空間 ≥ 下檔風險的此倍數視為相對有利」），但把顯示寫進判定路徑
// 等於埋下未來校準時會踩到的地雷。
//
// 捨去對報酬取保守估計，也是風險評估該有的方向；文案本就寫「估算…約」。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/domain/services/analysis_summary_service.dart';

import '../../helpers/analysis_data_generators.dart';
import '../../helpers/price_data_generators.dart';

void main() {
  const service = AnalysisSummaryService();
  final date = DateTime(2026, 7, 24);

  ({String? ratio, bool favorable, bool poor}) rrFor({
    required double close,
    required double support,
    required double resistance,
  }) {
    final result = service.generate(
      analysis: createTestAnalysis(
        trendState: 'DOWN',
        score: 20,
        supportLevel: support,
        resistanceLevel: resistance,
      ),
      reasons: [createTestReason(reasonType: 'ROE_EXCELLENT', ruleScore: 8)],
      latestPrice: createTestPrice(date: date, close: close),
      priceChange: -1.0,
      institutionalHistory: [],
      revenueHistory: [],
      latestPER: null,
      horizon: Horizon.short,
    );
    String? ratio;
    var favorable = false;
    var poor = false;
    for (final p in result.overallParts) {
      if (p.key == 'summary.riskReward') ratio = p.namedArgs['ratio'];
      if (p.key == 'summary.riskRewardFavorable') favorable = true;
      if (p.key == 'summary.riskRewardPoor') poor = true;
    }
    return (ratio: ratio, favorable: favorable, poor: poor);
  }

  test('🚨 實測光寶科 2301：rr=1.9630 不得顯示成「2.0」', () {
    final r = rrFor(close: 214.5, support: 201.0, resistance: 241.0);

    expect(
      r.ratio,
      '1.9',
      reason:
          '(241.0-214.5)/(214.5-201.0) = 1.9630。四捨五入成 2.0 會讓畫面看起來'
          '過了門檻，文字卻不給「賠率相對有利」',
    );
    expect(r.favorable, isFalse, reason: '判讀不變——1.963 本來就沒過 2.0');
  });

  test('🚨 rr=0.96 不得顯示成「1.0」（同句話裡自相矛盾）', () {
    // upside 9.6、downside 10.0 → rr = 0.96
    final r = rrFor(close: 100.0, support: 90.0, resistance: 109.6);

    expect(r.ratio, '0.9', reason: '顯示「1:1.0」＝上下檔相當，卻同時說「下檔風險已大於上檔空間」');
    expect(r.poor, isTrue, reason: '判讀不變——0.96 本來就 < 1');
  });

  test('對照組：實測晶豪科 3006 與元太 8069 不受影響', () {
    final jhk = rrFor(close: 206.0, support: 198.5, resistance: 223.5);
    expect(jhk.ratio, '2.3'); // 2.3333
    expect(jhk.favorable, isTrue);

    final eink = rrFor(close: 191.0, support: 181.0, resistance: 201.5);
    expect(eink.ratio, '1.0'); // 1.05 → 捨去 1.0
    expect(eink.favorable, isFalse);
    expect(eink.poor, isFalse);
  });

  test('邊界：恰好等於門檻時不得被捨去到門檻之下', () {
    // rr 恰好 2.0
    final exactly2 = rrFor(close: 100.0, support: 90.0, resistance: 120.0);
    expect(exactly2.ratio, '2.0');
    expect(exactly2.favorable, isTrue);

    // rr 恰好 1.0
    final exactly1 = rrFor(close: 100.0, support: 90.0, resistance: 110.0);
    expect(exactly1.ratio, '1.0');
    expect(exactly1.poor, isFalse);
  });

  // 捨去實作必須先消除浮點噪音：`(rr * 10).floor()` 在真值恰好是 x.x 時
  // 會被 upside/downside 的 FP 誤差咬（0.6 算成 0.5999999999999999 → 0.5），
  // 整整掉一格。實測 79,200 組構造值中 2,419 組中招——比它要修的 12/578 還多。
  test('🚨 真值恰好為 x.x 時不得因浮點誤差掉一格', () {
    // 6.7 * 0.6 / 6.7 在 IEEE754 下算出 0.5999999999999999
    final r = rrFor(
      close: 100.0,
      support: 100.0 - 6.7,
      resistance: 100.0 + 6.7 * 0.6,
    );
    expect(r.ratio, '0.6', reason: '純 floor 會顯示 0.5');

    // 另一組：0.1 * 0.7 / 0.1 → 0.6999999999999998
    final r2 = rrFor(
      close: 100.0,
      support: 100.0 - 0.1,
      resistance: 100.0 + 0.1 * 0.7,
    );
    expect(r2.ratio, '0.7', reason: '純 floor 會顯示 0.6');
  });

  test('🚨 不變量：整段區間掃描，顯示值與判讀不得互相矛盾', () {
    const downside = 10.0;
    final offenders = <String>[];
    // upside 4.0 ~ 30.0 每 0.05 一步 → rr 0.40 ~ 3.00
    for (var i = 80; i <= 600; i++) {
      final upside = i * 0.05;
      final r = rrFor(
        close: 100.0,
        support: 100.0 - downside,
        resistance: 100.0 + upside,
      );
      final shown = double.parse(r.ratio!);

      if (r.favorable && shown < AnalysisParams.riskRewardFavorableThreshold) {
        offenders.add(
          'rr≈${(upside / downside).toStringAsFixed(4)} '
          '顯示 $shown 卻標「有利」',
        );
      }
      if (!r.favorable &&
          shown >= AnalysisParams.riskRewardFavorableThreshold) {
        offenders.add(
          'rr≈${(upside / downside).toStringAsFixed(4)} '
          '顯示 $shown 卻不標「有利」',
        );
      }
      if (r.poor && shown >= 1.0) {
        offenders.add(
          'rr≈${(upside / downside).toStringAsFixed(4)} '
          '顯示 $shown 卻標「不利」',
        );
      }
      if (!r.poor && shown < 1.0) {
        offenders.add(
          'rr≈${(upside / downside).toStringAsFixed(4)} '
          '顯示 $shown 卻不標「不利」',
        );
      }
    }

    expect(
      offenders.take(8),
      isEmpty,
      reason:
          '共 ${offenders.length} 處矛盾。這條掃整段區間而非個案——修法必須讓'
          '矛盾在數學上不可能，不是把已知的 12 筆調對',
    );
  });
}

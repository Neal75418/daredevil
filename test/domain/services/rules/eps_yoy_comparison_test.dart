// EPS 比較基準改同季 YoY(2026-08-15 數值稽核)
//
// 舊實作用**季對季(QoQ)**:eps[i] vs eps[i+1]。但台股單季 EPS 有強
// 季節性——實測 2023 年起全市場,Q1 財報中 QoQ 跌幅 ≥20% 者佔 32.5%,
// Q3 只有 12.6%,**相差 2.6 倍**。於是 EPS_DECLINE_WARNING(扣分)在
// Q1 財報季系統性放大、Q3 系統性沉默;EPS_CONSECUTIVE_GROWTH 反向同理。
// quarterly_report_dao 自己的註解也記載過 2454 的實例:2025 四季
// 18.43→17.5→15.84→14.4 純遞減卻是正常經營。
//
// **語意選擇**:保持「連續 N 季成長/衰退」的原意,只把比較基準從
// 「上一季」換成「去年同季」。即「連續 2 季的 YoY 都成長」,不是
// 「YoY 連續改善」——後者是另一個指標(成長加速),不是這條規則在說的事。
//
// 去年同季用**日期容差比對**而非 index+4:財報日期可能跳季,固定位移
// 會拿到錯的基期(同 ROE 修正的作法)。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/technical_indicators.dart';
import 'package:daredevil/domain/services/rules/fundamental_scan_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

import '../../../helpers/price_data_generators.dart';

/// 站上 MA20 的價格序列(技術面 gate 用)
List<DailyPriceEntry> aboveMa20() {
  final now = DateTime.now();
  return List.generate(
    30,
    (i) => createTestPrice(
      date: now.subtract(Duration(days: 30 - i)),
      close: 100 + i * 0.5,
      volume: 1000,
    ),
  );
}

AnalysisContext ctx() => AnalysisContext(
  trendState: TrendState.up,
  evaluationTime: DateTime(2026, 8, 14),
  indicators: const TechnicalIndicators(ma20: 100, ma60: 95),
);

/// EPS 序列(新到舊),date 為季底
List<FinancialDataEntry> epsSeries(List<({int y, int q, double v})> items) => [
  for (final it in items)
    FinancialDataEntry(
      symbol: '1111',
      date: DateTime(it.y, it.q * 3, it.q == 1 || it.q == 4 ? 31 : 30),
      statementType: 'INCOME',
      dataType: 'EPS',
      value: it.v,
      originName: null,
    ),
];

void main() {
  const growth = EPSConsecutiveGrowthRule();

  StockData stock(List<FinancialDataEntry> eps) =>
      StockData(symbol: '1111', prices: aboveMa20(), epsHistory: eps);

  test('🚨 季節性遞減不得判成衰退——YoY 全部成長就該觸發成長', () {
    // 典型季節性公司:每年 Q1 低、Q4 高,但**每季都比去年同季好**
    // QoQ 看起來是 14.4 ← 15.84 ← 17.5 ← 18.43 一路遞減(舊實作判衰退)
    final eps = epsSeries([
      (y: 2026, q: 2, v: 20.0), // vs 2025Q2 17.5 → +14.3%
      (y: 2026, q: 1, v: 16.5), // vs 2025Q1 14.4 → +14.6%
      (y: 2025, q: 4, v: 21.0),
      (y: 2025, q: 3, v: 18.43),
      (y: 2025, q: 2, v: 17.5),
      (y: 2025, q: 1, v: 14.4),
    ]);
    final r = growth.evaluate(ctx(), stock(eps));
    expect(r, isNotNull, reason: '連續兩季 YoY 各 +14%,是實質成長;QoQ 的遞減只是季節性');
    expect(r!.type, ReasonType.epsConsecutiveGrowth);
  });

  test('🚨 QoQ 成長但 YoY 衰退 → 不得觸發(舊實作會誤報)', () {
    // 逐季回升但仍遠低於去年同季 = 衰退中的反彈,不是成長
    final eps = epsSeries([
      (y: 2026, q: 2, v: 5.0), // vs 2025Q2 20.0 → −75%
      (y: 2026, q: 1, v: 3.0), // vs 2025Q1 18.0 → −83%
      (y: 2025, q: 4, v: 2.0),
      (y: 2025, q: 3, v: 1.5),
      (y: 2025, q: 2, v: 20.0),
      (y: 2025, q: 1, v: 18.0),
    ]);
    expect(
      growth.evaluate(ctx(), stock(eps)),
      isNull,
      reason: 'QoQ 3.0→5.0 是成長,但對去年同季腰斬,不該報「EPS 連續成長」',
    );
  });

  test('缺去年同季 → 不觸發(不用可得資料頂替)', () {
    final eps = epsSeries([
      (y: 2026, q: 2, v: 20.0),
      (y: 2026, q: 1, v: 16.5),
      (y: 2025, q: 4, v: 21.0),
    ]);
    expect(growth.evaluate(ctx(), stock(eps)), isNull);
  });

  test('去年同季 ≤ 0 → 不計算成長率(除零與無意義基期)', () {
    final eps = epsSeries([
      (y: 2026, q: 2, v: 20.0),
      (y: 2026, q: 1, v: 16.5),
      (y: 2025, q: 4, v: 21.0),
      (y: 2025, q: 3, v: 18.0),
      (y: 2025, q: 2, v: -1.0), // 去年同季虧損
      (y: 2025, q: 1, v: 14.4),
    ]);
    expect(growth.evaluate(ctx(), stock(eps)), isNull);
  });

  group('EPS_DECLINE_WARNING 對稱使用 YoY', () {
    const decline = EPSDeclineWarningRule();

    test('🚨 季節性遞減不得判成衰退(與成長規則同一組資料)', () {
      final eps = epsSeries([
        (y: 2026, q: 2, v: 20.0), // vs 2025Q2 17.5 → +14%
        (y: 2026, q: 1, v: 16.5), // vs 2025Q1 14.4 → +15%
        (y: 2025, q: 4, v: 21.0),
        (y: 2025, q: 3, v: 18.43),
        (y: 2025, q: 2, v: 17.5),
        (y: 2025, q: 1, v: 14.4),
      ]);
      expect(
        decline.evaluate(ctx(), stock(eps)),
        isNull,
        reason: 'QoQ 一路遞減但 YoY 都在成長,這是季節性不是衰退',
      );
    });

    test('真實的 YoY 衰退仍要抓到(確認不是把功能關掉)', () {
      final eps = epsSeries([
        (y: 2026, q: 2, v: 5.0), // vs 2025Q2 20.0 → −75%
        (y: 2026, q: 1, v: 3.0), // vs 2025Q1 18.0 → −83%
        (y: 2025, q: 4, v: 2.0),
        (y: 2025, q: 3, v: 1.5),
        (y: 2025, q: 2, v: 20.0),
        (y: 2025, q: 1, v: 18.0),
      ]);
      final r = decline.evaluate(ctx(), stock(eps));
      expect(r, isNotNull);
      expect(r!.type, ReasonType.epsDeclineWarning);
    });
  });
}

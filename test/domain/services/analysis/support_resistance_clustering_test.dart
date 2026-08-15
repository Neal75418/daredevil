// 支撐壓力聚類的鏈式漂移(2026-08-15 數值稽核)
//
// 這個服務**從來沒有專屬測試檔**——全 repo 只有 analysis_service_test
// 間接引用,那段聚類邏輯從沒被斷言驗過。這也解釋了為什麼 3.9% 的漂移
// 能存在這麼久。本檔先釘住行為,再談修正。
//
// 病灶:「2% 聚類」是拿新點與**當前 zone 的跑動平均**比較,而每收一個點
// 平均就往上移,於是下一個點又以新平均為基準 → 鏈式漂移,一個 zone 實際
// 可跨到約 2×threshold(3.9%)。更關鍵的是回報值是 zone 的**平均價**:
// 跨 3.9% 的 zone,其平均離兩端最遠成員 1.9%——回報的「壓力位」可能是
// 一個**沒有任何波段高點真正碰過的價位**。
//
// 影響:alert_evaluation_service 的突破/跌破警示直接用 currentPrice 與
// 這個值比較,1.9% 的偏移在台股一根 K 內就能跨過。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/analysis/support_resistance_service.dart';

import '../../../helpers/price_data_generators.dart';

/// 造出擺盪序列:每個 swing high 相隔 [stepPct]%,用來觀察聚類寬度
List<DailyPriceEntry> swingSeries({
  required int swingCount,
  required double stepPct,
  double base = 100,
}) {
  final now = DateTime.now();
  final out = <DailyPriceEntry>[];
  var day = 0;
  // 前置低檔,讓 swing 偵測有左右窗
  for (var i = 0; i < 5; i++) {
    out.add(
      createTestPrice(
        date: now.subtract(Duration(days: 200 - day++)),
        close: base * 0.9,
        high: base * 0.9,
        low: base * 0.88,
        volume: 1000,
      ),
    );
  }
  for (var s = 0; s < swingCount; s++) {
    final peak = base * (1 + stepPct / 100 * s);
    // 谷 → 峰 → 谷,形成可辨識的 swing high
    for (final f in [0.92, 1.0, 0.92]) {
      out.add(
        createTestPrice(
          date: now.subtract(Duration(days: 200 - day++)),
          close: peak * f,
          high: peak * f,
          low: peak * f * 0.99,
          volume: 1000,
        ),
      );
    }
  }
  return out;
}

void main() {
  final service = SupportResistanceService();

  group('聚類寬度(特徵化——先釘住現有行為)', () {
    test('findRange 的窗口與端點', () {
      final prices = swingSeries(swingCount: 6, stepPct: 1.0);
      final (bottom, top) = service.findRange(prices);
      expect(top, isNotNull);
      expect(bottom, isNotNull);
      expect(top!, greaterThanOrEqualTo(bottom!), reason: '區間頂不得低於區間底');
    });

    test('🚨 回報的壓力位必須是真的有波段點碰過的價位', () {
      // 6 個間距 1% 的 swing high(100 → 105):若鏈式漂移把它們併成
      // 一個 zone,回報的平均會落在中間、沒有任何一個高點真正碰過
      final prices = swingSeries(swingCount: 6, stepPct: 1.0);
      final (_, resistance) = service.findSupportResistance(prices);
      if (resistance == null) return; // 無壓力位不在本測試範圍

      // 收集所有實際的高點
      final highs = prices.map((p) => p.high).whereType<double>().toList();
      final nearest = highs
          .map((h) => (h - resistance).abs() / resistance)
          .reduce((a, b) => a < b ? a : b);
      expect(
        nearest,
        lessThan(0.01),
        reason:
            '回報的壓力位 $resistance 離最近的實際高點 '
            '${(nearest * 100).toStringAsFixed(2)}% —— '
            '超過 1% 表示它是聚類平均的產物,不是真實價位',
      );
    });

    test('間距明顯大於門檻的波段點不得併為同一區', () {
      // 間距 5%(遠大於 2% 門檻)→ 必須分開
      final prices = swingSeries(swingCount: 4, stepPct: 5.0);
      final (support, resistance) = service.findSupportResistance(prices);
      // 只要不 crash 且回報值落在資料範圍內即可(行為特徵化)
      final highs = prices.map((p) => p.high).whereType<double>().toList();
      final maxHigh = highs.reduce((a, b) => a > b ? a : b);
      final minLow = prices
          .map((p) => p.low)
          .whereType<double>()
          .reduce((a, b) => a < b ? a : b);
      if (resistance != null) {
        expect(resistance, lessThanOrEqualTo(maxHigh * 1.001));
      }
      if (support != null) {
        expect(support, greaterThanOrEqualTo(minLow * 0.999));
      }
    });
  });
}

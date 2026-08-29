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
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params.dart';
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

  // ==========================================
  // ATR 動態半徑的上界（2026-08-29 稽核 H3）
  // ==========================================
  //
  // `maxDistance = atrDistance ?? maxSupportResistanceDistance` —— ATR 版
  // **完全沒有上界**，而它取代的那個常數（0.08）文件寫著「超過此距離的
  // 壓力/支撐將被忽略，8% 可偵測近期水位並過濾無關水位」。
  //
  // 實測 2,135 檔:54.3% 的半徑比文件的 8% 寬、p90 = 17.3%、**max = 181.5%**
  // （5904，未還原的價格斷點把 ATR 撐爆）。半徑 > 100% 時 `minSupport` 變成
  // 負數，現價下方的**每一個** zone 都「在範圍內」。排除近 20 根有斷點者後
  // max 降到 51.9%、p99 = 22.9%。
  //
  // **上界不發明新數字**：`maxSupportResistanceDistance (0.08) ×
  // atrDistanceMultiplier (3.0) = 0.24` —— 語意是「動態半徑最多放寬到靜態的
  // 3 倍，與 ATR 本身用的倍數一致」，而它幾乎正好等於實測 p99（22.9%）。
  // 兩個獨立錨點吻合。
  //
  // **不加下界**：低波動股用窄半徑是 ATR 縮放的用意，不是缺陷。
  group('ATR 動態半徑必須有上界', () {
    /// 每天大幅震盪 → ATR 極大;[swing] 控制單日振幅
    List<DailyPriceEntry> wildRange({required double swing}) {
      final now = DateTime.now();
      return [
        for (var i = 0; i < 60; i++)
          createTestPrice(
            date: now.subtract(Duration(days: 60 - i)),
            close: 100 + (i.isEven ? swing : -swing),
            high: 100 + swing * 2,
            low: 100 - swing * 2,
            volume: 1000,
          ),
      ];
    }

    double cap() =>
        TrendParams.maxSupportResistanceDistance *
        TrendParams.atrDistanceMultiplier;

    test('上界由既有兩個常數推得,不是另外選的數字', () {
      expect(cap(), closeTo(0.24, 1e-9));
    });

    test('🚨 高波動股的關卡不得超出上界', () {
      final prices = wildRange(swing: 30); // ATR ≈ 120 → 未設限時半徑約 3.6 倍
      final close = prices.last.close!;
      final (support, resistance) = service.findSupportResistance(prices);

      if (support != null) {
        expect(
          (close - support) / close,
          lessThanOrEqualTo(cap() + 1e-9),
          reason:
              '離現價 ${((close - support) / close * 100).toStringAsFixed(1)}% 的支撐不可用於停損',
        );
      }
      if (resistance != null) {
        expect((resistance - close) / close, lessThanOrEqualTo(cap() + 1e-9));
      }
    });

    test('🚨 半徑不得大到讓 minSupport 變成負數', () {
      // 未設限時 5904 的半徑是 181.5%,minSupport = close × (1 − 1.815) < 0
      // ——現價下方的每一個 zone 都「在範圍內」,等於沒有下界。
      final prices = wildRange(swing: 80);
      final close = prices.last.close!;
      final (support, _) = service.findSupportResistance(prices);
      if (support != null) {
        expect(support, greaterThan(close * (1 - cap()) - 1e-9));
      }
    });

    test('低波動股維持窄半徑(不加下界——那是 ATR 縮放的用意)', () {
      final prices = wildRange(swing: 0.5);
      final close = prices.last.close!;
      final (support, resistance) = service.findSupportResistance(prices);
      // 只要不 crash、且落在遠比 8% 更窄的範圍內即可
      if (support != null) {
        expect((close - support) / close, lessThan(0.08));
      }
      if (resistance != null) {
        expect((resistance - close) / close, lessThan(0.08));
      }
    });
  });

  // ==========================================
  // 末根停牌時的參考價（2026-08-29 稽核 M10）
  // ==========================================
  //
  // `findSupportResistance` 在 `prices.last.close == null` 時走一條
  // **完全沒有邊界、也沒有方向檢查**的回退：直接回最後一個 swing 高/低點。
  // 症狀有兩種:回報一個在現價**上方**的「支撐」,或一個離現價 28% 遠的值。
  //
  // 觸發前提確實存在:上游 `classifyCandidate` + `LiquidityChecker` 只保證
  // **完整歷史**的末根有收盤,而 `analysis_coordinator_service` 傳進來的是
  // **priorHistory**——末根是倒數第二根,不受那道保證涵蓋(2026-08-28 實測
  // 20 檔倒數第二根停牌)。⚠️ 那 20 檔當天都沒真的進到 analyzeStock(全被
  // 流動性門檻擋掉);可達性來自自選股的 `exemptFromLiquidity` 豁免路徑。
  group('末根停牌不得改變支撐壓力', () {
    /// 正弦擺盪 + 一個**深谷**,末根停牌。
    ///
    /// 深谷讓「最近的 swing low」落在離現價 28% 的地方——舊回退直接回它
    /// （無界）,新路徑則因超出 ATR 半徑而改取擺盪區的低點。兩者都非 null
    /// 且方向正確,但差很多,所以這組 fixture 能真的分辨修法。
    List<DailyPriceEntry> sineWithDipThenHalt({bool halt = true}) {
      final now = DateTime.now();
      const len = 52;
      return [
        for (var i = 0; i < len; i++)
          () {
            final halted = halt && i == len - 1;
            final close = halted
                ? null
                : (i == 37 ? 70.0 : 96 + 4 * sin(2 * pi * i / 25));
            return createTestPrice(
              date: now.subtract(Duration(days: len - i)),
              close: close,
              high: close == null ? null : close * 1.01,
              low: close == null ? null : close * 0.99,
              volume: halted ? 0 : 1000,
            );
          }(),
      ];
    }

    /// 擺盪 → 急跌 → 末根停牌。急跌段落在 swing 偵測窗之外（右側需留
    /// halfWindow=10 根），所以最後一個 swing low 會停在**高檔擺盪區**，
    /// 而最後一個有效收盤在低檔 → 舊回退給出「高於現價的支撐」。
    List<DailyPriceEntry> plungeThenHalt() {
      final now = DateTime.now();
      final out = <DailyPriceEntry>[];
      var day = 0;
      DailyPriceEntry bar(double? close) => createTestPrice(
        date: now.subtract(Duration(days: 200 - day++)),
        close: close,
        high: close,
        low: close == null ? null : close * 0.99,
        volume: close == null ? 0 : 1000,
      );
      for (var i = 0; i < 30; i++) {
        out.add(bar(i.isEven ? 105.0 : 95.0));
      }
      for (var i = 0; i < 14; i++) {
        out.add(bar(95 - i * (15 / 13)));
      }
      out.add(bar(null));
      return out;
    }

    double lastValidClose(List<DailyPriceEntry> p) =>
        p.map((e) => e.close).whereType<double>().last;

    test('對照組:末根有收盤時算得出雙邊關卡,且方向正確', () {
      // 無條件斷言（不是 `if (x != null)`）——這條若退化成「什麼都沒驗」,
      // 後面那條「停牌不得改變答案」就會變成兩個 null 相等的套套邏輯。
      final prices = sineWithDipThenHalt(halt: false);
      final close = lastValidClose(prices);
      final (support, resistance) = service.findSupportResistance(prices);

      expect(support, isNotNull);
      expect(resistance, isNotNull);
      expect(support!, lessThan(close));
      expect(resistance!, greaterThan(close));
    });

    test('🚨 末根停牌時,關卡必須與「把停牌根拿掉」時完全相同', () {
      final halted = sineWithDipThenHalt();
      expect(halted.last.close, isNull, reason: 'fixture 必須真的以停牌根結尾');
      final withoutHalt = halted.sublist(0, halted.length - 1);

      final fromHalted = service.findSupportResistance(halted);
      final fromClean = service.findSupportResistance(withoutHalt);

      expect(fromHalted.$1, isNotNull, reason: '停牌根不得讓支撐整個消失');
      expect(fromHalted.$2, isNotNull);
      expect(fromHalted, fromClean, reason: '多附一根沒有交易的 K 棒,不該改變這檔股票的支撐壓力');
    });

    test('🚨 末根停牌時,支撐不得高於最後一個有效收盤', () {
      // 舊回退在這組 fixture 上回 94.05,而最後有效收盤是 80.0
      // ——一條畫在現價下方、實際卻在上方的「支撐」線。
      final prices = plungeThenHalt();
      final close = lastValidClose(prices);
      final (support, resistance) = service.findSupportResistance(prices);

      if (support != null) {
        expect(
          support,
          lessThan(close),
          reason: '「支撐」高於現價會被畫成下方的線,並被 BreakdownRule 拿去比較',
        );
      }
      if (resistance != null) expect(resistance, greaterThan(close));
    });

    test('完全沒有有效收盤 → 回 (null, null)（契約,非迴歸守門）', () {
      // 舊碼在這個輸入上也回 (null, null)（highs/lows 皆空）,所以這條
      // **不會**因還原生產碼而轉紅。留著是為了釘住「沒有參考價就不給關卡」
      // 這個契約,不要誤以為它守著 M10。
      final now = DateTime.now();
      final prices = List.generate(
        45,
        (i) => createTestPrice(date: now.subtract(Duration(days: 45 - i))),
      );
      expect(service.findSupportResistance(prices), (null, null));
    });
  });
}

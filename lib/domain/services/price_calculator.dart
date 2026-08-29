import 'dart:math';

import 'package:daredevil/core/constants/rule_params_sector.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 股價相關計算工具
class PriceCalculator {
  PriceCalculator._();

  /// 市場是否處於上升 regime：載入 universe 的 [lookbackDays]D **中位數**報酬 > 0。
  ///
  /// 產業領導 tilt 用。有效股不足視為資料不足 → 保守回 false（不套 tilt）。
  /// 規則 gate 場景用 [marketUptrendOrNull]（資料不足回 null、不擋規則）。
  static bool isMarketUptrend(
    Map<String, List<DailyPriceEntry>> priceHistories,
    int lookbackDays,
  ) => marketUptrendOrNull(priceHistories, lookbackDays) ?? false;

  /// [isMarketUptrend] 的三值版：有效股 < [SectorParams.regimeMinEligibleStocks]
  /// 回 null（未知）。
  ///
  /// 回檔類規則的 regime gate 用——`AnalysisContext.isMarketUptrend == false`
  /// 才擋，null 視為 permissive，避免 fresh DB / 歷史不足時誤殺訊號。
  ///
  /// [asOf] 給定時只計入「最後一根 bar 就是該日」的股票。單一市場資料缺漏
  /// 時（實測 TWSE 1225 / TPEx 904），有資料那半邊的 `last` 是今日、缺漏
  /// 那半邊的 `last` 是昨日 —— 不過濾就會把「今日的一半」與「昨日的另一半」
  /// 混進同一個母體，是評分裡唯一真正被半市場污染的計算。過濾後半市場仍有千餘檔，
  /// 遠高於 [SectorParams.regimeMinEligibleStocks]，regime 照常算得出來
  /// 且變成正確的；真的不足則照既有語意回 null（permissive、不誤殺）。
  ///
  /// 與 `classifyCandidate` 的 staleBar 檢查同一套新鮮度概念。
  ///
  /// **為什麼是中位數而不是平均**（2026-08-29 領域稽核 C2）：報酬分布右偏
  /// 得極端——下界被 −100% 綁住、上界無限——所以少數多倍股就能主導兩千檔的
  /// 等權平均。實測（本機 DB、120 交易日回看）**180 個可判定日裡有 179 天
  /// 判多頭**（99.4%），其中 40.6% 的日子過半股票其實在跌；2026-08-28 平均
  /// +12.93%、中位數 +0.66%，貢獻最大的 3026(+578%)、7610(+418%)、
  /// 6213(+356%) 都是**真行情**（價格序列連續無斷點），不是資料錯誤。
  /// 一道 99.4% 時間都開著的 gate 不是 gate。
  ///
  /// 換中位數不需要選新門檻，因為 `中位數 > 0 ⟺ 過半股票上漲`（奇數檔嚴格
  /// 成立；偶數檔取中間兩值平均，恰好半數上漲時取決於兩者幅度）。這道 gate
  /// 自此在**定義上**等同市場寬度，而不是碰巧一致。
  ///
  /// ⚠️ `tool/replay_calibrator.dart` 的 [computeMarketUptrendByDate] 是同一
  /// 語意的第二份實作（為了 O(總列數) 一次算完全部日期），**兩者必須一起改**
  /// ——parity 測試在兩邊同時錯的時候仍然會綠。
  static bool? marketUptrendOrNull(
    Map<String, List<DailyPriceEntry>> priceHistories,
    int lookbackDays, {
    DateTime? asOf,
  }) {
    final returns = <double>[];
    for (final history in priceHistories.values) {
      if (history.length < lookbackDays + 1) continue;
      if (asOf != null) {
        // 逐欄比 y/m/d：DateTime 的 == 連時分秒一起比，評分日帶了時間
        // 就會把全部股票濾光、regime 恆為 null。
        final d = history.last.date;
        if (d.year != asOf.year || d.month != asOf.month || d.day != asOf.day) {
          continue;
        }
      }
      final latest = history.last.close;
      final old = history[history.length - lookbackDays - 1].close;
      if (latest == null || old == null || old <= 0) continue;
      returns.add((latest - old) / old);
    }
    if (returns.length < SectorParams.regimeMinEligibleStocks) return null;
    return median(returns) > 0;
  }

  /// 中位數（偶數取中間兩值平均）。**就地排序傳入的 list**。
  ///
  /// 抽成共用函式是刻意的：`tool/replay_calibrator.dart` 的
  /// [computeMarketUptrendByDate] 為了效能有第二份 regime 實作，若兩邊各自
  /// 寫一次排序與 tie 規則，偶數檔的取法就可能悄悄分岔——而 parity 測試在
  /// 兩邊同時錯時仍會綠。
  ///
  /// 前置條件：[values] 不可為空。
  static double median(List<double> values) {
    assert(values.isNotEmpty, 'median of empty list');
    values.sort();
    final n = values.length;
    return n.isOdd ? values[n ~/ 2] : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2;
  }

  /// 5 trading days 報酬（%）。回 null 當 history < 6 筆 / 端點 close null /
  /// 起點 0。
  static double? ret5d(List<DailyPriceEntry>? history) {
    if (history == null || history.length < 6) return null;
    final latest = history.last.close;
    final old = history[history.length - 6].close;
    if (latest == null || old == null || old == 0) return null;
    return (latest - old) / old * 100;
  }

  /// 1 trading day 報酬（%）— 族群排行「今日」視窗。
  static double? ret1d(List<DailyPriceEntry>? history) {
    if (history == null || history.length < 2) return null;
    final latest = history.last.close;
    final old = history[history.length - 2].close;
    if (latest == null || old == null || old == 0) return null;
    return (latest - old) / old * 100;
  }

  /// 20 trading days 報酬（%）— 族群排行／產業動能聚合鍵。
  /// 回 null 當 history < 21 筆 / 端點 close null / 起點 0。
  static double? ret20d(List<DailyPriceEntry>? history) {
    if (history == null || history.length < 21) return null;
    final latest = history.last.close;
    final old = history[history.length - 21].close;
    if (latest == null || old == null || old == 0) return null;
    return (latest - old) / old * 100;
  }

  /// 60 trading days 報酬（%）— 相對強度（RS）proxy。
  ///
  /// 60D 報酬與「全市場 60D percentile rank」同序（單調函數），
  /// Mode B 排序與掃描頁 rs60Desc 排序共用此鍵。
  /// 回 null 當 history < 61 筆 / 端點 close null / 起點 0。
  static double? ret60d(List<DailyPriceEntry>? history) {
    if (history == null || history.length < 61) return null;
    final latest = history.last.close;
    final old = history[history.length - 61].close;
    if (latest == null || old == null || old == 0) return null;
    return (latest - old) / old * 100;
  }

  /// 根據價格歷史計算漲跌幅百分比
  ///
  /// 優先使用 API 提供的漲跌價差（[DailyPriceEntry.priceChange]），
  /// 確保即使歷史資料有缺口（例如跳過某日更新），漲跌幅仍正確。
  ///
  /// 回退邏輯：若 priceChange 為 null（如 FinMind 歷史資料），
  /// 則根據 history 中的前一日收盤價計算。
  ///
  /// 以下情況回傳 null：
  /// - latestPrice 為 null 或收盤價為 null
  /// - 無法計算前一日收盤價（歷史資料不足且無 priceChange）
  /// - 前一日收盤價為零或負數
  static double? calculatePriceChange(
    List<DailyPriceEntry> history,
    DailyPriceEntry? latestPrice,
  ) {
    if (latestPrice == null || latestPrice.close == null) return null;

    final latestClose = latestPrice.close!;

    // 優先使用 API 提供的漲跌價差（最可靠，不依賴歷史資料完整性）
    if (latestPrice.priceChange != null) {
      final change = latestPrice.priceChange!;
      final prevClose = latestClose - change;
      if (prevClose <= 0) return null;
      return (change / prevClose) * 100;
    }

    // 回退：使用歷史收盤價計算
    if (history.isEmpty) return null;

    final latestDate = DateContext.normalize(latestPrice.date);
    final historyLastDate = DateContext.normalize(history.last.date);

    // 判斷 history 是否已包含 latestPrice 的日期
    final historyIncludesLatest = historyLastDate == latestDate;

    double? prevClose;
    if (historyIncludesLatest) {
      // history 包含最新價格，前一日是倒數第二筆
      if (history.length < 2) return null;
      prevClose = history[history.length - 2].close;
    } else {
      // history 不包含最新價格，前一日是 history 的最後一筆
      prevClose = history.last.close;
    }

    if (prevClose == null || prevClose == 0) return null;

    return ((latestClose - prevClose) / prevClose) * 100;
  }

  /// 批次計算多檔股票的漲跌幅
  ///
  /// 輸入股票代號對應的價格歷史與最新價格，
  /// 回傳股票代號對應的漲跌幅百分比。
  static Map<String, double?> calculatePriceChangesBatch(
    Map<String, List<DailyPriceEntry>> priceHistories,
    Map<String, DailyPriceEntry> latestPrices,
  ) {
    final result = <String, double?>{};

    for (final symbol in latestPrices.keys) {
      final history = priceHistories[symbol];
      final latestPrice = latestPrices[symbol];

      // 不可在 history 為空時直接短路回 null：
      // calculatePriceChange 會優先使用 latestPrice.priceChange（API 提供），
      // 即使 history 為空也能正確計算漲跌幅
      result[symbol] = calculatePriceChange(history ?? [], latestPrice);
    }

    return result;
  }

  /// 從價格歷史中提取最近 N 筆收盤價供 Sparkline 使用
  ///
  /// [priceHistory] 價格歷史（需按日期升序排列）
  /// [count] 要提取的資料筆數（預設 20）
  ///
  /// 回傳最近 N 筆的收盤價列表（過濾掉 null 值）
  static List<double> extractSparklinePrices(
    List<DailyPriceEntry> priceHistory, {
    int count = 20,
  }) {
    if (priceHistory.isEmpty) return [];

    final startIdx = priceHistory.length > count
        ? priceHistory.length - count
        : 0;
    return priceHistory
        .sublist(startIdx)
        .map((p) => p.close)
        .whereType<double>()
        .toList();
  }

  // ==================================================
  // 成交量計算
  // ==================================================

  /// 計算 N 日平均成交量
  ///
  /// [prices] 價格資料（需按日期升序排列）
  /// [days] 計算的天數（預設 5）
  /// [skipLast] 是否跳過最後一筆（今日），預設 false
  /// [filterZero] 是否過濾停牌日（成交量為 0），預設 false
  /// [minValidDays] 過濾後的最低有效日數,不足回 null(預設 1 = 舊行為)
  ///
  /// 回傳平均成交量。**注意退化語意**(2026-08-15 審計修正 doc):資料
  /// 短於 [days] 時是「有幾筆算幾筆」的短均量、不回 null——只有輸入為
  /// 空/全被濾/有效日不足 [minValidDays] 才回 null。呼叫端要求「必須
  /// 滿 N 個有效日」時請傳 [minValidDays]。
  static double? calculateAverageVolume(
    List<DailyPriceEntry> prices, {
    int days = 5,
    bool skipLast = false,
    bool filterZero = false,
    int minValidDays = 1,
  }) {
    if (prices.isEmpty) return null;

    // 從後往前取資料
    var source = prices.reversed;
    if (skipLast) {
      source = source.skip(1);
    }

    final volumes = source
        .take(days)
        .map((p) => p.volume ?? 0.0)
        .where((v) => !filterZero || v > 0)
        .toList();

    if (volumes.isEmpty || volumes.length < minValidDays) return null;

    return volumes.reduce((a, b) => a + b) / volumes.length;
  }

  /// 檢查今日成交量是否超過平均量的倍數
  ///
  /// [prices] 價格資料（需按日期升序排列）
  /// [multiplier] 倍數門檻（預設 1.5）
  /// [days] 計算平均的天數（預設 5）
  ///
  /// 回傳 true 表示今日成交量超過平均量的指定倍數
  /// 今日量是否達近 [days] 日均量的 [multiplier] 倍。
  ///
  /// **停牌日必須濾除**(2026-08-15 稽核):0 量被當有效觀測會稀釋分母——
  /// 5 日窗含 1 個停牌日時 1.5 倍門檻實質降到 1.2 倍、2 個停牌日降到 0.9 倍
  /// (低於平均量也算「量增」)。實測近 5 日窗含停牌日的股票有 34 檔。
  static bool isVolumeAboveAverage(
    List<DailyPriceEntry> prices, {
    double multiplier = 1.5,
    int days = 5,
  }) {
    if (prices.isEmpty) return false;

    final todayVolume = prices.last.volume;
    if (todayVolume == null || todayVolume <= 0) return false;

    final avgVolume = calculateAverageVolume(
      prices,
      days: days,
      skipLast: true,
      filterZero: true,
    );

    if (avgVolume == null || avgVolume <= 0) return false;

    return todayVolume >= avgVolume * multiplier;
  }
}

// ==================================================
// K 線驗證 Extension
// ==================================================

/// K 線資料驗證擴展
///
/// 提供 [DailyPriceEntry] 常用的 null 檢查方法，
/// 減少 K 線型態規則中的重複驗證邏輯
extension CandleValidation on DailyPriceEntry {
  /// 檢查 OHLC 四項價格是否皆有效（非 null）
  ///
  /// 用於需要完整 K 線資料的型態判斷（如錘子線、十字線）
  bool get hasValidOHLC =>
      open != null && high != null && low != null && close != null;

  /// 檢查開盤價與收盤價是否皆有效（非 null）
  ///
  /// 用於僅需判斷 K 線方向的場景（如吞噬型態、連續漲跌）
  bool get hasValidOpenClose => open != null && close != null;

  /// 取得實體大小（絕對值）
  ///
  /// 若開盤或收盤為 null，回傳 0
  double get bodySize {
    if (open == null || close == null) return 0;
    return (close! - open!).abs(); // Safe: null check above
  }

  /// 判斷是否為紅 K（收盤 > 開盤）
  ///
  /// 若資料無效，回傳 false
  // Safe: hasValidOpenClose guarantees open/close non-null
  bool get isBullish {
    if (!hasValidOpenClose) return false;
    return close! > open!;
  }

  /// 判斷是否為黑 K（收盤 < 開盤）
  ///
  /// 若資料無效，回傳 false
  // Safe: hasValidOpenClose guarantees open/close non-null
  bool get isBearish {
    if (!hasValidOpenClose) return false;
    return close! < open!;
  }

  /// 取得振幅（最高價 - 最低價）
  ///
  /// 若 high 或 low 為 null，回傳 0
  double get range {
    if (high == null || low == null) return 0;
    return high! - low!; // Safe: null check above
  }

  /// 取得上影線長度
  ///
  /// 上影線 = 最高價 - max(開盤, 收盤)
  /// 若 OHLC 資料不完整，回傳 0
  // Safe: hasValidOHLC guarantees all OHLC fields non-null
  double get upperShadow {
    if (!hasValidOHLC) return 0;
    return high! - max(open!, close!);
  }

  /// 取得下影線長度
  ///
  /// 下影線 = min(開盤, 收盤) - 最低價
  /// 若 OHLC 資料不完整，回傳 0
  // Safe: hasValidOHLC guarantees all OHLC fields non-null
  double get lowerShadow {
    if (!hasValidOHLC) return 0;
    return min(open!, close!) - low!;
  }
}

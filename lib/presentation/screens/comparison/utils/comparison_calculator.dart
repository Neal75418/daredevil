import 'dart:math';

import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/stock_summary.dart';

/// 比較表的純計算工具。
///
/// 所有方法皆為 static，不依賴 [BuildContext]。
/// [Color] 視為純資料（來自 [AppTheme]）。
abstract final class ComparisonCalculator {
  // ==================================================
  // 1) Winner detection
  // ==================================================

  /// 從一組可為 null 的數值中，回傳「最佳」值的索引。
  ///
  /// 當 [higherIsBetter] 為 `true` 時，最大的非 null 值勝出；
  /// 反之最小值勝出。當所有值皆為 `null` 時回傳 `null`。
  static int? findWinnerIndex(
    List<double?> values, {
    required bool higherIsBetter,
  }) {
    int? bestIdx;
    double? bestVal;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      if (bestVal == null || (higherIsBetter ? v > bestVal : v < bestVal)) {
        bestVal = v;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  // ==================================================
  // 2) Price return calculation
  // ==================================================

  /// 根據價格 [history]，計算指定 [tradingDays] 交易日的報酬率百分比。
  ///
  /// 回傳 record 包含：
  /// - `display`：格式化字串如 `"+12.3%"` 或 `"-5.1%"`，資料不足時為 `"-"`。
  /// - `numeric`：原始百分比值（供比較用），或 `null`。
  /// - `color`：根據正負號對應的漲跌顏色。
  static ({String display, double? numeric, Color? color}) calculatePriceReturn(
    List<DailyPriceEntry>? history,
    int tradingDays,
    Brightness brightness,
  ) {
    if (history == null || history.isEmpty) {
      return (display: '-', numeric: null, color: null);
    }

    final sorted = List<DailyPriceEntry>.from(history)
      ..sort((a, b) => a.date.compareTo(b.date));
    final startIdx = max(0, sorted.length - tradingDays);
    final startPrice = sorted[startIdx].close;
    final endPrice = sorted.last.close;

    if (startPrice == null || startPrice == 0 || endPrice == null) {
      return (display: '-', numeric: null, color: null);
    }

    final pct = ((endPrice / startPrice) - 1) * 100;
    // 與顯示文字同精度捨入後再判方向，避免平盤「+0.0%」或微負值著色矛盾
    final rounded = AppNumberFormat.roundForDisplay(pct, 1);
    final display = AppNumberFormat.signedPercent(pct, decimals: 1);
    final color = rounded == 0
        ? null
        : AppTheme.getPriceColor(rounded, brightness);

    return (display: display, numeric: pct, color: color);
  }

  // ==================================================
  // 3) Institutional net aggregation
  // ==================================================

  /// 法人買賣超的彙總窗：最近幾個交易日（對應「外資5日淨買」等欄位標籤）。
  static const int institutionalNetDays = 5;

  /// 依日期取最近 [institutionalNetDays] 筆。DAO 依日期升冪回傳、查詢窗通常比
  /// 5 個交易日寬，直接取前 5 筆會拿到最舊的幾天，所以不依賴輸入順序。
  static Iterable<DailyInstitutionalEntry> _latestInstitutional(
    List<DailyInstitutionalEntry> entries,
  ) {
    final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(institutionalNetDays);
  }

  /// 使用 [getNet] 存取器，彙總最近 [institutionalNetDays] 個交易日的法人買賣超，
  /// 回傳格式化顯示值（以張為單位，即 /1000）、原始合計值（股）及對應顏色。
  static ({String display, double? numeric, Color? color})
  aggregateInstitutionalNet(
    List<DailyInstitutionalEntry>? entries,
    double Function(DailyInstitutionalEntry) getNet,
    Brightness brightness,
  ) {
    if (entries == null || entries.isEmpty) {
      return (display: '-', numeric: null, color: null);
    }

    double total = 0;
    for (final entry in _latestInstitutional(entries)) {
      total += getNet(entry);
    }

    final lots = (total / 1000).round();
    // 顯示以「張」為單位；配色須與捨入後張數一致（<500 股顯示 0 張即中性）
    final display = '${lots > 0 ? "+" : ""}$lots';
    final color = lots == 0
        ? null
        : AppTheme.getPriceColor(lots.toDouble(), brightness);

    return (display: display, numeric: total, color: color);
  }

  /// 雷達圖法人軸的滿分範圍：±5,000 萬股（5 萬張）。
  static const double foreignNetRadarFullScaleShares = 5e7;

  /// 雷達圖法人軸：最近 [institutionalNetDays] 個交易日外資淨買超（股）換算
  /// 0~100，[foreignNetRadarFullScaleShares] 為滿分範圍；無資料回中性 50。
  static double foreignNetRadarScore(List<DailyInstitutionalEntry>? entries) {
    if (entries == null || entries.isEmpty) return 50;
    double totalNet = 0;
    for (final entry in _latestInstitutional(entries)) {
      totalNet += entry.foreignNet ?? 0;
    }
    return ((totalNet / foreignNetRadarFullScaleShares) * 50 + 50).clamp(
      0,
      100,
    );
  }

  // ==================================================
  // 4) Sentiment conversion
  // ==================================================

  /// 將 [SummarySentiment] 對應為數值分數（0.0 -- 4.0）以供比較。
  ///
  /// 輸入為 `null` 時回傳 `null`。
  static double? sentimentToNumeric(SummarySentiment? sentiment) {
    if (sentiment == null) return null;
    return switch (sentiment) {
      SummarySentiment.strongBullish => 4.0,
      SummarySentiment.bullish => 3.0,
      SummarySentiment.neutral => 2.0,
      SummarySentiment.bearish => 1.0,
      SummarySentiment.strongBearish => 0.0,
    };
  }

  /// 將 [SummarySentiment] 對應為其對應的 [Color]。
  ///
  /// 輸入為 `null` 時回傳 `null`。
  static Color? sentimentToColor(
    SummarySentiment? sentiment,
    Brightness brightness,
  ) {
    if (sentiment == null) return null;
    return switch (sentiment) {
      SummarySentiment.strongBullish => AppTheme.upColor,
      SummarySentiment.bullish => AppTheme.upColor,
      SummarySentiment.neutral => PriceColors.flatFor(brightness),
      SummarySentiment.bearish => PriceColors.downFor(brightness),
      SummarySentiment.strongBearish => PriceColors.downFor(brightness),
    };
  }
}

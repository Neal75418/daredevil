import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/l10n/app_strings.dart';

/// 優化的迷你走勢圖 Widget
///
/// 效能優化：
/// 1. RepaintBoundary 將重繪與父元件隔離
/// 2. 資料正規化僅在建置時執行一次
/// 3. 最小化 LineChartData 設定
class MiniSparkline extends StatelessWidget {
  const MiniSparkline({
    super.key,
    required this.prices,
    required this.color,
    this.width,
    this.height,
  });

  final List<double> prices;
  final Color color;

  /// 圖表寬度（預設 70）
  final double? width;

  /// 圖表高度（預設 32）
  final double? height;

  /// 顯示的最大資料點數（為清晰呈現）；訊號卡說明的「近 N 個交易日」取此值
  static const int maxDataPoints = 20;

  /// 有意義圖表所需的最小資料點數
  static const int _minDataPoints = 5;

  /// 垂直間距百分比（上下各 10%）
  static const double _verticalPadding = 0.1;

  /// 間距後可用的內容範圍（1.0 - 2 * padding）
  static const double _contentRange = 0.8;

  /// 顯示圖表的最小價格變化百分比（0.3%）
  static const double _minVariationPercent = 0.003;

  /// 變化不到此百分比視為持平
  static const double _flatChangePercent = 0.1;

  /// 畫出來那段（最近 [maxDataPoints] 筆）的首尾漲跌百分比；不到
  /// [_flatChangePercent] 回 0（持平），資料不足回 null。
  ///
  /// 朗讀標籤與呼叫端的走勢圖配色共用這個值：看到的線、聽到的描述、
  /// 顏色三者一致（原本配色跟著今日漲跌，線往上卻是跌色）。
  static double? trendChangePercent(List<double> prices) {
    if (prices.length < _minDataPoints) return null;
    final sampled = _samplePrices(prices);
    final first = sampled.first;
    if (first <= 0) return 0;
    final change = (sampled.last - first) / first * 100;
    return change.abs() < _flatChangePercent ? 0 : change;
  }

  /// 建立無障礙語意標籤
  String _buildSemanticLabel(List<double> sampledPrices) {
    final change = trendChangePercent(sampledPrices);
    if (change == null) return S.sparklineDefault;
    final days = sampledPrices.length;
    if (change == 0) return S.sparklineFlat(days);
    return S.sparklineTrend(days, change);
  }

  @override
  Widget build(BuildContext context) {
    // 需至少 5 個資料點才能呈現有意義的視覺化
    if (prices.length < _minDataPoints) {
      return const SizedBox.shrink();
    }

    // 取樣最近 N 個交易日以獲得更清晰的呈現
    final sampledPrices = _samplePrices(prices);

    // 檢查是否有足夠的價格變化
    final result = _normalizeToSpots(sampledPrices);
    if (result == null) {
      return const SizedBox.shrink();
    }

    // 使用 RepaintBoundary 隔離圖表重繪
    return Semantics(
      label: _buildSemanticLabel(sampledPrices),
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: width ?? 70,
          height: height ?? 32,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 1,
              lineBarsData: [
                LineChartBarData(
                  spots: result,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: color,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.25),
                        color.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),
              ],
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
            ),
            duration: Duration.zero, // 停用動畫以提升效能
          ),
        ),
      ),
    );
  }

  /// 取樣價格至最近 N 個資料點以獲得更清晰的呈現
  static List<double> _samplePrices(List<double> prices) {
    if (prices.length <= maxDataPoints) return prices;
    return prices.sublist(prices.length - maxDataPoints);
  }

  /// 將價格正規化至 0-1 範圍以獲得一致的圖表高度
  /// 若變化不足以顯示有意義的圖表則回傳 null
  List<FlSpot>? _normalizeToSpots(List<double> prices) {
    if (prices.isEmpty) return null;
    if (prices.length == 1) return null;

    var min = prices[0];
    var max = prices[0];
    for (final price in prices) {
      if (price < min) min = price;
      if (price > max) max = price;
    }

    final range = max - min;
    final avgPrice = (max + min) / 2;
    final variationPercent = avgPrice > 0 ? range / avgPrice : 0;

    if (variationPercent < _minVariationPercent) {
      return null;
    }

    return List.generate(
      prices.length,
      (i) => FlSpot(
        i.toDouble(),
        ((prices[i] - min) / range) * _contentRange + _verticalPadding,
      ),
    );
  }
}

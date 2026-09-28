import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/presentation/providers/comparison_provider.dart';
import 'package:daredevil/presentation/screens/comparison/utils/comparison_calculator.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 雷達圖，跨 6 個維度比較股票。
///
/// 軸線：分數、價格表現、估值、營收、法人、AI 情緒。
/// 每個軸線正規化至 0-100。
class RadarComparisonChart extends StatelessWidget {
  const RadarComparisonChart({super.key, required this.state});

  final ComparisonState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.symbols.length < 2) return const SizedBox.shrink();

    final datasets = _buildDatasets(theme);
    if (datasets.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'accessibility.radarChart'.tr(),
      excludeSemantics: true,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'comparison.radarTitle'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: DesignTokens.spacing4),
              Text(
                'comparison.radarCaption'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DesignTokens.spacing8),
              SizedBox(
                height: 250,
                child: RadarChart(
                  RadarChartData(
                    dataSets: datasets,
                    radarBackgroundColor: Colors.transparent,
                    borderData: FlBorderData(show: false),
                    radarBorderData: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    tickBorderData: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                    ),
                    gridBorderData: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                    ),
                    tickCount: 4,
                    ticksTextStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 8,
                    ),
                    titlePositionPercentageOffset: 0.2,
                    titleTextStyle: theme.textTheme.labelSmall!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    getTitle: (index, angle) {
                      const labels = [
                        'comparison.metricScore',
                        'comparison.sectionPrice',
                        'comparison.sectionValuation',
                        'comparison.sectionRevenue',
                        'comparison.sectionInstitutional',
                        'comparison.sectionAI',
                      ];
                      if (index < labels.length) {
                        return RadarChartTitle(text: labels[index].tr());
                      }
                      return const RadarChartTitle(text: '');
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<RadarDataSet> _buildDatasets(ThemeData theme) {
    final datasets = <RadarDataSet>[];
    // Card 在淺色主題是 #FFFFFF，色盤需依主題明暗解析。
    final palette = DesignTokens.chartPaletteFor(theme);

    for (var i = 0; i < state.symbols.length; i++) {
      final symbol = state.symbols[i];
      final color = palette[i % palette.length];

      final values = _computeRadarValues(symbol);

      datasets.add(
        RadarDataSet(
          dataEntries: values.map((v) => RadarEntry(value: v)).toList(),
          fillColor: color.withValues(alpha: 0.1),
          borderColor: color,
          borderWidth: 2,
          entryRadius: 3,
        ),
      );
    }

    return datasets;
  }

  /// 計算股票的 6 個正規化數值（0-100）。
  List<double> _computeRadarValues(String symbol) {
    return [
      _scoreValue(symbol),
      _pricePerformanceValue(symbol),
      _valuationValue(symbol),
      _revenueValue(symbol),
      _institutionalValue(symbol),
      _sentimentValue(symbol),
    ];
  }

  /// 分數：直接對應 0-100（雷達圖預設顯示短線分數）
  double _scoreValue(String symbol) {
    return (state.analysesMap[symbol]?.scoreShort ?? 0).clamp(0, 100);
  }

  /// 價格表現：近 1 個月報酬率對應至 0-100（線性截斷）。
  /// -30% 以下 = 0，+30% 以上 = 100，0% = 50。
  double _pricePerformanceValue(String symbol) {
    final history = state.priceHistoriesMap[symbol];
    if (history == null || history.length < 2) return 50;

    final sorted = List<DailyPriceEntry>.from(history)
      ..sort((a, b) => a.date.compareTo(b.date));

    // 取約 20 個交易日前（約 1 個月）
    final startIndex = max(0, sorted.length - 20);
    final startPrice = sorted[startIndex].close ?? 0.0;
    final endPrice = sorted.last.close ?? 0.0;

    if (startPrice == 0) return 50;

    final returnPct = ((endPrice / startPrice) - 1) * 100;
    // 將 [-30, +30] 映射到 [0, 100]
    return ((returnPct + 30) / 60 * 100).clamp(0, 100);
  }

  /// 估值：P/E（越低越好）與殖利率（越高越好）的複合指標。
  /// P/E < 10 = 100，P/E > 40 = 0；殖利率 > 6% = 100，0% = 0。
  double _valuationValue(String symbol) {
    final valuation = state.valuationsMap[symbol];
    if (valuation == null) return 50;

    double score = 0;
    int count = 0;

    final pe = valuation.per;
    if (pe != null && pe > 0) {
      // P/E 越低越好：PE 10 → 100, PE 40 → 0
      score += ((40 - pe) / 30 * 100).clamp(0, 100);
      count++;
    }

    final yield_ = valuation.dividendYield;
    if (yield_ != null) {
      // 殖利率越高越好：0% → 0, 6% → 100
      score += (yield_ / 6 * 100).clamp(0, 100);
      count++;
    }

    return count > 0 ? score / count : 50;
  }

  /// 營收：年增率對應至 0-100。
  /// -50% = 0，+50% = 100，0% = 50。
  double _revenueValue(String symbol) {
    final revenueList = state.revenueMap[symbol];
    if (revenueList == null || revenueList.isEmpty) return 50;

    final yoy = revenueList.first.yoyGrowth;
    if (yoy == null) return 50;

    return ((yoy + 50) / 100 * 100).clamp(0, 100);
  }

  /// 法人：最近 5 個交易日外資淨買超。正值 = 偏多，負值 = 偏空。
  double _institutionalValue(String symbol) =>
      ComparisonCalculator.foreignNetRadarScore(state.institutionalMap[symbol]);

  /// 情緒：極度看多=95、看多=75、中性=50、看空=25、極度看空=5。
  double _sentimentValue(String symbol) {
    final summary = state.summariesMap[symbol];
    if (summary == null) return 50;

    return switch (summary.sentiment) {
      SummarySentiment.strongBullish => 95,
      SummarySentiment.bullish => 75,
      SummarySentiment.neutral => 50,
      SummarySentiment.bearish => 25,
      SummarySentiment.strongBearish => 5,
    };
  }
}

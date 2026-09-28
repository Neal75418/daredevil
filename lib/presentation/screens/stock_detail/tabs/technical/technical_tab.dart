import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/presentation/screens/stock_detail/tabs/technical/chart_indicators.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/technical/indicator_cards.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/technical/indicator_selectors.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/technical/ohlcv_card.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/k_line_chart_widget.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/utils/responsive_helper.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

/// 圖表時間範圍選項
enum ChartTimeRange {
  oneMonth(30, '1M'),
  threeMonths(90, '3M'),
  sixMonths(180, '6M'),
  oneYear(365, '1Y'),
  all(0, 'ALL'); // 0 表示全部資料

  const ChartTimeRange(this.days, this.label);
  final int days;
  final String label;
}

/// 技術分析分頁 - K 線圖 + 技術指標 + 成交量
class TechnicalTab extends ConsumerStatefulWidget {
  const TechnicalTab({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<TechnicalTab> createState() => _TechnicalTabState();
}

class _TechnicalTabState extends ConsumerState<TechnicalTab> {
  // 主圖指標（疊加於 K 線圖）：MA、BOLL、SAR
  final Set<ChartMainIndicator> _mainIndicators = {ChartMainIndicator.ma};
  // 副圖指標（子圖表）：MACD、KDJ、RSI、WR、CCI
  final Set<ChartSecondaryIndicator> _secondaryIndicators = {};
  // 時間範圍（預設 3 個月）
  ChartTimeRange _timeRange = ChartTimeRange.threeMonths;

  final TechnicalIndicatorService _indicatorService =
      TechnicalIndicatorService();

  void _toggleMainIndicator(ChartMainIndicator indicator) {
    setState(() {
      if (_mainIndicators.contains(indicator)) {
        _mainIndicators.remove(indicator);
      } else {
        _mainIndicators.add(indicator);
      }
    });
  }

  void _toggleSecondaryIndicator(ChartSecondaryIndicator indicator) {
    setState(() {
      if (_secondaryIndicators.contains(indicator)) {
        _secondaryIndicators.remove(indicator);
      } else {
        _secondaryIndicators.add(indicator);
      }
    });
  }

  void _setTimeRange(ChartTimeRange range) {
    setState(() {
      _timeRange = range;
    });
  }

  /// 選定時間範圍內的 K 棒數（null＝全部）。
  ///
  /// 2026-08-03 由「先截斷再傳圖表」改為「傳完整歷史＋只給顯示筆數」：
  /// 截斷版會讓 MA 在**截斷後**的資料上計算——1M 視圖只有約 20 根 bar，
  /// MA60 完全算不出來；3M 也只有右緣幾個點有值。指標必須在完整歷史上
  /// 算完，才截尾顯示（見 [KLineChartWidget.visibleCount]）。
  int? _visibleBarCount(List<DailyPriceEntry> history) {
    if (_timeRange == ChartTimeRange.all || history.isEmpty) return null;

    final cutoffDate = DateTime.now().subtract(Duration(days: _timeRange.days));
    // 只數 OHLC 齊全列(2026-08-05 複審):圖表建 K 棒會剔除缺值列,
    // 這裡若照數全列,sublist 起點前移、尾端多顯示範圍外的舊 K。
    return history
        .where(
          (entry) =>
              entry.date.isAfter(cutoffDate) &&
              entry.open != null &&
              entry.high != null &&
              entry.low != null &&
              entry.close != null,
        )
        .length;
  }

  /// 建立時間範圍選擇器
  Widget _buildTimeRangeSelector(ThemeData theme) {
    return SegmentedButton<ChartTimeRange>(
      segments: ChartTimeRange.values
          .map(
            (range) => ButtonSegment<ChartTimeRange>(
              value: range,
              label: Text(range.label),
            ),
          )
          .toList(),
      selected: {_timeRange},
      onSelectionChanged: (Set<ChartTimeRange> selection) {
        _setTimeRange(selection.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final priceState = ref.watch(
      stockDetailProvider(widget.symbol).select((s) => s.price),
    );
    final theme = Theme.of(context);

    if (priceState.priceHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.candlestick_chart_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: DesignTokens.spacing16),
            Text(
              'stockDetail.noTechnicalData'.tr(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // 依選取的副圖指標計算圖表高度
    final baseHeight = context.responsive(
      mobile: 320.0,
      tablet: 400.0,
      desktop: 450.0,
    );
    final secondaryHeight = _secondaryIndicators.isEmpty
        ? 0.0
        : 120.0 * _secondaryIndicators.length;
    final totalChartHeight = baseHeight + secondaryHeight;

    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(DesignTokens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // K 線圖區段
          SectionHeader(
            title: 'stockDetail.klineChart'.tr(),
            icon: Icons.candlestick_chart,
          ),
          const SizedBox(height: DesignTokens.spacing12),

          // 主圖指標選擇（MA、BOLL、SAR）
          MainIndicatorSelector(
            selectedIndicators: _mainIndicators,
            onToggle: _toggleMainIndicator,
          ),
          const SizedBox(height: DesignTokens.spacing8),

          // 時間區間選擇
          _buildTimeRangeSelector(theme),
          const SizedBox(height: DesignTokens.spacing12),

          // 含指標的 K 線圖
          KLineChartWidget(
            priceHistory: priceState.priceHistory,
            visibleCount: _visibleBarCount(priceState.priceHistory),
            mainIndicators: _mainIndicators,
            secondaryIndicators: _secondaryIndicators,
            height: totalChartHeight,
            maDayList: kTechnicalMaDayList,
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // 副圖指標選擇（MACD、KDJ、RSI、WR、CCI）
          SectionHeader(
            title: 'stockDetail.secondaryIndicators'.tr(),
            icon: Icons.show_chart,
          ),
          const SizedBox(height: DesignTokens.spacing8),
          SecondaryIndicatorSelector(
            selectedIndicators: _secondaryIndicators,
            onToggle: _toggleSecondaryIndicator,
          ),
          const SizedBox(height: DesignTokens.spacing16),

          // OHLCV 資料卡片
          OhlcvCard(
            latestPrice: priceState.latestPrice,
            priceChange: priceState.priceChange,
          ),

          // 詳細指標數值
          if (_secondaryIndicators.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spacing16),
            SectionHeader(
              title: 'stockDetail.indicatorValues'.tr(),
              icon: Icons.analytics,
            ),
            const SizedBox(height: DesignTokens.spacing12),
            IndicatorCardsSection(
              priceHistory: priceState.priceHistory,
              secondaryIndicators: _secondaryIndicators,
              mainIndicators: _mainIndicators,
              indicatorService: _indicatorService,
            ),
          ],
        ],
      ),
    );
  }
}

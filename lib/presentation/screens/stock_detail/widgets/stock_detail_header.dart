import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/extensions/trend_state_extension.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/providers/stock_detail_provider.dart';
import 'package:daredevil/presentation/widgets/reason_tags.dart';

/// Header 所需的最小資料集，用於 `.select()` 精確 rebuild
class StockHeaderData {
  const StockHeaderData({
    this.stockName,
    this.stockMarket,
    this.stockIndustry,
    this.latestClose,
    this.priceChange,
    this.trendState,
    this.support,
    this.resistance,
    this.reasons = const [],
    this.dataDate,
    this.hasDataMismatch = false,
    this.missingDomains = const [],
  });

  final String? stockName;
  final String? stockMarket;
  final String? stockIndustry;
  final double? latestClose;
  final double? priceChange;
  final String? trendState;
  final double? support;
  final double? resistance;
  final List<String> reasons;
  final DateTime? dataDate;
  final bool hasDataMismatch;

  /// 缺漏的資料 domain（i18n keys）。「無資料 ≈ 無訊號」的混淆解方：
  /// 基本面/籌碼缺漏的股票分數天然偏低，UI 必須提示「偏低可能因資料
  /// 缺漏、非真的弱」。空 = 齊全、不顯示（零噪音）。
  final List<String> missingDomains;

  /// 從完整 StockDetailState 投影
  factory StockHeaderData.fromState(StockDetailState s) => StockHeaderData(
    stockName: s.stockName,
    stockMarket: s.stockMarket,
    stockIndustry: s.stockIndustry,
    latestClose: s.latestClose,
    priceChange: s.priceChange,
    trendState: s.price.analysis?.trendState,
    support: s.price.analysis?.supportLevel,
    resistance: s.price.analysis?.resistanceLevel,
    reasons: s.reasons.map((r) => r.reasonType).toList(),
    dataDate: s.dataDate,
    hasDataMismatch: s.hasDataMismatch,
    // 首次載入中不判定缺漏（避免非同步子狀態未到位時閃現假提示）；已有
    // 內容的背景重載沿用現有資料判定，提示不隨重載消失再出現
    missingDomains: _computeMissingDomains(s),
  );

  /// 缺漏 domain 判定。ETF（00 開頭）天生無財報——營收/EPS/估值三個
  /// domain 對 ETF 豁免（比照 `FundamentalSyncer` 的 isEtfCode 跳過邏輯），
  /// 否則提示會對所有 ETF 永久誤報。
  static List<String> _computeMissingDomains(StockDetailState s) {
    if ((s.loading.isLoading && !s.hasContent) ||
        s.loading.isLoadingFundamentals ||
        s.loading.isLoadingChip) {
      return const [];
    }
    final symbol = s.price.stock?.symbol ?? '';
    final isEtf = StockPatterns.isEtfCode(symbol);
    return [
      if (s.price.priceHistory.isEmpty) 'stockDetail.domain.price',
      if (s.chip.institutionalHistory.isEmpty)
        'stockDetail.domain.institutional',
      if (!isEtf && s.fundamentals.revenueHistory.isEmpty)
        'stockDetail.domain.revenue',
      if (!isEtf && s.fundamentals.epsHistory.isEmpty) 'stockDetail.domain.eps',
      if (!isEtf && s.fundamentals.latestPER == null)
        'stockDetail.domain.valuation',
      // 籌碼分佈是**延遲載入**的：loadChipData() 的唯一呼叫點是籌碼分頁，
      // 使用者沒開過那頁時此清單本來就是空的。上方的 isLoadingChip 守門
      // 擋不住——「從未開始載入」時該旗標同樣是 false。
      //
      // 實機（2026-07-26，2357）：摘要頁常駐「資料缺漏：籌碼分佈」，但 DB
      // 有 45 列，且全市場 2,129 檔有價格的股票**沒有任何一檔缺這份資料**。
      // 一個對每檔股票都出現的假警告會訓練使用者忽略警告，真的缺資料時
      // 反而看不見。
      //
      // chipStrength 是 loadChipData 自身的「已載入」哨兵，此處同源使用：
      // 未載入 = 未知，不是缺漏。
      if (s.chip.chipStrength != null && s.chip.holdingDistribution.isEmpty)
        'stockDetail.domain.distribution',
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockHeaderData &&
          stockName == other.stockName &&
          stockMarket == other.stockMarket &&
          stockIndustry == other.stockIndustry &&
          latestClose == other.latestClose &&
          priceChange == other.priceChange &&
          trendState == other.trendState &&
          support == other.support &&
          resistance == other.resistance &&
          listEquals(reasons, other.reasons) &&
          dataDate == other.dataDate &&
          hasDataMismatch == other.hasDataMismatch &&
          listEquals(missingDomains, other.missingDomains);

  @override
  int get hashCode => Object.hash(
    stockName,
    stockMarket,
    latestClose,
    priceChange,
    trendState,
    dataDate,
    hasDataMismatch,
    Object.hashAll(missingDomains),
  );
}

/// 股票詳情頁的 Header 區塊
///
/// 顯示股票名稱、價格、漲跌幅、趨勢與支撐壓力等資訊
class StockDetailHeader extends StatelessWidget {
  const StockDetailHeader({
    super.key,
    required this.data,
    required this.symbol,
    this.isCalibrationBacked,
  });

  final StockHeaderData data;

  /// 判定 reason code 是否經校準背書；null → 用 registry（見 ReasonTags）
  final bool Function(String code)? isCalibrationBacked;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceChange = data.priceChange;
    // 與顯示文字同精度（2 位）捨入後再判方向，讓箭頭/漸層/配色與數字一致：
    // 平盤或微負值（-0.004→顯示 0.00%）一律中性，不顯示漲跌箭頭或方向色。
    final displayedChange = priceChange == null
        ? null
        : AppNumberFormat.roundForDisplay(priceChange, 2);
    final isNeutral = displayedChange == null || displayedChange == 0;
    final isPositive = (displayedChange ?? 0) > 0;
    final priceColor = AppTheme.getPriceColor(
      displayedChange,
      theme.brightness,
    );

    return Semantics(
      label: _buildSemanticLabel(),
      container: true,
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.spacing16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildNameRow(theme),
                      const SizedBox(height: DesignTokens.spacing4),
                      if (data.reasons.isNotEmpty) _buildReasonTags(theme),
                    ],
                  ),
                ),
                _buildPriceColumn(
                  theme,
                  priceChange,
                  isPositive,
                  isNeutral,
                  priceColor,
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacing12),
            _buildTrendRow(theme),
          ],
        ),
      ),
    );
  }

  String _buildSemanticLabel() {
    final parts = <String>[];
    final name = data.stockName;
    if (name != null) parts.add(name);
    parts.add(symbol);
    final close = data.latestClose;
    if (close != null) {
      parts.add(S.accessibilityClosePrice(close.toStringAsFixed(2)));
    }
    final change = data.priceChange;
    if (change != null) {
      final absChange = _calculateAbsoluteChange(close, change);
      final absText = absChange != null
          ? '${S.accessibilityAbsoluteChange(AppNumberFormat.signedFixed(absChange, decimals: 2))}, '
          : '';
      final pctText = AppNumberFormat.signedPercent(change, decimals: 2);
      parts.add(S.accessibilityPriceChangeDetail(absText, pctText));
    }
    final trend = data.trendState;
    if (trend != null) parts.add(S.accessibilityTrend(trend.trendKey));
    return parts.join(', ');
  }

  Widget _buildNameRow(ThemeData theme) {
    return Row(
      children: [
        Flexible(
          child: Text(
            data.stockName ?? symbol,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (data.stockMarket == MarketCode.tpex) ...[
          const SizedBox(width: DesignTokens.spacing8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing6,
              vertical: DesignTokens.spacing2,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Text(
              'stockDetail.otcBadge'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        if (data.stockIndustry != null && data.stockIndustry!.isNotEmpty) ...[
          const SizedBox(width: DesignTokens.spacing8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing6,
                vertical: DesignTokens.spacing2,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              ),
              child: Text(
                data.stockIndustry!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReasonTags(ThemeData theme) {
    final backedFn =
        isCalibrationBacked ??
        (code) => CalibratedScoresRegistry.instance.isCalibrationBacked(code);
    return Wrap(
      spacing: DesignTokens.spacing6,
      runSpacing: DesignTokens.spacing4,
      children: data.reasons.take(3).map((reason) {
        final backed = backedFn(reason);
        final onColor = theme.colorScheme.onPrimaryContainer;
        final chip = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacing8,
            vertical: DesignTokens.spacing2,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (backed) ...[
                Icon(Icons.verified_outlined, size: 12, color: onColor),
                const SizedBox(width: DesignTokens.spacing4),
              ],
              Text(
                ReasonTags.translateReasonCode(reason),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
        if (!backed) return chip;
        return Tooltip(
          message: 'reasonTags.calibrationBackedNote'.tr(),
          triggerMode: TooltipTriggerMode.tap,
          preferBelow: true,
          child: chip,
        );
      }).toList(),
    );
  }

  /// 從收盤價與漲跌幅百分比反算絕對漲跌金額
  double? _calculateAbsoluteChange(double? close, double? pctChange) {
    if (close == null || pctChange == null || pctChange == 0) return null;
    return close * pctChange / (100 + pctChange);
  }

  Widget _buildPriceColumn(
    ThemeData theme,
    double? priceChange,
    bool isPositive,
    bool isNeutral,
    Color priceColor,
  ) {
    final absChange = _calculateAbsoluteChange(data.latestClose, priceChange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          data.latestClose?.toStringAsFixed(2) ?? '-',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontFamily: 'RobotoMono',
            fontSize: 32,
            letterSpacing: -1,
          ),
        ),
        if (priceChange != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing10,
              vertical: DesignTokens.spacing4,
            ),
            decoration: BoxDecoration(
              // 漸層取自 priceColor（平盤=中性灰、漲=紅、跌=綠），與邊框/文字一致
              gradient: LinearGradient(
                colors: [
                  priceColor.withValues(alpha: 0.2),
                  priceColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(color: priceColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNeutral
                      ? Icons.trending_flat
                      : (isPositive ? Icons.north : Icons.south),
                  size: 14,
                  color: priceColor,
                ),
                const SizedBox(width: DesignTokens.spacing4),
                Text(
                  _formatDetailChangeText(absChange, priceChange, isNeutral),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: priceColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        if (data.dataDate != null)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacing4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data.hasDataMismatch)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: DesignTokens.spacing4,
                    ),
                    child: Icon(
                      Icons.sync_problem,
                      size: 12,
                      color: theme.colorScheme.error,
                    ),
                  ),
                Text(
                  _formatDataDate(data.dataDate!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: data.hasDataMismatch
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        // 資料完整度提示（評分改進 #8）：缺漏 domain 的股票分數天然偏低，
        // 不提示會讓「無資料」被誤讀成「訊號弱」。齊全時零噪音。
        if (data.missingDomains.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacing4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: DesignTokens.spacing4),
                Flexible(
                  child: Text(
                    'stockDetail.dataMissing'.tr(
                      namedArgs: {
                        'domains': data.missingDomains
                            .map((k) => k.tr())
                            .join('、'),
                      },
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTrendRow(ThemeData theme) {
    final trendState = data.trendState;

    // 三個 chip 並排在 EN locale 或字體放大時可能超出窄螢幕寬度
    // （iPhone SE ≈ 343px 可用寬，三 chip 自然寬約 311px，邊界）。
    // 改用 Wrap 讓 chip 必要時換行，避免 RenderFlex overflow。
    return Wrap(
      spacing: DesignTokens.spacing8,
      runSpacing: DesignTokens.spacing8,
      children: [
        // 沒有當日分析時**不渲染**，而非退回「盤整」——`?? 'sideways'` 會把
        // 「這檔今天沒被評分」講成一個明確的趨勢宣稱。
        // 實測 2026-07-24：有價格 2,127 檔、被評分僅 154 檔，其餘 1,973 檔
        // （93%）打開都會看到「盤整」；台積電當日 -2.29%、前一個分析日是 DOWN。
        // 做法與下方支撐/壓力徽章一致（本來就在 null 時不渲染）。
        // RANGE 是合法分析結果，仍會走到這裡並正確顯示「盤整」。
        if (trendState != null)
          _InfoChip(
            label: 'trend.${trendState.trendKey}'.tr(),
            icon: trendState.trendIconData,
            color: trendState.trendColorFor(theme.brightness),
          ),
        if (data.support case final supportLevel?)
          _LevelChip(
            label: 'stockDetail.support'.tr(),
            value: supportLevel,
            color: AppTheme.downColor,
          ),
        if (data.resistance case final resistanceLevel?)
          _LevelChip(
            label: 'stockDetail.resistance'.tr(),
            value: resistanceLevel,
            color: AppTheme.upColor,
          ),
      ],
    );
  }

  /// 格式化詳情頁漲跌文字：有絕對金額時顯示「+2.50 (+1.67%)」。
  /// 平盤（捨入歸零）只顯示中性的「0.00%」，不帶 + 也不顯示負零。
  String _formatDetailChangeText(
    double? absChange,
    double priceChange,
    bool isNeutral,
  ) {
    final pctText = AppNumberFormat.signedPercent(priceChange, decimals: 2);
    if (absChange != null && !isNeutral) {
      return '${AppNumberFormat.signedFixed(absChange, decimals: 2)} ($pctText)';
    }
    return pctText;
  }

  String _formatDataDate(DateTime date) {
    final now = DateTime.now();
    final today = DateContext.normalize(now);
    final dataDay = DateContext.normalize(date);

    if (dataDay == today) {
      return 'stockDetail.dataToday'.tr();
    } else if (dataDay == today.subtract(const Duration(days: 1))) {
      return 'stockDetail.dataYesterday'.tr();
    } else {
      return '${date.month}/${date.day} ${'stockDetail.dataLabel'.tr()}';
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing10,
        vertical: DesignTokens.spacing6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: PriceColors.onTintOf(color, Theme.of(context).brightness),
          ),
          const SizedBox(width: DesignTokens.spacing6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: PriceColors.onTintOf(color, Theme.of(context).brightness),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing10,
        vertical: DesignTokens.spacing6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: DesignTokens.spacing6),
          Text(
            '$label ${value.toStringAsFixed(1)}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

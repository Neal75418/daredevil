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
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
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
    this.open,
    this.high,
    this.low,
    this.volumeShares,
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

  /// 正式資料那一筆的開高低與成交量(股);上方「開高低量」列用
  final double? open;
  final double? high;
  final double? low;
  final double? volumeShares;

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
    open: s.price.latestPrice?.open,
    high: s.price.latestPrice?.high,
    low: s.price.latestPrice?.low,
    volumeShares: s.price.latestPrice?.volume,
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
          listEquals(missingDomains, other.missingDomains) &&
          open == other.open &&
          high == other.high &&
          low == other.low &&
          volumeShares == other.volumeShares;

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
    open,
    high,
    low,
    volumeShares,
  );
}

/// 個股頁上方的即時報價(只有用即時報價時才有;見 `LiveQuoteMerge`)
@immutable
class StockHeaderLive {
  const StockHeaderLive({
    required this.price,
    required this.changePercent,
    required this.change,
    required this.statusText,
    this.open,
    this.high,
    this.low,
    this.volumeLots,
    this.flash,
    this.flashEnabled = true,
  });

  final double price;
  final double? changePercent;

  /// 漲跌金額(現價 − MIS 昨收)
  final double change;

  /// 放在原「資料日期」位置的狀態(報價時間／今日收盤／最後報價／暫停)
  final String statusText;
  final double? open;
  final double? high;
  final double? low;

  /// 累計成交量(張,MIS v)
  final int? volumeLots;
  final LiveQuoteFlash? flash;
  final bool flashEnabled;

  /// 合併結果是即時報價時建立;否則 null(上方維持盤後資料)
  static StockHeaderLive? from({
    required MergedPrice merged,
    required LiveQuoteState state,
    required bool flashEnabled,
  }) {
    final live = merged.live;
    final price = merged.price;
    final previous = merged.previousClose;
    if (merged.kind != MergedPriceKind.live ||
        live == null ||
        price == null ||
        previous == null) {
      return null;
    }
    return StockHeaderLive(
      price: price,
      changePercent: merged.changePercent,
      change: price - previous,
      statusText:
          LiveQuoteStatusRule.header(
            state: state,
            merged: [merged],
            intradayTime: merged.quoteTime,
          )?.text() ??
          '',
      open: live.open,
      high: live.high,
      low: live.low,
      volumeLots: live.volumeLots,
      flash: live.flash,
      flashEnabled: flashEnabled,
    );
  }
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
    this.live,
    this.limitStatus = PriceLimitStatus.none,
  });

  final StockHeaderData data;

  /// 判定 reason code 是否經校準背書；null → 用 registry（見 ReasonTags）
  final bool Function(String code)? isCalibrationBacked;
  final String symbol;

  /// 盤中即時報價;null = 盤後資料
  final StockHeaderLive? live;

  /// 漲跌停狀態(由畫面以 `PriceLimit.statusOf` 算好傳入)
  final PriceLimitStatus limitStatus;

  double? get _close => live?.price ?? data.latestClose;

  double? get _changePercent {
    final l = live;
    return l != null ? l.changePercent : data.priceChange;
  }

  double? get _absChange {
    final l = live;
    return l != null
        ? l.change
        : _calculateAbsoluteChange(data.latestClose, data.priceChange);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceChange = _changePercent;
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
            _buildTradingRow(theme),
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
    final close = _close;
    if (close != null) {
      parts.add(S.accessibilityClosePrice(close.toStringAsFixed(2)));
    }
    final change = _changePercent;
    if (change != null) {
      final absChange = _absChange;
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
    final absChange = _absChange;
    final live = this.live;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        PriceFlash(
          flash: live?.flash,
          enabled: live?.flashEnabled ?? true,
          child: Text(
            _close?.toStringAsFixed(2) ?? '-',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: 'RobotoMono',
              fontSize: 32,
              letterSpacing: -1,
            ),
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
        if (limitStatus != PriceLimitStatus.none)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacing4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.getPriceColor(
                  limitStatus.isUp ? 1 : -1,
                  theme.brightness,
                ),
                borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              ),
              child: Text(
                S.priceLimitLabel(limitStatus),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (live != null)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacing4),
            child: Text(
              live.statusText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (data.dataDate != null)
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

  /// 開盤、最高、最低、成交量(張)。即時用 MIS 的張數;盤後把股數除以 1,000。
  ///
  /// 自己佔一列、逐項換行:放進右側價格欄會把整列撐爆(手機寬度下左側股名欄
  /// 被擠掉),見 header 測試的手機版面情境。
  Widget _buildTradingRow(ThemeData theme) {
    final l = live;
    final open = l != null ? l.open : data.open;
    final high = l != null ? l.high : data.high;
    final low = l != null ? l.low : data.low;
    final lots = l != null
        ? l.volumeLots?.toDouble()
        : (data.volumeShares == null ? null : data.volumeShares! / 1000);
    if (open == null && high == null && low == null && lots == null) {
      return const SizedBox.shrink();
    }
    String price(double? v) => v?.toStringAsFixed(2) ?? '-';
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Builder(
      builder: (context) {
        final locale = Localizations.localeOf(context);
        return Padding(
          padding: const EdgeInsets.only(top: DesignTokens.spacing8),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: DesignTokens.spacing12,
              runSpacing: DesignTokens.spacing2,
              children: [
                Text('${'stockDetail.open'.tr()} ${price(open)}', style: style),
                Text('${'stockDetail.high'.tr()} ${price(high)}', style: style),
                Text('${'stockDetail.low'.tr()} ${price(low)}', style: style),
                Text(
                  '${'stockDetail.volume'.tr()} '
                  '${lots == null ? '-' : formatLots(lots, locale)}',
                  style: style,
                ),
              ],
            ),
          ),
        );
      },
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

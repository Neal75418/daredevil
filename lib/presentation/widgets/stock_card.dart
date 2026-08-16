import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/ui_constants.dart';
import 'package:daredevil/core/extensions/trend_state_extension.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/presentation/widgets/reason_tags.dart';
import 'package:daredevil/presentation/widgets/risk_badge_cluster.dart';
import 'package:daredevil/presentation/widgets/score_tier_badge.dart';
import 'package:daredevil/presentation/widgets/stock_card_price.dart';
import 'package:daredevil/presentation/widgets/stock_card_sparkline.dart';
import 'package:daredevil/presentation/widgets/warning_badge.dart';

/// 現代化股票資訊卡片 Widget
///
/// 特色：
/// - 採用微妙漸層的現代視覺設計
/// - 依照台灣慣例的價格顏色（紅色 = 上漲，綠色 = 下跌）
/// - 帶有顏色編碼的評分標章
/// - 趨勢指示器與圖示
/// - 微互動：輕微的按壓縮放動畫
/// - 可選的迷你走勢圖
class StockCard extends StatefulWidget {
  const StockCard({
    super.key,
    required this.symbol,
    this.stockName,
    this.market,
    this.latestClose,
    this.priceChange,
    this.score,
    this.dualScore,
    this.reasons = const [],
    this.trendState,
    this.isInWatchlist = false,
    this.onTap,
    this.onLongPress,
    this.onWatchlistTap,
    this.pinned,
    this.onPinToggle,
    this.recentPrices,
    this.warningType,
    this.warningReasons = const [],
    this.showLimitMarkers = true,
  });

  final String symbol;
  final String? stockName;

  /// 市場：'TWSE'（上市）或 'TPEx'（上櫃）
  final String? market;
  final double? latestClose;
  final double? priceChange;

  /// 單一 score（fallback）— 當 [dualScore] 為 null 時顯示單一 ScoreTierBadge
  final double? score;

  /// 釘選狀態（出場層 Phase 2）。null = 不顯示釘選鈕（掃描頁等不提供
  /// 釘選入口的清單）；[onPinToggle] 提供時才渲染。
  final bool? pinned;

  /// 點擊釘選鈕 callback（今日頁推薦卡入口）
  final VoidCallback? onPinToggle;

  /// 雙 horizon score (5D, 60D) — 給 Today screen Mode tab 用
  ///
  /// 不為 null 時，header 內顯示 tier 徽章＋5D/60D 雙數字
  /// （ScoreTierBadge.dual）。其他 caller（watchlist / scan）不傳此參數
  /// 就維持單一 ScoreTierBadge 行為。
  final (double, double)? dualScore;
  final List<String> reasons;
  final String? trendState;
  final bool isInWatchlist;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onWatchlistTap;
  final List<double>? recentPrices;

  /// 警示類型（注意股票、處置股票、高質押）— watchlist 等單一警示用
  final WarningBadgeType? warningType;

  /// 風險警訊類訊號（Today mode 卡片用）— 聚合成 [RiskBadgeCluster] 徽章。
  /// 與 [warningType] 在不同畫面使用、實務互斥；同時有值時 cluster 優先。
  final List<ReasonType> warningReasons;

  /// 是否顯示漲跌停標記
  final bool showLimitMarkers;

  @override
  State<StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<StockCard> {
  bool _isPressed = false;
  String? _cachedSemanticLabel;

  @override
  void didUpdateWidget(StockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cachedSemanticLabel = null;
  }

  /// 建立無障礙語意標籤
  String _buildSemanticLabel() {
    final parts = <String>[];
    parts.add(S.accessibilityStock(widget.symbol));
    if (widget.stockName != null) parts.add(widget.stockName!);
    if (widget.latestClose != null) {
      parts.add(S.accessibilityPrice(widget.latestClose!));
    }
    if (widget.priceChange != null) {
      parts.add(S.accessibilityPriceChange(widget.priceChange!));
      if (widget.showLimitMarkers) {
        if (PriceLimit.isLimitUp(widget.priceChange)) {
          parts.add(S.priceLimitUp);
        } else if (PriceLimit.isLimitDown(widget.priceChange)) {
          parts.add(S.priceLimitDown);
        }
      }
    }
    if (widget.score != null && widget.score! > 0) {
      parts.add(S.accessibilityScore(widget.score!.toInt()));
    }
    if (widget.trendState != null) {
      parts.add(S.getTrendLabel(widget.trendState));
    }
    if (widget.reasons.isNotEmpty) {
      parts.add(S.accessibilitySignals(widget.reasons.take(2).join(', ')));
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 先捨入到價格區塊的顯示精度（2 位）再取色，否則微負值會出現
    // 「文字 0.00% 卻著跌色」的矛盾（同 stock_preview_sheet 慣例）。
    final priceColor = AppTheme.getPriceColor(
      widget.priceChange == null
          ? null
          : AppNumberFormat.roundForDisplay(widget.priceChange!, 2),
      theme.brightness,
    );

    return Semantics(
      label: _cachedSemanticLabel ??= _buildSemanticLabel(),
      button: true,
      enabled: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: AnimDurations.press,
          curve: AnimCurves.enter,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.stockCardMarginH,
                  vertical: DesignTokens.stockCardMarginV,
                ),
                decoration: AppTheme.cardDecoration(
                  context,
                  isPremium: (widget.score ?? 0) >= 80,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onTap?.call();
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      widget.onLongPress?.call();
                    },
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                    child: Padding(
                      padding: const EdgeInsets.all(
                        DesignTokens.stockCardPadding,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // 緊湊模式：縮小字體/圖示/間距
                          final isCompactLayout =
                              constraints.maxWidth <
                              UiConstants.compactCardBreakpoint;
                          // Grid 固定高度時用 Flexible 防止垂直溢出
                          final isHeightConstrained =
                              constraints.maxHeight <
                              DesignTokens.stockCardHeight;
                          // 價格區塊是 Row 中佔最多寬度的元素，
                          // 需要比其他元素更早 compact 以釋放空間給訊號
                          final isCompactPrice =
                              constraints.maxWidth <
                              UiConstants.sparklineMinWidth;
                          // 走勢圖佔 78px，需要比 compact 更寬的門檻
                          final showSparkline =
                              !isCompactPrice &&
                              widget.recentPrices != null &&
                              widget.recentPrices!.length >= 7;

                          return Row(
                            children: [
                              // 趨勢指示器（響應式）
                              _buildTrendIndicator(compact: isCompactLayout),
                              SizedBox(
                                width: isCompactLayout
                                    ? DesignTokens.spacing8
                                    : DesignTokens.spacing12,
                              ),

                              // 股票資訊區塊
                              Expanded(
                                child: Column(
                                  // Grid 固定高度時用 max 才能讓
                                  // Flexible 正確分配剩餘空間
                                  mainAxisSize: isHeightConstrained
                                      ? MainAxisSize.max
                                      : MainAxisSize.min,
                                  // Grid 並排時垂直置中，對齊 Row 中其他
                                  // crossAxisAlignment.center 的元素
                                  mainAxisAlignment: isHeightConstrained
                                      ? MainAxisAlignment.center
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildHeader(theme),
                                    if (widget.stockName != null) ...[
                                      const SizedBox(
                                        height: DesignTokens.spacing2,
                                      ),
                                      _buildStockName(theme),
                                    ],
                                    if (widget.reasons.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      if (isHeightConstrained)
                                        Flexible(
                                          child: ClipRect(
                                            child: ReasonTags(
                                              reasons: widget.reasons,
                                              maxTags: isCompactLayout ? 1 : 2,
                                              translateCodes: true,
                                              size: ReasonTagSize.compact,
                                            ),
                                          ),
                                        )
                                      else
                                        ReasonTags(
                                          reasons: widget.reasons,
                                          maxTags: isCompactLayout ? 1 : 2,
                                          translateCodes: true,
                                          size: ReasonTagSize.compact,
                                        ),
                                    ],
                                  ],
                                ),
                              ),

                              SizedBox(
                                width: isCompactLayout
                                    ? DesignTokens.spacing6
                                    : DesignTokens.spacing12,
                              ),

                              // 迷你走勢圖（窄卡片時自動隱藏）
                              if (showSparkline) ...[
                                _buildSparkline(priceColor),
                                const SizedBox(width: 8),
                              ],

                              // 價格區塊（兩級響應式：400px 以下即 compact）
                              StockCardPriceSection(
                                latestClose: widget.latestClose,
                                priceChange: widget.priceChange,
                                showLimitMarkers: widget.showLimitMarkers,
                                priceColor: priceColor,
                                compact: isCompactPrice,
                              ),

                              // 自選按鈕（響應式）
                              if (widget.onWatchlistTap != null)
                                _buildWatchlistButton(
                                  theme,
                                  compact: isCompactLayout,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // 警示標記覆蓋層（cluster 優先於單一 warningType）
              if (widget.warningReasons.isNotEmpty)
                Positioned(
                  top: 0,
                  right: 12,
                  child: RiskBadgeCluster(warnings: widget.warningReasons),
                )
              else if (widget.warningType != null)
                Positioned(
                  top: 0,
                  right: 12,
                  child: WarningBadge(
                    type: widget.warningType!,
                    compact: true,
                    showIcon: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 趨勢狀態指示：箭頭圖示，但**中性色**
  ///
  /// 2026-08-16：原本配股價紅綠，與同一張卡右側的「當日漲跌」撞成同一種
  /// 視覺語言——但兩者講的是不同的事：這裡是多空結構（20MA vs 60MA），
  /// 那裡是今天的走勢。實測 36 檔自選股有 13 檔（36%）方向相反（仁寶趨勢
  /// DOWN 卻漲停 +9.92%）。
  ///
  /// 中間曾改成文字標籤（多頭／空頭／盤整），但 24px 的窄欄擠兩個中文字
  /// 實機看起來很醜，使用者直接回報——**改色不改形**才是這裡的正解：形狀
  /// 保留方向資訊與原本的緊湊度，去掉顏色就不再宣稱漲跌。紅綠自此在全 app
  /// 只代表股價（同款修正見警示頁的 `AlertTypeIcon`）。
  Widget _buildTrendIndicator({bool compact = false}) {
    final size = compact ? 18.0 : 24.0;

    // 未評分(trendState null)不得宣稱趨勢(2026-08-01 複審):d7a0f605 只
    // 修了 detail header,本卡片(自選/推薦高流量路徑)同型漏掃——nullable
    // extension 的 _ 分支把 null 畫成「持平」,沒評分卻給確定趨勢。
    if (widget.trendState == null) {
      return SizedBox(width: size, height: size);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          widget.trendState.trendIconData,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: size,
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    // 結構：左側內容（symbol+徽章）包在 Expanded 的內層 Row，釘選鈕
    // 剛性放外層右緣。loose Flexible 用不完的配額會變成該 Row 的尾端
    // 留白（不回填 Spacer）——留白限制在內層 Row 裡看不見的右側，
    // 釘選鈕才能恆貼 header 右緣；窄卡片時內層被壓縮、徽章以
    // FittedBox 等比縮小而非 overflow。
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  widget.symbol,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.dualScore != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ScoreTierBadge.dual(
                      shortScore: widget.dualScore!.$1,
                      longScore: widget.dualScore!.$2,
                    ),
                  ),
                ),
              ] else if (widget.score != null && widget.score! > 0) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ScoreTierBadge(score: widget.score!.toDouble()),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.onPinToggle != null)
          // 釘選論點（出場層）：outline = 未釘選、filled = 已釘選
          InkWell(
            onTap: widget.onPinToggle,
            borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                (widget.pinned ?? false)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                size: 16,
                color: (widget.pinned ?? false)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStockName(ThemeData theme) {
    final marketLabel = widget.market == MarketCode.tpex ? '櫃' : null;
    final isLimitUp =
        widget.showLimitMarkers && PriceLimit.isLimitUp(widget.priceChange);
    final isLimitDown =
        widget.showLimitMarkers && PriceLimit.isLimitDown(widget.priceChange);

    return Row(
      children: [
        Flexible(
          child: Text(
            widget.stockName!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (marketLabel != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Text(
              marketLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        // 漲停/跌停醒目標籤
        if (isLimitUp || isLimitDown) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.getPriceColor(
                widget.priceChange,
                Theme.of(context).brightness,
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Text(
              isLimitUp ? S.priceLimitUp : S.priceLimitDown,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 建立迷你走勢圖
  ///
  /// 新增防禦性 null 檢查，避免條件判斷與方法呼叫之間的競態條件
  Widget _buildSparkline(Color priceColor) {
    final prices = widget.recentPrices;
    if (prices == null || prices.length < 7) {
      return const SizedBox.shrink();
    }
    return MiniSparkline(prices: prices, color: priceColor);
  }

  Widget _buildWatchlistButton(ThemeData theme, {bool compact = false}) {
    final tooltipText = widget.isInWatchlist
        ? S.watchlistRemoveTooltip
        : S.watchlistAddTooltip;
    final iconSize = compact ? 20.0 : 26.0;
    return Padding(
      padding: EdgeInsets.only(left: compact ? 2 : 4),
      child: Semantics(
        label: tooltipText,
        button: true,
        child: IconButton(
          icon: Icon(
            widget.isInWatchlist
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            color: widget.isInWatchlist
                ? Colors.amber
                : theme.colorScheme.onSurfaceVariant,
            size: iconSize,
          ),
          tooltip: tooltipText,
          onPressed: () {
            HapticFeedback.mediumImpact();
            widget.onWatchlistTap?.call();
          },
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: compact ? EdgeInsets.zero : null,
          splashRadius: compact ? 18 : 20,
        ),
      ),
    );
  }
}

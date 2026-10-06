import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

/// 股票卡片的價格區塊 Widget
///
/// 顯示最新收盤價、絕對漲跌金額與漲跌幅百分比，包含漲跌停標記。
/// 格式符合台股慣例：▲2.50 (+1.67%)
class StockCardPriceSection extends StatelessWidget {
  const StockCardPriceSection({
    super.key,
    this.latestClose,
    this.priceChange,
    this.limitStatus = PriceLimitStatus.none,
    required this.priceColor,
    this.compact = false,
    this.flash,
    this.flashEnabled = true,
  });

  final double? latestClose;
  final double? priceChange;

  /// 漲跌停狀態(由 StockCard 以 `PriceLimit.statusOf` 算好傳入;本元件不自行推算)
  final PriceLimitStatus limitStatus;
  final Color priceColor;

  /// 緊湊模式：縮小字體、省略絕對漲跌金額，僅顯示百分比
  final bool compact;

  /// 本輪閃色事件(盤中即時報價;見 [PriceFlash])
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 從收盤價與漲跌幅百分比反算絕對漲跌金額
  double? get _absoluteChange {
    if (latestClose == null || priceChange == null || priceChange == 0) {
      return null;
    }
    // prevClose = latestClose / (1 + pct/100)
    // absoluteChange = latestClose - prevClose
    return latestClose! * priceChange! / (100 + priceChange!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 與顯示文字同精度（2 位）捨入後判方向：平盤與微負值（-0.004→0.00%）
    // 一律中性——不指方向、不帶正負號，與 stock_preview_sheet 同一慣例。
    final displayedChange = priceChange == null
        ? null
        : AppNumberFormat.roundForDisplay(priceChange!, 2);
    final isPositive = (displayedChange ?? 0) > 0;
    final isNeutral = displayedChange == null || displayedChange == 0;
    final isLimitUp = limitStatus.isUp;
    final isLimitDown = limitStatus.isDown;
    final absChange = _absoluteChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (latestClose != null)
          PriceFlash(
            flash: flash,
            enabled: flashEnabled,
            child: Text(
              latestClose!.toStringAsFixed(2),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: compact
                    ? DesignTokens.fontSizeMd
                    : DesignTokens.fontSizeXl,
                letterSpacing: 0.5,
                fontFamily: 'RobotoMono',
              ),
            ),
          ),
        if (priceChange != null) ...[
          SizedBox(
            height: compact ? DesignTokens.spacing2 : DesignTokens.spacing4,
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 8,
              vertical: compact ? 2 : 4,
            ),
            decoration: BoxDecoration(
              color: priceColor.withValues(alpha: isNeutral ? 0.1 : 0.15),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: (isLimitUp || isLimitDown)
                  ? Border.all(color: priceColor, width: 1.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 漲跌停標記
                if (isLimitUp || isLimitDown)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      isLimitUp
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: PriceColors.onTintOf(
                        priceColor,
                        Theme.of(context).brightness,
                      ),
                      size: compact ? 12 : 14,
                    ),
                  )
                // 裝飾圖示 - 文字已包含正負號
                else if (!isNeutral)
                  ExcludeSemantics(
                    child: Icon(
                      isPositive ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: PriceColors.onTintOf(
                        priceColor,
                        Theme.of(context).brightness,
                      ),
                      size: compact ? 14 : 18,
                    ),
                  ),
                Text(
                  compact
                      ? _formatCompactChangeText()
                      : _formatChangeText(absChange),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: PriceColors.onTintOf(
                      priceColor,
                      Theme.of(context).brightness,
                    ),
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? DesignTokens.fontSizeXs : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 格式化漲跌文字：有絕對金額時顯示「+2.50 (+1.67%)」，否則僅顯示百分比
  ///
  /// 正負號交由 [AppNumberFormat] 的「先捨入再判正負」處理，平盤與捨入
  /// 歸零一律回正零（`0.00`），不會出現 `-0.00`。
  String _formatChangeText(double? absChange) {
    final pctText = AppNumberFormat.signedPercent(priceChange!, decimals: 2);
    if (absChange == null) return pctText;
    final absText = AppNumberFormat.signedFixed(absChange, decimals: 2);
    return '$absText ($pctText)';
  }

  /// 緊湊模式漲跌文字：僅顯示百分比「+1.67%」
  String _formatCompactChangeText() =>
      AppNumberFormat.signedPercent(priceChange!, decimals: 2);
}

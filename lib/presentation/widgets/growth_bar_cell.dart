import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 數值欄的比例背景條(2026-08-13 月營收/季報總覽共用)。
///
/// 動機:兩頁都是上千列的數字牆,掃視只能逐列讀。背景條讓量值變形狀
/// ——密度不變,相對大小一眼可比。
///
/// 正規化:**以可見列的最大絕對值為滿條**([maxAbs] 由呼叫端對當前
/// 可見清單計算)——不發明絕對 cap(營收 % 與 EPS 差值的量綱完全不同,
/// 任何寫死的上限都只對其中一頁有意義),同視圖內比例即可比,換排序/
/// 過濾自動重校。
///
/// 色彩:條色跟隨數值方向的股價語意(紅漲綠跌,同文字色),低透明度
/// 墊底不搶字。[value] 為 null 顯示「--」無條。
class GrowthBarCell extends StatelessWidget {
  const GrowthBarCell({
    super.key,
    required this.width,
    required this.text,
    required this.value,
    required this.maxAbs,
    this.bold = false,
  });

  final double width;
  final String text;
  final double? value;

  /// 可見清單中本欄的最大 |值|;≤0 時不畫條(全清單無資料)
  final double maxAbs;

  final bool bold;

  /// 條長比例(供測試直接驗算)
  @visibleForTesting
  static double fractionOf(double? value, double maxAbs) {
    if (value == null || maxAbs <= 0) return 0;
    return (value.abs() / maxAbs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final fraction = fractionOf(v, maxAbs);
    final color = v == null
        ? theme.colorScheme.onSurfaceVariant
        : AppTheme.getPriceColor(v, theme.brightness);

    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          if (fraction > 0)
            FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor: fraction,
              child: Container(
                height: DesignTokens.growthBarHeight,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: DesignTokens.growthBarAlpha),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                ),
              ),
            ),
          // FittedBox(2026-08-13 終審):+1096390.6% 這種極端字串寬於欄寬時
          // 縮字不折行——**不可用 maxLines+clip**:end 對齊下被裁的是左側
          // (正負號與高位數),會顯示成看似合理的錯誤數字
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

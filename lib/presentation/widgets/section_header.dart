import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// 帶有漸層裝飾線的區塊標題
///
/// 特色：
/// - 左側漸層裝飾線
/// - 圖示 + 標題排版
/// - 可選的副標題
/// - 可選的尾端 Widget（例如動作按鈕）
/// - 輕微的進場動畫
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.animate = true,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.isDark;

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing8,
      ),
      child: Row(
        children: [
          // 漸層裝飾線
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // 純裝飾（4x20 色條、不承載文字），本身無對比度門檻；但
                // AppTheme.primaryColor 恆為深色版品牌亮色，而標題圖示用的
                // 是 theme.colorScheme.primary——淺色主題解析成 brandOnLight
                // 深藍，同一個 header 內兩塊藍會明顯不同色。統一取用主題色。
                colors: isDark
                    ? [AppTheme.brandDecorative, theme.colorScheme.primary]
                    : [theme.colorScheme.primary, AppTheme.brandDecorative],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: DesignTokens.spacing12),

          // 圖示（若有提供）
          if (icon != null) ...[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: DesignTokens.spacing8),
          ],

          // 標題與副標題
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: DesignTokens.spacing2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 尾端 Widget（若有提供）。Flexible+橫向捲動:trailing 原是 Row 的
          // 裸子元素,SegmentedButton 之類的寬 trailing 在窄幅(zh 320pt、
          // en 393pt)會 RenderFlex 溢出——2026-08-13 審查以真實譯文實測,
          // 族群排行加第 4 個 segment 後 zh 265px/en 547px。讓步策略:
          // 空間夠時外觀不變,不夠時 trailing 自己捲,不擠爆標題。
          if (trailing != null)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: trailing!,
              ),
            ),
        ],
      ),
    );

    if (animate) {
      content = content
          .animate()
          .fadeIn(duration: AnimDurations.normal)
          .slideX(
            begin: -0.05,
            duration: AnimDurations.normal,
            curve: AnimCurves.enter,
          );
    }

    return content;
  }
}

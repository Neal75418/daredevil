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

    // 左側裝飾線＋圖示＋標題（與副標題）
    final leading = <Widget>[
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
    ];
    final titleColumn = Column(
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
    );

    final Widget body;
    if (trailing == null) {
      body = Row(
        children: [
          ...leading,
          Expanded(child: titleColumn),
        ],
      );
    } else {
      // 有尾端 Widget（族群排行的期間切換）：放得下就與標題同一行、靠右；
      // 放不下整排換到標題下一行。原本標題 Expanded＋trailing Flexible 平分
      // 寬度，trailing 在靠右對齊的橫向捲動裡，窄螢幕第一個選項「今日」被捲
      // 出畫面（2026-09-25 實機 ~397pt）。連獨立一行都放不下（en 長標籤、
      // 320pt）時不捲動：SegmentedButton 受寬度限制會等分縮窄、標籤換行，
      // 所有選項仍都看得到（捲動會把另一端的選項藏起來）。
      // 撐滿整行（同原本的 Row）：寬鬆約束下 Wrap 只縮到內容寬度，
      // spaceBetween 沒有空間可分，trailing 會貼著標題而非靠右
      body = SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DesignTokens.spacing12,
          runSpacing: DesignTokens.spacing8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...leading,
                Flexible(child: titleColumn),
              ],
            ),
            trailing!,
          ],
        ),
      );
    }

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing8,
      ),
      child: body,
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

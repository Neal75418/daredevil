import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';

/// 設計系統核心常數
///
/// 統一管理應用程式中的間距、圓角、透明度等設計參數，
/// 確保 UI 風格一致性，避免魔術數字。
abstract final class DesignTokens {
  /// 低基期營收列的淡化(2026-08-13):與族群轉向「強者榜 0 檔」卡片同
  /// 策略——掃過去自然跳過,但點得到、讀得到
  static const double lowBaseRowOpacity = 0.55;

  /// 數值欄背景比例條(GrowthBarCell):高度與透明度——低透明墊底不搶字
  static const double growthBarHeight = 16;
  static const double growthBarAlpha = 0.14;

  // ==================================================
  // 間距系統 (8dp Grid)
  // ==================================================

  /// 2dp - 微間距（行內元素間距）
  static const double spacing2 = 2.0;

  /// 4dp - 極小間距（標籤內文字間距）
  static const double spacing4 = 4.0;

  /// 6dp - 小間距（緊湊元素間距）
  static const double spacing6 = 6.0;

  /// 8dp - 基礎間距
  static const double spacing8 = 8.0;

  /// 10dp - 小中間距
  static const double spacing10 = 10.0;

  /// 12dp - 中等間距
  static const double spacing12 = 12.0;

  /// 14dp - 卡片內間距
  static const double spacing14 = 14.0;

  /// 16dp - 標準間距（Section 間距）
  static const double spacing16 = 16.0;

  /// 20dp - 大間距（區段間距）
  static const double spacing20 = 20.0;

  /// 24dp - 大間距（區塊間距）
  static const double spacing24 = 24.0;

  /// 32dp - 超大間距
  static const double spacing32 = 32.0;

  // ==================================================
  // 圓角系統
  // ==================================================

  /// 4dp - 極小圓角（標籤、徽章）
  static const double radiusXs = 4.0;

  /// 6dp - 小圓角（緊湊標籤）
  static const double radiusSm = 6.0;

  /// 8dp - 中等圓角（Chip、小卡片）
  static const double radiusMd = 8.0;

  /// 12dp - 大圓角（按鈕、輸入框）
  static const double radiusLg = 12.0;

  /// 16dp - 超大圓角（卡片）
  static const double radiusXl = 16.0;

  /// 20dp - 特大圓角（Dialog）
  static const double radiusXxl = 20.0;

  // ==================================================
  // 透明度系統
  // ==================================================

  /// 10% 透明度 - 淺色主題背景
  static const double opacity10 = 0.10;

  /// 15% 透明度 - 淺色主題懸停
  static const double opacity15 = 0.15;

  /// 20% 透明度 - 中等透明
  static const double opacity20 = 0.20;

  /// 25% 透明度 - 深色主題背景
  static const double opacity25 = 0.25;

  /// 40% 透明度 - 邊框、分隔線
  static const double opacity40 = 0.40;

  // ==================================================
  // StockCard 專用常數
  // ==================================================

  /// 股票卡片高度（Grid 佈局用）
  /// 計算：margin(12) + padding(28) + content(~114) = 154
  static const double stockCardHeight = 154.0;

  /// 股票卡片最小寬度（用於計算 Grid 欄數）
  static const double stockCardMinWidth = 340.0;

  /// 股票卡片水平外邊距
  static const double stockCardMarginH = 16.0;

  /// 股票卡片垂直外邊距
  static const double stockCardMarginV = 6.0;

  /// 股票卡片內邊距
  static const double stockCardPadding = 14.0;

  // ==================================================
  // 文字大小
  // ==================================================

  /// 10sp - 極小文字（輔助標記）
  static const double fontSizeXs = 10.0;

  /// 12sp - 小文字（標籤）
  static const double fontSizeSm = 12.0;

  /// 14sp - 中等文字（內文）
  static const double fontSizeMd = 14.0;

  /// 16sp - 大文字（副標題）
  static const double fontSizeLg = 16.0;

  /// 18sp - 超大文字（價格顯示）
  static const double fontSizeXl = 18.0;

  // ==================================================
  // 圖示大小
  // ==================================================

  /// 14dp - 小圖示
  static const double iconSizeSm = 14.0;

  /// 18dp - 中等圖示
  static const double iconSizeMd = 18.0;

  /// 24dp - 標準圖示
  static const double iconSizeLg = 24.0;

  /// 26dp - 大圖示（自選按鈕）
  static const double iconSizeXl = 26.0;

  // ==================================================
  // 進度條/視覺化元素
  // ==================================================

  /// 12dp - 進度條/量表高度
  static const double barHeight = 12.0;

  // ==================================================
  // 陰影系統
  // ==================================================

  /// 小陰影模糊半徑 - 警示標記、進度條光暈
  static const double shadowBlurSm = 4.0;

  /// 中陰影模糊半徑 - 卡片、浮動元件
  static const double shadowBlurMd = 12.0;

  /// 大陰影模糊半徑 - 覆蓋層、底部彈出面板
  static const double shadowBlurLg = 20.0;

  /// 光暈模糊半徑 - Premium 卡片的品牌光暈
  static const double shadowBlurGlow = 16.0;

  /// 小陰影偏移 - 輕微浮起感
  static const Offset shadowOffsetSm = Offset(0, 1);

  /// 中陰影偏移 - 標準浮起感
  static const Offset shadowOffsetMd = Offset(0, 4);

  /// 上方陰影偏移 - 底部彈出面板
  static const Offset shadowOffsetUp = Offset(0, -5);

  /// 光暈擴散半徑 - 內縮光暈效果
  static const double shadowSpreadGlow = -4.0;

  // ==================================================
  // 語意色（status indicators）
  // ==================================================
  //
  // colorScheme 沒涵蓋 success / warning 兩個語意 — Material 3 預設只給
  // primary / secondary / tertiary / error。app 內 status indicator 過去
  // 各自 hardcode `Colors.green.shade600` / `Colors.orange.shade700`，dark
  // mode 對比僅勉強壓 WCAG AA（4.96:1）、不同 widget 容易飄。
  //
  // 抽 token 統一管理，並提供 `successColor(theme)` / `warningColor(theme)`
  // helper 自動切換。4 色分別對其主題的 background／surface 兩種背景實測
  // （`ColorContrast.ratio`）：8 組配對中僅 2 組達 AAA（≥7:1）——successLight
  // 對 lightBackground 7.10:1、warningDark 對 darkBackground 8.25:1；其餘
  // 6 組落在 4.76-6.94，達 AA（≥4.5:1）但未達 AAA，並非全數 ≥7:1。

  /// Success 語意色（淺色主題）
  ///
  /// 「成功／高信心」屬非方向性語意，不使用綠色 —— 綠色在本 app
  /// 代表下跌。改用品牌藍，與股價語意徹底分離。
  static const Color successLight = QualityColors.brandOnLight;

  /// Success 語意色（深色主題）
  static const Color successDark = QualityColors.brand;

  /// Warning 語意色（淺色主題）
  static const Color warningLight = WarningColors.warningOnLight;

  /// Warning 語意色（深色主題）
  ///
  /// 與 `WarningColors.warning` 同值 —— 此處曾與 `AppTheme.warningColor`
  /// 各自宣告不同值（#FB923C 27° vs #FF9800 36°），造成同語意雙色漂移。
  static const Color warningDark = WarningColors.warning;

  // ==================================================
  // 圖表色盤
  // ==================================================

  /// 通用圖表色盤 —— 依主題明暗委派至 [CategoryColors.chartPaletteFor]。
  ///
  /// 原本 8 色含紅 `#F44336` 與綠 `#4CAF50`，在 `price_overlay_chart`
  /// 這類股價疊圖上會被誤讀為漲跌。收斂為 6 色且全數避開股價色相區。
  ///
  /// 曾一度是 `static const` 直接指向深色主題那組色盤，淺色主題完全沒有
  /// 對應設計、6 色中有 4 色對淺色背景低於 3.0:1——因為淺色主題從未被
  /// 涵蓋在任何守門測試裡。改為依 [ThemeData.brightness] 解析的方法，
  /// 呼叫端一律要傳入實際渲染時的 [ThemeData]，不得快取成常數。
  static List<Color> chartPaletteFor(ThemeData theme) {
    return CategoryColors.chartPaletteFor(theme.brightness);
  }

  /// 依 theme 模式取 success 語意色
  static Color successColor(ThemeData theme) {
    return theme.brightness == Brightness.dark ? successDark : successLight;
  }

  /// 依 theme 模式取 warning 語意色
  static Color warningColor(ThemeData theme) {
    return theme.brightness == Brightness.dark ? warningDark : warningLight;
  }
}

import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

/// Daredevil 應用程式主題系統
///
/// 設計理念：
/// - 深色模式優先，搭配鮮豔強調色
/// - 專注於金融數據，清晰的視覺層次
/// - 台灣股市慣例：紅色代表漲，綠色代表跌
class AppTheme {
  AppTheme._();

  // ==================================================
  // 色彩調色盤（Material Design 標準）
  // ==================================================

  /// 主品牌色（Blue 400）。深色主題採 M3 色調邏輯：淺色 primary + 深色 onPrimary。
  static const primaryColor = QualityColors.brand;

  /// 品牌裝飾色（Blue 500）—— 僅用於邊框、低透明度底色，不承載文字。
  static const brandDecorative = QualityColors.brandDecorative;

  /// 深色主題中，疊加在 [brandDecorative] 裝飾底之上的文字色（Blue 300）。
  static const brandOnDecorative = QualityColors.brandOnDecorative;

  /// 第三強調色 - Material Deep Orange
  static const tertiaryColor = Color(0xFFFF5722);

  // ==================================================
  // 股價顏色（台灣慣例）—— 全數委派 PriceColors
  // ==================================================
  //
  // 這些常數曾與 PriceColors 各自宣告同一組色值，形成雙軌：守門測試斷言
  // PriceColors（生產端 0 個消費者），畫面實際渲染 AppTheme（沒有任何測試
  // 守住）。把 _downColorLight 改成 #CCFFCC（對白底 1.3:1，等同隱形）
  // 或把 upColor 改成純綠 #00FF00，全套測試依然全綠。
  //
  // 改為委派後只剩一份真值；對比度守門一律打在 PriceColors.forChange
  // （即 getPriceColor 的實作）這條實際渲染路徑上，見
  // test/core/theme/semantic_colors_test.dart。

  /// 上漲 - 紅色
  static const upColor = PriceColors.up;

  /// 下跌 - 鮮綠色（深色主題用）。淺色主題請走 [getPriceColor]。
  static const downColor = PriceColors.down;

  /// 平盤 - 灰色（深色主題用）。淺色主題請走 [getPriceColor]／[getFlatColor]。
  static const neutralColor = PriceColors.flat;

  /// 錯誤色 - 使用較深的紅橘色，與上漲顏色區分
  static const errorColor = Color(0xFFE74C3C);

  // 語意色
  /// 正面/成功 —— 非方向性語意，使用品牌藍
  static const successColor = QualityColors.brand;

  /// 警示 —— 委派 WarningColors，避免雙處宣告漂移
  static const warningColor = WarningColors.warning;

  /// 注意
  static const cautionColor = WarningColors.caution;

  /// 股利正面指標 —— 非方向性語意，使用品牌藍
  static const dividendColor = QualityColors.brand;

  /// 中性灰 —— 用於非漲跌的平穩狀態
  static const neutralSlateColor = QualityColors.muted;

  /// 通知標記 —— 原為 #6C63FF（243°），與品牌紫 255° 僅隔 12° 難以區分
  static const notificationColor = WarningColors.caution;

  // 法人分類色已移除。
  //
  // 外資／投信／自營商原本各有專屬色（#3498DB / #9B59B6 / #E67E22），
  // 但實際只用於 14px 圖示、8px 圓點與 alpha 0.3 邊框，且每個實例都
  // 緊鄰文字標籤，顏色屬冗餘的第三重編碼。
  //
  // 移除同時消除四組色相過近問題，其中最嚴重的是自營橘 27° 與上漲紅
  // 355° 僅隔 32° 且出現在同一張卡片上（橘圖示配紅數字）。
  // 身分改由圖示形狀（language / account_balance / store）與文字標籤區分。

  // 深色主題表面顏色（Tailwind Zinc — 飽和度 4%，不與股價色競爭色相）
  static const _surfaceDark = SemanticColors.darkSurface; // Zinc 800
  static const _backgroundDark = SemanticColors.darkBackground; // Zinc 900
  static const _cardDark = SemanticColors.darkSurface; // Zinc 800
  static const _cardDarkSurface = SemanticColors.darkElevated; // Zinc 700

  // 淺色主題表面顏色——引用 SemanticColors 單一來源(2026-08-15 審計:
  // 原為獨立字面量,與守門測試驗的 lightSurface 可各自漂移;深色系
  // 本來就這樣寫,對齊之)
  static const _surfaceLight = SemanticColors.lightSurface;
  static const _backgroundLight = Color(0xFFFFFFFF);
  static const _cardLight = Color(0xFFFFFFFF);
  static const _inputFillLight = Color(0xFFEFF1F5); // 輸入框底色，與白色背景區隔

  // ==================================================
  // 深色主題
  // ==================================================

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // ignore: prefer_const_constructors - ColorScheme.dark is a factory constructor
      colorScheme: ColorScheme.dark(
        primary: QualityColors.brand,
        onPrimary: QualityColors.onBrand,
        secondary: QualityColors.brand,
        onSecondary: QualityColors.onBrand,
        tertiary: tertiaryColor,
        surface: _surfaceDark,
        onSurface: SemanticColors.darkTextPrimary,
        onSurfaceVariant: SemanticColors.darkTextSecondary,
        error: const Color(0xFFFF6B6B),
        outline: SemanticColors.darkOutline,
        // 未指定時 ColorScheme.dark() 會經 onBackground 落回 Colors.white
        // （Flutter SDK color_scheme.dart：outlineVariant ??= onBackground，
        // onBackground 參數本身預設 Colors.white）——與此系統刻意選用的低
        // 對比 chrome（其餘 outline 類色皆 <=1.5:1 對表面）形成 14.9:1 的
        // 強烈落差，會在 21 個檔案的邊框/分隔線/圖表格線上突兀跳出。
        // 沿用既有的「次一階邊框」慣例（等同 dividerTheme 深色值）。
        outlineVariant: SemanticColors.darkElevated,
        // 已知範圍外缺口（未在本輪修復，記錄供下一輪參考）：
        // surfaceContainerLowest/Low/(本身)/High/Highest 五階同樣未指定，
        // 全數 `?? surface` 塌成同一色，導致 5 階 elevation ladder 變
        // no-op（例：stock_detail/tabs/alerts_tab.dart 的非啟用狀態圖示
        // 底色與 chip_strength_indicator.dart 的進度軌道底色，皆與所在
        // Card 背景同色，對比 1.0:1，視覺上完全隱形）。此問題早於本次
        // 修復即存在、非本次改動引入，且修法需要設計一套全新五階色階
        // （非僅補一個值），範圍超出本輪「未指定欄位落回 teal 類問題」
        // 的修復範圍，故僅記錄不在此修，待另一輪處理。
      ),
      scaffoldBackgroundColor: _backgroundDark,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: SemanticColors.darkTextPrimary,
        ),
      ),

      // 卡片
      cardTheme: CardThemeData(
        elevation: 0,
        color: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // 列表項目
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: _cardDark,
      ),

      // 底部導航
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceDark.withValues(alpha: 0.85),
        indicatorColor: primaryColor.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 70,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: SemanticColors.darkTextPrimary);
          }
          return const IconThemeData(color: SemanticColors.darkTextSecondary);
        }),
      ),

      // 按鈕
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: SemanticColors.darkOutline),
          ),
        ),
      ),

      // 輸入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // 🚨 不可用 _cardDark(2026-08-08 實機):它與 dialogTheme 的
        // backgroundColor 是**同一個常數**(SemanticColors.darkSurface),
        // 對比度 1.00:1——對話框裡的輸入框整個看不見,只剩懸空的文字,
        // 而框的內距看起來像莫名其妙的縮排。
        //
        // 深色主題同時做了兩件事才出事:拿掉邊框(BorderSide.none)**又**
        // 用了與容器同色的填色。淺色主題保留邊框,所以沒有這個問題。
        // 改用 darkElevated(Zinc 700,1.43:1)——它的語意本來就是「浮起
        // 的表面」,填色輸入框正是這個角色。
        fillColor: _cardDarkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // 標籤
      chipTheme: ChipThemeData(
        backgroundColor: _cardDarkSurface,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: SemanticColors.darkTextPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide.none,
        ),
      ),

      // 分隔線
      dividerTheme: const DividerThemeData(
        color: SemanticColors.darkElevated,
        thickness: 1,
        space: 1,
      ),

      // 提示訊息列
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _cardDarkSurface,
        contentTextStyle: const TextStyle(
          color: SemanticColors.darkTextPrimary,
        ),
        actionTextColor: QualityColors.brand,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // 對話框
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
      ),
    );
  }

  // ==================================================
  // 淺色主題
  // ==================================================

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      // ignore: prefer_const_constructors - ColorScheme.light is a factory constructor
      colorScheme: ColorScheme.light(
        primary: QualityColors.brandOnLight,
        onPrimary: const Color(0xFFFFFFFF),
        secondary: QualityColors.brandOnLight,
        // ColorScheme.light() 的 onSecondary 未指定會落回 Material 預設
        // Colors.black，對 brandOnLight（#1D4ED8）不足——且不只
        // onSecondary 本身，onSecondaryContainer（衍生自 onSecondary，見
        // Flutter SDK：onSecondaryContainer ??= onSecondary）在
        // stock_card 市場標籤、watchlist 數量徽章等 10 處實際文字上也會
        // 一併沿用同一個不合格的黑。改與 onPrimary 對稱，對 brandOnLight
        // 達 7.10:1。
        onSecondary: const Color(0xFFFFFFFF),
        tertiary: tertiaryColor,
        // onTertiary 未指定會落回 onSecondary（Flutter SDK：
        // onTertiary ??= onSecondary）。若不明確指定，上面 onSecondary
        // 改白之後會被動跟著變白，但白對 tertiaryColor（#FF5722）只有
        // 3.16:1，反而讓目前用黑字（純黑 6.64:1，見 stock_detail_header
        // 產業標籤、news_screen 更多標籤）合格的組合退步。故與
        // onSecondary 明確脫鉤——沿用既有的 onSurface 深色文字值
        // #1A1A2E（5.39:1，非純黑但同樣過 AA，換取與主題其餘深色文字
        // 一致，不必為此另立一個只差在這裡用的顏色）。
        onTertiary: const Color(0xFF1A1A2E),
        surface: _surfaceLight,
        onSurface: const Color(0xFF1A1A2E),
        onSurfaceVariant: const Color(0xFF666680),
        error: const Color(0xFFE53935),
        // onError 未指定會落回 Colors.white，對 error（#E53935）僅
        // 4.23:1——onErrorContainer（衍生自 onError）承載 alerts_tab.dart
        // 的錯誤說明本文，未達 4.5:1。改用純黑達 4.97:1；主題慣用的深色
        // 文字 #1A1A2E（見上方 onTertiary）在此僅 4.04:1，不夠，故此處
        // 例外用純黑而非沿用 #1A1A2E——之後做顏色收斂時請勿把這裡「統一」
        // 成 #1A1A2E，會靜默跌破 4.5:1。
        onError: const Color(0xFF000000),
        outline: const Color(0xFFE0E0E8),
        // 理由同深色主題：未指定會落回 Colors.black，對白底表面形成
        // 21:1 的極端反差。沿用既有的分隔線／卡片邊框淺灰值。
        outlineVariant: const Color(0xFFE8E8F0),
      ),
      scaffoldBackgroundColor: _backgroundLight,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A1A2E),
        ),
        iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
      ),

      // 卡片
      cardTheme: CardThemeData(
        elevation: 0,
        color: _cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8E8F0), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // 列表項目
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: _cardLight,
      ),

      // 底部導航
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _backgroundLight.withValues(alpha: 0.95),
        indicatorColor: primaryColor.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 70,
      ),

      // 按鈕
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // 輸入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _inputFillLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // 標籤
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceLight,
        selectedColor: primaryColor.withValues(alpha: 0.15),
        labelStyle: const TextStyle(
          fontSize: 12,
          color: Color(0xFF1A1A2E), // Ensure visible text in light mode
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          color: Color(0xFF1A1A2E),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE0E0E8)),
        ),
      ),

      // 分隔線
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE8E8F0),
        thickness: 1,
        space: 1,
      ),

      // 提示訊息列
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1A1A2E),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // 對話框
      dialogTheme: DialogThemeData(
        backgroundColor: _backgroundLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ==================================================
  // 輔助方法
  // ==================================================

  /// 根據漲跌幅取得對應顏色
  ///
  /// [brightness] 必須傳入，淺色模式使用更深的綠色與更深的平盤灰以提高對比度。
  /// 若有 BuildContext 可用，建議直接使用 `context.priceColor(change)` 擴充方法。
  static Color getPriceColor(double? change, Brightness brightness) =>
      PriceColors.forChange(change, brightness);

  /// 取得平盤色（依主題解析）
  ///
  /// 供「已知是平盤／無方向」但不經 [getPriceColor] 的呼叫端使用，
  /// 例如趨勢橫盤圖示、法人淨額為 0 的數字。若有 BuildContext 可用，
  /// 建議直接使用 `context.flatColor` 擴充方法。
  static Color getFlatColor(Brightness brightness) =>
      PriceColors.flatFor(brightness);

  /// 根據評分取得對應顏色
  ///
  /// [brightness] 用於解析最低分級的平盤灰——淺色主題需要更深的灰，
  /// 深色主題的 [neutralColor] 對白底僅 2.58:1。
  static Color getScoreColor(double score, Brightness brightness) {
    if (score >= 50) return upColor;
    if (score >= 35) return warningColor;
    if (score >= 20) return cautionColor;
    return getFlatColor(brightness);
  }

  /// 高分股票的頂級金屬漸層
  static LinearGradient get premiumGradient => LinearGradient(
    colors: [
      SemanticColors.darkSurface,
      SemanticColors.darkElevated.withValues(alpha: 0.5),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 卡片裝飾（含細微邊框）
  static BoxDecoration cardDecoration(
    BuildContext context, {
    bool isPremium = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 如果是高分卡片且在深色模式，使用特殊樣式
    if (isPremium && isDark) {
      return BoxDecoration(
        gradient: premiumGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: SemanticColors.darkOutline.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: DesignTokens.opacity20),
            blurRadius: DesignTokens.shadowBlurMd,
            offset: DesignTokens.shadowOffsetMd,
          ),
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.05),
            blurRadius: DesignTokens.shadowBlurGlow,
            spreadRadius: DesignTokens.shadowSpreadGlow,
          ),
        ],
      );
    }

    return BoxDecoration(
      color: isDark ? _cardDark : _cardLight,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark ? SemanticColors.darkElevated : const Color(0xFFE8E8F0),
        width: 1,
      ),
    );
  }
}

/// 便捷存取主題顏色的擴充方法
extension ThemeExtension on BuildContext {
  /// 根據漲跌幅取得價格顏色（自動適配深淺色主題）
  Color priceColor(double? change) =>
      AppTheme.getPriceColor(change, Theme.of(this).brightness);

  /// 平盤／無方向色（自動適配深淺色主題）
  Color get flatColor => AppTheme.getFlatColor(Theme.of(this).brightness);

  /// 檢查目前是否為深色主題
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

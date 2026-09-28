import 'dart:ui';

import 'package:daredevil/core/theme/semantic_colors.dart';

/// 技術指標圖表與相關元件的色彩常數
///
/// 統一管理所有指標相關的硬編碼顏色，確保一致性並便於維護。
abstract final class IndicatorColors {
  // ==================================================
  // 圖表線條顏色
  // ==================================================

  /// K 線圖四條均線的顏色(MA5 / MA10 / MA20 / MA60,順序對應
  /// `kTechnicalMaDayList`)。
  ///
  /// 取 [CategoryColors.chartPaletteFor] 既有色盤的 index tuple,**不宣告
  /// 新色值**——因此自動繼承 `semantic_colors_test` 對該色盤已在跑的
  /// 對比度與色族間距守門(新色值得重驗與既有 6 色的兩兩間距)。
  ///
  /// 配色理由:
  /// - 唯一同色族的一對(MA5/MA60,色相僅差 5.5°)配給**幾何差異最大**的
  ///   兩條線——MA5 每根 K 都在扭、緊貼 K 棒,MA60 近乎水平,不會有
  ///   「兩條纏在一起分不出」的情境;會反覆交叉的相鄰均線
  ///   (MA5/MA10、MA10/MA20)全部落在不同色族(間距 ≥ 41°)。
  ///   這一對另靠對比度區分:深色 9.82 vs 4.82(2.0x)。
  /// - 兩條決策線色相對立(178.96°):MA20 是回檔進場帶、MA60 是 regime
  ///   gate(`pullback_rules` 硬過濾 ma20 > ma60),且兩條拿最高的兩檔對比。
  /// - MA5 刻意最暗(四條最低):它大部分時間貼在 K 棒上,越亮越跟紅綠
  ///   K 棒搶語意。
  ///
  /// 與台股慣例的差異:券商常見「紅 MA5 / 綠 MA20」,但紅綠在本專案是
  /// 股價漲跌的專屬語意色(K 線圖上紅綠已代表漲跌,見 [SemanticColors]
  /// 的色相禁區),均線再用紅綠會語意打架,故不照抄。
  static const maPaletteIndices = [0, 2, 4, 3];

  static List<Color> maColorsFor(Brightness brightness) {
    final palette = CategoryColors.chartPaletteFor(brightness);
    return [for (final i in maPaletteIndices) palette[i]];
  }

  /// 主要指標線（K, DIF, WR）— Sky Blue
  static const chartPrimary = Color(0xFF60A5FA);

  /// 次要指標線（D, DEA, RSI）— Yellow
  static const chartSecondary = Color(0xFFFACC15);

  /// 第三指標線（J、CCI；MACD 副圖標頭的 MACD 數值文字）— Purple
  static const chartTertiary = Color(0xFFA78BFA);

  // ==================================================
  // 圖表背景
  // ==================================================

  /// K 線圖深色模式背景
  ///
  /// 原為 `#0F172A`——正是 Task 3 從 `app_theme.dart` 換掉的舊
  /// `_backgroundDark`（Slate 900，HSL 222.2° / 47.4% / 11.2%）。深色表面
  /// 遷移至 Zinc 後這裡沒跟上，K 線圖因此是整個深色主題裡唯一一塊 Slate
  /// 藍面板。改為委派 [SemanticColors.darkBackground]（Zinc 900，飽和 5.9%），
  /// 與 scaffold 同色、不再與股價綠競爭色相。
  ///
  /// 對比度影響可忽略：圖上五個前景色對新舊背景分別為上漲 5.31 / 5.35、
  /// 下跌 9.18 / 9.25、MA 6.97 / 7.02、11.57 / 11.66、6.51 / 6.56，
  /// 全數維持在門檻之上。
  static const chartDarkBackground = SemanticColors.darkBackground;

  // ==================================================
  // 指標標籤顏色
  // ==================================================

  // 指標標籤徽章由「裝飾底色」與「文字色」兩者組成，兩者不同色。
  //
  // 徽章底是標籤色以 10% alpha 疊加卡片背景（IndicatorCardContainer 的
  // surfaceContainerHighest@0.7；因 surfaceContainer* 四階全數塌回 surface，
  // 該 alpha 實際是 no-op，合成後就是 surface 本身：淺色 #F8F9FA、
  // 深色 #27272A）。標籤色自身對這個合成底的對比度分別只有：
  //
  //   atrLabel #8B5CF6 → 淺色 3.56:1、深色 3.17:1
  //   obvLabel #3B82F6 → 淺色 3.12:1、深色 3.59:1
  //
  // 四者皆未達 11px 標籤文字所需的 AA 4.5:1。設計文件另有明文：`#8B5CF6`
  // 僅供裝飾、不得承載文字。Task 4 已為品牌色發明
  // QualityColors.brandOnDecorative 解同一問題，但未 sweep 到這兩個同型
  // sibling，故補上各自的 *LabelText 解析函式。

  /// OBV 指標標籤的裝飾底色（藍，分類語意）。純裝飾，不承載文字。
  static const obvLabel = Color(0xFF3B82F6);

  /// ATR 指標標籤的裝飾底色。
  ///
  /// 委派 [QualityColors.brandDecorative]（品牌換藍後為 Blue 500，與
  /// [obvLabel] 同值）——各自宣告會形成與 `AppTheme` 價格色同型的
  /// 雙處宣告漂移風險。
  static const atrLabel = QualityColors.brandDecorative;

  /// ATR 標籤在 [atrLabel] 10% 疊色底上的文字色（依主題解析）。
  ///
  /// 淺色 `#1D4ED8` 對合成底 5.69:1、深色 `#93C5FD` 7.34:1。
  static Color atrLabelText(Brightness brightness) =>
      brightness == Brightness.light
      ? QualityColors.brandOnLight
      : QualityColors.brandOnDecorative;

  /// OBV 標籤在 [obvLabel] 10% 疊色底上的文字色（依主題解析）。
  ///
  /// 取與 [obvLabel] 同色相（217°）的藍 800／藍 300，與
  /// `CategoryColors.chartPalette` 用的是同一組明度階；對合成底
  /// 淺色 5.08:1、深色 7.33:1。
  static Color obvLabelText(Brightness brightness) =>
      brightness == Brightness.light
      ? const Color(0xFF175DD0) // 藍 800
      : const Color(0xFF93C5FD); // 藍 300

  // ==================================================
  // 波動度色階
  // ==================================================

  /// 低波動（ATR）—— 非方向性，使用中性灰
  static const volatilityLow = Color(0xFF71717A);

  /// 中波動（ATR）—— 波動度是「請注意」而非多空訊號
  static const volatilityMedium = WarningColors.caution;

  /// 高波動（ATR）—— 波動度是「請注意」而非多空訊號，不使用紅色
  static const volatilityHigh = WarningColors.warning;

  // 籌碼評等色階已移至 PriceColors.chipRating()。
  // 該色階屬方向性語意（籌碼強弱＝多空），與漲跌共用紅綠色彩語言，
  // 故不放在本檔（本檔為圖表與指標的分類色）。

  // ==================================================
  // 指標選擇標籤
  // ==================================================

  /// MA / MACD 選擇器
  static const selectorBlue = Color(0xFF3498DB);

  /// BOLL / RSI 選擇器
  static const selectorPurple = Color(0xFF9B59B6);

  /// SAR / KDJ 選擇器
  static const selectorOrange = Color(0xFFE67E22);

  /// WR 選擇器
  static const selectorTeal = Color(0xFF1ABC9C);

  /// CCI 選擇器
  static const selectorRed = Color(0xFFE74C3C);

  /// 選擇器 chip 選中態（自身 15% tint 底）上的文字色，依主題解析。
  ///
  /// 選中 chip 的底是 selector 色 @0.15 疊 surface，本色文字對合成底
  /// 五色全部或半數主題不合格（2.0～4.2:1）。各對應色維持同色相家族
  /// （teal 淺色例外：teal-700 色相 175.3° 貼綠區邊界 0.3°，改用
  /// cyan-800 `#155E75`／194°，同時把對比從 4.58 拉到 6.08）。
  /// 全部組合實測 4.7～7.0:1。未知色（防禦分支）回傳中性高對比色。
  static Color selectorOnTint(Color base, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return switch (base) {
      selectorBlue =>
        isLight ? const Color(0xFF1565C0) : const Color(0xFF93C5FD),
      selectorPurple =>
        isLight ? const Color(0xFF6A1B9A) : const Color(0xFFCE93D8),
      selectorOrange =>
        isLight ? const Color(0xFF9A3412) : const Color(0xFFFDBA74),
      selectorTeal => isLight ? const Color(0xFF155E75) : selectorTeal,
      selectorRed =>
        isLight ? const Color(0xFFB71C1C) : const Color(0xFFFF8A80),
      // 防禦分支：未知色回傳中性高對比色而非 base 本色——回傳 base 等於
      // 同色疊同色（不可讀）的靜默劣化
      _ => isLight ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8),
    };
  }
}

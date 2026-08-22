import 'dart:ui';

import 'package:daredevil/core/constants/chip_strength.dart';

/// 色彩語意類別的單一真相來源。
///
/// 分類判準：
/// - [PriceColors]     值變大代表偏多或偏空 —— 唯一可使用紅綠色相者
/// - [QualityColors]   有好壞之分但無多空方向
/// - [CategoryColors]  純分類，無好壞也無方向
/// - [WarningColors]   「請注意」，與多空無關
///
/// 紅區（hue >= 345 或 <= 15）與綠區（88-175）為股價語意保留區，
/// 除 [PriceColors] 外不得使用。此約束由
/// `test/core/theme/semantic_colors_test.dart` 強制。
abstract final class SemanticColors {
  static const darkBackground = Color(0xFF18181B); // Zinc 900
  static const darkSurface = Color(0xFF27272A); // Zinc 800
  static const darkElevated = Color(0xFF3F3F46); // Zinc 700
  static const darkOutline = Color(0xFF52525B); // Zinc 600
  static const darkTextPrimary = Color(0xFFF4F4F5); // Zinc 100
  static const darkTextSecondary = Color(0xFFA1A1AA); // Zinc 400

  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF8F9FA);
}

/// 方向性語意 —— 唯一可使用紅綠色相的類別。
abstract final class PriceColors {
  /// 上漲（台股慣例：紅）。色相 354.8°
  static const up = Color(0xFFFF4757);

  /// 下跌（台股慣例：綠）。色相 145.4°
  static const down = Color(0xFF2ED573);

  /// 下跌（淺色主題專用，白底對比加強）
  static const downOnLight = Color(0xFF1B9E50);

  /// 平盤（深色主題）。刻意使用灰階，不佔用任何色相。
  ///
  /// 對深色卡片（`SemanticColors.darkSurface` `#27272A`）5.76:1、對 scaffold
  /// （`#18181B`）6.86:1，兩者皆達 AA——`AppTheme.neutralColor` 委派至此。
  ///
  /// 設計文件曾寫成 Zinc 400 `#A1A1AA`，但該值色相 240°、非灰階，會違反
  /// 本類別「平盤不佔用色相」的約束（`semantic_colors_test.dart` 的籌碼評等
  /// 色相守門要求平盤為灰階）。`#A1A1A1` 是同明度的純灰版本，對深色兩種
  /// 背景的對比與 `#A1A1AA` 差距在 0.05 以內（5.76/6.86 對 5.81/6.91）。
  static const flat = Color(0xFFA1A1A1);

  /// 平盤（淺色主題專用）。
  ///
  /// [flat] 是為深色背景挑的明亮灰，對白底僅 2.58:1、對 `#F8F9FA` 僅 2.45:1
  /// ——連圖形物件 3.0:1 都不到。純灰階無法同時滿足深淺兩色主題的 AA
  /// （對白底 4.5:1 需相對亮度 <= 0.1833、對 `#27272A` 4.5:1 需 >= 0.2672，
  /// 兩區間不相交），故與 [down]／[downOnLight] 同樣採雙值設計。
  ///
  /// `#717171` 是 [flat] 的下一階純灰：對白底 4.88:1、對 `#F8F9FA` 4.63:1，
  /// 皆達 AA。呼叫端一律透過 [flatFor] 取色，不得直接引用單側常數。
  static const flatOnLight = Color(0xFF717171);

  /// 籌碼偏多（上漲紅的淺色階）
  static const chipBullish = Color(0xFFFF8A94);

  /// 籌碼偏空（下跌綠的淺色階）
  static const chipBearish = Color(0xFF7DD8A0);

  /// 平盤 tint 徽章上的文字色（深色主題）。純灰階（hue −1）。
  ///
  /// [flat] 本色對自身 @0.15 tint 合成底僅 4.44:1，此值實測 5.49:1。
  static const flatOnTintDark = Color(0xFFB3B3B3);

  /// 「上漲紅」tint 徽章上的文字色，依主題解析。
  ///
  /// 深色主題 [up] 本色對自身 tint 合成底僅 3.76~4.47:1，改用 [chipBullish]
  /// 淺紅（同色相 354.9°，α 0.1~0.15 各背景實測 5.57~6.62:1）。
  /// **淺色主題暫維持 [up] 本色**——使用者僅使用深色主題，淺色主題下
  /// 紅綠家族的疊色對比缺陷整批列入 deferred；日後啟用淺色主題前需一併
  /// 處理（候選 red-900 `#B71C1C`／green-800 `#166534` 已精算通過）。
  ///
  /// 原本這裡指向一份 2026-07-18 的稽核清單，2026-08-22 查證後刪除：
  /// 清單記的是更名前（afterclose）的檔案路徑與行號，抽樣驗證多數站點
  /// 已在後續重構中消失，留著是一份會誤導人的舊地圖。真正的防線是
  /// `test/core/theme/` 的 111 條守門測試（色相禁區／對比度／語意單調性），
  /// 任何新的違規會被它們當場擋下，不需要靜態清單。
  static Color upOnTintFor(Brightness brightness) =>
      brightness == Brightness.dark ? chipBullish : up;

  /// 「已知 price 家族色」的 tint 徽章文字對應（值→onTint），供以
  /// `Color` 參數傳遞色彩的徽章 widget 做最小改動接線。
  ///
  /// 深色主題：[up]→[chipBullish]、[flat]→[flatOnTintDark]，其餘
  /// （[down] 等已達標者、未知色）原樣回傳。淺色主題一律原樣（deferred）。
  static Color onTintOf(Color base, Brightness brightness) {
    if (brightness != Brightness.dark) return base;
    if (base == up) return chipBullish;
    if (base == flat) return flatOnTintDark;
    return base;
  }

  /// 漲跌平 tint 徽章上的文字／圖示色（tint＝[forChange] 本色 @0.1~0.15）。
  ///
  /// 深色主題：漲→[chipBullish]、跌→[down]（本色已達標）、平→
  /// [flatOnTintDark]。淺色主題暫回傳 [forChange] 本色（deferred，
  /// 理由同 [upOnTintFor]）。
  static Color forChangeOnTint(double? change, Brightness brightness) {
    if (brightness != Brightness.dark) return forChange(change, brightness);
    if (change == null || change == 0) return flatOnTintDark;
    return change > 0 ? chipBullish : down;
  }

  /// 籌碼評等徽章文字色（徽章 tint＝[chipRating] 本色 @0.15）。
  ///
  /// 深色主題下 strong（up 紅）3.76:1、neutral（灰）4.44:1 不足，分別
  /// 改 [chipBullish]／[flatOnTintDark]；bearish/weak 本色已達標。
  /// 淺色主題暫維持 [chipRating] 本色（deferred，理由同 [upOnTintFor]）。
  static Color chipRatingOnTint(ChipRating rating, Brightness brightness) {
    if (brightness != Brightness.dark) return chipRating(rating);
    return switch (rating) {
      ChipRating.strong => chipBullish,
      ChipRating.bullish => chipBullish,
      ChipRating.neutral => flatOnTintDark,
      ChipRating.bearish => chipBearish,
      ChipRating.weak => down,
    };
  }

  /// 依主題明暗解析「下跌」色。
  ///
  /// 呼叫端一律應透過此方法（或 `AppTheme.getPriceColor`）取色，不得直接
  /// 引用 [down]／[downOnLight]——直接引用等於把單一主題的色值寫死，正是
  /// 淺色主題長期沒有守門的成因。
  static Color downFor(Brightness brightness) =>
      brightness == Brightness.light ? downOnLight : down;

  /// 依主題明暗解析「平盤」色。理由同 [downFor]。
  static Color flatFor(Brightness brightness) =>
      brightness == Brightness.light ? flatOnLight : flat;

  /// 依主題明暗解析漲跌平色。[change] 為 `null` 或 0 時視為平盤。
  ///
  /// 這是生產渲染的唯一入口——`AppTheme.getPriceColor` 委派至此，
  /// `semantic_colors_test.dart` 也對此方法（而非各別常數）做對比度守門，
  /// 確保「測試斷言的顏色」與「畫面渲染的顏色」是同一條路徑。
  static Color forChange(double? change, Brightness brightness) {
    if (change == null || change == 0) return flatFor(brightness);
    return change > 0 ? up : downFor(brightness);
  }

  /// 籌碼評等對應色。
  ///
  /// 籌碼強弱與漲跌屬同一多空語意軸，故共用紅綠色彩語言：
  /// 強勢＝紅、弱勢＝綠，與台股慣例一致。
  static Color chipRating(ChipRating rating) => switch (rating) {
    ChipRating.strong => up,
    ChipRating.bullish => chipBullish,
    ChipRating.neutral => flat,
    ChipRating.bearish => chipBearish,
    ChipRating.weak => down,
  };
}

/// 非方向性的好壞語意。
abstract final class QualityColors {
  /// 品牌主色（填色用）。Blue 400。
  ///
  /// 2026-07-19 由 Violet 400（#A78BFA）改為藍——紫色經使用者實機驗收
  /// 否決；當初否決藍色的理由（與外資藍 205° 過近）已隨法人分類色移除
  /// 而消失。深色主題採 Material 3 色調邏輯：primary 用淺色調、onPrimary
  /// 用深色。Blue 500（#3B82F6）白字在其上僅 3.68:1 不符文字 AA，
  /// 故不作為填色使用。對深背景 6.97:1、對深卡片 5.86:1。
  static const brand = Color(0xFF60A5FA);

  /// 品牌填色上的文字色（深字對 [brand] 6.97:1）
  static const onBrand = Color(0xFF18181B);

  /// 深色底上的品牌文字與圖示色（與 [brand] 同值，語意不同故分開命名）
  static const brandOnDark = Color(0xFF60A5FA);

  /// 淺色主題的品牌色（Blue 700，白底 6.70:1、surface 6.36:1、白字在其上 6.70:1）
  static const brandOnLight = Color(0xFF1D4ED8);

  /// 純裝飾用品牌色（Blue 500）—— 邊框、低透明度底色、focus ring。
  /// 不承載文字，故不適用 WCAG 文字門檻。
  ///
  /// 與 [CategoryColors.chartPaletteDark] 的藍 500、`IndicatorColors.obvLabel`
  /// 同值——刻意共用：三者皆為「藍色裝飾/序列」角色，分開宣告不同值反而
  /// 製造雙處漂移風險。
  static const brandDecorative = Color(0xFF3B82F6);

  /// 深色主題中，疊加在 [brandDecorative] 裝飾底之上的文字色（Blue 300）。
  ///
  /// [brandDecorative] 以 25% alpha 疊加卡片背景（[SemanticColors.darkSurface]）
  /// 後的合成色為 `#2C3E5D`，[brand] 只對平面背景校準過，疊色後是完全
  /// 不同的顏色配對。Blue 300 對該合成色 5.96:1。
  ///
  /// 不得用於平面背景之上的品牌文字——平面背景請用 [brand]／[brandOnDark]。
  static const brandOnDecorative = Color(0xFF93C5FD);

  /// 低強度／停用／低波動
  static const muted = Color(0xFF71717A);

  /// 淺色主題中，**多層品牌 tint** 疊加後的文字色（Blue 900）。
  ///
  /// 更新進度橫幅是雙層疊色：banner 底＝primary@0.3 疊 scaffold、步驟
  /// chip 再疊 primary@0.2——合成後為飽和淺藍（`#9BB1EE`），連
  /// [brandOnLight] 對其都不足。Blue 900 對最深的漸層停點實測 4.89:1。
  /// 單層 tint 請用 [brandOnLight]（淺）／[brandOnDecorative]（深）。
  static const brandOnDeepTintLight = Color(0xFF1E3A8A);

  /// 守門測試掃描對象。新增常數時必須加入此清單。
  static const all = <Color>[
    brand,
    onBrand,
    brandOnDark,
    brandOnLight,
    brandDecorative,
    brandOnDecorative,
    brandOnDeepTintLight,
    muted,
  ];
}

/// 純分類語意，無好壞也無方向。
abstract final class CategoryColors {
  /// 法人／中性分類標記。
  ///
  /// 外資／投信／自營商原本各有專屬色，但實際只用於 14px 圖示、
  /// 8px 圓點與 alpha 0.3 邊框，且每個實例都緊鄰文字標籤，
  /// 顏色屬冗餘的第三重編碼。統一為中性灰後同時消除四組色相過近問題。
  static const neutral = Color(0xFFA1A1AA);

  /// 圖表序列色盤 —— 深色主題（3 色相 × 2 明度）。
  ///
  /// 排除紅綠禁區後可用色相僅剩 243°，無法容納 6 個互隔 60° 的色相。
  /// 改以 3 個充分分離的色相（25° / 217° / 258°）各取兩個明度階，
  /// 同族靠明度區分、異族靠色相區分。
  /// 序列超過 6 個時應改用直接標註，不得再增加顏色。
  ///
  /// 只對深色背景（[SemanticColors.darkBackground]）驗證過對比度——淺色
  /// 主題請用 [chartPaletteLight]，不得直接沿用本清單（300 階淺色調對
  /// 白底完全不合格，見 [chartPaletteLight] 的說明）。
  static const chartPaletteDark = <Color>[
    Color(0xFF3B82F6), // 藍 500 — 217°
    Color(0xFFF97316), // 橘 500 — 25°
    Color(0xFF8B5CF6), // 紫 500 — 258°
    Color(0xFF93C5FD), // 藍 300 — 212°
    Color(0xFFFDBA74), // 橘 300 — 31°
    Color(0xFFC4B5FD), // 紫 300 — 252°
  ];

  /// 圖表序列色盤 —— 淺色主題（同一 3 色相 × 2 明度，換用較深明度階）。
  ///
  /// [chartPaletteDark] 的 300 階是為深色背景挑的淺色調，實測對淺色主題
  /// 兩種實際背景（[SemanticColors.lightSurface] `#F8F9FA`、
  /// [SemanticColors.lightBackground] `#FFFFFF`）6 色中有 4 色低於圖形物件
  /// 門檻 3.0:1（僅藍 500、紫 500 過關）——300 階淺色調放到白底上必然不足，
  /// 這正是淺色主題從未被任何守門測試涵蓋過的缺口。
  ///
  /// 改用同 3 色相各自的 600／800 階（比 [chartPaletteDark] 更深、更飽和），
  /// 對兩種淺色背景實測皆 ≥3.4:1（`ColorContrast.ratio`精算，見
  /// `semantic_colors_test.dart` 對應守門測試）。色相與 [chartPaletteDark]
  /// 完全相同（僅明度不同），異族間距因此維持相同的 41°／127° 餘裕。
  static const chartPaletteLight = <Color>[
    Color(0xFF4685EA), // 藍 600 — 217°
    Color(0xFFD76618), // 橘 600 — 25°
    Color(0xFF966FEF), // 紫 600 — 258°
    Color(0xFF175DD0), // 藍 800 — 217°
    Color(0xFF9F4C12), // 橘 800 — 25°
    Color(0xFF713CE9), // 紫 800 — 258°
  ];

  /// 依主題明暗解析出應使用的圖表色盤。
  ///
  /// 呼叫端一律應透過此方法取色，不得直接引用 [chartPaletteDark] 或
  /// [chartPaletteLight]——直接引用等於重蹈本類別最初只驗證深色主題、
  /// 淺色主題淪為測試死角的覆轍。
  static List<Color> chartPaletteFor(Brightness brightness) {
    return brightness == Brightness.dark ? chartPaletteDark : chartPaletteLight;
  }
}

/// 「請注意」語意，與多空無關。
abstract final class WarningColors {
  /// 警示。色相 37.7°
  static const warning = Color(0xFFF59E0B);

  /// 注意。色相 45.9°
  static const caution = Color(0xFFFCD34D);

  /// 淺色主題的警示色（白底對比加強）
  static const warningOnLight = Color(0xFFB45309);

  /// 警示家族疊色底（warning／caution／amber tint）之上的文字色——淺色主題。
  ///
  /// 疊色徽章的合成背景是極淺琥珀（如 warning@0.15 疊白卡＝`#FEF0DA`），
  /// [warning]／[warningOnLight] 對其僅 1.8～4.4:1。amber-800 對本家族
  /// α 0.08～0.25 的全部合成背景實測 5.8～6.7:1。色相 22.7°，禁區外。
  static const onTintLight = Color(0xFF92400E);

  /// 警示家族疊色底之上的文字色——深色主題。與 [caution] 同值：
  /// 深色合成背景（如 warning@0.25 疊 `#27272A`＝`#5A4522`）上明亮的
  /// caution 黃達 5.7～8.6:1；[warning] 自身在 α≥0.25 時僅 4.2:1。
  static const onTintDark = caution;

  /// 依主題解析警示家族疊色底上的文字色。呼叫端一律走此入口。
  static Color onTintFor(Brightness brightness) =>
      brightness == Brightness.light ? onTintLight : onTintDark;

  /// 守門測試掃描對象（色相禁區驗證用）。新增常數時必須加入此清單。
  ///
  /// 對比度驗證不共用此清單——各常數的預定背景不同（[warningOnLight]
  /// 是白底、其餘是深色背景），必須各自對其預定背景驗證，見 [darkOnly]。
  /// [onTintDark] 與 [caution] 同值，不重複列入。
  static const all = <Color>[warning, caution, warningOnLight, onTintLight];

  /// 深色主題適用的警示色子集，對比度驗證對象為
  /// [SemanticColors.darkBackground]。[warningOnLight] 是淺色主題專用色，
  /// 驗證對象是白底，故不列入此清單。
  static const darkOnly = <Color>[warning, caution];
}

/// 錯誤／處置／注意（deep orange）語意——刻意紅相鄰的警報家族。
///
/// 這些色相落在股價紅區（>=345 或 <=15）內或其邊緣，是錯誤／處置語意的
/// 既有慣例（`AppTheme.errorColor` `#E74C3C` 色相 5.6°、`tertiaryColor`
/// `#FF5722` 色相 14.4°——兩者的色相歸類問題已列入 deferred，本類別不
/// 解決也不擴大它，只為既有 tint 徽章提供可讀的文字色）。因語意本身
/// 紅相鄰，本類別**不納入**色相禁區守門（納入必然失敗）；對比度守門見
/// `semantic_colors_test.dart` 的疊色情境測試。
abstract final class ErrorColors {
  /// error 家族 tint（`#E74C3C`／`#E53935` @0.12～0.25）上的文字——淺色主題。
  /// red-900，對本家族全部淺色合成背景實測 5.4～5.5:1。
  static const onTintLight = Color(0xFFB71C1C);

  /// 同上——深色主題。亮紅（red-A100 系），實測 4.9～5.5:1。
  static const onTintDark = Color(0xFFFF8A80);

  /// attention（deep orange tint）上的文字——淺色主題。orange-800，實測 6.1:1。
  static const attentionOnTintLight = Color(0xFF9A3412);

  /// 同上——深色主題。deepOrange-200，實測 5.8:1。
  static const attentionOnTintDark = Color(0xFFFFAB91);

  static Color onTintFor(Brightness brightness) =>
      brightness == Brightness.light ? onTintLight : onTintDark;

  static Color attentionOnTintFor(Brightness brightness) =>
      brightness == Brightness.light
      ? attentionOnTintLight
      : attentionOnTintDark;
}

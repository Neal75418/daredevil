import 'dart:ui';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/indicator_colors.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/presentation/providers/event_calendar_provider.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';
import 'package:flutter/material.dart' show HSLColor, ThemeData;
import 'package:flutter_test/flutter_test.dart';

/// 紅區：hue >= 345 或 <= 15。綠區：88 <= hue <= 175。
bool _inPriceHueZone(Color c) {
  final h = ColorContrast.hue(c);
  if (h < 0) return false; // 灰階不佔用色相
  return h >= 345 || h <= 15 || (h >= 88 && h <= 175);
}

void main() {
  _phase1TintGuards();
  phase2DarkTintGuards();

  group('第一層：色相禁區守門', () {
    test('QualityColors 不得落在股價色相區', () {
      for (final c in QualityColors.all) {
        expect(
          _inPriceHueZone(c),
          isFalse,
          reason:
              'QualityColors 含 ${c.toARGB32().toRadixString(16)}，'
              '色相 ${ColorContrast.hue(c).toStringAsFixed(1)}° 落在股價語意區',
        );
      }
    });

    test('EventType 事件色不得落在股價色相區(2026-08-01 複審擴掃)', () {
      // 7/24 股東會紫→teal 時漏了色相檢查:teal 全家族 172~175° 落在
      // 綠區(88-175)內緣——股東會 dot/chip/pill 會被誤讀為下跌色。
      // 掃描名單原本只有 Quality/Warning/CategoryColors,EventType 是
      // 7/24 新增的色彩決策面、完全無守門。
      //
      // 豁免 exDividend(紅)/earnings(綠):兩者「屬紅綠家族」是已記錄
      // 於 Phase 2 清單的既有債務(event_calendar_provider onTintFor
      // docstring),延後至紅綠專案,不在本守門範圍。
      const deferred = {EventType.exDividend, EventType.earnings};
      for (final t in EventType.values.where((t) => !deferred.contains(t))) {
        for (final c in [
          t.color,
          t.onTintFor(Brightness.light),
          t.onTintFor(Brightness.dark),
        ]) {
          expect(
            _inPriceHueZone(c),
            isFalse,
            reason:
                'EventType.${t.name} 用色 ${c.toARGB32().toRadixString(16)},'
                '色相 ${ColorContrast.hue(c).toStringAsFixed(1)}° 落在股價語意區',
          );
        }
      }
    });

    test('WarningColors 不得落在股價色相區', () {
      for (final c in WarningColors.all) {
        expect(
          _inPriceHueZone(c),
          isFalse,
          reason:
              'WarningColors 含 ${c.toARGB32().toRadixString(16)}，'
              '色相 ${ColorContrast.hue(c).toStringAsFixed(1)}°',
        );
      }
    });

    test('CategoryColors.chartPalette 不得落在股價色相區（深色＋淺色主題）', () {
      for (final c in [
        ...CategoryColors.chartPaletteDark,
        ...CategoryColors.chartPaletteLight,
      ]) {
        expect(
          _inPriceHueZone(c),
          isFalse,
          reason:
              'chartPalette 含 ${c.toARGB32().toRadixString(16)}，'
              '色相 ${ColorContrast.hue(c).toStringAsFixed(1)}°',
        );
      }
    });
  });

  group('第二層：對比度守門 —— 深色主題', () {
    const darkBg = SemanticColors.darkBackground;
    const darkCard = SemanticColors.darkSurface;

    test('品牌文字色對深色背景與卡片皆達 AA 4.5:1', () {
      expect(
        ColorContrast.ratio(QualityColors.brandOnDark, darkBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ColorContrast.ratio(QualityColors.brandOnDark, darkCard),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('品牌填色上的文字色達 AA 4.5:1', () {
      expect(
        ColorContrast.ratio(QualityColors.onBrand, QualityColors.brand),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('圖表色盤每色對深色主題兩種實際背景達圖形物件門檻 3:1', () {
      // chartPaletteDark 的消費者落在兩種不同的深色背景：comparison_* 四個
      // widget（包在 Card 內）與 insider_tab 的 MetricCard 圖示走 Card／
      // surface（#27272A，即 darkCard）；price_overlay_chart 等無自身背景
      // 容器者落在 scaffoldBackgroundColor（#18181B，即 darkBg）。darkCard
      // 是較嚴苛的背景——同一顏色對 darkCard 的對比恆比對 darkBg 低（例：
      // 紫 500 對 darkBg 4.18:1、對 darkCard 僅 3.52:1，是六色中對 darkCard
      // 餘裕最小者，`ColorContrast` 精算）。過去只驗證過 scaffold 背景，
      // 與淺色主題兩種背景皆驗證的作法不對稱——這正是紫 500 若調整為貼近
      // darkBg 邊界的色值（例如 #7D4FE8，對 darkBg 仍有 3.51:1 合格）時，
      // 對 darkCard 已跌破門檻（2.95:1）卻不會被舊測試攔下的原因，兩種
      // 深色背景都要驗證，不能只驗其中一種。
      for (final c in CategoryColors.chartPaletteDark) {
        expect(
          ColorContrast.ratio(c, darkBg),
          greaterThanOrEqualTo(3.0),
          reason:
              'chartPaletteDark ${c.toARGB32().toRadixString(16)} '
              '對 background(#18181B) 對比不足',
        );
        expect(
          ColorContrast.ratio(c, darkCard),
          greaterThanOrEqualTo(3.0),
          reason:
              'chartPaletteDark ${c.toARGB32().toRadixString(16)} '
              '對 card(#27272A) 對比不足',
        );
      }
    });

    test('圖表色盤每色對「MetricCard 圖示 10% 疊色 card」的合成背景達圖形物件門檻 3:1（深色主題）', () {
      // 淺色主題已驗證 MetricCard 疊色情境（見下方淺色主題分組），深色
      // 主題卻從未驗證對應的合成背景——這正是同一種「只驗證其中一種背景」
      // 疏漏在深淺主題間再次出現的地方。fundamentals_tab.dart 的 P/E／
      // P/B／殖利率三張 MetricCard（Task 9 由字面值色改為取自本色盤）與
      // insider_tab.dart 皆落在這個情境，若不獨立守門，任何未來調色都可能
      // 讓深色主題的合成對比悄悄跌破 3.0:1 卻不被任何測試攔下。
      for (final c in CategoryColors.chartPaletteDark) {
        final composite = ColorContrast.compositeOver(
          c,
          darkCard,
          DesignTokens.opacity10,
        );
        expect(
          ColorContrast.ratio(c, composite),
          greaterThanOrEqualTo(3.0),
          reason:
              'chartPaletteDark ${c.toARGB32().toRadixString(16)} '
              '疊色後對 MetricCard 合成背景（深色）對比不足',
        );
      }
    });

    test('警示色（深色主題）對深色背景達 AA 4.5:1', () {
      // 用 darkOnly 而非 all——warningOnLight 是淺色主題專用色，
      // 預定背景是白底，對深色背景驗證不適用，見下方淺色主題分組。
      for (final c in WarningColors.darkOnly) {
        expect(ColorContrast.ratio(c, darkBg), greaterThanOrEqualTo(4.5));
      }
    });

    test('品牌文字色對「裝飾底疊加卡片背景」的合成色達 AA 4.5:1（ReasonTags 深色情境）', () {
      // reason_tags.dart 深色主題底色不是平面卡片背景——是 brandDecorative
      // 以 DesignTokens.opacity25（實際生產 alpha）疊加卡片背景（darkCard，
      // 即 SemanticColors.darkSurface）後的合成色。上面幾個測試只驗證品牌
      // 文字對「平面」背景（darkBg／darkCard）的對比度，brand 本色對此
      // 合成色不足（Violet 時代 4.1:1），兩者是不同的顏色配對，不能互相
      // 替代——這正是上一輪疊色情境退步完全沒被攔下的原因。
      final composite = ColorContrast.compositeOver(
        QualityColors.brandDecorative,
        darkCard,
        DesignTokens.opacity25,
      );
      expect(
        ColorContrast.ratio(QualityColors.brandOnDecorative, composite),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('品牌文字色對「12% 疊色卡片背景」的合成色達 AA 4.5:1（PinnedThesis 深色情境）', () {
      // pinned_thesis_section.dart 深色主題「有效狀態」徽章文字色是
      // DesignTokens.successColor(theme)（深色主題委派至 successDark，即
      // QualityColors.brand），底色是同一個 successDark 以生產碼字面值 12%
      // alpha（pinned_thesis_section.dart 未走 DesignTokens.opacityNN 命名、
      // 直接寫字面值 0.12）疊加卡片背景（darkCard）後的合成色。
      //
      // 這個情境在品牌色為 Violet 400 時曾收窄到 4.5038:1（餘裕不足
      // 0.1%），是全案已知餘裕最薄的疊色配對；2026-07-19 品牌改 Blue 400
      // 後放寬至 4.79:1，但仍需獨立守門——任何未來的 Card 底色調整、
      // alpha 微調或品牌色相微調都可能讓它悄悄跌破 4.5:1，不能只靠
      // 「平面背景」或 ReasonTags 疊色情境的品牌色測試涵蓋，
      // 那些驗證的是不同的顏色配對。
      final composite = ColorContrast.compositeOver(
        DesignTokens.successDark,
        darkCard,
        0.12,
      );
      expect(
        ColorContrast.ratio(DesignTokens.successDark, composite),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('第二層：對比度守門 —— 淺色主題', () {
    const lightBg = SemanticColors.lightBackground; // #FFFFFF（Card／scaffold）
    const lightSurface = SemanticColors.lightSurface; // #F8F9FA（surface）

    test('圖表色盤每色對淺色主題兩種實際背景達圖形物件門檻 3:1', () {
      // chartPaletteLight 的消費者落在兩種不同的淺色背景：
      // IndustryAllocationCard 的備用色、insider_tab 的 MetricCard 圖示走
      // surfaceContainerLow（#F8F9FA，即 lightSurface）；AllocationPieChart
      // 無自身背景容器落在 scaffoldBackgroundColor，comparison_* 系列走
      // Card，兩者皆為 #FFFFFF（lightBg）。過去只驗證過深色背景，這正是
      // chartPalette 6 色中有 4 色對淺色背景低於 3.0:1 從未被攔下的原因，
      // 兩種淺色背景都要驗證，不能只驗其中一種。
      for (final c in CategoryColors.chartPaletteLight) {
        expect(
          ColorContrast.ratio(c, lightSurface),
          greaterThanOrEqualTo(3.0),
          reason:
              'chartPaletteLight ${c.toARGB32().toRadixString(16)} '
              '對 surface(#F8F9FA) 對比不足',
        );
        expect(
          ColorContrast.ratio(c, lightBg),
          greaterThanOrEqualTo(3.0),
          reason:
              'chartPaletteLight ${c.toARGB32().toRadixString(16)} '
              '對 background(#FFFFFF) 對比不足',
        );
      }
    });

    test('圖表色盤每色對「MetricCard 圖示 10% 疊色 surface」的合成背景達圖形物件門檻 3:1（淺色主題）', () {
      // metric_card.dart 圖示的實際渲染背景不是純色 surfaceContainerLow
      // ——圖示外圓是 accentColor 以 10%（DesignTokens.opacity10）alpha
      // 疊加在 surfaceContainerLow（淺色主題 #F8F9FA，即 lightSurface）
      // 之上的合成色，圖示本身（accentColor 純色）才是疊加在這個合成色
      // 上方的前景。insider_tab.dart 的 insiderRatio／pledgeRatio 兩張
      // MetricCard 正是分別取用 chartPaletteLight[0]／[2] 作為
      // accentColor。上面「兩種實際背景」測試驗證的是 `ColorContrast
      // .ratio(c, lightSurface)`（純色背景假設），對 600 階三色（索引
      // 0/1/2）算出 3.42-3.43:1；但實際合成背景因疊入 10% 前景色而更
      // 接近前景本身，真實對比收窄至 3.07-3.08:1（`ColorContrast
      // .compositeOver` 精算，最窄為橘 600 `#D76618` 的 3.0653:1）——仍
      // 達 3.0:1 門檻，但餘裕已不到 0.07，純色背景假設高估了實際餘裕，
      // 需要獨立守門，不能只靠上面的純背景測試涵蓋。
      for (final c in CategoryColors.chartPaletteLight) {
        final composite = ColorContrast.compositeOver(
          c,
          lightSurface,
          DesignTokens.opacity10,
        );
        expect(
          ColorContrast.ratio(c, composite),
          greaterThanOrEqualTo(3.0),
          reason:
              'chartPaletteLight ${c.toARGB32().toRadixString(16)} '
              '疊色後對 MetricCard 合成背景對比不足',
        );
      }
    });

    test('品牌色（淺色主題）對白底達 AA 4.5:1', () {
      expect(
        ColorContrast.ratio(QualityColors.brandOnLight, lightBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('警示色（淺色主題）對白底達 AA 4.5:1', () {
      expect(
        ColorContrast.ratio(WarningColors.warningOnLight, lightBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('平盤色（淺色主題）對白底與 surface 皆達 AA 4.5:1', () {
      // 平盤色不套大字門檻：它與下跌色不同，會出現在 12px w500 的法人淨額
      // （chip_helpers.buildNetValue）與 10px w700 的市場儀表板徽章上，
      // 屬 WCAG 一般文字。深色主題的 flat（#A1A1A1）對白底僅 2.58:1、對
      // surface 僅 2.45:1，連圖形物件 3.0:1 都不到，故淺色主題必須用
      // 獨立的 flatOnLight。
      expect(
        ColorContrast.ratio(PriceColors.flatOnLight, lightBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ColorContrast.ratio(PriceColors.flatOnLight, lightSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('下跌色（淺色主題）對白底達大字門檻 3.0:1', () {
      // downOnLight 只套 WCAG 大字（Large Text）門檻 3.0:1，不套一般文字
      // 門檻 4.5:1：股價數字一律為粗體 ≥15px，符合大字定義。這是既有的
      // 台股綠色值，設計文件明訂不因對比度小數點差異而更動漲跌色——
      // 同樣理由也適用於 PriceColors.up 對卡片底的 4.46:1（見
      // docs/plans/2026-07-18-color-system-semantic-redesign-design.md）。
      expect(
        ColorContrast.ratio(PriceColors.downOnLight, lightBg),
        greaterThanOrEqualTo(3.0),
        reason: '股價數字為粗體大字，適用 WCAG 大字門檻 3.0:1，非一般文字 4.5:1',
      );
    });
  });

  group('生產渲染路徑守門 —— AppTheme.getPriceColor', () {
    // 這一組是本檔唯一直接打在「畫面實際渲染的那條路徑」上的守門。
    //
    // 先前的設計是雙軌宣告：守門測試斷言 PriceColors.*（生產端 0 個消費
    // 者），畫面實際渲染 AppTheme 自己的一組同值常數（沒有任何測試守住）。
    // 把 AppTheme._downColorLight 改成 #CCFFCC（對白底 1.3:1，等同隱形）
    // 或把 AppTheme.upColor 改成純綠 #00FF00，3,189 個測試依然全綠。
    //
    // 既有那些 `expect(trend.trendColor, AppTheme.upColor)` 形式的斷言是
    // 同義反覆——兩邊指向同一個常數，改動常數時兩邊一起變，恆為真。
    // 所以這裡一律斷言「解析結果對實際渲染背景的對比度」與「色相落在正確
    // 的多空半邊」，兩者都是改壞色值就會紅的性質，不是恆真的等式。

    /// 每個 (Brightness, 背景) 配對的實際渲染背景。
    ///
    /// 深色：Card／surface `#27272A`、scaffold `#18181B`
    /// 淺色：Card／scaffold `#FFFFFF`、surface／surfaceContainer* `#F8F9FA`
    const backgrounds = <Brightness, List<Color>>{
      Brightness.dark: [
        SemanticColors.darkSurface,
        SemanticColors.darkBackground,
      ],
      Brightness.light: [
        SemanticColors.lightBackground,
        SemanticColors.lightSurface,
      ],
    };

    String hex(Color c) =>
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

    test('漲跌色對兩主題各自的兩種實際背景皆達大字門檻 3.0:1', () {
      // 股價數字一律粗體 ≥15px，適用 WCAG 大字門檻 3.0:1（見下方「下跌色
      // （淺色主題）」測試的說明）。上漲紅對淺色 surface 為 3.17:1、下跌綠
      // 對淺色 surface 為 3.29:1，餘裕都不到 0.3——正是需要守門的地方。
      for (final entry in backgrounds.entries) {
        for (final bg in entry.value) {
          for (final change in <double>[1.5, -1.5]) {
            final c = AppTheme.getPriceColor(change, entry.key);
            expect(
              ColorContrast.ratio(c, bg),
              greaterThanOrEqualTo(3.0),
              reason:
                  'getPriceColor($change, ${entry.key}) = ${hex(c)} '
                  '對 ${hex(bg)} 對比不足',
            );
          }
        }
      }
    });

    test('平盤色對兩主題各自的兩種實際背景皆達 AA 4.5:1', () {
      // 平盤色套一般文字門檻而非大字門檻：它會出現在 12px w500
      // （chip_helpers.buildNetValue）與 10px w700（trading_turnover_row、
      // hero_index_section 階段徽章）的文字上，不符大字定義。
      for (final entry in backgrounds.entries) {
        for (final bg in entry.value) {
          for (final change in <double?>[null, 0]) {
            final c = AppTheme.getPriceColor(change, entry.key);
            expect(
              ColorContrast.ratio(c, bg),
              greaterThanOrEqualTo(4.5),
              reason:
                  'getPriceColor($change, ${entry.key}) = ${hex(c)} '
                  '對 ${hex(bg)} 對比不足',
            );
          }
        }
      }
    });

    test('上漲解析為紅區色相、下跌解析為綠區色相（兩主題）', () {
      // 只驗對比度攔不住「紅綠對調」——兩個色值互換後對比度完全不變。
      // 故另驗色相半邊：上漲必須落在紅區（>=345 或 <=15）、下跌必須落在
      // 綠區（88-175），與台股慣例一致。
      for (final brightness in Brightness.values) {
        final up = AppTheme.getPriceColor(1.5, brightness);
        final down = AppTheme.getPriceColor(-1.5, brightness);
        final upHue = ColorContrast.hue(up);
        final downHue = ColorContrast.hue(down);
        expect(
          upHue >= 345 || upHue <= 15,
          isTrue,
          reason:
              '$brightness 上漲色 ${hex(up)} 色相 '
              '${upHue.toStringAsFixed(1)}° 不在紅區',
        );
        expect(
          downHue >= 88 && downHue <= 175,
          isTrue,
          reason:
              '$brightness 下跌色 ${hex(down)} 色相 '
              '${downHue.toStringAsFixed(1)}° 不在綠區',
        );
      }
    });

    test('平盤解析為灰階，不佔用任何色相（兩主題）', () {
      for (final brightness in Brightness.values) {
        final flat = AppTheme.getPriceColor(0, brightness);
        expect(
          ColorContrast.hue(flat),
          lessThan(0),
          reason: '$brightness 平盤色 ${hex(flat)} 帶色相，會與方向性語意混淆',
        );
      }
    });

    test('淺色主題的下跌與平盤必須與深色主題取不同色值', () {
      // 兩主題共用同一色值就代表某一側沒有為自己的背景校準過——這正是
      // AppTheme.neutralColor 單值（Slate #747D8C）時兩個主題皆未達 AA
      // 的成因。此測試把「雙值設計」本身變成規格。
      expect(
        AppTheme.getPriceColor(-1.5, Brightness.light),
        isNot(AppTheme.getPriceColor(-1.5, Brightness.dark)),
      );
      expect(
        AppTheme.getPriceColor(0, Brightness.light),
        isNot(AppTheme.getPriceColor(0, Brightness.dark)),
      );
    });

    test('AppTheme 價格色常數委派 PriceColors，不得雙處宣告', () {
      // 委派關係本身是恆真等式，攔不住色值漂移（上面幾個測試才攔得住）；
      // 這裡攔的是另一種回歸：有人把 AppTheme 的常數改回自己的字面值，
      // 讓雙軌宣告復活。理由同「warning 色僅宣告一處」。
      expect(AppTheme.upColor, PriceColors.up);
      expect(AppTheme.downColor, PriceColors.down);
      expect(AppTheme.neutralColor, PriceColors.flat);
      expect(
        AppTheme.getPriceColor(-1.5, Brightness.light),
        PriceColors.downOnLight,
      );
      expect(
        AppTheme.getPriceColor(0, Brightness.light),
        PriceColors.flatOnLight,
      );
    });

    test('getScoreColor 最低分級解析為依主題的平盤色，非固定深色值', () {
      expect(
        AppTheme.getScoreColor(10, Brightness.light),
        PriceColors.flatOnLight,
      );
      expect(AppTheme.getScoreColor(10, Brightness.dark), PriceColors.flat);
    });
  });

  group('指標標籤徽章：文字對自身疊色底（C4）', () {
    // atr_card／obv_card 的標籤徽章底是標籤色以 10% alpha 疊加
    // IndicatorCardContainer 的背景。該容器用
    // surfaceContainerHighest.withValues(alpha: 0.7)，而 surfaceContainer*
    // 四階全數塌回 surface，等於把 surface 疊在 surface 上——alpha 是
    // no-op，合成後就是 surface 本身（淺色 #F8F9FA、深色 #27272A）。
    //
    // 標籤色自身對這個合成底只有 3.12-3.59:1，未達 11px 標籤的 AA 4.5:1；
    // 設計文件另有明文「#8B5CF6 僅裝飾、不承載文字」。Task 4 已為品牌色
    // 發明 brandOnDecorative 解同型問題，但沒 sweep 到這兩張卡片。
    const cardBg = <Brightness, Color>{
      Brightness.light: SemanticColors.lightSurface,
      Brightness.dark: SemanticColors.darkSurface,
    };

    void expectLabelReadable(
      String name,
      Color tint,
      Color Function(Brightness) textColor,
    ) {
      for (final entry in cardBg.entries) {
        final composite = ColorContrast.compositeOver(
          tint,
          entry.value,
          DesignTokens.opacity10,
        );
        expect(
          ColorContrast.ratio(textColor(entry.key), composite),
          greaterThanOrEqualTo(4.5),
          reason:
              '$name 標籤文字對 10% 疊色底（${entry.key}）對比不足；'
              '徽章文字為 11px labelSmall，適用一般文字門檻',
        );
      }
    }

    test('ATR 標籤文字對自身 10% 疊色底達 AA 4.5:1（兩主題）', () {
      expectLabelReadable(
        'ATR',
        IndicatorColors.atrLabel,
        IndicatorColors.atrLabelText,
      );
    });

    test('OBV 標籤文字對自身 10% 疊色底達 AA 4.5:1（兩主題）', () {
      // obv_card 是 atr_card 的同型 sibling：同樣的徽章結構、同樣把標籤色
      // 直接當文字色用（淺色 3.12:1、深色 3.59:1）。與 atr_card 一併修，
      // 避免只點修被指名的那一個、留下同 bug class 的另一半。
      expectLabelReadable(
        'OBV',
        IndicatorColors.obvLabel,
        IndicatorColors.obvLabelText,
      );
    });

    test('標籤裝飾底本身不得被當成文字色（兩主題皆須換色）', () {
      // 若有人把 *LabelText 改回直接回傳裝飾底色，上面的對比度測試會紅；
      // 這條額外把「必須是不同的顏色」寫成規格，讓退化意圖更早被攔下。
      for (final brightness in Brightness.values) {
        expect(
          IndicatorColors.atrLabelText(brightness),
          isNot(IndicatorColors.atrLabel),
        );
        expect(
          IndicatorColors.obvLabelText(brightness),
          isNot(IndicatorColors.obvLabel),
        );
      }
    });

    test('ATR 裝飾底委派 QualityColors.brandDecorative，不得雙處宣告', () {
      expect(IndicatorColors.atrLabel, QualityColors.brandDecorative);
    });
  });

  group('深色表面 Zinc 化殘留（C6）', () {
    // Task 3 把深色表面由 Slate 換成 Zinc，但 shimmer 骨架與 K 線圖背景
    // 沒跟上，仍是 Slate #1E293B / #334155 / #0F172A——正是 app_theme.dart
    // 換掉的舊 _surfaceDark / _cardDarkSurface / _backgroundDark。
    //
    // 用「飽和度」而非「不等於某個字面值」斷言：後者只攔得住原字面值，
    // 攔不住換成另一個同樣偏藍的色。Slate 三色飽和度 25.0-47.4%，
    // Zinc 三色 3.7-5.9%，10% 門檻能乾淨分開兩族。
    void expectZinc(String name, Color c) {
      final s = HSLColor.fromColor(c).saturation;
      expect(
        s,
        lessThan(0.10),
        reason:
            '$name = ${c.toARGB32().toRadixString(16)} 飽和度 '
            '${(s * 100).toStringAsFixed(1)}%，仍是 Slate 色盤；'
            '深色表面已於 Task 3 遷移至 Zinc',
      );
    }

    test('shimmer 骨架三色為 Zinc 且取自 SemanticColors', () {
      expectZinc('shimmer base', ShimmerColors.baseColor(true));
      expectZinc('shimmer highlight', ShimmerColors.highlightColor(true));
      expectZinc('shimmer skeleton', ShimmerColors.skeletonColor(true));

      expect(ShimmerColors.baseColor(true), SemanticColors.darkSurface);
      expect(ShimmerColors.highlightColor(true), SemanticColors.darkElevated);
      expect(ShimmerColors.skeletonColor(true), SemanticColors.darkBackground);
    });

    test('shimmer 掃過的明暗對比維持可見（base/highlight 比值 >= 1.3）', () {
      // 換色不得讓微光掃過變得看不出來。Slate 舊組合為 1.4128、
      // Zinc 新組合 1.4262，差異 <1%。
      expect(
        ColorContrast.ratio(
          ShimmerColors.baseColor(true),
          ShimmerColors.highlightColor(true),
        ),
        greaterThanOrEqualTo(1.3),
      );
    });

    test('K 線圖深色背景為 Zinc 且取自 SemanticColors', () {
      expectZinc('chartDarkBackground', IndicatorColors.chartDarkBackground);
      expect(
        IndicatorColors.chartDarkBackground,
        SemanticColors.darkBackground,
      );
    });

    test('K 線圖前景色對新背景維持門檻（漲跌 3.0、指標線 3.0）', () {
      const bg = IndicatorColors.chartDarkBackground;
      for (final c in [
        PriceColors.up,
        PriceColors.down,
        IndicatorColors.chartPrimary,
        IndicatorColors.chartSecondary,
        IndicatorColors.chartTertiary,
      ]) {
        expect(
          ColorContrast.ratio(c, bg),
          greaterThanOrEqualTo(3.0),
          reason: '${c.toARGB32().toRadixString(16)} 對 K 線圖背景對比不足',
        );
      }
    });
  });

  group('第三層：語意單調性守門', () {
    test('籌碼評等五級全部落在股價色相區或為灰階', () {
      for (final r in ChipRating.values) {
        final c = PriceColors.chipRating(r);
        final h = ColorContrast.hue(c);
        expect(h < 0 || _inPriceHueZone(c), isTrue, reason: '$r 對應色非股價語意色');
      }
    });

    test('籌碼評等自強勢至弱勢單調由紅轉綠', () {
      // 以「紅色分量減綠色分量」作為多空傾向指標，強勢端最大、弱勢端最小。
      double bias(Color c) => c.r - c.g;

      final values = ChipRating.values
          .map((r) => bias(PriceColors.chipRating(r)))
          .toList();

      for (var i = 0; i < values.length - 1; i++) {
        expect(
          values[i],
          greaterThan(values[i + 1]),
          reason:
              '${ChipRating.values[i]} 到 ${ChipRating.values[i + 1]} '
              '未維持由紅至綠的單調性',
        );
      }
    });

    test('籌碼強勢與上漲同色、弱勢與下跌同色', () {
      expect(PriceColors.chipRating(ChipRating.strong), PriceColors.up);
      expect(PriceColors.chipRating(ChipRating.weak), PriceColors.down);
    });
  });

  group('Quality 類綠色已完成遷移', () {
    test('DesignTokens success 兩主題皆非綠色相', () {
      for (final c in [DesignTokens.successLight, DesignTokens.successDark]) {
        final h = ColorContrast.hue(c);
        expect(
          h >= 88 && h <= 175,
          isFalse,
          reason:
              'success 仍為綠色 ${h.toStringAsFixed(1)}°，'
              '會與「下跌」語意混淆',
        );
      }
    });

    test('warning 色僅宣告一處', () {
      // AppTheme.warningColor 與 DesignTokens.warningDark 曾各自宣告不同值
      // （#FF9800 36° vs #FB923C 27°），合併後兩者必須同值。兩側都要斷言
      // ——先前只斷言 DesignTokens.warningDark 一側，AppTheme.warningColor
      // 單獨改回舊值 #FF9800 不會被抓到（整份測試檔仍全綠），防不住註解
      // 宣稱要防的雙處宣告漂移。
      expect(DesignTokens.warningDark, WarningColors.warning);
      expect(AppTheme.warningColor, WarningColors.warning);
    });
  });

  group('圖表色盤色族間距', () {
    // 色相差 <= 15 度視為同族（需明度比值 >= 1.5 區分），否則須間距 >= 35 度。
    // 抽成共用函式讓深色／淺色兩組色盤套同一份判準，而非各自重寫一份、
    // 兩邊標準悄悄分岔。
    void checkFamilySpacing(List<Color> palette, Color bg) {
      for (var i = 0; i < palette.length; i++) {
        for (var j = i + 1; j < palette.length; j++) {
          final hi = ColorContrast.hue(palette[i]);
          final hj = ColorContrast.hue(palette[j]);
          var delta = (hi - hj).abs();
          if (delta > 180) delta = 360 - delta;

          if (delta <= 15) {
            final ri = ColorContrast.ratio(palette[i], bg);
            final rj = ColorContrast.ratio(palette[j], bg);
            final hiR = ri > rj ? ri : rj;
            final loR = ri > rj ? rj : ri;
            expect(
              hiR / loR,
              greaterThanOrEqualTo(1.5),
              reason: '同色族 $i/$j 明度差不足，線條會難以區分',
            );
          } else {
            expect(
              delta,
              greaterThanOrEqualTo(35.0),
              reason: '色族 $i/$j 間距 ${delta.toStringAsFixed(1)}° 過近',
            );
          }
        }
      }
    }

    test('深色主題：不同色族間距 >= 35 度、同色族對比比值 >= 1.5', () {
      checkFamilySpacing(
        CategoryColors.chartPaletteDark,
        SemanticColors.darkBackground,
      );
    });

    test('淺色主題：不同色族間距 >= 35 度、同色族對比比值 >= 1.5', () {
      // 深色主題只驗證過這條規則，淺色主題從未套用過——這正是
      // chartPaletteLight 需要獨立設計、獨立驗證的原因之一。
      checkFamilySpacing(
        CategoryColors.chartPaletteLight,
        SemanticColors.lightBackground,
      );
    });
  });

  group('圖表色盤收斂（Task 8）', () {
    test(
      'DesignTokens.chartPaletteFor 依主題委派至 CategoryColors.chartPaletteFor',
      () {
        // chartPalette 曾是 `static const` 直接指向深色那組色盤，改為依主題
        // 解析的方法後，委派關係要兩個 Brightness 都驗證——只驗證其中一個
        // 會漏掉「淺色主題忘記接上新色盤」這類回歸。
        expect(
          DesignTokens.chartPaletteFor(ThemeData(brightness: Brightness.dark)),
          CategoryColors.chartPaletteFor(Brightness.dark),
        );
        expect(
          DesignTokens.chartPaletteFor(ThemeData(brightness: Brightness.light)),
          CategoryColors.chartPaletteFor(Brightness.light),
        );
      },
    );

    test('股價疊圖不得出現股價語意色（兩主題）', () {
      // price_overlay_chart 以 chartPalette 繪製多檔股價線，
      // 若含綠色會被讀成「該檔在跌」。
      for (final c in [
        ...CategoryColors.chartPaletteDark,
        ...CategoryColors.chartPaletteLight,
      ]) {
        expect(_inPriceHueZone(c), isFalse);
      }
    });
  });
}

/// Phase 1 疊色修復（2026-07-19）的守門：每一列＝一個生產情境，
/// α 與 tint 色**必須**與 widget 內的實際值同步——widget 改 α 或 tint
/// 而不改這裡，等同解除該情境的防護。
///
/// 背景鍵：card=白卡/#27272A、surface=#F8F9FA/#27272A、scaffold=#FFF/#18181B。
class _TintScenario {
  const _TintScenario(
    this.name,
    this.fgLight,
    this.fgDark,
    this.tintLight,
    this.tintDark,
    this.alphaLight,
    this.alphaDark,
    this.bgLight,
    this.bgDark, {
    this.threshold = 4.5,
  });

  final String name;
  final Color fgLight;
  final Color fgDark;
  final Color tintLight;
  final Color tintDark;
  final double alphaLight;
  final double alphaDark;
  final Color bgLight;
  final Color bgDark;
  final double threshold;
}

void _phase1TintGuards() {
  const white = Color(0xFFFFFFFF);
  const lightSurface = SemanticColors.lightSurface;
  const darkCard = SemanticColors.darkSurface;
  const darkScaffold = SemanticColors.darkBackground;
  const warnOnTintL = WarningColors.onTintLight;
  const warnOnTintD = WarningColors.onTintDark;
  const osvL = Color(0xFF666680);
  const osvD = SemanticColors.darkTextSecondary;
  const outlineL = Color(0xFFE0E0E8);
  const outlineD = SemanticColors.darkOutline;

  final scenarios = <_TintScenario>[
    // today/widgets/data_stale_banner.dart（直接疊在 scaffold 上）
    const _TintScenario(
      'Today.dataStale',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.12,
      0.12,
      white,
      darkScaffold,
    ),
    // warning_badge.dart（α: 淺 0.15／深 0.25）
    const _TintScenario(
      'WarningBadge.highPledge',
      warnOnTintL,
      warnOnTintD,
      Color(0xFFFFC107),
      Color(0xFFFFC107),
      0.15,
      0.25,
      white,
      darkCard,
    ),
    const _TintScenario(
      'WarningBadge.attention',
      ErrorColors.attentionOnTintLight,
      ErrorColors.attentionOnTintDark,
      AppTheme.tertiaryColor,
      AppTheme.tertiaryColor,
      0.15,
      0.25,
      white,
      darkCard,
    ),
    const _TintScenario(
      'WarningBadge.disposal',
      ErrorColors.onTintLight,
      ErrorColors.onTintDark,
      AppTheme.errorColor,
      AppTheme.errorColor,
      0.15,
      0.25,
      white,
      darkCard,
    ),
    // risk_badge_cluster.dart（moderate tint 依主題解析）
    const _TintScenario(
      'RiskBadge.moderate',
      warnOnTintL,
      warnOnTintD,
      DesignTokens.warningLight,
      DesignTokens.warningDark,
      0.15,
      0.25,
      white,
      darkCard,
    ),
    const _TintScenario(
      'RiskBadge.severe',
      ErrorColors.onTintLight,
      ErrorColors.onTintDark,
      AppTheme.errorColor,
      AppTheme.errorColor,
      0.15,
      0.25,
      white,
      darkCard,
    ),
    // atr_card.dart 波動徽章（indcard≈surface）
    const _TintScenario(
      'ATR.medium',
      warnOnTintL,
      warnOnTintD,
      WarningColors.caution,
      WarningColors.caution,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
    const _TintScenario(
      'ATR.high',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
    const _TintScenario(
      'ATR.low',
      osvL,
      osvD,
      QualityColors.muted,
      QualityColors.muted,
      0.10,
      0.10,
      lightSurface,
      darkCard,
    ),
    // alerts_screen.dart 狀態 pill
    const _TintScenario(
      'Alerts.triggered',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.2,
      0.2,
      white,
      darkCard,
    ),
    const _TintScenario(
      'Alerts.active',
      QualityColors.brandOnLight,
      QualityColors.brandOnDecorative,
      QualityColors.brand,
      QualityColors.brand,
      0.2,
      0.2,
      white,
      darkCard,
    ),
    const _TintScenario(
      'Alerts.inactive',
      osvL,
      osvD,
      outlineL,
      outlineD,
      0.15,
      0.15,
      white,
      darkCard,
    ),
    // ai_summary_card.dart 信心徽章
    const _TintScenario(
      'AiConfidence.high',
      QualityColors.brandOnLight,
      QualityColors.brandOnDecorative,
      QualityColors.brand,
      QualityColors.brand,
      0.15,
      0.15,
      white,
      darkCard,
    ),
    const _TintScenario(
      'AiConfidence.medium',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.15,
      0.15,
      white,
      darkCard,
    ),
    const _TintScenario(
      'AiConfidence.low',
      osvL,
      osvD,
      outlineL,
      outlineD,
      0.15,
      0.15,
      white,
      darkCard,
    ),
    // pinned_thesis_section.dart 失效狀態（error scheme 依主題）
    const _TintScenario(
      'PinnedThesis.invalidated',
      ErrorColors.onTintLight,
      ErrorColors.onTintDark,
      Color(0xFFE53935),
      Color(0xFFFF6B6B),
      0.12,
      0.12,
      white,
      darkCard,
    ),
    // chip_anomaly_row.dart
    const _TintScenario(
      'Anomaly.banner',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.08,
      0.08,
      white,
      darkCard,
    ),
    const _TintScenario(
      'Anomaly.count',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.10,
      0.10,
      white,
      darkCard,
    ),
    const _TintScenario(
      'Anomaly.iconBox',
      warnOnTintL,
      warnOnTintD,
      WarningColors.warning,
      WarningColors.warning,
      0.12,
      0.12,
      white,
      darkCard,
      threshold: 3.0,
    ),
    const _TintScenario(
      'Anomaly.orangeBadge',
      warnOnTintL,
      warnOnTintD,
      Color(0xFFFF9800),
      Color(0xFFFF9800),
      0.10,
      0.10,
      white,
      darkCard,
    ),
    const _TintScenario(
      'Anomaly.redBadge',
      ErrorColors.onTintLight,
      ErrorColors.onTintDark,
      Color(0xFFF44336),
      Color(0xFFF44336),
      0.10,
      0.10,
      white,
      darkCard,
    ),
    // market_dashboard.dart 過期廣度徽章（withAlpha(30)=30/255）
    const _TintScenario(
      'StaleBreadth',
      warnOnTintL,
      warnOnTintD,
      DesignTokens.warningLight,
      DesignTokens.warningDark,
      30 / 255,
      30 / 255,
      white,
      darkCard,
    ),
    // market_reading_line.dart 醒目 strip（tint=caution@0.10）
    const _TintScenario(
      'ReadingLine.warningStrip',
      warnOnTintL,
      warnOnTintD,
      WarningColors.caution,
      WarningColors.caution,
      0.10,
      0.10,
      white,
      darkCard,
    ),
    // onboarding step2 圖示（48px 大圖示 → 3.0）
    const _TintScenario(
      'Onboarding.step2Icon',
      warnOnTintL,
      warnOnTintD,
      Color(0xFFFF9800),
      Color(0xFFFF9800),
      0.10,
      0.10,
      white,
      darkScaffold,
      threshold: 3.0,
    ),
    // 行事曆事件徽章（event_list_tile/event_detail_sheet，@0.15 疊 surface）
    // ——審查發現這一家族原本漏在守門外，且 custom/meeting 是全表邊際最薄
    // 的組合（4.67/4.72）。除息紅/財報綠屬 Phase 2 不在此列。
    _TintScenario(
      'Event.exRights',
      EventType.exRights.onTintFor(Brightness.light),
      EventType.exRights.onTintFor(Brightness.dark),
      EventType.exRights.color,
      EventType.exRights.color,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
    _TintScenario(
      'Event.shareholderMeeting',
      EventType.shareholderMeeting.onTintFor(Brightness.light),
      EventType.shareholderMeeting.onTintFor(Brightness.dark),
      EventType.shareholderMeeting.color,
      EventType.shareholderMeeting.color,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
    _TintScenario(
      'Event.disposalEnd',
      EventType.disposalEnd.onTintFor(Brightness.light),
      EventType.disposalEnd.onTintFor(Brightness.dark),
      EventType.disposalEnd.color,
      EventType.disposalEnd.color,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
    _TintScenario(
      'Event.shortSuspension',
      EventType.shortSuspension.onTintFor(Brightness.light),
      EventType.shortSuspension.onTintFor(Brightness.dark),
      EventType.shortSuspension.color,
      EventType.shortSuspension.color,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
    _TintScenario(
      'Event.custom',
      EventType.custom.onTintFor(Brightness.light),
      EventType.custom.onTintFor(Brightness.dark),
      EventType.custom.color,
      EventType.custom.color,
      0.15,
      0.15,
      lightSurface,
      darkCard,
    ),
  ];

  group('Phase1 疊色徽章守門（前景對合成底）', () {
    for (final s in scenarios) {
      test(s.name, () {
        final compL = ColorContrast.compositeOver(
          s.tintLight,
          s.bgLight,
          s.alphaLight,
        );
        final compD = ColorContrast.compositeOver(
          s.tintDark,
          s.bgDark,
          s.alphaDark,
        );
        expect(
          ColorContrast.ratio(s.fgLight, compL),
          greaterThanOrEqualTo(s.threshold),
          reason: '${s.name} 淺色：前景對合成底不足 ${s.threshold}',
        );
        expect(
          ColorContrast.ratio(s.fgDark, compD),
          greaterThanOrEqualTo(s.threshold),
          reason: '${s.name} 深色：前景對合成底不足 ${s.threshold}',
        );
      });
    }

    test('UpdateBanner 步驟指示器（雙層品牌 tint）', () {
      // 淺色：primaryContainer@0.3 疊 scaffold，再疊 chip 漸層 @0.2（取最深的左停點）
      final bannerL = ColorContrast.compositeOver(
        QualityColors.brandOnLight,
        const Color(0xFFFFFFFF),
        0.3,
      );
      final stopL = ColorContrast.compositeOver(
        QualityColors.brandOnLight,
        bannerL,
        0.2,
      );
      expect(
        ColorContrast.ratio(QualityColors.brandOnDeepTintLight, stopL),
        greaterThanOrEqualTo(4.5),
      );
      // 深色：banner 底=surfaceContainerLow(=#27272A)，chip 疊 brand@0.2
      final stopD = ColorContrast.compositeOver(
        QualityColors.brand,
        SemanticColors.darkSurface,
        0.2,
      );
      expect(
        ColorContrast.ratio(QualityColors.brandOnDecorative, stopD),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('指標選擇器五色選中態文字（@0.15 疊 surface）', () {
      const selectors = [
        IndicatorColors.selectorBlue,
        IndicatorColors.selectorPurple,
        IndicatorColors.selectorOrange,
        IndicatorColors.selectorTeal,
        IndicatorColors.selectorRed,
      ];
      for (final base in selectors) {
        final compL = ColorContrast.compositeOver(
          base,
          SemanticColors.lightSurface,
          0.15,
        );
        final compD = ColorContrast.compositeOver(
          base,
          SemanticColors.darkSurface,
          0.15,
        );
        expect(
          ColorContrast.ratio(
            IndicatorColors.selectorOnTint(base, Brightness.light),
            compL,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'selector ${base.toARGB32().toRadixString(16)} 淺色不足',
        );
        expect(
          ColorContrast.ratio(
            IndicatorColors.selectorOnTint(base, Brightness.dark),
            compD,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'selector ${base.toARGB32().toRadixString(16)} 深色不足',
        );
      }
    });

    test('半透明前景文字已全數改實色（OSV 對四種平面背景）', () {
      // Family C sweep 的守門：實色 onSurfaceVariant 對 card/surface 皆達 AA
      for (final (fg, bg) in [
        (osvL, const Color(0xFFFFFFFF)),
        (osvL, SemanticColors.lightSurface),
        (osvD, SemanticColors.darkSurface),
        (osvD, SemanticColors.darkBackground),
      ]) {
        expect(ColorContrast.ratio(fg, bg), greaterThanOrEqualTo(4.5));
      }
    });
  });
}

/// Phase 2 深色紅綠 tint 守門（2026-07-19）。淺色主題 35 組 deferred——
/// 使用者僅使用深色主題；日後啟用淺色前見 PriceColors.upOnTintFor 說明。
void phase2DarkTintGuards() {
  group('Phase2 深色紅綠 tint 守門（淺色 deferred）', () {
    const d = Brightness.dark;

    test('上漲紅 tint 徽章文字：生產 α×背景全組合達 4.5', () {
      final fg = PriceColors.upOnTintFor(d);
      for (final (a, bg) in <(double, Color)>[
        (0.10, SemanticColors.darkSurface),
        (0.12, SemanticColors.darkSurface),
        (0.15, SemanticColors.darkSurface),
        (0.15, SemanticColors.darkBackground),
      ]) {
        final comp = ColorContrast.compositeOver(PriceColors.up, bg, a);
        expect(
          ColorContrast.ratio(fg, comp),
          greaterThanOrEqualTo(4.5),
          reason: 'up@$a 疊 ${bg.toARGB32().toRadixString(16)}',
        );
      }
    });

    test('籌碼評等五級 on-tint（tint=本色@0.15）達 4.5', () {
      for (final r in ChipRating.values) {
        final comp = ColorContrast.compositeOver(
          PriceColors.chipRating(r),
          SemanticColors.darkSurface,
          0.15,
        );
        expect(
          ColorContrast.ratio(PriceColors.chipRatingOnTint(r, d), comp),
          greaterThanOrEqualTo(4.5),
          reason: '$r',
        );
      }
    });

    test('forChangeOnTint 三態（@0.15 疊卡片）達 4.5', () {
      for (final change in <double?>[1.5, -1.5, 0, null]) {
        final comp = ColorContrast.compositeOver(
          PriceColors.forChange(change, d),
          SemanticColors.darkSurface,
          0.15,
        );
        expect(
          ColorContrast.ratio(PriceColors.forChangeOnTint(change, d), comp),
          greaterThanOrEqualTo(4.5),
          reason: 'change=$change',
        );
      }
    });

    test('行事曆 除息/財報 深色 on-tint 達 4.5', () {
      for (final t in [EventType.exDividend, EventType.earnings]) {
        final comp = ColorContrast.compositeOver(
          t.color,
          SemanticColors.darkSurface,
          0.15,
        );
        expect(
          ColorContrast.ratio(t.onTintFor(d), comp),
          greaterThanOrEqualTo(4.5),
          reason: '$t',
        );
      }
    });
  });
}

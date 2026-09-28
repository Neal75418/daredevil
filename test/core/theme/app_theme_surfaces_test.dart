import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('深色主題 primary 對背景達 AA、onPrimary 為深色', () {
    final theme = AppTheme.darkTheme;
    expect(
      ColorContrast.ratio(
        theme.colorScheme.primary,
        theme.scaffoldBackgroundColor,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      ColorContrast.ratio(
        theme.colorScheme.onPrimary,
        theme.colorScheme.primary,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('主題內不再出現 Material 預設 teal', () {
    final theme = AppTheme.darkTheme;
    expect(theme.colorScheme.secondary, isNot(const Color(0xFF03DAC6)));
  });

  test('深色主題表面色飽和度低於 10%', () {
    final theme = AppTheme.darkTheme;
    for (final c in [
      theme.scaffoldBackgroundColor,
      theme.colorScheme.surface,
      theme.dividerTheme.color!,
    ]) {
      final s = HSLColor.fromColor(c).saturation;
      expect(
        s,
        lessThan(0.10),
        reason:
            '${c.toARGB32().toRadixString(16)} 飽和度 '
            '${(s * 100).toStringAsFixed(0)}% 過高，會與股價綠色競爭色相',
      );
    }
  });

  test('深色主題表面色取自 SemanticColors', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, SemanticColors.darkBackground);
    expect(theme.colorScheme.surface, SemanticColors.darkSurface);
  });

  group('ColorScheme 未指定欄位不落回 Material 預設（issue: secondary 曾靜默帶回 teal）', () {
    test('淺色主題 onSecondary／onTertiary 對各自承載色達 AA 4.5:1', () {
      // ColorScheme.light() 的 onSecondary 字面預設值是 Colors.black；
      // onTertiary 本身無字面預設（建構子參數是 Color? 且無預設值），
      // 是透過 getter fallback（onTertiary ??= onSecondary，見 Flutter SDK
      // color_scheme.dart）間接繼承同一個黑。若不明確覆寫，會經
      // onSecondaryContainer／onTertiaryContainer 兩個衍生欄位散布到
      // stock_card 市場標籤、watchlist 數量徽章、stock_detail_header
      // 產業標籤等實際文字上。
      final scheme = AppTheme.lightTheme.colorScheme;
      expect(
        ColorContrast.ratio(scheme.onSecondary, scheme.secondary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        ColorContrast.ratio(scheme.onTertiary, scheme.tertiary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('淺色主題 onErrorContainer 對 errorContainer 達 AA 4.5:1', () {
      // alerts_tab.dart 用 onErrorContainer 承載錯誤說明本文。
      // onErrorContainer 未指定時落回 onError 的 Material 預設字面值
      // Colors.white；errorContainer 未指定時落回的是 error——本檔明確
      // 指定的 #E53935，並非 Material 預設。白字對 #E53935 僅 4.23:1，
      // 不合格。
      final scheme = AppTheme.lightTheme.colorScheme;
      expect(
        ColorContrast.ratio(scheme.onErrorContainer, scheme.errorContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('深色與淺色主題 outlineVariant 貼近低對比 chrome，非 Material 預設的強烈反差', () {
      // 未指定時會經 onBackground 落回 Colors.white（深色）／
      // Colors.black（淺色），對各自的 colorScheme.surface 形成
      // 14.9:1（深色）／19.9:1（淺色，surface 是 #F8F9FA 非純白，21:1
      // 是純黑對純白card/scaffold 的數字）的極端反差，與此系統刻意選用的
      // 低對比 chrome（其餘 outline 類色對表面實測約 1.2-1.4:1）完全不
      // 搭調，會在 comparison/market_dashboard 等 21 個檔案的邊框與圖表
      // 格線上突兀跳出。
      //
      // 用「對表面的對比度遠低於 3:1 圖形物件門檻」而非「不等於某個
      // Material 常數」斷言：後者只攔得住原字面值，攔不住換成另一個
      // 同樣過亮/過暗、依然突兀的顏色。
      final dark = AppTheme.darkTheme.colorScheme;
      final light = AppTheme.lightTheme.colorScheme;
      expect(
        ColorContrast.ratio(dark.outlineVariant, dark.surface),
        lessThan(3.0),
      );
      expect(
        ColorContrast.ratio(light.outlineVariant, light.surface),
        lessThan(3.0),
      );
    });
  });

  group('on-color 與實際疊色底的配對（issue: onSecondary 改白後，疊色底站點反而不合格）', () {
    test('淺色主題：FilterChip 選中底色與 empty_state 資料需求標籤，onSurface 皆達 AA 4.5:1', () {
      // 這兩處的實際底色都不是實心 secondaryContainer，而是疊色：
      // - chipTheme.selectedColor 是 primaryColor 疊 15% alpha 於白之上
      //   （見 app_theme.dart 淺色 chipTheme）
      // - empty_state 的資料需求標籤是 secondaryContainer 疊 60% alpha
      // onSecondaryContainer 是為「文字疊在實心 secondaryContainer 之上」
      // 校準的（見上面「淺色主題 onSecondary／onTertiary」測試），對這兩個
      // 疊色合成背景分別只有 1.14:1／2.90:1，故 scan_screen.dart／
      // news_screen.dart 的 FilterChip 選中標籤與 empty_state.dart 的
      // 資料需求標籤改用 onSurface。深色主題不受影響（chipTheme 未覆寫
      // selectedColor，落回實心 secondaryContainer；empty_state 的
      // onSecondaryContainer 也未改變），故不在此驗證。
      final scheme = AppTheme.lightTheme.colorScheme;

      final chipSelectedBg = ColorContrast.compositeOver(
        AppTheme.primaryColor,
        SemanticColors.lightBackground,
        0.15,
      );
      expect(
        ColorContrast.ratio(scheme.onSurface, chipSelectedBg),
        greaterThanOrEqualTo(4.5),
      );

      final emptyStateTagBg = ColorContrast.compositeOver(
        scheme.secondaryContainer,
        SemanticColors.lightBackground,
        0.6,
      );
      expect(
        ColorContrast.ratio(scheme.onSurface, emptyStateTagBg),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('🚨 無邊框輸入框必須靠填色與容器區分(2026-08-08 實機)', () {
    // 深色主題同時做了兩件事:把邊框設成 BorderSide.none,**又**把 fillColor
    // 設成與 dialogTheme.backgroundColor 同一個常數(SemanticColors.darkSurface)
    // → 對比度 1.00:1,對話框裡的輸入框整個看不見,只剩懸空的文字,而框的
    // 內距看起來像莫名其妙的縮排。
    //
    // 沒有任何 golden 測試渲染過深色模式的輸入框,所以改壞了也不會紅——
    // 這條守在主題層,不依賴任何畫面有沒有被拍成 golden。

    double ratio(Color a, Color b) => ColorContrast.ratio(a, b);

    test('深色:輸入框填色 ≠ 對話框底色', () {
      final t = AppTheme.darkTheme;
      final fill = t.inputDecorationTheme.fillColor!;
      final dialogBg = t.dialogTheme.backgroundColor!;
      expect(fill, isNot(dialogBg), reason: '同色 = 框看不見。這正是 2026-08-08 實機回報的狀況');
      expect(
        ratio(fill, dialogBg),
        greaterThan(1.2),
        reason: '要看得出邊界,實測 ${ratio(fill, dialogBg).toStringAsFixed(2)}:1',
      );
    });

    test('深色:輸入框填色 ≠ 卡片底色(卡片內的欄位同樣要看得見)', () {
      final t = AppTheme.darkTheme;
      final fill = t.inputDecorationTheme.fillColor!;
      expect(fill, isNot(t.cardTheme.color));
    });

    test('淺色主題靠邊框區分,不受此限', () {
      // 淺色沒有這個問題:它保留了 BorderSide(color: ...)。記錄下來,
      // 免得日後有人「統一」成無邊框時把淺色也一起弄壞。
      final t = AppTheme.lightTheme;
      final border = t.inputDecorationTheme.enabledBorder as OutlineInputBorder;
      expect(
        border.borderSide.style,
        BorderStyle.solid,
        reason: '淺色若也改成無邊框,就必須比照深色檢查填色對比',
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart';

import '../../../../../helpers/widget_test_helpers.dart';

void main() {
  const zh = Locale('zh', 'TW');
  const en = Locale('en');

  setUpAll(() async {
    await setupTestLocalization();
  });

  group('formatLots（依語系分級；測試未載翻譯，`.tr()` 回傳 key）', () {
    const unit = 'stockDetail.unitShares';

    test('中文：萬張／千張／張，一位小數', () {
      expect(formatLots(15000, zh), '1.5萬$unit');
      expect(formatLots(1500, zh), '1.5千$unit');
      expect(formatLots(500, zh), '500$unit');
    });

    test('英文：1.5 萬張 = 15 thousand lots，不是 1.5 thousand', () {
      expect(formatLots(15000, en), '15.0K$unit');
      expect(formatLots(1500, en), '1.5K$unit');
      expect(formatLots(500, en), '500$unit');
    });

    test('英文 formatNet 帶正負號', () {
      expect(formatNet(15_000_000, en), '+15.0K$unit');
      expect(formatNet(-15_000_000, en), '-15.0K$unit');
    });
  });

  group('formatNet', () {
    test('positive small value stays in raw units', () {
      // value < 1000 → just the raw number with +
      expect(formatNet(500, zh), '+500');
    });

    test('negative small value stays in raw units', () {
      expect(formatNet(-300, zh), '-300');
    });

    test('zero returns unsigned 0（平盤不帶 +）', () {
      expect(formatNet(0, zh), '0');
    });
  });

  group('formatSharesChange', () {
    test('positive value keeps +', () {
      expect(formatSharesChange(500), startsWith('+'));
    });

    test('zero has no + sign（平盤不帶 +）', () {
      expect(formatSharesChange(0), isNot(startsWith('+')));
    });
  });

  group('平盤配色一致性（顯示 0 不著漲跌方向色）', () {
    testWidgets('buildNetValue 平盤（0）著中性色', (tester) async {
      await tester.pumpWidget(
        buildTestApp(Builder(builder: (c) => buildNetValue(c, 0))),
      );
      final text = tester.widget<Text>(find.text('0'));
      expect(
        text.style?.color,
        AppTheme.getFlatColor(Brightness.light),
        reason: '平盤淨額顯示 0，不得著漲(紅)色',
      );
    });

    testWidgets('buildSummaryCard 平盤（0）著中性色', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (c) => buildSummaryCard(c, '外資', 0, Icons.trending_up),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('0'));
      expect(text.style?.color, AppTheme.getFlatColor(Brightness.light));
    });
  });

  group('formatBalance', () {
    test('delegates to formatLots', () {
      // formatBalance(value) == formatLots(value)
      final result = formatBalance(500, zh);
      final expected = formatLots(500, zh);
      expect(result, expected);
    });
  });

  group('buildSummaryCard', () {
    testWidgets('displays label and formatted value', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) =>
                buildSummaryCard(context, '外資', 5000, Icons.trending_up),
          ),
        ),
      );

      expect(find.text('外資'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    for (final (locale, expected) in [
      (const Locale('zh', 'TW'), '+1.5萬'),
      (const Locale('en', 'US'), '+15.0K'),
    ]) {
      testWidgets('淨額依 context 語系格式化：$locale → $expected', (tester) async {
        // 15,000,000 股 = 15,000 張
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) =>
                  buildSummaryCard(context, '外資', 15000000, Icons.trending_up),
            ),
            locale: locale,
          ),
        );
        expect(find.textContaining(expected), findsOneWidget);
      });
    }
  });

  group('buildColumnHeader', () {
    testWidgets('displays label with dot', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Row(children: [buildColumnHeader(theme, '買超')]);
            },
          ),
        ),
      );

      expect(find.text('買超'), findsOneWidget);
    });
  });

  group('法人身分圖示／圓點對比度守門（C3：法人色移除後的退步）', () {
    // 法人色移除後，身分改由「圖示形狀」承擔（設計文件明載）——圖示因此是
    // 需傳達資訊的圖形物件，適用 WCAG 3.0:1。呼叫端曾一律傳入
    // CategoryColors.neutral（#A1A1AA），對本卡片底色 surfaceContainerLow
    // （淺色主題 #F8F9FA）僅 2.43:1，比移除前的投信紫 #9B59B6（4.43:1）
    // 明確退步。此測試取「實際渲染出來的 Icon.color」再對「實際渲染背景」
    // 算對比度，而非斷言某個常數——後者無法察覺呼叫端又把不合格色傳回來。
    Future<void> pumpCard(WidgetTester tester, Brightness brightness) async {
      tester.view.physicalSize = const Size(2000, 2000);
      addTearDown(() => tester.view.resetPhysicalSize());
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (c) => buildSummaryCard(c, '外資', 5000, Icons.language),
          ),
          brightness: brightness,
        ),
      );
    }

    for (final brightness in Brightness.values) {
      testWidgets('摘要卡 14px 圖示對卡片底達 3.0:1（$brightness）', (tester) async {
        await pumpCard(tester, brightness);

        final icon = tester.widget<Icon>(find.byIcon(Icons.language));
        final container = tester.widget<Container>(
          find
              .ancestor(
                of: find.byIcon(Icons.language),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;

        expect(
          ColorContrast.ratio(icon.color!, decoration.color!),
          greaterThanOrEqualTo(3.0),
          reason:
              '圖示 ${icon.color} 對實際卡片底 ${decoration.color} 對比不足；'
              '法人色移除後圖示形狀承擔身分，適用圖形物件門檻',
        );
      });

      testWidgets('明細表 8px 圓點對表頭底達 3.0:1（$brightness）', (tester) async {
        tester.view.physicalSize = const Size(2000, 2000);
        addTearDown(() => tester.view.resetPhysicalSize());
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Container(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Row(children: [buildColumnHeader(theme, '外資')]),
                );
              },
            ),
            brightness: brightness,
          ),
        );

        final dot = tester.widget<Container>(
          find
              .ancestor(of: find.text('外資'), matching: find.byType(Container))
              .last,
        );
        // 取圓點本身（SizedBox 尺寸 8x8 的那個 Container）
        final dots = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) => c.decoration is BoxDecoration)
            .map((c) => c.decoration! as BoxDecoration)
            .where((d) => d.shape == BoxShape.circle)
            .toList();
        expect(dots, hasLength(1), reason: '預期恰好一個圓點');
        expect(dot, isNotNull);

        final bg = tester
            .widget<Container>(find.byType(Container).first)
            .color!;
        expect(
          ColorContrast.ratio(dots.single.color!, bg),
          greaterThanOrEqualTo(3.0),
          reason: '圓點 ${dots.single.color} 對表頭底 $bg 對比不足',
        );
      });
    }
  });
}

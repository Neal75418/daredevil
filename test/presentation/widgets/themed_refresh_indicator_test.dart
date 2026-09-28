import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('ThemedRefreshIndicator', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          ThemedRefreshIndicator(
            onRefresh: () async {},
            child: ListView(children: const [Text('Item 1'), Text('Item 2')]),
          ),
        ),
      );

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });

    testWidgets('wraps child in RefreshIndicator', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          ThemedRefreshIndicator(
            onRefresh: () async {},
            child: ListView(children: const [Text('content')]),
          ),
        ),
      );

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('主題盲色彩守門（C5）', () {
    // AppTheme.primaryColor 恆為品牌色（現為 brand #60A5FA，為深色主題挑的
    // 亮色）。RefreshIndicator 的弧線是圖形物件（需 3.0:1），而它的
    // backgroundColor 在淺色主題是 colorScheme.surface——亮色對其不足 3:1。
    // 斷言「實際渲染出來的 color 對實際渲染出來的 backgroundColor」的對比，
    // 而非斷言等於某個常數：常數等式擋不住有人換成另一個同樣過亮的顏色。
    for (final brightness in Brightness.values) {
      testWidgets('旋轉弧線對自身背景達圖形物件門檻 3.0:1（$brightness）', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            ThemedRefreshIndicator(
              onRefresh: () async {},
              child: ListView(children: const [Text('content')]),
            ),
            brightness: brightness,
          ),
        );

        final indicator = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );
        expect(indicator.color, isNotNull);
        expect(indicator.backgroundColor, isNotNull);
        expect(
          ColorContrast.ratio(indicator.color!, indicator.backgroundColor!),
          greaterThanOrEqualTo(3.0),
          reason:
              '弧線 ${indicator.color} 對 indicator 背景 '
              '${indicator.backgroundColor} 對比不足',
        );
      });
    }
  });
}

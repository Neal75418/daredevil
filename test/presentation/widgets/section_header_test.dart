import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/widgets/section_header.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  group('SectionHeader', () {
    testWidgets('displays title text', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SectionHeader(title: 'Test Section', animate: false),
        ),
      );

      expect(find.text('Test Section'), findsOneWidget);
    });

    testWidgets('displays icon when provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SectionHeader(
            title: 'With Icon',
            icon: Icons.star,
            animate: false,
          ),
        ),
      );

      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('does not display icon when not provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SectionHeader(title: 'No Icon', animate: false)),
      );

      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('displays subtitle when provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SectionHeader(
            title: 'Title',
            subtitle: 'Subtitle text',
            animate: false,
          ),
        ),
      );

      expect(find.text('Subtitle text'), findsOneWidget);
    });

    testWidgets('does not display subtitle when not provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SectionHeader(title: 'Only Title', animate: false)),
      );

      // 只有標題文字
      expect(find.text('Only Title'), findsOneWidget);
    });

    testWidgets('displays trailing widget when provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          SectionHeader(
            title: 'With Action',
            trailing: TextButton(
              onPressed: () {},
              child: const Text('View All'),
            ),
            animate: false,
          ),
        ),
      );

      expect(find.text('View All'), findsOneWidget);
    });

    testWidgets('trailing action button is tappable', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        buildTestApp(
          SectionHeader(
            title: 'Action',
            trailing: TextButton(
              onPressed: () => tapped = true,
              child: const Text('Tap me'),
            ),
            animate: false,
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));
      expect(tapped, isTrue);
    });

    // 族群排行的期間切換：標題 Expanded＋trailing Flexible 平分寬度，窄螢幕
    // 時 trailing 在「靠右對齊的橫向捲動」裡，第一個選項「今日」被捲出畫面
    // （2026-09-25 實機 ~397pt）。放不下時整排換到標題下一行。
    group('trailing 放不下時', () {
      Widget segmented(List<String> labels) => SegmentedButton<int>(
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        showSelectedIcon: false,
        segments: [
          for (var i = 0; i < labels.length; i++)
            ButtonSegment(value: i, label: Text(labels[i])),
        ],
        selected: const {0},
        onSelectionChanged: (_) {},
      );

      const rankModes = ['今日', '5日', '20日', '轉向'];

      Future<void> pumpAt(
        WidgetTester tester,
        double width,
        List<String> labels,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          buildTestApp(
            SectionHeader(
              title: '族群排行',
              icon: Icons.workspaces_outline,
              trailing: segmented(labels),
              animate: false,
            ),
          ),
        );
      }

      // 「在螢幕座標內」不等於看得到：被捲出捲動區的選項座標會落在標題
      // 底下、只是被裁掉。要完整落在所在捲動區的可見範圍內，且點得到。
      void expectFullyVisible(WidgetTester tester, String label, double width) {
        final text = find.text(label);
        final rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(width), reason: label);
        final scrollable = find.ancestor(
          of: text,
          matching: find.byType(Scrollable),
        );
        if (scrollable.evaluate().isNotEmpty) {
          final viewport = tester.getRect(scrollable.first);
          expect(rect.left, greaterThanOrEqualTo(viewport.left), reason: label);
          expect(rect.right, lessThanOrEqualTo(viewport.right), reason: label);
        }
        expect(text.hitTestable(), findsOneWidget, reason: label);
      }

      // 框在畫面內不代表讀得懂：受擠壓時字形可能被從中間切成多行
      void expectNotBrokenMidWord(WidgetTester tester, String label) {
        final rp = tester.renderObject<RenderParagraph>(find.text(label));
        expect(
          rp.size.width,
          greaterThanOrEqualTo(rp.getMinIntrinsicWidth(double.infinity) - 0.5),
          reason: label,
        );
      }

      for (final width in [320.0, 360.0, 390.0]) {
        testWidgets('${width.toInt()} 寬：四個選項全部完整可見、不溢出', (tester) async {
          await pumpAt(tester, width, rankModes);
          expect(tester.takeException(), isNull);
          for (final label in rankModes) {
            expectFullyVisible(tester, label, width);
            expectNotBrokenMidWord(tester, label);
          }
        });
      }

      testWidgets('寬螢幕放得下 → 與標題同一行', (tester) async {
        await pumpAt(tester, 1200, rankModes);
        final title = tester.getRect(find.text('族群排行'));
        final first = tester.getRect(find.text('今日'));
        expect(first.top, lessThan(title.bottom));
        expect(first.bottom, greaterThan(title.top));
        // 靠右（右側 16pt 內距）。改版前停在中線：標題 Expanded 與 trailing
        // Flexible 平分寬度，loose 的 Flexible 只取內容寬度
        final last = tester.getRect(find.text('轉向'));
        expect(last.right, greaterThan(1200 - 16 - 40));
      });

      // 同一行時 trailing 與標題區垂直置中（有副標時標題區較高）
      testWidgets('有副標、同一行 → trailing 與標題區垂直置中', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          buildTestApp(
            SectionHeader(
              title: '族群排行',
              subtitle: '副標題說明文字',
              icon: Icons.workspaces_outline,
              trailing: segmented(rankModes),
              animate: false,
            ),
          ),
        );
        final titleTop = tester.getRect(find.text('族群排行')).top;
        final subtitleBottom = tester.getRect(find.text('副標題說明文字')).bottom;
        final trailing = tester.getRect(find.byType(SegmentedButton<int>));
        expect(
          trailing.center.dy,
          moreOrLessEquals((titleTop + subtitleBottom) / 2, epsilon: 1),
        );
      });

      testWidgets('長標題＋trailing → 標題自己換行、不溢出', (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          buildTestApp(
            SectionHeader(
              title: '一個非常非常長的區塊標題會超過一整行的寬度',
              icon: Icons.workspaces_outline,
              trailing: segmented(rankModes),
              animate: false,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expectFullyVisible(tester, '今日', 320);
      });

      // 連獨立一行都放不下（英文長標籤、最窄手機）：不捲動——SegmentedButton
      // 受寬度限制等分縮窄、標籤換行，所有選項仍看得到（捲動會藏住另一端）。
      // 這裡只驗「看得到」；極端情況下單字可能被切開（見可讀性 minor）。
      testWidgets('一整行也放不下 → 不溢出、所有選項可見', (tester) async {
        const longLabels = [
          'Today',
          '5 days',
          '20 days',
          'Rotation',
          'Extra long option',
        ];
        await pumpAt(tester, 320, longLabels);
        expect(tester.takeException(), isNull);
        for (final label in longLabels) {
          expectFullyVisible(tester, label, 320);
        }
      });
    });

    testWidgets('renders with animation when animate is true', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SectionHeader(title: 'Animated', animate: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Animated'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SectionHeader(title: 'Dark Mode', animate: false),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('Dark Mode'), findsOneWidget);
    });
  });
}

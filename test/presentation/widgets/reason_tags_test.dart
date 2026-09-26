import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/presentation/widgets/reason_tags.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('ReasonTags 校準背書標記', () {
    testWidgets('背書的 reason chip 顯示 verified 標記，其餘不顯示', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          ReasonTags(
            reasons: const ['WEEK_52_HIGH', 'KD_GOLDEN_CROSS'],
            translateCodes: true,
            isCalibrationBacked: (code) => code == 'WEEK_52_HIGH',
          ),
        ),
      );
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    });

    testWidgets('translateCodes=false（傳的是 label 非 code）時不標記', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          ReasonTags(
            reasons: const ['WEEK_52_HIGH'],
            isCalibrationBacked: (_) => true,
          ),
        ),
      );
      expect(find.byIcon(Icons.verified_outlined), findsNothing);
    });
  });

  group('ReasonTags', () {
    testWidgets('displays all reason labels', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const ReasonTags(reasons: ['Alpha', 'Beta', 'Gamma'])),
      );

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });

    testWidgets('limits displayed tags with maxTags', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ReasonTags(reasons: ['A', 'B', 'C', 'D', 'E'], maxTags: 3),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsNothing);
      expect(find.text('E'), findsNothing);
    });

    testWidgets('shows all tags when maxTags is null', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const ReasonTags(reasons: ['X', 'Y', 'Z'])),
      );

      expect(find.text('X'), findsOneWidget);
      expect(find.text('Y'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('renders empty when reasons list is empty', (tester) async {
      await tester.pumpWidget(buildTestApp(const ReasonTags(reasons: [])));

      expect(find.byType(Wrap), findsOneWidget);
    });

    testWidgets('renders with compact size', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ReasonTags(reasons: ['Tag1'], size: ReasonTagSize.compact),
        ),
      );

      expect(find.text('Tag1'), findsOneWidget);
    });

    testWidgets('renders with normal size', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ReasonTags(reasons: ['Tag1'], size: ReasonTagSize.normal),
        ),
      );

      expect(find.text('Tag1'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ReasonTags(reasons: ['DarkTag']),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('DarkTag'), findsOneWidget);
    });

    testWidgets('深色模式實際渲染的底色疊加文字色，對比達 AA 4.5:1（守住接線，非只守常數）', (tester) async {
      // 這裡刻意從 render tree 讀取實際的 decoration 底色、alpha 與文字
      // 色——而非重複斷言 QualityColors 常數彼此的數值——否則若有人把
      // 文字色改回未經校準的顏色，或改了 DesignTokens.opacity25，
      // 只驗證常數值的守門測試不會發現任何異常（常數本身沒變）。
      await tester.pumpWidget(
        buildTestApp(
          const ReasonTags(reasons: ['DarkTag']),
          brightness: Brightness.dark,
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('DarkTag'),
              matching: find.byType(Container),
            )
            .first,
      );
      final tint = (container.decoration! as BoxDecoration).color!;
      final textColor = tester.widget<Text>(find.text('DarkTag')).style!.color!;

      // ReasonTags 兩個真實使用點的卡片底色：stock_preview_sheet.dart 是
      // colorScheme.surface；stock_card.dart 走 AppTheme.cardDecoration。
      // 此處以 colorScheme.surface 為準。
      final composite = ColorContrast.compositeOver(
        Color.from(alpha: 1.0, red: tint.r, green: tint.g, blue: tint.b),
        AppTheme.darkTheme.colorScheme.surface,
        tint.a,
      );
      expect(
        ColorContrast.ratio(textColor, composite),
        greaterThanOrEqualTo(4.5),
      );
    });

    // 初版用 colorScheme.error 自疊自(#FF6B6B 文字疊自身 25% tint)僅
    // ~3.6:1——審查抓出後改用 AppTheme.errorColor tint +
    // ErrorColors.onTintFor(WarningBadge 同源校準)。從 render tree 讀
    // 實際色,防止改回未校準顏色。每個 brightness 獨立 testWidgets:
    // MaterialApp 換 theme 有 AnimatedTheme 過渡,同 tree 內切換會讀到
    // 過渡中的舊 theme。
    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets('跌破風控 tag(isRisk)$brightness 實渲染對比達 AA 4.5:1', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestApp(
            const ReasonTags(reasons: ['BREAK_MA60'], translateCodes: true),
            brightness: brightness,
          ),
        );
        final theme = brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;
        final label = ReasonTags.translateReasonCode('BREAK_MA60');
        final container = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        final tint = (container.decoration! as BoxDecoration).color!;
        final textColor = tester.widget<Text>(find.text(label)).style!.color!;
        final composite = ColorContrast.compositeOver(
          Color.from(alpha: 1.0, red: tint.r, green: tint.g, blue: tint.b),
          theme.colorScheme.surface,
          tint.a,
        );
        expect(
          ColorContrast.ratio(textColor, composite),
          greaterThanOrEqualTo(4.5),
          reason: '$brightness isRisk tag 對比不足',
        );
      });
    }
  });

  group('ReasonTags.translateReasonCode', () {
    test('returns original code for unknown codes', () {
      expect(ReasonTags.translateReasonCode('UNKNOWN_CODE'), isNotEmpty);
    });

    test('tooltipForReasonCode returns null for unknown codes', () {
      expect(ReasonTags.tooltipForReasonCode('UNKNOWN_CODE'), isNull);
    });
  });
}

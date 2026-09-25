// ScoreTierBadge widget 測試 — 分級徽章 + 小字數字（評分改進 #5，
// 使用者選定「徽章為主視覺、確切分數退為小字」）
//
// 測試環境不載實際翻譯（setupTestLocalization 慣例）→ .tr() 回傳 key，
// 斷言以 i18n key 為準；實際字面（強/中/弱/觀察）由 zh-TW.json 保證。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/presentation/widgets/score_tier_badge.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(buildTestApp(child, brightness: Brightness.light));
  }

  group('ScoreTierBadge — 單分數', () {
    testWidgets('強級分數：顯示「強」徽章 + 小字數字', (tester) async {
      await pump(tester, const ScoreTierBadge(score: 52));
      expect(find.text('score.tier.strong'), findsOneWidget);
      expect(find.text('52'), findsOneWidget);
    });

    testWidgets('弱級分數：顯示「弱」徽章', (tester) async {
      await pump(tester, const ScoreTierBadge(score: 14));
      expect(find.text('score.tier.weak'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('觀察區分數（< 12）：顯示「觀察」', (tester) async {
      await pump(tester, const ScoreTierBadge(score: 9));
      expect(find.text('score.tier.observation'), findsOneWidget);
    });
  });

  group('ScoreTierBadge — 雙 horizon', () {
    // 只顯示分級依據的那個分數（較高者）：兩個數字並排讓徽章在窄卡片
    // 被 FittedBox 縮到看不清（390pt 約 0.42 倍），且看不出分級看哪個
    testWidgets('雙分數不同：徽章取較高分的級別、只顯示較高的分數', (tester) async {
      // short 20（弱）、long 48（強）→ 徽章「強」＋ 48
      await pump(
        tester,
        const ScoreTierBadge.dual(shortScore: 20, longScore: 48),
      );
      expect(find.text('score.tier.strong'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('20'), findsNothing);
      expect(
        tester.widget<Text>(find.text('48')).style!.fontSize,
        greaterThanOrEqualTo(11),
      );
    });

    testWidgets('雙分數相同：collapse 成單一數字、無 horizon 標籤', (tester) async {
      await pump(
        tester,
        const ScoreTierBadge.dual(shortScore: 30, longScore: 30),
      );
      expect(find.text('score.tier.medium'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
    });
  });

  // 分數是「符合條件的程度」、不是漲跌：紅綠專屬股價，徽章用品牌色深淺
  // （原本強／中是綠系，緊貼綠色的下跌數字會被讀成看跌）
  group('ScoreTierBadge — 配色', () {
    BoxDecoration decorationOf(WidgetTester tester, String tierKey) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(tierKey),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    Color? textColorOf(WidgetTester tester, String tierKey) =>
        tester.widget<Text>(find.text(tierKey)).style?.color;

    for (final brightness in Brightness.values) {
      group(brightness.name, () {
        Future<ColorScheme> pumpScore(WidgetTester tester, double score) async {
          await tester.pumpWidget(
            buildTestApp(ScoreTierBadge(score: score), brightness: brightness),
          );
          return Theme.of(
            tester.element(find.byType(ScoreTierBadge)),
          ).colorScheme;
        }

        testWidgets('強：品牌色實心', (tester) async {
          final scheme = await pumpScore(tester, 52);
          final d = decorationOf(tester, 'score.tier.strong');
          expect(d.color, scheme.primary);
          expect(textColorOf(tester, 'score.tier.strong'), scheme.onPrimary);
        });

        testWidgets('中：品牌色外框', (tester) async {
          final scheme = await pumpScore(tester, 30);
          final d = decorationOf(tester, 'score.tier.medium');
          expect((d.border! as Border).top.color, scheme.primary);
          expect(textColorOf(tester, 'score.tier.medium'), scheme.primary);
        });

        testWidgets('弱：灰色外框', (tester) async {
          final scheme = await pumpScore(tester, 14);
          final d = decorationOf(tester, 'score.tier.weak');
          expect((d.border! as Border).top.color, scheme.onSurfaceVariant);
          expect(
            textColorOf(tester, 'score.tier.weak'),
            scheme.onSurfaceVariant,
          );
        });

        // 觀察與弱只靠「有沒有框」區分：沒有框、灰字
        testWidgets('觀察：無框灰字（與弱區分）', (tester) async {
          final scheme = await pumpScore(tester, 9);
          final d = decorationOf(tester, 'score.tier.observation');
          expect(d.border, isNull);
          expect(d.color, isNull);
          expect(
            textColorOf(tester, 'score.tier.observation'),
            scheme.onSurfaceVariant,
          );
        });

        testWidgets('強／中／弱都不得是漲跌色', (tester) async {
          final priceColors = {
            AppTheme.getPriceColor(1, brightness),
            AppTheme.getPriceColor(-1, brightness),
            PriceColors.up,
            PriceColors.down,
            PriceColors.downOnLight,
          };
          for (final (score, key) in [
            (52.0, 'score.tier.strong'),
            (30.0, 'score.tier.medium'),
            (14.0, 'score.tier.weak'),
          ]) {
            await pumpScore(tester, score);
            final d = decorationOf(tester, key);
            final used = {
              ?d.color?.withValues(alpha: 1),
              if (d.border is Border) (d.border! as Border).top.color,
              ?textColorOf(tester, key),
            };
            expect(used.intersection(priceColors), isEmpty, reason: key);
          }
        });
      });
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/chip_strength_indicator.dart';

import '../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('ChipStrengthIndicator', () {
    testWidgets('displays battery icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const ChipStrengthIndicator(
            strength: ChipStrengthResult(
              score: 75,
              rating: ChipRating.strong,
              attitude: InstitutionalAttitude.aggressiveBuy,
              measuredDomains: 6,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.battery_charging_full), findsOneWidget);
    });

    testWidgets('displays score value', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const ChipStrengthIndicator(
            strength: ChipStrengthResult(
              score: 85,
              rating: ChipRating.strong,
              attitude: InstitutionalAttitude.aggressiveBuy,
              measuredDomains: 6,
            ),
          ),
        ),
      );

      expect(find.text('85'), findsOneWidget);
      expect(find.text(' / 100'), findsOneWidget);
    });

    testWidgets('renders with weak rating', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const ChipStrengthIndicator(
            strength: ChipStrengthResult(
              score: 5,
              rating: ChipRating.weak,
              attitude: InstitutionalAttitude.aggressiveSell,
              measuredDomains: 6,
            ),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders with neutral rating', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const ChipStrengthIndicator(
            strength: ChipStrengthResult(
              score: 40,
              rating: ChipRating.neutral,
              attitude: InstitutionalAttitude.neutral,
              measuredDomains: 6,
            ),
          ),
        ),
      );

      expect(find.text('40'), findsOneWidget);
    });
  });

  group('籌碼評等顏色（台股慣例：紅漲綠跌，與國際慣例相反）', () {
    // 測試對象必須是 widget 實際渲染出的顏色，不是 PriceColors.chipRating
    // 常數——後者在 Task 2 已實作，對它斷言的測試一寫出來就是綠的，
    // 看不到失敗就不算 TDD。本 Task 的交付是 widget 改用新映射。
    Future<Color?> renderedRatingColor(
      WidgetTester tester,
      ChipRating rating,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          ChipStrengthIndicator(
            strength: ChipStrengthResult(
              score: 50,
              rating: rating,
              attitude: InstitutionalAttitude.neutral,
              measuredDomains: 6,
            ),
          ),
        ),
      );
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.battery_charging_full),
      );
      return icon.color;
    }

    testWidgets('籌碼強勢渲染為紅色（台股慣例：與上漲同色）', (tester) async {
      expect(
        await renderedRatingColor(tester, ChipRating.strong),
        PriceColors.up,
      );
    });

    testWidgets('籌碼弱勢渲染為綠色（台股慣例：與下跌同色）', (tester) async {
      expect(
        await renderedRatingColor(tester, ChipRating.weak),
        PriceColors.down,
      );
    });

    testWidgets('籌碼中性渲染為灰階，不佔用色相', (tester) async {
      expect(
        await renderedRatingColor(tester, ChipRating.neutral),
        PriceColors.flat,
      );
    });

    testWidgets('🚨 資料不足 → 顯示「資料不足」,不得渲染無輸入的預設評級', (tester) async {
      // baseline 50 之後,稀疏股實際會到 UI 的狀態是 score=50/neutral
      // (無輸入下的預設值,不是量測結果)——舊 fixture 的 score=0/weak 在
      // measuredDomains=1 下已結構性不可達(單域最大負值 −27 → 最低 23),
      // 守的是不存在的狀態(2026-08-29 review)。
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const ChipStrengthIndicator(
            strength: ChipStrengthResult(
              score: ChipScoringParams.baselineScore,
              rating: ChipRating.neutral, // fromScore(baseline) 的產物——不得顯示
              attitude: InstitutionalAttitude.neutral,
              measuredDomains: 1,
            ),
          ),
        ),
      );

      expect(find.textContaining('chip.insufficientCaption'), findsOneWidget);
      expect(
        find.text('chip.ratingNeutral'),
        findsNothing,
        reason: '「沒被量測」與「實測中性」不得逐 pixel 相同',
      );
      expect(
        find.text('${ChipScoringParams.baselineScore}'),
        findsNothing,
        reason: '分數是無輸入下的預設值,不得顯示',
      );
    });
  });
}

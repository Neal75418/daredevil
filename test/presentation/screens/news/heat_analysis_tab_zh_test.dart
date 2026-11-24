// 真實 zh-TW 翻譯下的回檔暫停說明（帶比例）。zhTranslations 會寫入全域翻譯
// 且不還原，所以獨立成檔（見 buildProviderTestApp 的說明）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/domain/models/market_regime.dart';
import 'package:daredevil/domain/services/news/heat_calculator.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/news_heat_provider.dart';
import 'package:daredevil/presentation/screens/news/heat_analysis_tab.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  testWidgets('只看回檔中、大盤偏空：說明寫出比例與恢復條件', (tester) async {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
    const noPullback = NewsHeatAnalysis(
      themes: [
        ThemeHeat(
          theme: '記憶體',
          articles7d: 23,
          articlesPrev21d: 6,
          isSurging: true,
          topStocks: ['2408'],
        ),
      ],
      stocks: [
        StockHeat(
          symbol: '2408',
          mentions7d: 9,
          mentionsPrev21d: 2,
          isSurging: true,
          distinctSources7d: 3,
          hasRiskNews: false,
          isNewEntrant: false,
          surgeRatio: 9.0,
        ),
      ],
      stockNames: {'2408': '南亞科'},
      modeBySymbol: {'2408': ScoringMode.strengthObserve},
      priceChangeBySymbol: {},
      warningBySymbol: {},
      surgeReliable: true,
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        const HeatAnalysisTab(),
        zhTranslations: true,
        overrides: [
          newsHeatProvider.overrideWith((ref) async => noPullback),
          pullbackPauseProvider.overrideWithValue(
            const MarketRegimeReading(
              eligibleCount: 455,
              upCount: 132,
              medianReturn: -0.1609,
              isUptrend: false,
              lookbackDays: 120,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看回檔中'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('回檔訊號暫停'), findsOneWidget);
    // 132／455＝29.0%
    expect(find.textContaining('只有 29% 比半年前高，過半就會恢復'), findsOneWidget);
  });
}

/// Golden test: MarketOverviewScreen（今日頁摘要條進入的完整大盤頁）
///
/// 平台相依（字型渲染），只在本機跑；CI 以 --exclude-tags golden 排除。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/screens/market/market_overview_screen.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class _FakeMarket extends MarketOverviewNotifier {
  @override
  MarketOverviewState build() => _testMarket;

  @override
  Future<void> loadData() async {}
}

final _testDate = DateTime(2026, 3, 10);

final _testMarket = MarketOverviewState(
  indices: [
    TwseMarketIndex(
      date: _testDate,
      name: MarketIndexNames.taiex,
      close: 22150.3,
      change: -61.2,
      changePercent: -0.28,
    ),
    TwseMarketIndex(
      date: _testDate,
      name: MarketIndexNames.tpexIndex,
      close: 245.6,
      change: 0.25,
      changePercent: 0.1,
    ),
  ],
  indexHistory: {
    MarketIndexNames.taiex: List.generate(60, (i) => 21500.0 + i * 11),
  },
  advanceDeclineByMarket: const {
    MarketCode.twse: AdvanceDecline(advance: 408, decline: 667, unchanged: 149),
    MarketCode.tpex: AdvanceDecline(advance: 380, decline: 402, unchanged: 88),
  },
  historyTrends: HistoryTrends(
    turnover: {
      MarketCode.twse: [
        (date: DateTime(2026, 3, 9), value: 3500.0),
        (date: DateTime(2026, 3, 10), value: 3200.0),
      ],
    },
  ),
);

/// 測試環境 .tr() 回 key 字串（比真實文字長），1080 寬時儀表板情緒區塊
/// 假溢出（1600 寬並排雙欄時每欄仍不足）；加寬到 2000。手機寬度的實際樣貌由實機截圖確認。
void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _build(Brightness brightness) => buildProviderTestApp(
  const MarketOverviewScreen(),
  overrides: [marketOverviewProvider.overrideWith(_FakeMarket.new)],
  brightness: brightness,
);

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('MarketOverviewScreen Golden', () {
    testWidgets('light', (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_build(Brightness.light));
      // 儀表板各區塊有錯開的進場淡入，推到動畫結束才截
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/market_overview_screen_light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_build(Brightness.dark));
      // 儀表板各區塊有錯開的進場淡入，推到動畫結束才截
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/market_overview_screen_dark.png'),
      );
    });
  });
}

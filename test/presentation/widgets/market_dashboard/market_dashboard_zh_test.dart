import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/hero_index_section.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// Hero 指數狀態列「指數為 M/D 收盤」以真實 zh-TW 翻譯驗完整字串（含日期）：
// 沒載翻譯時 .tr() 回 key、日期不會被比到。真實翻譯寫入全域
// Localization.instance、會污染同檔其他測試，故獨立成檔。
void main() {
  setUpAll(() async => setupTestLocalization());

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  TwseMarketIndex index(String name, DateTime date) => TwseMarketIndex(
    date: date,
    name: name,
    close: 21000,
    change: 100,
    changePercent: 0.5,
  );

  MarketOverviewState state({
    required List<TwseMarketIndex> indices,
    Map<String, DateTime> stale = const {},
  }) => MarketOverviewState(
    indices: indices,
    advanceDeclineByMarket: {
      MarketCode.twse: const AdvanceDecline(advance: 500, decline: 300),
      MarketCode.tpex: const AdvanceDecline(advance: 200, decline: 150),
    },
    advanceDeclineStaleDates: stale,
    dataDate: DateTime(2026, 2, 13),
  );

  Future<void> pump(WidgetTester tester, MarketOverviewState s) async {
    widenViewport(tester);
    await tester.pumpWidget(
      buildProviderTestApp(MarketDashboard(state: s), zhTranslations: true),
    );
    // 載入翻譯後會重建、進場動畫各掛一個計時器：等畫面穩定，避免測試結束時
    // 仍有 Timer 未完成
    await tester.pumpAndSettle();
  }

  HeroIndexSection heroOf(WidgetTester tester, String name) => tester
      .widgetList<HeroIndexSection>(find.byType(HeroIndexSection))
      .firstWhere((h) => h.index.name == name);

  // 證交所約 14:00 公布今天收盤 → 指數是今天；Hero 下面各區要等每日更新
  testWidgets('🚨 Hero 指數比盤後資料新 → 狀態列「指數為 M/D 收盤」', (tester) async {
    await pump(
      tester,
      state(indices: [index(MarketIndexNames.taiex, DateTime(2026, 2, 16))]),
    );
    expect(heroOf(tester, MarketIndexNames.taiex).statusText, '指數為 2/16 收盤');
  });

  testWidgets('Hero 指數與盤後資料同一天 → 不標', (tester) async {
    await pump(
      tester,
      state(indices: [index(MarketIndexNames.taiex, DateTime(2026, 2, 13))]),
    );
    expect(heroOf(tester, MarketIndexNames.taiex).statusText, isNull);
  });

  // 上櫃行情斷線那天：dataDate 是今天，上櫃家數、成交額退回前一天
  testWidgets('🚨 上櫃盤後資料退回前一天 → 上櫃 Hero 標指數是哪天的收盤、上市不標', (tester) async {
    await pump(
      tester,
      state(
        indices: [
          index(MarketIndexNames.taiex, DateTime(2026, 2, 13)),
          index(MarketIndexNames.tpexIndex, DateTime(2026, 2, 13)),
        ],
        stale: {MarketCode.tpex: DateTime(2026, 2, 12)},
      ),
    );
    expect(
      heroOf(tester, MarketIndexNames.tpexIndex).statusText,
      '指數為 2/13 收盤',
    );
    expect(heroOf(tester, MarketIndexNames.taiex).statusText, isNull);
  });
}

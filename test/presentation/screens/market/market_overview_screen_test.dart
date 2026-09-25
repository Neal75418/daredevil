import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/screens/market/market_overview_screen.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';
import 'package:daredevil/presentation/widgets/themed_refresh_indicator.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class _FakeMarket extends MarketOverviewNotifier {
  _FakeMarket(this._initial);
  final MarketOverviewState _initial;
  int loadCalls = 0;

  @override
  MarketOverviewState build() => _initial;

  @override
  Future<void> loadData() async => loadCalls++;
}

const _withData = MarketOverviewState(
  advanceDeclineByMarket: {
    MarketCode.twse: AdvanceDecline(advance: 408, decline: 667, unchanged: 149),
  },
);

void main() {
  setUpAll(() async => setupTestLocalization());

  Future<_FakeMarket> pump(WidgetTester tester, MarketOverviewState s) async {
    // 測試環境 .tr() 回 key 字串（比真實文字長），依 test/CLAUDE.md 慣例
    // 加寬避免儀表板標題列的假溢出
    tester.view.physicalSize = const Size(5000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _FakeMarket(s);
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketOverviewScreen(),
        overrides: [marketOverviewProvider.overrideWith(() => fake)],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return fake;
  }

  testWidgets('有資料 → 渲染完整儀表板，進頁不重新載入', (tester) async {
    final fake = await pump(tester, _withData);
    expect(find.byType(MarketDashboard), findsOneWidget);
    expect(fake.loadCalls, 0);
  });

  testWidgets('下拉重新整理 → loadData', (tester) async {
    final fake = await pump(tester, _withData);
    // RefreshIndicator 要拉過視窗高度的 25%（4000 × 0.25）才觸發
    await tester.fling(
      find.byType(MarketDashboard),
      const Offset(0, 1500),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(fake.loadCalls, 1);
  });

  testWidgets('無資料有錯誤 → 錯誤可重試', (tester) async {
    final fake = await pump(tester, const MarketOverviewState(error: '網路錯誤'));
    expect(find.text('網路錯誤'), findsOneWidget);
    await tester.tap(find.text('common.retry'));
    expect(fake.loadCalls, 1);
  });

  testWidgets('無資料無錯誤 → 空狀態說明', (tester) async {
    await pump(tester, const MarketOverviewState());
    expect(find.text('marketOverview.pageEmpty'), findsOneWidget);
    expect(find.byType(MarketDashboard), findsNothing);
  });

  // 下拉只證明有呼叫 loadData；畫面要跟著 state 重建才看得到新資料
  testWidgets('state 更新後畫面跟著重建', (tester) async {
    final fake = await pump(tester, const MarketOverviewState());
    expect(find.byType(MarketDashboard), findsNothing);

    fake.state = _withData;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(MarketDashboard), findsOneWidget);
  });

  // 沒資料但正在載入：交給儀表板自己的載入卡，不能顯示「尚無大盤資料」
  testWidgets('無資料且載入中 → 載入中，不顯示空狀態', (tester) async {
    await pump(tester, const MarketOverviewState(isLoading: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('marketOverview.pageEmpty'), findsNothing);
  });

  // 與今日頁同一個下拉元件（主題色、觸覺回饋、逾時兜底）
  testWidgets('下拉用 ThemedRefreshIndicator', (tester) async {
    await pump(tester, _withData);
    expect(find.byType(ThemedRefreshIndicator), findsOneWidget);
  });

  // 獨立頁的導覽列已有「大盤總覽」；儀表板卡片原本放在今日頁需要自己的
  // 標題，搬過來後不能再重複一次
  testWidgets('「大盤總覽」只出現在導覽列一次', (tester) async {
    await pump(tester, _withData);
    expect(find.text('marketOverview.title'), findsOneWidget);
  });

  testWidgets('標題列顯示「大盤總覽」', (tester) async {
    await pump(tester, _withData);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('marketOverview.title'),
      ),
      findsOneWidget,
    );
  });
}

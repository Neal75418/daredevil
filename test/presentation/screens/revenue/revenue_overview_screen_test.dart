// 月營收總覽的累計年增欄+低基期防護(2026-08-13 一魚三吃)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/dao/revenue_dao.dart';
import 'package:daredevil/presentation/providers/revenue_overview_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/revenue/revenue_overview_screen.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class FakeRevenueNotifier extends RevenueOverviewNotifier {
  FakeRevenueNotifier(this._initial);
  final RevenueOverviewState _initial;
  @override
  RevenueOverviewState build() => _initial;
  @override
  Future<void> loadData() async {}
}

class FakeWatchlistNotifier extends WatchlistNotifier {
  @override
  WatchlistState build() => WatchlistState();
  @override
  Future<void> loadData() async {}
}

RevenueOverviewRow row(
  String symbol, {
  double? yoy,
  double? ytd,
  bool newHigh = false,
}) => RevenueOverviewRow(
  symbol: symbol,
  name: '測$symbol',
  market: 'TWSE',
  revenue: 580000,
  momGrowth: 12.0,
  yoyGrowth: yoy,
  ytdYoyGrowth: ytd,
  isNewHigh: newHigh,
);

void main() {
  setUpAll(() async => setupTestLocalization());

  Widget app(List<RevenueOverviewRow> rows) => buildProviderTestApp(
    const RevenueOverviewScreen(),
    overrides: [
      revenueOverviewProvider.overrideWith(
        () => FakeRevenueNotifier(
          RevenueOverviewState(
            overview: RevenueOverview(
              year: 2026,
              month: 7,
              rows: rows,
              filedByMarket: const {'TWSE': 2},
            ),
          ),
        ),
      ),
      watchlistProvider.overrideWith(FakeWatchlistNotifier.new),
    ],
  );

  void widen(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('🚨 累計年增欄渲染:標頭+數值', (tester) async {
    widen(tester);
    await tester.pumpWidget(app([row('2330', yoy: 25.0, ytd: 30.5)]));
    await tester.pumpAndSettle();

    expect(find.text('revenueOverview.ytdShort'), findsOneWidget);
    expect(find.text('+30.5%'), findsOneWidget);
  });

  testWidgets('🚨 低基期列:淡化+badge;正常列不受影響', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        row('4113', yoy: 1096390.6, ytd: 48.0), // 低基期
        row('2330', yoy: 25.0, ytd: 30.0),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('revenueOverview.lowBase'), findsOneWidget);
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity);
    expect(opacities.any((o) => o < 0.6), isTrue, reason: '低基期列必須淡化');
  });

  testWidgets('累計缺值 → 顯示 --,不標低基期', (tester) async {
    widen(tester);
    await tester.pumpWidget(app([row('9999', yoy: 500.0, ytd: null)]));
    await tester.pumpAndSettle();

    expect(find.text('revenueOverview.lowBase'), findsNothing);
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('排序含第四選項:累計年增', (tester) async {
    widen(tester);
    await tester.pumpWidget(app([row('2330', yoy: 25.0, ytd: 30.0)]));
    await tester.pumpAndSettle();

    expect(find.text('revenueOverview.sort.ytdYoy'), findsOneWidget);
  });

  testWidgets('🚨 375pt 手機寬:四欄不溢出且股名可見(終審釘 375+正向斷言)', (tester) async {
    // takeException()==null 在「股名被壓成 0 寬」時照樣綠——正向斷言
    // 才守得住「可用」而不只是「不炸」(全套綠≠可用的形狀)
    tester.view.physicalSize = const Size(375, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      app([
        row('4113', yoy: 1096390.6, ytd: 48.0, newHigh: true),
        row('2330', yoy: 25.0, ytd: 30.0),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: '76×3 時代 375 直接 RenderFlex 溢出;加欄前先重算欄寬帳',
    );
    final nameBox = tester.getSize(find.text('2330 測2330'));
    expect(nameBox.width, greaterThan(0), reason: '股名不得被壓成 0 寬');
  });

  testWidgets('🚨 背景條正規化排除低基期怪物:正常列仍有可讀比例', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        row('4113', yoy: 1096390.6, ytd: 48.0), // 怪物:夾滿條
        row('2330', yoy: 25.0, ytd: 30.0),
        row('3231', yoy: 50.0, ytd: 45.0),
      ]),
    );
    await tester.pumpAndSettle();

    final fractions = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((b) => b.widthFactor)
        .whereType<double>()
        .toList();
    // 年增欄:怪物 clamp=1.0;3231=50/50=1.0(非低基期最大);2330=25/50=0.5
    // 若怪物參與正規化,2330/3231 會是 0.000023/0.000046——條全趴地
    expect(
      fractions.where((f) => f > 0.4 && f < 0.6),
      isNotEmpty,
      reason: '正常列的比例必須可讀,不得被怪物壓扁',
    );
  });
}

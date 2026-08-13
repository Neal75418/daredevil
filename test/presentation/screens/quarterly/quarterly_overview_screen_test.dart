// 季報總覽:淨利率欄+EPS 年增背景條(2026-08-13)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/dao/quarterly_report_dao.dart';
import 'package:daredevil/presentation/providers/quarterly_report_overview_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/quarterly/quarterly_report_overview_screen.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class FakeQuarterlyNotifier extends QuarterlyReportOverviewNotifier {
  FakeQuarterlyNotifier(this._initial);
  final QuarterlyReportOverviewState _initial;
  @override
  QuarterlyReportOverviewState build() => _initial;
  @override
  Future<void> loadData() async {}
}

class FakeWatchlistNotifier extends WatchlistNotifier {
  @override
  WatchlistState build() => WatchlistState();
  @override
  Future<void> loadData() async {}
}

QuarterlyReportOverviewRow row(
  String symbol, {
  double? eps,
  double? net,
  double? rev,
  double? prior,
}) => QuarterlyReportOverviewRow(
  symbol: symbol,
  name: '測$symbol',
  market: 'TWSE',
  eps: eps,
  netIncome: net,
  revenue: rev,
  priorEps: prior,
);

void main() {
  setUpAll(() async => setupTestLocalization());

  void widen(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget app(List<QuarterlyReportOverviewRow> rows) => buildProviderTestApp(
    const QuarterlyReportOverviewScreen(),
    overrides: [
      quarterlyReportOverviewProvider.overrideWith(
        () => FakeQuarterlyNotifier(
          QuarterlyReportOverviewState(
            overview: QuarterlyReportOverview(
              year: 2026,
              quarter: 2,
              rows: rows,
              filedByMarket: const {'TWSE': 2},
            ),
          ),
        ),
      ),
      watchlistProvider.overrideWith(FakeWatchlistNotifier.new),
    ],
  );

  testWidgets('🚨 淨利率欄:標頭+數值(宜鼎 44.6%)', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([row('5289', eps: 166.45, net: 15883392, rev: 35626019, prior: 5.7)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('quarterlyOverview.marginCol'), findsOneWidget);
    expect(find.text('44.6%'), findsOneWidget);
  });

  testWidgets('🚨 EPS 年增欄有背景條,比例=差值/可見最大差值', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        row(
          '5289',
          eps: 166.45,
          net: 100,
          rev: 1000,
          prior: 5.7,
        ), // Δ160.75(滿條)
        row('2059', eps: 110.96, net: 100, rev: 1000, prior: 30.6), // Δ80.36
      ]),
    );
    await tester.pumpAndSettle();

    final boxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((b) => b.widthFactor)
        .whereType<double>()
        .toList();
    expect(boxes, hasLength(2));
    expect(boxes.reduce((a, b) => a > b ? a : b), closeTo(1.0, 1e-6));
    expect(
      boxes.reduce((a, b) => a < b ? a : b),
      closeTo(80.36 / 160.75, 0.001),
    );
  });

  testWidgets('淨利率缺值 → --,不炸', (tester) async {
    widen(tester);
    await tester.pumpWidget(app([row('9999', eps: 1.0, prior: 0.5)]));
    await tester.pumpAndSettle();
    expect(find.text('--'), findsWidgets);
  });
}

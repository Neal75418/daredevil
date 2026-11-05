import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_industry_group_sheet.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_mine_mark.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

HeatmapIndustry _industry(
  String? name,
  double cap,
  double? pct, {
  int stocks = 2,
  bool mine = false,
}) => HeatmapIndustry(
  name: name,
  marketCap: cap,
  weightedChangePercent: pct,
  tiles: [
    for (var i = 0; i < stocks; i++)
      HeatmapTile(
        symbol: '990$i',
        name: '測試$i',
        close: 100,
        marketCap: cap / stocks,
        change: pct == null
            ? const TileChangeHollow(HollowReason.noChangeData)
            : TileChangeValue(pct),
        isMine: mine && i == 0,
      ),
  ],
);

const HeatmapBox _box = (left: 0, top: 0, width: 100, height: 100);

HeatmapIndustryGroupLayout _group(List<HeatmapIndustry> members) =>
    HeatmapIndustryGroupLayout(
      members: members,
      bounds: _box,
      paint: _box,
      interactive: true,
      marketCap: members.fold(0.0, (a, i) => a + i.marketCap),
      weightedChangePercent: 0.5,
      breadth: (up: 4, down: 2, flat: 0, hollow: 2),
    );

final _members = [
  _industry('甲業', 4e8, 1),
  _industry('乙業', 3e8, null),
  _industry('丙業', 2e8, -2),
  _industry('丁業', 1e8, 3),
];

void main() {
  setUpAll(() async => setupTestLocalization());

  Future<void> pump(
    WidgetTester tester,
    HeatmapIndustryGroupLayout group, {
    ValueChanged<String>? onTap,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildProviderTestApp(
        HeatmapIndustryGroupSheet(
          title: '其他 4 個產業',
          group: group,
          onIndustryTap: onTap ?? (_) {},
        ),
        zhTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('標題與摘要：漲跌家數、市值加權漲跌', (tester) async {
    await pump(tester, _group(_members));
    expect(find.text('其他 4 個產業'), findsOneWidget);
    expect(find.text('漲 4、跌 2、平 0、無漲跌資料 2'), findsOneWidget);
    expect(find.text('市值加權 +0.50%'), findsOneWidget);
  });

  testWidgets('每列寫產業名稱、檔數與市值、加權漲跌；全是空心寫無漲跌資料', (tester) async {
    await pump(tester, _group(_members));
    expect(find.text('甲業'), findsOneWidget);
    expect(find.text('共 2 檔 · 市值 4.0 億'), findsOneWidget);
    expect(find.text('+1.00%'), findsOneWidget);
    expect(find.text('-2.00%'), findsOneWidget);
    expect(find.text('無漲跌資料'), findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(ListTile), matching: find.text('-2.00%')),
    );
    expect(text.style?.color, AppTheme.getPriceColor(-2, Brightness.light));
  });

  testWidgets('產業別空白寫「未分類」', (tester) async {
    await pump(
      tester,
      _group([_industry(null, 1e8, 1), _industry('甲業', 1e8, 1)]),
    );
    expect(find.text('未分類'), findsOneWidget);
  });

  testWidgets('含自選或持股的產業排最前面並加標記，其餘依漲跌幅、空心最後', (tester) async {
    await pump(
      tester,
      _group([..._members, _industry('戊業', 5e7, -5, mine: true)]),
    );
    final tops = [
      for (final name in ['戊業', '丁業', '甲業', '丙業', '乙業'])
        tester.getTopLeft(find.text(name)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('戊業'), matching: find.byType(ListTile)),
        matching: find.byType(HeatmapMineMark),
      ),
      findsOneWidget,
    );
    expect(find.byType(HeatmapMineMark), findsOneWidget);
  });

  testWidgets('點一列回呼產業 key', (tester) async {
    String? tapped;
    await pump(tester, _group(_members), onTap: (k) => tapped = k);
    await tester.tap(find.text('丙業'));
    expect(tapped, '丙業');
  });
}

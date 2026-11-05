import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_mine_mark.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_other_sheet.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

HeatmapTile _tile(
  String symbol,
  String name,
  double cap,
  TileChange change, {
  bool mine = false,
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  close: 100,
  marketCap: cap,
  change: change,
  isMine: mine,
);

const HeatmapBox _box = (left: 0, top: 0, width: 100, height: 100);

final _other = HeatmapOtherLayout(
  members: [
    _tile('9974', '測試卯', 4e8, const TileChangeValue(3)),
    _tile(
      '9973',
      '測試寅',
      3e8,
      const TileChangeHollow(HollowReason.noChangeData),
    ),
    _tile('9972', '測試丑', 2e8, const TileChangeValue(-2)),
    _tile('9971', '測試子', 1e8, const TileChangeValue(1)),
  ],
  bounds: _box,
  paint: _box,
  interactive: true,
  wholeIndustry: false,
  marketCap: 1e9,
  weightedChangePercent: 0.5,
  breadth: (up: 2, down: 1, flat: 0, hollow: 1),
);

void main() {
  setUpAll(() async => setupTestLocalization());

  Future<void> pump(WidgetTester tester, {ValueChanged<String>? onTap}) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildProviderTestApp(
        HeatmapOtherSheet(
          title: '半導體業 · 其他 4 檔',
          other: _other,
          onStockTap: onTap ?? (_) {},
        ),
        zhTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('標題與摘要：漲跌家數、市值加權漲跌', (tester) async {
    await pump(tester);
    expect(find.text('半導體業 · 其他 4 檔'), findsOneWidget);
    expect(find.text('漲 2、跌 1、平 0、無漲跌資料 1'), findsOneWidget);
    expect(find.text('市值加權 +0.50%'), findsOneWidget);
  });

  testWidgets('依漲跌幅排序（漲最多在上），沒有漲跌資料的放最後', (tester) async {
    await pump(tester);
    final tops = [
      for (final name in ['測試卯', '測試子', '測試丑', '測試寅'])
        tester.getTopLeft(find.text(name)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('每列寫名稱、代號與市值、漲跌幅；空心寫無漲跌資料', (tester) async {
    await pump(tester);
    expect(find.text('9974 · 市值 4.0 億'), findsOneWidget);
    expect(find.text('+3.00%'), findsOneWidget);
    expect(find.text('-2.00%'), findsOneWidget);
    expect(find.text('無漲跌資料'), findsOneWidget);
  });

  test('排序看顯示的值：四捨五入後相同就依市值', () {
    final sorted = sortHeatmapOtherMembers([
      _tile('9981', '小市值', 1e8, const TileChangeValue(1.004)),
      _tile('9982', '大市值', 9e8, const TileChangeValue(1.001)),
    ]);
    expect(sorted.map((t) => t.symbol), ['9982', '9981']);
  });

  test('自選或持股排最前面（各自依漲跌幅），其餘照舊', () {
    final sorted = sortHeatmapOtherMembers([
      _tile('9981', '漲多', 1e8, const TileChangeValue(5)),
      _tile('9982', '自選跌', 1e8, const TileChangeValue(-3), mine: true),
      _tile(
        '9983',
        '自選空心',
        1e8,
        const TileChangeHollow(HollowReason.noChangeData),
        mine: true,
      ),
      _tile('9984', '自選漲', 1e8, const TileChangeValue(2), mine: true),
      _tile('9985', '跌', 1e8, const TileChangeValue(-1)),
    ]);
    expect(sorted.map((t) => t.symbol), [
      '9984',
      '9982',
      '9983',
      '9981',
      '9985',
    ]);
  });

  testWidgets('自選或持股的列加雙線框標記', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final withMine = HeatmapOtherLayout(
      members: [
        _tile('9991', '測試自選', 2e8, const TileChangeValue(1), mine: true),
        _tile('9992', '測試別檔', 1e8, const TileChangeValue(2)),
      ],
      bounds: _box,
      paint: _box,
      interactive: true,
      wholeIndustry: false,
      marketCap: 3e8,
      weightedChangePercent: 1.3,
      breadth: (up: 2, down: 0, flat: 0, hollow: 0),
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        HeatmapOtherSheet(title: 't', other: withMine, onStockTap: (_) {}),
        zhTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HeatmapMineMark), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('測試自選'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(HeatmapMineMark),
      ),
      findsOneWidget,
    );
    // 清單列合併成一段描述：螢幕閱讀器唸到名稱後接著唸「自選或持股」
    expect(find.bySemanticsLabel(RegExp(r'測試自選\s+自選或持股')), findsOneWidget);
  });

  testWidgets('漲跌幅顏色看顯示的值：0.004% 顯示 0.00%、用平盤色', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tiny = HeatmapOtherLayout(
      members: [_tile('9991', '測試微', 1e8, const TileChangeValue(0.004))],
      bounds: _box,
      paint: _box,
      interactive: true,
      wholeIndustry: false,
      marketCap: 1e8,
      weightedChangePercent: 0.004,
      breadth: (up: 0, down: 0, flat: 1, hollow: 0),
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        HeatmapOtherSheet(title: 't', other: tiny, onStockTap: (_) {}),
        zhTranslations: true,
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(ListTile), matching: find.text('0.00%')),
    );
    expect(text.style?.color, AppTheme.getPriceColor(0, Brightness.light));
  });

  testWidgets('點一列回呼代號', (tester) async {
    String? tapped;
    await pump(tester, onTap: (s) => tapped = s);
    await tester.tap(find.text('測試丑'));
    expect(tapped, '9972');
  });
}

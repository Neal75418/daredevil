import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show OffsetLayer, RenderRepaintBoundary, SemanticsNode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_tooltip.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_view.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

const _width = 800.0;
const _height = 500.0;

HeatmapTile _tile(
  String symbol,
  String name,
  double cap,
  TileChange change, {
  double close = 100,
  bool mine = false,
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  close: close,
  marketCap: cap,
  change: change,
  isMine: mine,
);

final _data = HeatmapMarketData(
  market: 'TWSE',
  dataDate: DateTime(2026, 10, 7),
  excludedForShares: 0,
  industries: [
    HeatmapIndustry(
      name: 'A',
      marketCap: 183450000001,
      weightedChangePercent: 1.834,
      tiles: [
        _tile('9901', '測試甲', 123450000000, const TileChangeValue(1.834)),
        _tile(
          '9902',
          '測試乙',
          60000000000,
          const TileChangeHollow(HollowReason.noChangeData),
        ),
        _tile('9903', '測試丙', 1, const TileChangeValue(1)),
      ],
    ),
    // 只有一檔太小時不合併：9912 排成有面積、邊長不到 4 的細條，不可互動
    HeatmapIndustry(
      name: 'B',
      marketCap: 80500000000,
      weightedChangePercent: -0.4,
      tiles: [
        _tile('9911', '測試丁', 80000000000, const TileChangeValue(-0.4)),
        _tile('9912', '測試戊', 500000000, const TileChangeValue(-0.4)),
      ],
    ),
    // 一檔大的加 30 檔太小的：小的合併成一塊「其他」
    HeatmapIndustry(
      name: 'D',
      marketCap: 13000000000,
      weightedChangePercent: 1,
      tiles: [
        _tile('9961', '測試己', 10000000000, const TileChangeValue(1)),
        for (var i = 0; i < 30; i++)
          _tile('${9970 + i}', '微$i', 100000000, const TileChangeValue(1)),
      ],
    ),
    // 小產業：20 檔都太小，整個產業合成一塊
    HeatmapIndustry(
      name: 'C',
      marketCap: 400000000,
      weightedChangePercent: 0.5,
      tiles: [
        for (var i = 0; i < 20; i++)
          _tile('${9921 + i}', '小$i', 20000000, const TileChangeValue(0.5)),
      ],
    ),
  ],
);

/// 再加一個小產業 E（含一檔自選）：C 與 E 在全市場圖上合成一塊
final _dataSmall = HeatmapMarketData(
  market: 'TWSE',
  dataDate: DateTime(2026, 10, 7),
  excludedForShares: 0,
  industries: [
    ..._data.industries,
    HeatmapIndustry(
      name: 'E',
      marketCap: 300000000,
      weightedChangePercent: -1,
      tiles: [
        _tile('9951', '測試庚', 200000000, const TileChangeValue(-1), mine: true),
        _tile('9952', '測試辛', 100000000, const TileChangeValue(-1)),
      ],
    ),
  ],
);

String _industryLabel(HeatmapIndustryLayout l) => 'industry:${l.industry.key}';
String _tileLabel(HeatmapTileLayout t) => 'tile:${t.tile.symbol}';
String _otherLabel(int count) => 'other:$count';
String _wholeLabel(int count) => 'all:$count';
String _otherSemantics(HeatmapIndustryLayout l, HeatmapOtherLayout o) =>
    'other:${l.industry.key}';
String _groupLabel(int count) => '其他 $count 個產業';
String _groupSemantics(HeatmapIndustryGroupLayout g) =>
    'group:${g.members.length}';

const _labels = HeatmapPaintLabels(
  uncategorized: '未分類',
  industrySemantics: _industryLabel,
  tileSemantics: _tileLabel,
  otherLabel: _otherLabel,
  otherShortLabel: 'oth',
  wholeLabel: _wholeLabel,
  otherSemantics: _otherSemantics,
  groupLabel: _groupLabel,
  groupShortLabel: '其他產業',
  groupSemantics: _groupSemantics,
);

HeatmapView _view({
  String? zoom,
  ValueChanged<String>? onTile,
  ValueChanged<String>? onIndustry,
  HeatmapOtherTap? onOther,
  ValueChanged<HeatmapIndustryGroupLayout>? onGroup,
  HeatmapMarketData? data,
}) => HeatmapView(
  data: data ?? _data,
  zoomIndustryKey: zoom,
  onIndustryTap: onIndustry ?? (_) {},
  onTileTap: onTile ?? (_) {},
  onOtherTap: onOther ?? (_, _) {},
  onSmallIndustriesTap: onGroup ?? (_) {},
  labels: _labels,
);

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    buildProviderTestApp(child, zhTranslations: true, brightness: brightness);

Widget _app({
  String? zoom,
  Brightness brightness = Brightness.light,
  ValueChanged<String>? onTile,
  ValueChanged<String>? onIndustry,
  HeatmapOtherTap? onOther,
  ValueChanged<HeatmapIndustryGroupLayout>? onGroup,
  HeatmapMarketData? data,
  double width = _width,
  double height = _height,
}) => _host(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: _view(
        zoom: zoom,
        onTile: onTile,
        onIndustry: onIndustry,
        onOther: onOther,
        onGroup: onGroup,
        data: data,
      ),
    ),
  ),
  brightness: brightness,
);

/// 與畫面同一份佈局（同樣的資料與圖區大小）
final _layout = layoutHeatmap(_data.industries, width: _width, height: _height);

HeatmapTileLayout _tileOf(String symbol) =>
    _layout.expand((l) => l.tiles).firstWhere((t) => t.tile.symbol == symbol);

Offset _center(WidgetTester tester, HeatmapBox b) =>
    tester.getTopLeft(find.byType(HeatmapView)) +
    Offset(b.left + b.width / 2, b.top + b.height / 2);

Finder get _painterFinder => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is HeatmapPainter,
);

HeatmapPainter _painterOf(WidgetTester tester) =>
    tester.widget<CustomPaint>(_painterFinder).painter! as HeatmapPainter;

/// painter 產生的無障礙節點沒有對應的 widget，find.bySemanticsLabel 找不到：
/// 從熱力圖的 CustomPaint 往下走訪收集標籤
List<String> _semanticLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(_painterFinder));
  return labels;
}

Future<TestGesture> _hover(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(at);
  await tester.pump();
  return gesture;
}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void bigViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(2000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('點格子回呼代號', (tester) async {
    bigViewport(tester);
    String? tapped;
    await tester.pumpWidget(_app(onTile: (s) => tapped = s));
    await tester.pumpAndSettle();
    await tester.tapAt(_center(tester, _tileOf('9901').paint));
    expect(tapped, '9901');
  });

  testWidgets('點零面積的小格沒有回呼', (tester) async {
    bigViewport(tester);
    final tiny = _tileOf('9903');
    expect(tiny.interactive, isFalse);
    String? tapped;
    String? industry;
    await tester.pumpWidget(
      _app(onTile: (s) => tapped = s, onIndustry: (k) => industry = k),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(_center(tester, tiny.bounds));
    expect(tapped, isNull);
    expect(industry, isNull);
  });

  testWidgets('點有面積但邊長不到 4 的格子（不可互動）沒有回呼', (tester) async {
    bigViewport(tester);
    final small = _layout
        .expand((l) => l.tiles)
        .firstWhere(
          (t) => !t.interactive && t.paint.width > 0 && t.paint.height > 0,
        );
    expect(
      small.paint.width < 4 || small.paint.height < 4,
      isTrue,
      reason: '前提：格子有面積、邊長不到 4',
    );
    String? tapped;
    String? industry;
    await tester.pumpWidget(
      _app(onTile: (s) => tapped = s, onIndustry: (k) => industry = k),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(_center(tester, small.paint));
    expect(tapped, isNull);
    expect(industry, isNull);
  });

  testWidgets('點產業標題回呼產業 key', (tester) async {
    bigViewport(tester);
    String? industry;
    await tester.pumpWidget(_app(onIndustry: (k) => industry = k));
    await tester.pumpAndSettle();
    final header = _layout.firstWhere((l) => l.industry.key == 'B').header!;
    await tester.tapAt(_center(tester, header));
    expect(industry, 'B');
  });

  testWidgets('滑鼠移上去顯示提示：名稱、代號、價格、漲跌幅、市值；移出後消失', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final gesture = await _hover(
      tester,
      _center(tester, _tileOf('9901').paint),
    );
    expect(find.text('測試甲'), findsOneWidget);
    expect(find.text('9901 · A'), findsOneWidget);
    expect(find.text('價格 100.00'), findsOneWidget);
    expect(find.text('漲跌幅 +1.83%'), findsOneWidget);
    expect(find.text('市值 1,234.5 億'), findsOneWidget);
    await gesture.moveTo(const Offset(1900, 1300));
    await tester.pump();
    expect(find.text('測試甲'), findsNothing);
  });

  testWidgets('產業別空白時提示寫「未分類」', (tester) async {
    bigViewport(tester);
    final data = HeatmapMarketData(
      market: 'TWSE',
      dataDate: DateTime(2026, 10, 7),
      excludedForShares: 0,
      industries: [
        HeatmapIndustry(
          name: null,
          marketCap: 100,
          weightedChangePercent: 1,
          tiles: [_tile('9981', '測試庚', 100, const TileChangeValue(1))],
        ),
      ],
    );
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _width,
            height: _height,
            child: HeatmapView(
              data: data,
              zoomIndustryKey: null,
              onIndustryTap: (_) {},
              onTileTap: (_) {},
              onOtherTap: (_, _) {},
              onSmallIndustriesTap: (_) {},
              labels: _labels,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _hover(tester, const Offset(_width / 2, _height / 2));
    expect(find.text('9981 · 未分類'), findsOneWidget);
  });

  testWidgets('滑鼠移到合併塊：提示寫檔數、產業、漲跌家數與加權漲跌', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final other = _layout.firstWhere((l) => l.industry.key == 'D').other!;
    expect(other.members, hasLength(30), reason: '前提：30 檔被合併');
    await _hover(tester, _center(tester, other.paint));
    expect(find.text('other:30'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('漲 30、跌 0、平 0'), findsOneWidget);
    expect(find.text('市值加權 +1.00%'), findsOneWidget);
    expect(find.text('市值 30.0 億'), findsOneWidget);
  });

  group('合併塊提示', () {
    HeatmapOtherLayout other({
      bool whole = false,
      double? pct = 1,
      HeatmapBreadth breadth = (up: 2, down: 1, flat: 0, hollow: 1),
      int mine = 0,
    }) => HeatmapOtherLayout(
      members: [
        for (var i = 0; i < 4; i++)
          _tile(
            '${9990 + i}',
            '微$i',
            1e8,
            const TileChangeValue(1),
            mine: i < mine,
          ),
      ],
      bounds: (left: 0, top: 0, width: 100, height: 100),
      paint: (left: 0, top: 0, width: 100, height: 100),
      interactive: true,
      wholeIndustry: whole,
      marketCap: 4e8,
      weightedChangePercent: pct,
      breadth: breadth,
    );

    Future<void> pumpTooltip(WidgetTester tester, Widget tooltip) async {
      await tester.pumpWidget(_host(Center(child: tooltip)));
      await tester.pumpAndSettle();
    }

    testWidgets('有空心成員：家數多寫無漲跌資料的檔數', (tester) async {
      await pumpTooltip(
        tester,
        HeatmapOtherTooltip(other: other(), title: '其他 4 檔', industryName: 'D'),
      );
      expect(find.text('其他 4 檔'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('漲 2、跌 1、平 0、無漲跌資料 1'), findsOneWidget);
      expect(find.text('市值 4.0 億'), findsOneWidget);
      expect(find.textContaining('自選'), findsNothing);
    });

    testWidgets('成員有自選或持股：寫含幾檔', (tester) async {
      await pumpTooltip(
        tester,
        HeatmapOtherTooltip(
          other: other(mine: 2),
          title: '其他 4 檔',
          industryName: 'D',
        ),
      );
      expect(find.text('含自選或持股 2 檔'), findsOneWidget);
    });

    testWidgets('整個產業都合併：第二行寫檔數', (tester) async {
      await pumpTooltip(
        tester,
        HeatmapOtherTooltip(
          other: other(whole: true),
          title: 'D',
          industryName: 'D',
        ),
      );
      expect(find.text('共 4 檔'), findsOneWidget);
    });

    testWidgets('成員全是空心：加權漲跌寫無漲跌資料', (tester) async {
      await pumpTooltip(
        tester,
        HeatmapOtherTooltip(
          other: other(
            pct: null,
            breadth: (up: 0, down: 0, flat: 0, hollow: 4),
          ),
          title: '其他 4 檔',
          industryName: 'D',
        ),
      );
      expect(find.text('市值加權 無漲跌資料'), findsOneWidget);
    });
  });

  group('小產業合併塊', () {
    final market = layoutHeatmapMarket(
      _dataSmall.industries,
      width: _width,
      height: _height,
    );

    testWidgets('全市場：放不下標題列的小產業合成一塊交給 painter；放大後沒有', (tester) async {
      bigViewport(tester);
      await tester.pumpWidget(_app(data: _dataSmall));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).smallIndustries?.members.map((i) => i.key), [
        'C',
        'E',
      ]);
      expect(_painterOf(tester).layout.map((l) => l.industry.key), [
        'A',
        'B',
        'D',
      ]);
      await tester.pumpWidget(_app(data: _dataSmall, zoom: 'A'));
      await tester.pumpAndSettle();
      expect(_painterOf(tester).smallIndustries, isNull);
    });

    testWidgets('點合併塊交給回呼，不放大、不進個股', (tester) async {
      bigViewport(tester);
      HeatmapIndustryGroupLayout? group;
      String? industry;
      String? tapped;
      await tester.pumpWidget(
        _app(
          data: _dataSmall,
          onGroup: (g) => group = g,
          onIndustry: (k) => industry = k,
          onTile: (s) => tapped = s,
        ),
      );
      await tester.pumpAndSettle();
      expect(market.smallIndustries!.interactive, isTrue, reason: '前提');
      await tester.tapAt(_center(tester, market.smallIndustries!.paint));
      expect(group?.members.map((i) => i.key), ['C', 'E']);
      expect(industry, isNull);
      expect(tapped, isNull);
    });

    testWidgets('滑鼠移到合併塊：提示寫「其他 N 個產業」、檔數、含自選、家數', (tester) async {
      bigViewport(tester);
      await tester.pumpWidget(_app(data: _dataSmall));
      await tester.pumpAndSettle();
      await _hover(tester, _center(tester, market.smallIndustries!.paint));
      expect(find.text('其他 2 個產業'), findsOneWidget);
      expect(find.text('共 22 檔'), findsOneWidget);
      expect(find.text('含自選或持股 1 檔'), findsOneWidget);
      expect(find.text('漲 20、跌 2、平 0'), findsOneWidget);
      expect(find.text('市值 7.0 億'), findsOneWidget);
    });
  });

  testWidgets('點「其他 N 檔」交給合併塊的回呼（列出成員），不放大', (tester) async {
    bigViewport(tester);
    String? industry;
    String? tapped;
    (HeatmapIndustryLayout, HeatmapOtherLayout)? other;
    await tester.pumpWidget(
      _app(
        onIndustry: (k) => industry = k,
        onTile: (s) => tapped = s,
        onOther: (i, o) => other = (i, o),
      ),
    );
    await tester.pumpAndSettle();
    final d = _layout.firstWhere((l) => l.industry.key == 'D');
    await tester.tapAt(_center(tester, d.other!.paint));
    expect(other?.$1.industry.key, 'D');
    expect(other?.$2.members, hasLength(30));
    expect(industry, isNull);
    expect(tapped, isNull);
  });

  testWidgets('已放大時點整個產業合成的那塊：列出成員（不再放大同一個產業）', (tester) async {
    bigViewport(tester);
    // 500 檔等值：放大後每檔預期面積約 800 px²，仍整個合成一塊
    final data = HeatmapMarketData(
      market: 'TWSE',
      dataDate: DateTime(2026, 10, 7),
      excludedForShares: 0,
      industries: [
        HeatmapIndustry(
          name: 'E',
          marketCap: 500,
          weightedChangePercent: 1,
          tiles: [
            for (var i = 0; i < 500; i++)
              _tile('${1000 + i}', '小$i', 1, const TileChangeValue(1)),
          ],
        ),
      ],
    );
    final e = layoutHeatmap(
      data.industries,
      width: _width,
      height: _height,
    ).single;
    expect(e.other?.wholeIndustry, isTrue, reason: '前提：放大後仍整個合成一塊');
    String? industry;
    var otherCalls = 0;
    await tester.pumpWidget(
      _app(
        data: data,
        zoom: 'E',
        onIndustry: (k) => industry = k,
        onOther: (_, _) => otherCalls++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(_center(tester, e.other!.paint));
    expect(otherCalls, 1);
    expect(industry, isNull);
  });

  testWidgets('點整個產業合成的那塊：放大到該產業', (tester) async {
    bigViewport(tester);
    // 一檔大股的產業加上一個十檔都很小的產業：後者整個合成一塊
    final data = HeatmapMarketData(
      market: 'TWSE',
      dataDate: DateTime(2026, 10, 7),
      excludedForShares: 0,
      industries: [
        HeatmapIndustry(
          name: 'A',
          marketCap: 1e6,
          weightedChangePercent: 1,
          tiles: [_tile('9901', '測試甲', 1e6, const TileChangeValue(1))],
        ),
        HeatmapIndustry(
          name: 'E',
          marketCap: 3e4,
          weightedChangePercent: 1,
          tiles: [
            for (var i = 0; i < 10; i++)
              _tile('${9981 + i}', '小$i', 3e3, const TileChangeValue(1)),
          ],
        ),
      ],
    );
    final e = layoutHeatmap(
      data.industries,
      width: _width,
      height: _height,
    ).firstWhere((l) => l.industry.key == 'E');
    expect(e.other?.wholeIndustry, isTrue, reason: '前提：整個產業合成一塊');
    expect(e.other!.interactive, isTrue);
    String? industry;
    var otherCalls = 0;
    await tester.pumpWidget(
      _app(
        data: data,
        onIndustry: (k) => industry = k,
        onOther: (_, _) => otherCalls++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(_center(tester, e.other!.paint));
    expect(industry, 'E');
    expect(otherCalls, 0);
  });

  testWidgets('空心格子的提示寫原因', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _hover(tester, _center(tester, _tileOf('9902').paint));
    expect(find.text('測試乙'), findsOneWidget);
    expect(find.text('漲跌幅 無漲跌資料'), findsOneWidget);
  });

  testWidgets('長按顯示提示、按住移動換格子、放開就收', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      _center(tester, _tileOf('9911').paint),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text('測試丁'), findsOneWidget);
    expect(find.text('漲跌幅 -0.40%'), findsOneWidget);

    await gesture.moveTo(_center(tester, _tileOf('9901').paint));
    await tester.pump();
    expect(find.text('測試甲'), findsOneWidget);
    expect(find.text('測試丁'), findsNothing);

    await gesture.up();
    await tester.pump();
    expect(find.text('測試甲'), findsNothing);
  });

  testWidgets('長按中指標被取消時收起提示', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      _center(tester, _tileOf('9911').paint),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text('測試丁'), findsOneWidget);
    await gesture.cancel();
    await tester.pump();
    expect(find.text('測試丁'), findsNothing);
  });

  testWidgets('滑鼠移動不重建 CustomPaint', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final before = _painterOf(tester);
    await _hover(tester, _center(tester, _tileOf('9901').paint));
    expect(identical(_painterOf(tester), before), isTrue);
  });

  testWidgets('滑鼠在圖上移動：熱力圖那層不重畫（只有提示層更新）', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // 熱力圖外層的 RepaintBoundary：重畫時會錄一張新的圖層（沿用時是同一個）
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(of: _painterFinder, matching: find.byType(RepaintBoundary))
          .first,
    );
    Object? picture() => (boundary.debugLayer! as OffsetLayer).firstChild;
    final before = picture();
    expect(before, isNotNull);

    final gesture = await _hover(
      tester,
      _center(tester, _tileOf('9901').paint),
    );
    for (final symbol in ['9911', '9902', '9901']) {
      await gesture.moveTo(_center(tester, _tileOf(symbol).paint));
      await tester.pump();
    }
    // 前提：提示確實跟著換了
    expect(find.text('測試甲'), findsOneWidget);
    expect(identical(picture(), before), isTrue);
  });

  testWidgets('同樣資料重新 build：沿用同一份佈局，painter 不要求重畫', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final before = _painterOf(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    final after = _painterOf(tester);
    expect(identical(after.layout, before.layout), isTrue);
    expect(after.shouldRepaint(before), isFalse);
    expect(after.shouldRebuildSemantics(before), isFalse);
  });

  testWidgets('圖上文字用 App 主題的字族', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final font = Theme.of(
      tester.element(find.byType(HeatmapView)),
    ).textTheme.bodyMedium!;
    expect(font.fontFamily, isNotNull, reason: '前提：測試主題有字族');
    expect(_painterOf(tester).fontFamily, font.fontFamily);
    expect(_painterOf(tester).fontFamilyFallback, font.fontFamilyFallback);
  });

  testWidgets('主題切換後提示仍在、painter 改用深色', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _hover(tester, _center(tester, _tileOf('9901').paint));
    expect(_painterOf(tester).brightness, Brightness.light);
    await tester.pumpWidget(_app(brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(_painterOf(tester).brightness, Brightness.dark);
    expect(find.text('測試甲'), findsOneWidget);
  });

  testWidgets('佈局換了（放大）時舊提示消失、不拋錯', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _hover(tester, _center(tester, _tileOf('9901').paint));
    expect(find.text('測試甲'), findsOneWidget);
    await tester.pumpWidget(_app(zoom: 'B'));
    await tester.pump();
    expect(find.text('測試甲'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('極小圖區不拋錯', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app(width: 10, height: 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('高度 0 不拋錯、沒有格子', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app(height: 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_painterOf(tester).layout, isEmpty);
  });

  testWidgets('寬鬆 constraints 下撐滿可用的最大尺寸、點得到格子', (tester) async {
    bigViewport(tester);
    String? tapped;
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _width,
              maxHeight: _height,
            ),
            child: _view(onTile: (s) => tapped = s),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(HeatmapView)),
      const Size(_width, _height),
    );
    await tester.tapAt(_center(tester, _tileOf('9901').paint));
    expect(tapped, '9901');
  });

  testWidgets('Column 預設置中（寬度寬鬆）時也撐滿寬度', (tester) async {
    bigViewport(tester);
    String? tapped;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const SizedBox(height: 20),
            SizedBox(
              height: _height,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _width),
                child: _view(onTile: (s) => tapped = s),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(HeatmapView)),
      const Size(_width, _height),
    );
    await tester.tapAt(_center(tester, _tileOf('9901').paint));
    expect(tapped, '9901');
  });

  testWidgets('高度無上限（捲動容器內）不拋錯、不畫', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_host(SingleChildScrollView(child: _view())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_painterFinder, findsNothing);
  });

  testWidgets('放大後只畫該產業：無障礙節點變成該產業的格子', (tester) async {
    bigViewport(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(_semanticLabels(tester), [
      'industry:A',
      'industry:B',
      'industry:D',
      'industry:C',
    ]);

    await tester.pumpWidget(_app(zoom: 'A'));
    await tester.pumpAndSettle();
    // 9903 太小、不可互動：沒有節點
    expect(_semanticLabels(tester), ['tile:9901', 'tile:9902']);
    handle.dispose();
  });

  testWidgets('手勢層不產生沒有名稱的可點擊無障礙節點', (tester) async {
    bigViewport(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(
      find.semantics.byPredicate(
        (n) =>
            n.label.isEmpty &&
            (n.getSemanticsData().hasAction(SemanticsAction.tap) ||
                n.getSemanticsData().hasAction(SemanticsAction.longPress)),
      ),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('無障礙啟用產業節點回呼產業 key', (tester) async {
    bigViewport(tester);
    final handle = tester.ensureSemantics();
    String? industry;
    await tester.pumpWidget(_app(onIndustry: (k) => industry = k));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('industry:B'));
    expect(industry, 'B');
    handle.dispose();
  });

  testWidgets('放大時無障礙啟用格子節點回呼代號', (tester) async {
    bigViewport(tester);
    final handle = tester.ensureSemantics();
    String? tapped;
    await tester.pumpWidget(_app(zoom: 'A', onTile: (s) => tapped = s));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('tile:9902'));
    expect(tapped, '9902');
    handle.dispose();
  });
}

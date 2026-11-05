import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show OffsetLayer, RenderRepaintBoundary, SemanticsNode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
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
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  close: close,
  marketCap: cap,
  change: change,
  isMine: false,
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
    HeatmapIndustry(
      name: 'B',
      marketCap: 80000000000,
      weightedChangePercent: -0.4,
      tiles: [_tile('9911', '測試丁', 80000000000, const TileChangeValue(-0.4))],
    ),
    // 小產業：格子有面積但邊長不到 4，不可互動
    HeatmapIndustry(
      name: 'C',
      marketCap: 1200000000,
      weightedChangePercent: 0.5,
      tiles: [
        for (var i = 0; i < 20; i++)
          _tile('${9921 + i}', '小$i', 60000000, const TileChangeValue(0.5)),
      ],
    ),
  ],
);

String _industryLabel(HeatmapIndustryLayout l) => 'industry:${l.industry.key}';
String _tileLabel(HeatmapTileLayout t) => 'tile:${t.tile.symbol}';

const _labels = HeatmapPaintLabels(
  uncategorized: '未分類',
  industrySemantics: _industryLabel,
  tileSemantics: _tileLabel,
);

HeatmapView _view({
  String? zoom,
  ValueChanged<String>? onTile,
  ValueChanged<String>? onIndustry,
}) => HeatmapView(
  data: _data,
  zoomIndustryKey: zoom,
  onIndustryTap: onIndustry ?? (_) {},
  onTileTap: onTile ?? (_) {},
  labels: _labels,
);

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    buildProviderTestApp(child, zhTranslations: true, brightness: brightness);

Widget _app({
  String? zoom,
  Brightness brightness = Brightness.light,
  ValueChanged<String>? onTile,
  ValueChanged<String>? onIndustry,
  double width = _width,
  double height = _height,
}) => _host(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: _view(zoom: zoom, onTile: onTile, onIndustry: onIndustry),
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
    expect(_semanticLabels(tester), ['industry:A', 'industry:B', 'industry:C']);

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

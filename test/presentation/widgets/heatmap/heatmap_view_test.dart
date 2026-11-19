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
  String? industry = '半導體業',
  double close = 100,
  bool mine = false,
}) => HeatmapTile(
  symbol: symbol,
  name: name,
  industry: industry,
  close: close,
  marketCap: cap,
  change: change,
  isMine: mine,
);

HeatmapMarketData _market(
  List<HeatmapTile> tiles, {
  HeatmapLiveMode? liveMode,
}) => HeatmapMarketData(
  market: 'TWSE',
  dataDate: DateTime(2026, 10, 7),
  tiles: tiles,
  capCoverage: 0.74,
  excludedForShares: 0,
  liveMode: liveMode,
);

/// 市值降冪：9901 最大；9902 空心；9912 沒有產業別；9903 小到沒有面積
final _data = _market([
  _tile('9901', '測試甲', 123450000000, const TileChangeValue(1.834)),
  _tile(
    '9902',
    '測試乙',
    60000000000,
    const TileChangeHollow(HollowReason.noChangeData),
  ),
  _tile(
    '9911',
    '測試丁',
    50000000000,
    const TileChangeValue(-0.4),
    industry: '航運業',
  ),
  _tile('9912', '測試戊', 30000000000, const TileChangeValue(0), industry: null),
  _tile('9903', '測試丙', 1, const TileChangeValue(1)),
]);

String _tileLabel(HeatmapTileLayout t) => 'tile:${t.tile.symbol}';

const _labels = HeatmapPaintLabels(
  locale: Locale('zh', 'TW'),
  tileSemantics: _tileLabel,
);

HeatmapView _view({ValueChanged<String>? onTile, HeatmapMarketData? data}) =>
    HeatmapView(
      data: data ?? _data,
      onTileTap: onTile ?? (_) {},
      labels: _labels,
      uncategorizedLabel: '未分類',
    );

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    buildProviderTestApp(child, zhTranslations: true, brightness: brightness);

Widget _app({
  Brightness brightness = Brightness.light,
  ValueChanged<String>? onTile,
  HeatmapMarketData? data,
  double width = _width,
  double height = _height,
}) => _host(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: _view(onTile: onTile, data: data),
    ),
  ),
  brightness: brightness,
);

/// 與畫面同一份佈局（同樣的資料與圖區大小）
final _layout = layoutHeatmapTiles(_data.tiles, width: _width, height: _height);

HeatmapTileLayout _tileOf(String symbol) =>
    _layout.firstWhere((t) => t.tile.symbol == symbol);

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

  testWidgets('🚨 點格子之間的間隔沒有回呼', (tester) async {
    bigViewport(tester);
    // 9901 靠圖區內側的那一條邊正好在兩格中間的間隔上
    final b = _tileOf('9901').bounds;
    final onRightEdge = b.left + b.width < _width - 1;
    final gap = onRightEdge
        ? Offset(b.left + b.width, b.top + b.height / 2)
        : Offset(b.left + b.width / 2, b.top + b.height);
    expect(
      onRightEdge || b.top + b.height < _height - 1,
      isTrue,
      reason: '前提：9901 沒有佔滿整張圖',
    );
    String? tapped;
    await tester.pumpWidget(_app(onTile: (s) => tapped = s));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(find.byType(HeatmapView)) + gap);
    expect(tapped, isNull);
  });

  testWidgets('🚨 點畫得出來、但短邊不到 4 的格子（不互動）沒有回呼', (tester) async {
    bigViewport(tester);
    // 甲 60%、乙 39.84%、丙 0.16%：丙是一條 320×2 的細條
    final data = _market([
      _tile('9901', '測試甲', 6000, const TileChangeValue(1)),
      _tile('9902', '測試乙', 3984, const TileChangeValue(1)),
      _tile('9903', '測試丙', 16, const TileChangeValue(1)),
    ]);
    final thin = layoutHeatmapTiles(
      data.tiles,
      width: _width,
      height: _height,
    ).last;
    expect(thin.interactive, isFalse, reason: '前提');
    expect(
      thin.paint.width > 0 && thin.paint.height > 0,
      isTrue,
      reason: '前提：畫得出來、點得到它的範圍（${thin.paint}）',
    );
    String? tapped;
    await tester.pumpWidget(_app(data: data, onTile: (s) => tapped = s));
    await tester.pumpAndSettle();
    await tester.tapAt(_center(tester, thin.paint));
    expect(tapped, isNull);
  });

  testWidgets('滑鼠移上去顯示提示：名稱、代號與產業、價格、漲跌幅、市值；移出後消失', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final gesture = await _hover(
      tester,
      _center(tester, _tileOf('9901').paint),
    );
    expect(find.text('測試甲'), findsOneWidget);
    expect(find.text('9901 · 半導體業'), findsOneWidget);
    expect(find.text('價格 100.00'), findsOneWidget);
    expect(find.text('漲跌幅 +1.83%'), findsOneWidget);
    expect(find.text('市值 1,234.5 億'), findsOneWidget);
    await gesture.moveTo(const Offset(1900, 1300));
    await tester.pump();
    expect(find.text('測試甲'), findsNothing);
  });

  testWidgets('🚨 提示的產業是那一格自己的；產業別空白時寫傳入的「未分類」', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final gesture = await _hover(
      tester,
      _center(tester, _tileOf('9911').paint),
    );
    expect(find.text('9911 · 航運業'), findsOneWidget);
    await gesture.moveTo(_center(tester, _tileOf('9912').paint));
    await tester.pump();
    expect(find.text('9912 · 未分類'), findsOneWidget);
  });

  group('格子提示的空心原因', () {
    Future<void> pumpTile(
      WidgetTester tester,
      TileChange change, {
      HeatmapLiveMode? liveMode,
    }) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: HeatmapTooltip(
              tile: _tile('9901', '測試甲', 1e8, change),
              industryName: 'A',
              dataDate: DateTime(2026, 11, 6),
              liveMode: liveMode,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('盤中未即時：原因之外附正式資料那天的漲跌與日期（ASCII 減號）', (tester) async {
      await pumpTile(
        tester,
        TileChangeHollow(
          HollowReason.notLive,
          previous: (percent: -0.8, date: DateTime(2026, 11, 6)),
        ),
      );
      expect(find.text('漲跌幅 盤中未即時'), findsOneWidget);
      expect(find.text('11/6 收盤 -0.80%'), findsOneWidget);
    });

    for (final (reason, text) in [
      (HollowReason.notLive, '盤中未即時'),
      (HollowReason.noTrade, '尚無成交'),
      (HollowReason.noQuote, '無報價'),
      (HollowReason.noClosingQuote, '尚未取得收盤報價'),
      (HollowReason.noClosingMatch, '收盤沒撮合'),
      (HollowReason.noChangeData, '無漲跌資料'),
    ]) {
      testWidgets('${reason.name}（沒有前一筆）：只寫原因', (tester) async {
        await pumpTile(tester, TileChangeHollow(reason));
        expect(find.text('漲跌幅 $text'), findsOneWidget);
        expect(find.textContaining(RegExp(r'\d+/\d+ ')), findsNothing);
      });
    }

    // 即時模式下空心格子的價格是正式資料那天的收盤，不是現在的價格
    for (final (mode, reason) in [
      (HeatmapLiveMode.intraday, HollowReason.notLive),
      (HeatmapLiveMode.intraday, HollowReason.noTrade),
      (HeatmapLiveMode.afterClose, HollowReason.noClosingQuote),
      (HeatmapLiveMode.afterClose, HollowReason.noClosingMatch),
    ]) {
      testWidgets('${mode.name}、空心（${reason.name}）：價格標「（M/D 收盤）」', (
        tester,
      ) async {
        await pumpTile(tester, TileChangeHollow(reason), liveMode: mode);
        expect(find.text('價格 100.00（11/6 收盤）'), findsOneWidget);
      });
    }

    testWidgets('即時模式有顏色的格子：價格是即時價，不標日期', (tester) async {
      await pumpTile(
        tester,
        const TileChangeValue(1.5),
        liveMode: HeatmapLiveMode.intraday,
      );
      expect(find.text('價格 100.00'), findsOneWidget);
    });

    testWidgets('英文：空心格子的價格接「 (close M/D)」', (tester) async {
      await tester.pumpWidget(
        buildProviderTestApp(
          Center(
            child: HeatmapTooltip(
              tile: _tile(
                '9901',
                '測試甲',
                1e8,
                const TileChangeHollow(HollowReason.notLive),
              ),
              industryName: 'A',
              dataDate: DateTime(2026, 11, 6),
              liveMode: HeatmapLiveMode.intraday,
            ),
          ),
          enTranslations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Price: 100.00 (close 11/6)'), findsOneWidget);
    });

    testWidgets('正式資料的空心格子：不標日期（頁面右側已寫 M/D 收盤）', (tester) async {
      await pumpTile(tester, const TileChangeHollow(HollowReason.noChangeData));
      expect(find.text('價格 100.00'), findsOneWidget);
    });
  });

  testWidgets('空心格子的提示寫原因', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _hover(tester, _center(tester, _tileOf('9902').paint));
    expect(find.text('漲跌幅 無漲跌資料'), findsOneWidget);
  });

  testWidgets('即時套色的資料：空心格子的提示價格標資料日的收盤', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(
      _app(
        data: _market([
          for (final t in _data.tiles)
            t.symbol == '9902'
                ? _tile(
                    '9902',
                    '測試乙',
                    t.marketCap,
                    const TileChangeHollow(HollowReason.notLive),
                  )
                : t,
        ], liveMode: HeatmapLiveMode.intraday),
      ),
    );
    await tester.pumpAndSettle();
    await _hover(tester, _center(tester, _tileOf('9902').paint));
    expect(find.text('價格 100.00（10/7 收盤）'), findsOneWidget);
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

  group('資料換了而滑鼠沒動', () {
    testWidgets('🚨 圖上的檔換人：提示在同一幀改指新版面同一個位置的那一格', (tester) async {
      bigViewport(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _hover(tester, _center(tester, _tileOf('9901').paint));
      expect(find.text('測試甲'), findsOneWidget);
      // 9901 掉出圖上，換成市值一樣大的另一檔：版面相同、那個位置是新的一檔
      final swapped = _market([
        _tile(
          '9931',
          '測試新',
          123450000000,
          const TileChangeValue(-2),
          industry: '光電業',
        ),
        ..._data.tiles.skip(1),
      ]);
      await tester.pumpWidget(_app(data: swapped));
      expect(find.text('測試甲'), findsNothing);
      expect(find.text('測試新'), findsOneWidget);
      expect(find.text('9931 · 光電業'), findsOneWidget);
      await tester.pump();
      expect(find.text('測試新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('🚨 那個位置在新版面沒有格子：提示收起、不拋錯，之後也不自己冒出來', (tester) async {
      bigViewport(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _hover(tester, _center(tester, _tileOf('9901').paint));
      expect(find.byType(HeatmapTooltip), findsOneWidget);
      await tester.pumpWidget(_app(data: _market(const [])));
      expect(find.byType(HeatmapTooltip), findsNothing);
      await tester.pump();
      expect(find.byType(HeatmapTooltip), findsNothing);
      // 收起就是收起：之後換回原本的資料（指標沒動）也不自己冒出舊提示
      await tester.pumpWidget(_app());
      await tester.pump();
      expect(find.byType(HeatmapTooltip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('提示跟著新一輪的即時資料', () {
    /// 9901 換成即時漲跌（面積不變）
    HeatmapMarketData live(double pct) => _market([
      for (final t in _data.tiles)
        t.symbol == '9901'
            ? _tile(
                '9901',
                '測試甲',
                t.marketCap,
                TileChangeValue(pct),
                close: 100 + pct,
              )
            : t,
    ], liveMode: HeatmapLiveMode.intraday);

    testWidgets('滑鼠停在格子上：同一次 pump 就換成新數字，不空白一幀', (tester) async {
      bigViewport(tester);
      await tester.pumpWidget(_app(data: live(3)));
      await tester.pumpAndSettle();
      final gesture = await _hover(
        tester,
        _center(tester, _tileOf('9901').paint),
      );
      expect(find.text('漲跌幅 +3.00%'), findsOneWidget);
      await tester.pumpWidget(_app(data: live(3.5)));
      expect(find.text('漲跌幅 +3.50%'), findsOneWidget);
      expect(find.text('價格 103.50'), findsOneWidget);
      expect(find.text('漲跌幅 +3.00%'), findsNothing);
      // 幀結束後寫回：之後的幀照樣畫新數字，滑鼠移開照樣收起
      await tester.pump();
      expect(find.text('漲跌幅 +3.50%'), findsOneWidget);
      await gesture.moveTo(const Offset(1900, 1300));
      await tester.pump();
      expect(find.byType(HeatmapTooltip), findsNothing);
    });

    testWidgets('長按中換資料：提示仍在、數字換新，放開就收', (tester) async {
      bigViewport(tester);
      await tester.pumpWidget(_app(data: live(3)));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        _center(tester, _tileOf('9901').paint),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(find.text('漲跌幅 +3.00%'), findsOneWidget);
      await tester.pumpWidget(_app(data: live(3.5)));
      expect(find.text('漲跌幅 +3.50%'), findsOneWidget);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(find.byType(HeatmapTooltip), findsNothing);
    });
  });

  testWidgets('🚨 極小圖區（3×2）不拋錯', (tester) async {
    bigViewport(tester);
    await tester.pumpWidget(_app(width: 3, height: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_painterOf(tester).layout, hasLength(_data.tiles.length));
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

  testWidgets('🚨 無障礙節點是每一個可互動的格子', (tester) async {
    bigViewport(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(_semanticLabels(tester), [
      for (final t in _layout)
        if (t.interactive) 'tile:${t.tile.symbol}',
    ]);
    expect(_semanticLabels(tester), isNot(contains('tile:9903')));
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

  testWidgets('無障礙啟用格子節點回呼代號', (tester) async {
    bigViewport(tester);
    final handle = tester.ensureSemantics();
    String? tapped;
    await tester.pumpWidget(_app(onTile: (s) => tapped = s));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('tile:9902'));
    expect(tapped, '9902');
    handle.dispose();
  });
}

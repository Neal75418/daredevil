/// Golden test: MarketHeatmapScreen（虛構資料：市值前 30 檔，含各階、平盤、
/// 空心、自選框）
///
/// 平台相依（字型渲染），只在本機跑；CI 以 --exclude-tags golden 排除。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/market/market_heatmap_screen.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class _FakeHeatmap extends MarketHeatmapNotifier {
  @override
  MarketHeatmapState build() =>
      MarketHeatmapState(isLoading: false, markets: {MarketCode.twse: _data});

  @override
  Future<void> reload() async {}

  @override
  void setVisible(bool visible) {}
}

/// 資料日隔天開盤前：正式資料、不需要即時（盤中跑也畫同一張圖）
class _Clock implements AppClock {
  const _Clock();

  @override
  DateTime now() => DateTime(2026, 3, 11, 8);
}

class _FakeMarket extends MarketOverviewNotifier {
  @override
  MarketOverviewState build() => MarketOverviewState(
    indices: [
      TwseMarketIndex(
        date: DateTime(2026, 3, 10),
        name: MarketIndexNames.taiex,
        close: 22150.3,
        change: -61.2,
        changePercent: -0.28,
      ),
    ],
  );

  @override
  Future<void> loadData() async {}
}

const _hollow = TileChangeHollow(HollowReason.noChangeData);

/// 30 檔的市值（降冪，第一檔特別大）與漲跌：每一階的漲、跌，平盤與空心都有
const _caps = [
  9e11, 3e11, 2e11, 2e11, 1.5e11, 1.5e11, 1.2e11, 1e11, 1e11, 8e10, //
  8e10, 7e10, 6e10, 6e10, 5e10, 5e10, 4e10, 4e10, 4e10, 3e10, //
  3e10, 3e10, 2.5e10, 2.5e10, 2e10, 2e10, 2e10, 1.5e10, 1.5e10, 1e10,
];

const List<TileChange> _changes = [
  TileChangeValue(1.2),
  TileChangeValue(10),
  TileChangeValue(-10),
  TileChangeValue(7),
  TileChangeValue(-7),
  TileChangeValue(4),
  TileChangeValue(-4),
  TileChangeValue(2),
  TileChangeValue(-2),
  TileChangeValue(0.3),
  TileChangeValue(-0.3),
  TileChangeValue(0),
  _hollow,
  TileChangeValue(1),
  TileChangeValue(-1),
];

/// 畫雙線框的名次（一檔有漲跌、一檔空心）
const _mine = {0, 12};

final _data = HeatmapMarketData(
  market: MarketCode.twse,
  dataDate: DateTime(2026, 3, 10),
  capCoverage: 0.74,
  excludedForShares: 3,
  tiles: [
    for (var n = 0; n < _caps.length; n++)
      HeatmapTile(
        symbol: '${9901 + n}',
        name: '測試${n + 1}',
        industry: n.isEven ? '半導體業' : null,
        close: 50 + n * 61.5,
        marketCap: _caps[n],
        change: _changes[n % _changes.length],
        isMine: _mine.contains(n),
      ),
  ],
);

/// 寬度照大盤總覽頁 golden（測試環境 .tr() 回 key 字串，比真實文字長）
void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _build(Brightness brightness) => buildProviderTestApp(
  const MarketHeatmapScreen(),
  overrides: [
    marketHeatmapProvider.overrideWith(_FakeHeatmap.new),
    marketOverviewProvider.overrideWith(_FakeMarket.new),
    appClockProvider.overrideWithValue(const _Clock()),
  ],
  brightness: brightness,
);

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('MarketHeatmapScreen Golden', () {
    testWidgets('熱力圖頁（淺色）', (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_build(Brightness.light));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/market_heatmap_screen_light.png'),
      );
    });

    testWidgets('熱力圖頁（深色）', (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_build(Brightness.dark));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/market_heatmap_screen_dark.png'),
      );
    });
  });
}

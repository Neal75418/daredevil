/// Golden test: MarketHeatmapScreen（虛構資料：3 個產業、20 檔，含各階、
/// 平盤、空心、自選框）
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

HeatmapTile _tile(int n, double cap, TileChange change, {bool mine = false}) =>
    HeatmapTile(
      symbol: '${9900 + n}',
      name: '測試$n',
      close: 100,
      marketCap: cap,
      baseCap: change is TileChangeValue
          ? cap * 100 / (100 + change.percent)
          : 0,
      change: change,
      isMine: mine,
    );

HeatmapIndustry _industry(String name, double? pct, List<HeatmapTile> tiles) =>
    HeatmapIndustry(
      name: name,
      marketCap: tiles.fold(0.0, (s, t) => s + t.marketCap),
      weightedChangePercent: pct,
      tiles: tiles,
    );

final _data = HeatmapMarketData(
  market: MarketCode.twse,
  dataDate: DateTime(2026, 3, 10),
  excludedForShares: 3,
  industries: [
    _industry('半導體業', 1.2, [
      _tile(1, 9e11, const TileChangeValue(1.2), mine: true),
      _tile(2, 2e11, const TileChangeValue(10)),
      _tile(3, 1.5e11, const TileChangeValue(7)),
      _tile(4, 1e11, const TileChangeValue(4)),
      _tile(5, 8e10, const TileChangeValue(2)),
      _tile(6, 6e10, const TileChangeValue(0.3)),
      _tile(7, 4e10, _hollow),
    ]),
    _industry('金融保險業', -0.8, [
      _tile(11, 3e11, const TileChangeValue(-0.8)),
      _tile(12, 2e11, const TileChangeValue(-10)),
      _tile(13, 1.5e11, const TileChangeValue(-7), mine: true),
      _tile(14, 1e11, const TileChangeValue(-4)),
      _tile(15, 7e10, const TileChangeValue(-2)),
      _tile(16, 5e10, const TileChangeValue(-0.3)),
    ]),
    _industry('航運業', 0, [
      _tile(21, 1.2e11, const TileChangeValue(0)),
      _tile(22, 8e10, const TileChangeValue(1)),
      _tile(23, 6e10, _hollow, mine: true),
      _tile(24, 4e10, const TileChangeValue(-1)),
      _tile(25, 3e10, const TileChangeValue(0)),
      _tile(26, 2e10, const TileChangeValue(-0.3)),
      _tile(27, 1e10, const TileChangeValue(0.3)),
    ]),
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

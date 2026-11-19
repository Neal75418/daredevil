import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/heatmap.dart';

HeatmapTile _tile({
  String symbol = '9901',
  String? industry = '測試業',
  TileChange? change,
}) => HeatmapTile(
  symbol: symbol,
  name: '測試甲',
  industry: industry,
  close: 100,
  marketCap: 1000,
  change: change ?? const TileChangeValue(1),
  isMine: false,
);

HeatmapMarketData _data({
  HeatmapLiveMode? liveMode,
  List<HeatmapTile>? tiles,
  double capCoverage = 1,
}) => HeatmapMarketData(
  market: 'twse',
  dataDate: DateTime(2026, 11, 6),
  tiles: tiles ?? [_tile()],
  capCoverage: capCoverage,
  excludedForShares: 0,
  liveMode: liveMode,
);

void _expectDistinct(Object a, Object b) {
  expect(a, isNot(b));
  expect(a.hashCode, isNot(b.hashCode));
}

void _expectSame(Object a, Object b) {
  expect(a, b);
  expect(a.hashCode, b.hashCode);
}

void main() {
  test('HeatmapTile：industry 納入 ==／hashCode', () {
    _expectSame(_tile(), _tile());
    _expectDistinct(_tile(), _tile(industry: '半導體業'));
    _expectDistinct(_tile(), _tile(industry: null));
  });

  group('TileChangeHollow', () {
    test('previous 納入 ==／hashCode', () {
      final a = TileChangeHollow(
        HollowReason.notLive,
        previous: (percent: -0.8, date: DateTime(2026, 11, 6)),
      );
      _expectSame(
        a,
        TileChangeHollow(
          HollowReason.notLive,
          previous: (percent: -0.8, date: DateTime(2026, 11, 6)),
        ),
      );
      _expectDistinct(a, const TileChangeHollow(HollowReason.notLive));
      _expectDistinct(
        a,
        TileChangeHollow(
          HollowReason.notLive,
          previous: (percent: -0.7, date: DateTime(2026, 11, 6)),
        ),
      );
      _expectDistinct(
        a,
        TileChangeHollow(
          HollowReason.notLive,
          previous: (percent: -0.8, date: DateTime(2026, 11, 5)),
        ),
      );
    });

    test('原因不同就不相等；previous 預設 null', () {
      _expectDistinct(
        const TileChangeHollow(HollowReason.noTrade),
        const TileChangeHollow(HollowReason.noQuote),
      );
      expect(const TileChangeHollow(HollowReason.notLive).previous, isNull);
    });
  });

  test('HeatmapMarketData：tiles、capCoverage 納入 ==／hashCode', () {
    _expectSame(_data(), _data());
    _expectDistinct(_data(), _data(capCoverage: 0.5));
    _expectDistinct(_data(), _data(tiles: [_tile(symbol: '9902')]));
    _expectDistinct(
      _data(),
      _data(
        tiles: [
          _tile(),
          _tile(symbol: '9902'),
        ],
      ),
    );
  });

  test('HeatmapMarketData：liveMode 預設 null、納入 ==／hashCode', () {
    expect(_data().liveMode, isNull);
    _expectSame(
      _data(liveMode: HeatmapLiveMode.intraday),
      _data(liveMode: HeatmapLiveMode.intraday),
    );
    _expectDistinct(
      _data(liveMode: HeatmapLiveMode.intraday),
      _data(liveMode: HeatmapLiveMode.afterClose),
    );
    _expectDistinct(_data(), _data(liveMode: HeatmapLiveMode.intraday));
  });
}

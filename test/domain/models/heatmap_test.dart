import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/heatmap.dart';

HeatmapTile _tile({double baseCap = 100, TileChange? change}) => HeatmapTile(
  symbol: '9901',
  name: '測試甲',
  close: 100,
  marketCap: 1000,
  baseCap: baseCap,
  change: change ?? const TileChangeValue(1),
  isMine: false,
);

HeatmapIndustry _industry({double? liveCoverage}) => HeatmapIndustry(
  name: '測試業',
  marketCap: 1000,
  weightedChangePercent: 1,
  tiles: [_tile()],
  liveCoverage: liveCoverage,
);

HeatmapMarketData _data({HeatmapLiveMode? liveMode}) => HeatmapMarketData(
  market: 'twse',
  dataDate: DateTime(2026, 11, 6),
  industries: [_industry()],
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
  test('HeatmapTile：baseCap 納入 ==／hashCode', () {
    _expectSame(_tile(), _tile());
    _expectDistinct(_tile(), _tile(baseCap: 200));
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

  test('HeatmapIndustry：liveCoverage 預設 null、納入 ==／hashCode', () {
    expect(_industry().liveCoverage, isNull);
    _expectSame(_industry(liveCoverage: 0.5), _industry(liveCoverage: 0.5));
    _expectDistinct(_industry(liveCoverage: 0.5), _industry(liveCoverage: 1));
    _expectDistinct(_industry(), _industry(liveCoverage: 0));
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

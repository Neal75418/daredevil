import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// 股數來源的一筆：已發行股數（股）與資料日
typedef HeatmapShares = ({double shares, DateTime date});

/// 一檔股票的已發行股數判定
@immutable
sealed class SharesResolution {
  const SharesResolution();
}

/// 有可用的股數
final class SharesOk extends SharesResolution {
  const SharesOk(this.shares);

  final double shares;

  @override
  bool operator ==(Object other) => other is SharesOk && other.shares == shares;

  @override
  int get hashCode => shares.hashCode;

  @override
  String toString() => 'SharesOk($shares)';
}

/// 沒有可用的股數（不畫，計入頁尾）
final class SharesMissing extends SharesResolution {
  const SharesMissing();

  @override
  bool operator ==(Object other) => other is SharesMissing;

  @override
  int get hashCode => (SharesMissing).hashCode;

  @override
  String toString() => 'SharesMissing()';
}

/// 上櫃兩個來源相差太多（不畫，計入頁尾）
final class SharesInconsistent extends SharesResolution {
  const SharesInconsistent();

  @override
  bool operator ==(Object other) => other is SharesInconsistent;

  @override
  int get hashCode => (SharesInconsistent).hashCode;

  @override
  String toString() => 'SharesInconsistent()';
}

/// 空心格子的原因
enum HollowReason {
  /// 漲跌價差是空值、分母 ≤ 0、或收盤／漲跌／計算結果不是有限數
  noChangeData,
}

/// 一格的當日漲跌：有值，或空心
@immutable
sealed class TileChange {
  const TileChange();
}

final class TileChangeValue extends TileChange {
  const TileChangeValue(this.percent);

  /// 漲跌幅（%），未四捨五入
  final double percent;

  @override
  bool operator ==(Object other) =>
      other is TileChangeValue && other.percent == percent;

  @override
  int get hashCode => percent.hashCode;

  @override
  String toString() => 'TileChangeValue($percent)';
}

final class TileChangeHollow extends TileChange {
  const TileChangeHollow(this.reason);

  final HollowReason reason;

  @override
  bool operator ==(Object other) =>
      other is TileChangeHollow && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'TileChangeHollow($reason)';
}

/// 分組計算的輸入：一檔股票在資料日的價格與兩個股數來源
@immutable
class HeatmapStockInput {
  const HeatmapStockInput({
    required this.symbol,
    required this.name,
    required this.industry,
    required this.close,
    required this.priceChange,
    this.foreign,
    this.insider,
  });

  final String symbol;
  final String name;

  /// 股票主檔的產業別；null 或空字串歸「未分類」
  final String? industry;
  final double close;

  /// `daily_price.price_change`（收盤 − 平盤價）；空值畫空心，不退回前收盤
  final double? priceChange;

  /// 外資持股的已發行股數
  final HeatmapShares? foreign;

  /// 董監持股的已發行股數
  final HeatmapShares? insider;
}

/// 分組計算的輸入：一個市場在資料日的全部股票
@immutable
class HeatmapMarketInput {
  const HeatmapMarketInput({
    required this.market,
    required this.dataDate,
    required this.stocks,
    required this.mine,
  });

  /// `MarketCode.twse`／`MarketCode.tpex`
  final String market;
  final DateTime dataDate;
  final List<HeatmapStockInput> stocks;

  /// 自選∪持股的代號
  final Set<String> mine;
}

/// 一格（一檔股票）
@immutable
class HeatmapTile {
  const HeatmapTile({
    required this.symbol,
    required this.name,
    required this.close,
    required this.marketCap,
    required this.change,
    required this.isMine,
  });

  final String symbol;
  final String name;
  final double close;

  /// 收盤 × 已發行股數（元）
  final double marketCap;
  final TileChange change;

  /// 自選或持股（畫雙線框）
  final bool isMine;

  @override
  bool operator ==(Object other) =>
      other is HeatmapTile &&
      other.symbol == symbol &&
      other.name == name &&
      other.close == close &&
      other.marketCap == marketCap &&
      other.change == change &&
      other.isMine == isMine;

  @override
  int get hashCode =>
      Object.hash(symbol, name, close, marketCap, change, isMine);

  @override
  String toString() =>
      'HeatmapTile($symbol, cap: $marketCap, $change, mine: $isMine)';
}

/// 一個產業區塊
@immutable
class HeatmapIndustry {
  const HeatmapIndustry({
    required this.name,
    required this.marketCap,
    required this.weightedChangePercent,
    required this.tiles,
  });

  /// 產業別；null 是「未分類」
  final String? name;

  /// 成員市值合計
  final double marketCap;

  /// 有漲跌的成員以平盤市值（股數 × 平盤價）加權的漲跌幅（%）；全部空心時為 null
  final double? weightedChangePercent;

  /// 市值降冪、同值依代號升冪
  final List<HeatmapTile> tiles;

  /// 放大、點擊等用的識別值（未分類為空字串）
  String get key => name ?? '';

  @override
  bool operator ==(Object other) =>
      other is HeatmapIndustry &&
      other.name == name &&
      other.marketCap == marketCap &&
      other.weightedChangePercent == weightedChangePercent &&
      const ListEquality<HeatmapTile>().equals(other.tiles, tiles);

  @override
  int get hashCode => Object.hash(
    name,
    marketCap,
    weightedChangePercent,
    const ListEquality<HeatmapTile>().hash(tiles),
  );

  @override
  String toString() =>
      'HeatmapIndustry($key, cap: $marketCap, '
      'weighted: $weightedChangePercent, tiles: $tiles)';
}

/// 一個市場的熱力圖資料
@immutable
class HeatmapMarketData {
  const HeatmapMarketData({
    required this.market,
    required this.dataDate,
    required this.industries,
    required this.excludedForShares,
  });

  final String market;
  final DateTime dataDate;

  /// 市值降冪、同值依 [HeatmapIndustry.key] 升冪
  final List<HeatmapIndustry> industries;

  /// 缺股數或股數不一致而沒畫的檔數（頁尾）
  final int excludedForShares;

  @override
  bool operator ==(Object other) =>
      other is HeatmapMarketData &&
      other.market == market &&
      other.dataDate == dataDate &&
      other.excludedForShares == excludedForShares &&
      const ListEquality<HeatmapIndustry>().equals(
        other.industries,
        industries,
      );

  @override
  int get hashCode => Object.hash(
    market,
    dataDate,
    excludedForShares,
    const ListEquality<HeatmapIndustry>().hash(industries),
  );

  @override
  String toString() =>
      'HeatmapMarketData($market, $dataDate, '
      'excluded: $excludedForShares, industries: $industries)';
}

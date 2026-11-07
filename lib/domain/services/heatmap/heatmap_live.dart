import 'package:collection/collection.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_grouping.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 現在該用哪種即時模式；null 是不需要即時（全部用正式資料）。
///
/// 盤中（[MarketPhase.open]）與收盤後（[MarketPhase.afterClose]）才需要，
/// 而且只在該市場還沒有今天的正式資料時（[dataDate] 不是 [now] 那一天）；
/// 開盤前、休市日、或盤後資料已寫入，都沒有東西要即時。
HeatmapLiveMode? heatmapLiveModeAt({
  required MarketPhase phase,
  required DateTime dataDate,
  required DateTime now,
}) {
  if (DateContext.isSameDay(dataDate, now)) return null;
  return switch (phase) {
    MarketPhase.open => HeatmapLiveMode.intraday,
    MarketPhase.afterClose => HeatmapLiveMode.afterClose,
    MarketPhase.preOpen || MarketPhase.closed => null,
  };
}

/// 熱力圖要向報價中心登記的個股代號，最多 [HeatmapParams.liveTileLimit] 檔，
/// 依市值降冪、同值依代號升冪。
///
/// - [HeatmapLiveMode.intraday]：放大到某個產業（[zoomIndustryKey]）時是該產業
///   的前幾大，否則是全市場的前幾大。放大的產業不在 [official]（重讀後消失）
///   視同沒放大。
/// - [HeatmapLiveMode.afterClose]：全市場還沒有今天收盤報價的股票中的前幾大，
///   放大與否都一樣；拿到的移出、下一檔補進，一輪一輪把整個市場收齊。
///   收盤報價是定值，[entries] 裡哪個畫面抓的都算。
///
/// 純函式。放大時直接取產業內已排好的順序（[HeatmapIndustry.tiles]）。
List<String> heatmapLiveSymbols(
  HeatmapMarketData official, {
  required HeatmapLiveMode mode,
  required String? zoomIndustryKey,
  required Map<String, LiveQuoteEntry> entries,
  required DateTime today,
}) {
  final Iterable<HeatmapTile> candidates;
  switch (mode) {
    case HeatmapLiveMode.intraday:
      final zoomed = zoomIndustryKey == null
          ? null
          : official.industries.firstWhereOrNull(
              (industry) => industry.key == zoomIndustryKey,
            );
      candidates = zoomed?.tiles ?? _tilesByMarketCap(official);
    case HeatmapLiveMode.afterClose:
      candidates = _tilesByMarketCap(official).where((tile) {
        final entry = entries[tile.symbol];
        return entry == null || !isClosingQuoteOfToday(entry, today);
      });
  }
  return [
    for (final tile in candidates.take(HeatmapParams.liveTileLimit))
      tile.symbol,
  ];
}

/// 攤平各產業的格子，重排成市值降冪、同值依代號升冪（產業內已排好，
/// 跨產業要重排）
List<HeatmapTile> _tilesByMarketCap(HeatmapMarketData official) {
  return [for (final industry in official.industries) ...industry.tiles]
    ..sort((a, b) {
      final byCap = b.marketCap.compareTo(a.marketCap);
      return byCap != 0 ? byCap : a.symbol.compareTo(b.symbol);
    });
}

/// 今天的收盤報價：收盤後的登記清單、上色與進度共用這個判準，已取得的才會
/// 一致地移出清單、上色、計入進度
bool isClosingQuoteOfToday(LiveQuoteEntry entry, DateTime today) =>
    entry.isClosingQuote && DateContext.isSameDay(entry.date, today);

/// 把即時報價疊到正式資料上：逐格換漲跌、顯示價與平盤市值，產業的加權漲跌
/// 與即時占比重算。
///
/// 純函式，不碰資料庫。面積（[HeatmapTile.marketCap]）、格子與產業的順序、
/// 頁尾檔數、資料日都維持正式資料；即時只換顏色。
///
/// 漲跌幅＝(即時價 − y) × 100 ÷ y，y 是證交所即時資料的昨收（除權息日是
/// 參考價）。y 不可用時畫空心，不退回資料庫的收盤：除權息日會把股息算成
/// 跌幅。
///
/// - [HeatmapLiveMode.intraday]：只用熱力圖自己登記（[registered]）、登記之後
///   拿到過（[fresh]）、日期是 [today]、有成交或鎖住價的報價；登記之前中心裡
///   別的畫面抓到的報價不用（可能是早上的舊價）。
/// - [HeatmapLiveMode.afterClose]：只看是不是今天的收盤報價（定值，哪個畫面
///   抓的都可以）。
///
/// [symbolStatus] 只用來分辨盤中「無報價」與「未即時」。
HeatmapMarketData overlayHeatmapLive(
  HeatmapMarketData official, {
  required HeatmapLiveMode mode,
  required Map<String, LiveQuoteEntry> entries,
  required Map<String, LiveSymbolStatus> symbolStatus,
  required Set<String> registered,
  required Set<String> fresh,
  required DateTime today,
}) {
  _Verdict judge(HeatmapTile tile) {
    final entry = entries[tile.symbol];
    return switch (mode) {
      HeatmapLiveMode.intraday => _judgeIntraday(
        symbol: tile.symbol,
        entry: entry,
        registered: registered,
        fresh: fresh,
        status: symbolStatus[tile.symbol],
        today: today,
      ),
      HeatmapLiveMode.afterClose => _judgeAfterClose(entry, today),
    };
  }

  final industries = [
    for (final industry in official.industries)
      _overlayIndustry(industry, official.dataDate, judge),
  ];
  return HeatmapMarketData(
    market: official.market,
    dataDate: official.dataDate,
    industries: List.unmodifiable(industries),
    excludedForShares: official.excludedForShares,
    liveMode: mode,
  );
}

/// 一格的判定：用這筆報價上色，或空心的原因
sealed class _Verdict {
  const _Verdict();
}

final class _Colorable extends _Verdict {
  const _Colorable(this.entry);

  final LiveQuoteEntry entry;
}

final class _Hollow extends _Verdict {
  const _Hollow(this.reason);

  final HollowReason reason;
}

_Verdict _judgeIntraday({
  required String symbol,
  required LiveQuoteEntry? entry,
  required Set<String> registered,
  required Set<String> fresh,
  required LiveSymbolStatus? status,
  required DateTime today,
}) {
  if (!registered.contains(symbol)) return const _Hollow(HollowReason.notLive);
  if (entry == null || !fresh.contains(symbol)) {
    return _Hollow(
      status == LiveSymbolStatus.noQuote
          ? HollowReason.noQuote
          : HollowReason.notLive,
    );
  }
  // 日期先於顯示來源：不是今天的報價什麼都不能說
  if (!DateContext.isSameDay(entry.date, today)) {
    return const _Hollow(HollowReason.notLive);
  }
  // 試撮價或五檔中價不是真的漲跌
  if (entry.displaySource == LiveDisplaySource.trialOrBook) {
    return const _Hollow(HollowReason.noTrade);
  }
  return _Colorable(entry);
}

_Verdict _judgeAfterClose(LiveQuoteEntry? entry, DateTime today) =>
    entry != null && isClosingQuoteOfToday(entry, today)
    ? _Colorable(entry)
    : const _Hollow(HollowReason.noClosingQuote);

HeatmapIndustry _overlayIndustry(
  HeatmapIndustry industry,
  DateTime dataDate,
  _Verdict Function(HeatmapTile) judge,
) {
  final tiles = [
    for (final tile in industry.tiles)
      _overlayTile(tile, dataDate, judge(tile)),
  ];
  return HeatmapIndustry(
    name: industry.name,
    marketCap: industry.marketCap,
    weightedChangePercent: heatmapWeightedChange(tiles),
    tiles: List.unmodifiable(tiles),
    liveCoverage: heatmapValueCoverage(tiles),
  );
}

HeatmapTile _overlayTile(
  HeatmapTile tile,
  DateTime dataDate,
  _Verdict verdict,
) {
  switch (verdict) {
    case _Hollow(:final reason):
      return _hollowTile(tile, dataDate, reason);
    case _Colorable(:final entry):
      final y = entry.previousClose;
      final price = entry.price;
      final baseCap = tile.marketCap / tile.close * y;
      final percent = (price - y) * 100 / y;
      // 昨收或即時價不是正數、算不出有限的平盤市值或漲跌幅：沒有可信的漲跌
      if (!(y > 0) ||
          !(price > 0) ||
          !(baseCap > 0) ||
          !baseCap.isFinite ||
          !percent.isFinite) {
        return _hollowTile(tile, dataDate, HollowReason.noChangeData);
      }
      return HeatmapTile(
        symbol: tile.symbol,
        name: tile.name,
        close: price,
        marketCap: tile.marketCap,
        baseCap: baseCap,
        change: TileChangeValue(percent),
        isMine: tile.isMine,
      );
  }
}

/// 空心格子：顯示價維持正式資料的收盤；盤中未即時的附正式資料的漲跌
HeatmapTile _hollowTile(
  HeatmapTile tile,
  DateTime dataDate,
  HollowReason reason,
) {
  final official = tile.change;
  return HeatmapTile(
    symbol: tile.symbol,
    name: tile.name,
    close: tile.close,
    marketCap: tile.marketCap,
    baseCap: 0,
    change: TileChangeHollow(
      reason,
      previous: reason == HollowReason.notLive && official is TileChangeValue
          ? (percent: official.percent, date: dataDate)
          : null,
    ),
    isMine: tile.isMine,
  );
}

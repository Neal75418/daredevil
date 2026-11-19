import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
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

/// 熱力圖要向報價中心登記的個股代號：照 [HeatmapMarketData.tiles] 的順序
/// （市值降冪），最多 [HeatmapParams.liveTileLimit] 檔。
///
/// - [HeatmapLiveMode.intraday]：圖上的每一檔。
/// - [HeatmapLiveMode.afterClose]：還沒有今天收盤報價、報價中心也還沒放棄
///   （[closingGivenUp]，收盤那一盤沒撮合）的；拿到的與放棄的移出。放棄的
///   不移出會一直占著名額，報價中心不再抓它們。收盤報價是定值，[entries] 裡
///   哪個畫面抓的都算。盤中不看 [closingGivenUp]。
///
/// 純函式。
List<String> heatmapLiveSymbols(
  HeatmapMarketData official, {
  required HeatmapLiveMode mode,
  required Map<String, LiveQuoteEntry> entries,
  required Set<String> closingGivenUp,
  required DateTime today,
}) {
  final Iterable<HeatmapTile> candidates = switch (mode) {
    HeatmapLiveMode.intraday => official.tiles,
    HeatmapLiveMode.afterClose => official.tiles.where((tile) {
      final entry = entries[tile.symbol];
      return (entry == null || !isClosingQuoteOfToday(entry, today)) &&
          !closingGivenUp.contains(tile.symbol);
    }),
  };
  return [
    for (final tile in candidates.take(HeatmapParams.liveTileLimit))
      tile.symbol,
  ];
}

/// 今天的收盤報價：收盤後的登記清單、上色與進度共用這個判準，已取得的才會
/// 一致地移出清單、上色、計入進度
bool isClosingQuoteOfToday(LiveQuoteEntry entry, DateTime today) =>
    entry.isClosingQuote && DateContext.isSameDay(entry.date, today);

/// 把即時報價疊到正式資料上：逐格換漲跌與顯示價。
///
/// 純函式，不碰資料庫。面積（[HeatmapTile.marketCap]）、格子的順序、覆蓋率、
/// 頁尾檔數、資料日都維持正式資料；即時只換顏色。
///
/// 漲跌幅＝(即時價 − y) × 100 ÷ y，y 是證交所即時資料的昨收（除權息日是
/// 參考價）。y 不可用時畫空心，不退回資料庫的收盤：除權息日會把股息算成
/// 跌幅。
///
/// - [HeatmapLiveMode.intraday]：只用熱力圖自己登記（[registered]）、登記前後
///   拿到過（[fresh]，「前」只放寬一小段時間，由呼叫端決定）、日期是 [today]、
///   有成交或鎖住價的報價；更早以前中心裡別的畫面抓到的報價不用（可能是早上的
///   舊價）。
/// - [HeatmapLiveMode.afterClose]：依序判定：今天的收盤報價（定值，哪個畫面
///   抓的都可以）上色；在 [closingGivenUp]（報價中心試滿次數後放棄）是收盤
///   沒撮合；其餘是尚未取得收盤報價。
///
/// [symbolStatus] 只用來分辨盤中「無報價」與「未即時」；[closingGivenUp]
/// 盤中不看。
HeatmapMarketData overlayHeatmapLive(
  HeatmapMarketData official, {
  required HeatmapLiveMode mode,
  required Map<String, LiveQuoteEntry> entries,
  required Map<String, LiveSymbolStatus> symbolStatus,
  required Set<String> registered,
  required Set<String> fresh,
  required Set<String> closingGivenUp,
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
      HeatmapLiveMode.afterClose => _judgeAfterClose(
        entry: entry,
        givenUp: closingGivenUp.contains(tile.symbol),
        today: today,
      ),
    };
  }

  return HeatmapMarketData(
    market: official.market,
    dataDate: official.dataDate,
    tiles: List.unmodifiable([
      for (final tile in official.tiles)
        _overlayTile(tile, official.dataDate, judge(tile)),
    ]),
    capCoverage: official.capCoverage,
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

/// 收盤報價先於放棄：報價中心放棄的代號只要有今天的收盤報價就上色
_Verdict _judgeAfterClose({
  required LiveQuoteEntry? entry,
  required bool givenUp,
  required DateTime today,
}) {
  if (entry != null && isClosingQuoteOfToday(entry, today)) {
    return _Colorable(entry);
  }
  return _Hollow(
    givenUp ? HollowReason.noClosingMatch : HollowReason.noClosingQuote,
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
      // 平盤市值（股數 × 昨收）：正式資料的收盤或市值有問題時算不出正的有限值
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
        industry: tile.industry,
        close: price,
        marketCap: tile.marketCap,
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
    industry: tile.industry,
    close: tile.close,
    marketCap: tile.marketCap,
    change: TileChangeHollow(
      reason,
      previous: reason == HollowReason.notLive && official is TileChangeValue
          ? (percent: official.percent, date: dataDate)
          : null,
    ),
    isMine: tile.isMine,
  );
}

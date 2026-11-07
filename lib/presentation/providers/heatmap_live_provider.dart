import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_live.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 熱力圖頁正在看的市場（`MarketCode.twse`／`MarketCode.tpex`）與放大的產業
/// （[HeatmapIndustry.key]；null 是全市場）
typedef HeatmapSelection = ({String market, String? zoom});

final heatmapSelectionProvider =
    NotifierProvider.autoDispose<HeatmapSelectionNotifier, HeatmapSelection>(
      HeatmapSelectionNotifier.new,
    );

/// 熱力圖頁的選取；開頁是上市、全市場
class HeatmapSelectionNotifier extends Notifier<HeatmapSelection> {
  @override
  HeatmapSelection build() => (market: MarketCode.twse, zoom: null);

  /// 換市場並回到全市場（放大的產業屬於原本的市場）
  void selectMarket(String market) => state = (market: market, zoom: null);

  void zoomTo(String industryKey) =>
      state = (market: state.market, zoom: industryKey);

  void clearZoom() => state = (market: state.market, zoom: null);
}

/// 熱力圖頁要畫的資料與即時狀態
@immutable
class HeatmapLiveView {
  const HeatmapLiveView({
    this.data,
    this.mode,
    this.stockRegistrations = const [],
    this.quoteStatus,
    this.closing,
  });

  /// 要畫的資料：套上即時報價後的；不需要即時或停市日退回時是正式資料；
  /// 這個市場沒有正式資料時為 null
  final HeatmapMarketData? data;

  /// 現在的即時模式；不需要即時為 null。停市日退回時仍是現在的模式，
  /// [data] 的 [HeatmapMarketData.liveMode] 才是 null
  final HeatmapLiveMode? mode;

  /// 要向報價中心登記的個股（不含指數）。有登記時這個市場一定還沒有今天的
  /// 正式資料，[LiveQuoteRegistration.hasOfficialToday] 一律 false
  final List<LiveQuoteRegistration> stockRegistrations;

  /// 即時報價的狀態：盤中是報價中心的頁首規則（「證交所今天尚無報價」除外）；
  /// 收盤後只有報價暫停；停市日退回時是報價暫停或「證交所今天尚無報價」；
  /// 沒有為 null
  final LiveHeaderStatus? quoteStatus;

  /// 收盤後的進度：[total] 是整張圖（不論放大、合併）的檔數，[done] 是其中
  /// 已有今天收盤報價的檔數；收盤後以外與停市日退回時為 null
  final ({int done, int total})? closing;

  @override
  bool operator ==(Object other) =>
      other is HeatmapLiveView &&
      other.data == data &&
      other.mode == mode &&
      listEquals(other.stockRegistrations, stockRegistrations) &&
      other.quoteStatus == quoteStatus &&
      other.closing == closing;

  @override
  int get hashCode => Object.hash(
    data,
    mode,
    Object.hashAll(stockRegistrations),
    quoteStatus,
    closing,
  );

  @override
  String toString() =>
      'HeatmapLiveView(mode: $mode, data: ${data?.market} '
      '${data?.liveMode}, registrations: ${stockRegistrations.length}, '
      'status: $quoteStatus, closing: $closing)';
}

final heatmapLiveProvider =
    NotifierProvider.autoDispose<HeatmapLiveNotifier, HeatmapLiveView>(
      HeatmapLiveNotifier.new,
    );

/// 把正式資料、報價中心與交易時段組成熱力圖頁要顯示的 [HeatmapLiveView]。
///
/// 盤中只用「這頁開始登記該檔之後」抓到的報價上色：逐檔記該檔進入登記清單
/// 的時刻，報價中心的 `fetchedAt` 不早於它才算。清單變動（放大、取消放大、
/// 換市場、收盤後滾動）時新進的記現在、離開的移除，換日時整個清空。頁面被
/// 蓋住或 App 到背景時不清：已登記的檔，登記之後抓到的報價（哪個畫面抓的
/// 都算）照樣用，報價中心下一輪再換新。
class HeatmapLiveNotifier extends Notifier<HeatmapLiveView> {
  /// 代號 → 進入登記清單的時刻；Notifier 實例跨 build 保留
  final Map<String, DateTime> _since = {};

  /// [_since] 所屬的日期
  DateTime? _sinceDay;

  /// 上一次的 [HeatmapLiveView.data]
  HeatmapMarketData? _data;

  @override
  HeatmapLiveView build() {
    final selection = ref.watch(heatmapSelectionProvider);
    final official = ref.watch(
      marketHeatmapProvider.select((s) => s.markets[selection.market]),
    );
    final center = ref.watch(liveQuoteCenterProvider);
    // 跨過開盤、收盤、午夜時重算模式
    ref.watch(liveQuoteBoundaryProvider);
    final now = ref.read(appClockProvider).now();
    final today = DateContext.normalize(now);

    final mode = official == null
        ? null
        : heatmapLiveModeAt(
            phase: LiveQuoteSchedule.phaseAt(now),
            dataDate: official.dataDate,
            now: now,
          );
    if (official == null || mode == null) {
      _since.clear();
      return HeatmapLiveView(data: _keep(official));
    }

    final registered = heatmapLiveSymbols(
      official,
      mode: mode,
      zoomIndustryKey: selection.zoom,
      entries: center.entries,
      today: today,
    );
    final fresh = _track(registered, center.fetchedAt, now);
    final registrations = List<LiveQuoteRegistration>.unmodifiable([
      for (final symbol in registered)
        LiveQuoteRegistration(symbol: symbol, market: official.market),
    ]);
    final header = _header(official, registered, fresh, center, now);
    final paused = switch (header?.kind) {
      LiveHeaderKind.pausedRateLimit || LiveHeaderKind.pausedNetwork => header,
      _ => null,
    };

    if (_noQuotesToday(official, center, today)) {
      return HeatmapLiveView(
        data: _keep(official),
        mode: mode,
        stockRegistrations: registrations,
        quoteStatus:
            paused ?? const LiveHeaderStatus(LiveHeaderKind.noQuotesToday),
      );
    }

    final data = _keep(
      overlayHeatmapLive(
        official,
        mode: mode,
        entries: center.entries,
        symbolStatus: center.symbolStatus,
        registered: registered.toSet(),
        fresh: fresh,
        today: today,
      ),
    );
    return switch (mode) {
      // 「證交所今天尚無報價」只由停市日退回產生：頁首規則只在
      // `latestResponseHadToday == false` 時說它，而那時沒有退回，代表圖上
      // 某處有今天的報價；頁首規則只看登記的那幾檔（例如放大到還沒抓到的
      // 產業），說出來會是錯的
      HeatmapLiveMode.intraday => HeatmapLiveView(
        data: data,
        mode: mode,
        stockRegistrations: registrations,
        quoteStatus: header?.kind == LiveHeaderKind.noQuotesToday
            ? null
            : header,
      ),
      // 頁首規則的「證交所今天尚無報價」「最後報價」看的是還沒拿到收盤報價
      // 的那幾檔，收盤後會誤報；收盤後的狀態改由 [HeatmapLiveView.closing]
      // 描述，只保留暫停
      HeatmapLiveMode.afterClose => HeatmapLiveView(
        data: data,
        mode: mode,
        stockRegistrations: registrations,
        quoteStatus: paused,
        closing: _closingProgress(official, center.entries, today),
      ),
    };
  }

  /// 更新各檔進入登記清單的時刻，回傳 [registered] 中報價抓到的時刻
  /// （[fetchedAt]）不早於它的代號
  Set<String> _track(
    List<String> registered,
    Map<String, DateTime> fetchedAt,
    DateTime now,
  ) {
    final day = _sinceDay;
    // 頁面被蓋住過夜時不重算，回來後第一次重算才換日
    if (day == null || !DateContext.isSameDay(day, now)) {
      _since.clear();
      _sinceDay = now;
    }
    final kept = registered.toSet();
    _since.removeWhere((symbol, _) => !kept.contains(symbol));
    final fresh = <String>{};
    for (final symbol in registered) {
      final since = _since.putIfAbsent(symbol, () => now);
      final fetched = fetchedAt[symbol];
      if (fetched != null && !fetched.isBefore(since)) fresh.add(symbol);
    }
    return fresh;
  }

  /// 報價中心的頁首規則，套在登記的各檔上（只用這頁登記之後抓到的報價）
  static LiveHeaderStatus? _header(
    HeatmapMarketData official,
    List<String> registered,
    Set<String> fresh,
    LiveQuoteState center,
    DateTime now,
  ) {
    final closes = {
      for (final industry in official.industries)
        for (final tile in industry.tiles) tile.symbol: tile.close,
    };
    return LiveQuoteStatusRule.header(
      state: center,
      merged: [
        for (final symbol in registered)
          LiveQuoteMerge.merge(
            official: OfficialPrice(
              date: official.dataDate,
              close: closes[symbol],
            ),
            live: fresh.contains(symbol) ? center.entries[symbol] : null,
            now: now,
          ),
      ],
      intradayTime: center.latestQuoteTime,
    );
  }

  /// 停市日（日曆沒標的颱風假等）：報價中心最近一輪有回應但沒有今天的報價，
  /// 而且整張圖上（不論放大）沒有任何一檔有今天的報價。開盤頭幾秒同樣成立，
  /// 第一筆今天的報價到了就不成立
  static bool _noQuotesToday(
    HeatmapMarketData official,
    LiveQuoteState center,
    DateTime today,
  ) {
    if (center.latestResponseHadToday != false) return false;
    for (final industry in official.industries) {
      for (final tile in industry.tiles) {
        final entry = center.entries[tile.symbol];
        if (entry != null && DateContext.isSameDay(entry.date, today)) {
          return false;
        }
      }
    }
    return true;
  }

  /// 收盤後的進度（「今天的收盤報價」與登記清單、套色用同一個判準）
  static ({int done, int total}) _closingProgress(
    HeatmapMarketData official,
    Map<String, LiveQuoteEntry> entries,
    DateTime today,
  ) {
    var done = 0;
    var total = 0;
    for (final industry in official.industries) {
      for (final tile in industry.tiles) {
        total++;
        final entry = entries[tile.symbol];
        if (entry != null && isClosingQuoteOfToday(entry, today)) done++;
      }
    }
    return (done: done, total: total);
  }

  /// 新算出的資料與上一次相等時沿用上一次的物件：熱力圖以物件 identity
  /// 快取佈局，報價中心每一輪都發布新狀態，不沿用就每輪重排
  HeatmapMarketData? _keep(HeatmapMarketData? data) {
    final kept = data == _data ? _data : data;
    _data = kept;
    return kept;
  }
}

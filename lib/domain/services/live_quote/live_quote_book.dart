import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 一輪的結果(spec §3)
enum RoundOutcome {
  /// 至少拿到 1 筆今天的報價
  success,

  /// 有回應,但沒有任何今天的報價(開盤頭幾秒、日曆漏標的停市日、列全被
  /// 解析丟掉)。不算網路失敗、不退避
  respondedNoToday,

  /// 沒有任何一批有回應
  failed,
}

/// 報價中心的記帳本(純邏輯,不碰網路與時鐘;2026-10-06)。
///
/// 每一輪把 client 的逐批結果套進來,算出各檔的顯示價、顯示來源、閃色、
/// 卡片狀態,以及收盤後逐檔的嘗試次數。所有記憶都以「今天」為範圍,換日
/// 由 [rollDay] 清空。
class LiveQuoteBook {
  DateTime? _day;
  final Map<String, LiveQuoteEntry> _entries = {};
  final Map<String, LiveSymbolStatus> _status = {};

  /// 今天記到的最後成交價(含鎖住價)與時間
  final Map<String, ({double price, String? time})> _lastTraded = {};
  final Map<String, ({int attempts, DateTime lastAttemptAt})> _afterClose = {};

  /// 上一輪拿到今天報價的代號(閃色要連續兩輪都有)
  Set<String> _fetchedLastRound = {};
  int _flashSeq = 0;
  bool? _latestResponseHadToday;
  String? _latestQuoteTime;

  Map<String, LiveQuoteEntry> get entries => Map.unmodifiable(_entries);
  Map<String, LiveSymbolStatus> get symbolStatus => Map.unmodifiable(_status);

  /// 最近一次有回應的一輪有沒有今天的報價;還沒有任何回應為 null
  bool? get latestResponseHadToday => _latestResponseHadToday;

  /// 最近一次成功的一輪中,各筆報價時間的最大值
  String? get latestQuoteTime => _latestQuoteTime;

  /// 日期變了就清空所有記憶(App 開著過夜)。回傳是否清掉了前一天的資料
  bool rollDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_day == today) return false;
    final hadDay = _day != null;
    _day = today;
    _entries.clear();
    _status.clear();
    _lastTraded.clear();
    _afterClose.clear();
    _fetchedLastRound = {};
    _latestResponseHadToday = null;
    _latestQuoteTime = null;
    return hadDay;
  }

  /// App 重新可見、限流暫停後:下一輪不閃色(拿來比較的是很久以前的價格)
  void forgetLastRound() => _fetchedLastRound = {};

  /// 這幾檔的畫面都離開了:之後再登記時第一輪不閃色
  void forget(Iterable<String> symbols) => _fetchedLastRound.removeAll(symbols);

  /// 收盤後 [candidates] 中還要抓的代號(保持輸入順序)
  List<String> pendingAfterClose(Iterable<String> candidates) => [
    for (final s in candidates)
      if (LiveQuoteSchedule.afterClosePending(
        hasClosingQuote: _entries[s]?.isClosingQuote ?? false,
        attempts: _afterClose[s]?.attempts ?? 0,
      ))
        s,
  ];

  /// 收盤後 [candidates] 中現在該抓的代號(保持輸入順序)
  List<String> dueAfterClose(Iterable<String> candidates, DateTime now) => [
    for (final s in candidates)
      if (LiveQuoteSchedule.afterCloseDue(
        hasClosingQuote: _entries[s]?.isClosingQuote ?? false,
        attempts: _afterClose[s]?.attempts ?? 0,
        lastAttemptAt: _afterClose[s]?.lastAttemptAt,
        now: now,
      ))
        s,
  ];

  /// 套用一輪的結果。[requested] 是這一輪送出的代號;[afterClose] 為收盤後
  /// 的逐檔抓取(要記嘗試次數)。
  RoundOutcome apply(
    QuoteBatchReport report, {
    required Iterable<String> requested,
    required DateTime now,
    required bool afterClose,
  }) {
    rollDay(now);
    final today = DateTime(now.year, now.month, now.day);
    // 閃色只活一輪
    for (final e in _entries.entries.toList()) {
      if (e.value.flash != null) _entries[e.key] = e.value.withoutFlash();
    }

    final fetchedThisRound = <String>{};
    String? maxTime;
    for (final symbol in requested) {
      final quote = report.quotes[symbol];
      final date = quote?.date;
      if (quote != null && date != null && date == today) {
        _entries[symbol] = _display(symbol, quote, today);
        _status[symbol] = LiveSymbolStatus.ok;
        fetchedThisRound.add(symbol);
        if (_later(quote.time, maxTime)) maxTime = quote.time;
      } else {
        _status[symbol] = report.failedSymbols.contains(symbol)
            ? LiveSymbolStatus.batchFailed
            : LiveSymbolStatus.noQuote;
      }
      if (afterClose) _recordAfterCloseAttempt(symbol, report, now);
    }
    _fetchedLastRound = fetchedThisRound;

    if (fetchedThisRound.isNotEmpty) {
      _latestResponseHadToday = true;
      _latestQuoteTime = maxTime;
      return RoundOutcome.success;
    }
    if (requested.any(report.respondedSymbols.contains)) {
      _latestResponseHadToday = false;
      return RoundOutcome.respondedNoToday;
    }
    return RoundOutcome.failed;
  }

  LiveQuoteEntry _display(String symbol, IntradayQuote q, DateTime today) {
    final pick = _pick(symbol, q);
    if (pick.source != LiveDisplaySource.trialOrBook) {
      _lastTraded[symbol] = (price: pick.price, time: pick.time);
    }
    final previous = _entries[symbol];
    LiveQuoteFlash? flash;
    if (previous != null &&
        _fetchedLastRound.contains(symbol) &&
        _flashable(previous.displaySource) &&
        _flashable(pick.source) &&
        pick.price != previous.price) {
      flash = LiveQuoteFlash(id: ++_flashSeq, up: pick.price > previous.price);
    }
    return LiveQuoteEntry(
      symbol: symbol,
      date: today,
      price: pick.price,
      displaySource: pick.source,
      previousClose: q.previousClose,
      quoteTime: pick.time,
      isClosingQuote: LiveQuoteSchedule.isClosingQuote(q, today),
      open: q.open,
      high: q.high,
      low: q.low,
      volumeLots: q.volume,
      limitUp: q.limitUp,
      limitDown: q.limitDown,
      isLimitUpLocked: q.isLimitUpLocked,
      isLimitDownLocked: q.isLimitDownLocked,
      flash: flash,
    );
  }

  /// 顯示價(spec §3,依序)
  ({double price, LiveDisplaySource source, String? time}) _pick(
    String symbol,
    IntradayQuote q,
  ) {
    // 1. 本輪判為鎖住 → 漲停價或跌停價
    final limitUp = q.limitUp;
    if (q.isLimitUpLocked && limitUp != null) {
      return (price: limitUp, source: LiveDisplaySource.locked, time: q.time);
    }
    final limitDown = q.limitDown;
    if (q.isLimitDownLocked && limitDown != null) {
      return (price: limitDown, source: LiveDisplaySource.locked, time: q.time);
    }
    // 2. 本輪有成交價
    if (q.priceSource == QuotePriceSource.trade) {
      return (price: q.price, source: LiveDisplaySource.trade, time: q.time);
    }
    // 3. 本輪有 trade.z
    final lastTrade = q.lastTradePrice;
    if (lastTrade != null) {
      return (
        price: lastTrade,
        source: LiveDisplaySource.lastTrade,
        time: q.lastTradeTime,
      );
    }
    // 4. 今天記到的成交價或鎖住價
    final memory = _lastTraded[symbol];
    if (memory != null) {
      return (
        price: memory.price,
        source: LiveDisplaySource.lastTrade,
        time: memory.time,
      );
    }
    // 5. 試撮或五檔
    return (
      price: q.price,
      source: LiveDisplaySource.trialOrBook,
      time: q.time,
    );
  }

  static bool _flashable(LiveDisplaySource s) =>
      s != LiveDisplaySource.trialOrBook;

  void _recordAfterCloseAttempt(
    String symbol,
    QuoteBatchReport report,
    DateTime now,
  ) {
    final responded = report.respondedSymbols.contains(symbol);
    final closing = _entries[symbol]?.isClosingQuote ?? false;
    final attempts = _afterClose[symbol]?.attempts ?? 0;
    _afterClose[symbol] = (
      // 只計「有回應但不是收盤報價」;網路失敗、限流不計
      attempts: attempts + (responded && !closing ? 1 : 0),
      lastAttemptAt: now,
    );
  }

  /// [a] 是否比 [b] 晚;[a] 格式不符一律 false
  static bool _later(String? a, String? b) {
    final sa = LiveQuoteSchedule.secondsOfDay(a);
    if (sa == null) return false;
    final sb = LiveQuoteSchedule.secondsOfDay(b);
    return sb == null || sa > sb;
  }
}

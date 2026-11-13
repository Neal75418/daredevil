import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
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

/// 一次 [LiveQuoteBook.apply] 的統計(觀測用),只算列日期是今天的那幾檔:
/// `applied` 是這幾檔的總數(換上去的加上被擋下的)、`rejected` 是被擋下的、
/// `futureSnapshots` 是快照時刻偏前而不採信的、`missingSnapshots` 是沒有
/// 可信快照時刻的(含偏前的)、`oldestSnapshot` 是換上去的那幾檔裡最舊的
/// 快照時刻
typedef LiveApplyStats = ({
  int applied,
  int rejected,
  int futureSnapshots,
  int missingSnapshots,
  DateTime? oldestSnapshot,
});

/// 報價中心的記帳本(純邏輯,不碰網路與時鐘;2026-10-06)。
///
/// 每一輪把 client 的逐批結果套進來,算出各檔的顯示價、顯示來源、閃色、
/// 卡片狀態,以及收盤後逐檔的嘗試次數。所有記憶都以「今天」為範圍,換日
/// 由 [rollDay] 清空。
class LiveQuoteBook {
  DateTime? _day;
  final Map<String, LiveQuoteEntry> _entries = {};
  final Map<String, LiveSymbolStatus> _status = {};

  /// 各代號最近一次拿到今天報價的那一輪的套用時刻;沒拿到的輪次不動它
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, DateTime> _lastReceivedAt = {};
  LiveApplyStats? _lastApplyStats;

  /// 今天記到的最後成交價(含鎖住價)與時間
  final Map<String, ({double price, String? time})> _lastTraded = {};
  final Map<String, ({int attempts, DateTime lastAttemptAt})> _afterClose = {};

  /// 上一輪拿到今天報價的代號(閃色要連續兩輪都有)
  Set<String> _fetchedLastRound = {};
  int _flashSeq = 0;
  bool? _latestResponseHadToday;

  Map<String, LiveQuoteEntry> get entries => Map.unmodifiable(_entries);
  Map<String, LiveSymbolStatus> get symbolStatus => Map.unmodifiable(_status);

  /// 各代號最近一次拿到今天報價的那一輪的套用時刻(換日清空);沒拿到過的
  /// 代號不在裡面。時刻是呼叫端傳給 [apply] 的 `now`(報價中心取自
  /// `appClockProvider`):不早於實際抓取,被截斷的一輪記截斷當下。所以拿來
  /// 判斷「某個時刻之後才抓到」會寬鬆,最多差一輪。拿到的是比畫面舊的快照
  /// (沒換上去)也算拿到
  Map<String, DateTime> get fetchedAt => Map.unmodifiable(_fetchedAt);

  /// 各代號最近一次拿到今天報價時,那一批回應收到的時刻(換日清空)。時刻由
  /// 呼叫端經 [apply] 的 `receivedAt` 給;沒給的代號不動。和 [fetchedAt] 的
  /// 差別:這裡是那一批回來的當下,不是整輪套用的時刻
  Map<String, DateTime> get lastReceivedAt => Map.unmodifiable(_lastReceivedAt);

  /// 最近一次 [apply] 的統計;還沒套用過、或換日之後為 null
  LiveApplyStats? get lastApplyStats => _lastApplyStats;

  /// 最近一次有回應的一輪有沒有今天的報價;還沒有任何回應為 null
  bool? get latestResponseHadToday => _latestResponseHadToday;

  /// 日期變了就清空所有記憶(App 開著過夜)。回傳是否清掉了前一天的資料
  bool rollDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_day == today) return false;
    final hadDay = _day != null;
    _day = today;
    _entries.clear();
    _status.clear();
    _fetchedAt.clear();
    _lastReceivedAt.clear();
    _lastApplyStats = null;
    _lastTraded.clear();
    _afterClose.clear();
    _fetchedLastRound = {};
    _latestResponseHadToday = null;
    return hadDay;
  }

  /// App 重新可見、限流暫停後:下一輪不閃色(拿來比較的是很久以前的價格)
  void forgetLastRound() => _fetchedLastRound = {};

  /// 這幾檔的畫面都離開了:之後再登記時第一輪不閃色
  void forget(Iterable<String> symbols) => _fetchedLastRound.removeAll(symbols);

  /// 今天收盤後已放棄的代號 → 最後一次嘗試的套用時刻(呼叫端傳給 [apply]
  /// 的 `now`)。
  ///
  /// 放棄＝現在不是收盤報價,而且 [LiveQuoteSchedule.afterClosePending] 說
  /// 不必再抓(「有回應但不是收盤報價」已滿
  /// [LiveQuoteParams.afterCloseMaxAttempts] 次,收盤那一盤沒撮合)。直接取
  /// 排程判準的反面:沒有收盤報價的代號不是還要抓、就是在這裡。放棄後收盤後
  /// 不再請求它,時刻就停在放棄的那一次。換日清空
  Map<String, DateTime> get closingGivenUpAt {
    final givenUp = <String, DateTime>{};
    for (final MapEntry(key: symbol, value: (:attempts, :lastAttemptAt))
        in _afterClose.entries) {
      final closing = _entries[symbol]?.isClosingQuote ?? false;
      if (!closing &&
          !LiveQuoteSchedule.afterClosePending(
            hasClosingQuote: closing,
            attempts: attempts,
          )) {
        givenUp[symbol] = lastAttemptAt;
      }
    }
    return Map.unmodifiable(givenUp);
  }

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
  /// 的逐檔抓取(要記嘗試次數);[receivedAt] 是各代號所在那一批回應收到的
  /// 時刻(見 [lastReceivedAt])。
  ///
  /// 快照時刻在兩種情況下不採信、當成沒有:比那一批收到的時刻([receivedAt]
  /// 沒給這一檔時用 [now])晚超過 [LiveQuoteParams.snapshotFutureTolerance];
  /// 日期不是今天。
  ///
  /// 證交所的快取會回比上一輪舊的快照。今天的報價只在這兩條都成立時不換
  /// 上去:快照時刻比畫面那筆早;這一列自己的 `t` 沒有比畫面那筆晚(任一邊
  /// 無法解析也算沒有)。任一邊沒有可信的快照時刻就照換。沒換上去的那一檔
  /// 不改畫面那筆(含它的 `rowTime`,頁首的報價時間因此不往回)、不閃色、
  /// 不更新今天記到的成交價;其餘和換上去的一樣,都算這一輪拿到今天的報價:
  /// 卡片狀態、[fetchedAt]、[lastReceivedAt]、收盤後的嘗試、這一輪的結果與
  /// [latestResponseHadToday]、下一輪閃色要比對的「上一輪有拿到」。
  RoundOutcome apply(
    QuoteBatchReport report, {
    required Iterable<String> requested,
    required DateTime now,
    required bool afterClose,
    Map<String, DateTime> receivedAt = const {},
  }) {
    rollDay(now);
    final today = DateTime(now.year, now.month, now.day);
    // 閃色只活一輪
    for (final e in _entries.entries.toList()) {
      if (e.value.flash != null) _entries[e.key] = e.value.withoutFlash();
    }

    final fetchedThisRound = <String>{};
    var rejected = 0;
    var futureSnapshots = 0;
    var missingSnapshots = 0;
    DateTime? oldestSnapshot;
    for (final symbol in requested) {
      final quote = report.quotes[symbol];
      final date = quote?.date;
      if (quote != null && date != null && date == today) {
        final received = receivedAt[symbol];
        final snapshot = _trustedSnapshot(
          quote.snapshotAt,
          received ?? now,
          today,
        );
        final snapshotAt = snapshot.at;
        if (snapshot.future) futureSnapshots++;
        if (snapshotAt == null) missingSnapshots++;
        if (_olderThanShown(_entries[symbol], snapshotAt, quote.time)) {
          rejected++;
        } else {
          _entries[symbol] = _display(symbol, quote, today, snapshotAt);
          if (snapshotAt != null &&
              (oldestSnapshot == null || snapshotAt.isBefore(oldestSnapshot))) {
            oldestSnapshot = snapshotAt;
          }
        }
        _status[symbol] = LiveSymbolStatus.ok;
        _fetchedAt[symbol] = now;
        if (received != null) _lastReceivedAt[symbol] = received;
        fetchedThisRound.add(symbol);
      } else {
        _status[symbol] = report.failedSymbols.contains(symbol)
            ? LiveSymbolStatus.batchFailed
            : LiveSymbolStatus.noQuote;
      }
      if (afterClose) _recordAfterCloseAttempt(symbol, report, now);
    }
    _fetchedLastRound = fetchedThisRound;
    _lastApplyStats = (
      applied: fetchedThisRound.length,
      rejected: rejected,
      futureSnapshots: futureSnapshots,
      missingSnapshots: missingSnapshots,
      oldestSnapshot: oldestSnapshot,
    );

    if (fetchedThisRound.isNotEmpty) {
      _latestResponseHadToday = true;
      return RoundOutcome.success;
    }
    if (requested.any(report.respondedSymbols.contains)) {
      _latestResponseHadToday = false;
      return RoundOutcome.respondedNoToday;
    }
    return RoundOutcome.failed;
  }

  /// 可信的快照時刻:比收到它的時刻 [receivedAt] 晚超過
  /// [LiveQuoteParams.snapshotFutureTolerance](`future` 為 true),或日期
  /// 不是今天的,都當成沒有
  static ({DateTime? at, bool future}) _trustedSnapshot(
    DateTime? snapshotAt,
    DateTime receivedAt,
    DateTime today,
  ) {
    if (snapshotAt == null) return (at: null, future: false);
    if (snapshotAt.isAfter(
      receivedAt.add(LiveQuoteParams.snapshotFutureTolerance),
    )) {
      return (at: null, future: true);
    }
    return (
      at: DateContext.isSameDay(snapshotAt, today) ? snapshotAt : null,
      future: false,
    );
  }

  /// 這份今天的報價是不是比畫面那筆 [shown] 舊(見 [apply] 的兩條)
  static bool _olderThanShown(
    LiveQuoteEntry? shown,
    DateTime? snapshotAt,
    String? rowTime,
  ) {
    final shownAt = shown?.snapshotAt;
    if (shown == null || shownAt == null || snapshotAt == null) return false;
    return snapshotAt.isBefore(shownAt) &&
        !_strictlyLater(rowTime, shown.rowTime);
  }

  LiveQuoteEntry _display(
    String symbol,
    IntradayQuote q,
    DateTime today,
    DateTime? snapshotAt,
  ) {
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
      snapshotAt: snapshotAt,
      rowTime: q.time,
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

  /// [a] 是否確定比 [b] 晚:兩邊都解析得出來才比,任一邊格式不符一律 false
  static bool _strictlyLater(String? a, String? b) {
    final sa = LiveQuoteSchedule.secondsOfDay(a);
    final sb = LiveQuoteSchedule.secondsOfDay(b);
    return sa != null && sb != null && sa > sb;
  }
}

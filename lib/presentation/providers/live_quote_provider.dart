import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_book.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 畫面登記的一檔
@immutable
class LiveQuoteRegistration {
  const LiveQuoteRegistration({
    required this.symbol,
    required this.market,
    this.hasOfficialToday = false,
  });

  final String symbol;

  /// 市場別(`MarketCode.twse`／`MarketCode.tpex`),個股取自股票主檔;
  /// 大盤指數由報價中心硬對應,這裡帶什麼都不影響
  final String market;

  /// 這個畫面這一檔是否已有今天的正式資料(收盤後逐檔判斷要不要抓)
  final bool hasOfficialToday;

  @override
  bool operator ==(Object other) =>
      other is LiveQuoteRegistration &&
      other.symbol == symbol &&
      other.market == market &&
      other.hasOfficialToday == hasOfficialToday;

  @override
  int get hashCode => Object.hash(symbol, market, hasOfficialToday);
}

/// 報價中心對外的狀態(第 2、3 段的畫面讀它)
@immutable
class LiveQuoteState {
  const LiveQuoteState({
    this.entries = const {},
    this.symbolStatus = const {},
    this.stalled = false,
    this.rateLimitedUntil,
    this.lastRespondedAt,
    this.latestResponseHadToday,
    this.latestQuoteTime,
  });

  /// 各檔今天的即時報價(換日清空;顯示前一律經 `LiveQuoteMerge` 檢查日期)
  final Map<String, LiveQuoteEntry> entries;

  /// 各檔最近一次被請求的結果(卡片的「報價暫停」「無報價」)
  final Map<String, LiveSymbolStatus> symbolStatus;

  /// 報價暫停(網路):計時中,距上一次有回應的一輪超過門檻
  final bool stalled;

  /// 報價暫停(證交所限流):到這個時刻後試探;試探完成前不清
  final DateTime? rateLimitedUntil;

  /// 上一次有回應的一輪(頁首「最後更新」)
  final DateTime? lastRespondedAt;

  /// 最近一次有回應的一輪有沒有今天的報價;還沒有回應為 null
  /// (頁首「證交所今天尚無報價」)
  final bool? latestResponseHadToday;

  /// 最近一次成功的一輪中,各筆報價時間的最大值(頁首盤中顯示)
  final String? latestQuoteTime;
}

/// 報價中心專用 client:短逾時(MIS 卡住時 5 秒／8 秒就放棄、下一輪再來),
/// 不逐批記 warning(失敗由中心統一記)
final liveQuoteClientProvider = Provider<IntradayQuoteClient>((ref) {
  final client = IntradayQuoteClient(
    dio: MarketClientMixin.createDio(
      ApiEndpoints.twseMisIntraday,
      connectTimeout: LiveQuoteParams.connectTimeout,
      receiveTimeout: LiveQuoteParams.receiveTimeout,
    ),
    logBatchErrors: false,
  );
  ref.onDispose(client.close);
  return client;
});

final liveQuoteCenterProvider =
    NotifierProvider<LiveQuoteCenter, LiveQuoteState>(LiveQuoteCenter.new);

/// 盤中即時報價中心(全 App 唯一,2026-10-06)。
///
/// 畫面以 `LiveQuoteScope` 登記要看的股票;中心每秒一拍,在「有登記、App
/// 可見、排程說該抓」時逐批發請求(任何 60 秒內 ≤ 8 個、相鄰 ≥ 2 秒、
/// 避開 CLI),結果經 [LiveQuoteBook] 算成各檔顯示價放進 state。只存在
/// 記憶體,不寫資料庫;任何錯誤都不影響盤後資料的顯示。
///
/// 🚨 [register]／[unregister]／[setAppVisible] 會在 widget 的
/// didChangeDependencies／dispose(build 期間)被呼叫,**不可寫 state**
/// ——Riverpod 不允許 build 期間修改 provider。它們只改內部欄位與計時器,
/// 結果等下一拍才反映。
class LiveQuoteCenter extends Notifier<LiveQuoteState> {
  static const String _tag = 'LiveQuote';

  final Map<Object, List<LiveQuoteRegistration>> _registrations = {};
  final LiveQuoteBook _book = LiveQuoteBook();

  /// 最近幾個請求的送出時刻(節流用)。只留最近 [LiveQuoteParams.maxRequestsPerMinute]
  /// 個:「窗口內是否已滿」與「離上一個多久」都只看它們,更早的不影響判斷,
  /// 所以不必按時間修剪(修剪的窗口一旦和計數的不同,節流就會失準)
  final List<DateTime> _sentAt = [];
  Timer? _ticker;

  /// 啟動時生命週期狀態可能是 null → 視為可見
  bool _appVisible = true;

  _Round? _round;
  bool _inFlight = false;
  DateTime? _lastRoundStartedAt;

  /// 登記聯集的版本:一輪開始時記下,送下一批前不同就提早結束這一輪
  int _registrationVersion = 0;

  // 暫停計時:只在「排程要抓、App 可見、有登記」的相鄰拍子之間累計
  DateTime? _lastCountedTick;
  Duration _unresponsive = Duration.zero;
  bool _stalled = false;
  int _failuresSinceStall = 0;

  DateTime? _rateLimitedUntil;
  bool _probing = false;
  DateTime? _lastRespondedAt;

  // 紀錄去重:一段連續失敗只記開始與恢復;非預期錯誤一段只送一次
  int _failStreak = 0;
  bool _unexpectedReported = false;

  @override
  LiveQuoteState build() {
    ref.onDispose(_stopTicker);
    return const LiveQuoteState();
  }

  /// 登記 [owner] 要看的股票(同一 owner 再登記即取代)。等下一拍才抓
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      _changeRegistrations(
        () => _registrations[owner] = List.unmodifiable(entries),
      );

  void unregister(Object owner) {
    if (!_registrations.containsKey(owner)) return;
    _changeRegistrations(() => _registrations.remove(owner));
  }

  void _changeRegistrations(void Function() change) {
    final before = _union();
    change();
    final after = _union();
    // 畫面都離開的那幾檔:之後再登記時第一輪不閃色(中間沒有任何一輪時,
    // 拿來比較的會是很久以前的價格)
    _book.forget(before.keys.toSet().difference(after.keys.toSet()));
    // 聯集真的變了才換版本:畫面重建時用同一份清單再登記不影響進行中的一輪
    if (!_sameUnion(before, after)) _registrationVersion++;
    _syncTicker();
  }

  static bool _sameUnion(
    Map<String, LiveQuoteRegistration> a,
    Map<String, LiveQuoteRegistration> b,
  ) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  /// App 生命週期:resumed／inactive 可見,hidden／paused 不可見
  void setAppVisible(bool visible) {
    if (_appVisible == visible) return;
    _appVisible = visible;
    // 重新可見後第一輪不閃色:拿來比較的是隱藏前的價格
    if (visible) _book.forgetLastRound();
    _syncTicker();
  }

  /// 目前登記的聯集:代號 → 市場別(已套用指數硬對應)
  @visibleForTesting
  Map<String, String> get registeredMarkets => {
    for (final r in _union().values) r.symbol: _marketOf(r),
  };

  void _syncTicker() {
    final shouldRun =
        _appVisible && _registrations.values.any((l) => l.isNotEmpty);
    if (shouldRun && _ticker == null) {
      _ticker = Timer.periodic(LiveQuoteParams.tick, (_) => unawaited(_tick()));
    } else if (!shouldRun && _ticker != null) {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    // 停拍期間不計暫停時間
    _lastCountedTick = null;
    // 進行中的那一輪作廢:恢復時已拿到的批次可能是很久以前的,不可當成新的
    // 套用;請求還在路上的,回來後丟棄
    _round?.discarded = true;
    _round = null;
  }

  Future<void> _tick() async {
    try {
      await _step();
    } catch (e, st) {
      _reportUnexpected((error: e, stackTrace: st));
    }
  }

  Future<void> _step() async {
    final now = _now();
    if (_book.rollDay(now)) {
      // App 開著過夜:昨天的暫停計時不帶到今天,過夜那段也不算
      _unresponsive = Duration.zero;
      _lastCountedTick = null;
      _publish();
    }
    final phase = LiveQuoteSchedule.phaseAt(now);
    final afterClose = phase == MarketPhase.afterClose;
    final plan = _plan(phase, now);
    _countStall(now, pending: plan.pending, afterClose: afterClose);

    if (_inFlight) return; // 上一個請求還沒回來:跳過,不疊加
    final until = _rateLimitedUntil;
    if (until != null && now.isBefore(until)) return;
    final current = _round;
    if (current != null && current.version != _registrationVersion) {
      // 登記變了:已拿到的批次照常套用,剩下的不送,下一拍依新的登記重新規劃
      current.truncate();
      _round = null;
      _finishRound(current, now);
      return;
    }
    if (_round == null &&
        (plan.due.isEmpty || !_roundDue(now, _batchCount(plan.due.length)))) {
      return;
    }
    if (LiveQuoteSchedule.inCliAvoidWindow(now)) return;
    if (!LiveQuoteSchedule.canSendRequest(_sentAt, now)) return;

    final round = _round ??= _startRound(plan.due, afterClose, now);
    final batch = round.nextBatch();
    _sentAt.add(now);
    if (_sentAt.length > LiveQuoteParams.maxRequestsPerMinute) {
      _sentAt.removeAt(0);
    }
    final report = await _fetchBatch(batch, round);
    if (!ref.mounted) return;
    final after = _now();
    if (report == null) {
      _round = null;
      _enterRateLimit(after);
      return;
    }
    if (round.discarded) return;
    round.add(report);
    if (round.isDone) {
      _round = null;
      _finishRound(round, after);
    }
  }

  DateTime _now() => ref.read(appClockProvider).now();

  /// 這一拍的計畫:[due] 是若要開新的一輪該抓的代號 → 市場別(保持登記
  /// 順序);[pending] 是排程還要抓的檔數(暫停計時與門檻用)
  ({Map<String, String> due, int pending}) _plan(
    MarketPhase phase,
    DateTime now,
  ) {
    final union = _union();
    switch (phase) {
      case MarketPhase.closed:
      case MarketPhase.preOpen:
        return (due: const {}, pending: 0);
      case MarketPhase.open:
        return (
          due: {for (final r in union.values) r.symbol: _marketOf(r)},
          pending: union.length,
        );
      case MarketPhase.afterClose:
        final candidates = [
          for (final r in union.values)
            if (!r.hasOfficialToday) r.symbol,
        ];
        return (
          due: {
            for (final s in _book.dueAfterClose(candidates, now))
              s: _marketOf(union[s]!),
          },
          pending: _book.pendingAfterClose(candidates).length,
        );
    }
  }

  /// 所有畫面登記的聯集;同一檔只要有任一畫面還沒有今天的正式資料,
  /// 收盤後就要抓
  Map<String, LiveQuoteRegistration> _union() {
    final union = <String, LiveQuoteRegistration>{};
    for (final list in _registrations.values) {
      for (final r in list) {
        final seen = union[r.symbol];
        if (seen == null || (seen.hasOfficialToday && !r.hasOfficialToday)) {
          union[r.symbol] = r;
        }
      }
    }
    return union;
  }

  static String _marketOf(LiveQuoteRegistration r) => switch (r.symbol) {
    LiveQuoteParams.twseIndexSymbol => MarketCode.twse,
    LiveQuoteParams.tpexIndexSymbol => MarketCode.tpex,
    _ => r.market,
  };

  static int _batchCount(int symbols) =>
      (symbols + ApiEndpoints.misBatchSize - 1) ~/ ApiEndpoints.misBatchSize;

  bool _roundDue(DateTime now, int batchCount) {
    final last = _lastRoundStartedAt;
    if (last == null) return true;
    final interval = _stalled
        ? LiveQuoteSchedule.backoffInterval(batchCount, _failuresSinceStall)
        : LiveQuoteSchedule.pollInterval(batchCount);
    return now.difference(last) >= interval;
  }

  void _countStall(
    DateTime now, {
    required int pending,
    required bool afterClose,
  }) {
    final counting = pending > 0;
    final last = _lastCountedTick;
    if (counting && last != null) _unresponsive += now.difference(last);
    _lastCountedTick = counting ? now : null;
    final stalled =
        counting &&
        _unresponsive >
            LiveQuoteSchedule.stallThreshold(
              _batchCount(pending),
              afterClose: afterClose,
            );
    if (stalled == _stalled) return;
    _stalled = stalled;
    if (!stalled) _failuresSinceStall = 0;
    _publish();
  }

  _Round _startRound(Map<String, String> due, bool afterClose, DateTime now) {
    final entries = due.entries.toList();
    final batches = [
      for (var i = 0; i < entries.length; i += ApiEndpoints.misBatchSize)
        Map.fromEntries(entries.skip(i).take(ApiEndpoints.misBatchSize)),
    ];
    _lastRoundStartedAt = now;
    // 限流後的試探只送第一批
    return _Round(
      _probing ? batches.sublist(0, 1) : batches,
      version: _registrationVersion,
      probe: _probing,
      afterClose: afterClose,
    );
  }

  /// 送一批;限流回 null
  Future<QuoteBatchReport?> _fetchBatch(
    Map<String, String> batch,
    _Round round,
  ) async {
    _inFlight = true;
    try {
      return await ref.read(liveQuoteClientProvider).fetchQuotesDetailed(batch);
    } on RateLimitException {
      return null;
    } catch (e, st) {
      round.unexpected ??= (error: e, stackTrace: st);
      return QuoteBatchReport(
        quotes: const {},
        errors: ['${e.runtimeType}: $e'],
        respondedSymbols: const <String>{},
        failedSymbols: batch.keys.toSet(),
      );
    } finally {
      _inFlight = false;
    }
  }

  void _finishRound(_Round round, DateTime now) {
    final outcome = _book.apply(
      round.report,
      requested: round.requested,
      now: now,
      afterClose: round.afterClose,
    );
    if (round.probe) {
      _probing = false;
      _rateLimitedUntil = null;
    }
    if (outcome == RoundOutcome.failed) {
      if (_stalled) _failuresSinceStall++;
      _noteFailure(round.firstError ?? '回應無效(rtcode、格式或沒有列)');
    } else {
      _lastRespondedAt = now;
      _unresponsive = Duration.zero;
      _stalled = false;
      _failuresSinceStall = 0;
      _noteRecovery();
    }
    final unexpected = round.unexpected;
    if (unexpected == null) {
      _unexpectedReported = false;
    } else {
      _reportUnexpected(unexpected);
    }
    _publish();
  }

  void _enterRateLimit(DateTime now) {
    _rateLimitedUntil = now.add(LiveQuoteParams.rateLimitPause);
    _probing = true;
    // 試探那一輪拿來比較的會是 5 分鐘前的價格
    _book.forgetLastRound();
    _noteFailure('證交所限流,暫停 ${LiveQuoteParams.rateLimitPause.inMinutes} 分鐘後試探');
    _publish();
  }

  // 斷線與限流是預期中的環境狀況、畫面已標示 → 只用 warning(release 只留
  // breadcrumb);一段連續失敗只記開始與恢復
  void _noteFailure(String reason) {
    _failStreak++;
    if (_failStreak == 1) AppLogger.warning(_tag, '即時報價中斷:$reason');
  }

  void _noteRecovery() {
    if (_failStreak > 0) {
      AppLogger.warning(_tag, '即時報價恢復(連續失敗 $_failStreak 輪)');
    }
    _failStreak = 0;
  }

  /// 非預期錯誤 → error 帶例外物件(送 Sentry);一段只送一次
  void _reportUnexpected(({Object error, StackTrace stackTrace}) u) {
    if (_unexpectedReported) return;
    _unexpectedReported = true;
    AppLogger.error(_tag, '即時報價非預期錯誤', u.error, u.stackTrace);
  }

  void _publish() {
    state = LiveQuoteState(
      entries: _book.entries,
      symbolStatus: _book.symbolStatus,
      stalled: _stalled,
      rateLimitedUntil: _rateLimitedUntil,
      lastRespondedAt: _lastRespondedAt,
      latestResponseHadToday: _book.latestResponseHadToday,
      latestQuoteTime: _book.latestQuoteTime,
    );
  }
}

/// 進行中的一輪:逐批送出,全部回來才套進記帳本
class _Round {
  _Round(
    this.batches, {
    required this.version,
    required this.probe,
    required this.afterClose,
  });

  List<Map<String, String>> batches;

  /// 開始時的登記版本
  final int version;
  final bool probe;
  final bool afterClose;

  /// 停拍時作廢:還在路上的請求回來後丟棄
  bool discarded = false;
  int _next = 0;

  /// 只留已送出的批次(之後 [isDone] 為 true、[requested] 只算這些)
  void truncate() => batches = batches.sublist(0, _next);
  final Map<String, IntradayQuote> _quotes = {};
  final List<String> _errors = [];
  final Set<String> _responded = {};
  final Set<String> _failed = {};
  ({Object error, StackTrace stackTrace})? unexpected;

  bool get isDone => _next >= batches.length;
  Map<String, String> nextBatch() => batches[_next++];
  List<String> get requested => [for (final b in batches) ...b.keys];
  String? get firstError => _errors.isEmpty ? null : _errors.first;

  void add(QuoteBatchReport r) {
    _quotes.addAll(r.quotes);
    _errors.addAll(r.errors);
    _responded.addAll(r.respondedSymbols);
    _failed.addAll(r.failedSymbols);
  }

  QuoteBatchReport get report => QuoteBatchReport(
    quotes: _quotes,
    errors: _errors,
    respondedSymbols: _responded,
    failedSymbols: _failed,
  );
}

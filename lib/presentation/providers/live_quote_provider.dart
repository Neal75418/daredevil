import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, visibleForTesting;
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
    this.fetchedAt = const {},
    this.lastReceivedAt = const {},
    this.stalled = false,
    this.rateLimitedUntil,
    this.lastRespondedAt,
    this.latestResponseHadToday,
    this.closingGivenUpAt = const {},
  });

  /// 各檔今天的即時報價(換日清空;顯示前一律經 `LiveQuoteMerge` 檢查日期)
  final Map<String, LiveQuoteEntry> entries;

  /// 各檔最近一次被請求的結果(卡片的「報價暫停」「無報價」)
  final Map<String, LiveSymbolStatus> symbolStatus;

  /// 各檔最近一次拿到今天報價的那一輪的套用時刻(換日清空);沒拿到過的檔
  /// 不在裡面。時刻取自報價中心的 `appClockProvider` 時鐘,是套用那一輪的
  /// 當下:不早於實際抓取,被截斷的一輪記截斷當下。所以拿來判斷「某個時刻
  /// 之後才抓到」會寬鬆,最多差一輪。其他畫面先抓到的報價也算
  final Map<String, DateTime> fetchedAt;

  /// 各檔最近一次拿到今天報價時,那一批回應收到的時刻;沒拿到過的檔不在
  /// 裡面。時刻取自報價中心的 `appClockProvider` 時鐘,是那一批回來的當下、
  /// 不是整輪套用的時刻。作廢的(計時器停掉、或 App 看不見而不能抓時還沒
  /// 套用的那一輪)或因限流丟掉的一輪不記;暫停交易(列被丟掉)、批次失敗的
  /// 那一檔停在上一次。頁首靠它分辨「證交所的資料停住」與「這一檔最近沒有
  /// 拿到報價」。報價中心換日時才發布清空的版本:計時器停著跨過午夜時,
  /// 重新計時的第一拍之前讀到的仍是前一天的
  final Map<String, DateTime> lastReceivedAt;

  /// 報價暫停(網路):計時中,距上一次有回應的一輪超過門檻
  final bool stalled;

  /// 報價暫停(證交所限流):到這個時刻後試探;試探完成前不清。排程已沒有
  /// 要抓的(例如收盤後都已有正式資料)或換日時為 null
  final DateTime? rateLimitedUntil;

  /// 上一次有回應的一輪(頁首「最後更新」)
  final DateTime? lastRespondedAt;

  /// 最近一次有回應的一輪有沒有今天的報價;還沒有回應為 null
  /// (頁首「證交所今天尚無報價」)
  final bool? latestResponseHadToday;

  /// 收盤後已放棄的代號 → 最後一次嘗試的套用時刻(取自報價中心的
  /// `appClockProvider`)。放棄＝「有回應但不是收盤報價」已滿
  /// [LiveQuoteParams.afterCloseMaxAttempts] 次、現在仍不是收盤報價(收盤
  /// 那一盤沒撮合);放棄後收盤後不再請求,時刻停在那一次。代號在收盤後的
  /// 嘗試達到上限的那一輪加入。報價中心換日時(一拍開始或一輪結束時發現
  /// 日期變了)才發布清空的版本:計時器停著跨過午夜時,重新計時的第一拍
  /// 之前讀到的仍是前一天的,使用端要用時刻的日期判斷是不是今天放棄的
  final Map<String, DateTime> closingGivenUpAt;
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
/// 畫面以 `LiveQuoteScope` 登記要看的股票;中心每秒一拍,在「有登記、這一拍
/// 可以抓、排程說該抓」時逐批發請求(任何 60 秒內 ≤ 8 個、相鄰 ≥ 2 秒、
/// 避開 CLI),結果經 [LiveQuoteBook] 算成各檔顯示價放進 state。只存在
/// 記憶體,不寫資料庫;任何錯誤都不影響盤後資料的顯示。
///
/// 「這一拍可以抓」:App 可見時都可以。App 看不見時,macOS 以外的平台停掉
/// 計時器;macOS 計時器照跑,只在收盤後、還有收盤報價沒收完、不在限流也
/// 沒有判為暫停時抓,把收盤報價收完(桌面的視窗常被別的 App 蓋住一整個
/// 下午)。斷線暫停或限流(不論是看不見之前還是之後開始的)就停到重新可見:
/// 沒人看得到暫停的提示,不重試到午夜。唯一的例外是看不見之前送出、下一拍
/// 之前就回來的那個請求:照常套用,有回應時暫停或限流因此解除、接著收。
///
/// 🚨 [register]／[unregister]／[setAppVisible] 會在 widget 的
/// didChangeDependencies／dispose(build 期間)被呼叫,**不可寫 state**
/// ——Riverpod 不允許 build 期間修改 provider。它們只改內部欄位與計時器,
/// 結果等下一拍才反映。
class LiveQuoteCenter extends Notifier<LiveQuoteState> {
  /// [collectAfterCloseWhenHidden]:App 看不見時要不要把收盤報價收完;不給就
  /// 只有 macOS 要。用 `defaultTargetPlatform` 而不是 `Platform.isMacOS`:
  /// 測試底下前者固定是 android,後者跟著跑測試的機器變
  LiveQuoteCenter({bool? collectAfterCloseWhenHidden})
    : _collectWhenHidden =
          collectAfterCloseWhenHidden ??
          defaultTargetPlatform == TargetPlatform.macOS;

  static const String _tag = 'LiveQuote';

  final bool _collectWhenHidden;

  /// 各 owner 登記的清單與登記那天的日期
  final Map<Object, ({List<LiveQuoteRegistration> entries, DateTime day})>
  _registrations = {};
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

  /// 上一拍的時刻(看不見時記拍子間隔用);計時器停著時為 null
  DateTime? _lastTickAt;

  /// 登記聯集的版本:一輪開始時記下,送下一批前不同就提早結束這一輪
  int _registrationVersion = 0;

  // 暫停計時:只在「排程要抓、這一拍可以抓、有登記」的相鄰拍子之間累計
  DateTime? _lastCountedTick;
  Duration _unresponsive = Duration.zero;
  bool _stalled = false;
  int _failuresSinceStall = 0;

  /// 排程還有沒有要抓的;沒有時(例如收盤後都已有正式資料)不對外顯示限流
  bool _pending = false;

  DateTime? _rateLimitedUntil;
  bool _probing = false;
  DateTime? _lastRespondedAt;

  // 紀錄去重:一段連續失敗只記開始與恢復;非預期錯誤一段只送一次
  int _failStreak = 0;
  bool _unexpectedReported = false;

  // 快照時刻的異常:每天各只記一次 warning。「偏前」會跟著證交所快取的
  // 年齡來回變(本機時鐘慢 X 秒時,快取放不到 X−60 秒的那幾輪才偏前);X 在
  // 60 秒到「60 秒＋快取存活期」之間時,逐段記會隨快取換新反覆記
  bool _missingSnapshotsNoted = false;
  bool _futureSnapshotsNoted = false;

  @override
  LiveQuoteState build() {
    ref.onDispose(_stopTicker);
    return const LiveQuoteState();
  }

  /// 登記 [owner] 要看的股票(同一 owner 再登記即取代)。等下一拍才抓。
  ///
  /// 連同今天的日期一起記:清單裡的「已有今天正式資料」只在登記那天算數
  /// (見 [_union])
  void register(Object owner, List<LiveQuoteRegistration> entries) {
    final day = _dayOf(_now());
    _changeRegistrations(
      () => _registrations[owner] = (
        entries: List.unmodifiable(entries),
        day: day,
      ),
    );
  }

  /// 不讀時鐘、不碰 `ref`:畫面 dispose 時呼叫
  void unregister(Object owner) {
    if (!_registrations.containsKey(owner)) return;
    _changeRegistrations(() => _registrations.remove(owner));
  }

  void _changeRegistrations(void Function() change) {
    // 比的是登記時的原樣(不看登記日):離開的代號與登記日無關;聯集有沒有變
    // 只決定進行中的一輪要不要截斷
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

  /// App 生命週期:resumed／inactive 可見,hidden／paused 不可見。看不見時
  /// macOS 以外的平台停掉計時器;macOS 計時器照跑,由每一拍判斷能不能抓
  /// (見 [_step])
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

  /// 計時器:有登記,而且 App 可見或這個平台看不見時也要收。看不見時計時器
  /// 照跑不等於照抓,能不能抓由每一拍判斷(見 [_step])
  void _syncTicker() {
    final shouldRun =
        (_appVisible || _collectWhenHidden) &&
        _registrations.values.any((r) => r.entries.isNotEmpty);
    if (shouldRun && _ticker == null) {
      _ticker = Timer.periodic(LiveQuoteParams.tick, (_) => unawaited(_tick()));
    } else if (!shouldRun && _ticker != null) {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickAt = null;
    _suspend();
  }

  /// 這段時間不抓(計時器停了,或看不見時這一拍不能抓)
  void _suspend() {
    // 不抓的期間不計暫停時間
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
    final lastTick = _lastTickAt;
    final sinceLastTick = lastTick == null ? null : now.difference(lastTick);
    _lastTickAt = now;
    if (_rollDay(now)) _publish();
    final phase = LiveQuoteSchedule.phaseAt(now);
    final afterClose = phase == MarketPhase.afterClose;
    final plan = _plan(phase, now);
    // App 看不見(只有看不見時也要收的平台會跑到這裡):只在收盤後還有收盤
    // 報價沒收完、不在限流中、也沒有判為暫停才抓;沒人看得到暫停的提示,
    // 不在這時重試。限流時刻要到試探那一輪結束才清掉,所以限流到期後也不
    // 試探。已判為暫停的不再重算:暫停門檻跟著階段與批數變(盤中至少 60 秒、
    // 收盤後至少 120 秒),重算可能讓看不見之前判的暫停在 13:30 自己解除
    if (!_appVisible &&
        !(afterClose &&
            plan.pending > 0 &&
            _rateLimitedUntil == null &&
            !_stalled)) {
      _suspend();
      return;
    }
    final until = _rateLimitedUntil;
    final rateLimited = until != null && now.isBefore(until);
    // 限流暫停期間不計網路暫停:頁首已顯示限流,兩者同時為真時畫面不知該說哪一個
    _countStall(
      now,
      pending: rateLimited ? 0 : plan.pending,
      afterClose: afterClose,
    );
    _setPending(plan.pending > 0);
    if (!_appVisible) {
      _noteHiddenTick(sinceLastTick, plan.pending, afterClose);
      // 這一拍才判為暫停:停到重新可見或午夜換日
      if (_stalled) {
        _suspend();
        return;
      }
    }

    if (_inFlight) return; // 上一個請求還沒回來:跳過,不疊加
    if (rateLimited) return;
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
    round.add(report, after);
    if (round.isDone) {
      _round = null;
      _finishRound(round, after);
    }
  }

  DateTime _now() => ref.read(appClockProvider).now();

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 這一拍的計畫:[due] 是若要開新的一輪該抓的代號 → 市場別(保持登記
  /// 順序);[pending] 是排程還要抓的檔數(暫停計時與門檻用)
  ({Map<String, String> due, int pending}) _plan(
    MarketPhase phase,
    DateTime now,
  ) {
    final union = _union(today: _dayOf(now));
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
  /// 收盤後就要抓。
  ///
  /// 給了 [today]:登記日不是 [today] 的清單,「已有今天正式資料」不算數
  /// (合併之前逐個 owner 套用)。畫面的清單在重建時才重算,App 看不見時
  /// 不重建;前一天登記的「已有」說的是前一天的資料,隔天收盤後照樣要抓。
  /// 沒給 [today]:登記時的原樣
  Map<String, LiveQuoteRegistration> _union({DateTime? today}) {
    final union = <String, LiveQuoteRegistration>{};
    for (final (:entries, :day) in _registrations.values) {
      final expired = today != null && day != today;
      for (final entry in entries) {
        final r = expired && entry.hasOfficialToday
            ? LiveQuoteRegistration(symbol: entry.symbol, market: entry.market)
            : entry;
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

  /// 換日(App 開著過夜):清掉記帳本與所有跟「今天」有關的狀態,回傳是否換了日。
  /// `_step` 與 `_finishRound` 都先呼叫——請求跨午夜時,回應可能比下一拍早到,
  /// 換日不能只靠 `_step`
  bool _rollDay(DateTime now) {
    if (!_book.rollDay(now)) return false;
    _unresponsive = Duration.zero;
    _lastCountedTick = null;
    _stalled = false;
    _failuresSinceStall = 0;
    _rateLimitedUntil = null;
    _probing = false;
    _lastRespondedAt = null;
    _missingSnapshotsNoted = false;
    _futureSnapshotsNoted = false;
    return true;
  }

  void _setPending(bool pending) {
    if (pending == _pending) return;
    _pending = pending;
    _publish();
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
    _rollDay(now);
    // 看不見時套用的輪次不閃色:閃色留在畫面那筆直到下一次套用,收完之後
    // 沒有下一輪,會留到切回來的第一幀才播,看起來像剛剛才變
    if (!_appVisible) _book.forgetLastRound();
    final outcome = _book.apply(
      round.report,
      requested: round.requested,
      now: now,
      afterClose: round.afterClose,
      receivedAt: round.receivedAt,
    );
    _noteSnapshots();
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

  /// 剛套用的那一輪的快照時刻:每輪記一行 debug(擋下幾檔是實機確認「價格
  /// 不倒退」有在作用的依據);整輪的報價都沒有可信的快照時刻、有快照時刻
  /// 偏前,各自每天只記一次 warning
  void _noteSnapshots() {
    final stats = _book.lastApplyStats;
    if (stats == null) return;
    final oldest = stats.oldestSnapshot;
    AppLogger.debug(
      _tag,
      '一輪結束:今天的報價 ${stats.applied} 檔、擋下 ${stats.rejected} 檔'
      '(快照比畫面舊)、沒有可信快照時刻 ${stats.missingSnapshots} 檔'
      '(其中偏前 ${stats.futureSnapshots} 檔)、'
      '換上的最舊快照 ${oldest == null ? '無' : _hms(oldest)}、'
      'App ${_appVisible ? '可見' : '看不見'}',
    );

    // 今天的報價都沒有可信的快照時刻,而且不是整輪都偏前。整輪都偏前的下面
    // 另外記,不該用掉這一條當天的那一次;沒有今天報價的一輪兩邊都是 0,後半
    // 不成立
    final allMissing =
        stats.missingSnapshots == stats.applied &&
        stats.futureSnapshots < stats.applied;
    if (allMissing && !_missingSnapshotsNoted) {
      _missingSnapshotsNoted = true;
      AppLogger.warning(
        _tag,
        '這一輪的報價都沒有可信的快照時刻(回應沒帶 queryTime、格式不符、時刻'
        '偏前或日期不是今天):價格不倒退的保護與報價延遲的提示沒有作用',
      );
    }
    if (stats.futureSnapshots > 0 && !_futureSnapshotsNoted) {
      _futureSnapshotsNoted = true;
      AppLogger.warning(
        _tag,
        '快照時刻偏前:${stats.futureSnapshots} 檔的快照時刻比收到的時刻晚超過 '
        '${LiveQuoteParams.snapshotFutureTolerance.inSeconds} 秒,當成沒有'
        '(多半是本機時鐘偏慢)',
      );
    }
  }

  /// App 看不見時可以抓的一拍:記拍子間隔與暫停計時。系統可能放慢看不見的
  /// App 的計時器;無回應時間從上一次有回應的一輪起跨拍累計(一輪的各批
  /// 之間、等 CLI 讓開的拍子都算),超過暫停門檻就判為暫停、停到重新可見,
  /// 所以拍子間隔比門檻短也可能累計到
  void _noteHiddenTick(Duration? sinceLastTick, int pending, bool afterClose) {
    final threshold = LiveQuoteSchedule.stallThreshold(
      _batchCount(pending),
      afterClose: afterClose,
    );
    AppLogger.debug(
      _tag,
      '看不見時的一拍:距上一拍 '
      '${sinceLastTick == null ? '無' : '${sinceLastTick.inMilliseconds} 毫秒'}、'
      '無回應 ${_unresponsive.inSeconds} 秒、'
      '暫停門檻 ${threshold.inSeconds} 秒'
      '${_stalled ? '、判為暫停,停到重新可見' : ''}',
    );
  }

  static String _hms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

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
      fetchedAt: _book.fetchedAt,
      lastReceivedAt: _book.lastReceivedAt,
      stalled: _stalled,
      rateLimitedUntil: _pending ? _rateLimitedUntil : null,
      lastRespondedAt: _lastRespondedAt,
      latestResponseHadToday: _book.latestResponseHadToday,
      closingGivenUpAt: _book.closingGivenUpAt,
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

  /// 開始不抓時作廢(見 `LiveQuoteCenter._suspend`):還在路上的請求回來後丟棄
  bool discarded = false;
  int _next = 0;

  /// 只留已送出的批次(之後 [isDone] 為 true、[requested] 只算這些)
  void truncate() => batches = batches.sublist(0, _next);
  final Map<String, IntradayQuote> _quotes = {};
  final List<String> _errors = [];
  final Set<String> _responded = {};
  final Set<String> _failed = {};

  /// 有報價的各代號 → 所在那一批回應收到的時刻
  final Map<String, DateTime> receivedAt = {};
  ({Object error, StackTrace stackTrace})? unexpected;

  bool get isDone => _next >= batches.length;
  Map<String, String> nextBatch() => batches[_next++];
  List<String> get requested => [for (final b in batches) ...b.keys];
  String? get firstError => _errors.isEmpty ? null : _errors.first;

  /// 加進一批的結果;[at] 是這一批回應收到的時刻
  void add(QuoteBatchReport r, DateTime at) {
    _quotes.addAll(r.quotes);
    for (final symbol in r.quotes.keys) {
      receivedAt[symbol] = at;
    }
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

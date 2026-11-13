import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';

enum LiveHeaderKind {
  pausedRateLimit,
  pausedNetwork,
  noQuotesToday,
  delayed,
  quoteTime,
  closingPending,
  lastQuote,
}

/// 頁首(自選)或價格下方(個股頁)的即時報價狀態
@immutable
class LiveHeaderStatus {
  const LiveHeaderStatus(this.kind, [this.time]);

  final LiveHeaderKind kind;

  /// 限流的再試時刻為 HH:MM,其餘為 HH:MM:SS(報價延遲是證交所資料停住的
  /// 那個快照時刻);沒有時間為 null
  final String? time;

  String text() {
    final t = time;
    return switch (kind) {
      LiveHeaderKind.pausedRateLimit => 'liveQuote.pausedRateLimit'.tr(
        namedArgs: {'time': t ?? ''},
      ),
      LiveHeaderKind.pausedNetwork =>
        t == null
            ? 'liveQuote.pausedNetworkNoTime'.tr()
            : 'liveQuote.pausedNetwork'.tr(namedArgs: {'time': t}),
      LiveHeaderKind.noQuotesToday => 'liveQuote.noQuotesToday'.tr(),
      LiveHeaderKind.delayed => 'liveQuote.delayed'.tr(
        namedArgs: {'time': t ?? ''},
      ),
      LiveHeaderKind.quoteTime => 'liveQuote.quoteTime'.tr(
        namedArgs: {'time': t ?? ''},
      ),
      LiveHeaderKind.closingPending => 'liveQuote.closingPending'.tr(),
      LiveHeaderKind.lastQuote => 'liveQuote.lastQuote'.tr(
        namedArgs: {'time': t ?? ''},
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is LiveHeaderStatus && other.kind == kind && other.time == time;

  @override
  int get hashCode => Object.hash(kind, time);

  @override
  String toString() => 'LiveHeaderStatus($kind, $time)';
}

enum LiveCardCaptionKind { paused, noQuote, lastQuote }

/// 卡片上的例外標示
@immutable
class LiveCardCaption {
  const LiveCardCaption(this.kind, [this.time]);

  final LiveCardCaptionKind kind;
  final String? time;

  String text() => switch (kind) {
    LiveCardCaptionKind.paused => 'liveQuote.cardPaused'.tr(),
    LiveCardCaptionKind.noQuote => 'liveQuote.cardNoQuote'.tr(),
    LiveCardCaptionKind.lastQuote => 'liveQuote.lastQuote'.tr(
      namedArgs: {'time': time ?? ''},
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is LiveCardCaption && other.kind == kind && other.time == time;

  @override
  int get hashCode => Object.hash(kind, time);

  @override
  String toString() => 'LiveCardCaption($kind, $time)';
}

/// 即時報價的頁首狀態與卡片標示規則(spec §7「共通」)
abstract final class LiveQuoteStatusRule {
  /// 頁首狀態,依序取第一個成立的:
  /// 0. 畫面上全部用今天的正式資料 → null(沒有即時數字可描述);
  /// 1. 報價暫停(限流優先於網路);
  /// 2. 證交所今天尚無報價(最近一輪有回應、但全部不是今天,且沒有卡片用今天
  ///    的即時報價或正式資料;第一輪回應前不顯示);
  /// 3. 報價延遲(只在盤中,見 [_delayedSnapshot]);
  /// 4. 有卡片用即時報價:盤中為 [intradayTime](沒給時取各卡片顯示的報價
  ///    時間裡最新的);收盤後全是收盤報價為「今日收盤」,否則「最後報價」取
  ///    最舊的那筆時間;
  /// 5. 都沒有 → null。
  static LiveHeaderStatus? header({
    required LiveQuoteState state,
    required Iterable<MergedPrice> merged,
    required String? intradayTime,
    required DateTime now,
  }) {
    final all = merged.toList();
    // 報價中心的狀態是全 App 共用的(例如別的畫面那檔暫停交易,讓最近一輪
    // 「尚無報價」),畫面上全部是今天的正式資料時不能拿來描述這個畫面
    if (all.isNotEmpty &&
        all.every((m) => m.kind == MergedPriceKind.official)) {
      return null;
    }
    final until = state.rateLimitedUntil;
    if (until != null) {
      return LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, hm(until));
    }
    if (state.stalled) {
      final at = state.lastRespondedAt;
      return LiveHeaderStatus(
        LiveHeaderKind.pausedNetwork,
        at == null ? null : hms(at),
      );
    }
    final live = [
      for (final m in all)
        if (m.kind == MergedPriceKind.live) m,
    ];
    // 只在沒有卡片顯示今天的價格(即時或正式資料)時才說「尚無報價」:收盤後
    // 逐檔抓,最近一輪可能只剩一檔(例如暫停交易、列被丟掉),其他卡片早已
    // 顯示今天的收盤
    final anyToday =
        live.isNotEmpty || all.any((m) => m.kind == MergedPriceKind.official);
    if (state.latestResponseHadToday == false && !anyToday) {
      return const LiveHeaderStatus(LiveHeaderKind.noQuotesToday);
    }
    if (live.isEmpty) return null;
    final delayedSnapshot = _delayedSnapshot(state, live, now);
    if (delayedSnapshot != null) {
      return LiveHeaderStatus(LiveHeaderKind.delayed, hms(delayedSnapshot));
    }
    if (live.any((m) => m.label == LiveQuoteLabel.quoteTime)) {
      return LiveHeaderStatus(
        LiveHeaderKind.quoteTime,
        intradayTime ?? _latest(live),
      );
    }
    final lastQuotes = [
      for (final m in live)
        if (m.label == LiveQuoteLabel.lastQuote) m,
    ];
    if (lastQuotes.isEmpty) {
      return const LiveHeaderStatus(LiveHeaderKind.closingPending);
    }
    return LiveHeaderStatus(LiveHeaderKind.lastQuote, _oldest(lastQuotes));
  }

  /// 這一頁用即時報價的卡片裡,最新的那一列時間(MIS 列的 `t`);沒有可用的
  /// 回 null。自選與熱力圖頁首的「報價時間」用它,不用全 App 共用的值:
  /// 證交所的快取每一組查詢各一份、各自落後,別的畫面剛抓到的時間可能比這
  /// 一頁的每一筆都新。快照時刻可信時,較舊的快照不會換上畫面,所以它不會
  /// 因為舊快照往回
  static String? latestRowTime(Iterable<MergedPrice> merged) {
    String? best;
    int? bestSeconds;
    for (final m in merged) {
      final rowTime = m.live?.rowTime;
      final seconds = LiveQuoteSchedule.secondsOfDay(rowTime);
      if (seconds == null) continue;
      if (bestSeconds == null || seconds > bestSeconds) {
        best = rowTime;
        bestSeconds = seconds;
      }
    }
    return best;
  }

  /// 證交所的資料停住時,回延遲最大的那張卡片的快照時刻;否則 null。
  ///
  /// 一張卡片的延遲＝最近一次收到今天報價的時刻－畫面那筆的快照時刻,超過
  /// [LiveQuoteParams.delayThreshold] 才算(證交所的快取平常就落後一兩分鐘)。
  /// 只看 [LiveQuoteParams.delayActiveWindow] 內收到過的卡片:更久沒收到的
  /// (剛重新進入畫面、App 從背景回來、暫停交易、批次失敗),手上的資料舊是
  /// 因為沒去抓或證交所沒給,不能說成證交所的資料停住。沒有快照時刻的卡片
  /// 無從判斷,略過。收盤後不判斷
  static DateTime? _delayedSnapshot(
    LiveQuoteState state,
    List<MergedPrice> live,
    DateTime now,
  ) {
    if (LiveQuoteSchedule.phaseAt(now) != MarketPhase.open) return null;
    DateTime? worstSnapshot;
    var worstDelay = LiveQuoteParams.delayThreshold;
    for (final m in live) {
      final entry = m.live;
      final snapshot = entry?.snapshotAt;
      final received = state.lastReceivedAt[entry?.symbol];
      if (snapshot == null || received == null) continue;
      if (now.difference(received) > LiveQuoteParams.delayActiveWindow) {
        continue;
      }
      final delay = received.difference(snapshot);
      if (delay > worstDelay) {
        worstDelay = delay;
        worstSnapshot = snapshot;
      }
    }
    return worstSnapshot;
  }

  /// 卡片例外標示:畫面已有今天的正式資料時不標;否則批次失敗 → 報價暫停、
  /// 有回應沒報價 → 無報價、收盤後不是收盤報價 → 最後報價 HH:MM:SS
  static LiveCardCaption? card({
    required LiveSymbolStatus? status,
    required MergedPrice merged,
  }) {
    if (merged.kind == MergedPriceKind.official) return null;
    switch (status) {
      case LiveSymbolStatus.batchFailed:
        return const LiveCardCaption(LiveCardCaptionKind.paused);
      case LiveSymbolStatus.noQuote:
        return const LiveCardCaption(LiveCardCaptionKind.noQuote);
      case LiveSymbolStatus.ok:
      case null:
        break;
    }
    if (merged.label == LiveQuoteLabel.lastQuote) {
      return LiveCardCaption(LiveCardCaptionKind.lastQuote, merged.quoteTime);
    }
    return null;
  }

  static String hms(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String? _latest(List<MergedPrice> ms) => _pick(ms, (a, b) => a > b);

  static String? _oldest(List<MergedPrice> ms) => _pick(ms, (a, b) => a < b);

  static String? _pick(List<MergedPrice> ms, bool Function(int, int) better) {
    String? best;
    int? bestSeconds;
    for (final m in ms) {
      final s = LiveQuoteSchedule.secondsOfDay(m.quoteTime);
      if (s == null) continue;
      if (bestSeconds == null || better(s, bestSeconds)) {
        best = m.quoteTime;
        bestSeconds = s;
      }
    }
    return best;
  }
}

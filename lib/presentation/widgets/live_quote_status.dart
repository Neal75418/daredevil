import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';

enum LiveHeaderKind {
  pausedRateLimit,
  pausedNetwork,
  noQuotesToday,
  quoteTime,
  closingPending,
  lastQuote,
}

/// 頁首(自選)或價格下方(個股頁)的即時報價狀態
@immutable
class LiveHeaderStatus {
  const LiveHeaderStatus(this.kind, [this.time]);

  final LiveHeaderKind kind;

  /// 限流的再試時刻為 HH:MM,其餘為 HH:MM:SS;沒有時間為 null
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
  /// 1. 報價暫停(限流優先於網路);
  /// 2. 證交所今天尚無報價(最近一輪有回應、但全部不是今天,且沒有卡片用今天
  ///    的即時報價;第一輪回應前不顯示);
  /// 3. 有卡片用即時報價:盤中為 [intradayTime];收盤後全是收盤報價為
  ///    「今日收盤」,否則「最後報價」取最舊的那筆時間;
  /// 4. 都沒有 → null。
  static LiveHeaderStatus? header({
    required LiveQuoteState state,
    required Iterable<MergedPrice> merged,
    required String? intradayTime,
  }) {
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
      for (final m in merged)
        if (m.kind == MergedPriceKind.live) m,
    ];
    // 只在沒有卡片用今天的即時報價時才說「尚無報價」:收盤後逐檔抓,最近一輪
    // 可能只剩一檔(例如暫停交易、列被丟掉),其他卡片早已顯示今天的收盤報價
    if (state.latestResponseHadToday == false && live.isEmpty) {
      return const LiveHeaderStatus(LiveHeaderKind.noQuotesToday);
    }
    if (live.isEmpty) return null;
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

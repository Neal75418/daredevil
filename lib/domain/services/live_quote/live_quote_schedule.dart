import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_session.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';

/// 交易階段(依台北時間與交易日曆)
enum MarketPhase { closed, preOpen, open, afterClose }

/// 盤中即時報價的排程規則(純函式,2026-10-06)。
///
/// 只回答「現在是什麼階段、多久抓一次、這個請求能不能發、這筆是不是收盤
/// 報價」;要抓哪些股票、何時發,由 `LiveQuoteCenter` 組合。
abstract final class LiveQuoteSchedule {
  static MarketPhase phaseAt(DateTime now) {
    if (!TaiwanCalendar.isTradingDay(now)) return MarketPhase.closed;
    final minutes = now.hour * 60 + now.minute;
    if (minutes < MarketSession.openMinutes) return MarketPhase.preOpen;
    if (minutes < MarketSession.closeMinutes) return MarketPhase.open;
    return MarketPhase.afterClose;
  }

  /// 一輪 [batchCount] 批時的輪詢間隔:平常 15 秒;批數 > 2 時拉長為
  /// 批數 × 7.5 秒,平均請求率維持每分鐘 8 次(瞬間的上限由
  /// [canSendRequest] 守住)
  static Duration pollInterval(int batchCount) {
    final spread = Duration(
      microseconds:
          Duration.microsecondsPerMinute *
          batchCount ~/
          LiveQuoteParams.maxRequestsPerMinute,
    );
    return spread > LiveQuoteParams.pollInterval
        ? spread
        : LiveQuoteParams.pollInterval;
  }

  /// 距上一次有回應的一輪超過多久視為暫停:max(60 秒, 2 × 輪詢間隔)。
  /// 收盤後每檔 1 分鐘才抓一次,間隔以 1 分鐘計,否則 CLI 避讓讓某次間隔
  /// 變成 69 秒時就會誤判暫停。
  static Duration stallThreshold(int batchCount, {bool afterClose = false}) {
    var interval = pollInterval(batchCount);
    if (afterClose && interval < LiveQuoteParams.afterCloseRetryInterval) {
      interval = LiveQuoteParams.afterCloseRetryInterval;
    }
    final twice = interval * 2;
    return twice > LiveQuoteParams.stallFloor
        ? twice
        : LiveQuoteParams.stallFloor;
  }

  /// 暫停後第 [failuresSinceStall] 次失敗之後的間隔:輪詢間隔逐次加倍,
  /// 最長 2 分鐘
  static Duration backoffInterval(int batchCount, int failuresSinceStall) {
    var interval = pollInterval(batchCount);
    for (
      var i = 0;
      i < failuresSinceStall && interval < LiveQuoteParams.maxBackoff;
      i++
    ) {
      interval *= 2;
    }
    return interval < LiveQuoteParams.maxBackoff
        ? interval
        : LiveQuoteParams.maxBackoff;
  }

  /// 盤中提醒 CLI 每 5 分鐘整點後 10 秒內不發請求(讓給 CLI)。CLI 只在
  /// 交易時段跑,收盤後照樣讓開:規則簡單,代價只是延後最多 10 秒。
  static bool inCliAvoidWindow(DateTime now) =>
      now.minute % LiveQuoteParams.cliEveryMinutes == 0 &&
      Duration(seconds: now.second, milliseconds: now.millisecond) <
          LiveQuoteParams.cliAvoidWindow;

  /// 現在能不能再發一個請求([recent] 是先前請求的送出時刻):窗口內少於
  /// 8 個,而且距上一個夠久。送出前都檢查,就保證任何 60 秒的窗口內不超過
  /// 8 個。
  ///
  /// 時刻只到整秒(見 [LiveQuoteParams.clockResolution]),紀錄上的差可能比
  /// 實際多將近 1 秒:間隔要紀錄上差 3 秒,實際才一定 ≥ 2 秒;窗口算到
  /// 紀錄上 61 秒,實際 60 秒內的才不會漏算。
  static bool canSendRequest(Iterable<DateTime> recent, DateTime now) {
    final minGap =
        LiveQuoteParams.minRequestGap + LiveQuoteParams.clockResolution;
    final window =
        LiveQuoteParams.requestWindow + LiveQuoteParams.clockResolution;
    var inWindow = 0;
    for (final t in recent) {
      final ago = now.difference(t);
      if (ago < minGap) return false;
      if (ago < window) inWindow++;
    }
    return inWindow < LiveQuoteParams.maxRequestsPerMinute;
  }

  /// 收盤報價:日期是今天、時間 ≥ 13:30:00、價格來自成交或鎖住。
  /// 不依賴非官方的 trade 物件。
  static bool isClosingQuote(IntradayQuote quote, DateTime today) {
    final date = quote.date;
    if (date == null || !DateContext.isSameDay(date, today)) return false;
    final seconds = secondsOfDay(quote.time);
    if (seconds == null || seconds < MarketSession.closeMinutes * 60) {
      return false;
    }
    return quote.priceSource == QuotePriceSource.trade ||
        quote.priceSource == QuotePriceSource.locked;
  }

  /// 收盤後這一檔是否還要抓:還沒拿到收盤報價,而且「有回應但不是收盤
  /// 報價」未滿 10 次
  static bool afterClosePending({
    required bool hasClosingQuote,
    required int attempts,
  }) => !hasClosingQuote && attempts < LiveQuoteParams.afterCloseMaxAttempts;

  /// 收盤後這一檔現在該不該抓:還要抓,而且距上次嘗試滿 1 分鐘
  static bool afterCloseDue({
    required bool hasClosingQuote,
    required int attempts,
    required DateTime? lastAttemptAt,
    required DateTime now,
  }) =>
      afterClosePending(hasClosingQuote: hasClosingQuote, attempts: attempts) &&
      (lastAttemptAt == null ||
          now.difference(lastAttemptAt) >=
              LiveQuoteParams.afterCloseRetryInterval);

  /// `HH:mm:ss` → 當天第幾秒;格式不符回 null
  static int? secondsOfDay(String? hms) {
    final parts = (hms ?? '').split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return h * 3600 + m * 60 + s;
  }
}

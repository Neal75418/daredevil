import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/data/database/app_database.dart';

/// v3 第零層的大盤油門（對象是加權指數）
enum ThrottleState {
  /// 守住 5 日門檻與月線
  full,

  /// 守住 5 日門檻、收在月線下
  reduced,

  /// 收破 5 日門檻
  flat,
}

/// 油門讀數
class ThrottleReading {
  const ThrottleReading({
    required this.state,
    required this.close,
    required this.ma20,
    required this.threshold,
    required this.lastBreakDate,
    required this.tradingDaysSinceBreak,
    required this.lookbackTradingDays,
  });

  final ThrottleState state;

  /// 資料日收盤
  final double close;

  /// 含資料日在內的 20 日收盤平均（月線）
  final double ma20;

  /// 5 日門檻：資料日之前 4 個交易日的收盤平均
  final double threshold;

  /// 讀到的歷史裡最近一次收破 5 日門檻的日子（含資料日）；沒有為 null。
  /// v3 的空手要等指數走完結構 C 才解除，App 不判斷解除，畫面寫出這個日子
  /// 讓使用者自己判斷空手是否仍有效。
  final DateTime? lastBreakDate;

  /// [lastBreakDate] 距資料日幾個交易日
  final int? tradingDaysSinceBreak;

  /// 查過收破與否的交易日數（前 4 筆沒有門檻可比，不算在內）
  final int lookbackTradingDays;
}

/// [taiex] 為升冪的加權指數；少於 21 筆回 null。不檢查最後一筆是不是資料日，
/// 由呼叫端判斷。
ThrottleReading? readThrottle(List<MarketIndexEntry> taiex) {
  const maPeriod = CloseSummaryParams.maPeriod;
  const thresholdDays = CloseSummaryParams.throttleThresholdDays;
  if (taiex.length < maPeriod + 1) return null;
  final closes = [for (final row in taiex) row.close];
  final last = closes.length - 1;

  double thresholdAt(int i) =>
      closes.sublist(i - thresholdDays, i).reduce((a, b) => a + b) /
      thresholdDays;

  final close = closes[last];
  final threshold = thresholdAt(last);
  final ma20 =
      closes.sublist(closes.length - maPeriod).reduce((a, b) => a + b) /
      maPeriod;
  final state = close < threshold
      ? ThrottleState.flat
      : close < ma20
      ? ThrottleState.reduced
      : ThrottleState.full;

  int? breakIndex;
  for (var i = last; i >= thresholdDays; i--) {
    if (closes[i] < thresholdAt(i)) {
      breakIndex = i;
      break;
    }
  }

  return ThrottleReading(
    state: state,
    close: close,
    ma20: ma20,
    threshold: threshold,
    lastBreakDate: breakIndex == null ? null : taiex[breakIndex].date,
    tradingDaysSinceBreak: breakIndex == null ? null : last - breakIndex,
    lookbackTradingDays: closes.length - thresholdDays,
  );
}

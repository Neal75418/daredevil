/// 收盤摘要的個股價格條件（v3 強者榜四條件、月線、結構 B／C、前提條件）。
///
/// 所有函式的 `bars` 都是升冪日線、最後一根是資料日，呼叫端已經切掉價格
/// 斷點之前的資料並去掉收盤為 null 的列。回看天數不夠的條件回
/// [CheckOutcome.insufficient]，一律當成未通過。
library;

import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/constants/tw_price_tick.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';

/// 一條條件的結果
enum CheckOutcome { pass, fail, insufficient }

/// v3 強者榜的四個入選條件
class StrongListCheck {
  const StrongListCheck({
    required this.ret20,
    required this.limitUpIn20,
    required this.avgVolume20,
    required this.aboveMa20,
  });

  /// 20 日漲幅 > `SectorParams.rotationStrongListRet20Pct`
  final CheckOutcome ret20;

  /// 近 20 根有一根漲停
  final CheckOutcome limitUpIn20;

  /// 20 日均量 > `SectorParams.rotationStrongListDailyVolumeShares`
  final CheckOutcome avgVolume20;

  /// 收盤在 20 日均線之上
  final CheckOutcome aboveMa20;

  List<CheckOutcome> get _all => [ret20, limitUpIn20, avgVolume20, aboveMa20];

  /// 通過的條數
  int get passed => _all.where((o) => o == CheckOutcome.pass).length;

  bool get allPassed => passed == _all.length;
}

/// 強者榜四條件；少於 21 根時四條都是資料不足
StrongListCheck checkStrongList(List<DailyPriceEntry> bars) {
  if (bars.length < CloseSummaryParams.maPeriod + 1) {
    return const StrongListCheck(
      ret20: CheckOutcome.insufficient,
      limitUpIn20: CheckOutcome.insufficient,
      avgVolume20: CheckOutcome.insufficient,
      aboveMa20: CheckOutcome.insufficient,
    );
  }
  final ret = PriceCalculator.ret20d(bars);
  final window = bars.sublist(bars.length - CloseSummaryParams.maPeriod);

  var limitUp = false;
  for (var i = bars.length - window.length; i < bars.length; i++) {
    if (closeLimitStatus(bars, i).isUp) {
      limitUp = true;
      break;
    }
  }

  final volumes = [for (final b in window) b.volume];
  final CheckOutcome avgVolume;
  if (volumes.contains(null)) {
    avgVolume = CheckOutcome.insufficient;
  } else {
    final avg = volumes.fold<double>(0, (s, v) => s + v!) / volumes.length;
    avgVolume = _outcome(
      avg > SectorParams.rotationStrongListDailyVolumeShares,
    );
  }

  final ma20 = _maAt(bars, CloseSummaryParams.maPeriod, bars.length - 1);
  return StrongListCheck(
    ret20: ret == null
        ? CheckOutcome.insufficient
        : _outcome(ret > SectorParams.rotationStrongListRet20Pct),
    limitUpIn20: _outcome(limitUp),
    avgVolume20: avgVolume,
    aboveMa20: ma20 == null
        ? CheckOutcome.insufficient
        : _outcome(bars.last.close! > ma20),
  );
}

/// 第 [index] 根收盤的漲跌停狀態：以平盤價（[DailyPriceEntry.basePrice]，
/// 沒有時用收盤 − 漲跌）依升降單位算出漲跌停價再比對收盤。算不出平盤價、
/// 或 ETF（00 開頭，升降單位不同）時退回用漲跌幅推算。
PriceLimitStatus closeLimitStatus(List<DailyPriceEntry> bars, int index) {
  final bar = bars[index];
  final pct = PriceCalculator.calculatePriceChange(
    bars.sublist(0, index + 1),
    bar,
  );
  final close = bar.close;
  final change = bar.priceChange;
  final base =
      bar.basePrice ??
      (close == null || change == null ? null : close - change);
  if (close == null ||
      base == null ||
      base <= 0 ||
      bar.symbol.startsWith('00')) {
    return PriceLimit.statusOf(changePercent: pct);
  }
  final limits = TwPriceTick.limitPrices(base);
  return PriceLimit.statusOf(
    changePercent: pct,
    price: close,
    limitUp: limits.up,
    limitDown: limits.down,
  );
}

/// 從資料日往回數，連續收在當日 20 日均線同一側的天數：之上（含等於）為正、
/// 之下為負；資料不足回 0
int maSideStreak(List<DailyPriceEntry> bars) {
  final mas = _smaSeries(bars, CloseSummaryParams.maPeriod);
  final last = bars.length - 1;
  final lastMa = last < 0 ? null : mas[last];
  if (lastMa == null) return 0;
  final above = bars[last].close! >= lastMa;
  var count = 0;
  for (var i = last; i >= 0; i--) {
    final ma = mas[i];
    if (ma == null || (bars[i].close! >= ma) != above) break;
    count++;
  }
  return above ? count : -count;
}

/// 資料日收在 20 日均線下、前一日收在均線上（含等於）
bool crossedBelowMa(List<DailyPriceEntry> bars) {
  final mas = _smaSeries(bars, CloseSummaryParams.maPeriod);
  final last = bars.length - 1;
  if (last < 1) return false;
  final maLast = mas[last];
  final maPrev = mas[last - 1];
  if (maLast == null || maPrev == null) return false;
  return bars[last].close! < maLast && bars[last - 1].close! >= maPrev;
}

/// 結構 B（強勢回測）成立時回支撐均線週期（取最短的），否則回 null
int? structureBSupport(List<DailyPriceEntry> bars) {
  final ret = PriceCalculator.ret20d(bars);
  if (ret == null || ret <= 0) return null;
  final last = bars.length - 1;
  final close = bars[last].close!;
  final trendMa = _maAt(bars, CloseSummaryParams.structureBTrendMaPeriod, last);
  if (trendMa == null || close <= trendMa) return null;
  final low = bars[last].low ?? close;
  for (final period in CloseSummaryParams.structureBSupportPeriods) {
    final support = _maAt(bars, period, last);
    if (support == null) continue;
    if (low <= support * CloseSummaryParams.structureBTouchRatio &&
        close >= support * CloseSummaryParams.structureBHoldRatio) {
      return period;
    }
  }
  return null;
}

/// 結構 C（突破）：資料日收盤高於之前 20 根的最高價
bool structureC(List<DailyPriceEntry> bars) {
  const lookback = CloseSummaryParams.structureCLookbackDays;
  if (bars.length < lookback + 1) return false;
  final prior = bars.sublist(bars.length - 1 - lookback, bars.length - 1);
  final highest = prior
      .map((b) => b.high ?? b.close!)
      .reduce((a, b) => a > b ? a : b);
  return bars.last.close! > highest;
}

/// v3 第 2 層的前提條件
class EntryPrerequisites {
  const EntryPrerequisites({
    required this.moving,
    required this.bias,
    required this.revenue,
    required this.dayVolume,
    required this.biasPct,
  });

  /// 會動：60 日漲幅 > 0
  final CheckOutcome moving;

  /// 月線乖離 < `CloseSummaryParams.maxBiasPct`
  final CheckOutcome bias;

  /// 營收年增近 3 月平均 > `CloseSummaryParams.minRevenueYoy3mPct`
  final CheckOutcome revenue;

  /// 資料日成交量 > `CloseSummaryParams.minDayVolumeShares`
  final CheckOutcome dayVolume;

  /// 月線乖離（%）；20 日均線算不出來時為 null
  final double? biasPct;

  bool get allPassed =>
      [moving, bias, revenue, dayVolume].every((o) => o == CheckOutcome.pass);
}

/// 前提條件；[revenueYoy3m] 為營收年增近 3 月平均（%），沒有資料傳 null
EntryPrerequisites checkEntryPrerequisites(
  List<DailyPriceEntry> bars, {
  required double? revenueYoy3m,
}) {
  final ret60 = PriceCalculator.ret60d(bars);
  final ma20 = bars.isEmpty
      ? null
      : _maAt(bars, CloseSummaryParams.maPeriod, bars.length - 1);
  final biasPct = ma20 == null || ma20 == 0
      ? null
      : (bars.last.close! - ma20) / ma20 * 100;
  final volume = bars.isEmpty ? null : bars.last.volume;
  return EntryPrerequisites(
    moving: ret60 == null ? CheckOutcome.insufficient : _outcome(ret60 > 0),
    bias: biasPct == null
        ? CheckOutcome.insufficient
        : _outcome(biasPct < CloseSummaryParams.maxBiasPct),
    revenue: revenueYoy3m == null
        ? CheckOutcome.insufficient
        : _outcome(revenueYoy3m > CloseSummaryParams.minRevenueYoy3mPct),
    dayVolume: volume == null
        ? CheckOutcome.insufficient
        : _outcome(volume > CloseSummaryParams.minDayVolumeShares),
    biasPct: biasPct,
  );
}

CheckOutcome _outcome(bool passed) =>
    passed ? CheckOutcome.pass : CheckOutcome.fail;

List<double?> _smaSeries(List<DailyPriceEntry> bars, int period) =>
    TechnicalIndicatorService().calculateSMA([
      for (final b in bars) b.close!,
    ], period);

/// 第 [index] 根的 [period] 日收盤均線；不足回 null
double? _maAt(List<DailyPriceEntry> bars, int period, int index) {
  if (index < period - 1) return null;
  final series = _smaSeries(bars.sublist(0, index + 1), period);
  return series.isEmpty ? null : series.last;
}

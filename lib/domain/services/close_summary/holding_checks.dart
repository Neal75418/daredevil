/// 收盤摘要的持股條件：成本守門價（v3.3 §4.1 的守門價，以成本為基準）與
/// 「8 日未達 +1R」（v3.3 的時間停損）。
///
/// 成本守門價＝平均成本 − k × ATR(n)，k、n 與個股頁的守門價提醒同一組
/// （`AlertParams`），ATR 的算法也同一支（`AlertTargetCalculator.simpleAtr`），
/// 以進場日為最後一天計算後固定不動（v3.4：+1R 不移到成本）。
library;

import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/constants/transaction_types.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert/alert_target_calculator.dart';

/// 「8 日未達 +1R」的狀態
enum TimeStopState {
  /// 還在 8 個交易日內、收盤還沒到過 +1R
  running,

  /// 8 個交易日內收盤到過 +1R
  lifted,

  /// 滿 8 個交易日，收盤都沒到過 +1R
  expired,
}

/// 一筆持股在資料日的狀態
class HoldingCheck {
  const HoldingCheck({
    required this.entryDate,
    required this.quantity,
    required this.avgCost,
    required this.stopPrice,
    required this.oneR,
    required this.tradingDaysHeld,
    required this.timeStop,
    required this.closePrice,
    required this.unrealizedPnl,
    required this.unrealizedPct,
  });

  /// 目前這段持有第一筆買進的日期
  final DateTime entryDate;

  final double quantity;
  final double avgCost;

  /// 成本守門價；進場日（含）以前不足 ATR 需要的根數、或進場日晚於資料日
  /// （當天的盤後資料還沒寫入）時為 null
  final double? stopPrice;

  /// 1R＝平均成本 − 成本守門價
  final double? oneR;

  /// 進場日之後到資料日的交易日數（不含進場日；進場當天、或進場日晚於資料日
  /// 時為 0）；進場日早於讀到的第一根日線時數不出來，為 null
  final int? tradingDaysHeld;

  /// [stopPrice] 為 null 時為 null
  final TimeStopState? timeStop;

  /// 資料日收盤
  final double closePrice;

  final double unrealizedPnl;

  /// 未實現損益（%）
  final double unrealizedPct;

  /// 資料日收盤低於成本守門價
  bool get stopBroken => stopPrice != null && closePrice < stopPrice!;
}

/// 目前這段持有（買進、賣出累計數量最後一次歸零之後）第一筆買進的日期。
/// 沒有買進、或買進的股數已經賣光時回 null。這時就算持股數還大於 0，剩下
/// 的通常是股票股利配來、成本為 0 的那批，不算成本守門價。
///
/// 只累計買進與賣出：股票股利配來的股數可以一起賣掉，所以賣出可能超過
/// 買進的合計，累計到 0 以下就當成 0。
DateTime? holdingEntryDate(List<PortfolioTransactionEntry> transactions) {
  final sorted = [...transactions]
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  var held = 0.0;
  DateTime? entry;
  for (final tx in sorted) {
    switch (tx.txType) {
      case TransactionTypes.buy:
        if (held <= 0) entry = DateContext.normalize(tx.date);
        held += tx.quantity;
      case TransactionTypes.sell:
        held -= tx.quantity;
        if (held <= 0) {
          held = 0;
          entry = null;
        }
    }
  }
  return held > 0 ? entry : null;
}

/// [bars] 為升冪日線、最後一根是資料日，要涵蓋進場日之前 ATR 需要的根數。
/// 沒有買進或資料日沒有收盤時回 null。持股列可能數量大於 0、這裡卻回 null
/// （只剩股票股利配來的股數），呼叫端要能處理。
HoldingCheck? checkHolding({
  required PortfolioPositionEntry position,
  required List<PortfolioTransactionEntry> transactions,
  required List<DailyPriceEntry> bars,
}) {
  final entryDate = holdingEntryDate(transactions);
  final close = bars.isEmpty ? null : bars.last.close;
  if (entryDate == null || close == null) return null;

  // 進場日晚於資料日：進場那根還沒寫入，成本守門價與時間都等它寫入再算
  final entryAfterData = entryDate.isAfter(
    DateContext.normalize(bars.last.date),
  );
  // 進場日那根（進場日不是交易日時取之前最後一根）
  final entryIndex = bars.lastIndexWhere(
    (b) => !DateContext.normalize(b.date).isAfter(entryDate),
  );
  final afterEntry = bars.sublist(entryIndex + 1);

  final atr = entryIndex < 0 || entryAfterData
      ? null
      : AlertTargetCalculator.simpleAtr(
          AlertTargetCalculator.ohlcFrom(bars.sublist(0, entryIndex + 1)),
          AlertParams.stopGateAtrPeriod,
        );
  final avgCost = position.avgCost;
  final stopPrice = atr == null
      ? null
      : avgCost - AlertParams.stopGateAtrMultiple * atr;
  final oneR = stopPrice == null ? null : avgCost - stopPrice;

  TimeStopState? timeStop;
  if (oneR != null) {
    final window = afterEntry.take(CloseSummaryParams.timeStopTradingDays);
    if (window.any((b) => (b.close ?? 0) >= avgCost + oneR)) {
      timeStop = TimeStopState.lifted;
    } else if (afterEntry.length >= CloseSummaryParams.timeStopTradingDays) {
      timeStop = TimeStopState.expired;
    } else {
      timeStop = TimeStopState.running;
    }
  }

  return HoldingCheck(
    entryDate: entryDate,
    quantity: position.quantity,
    avgCost: avgCost,
    stopPrice: stopPrice,
    oneR: oneR,
    tradingDaysHeld: entryAfterData
        ? 0
        : entryIndex < 0
        ? null
        : afterEntry.length,
    timeStop: timeStop,
    closePrice: close,
    unrealizedPnl: (close - avgCost) * position.quantity,
    unrealizedPct: avgCost == 0 ? 0 : (close / avgCost - 1) * 100,
  );
}

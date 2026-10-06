import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 今日損益(以昨收計)的計算結果
@immutable
class TodayPnl {
  const TodayPnl({
    required this.amount,
    required this.missingCount,
    required this.includesNonClosing,
  });

  /// 已計入的持股:股數 ×(顯示價 − 昨收)之和
  final double amount;

  /// 沒有今天有效價格(或推不回昨收)而未計入的在倉持股數
  final int missingCount;

  /// 收盤後有持股用的是非收盤的「最後報價」
  final bool includesNonClosing;
}

/// 今日損益(以昨收計)的規則(spec §7「今日損益」,純函式)
abstract final class TodayPnlRule {
  /// 依各持股的合併結果計算今日損益;非交易日、盤前或沒有在倉持股時回
  /// null(不顯示)。
  ///
  /// - 用即時報價:昨收 = MIS 的昨收;
  /// - 用今天的正式資料:昨收 = 收盤 − 交易所漲跌價差(除權息日即為參考價);
  /// - 沒有今天的價格(合併結果退回原本的資料)或推不回昨收:不當 0、不默默
  ///   略過,計入 [TodayPnl.missingCount]。
  static TodayPnl? compute(
    Iterable<({double quantity, MergedPrice merged})> holdings, {
    required MarketPhase phase,
  }) {
    if (phase == MarketPhase.closed || phase == MarketPhase.preOpen) {
      return null;
    }
    var amount = 0.0;
    var missing = 0;
    var nonClosing = false;
    var held = false;
    for (final (:quantity, :merged) in holdings) {
      if (quantity <= 0) continue;
      held = true;
      final price = merged.price;
      final previous = merged.previousClose;
      if (merged.kind == MergedPriceKind.fallback ||
          price == null ||
          previous == null) {
        missing++;
        continue;
      }
      amount += quantity * (price - previous);
      if (merged.label == LiveQuoteLabel.lastQuote) nonClosing = true;
    }
    if (!held) return null;
    return TodayPnl(
      amount: amount,
      missingCount: missing,
      includesNonClosing: nonClosing,
    );
  }
}
